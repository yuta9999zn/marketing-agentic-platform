# frozen_string_literal: true

module Facebook
  module Posts
    # Các hành động nghiệp vụ trên bài đăng. Mỗi hành động: khoá dòng, kiểm tra
    # trạng thái, ghi audit. Không hành động nào nhảy thẳng tới publishing.
    class Transitions
      class << self
        # draft → pending_approval. Auto-publish chỉ khi Page VÀ campaign bật rõ ràng.
        def submit(post, user:)
          post.with_lock do
            raise Facebook::StateError, "Chỉ bản nháp mới gửi duyệt được." unless post.draft?

            issues = Validate.call(post) - [ :connection_not_connected, :missing_scopes, :unconfigured, :token_missing, :connection_disconnected ]
            raise Facebook::ValidationError, issues if issues.any?

            post.update!(status: "pending_approval", submitted_at: Time.current, rejection_note: nil, rejected_at: nil)
            Audit.record(post, "submitted", user: user)
          end

          if auto_publish?(post)
            approve(post, user: nil, source: "auto_publish")
          else
            Audit.notify_approvers(post, "facebook_post_pending_approval", except_user: user)
          end
          post
        end

        # pending_approval → approved (→ scheduled nếu đã có giờ đăng).
        def approve(post, user:, source: "human", note: nil)
          post.with_lock do
            raise Facebook::StateError, "Bài không ở trạng thái chờ duyệt." unless post.pending_approval?

            post.update!(status: "approved", approved_by: user, approved_at: Time.current, approval_source: source)
            Audit.record(post, "approved", user: user, details: { "source" => source, "note" => note }.compact)
          end
          Audit.notify(post, "facebook_post_approved", user: post.created_by) if post.created_by && post.created_by != user

          if post.scheduled_at.present? || source == "auto_publish"
            schedule(post, user: user, at: post.scheduled_at || Time.current, timezone: post.timezone, publish_now: post.scheduled_at.blank?)
          end
          post
        end

        # pending_approval → draft kèm lý do.
        def reject(post, user:, note:)
          post.with_lock do
            raise Facebook::StateError, "Bài không ở trạng thái chờ duyệt." unless post.pending_approval?

            post.update!(status: "draft", rejection_note: note.presence, rejected_at: Time.current)
            Audit.record(post, "rejected", user: user, details: { "note" => note })
          end
          Audit.notify(post, "facebook_post_rejected", user: post.created_by, payload: { "note" => note.to_s }) if post.created_by
          post
        end

        # approved/scheduled → scheduled tại `at` (giờ địa phương theo timezone, hoặc Time).
        def schedule(post, user:, at:, timezone:, publish_now: false)
          run_at = Scheduling.parse_local(at, timezone)
          raise ArgumentError, "Thời điểm đăng phải ở tương lai." if !publish_now && run_at < Time.current - 1.minute

          post.with_lock do
            raise Facebook::StateError, "Chỉ bài đã duyệt mới lên lịch được." unless post.schedulable?

            post.rotate_schedule_token!
            post.update!(status: "scheduled", scheduled_at: run_at, timezone: timezone, attempts: 0,
                         next_attempt_at: nil, last_error: nil, last_error_code: nil, error_kind: nil)
            Audit.record(post, publish_now ? "publish_now" : "scheduled", user: user,
                         details: { "scheduled_at" => run_at.utc.iso8601, "timezone" => timezone })
          end
          Scheduling.enqueue(post)
          post
        end

        # scheduled → approved (bỏ lịch, giữ duyệt).
        def unschedule(post, user:)
          post.with_lock do
            raise Facebook::StateError, "Bài không đang lên lịch." unless post.scheduled?

            post.rotate_schedule_token!
            post.update!(status: "approved", next_attempt_at: nil)
            Audit.record(post, "unscheduled", user: user)
          end
          post
        end

        def cancel(post, user:, note: nil)
          post.with_lock do
            raise Facebook::StateError, "Không huỷ được bài ở trạng thái #{post.status}." unless post.cancellable?

            post.rotate_schedule_token!
            post.update!(status: "cancelled", cancelled_at: Time.current, next_attempt_at: nil)
            Audit.record(post, "cancelled", user: user, details: { "note" => note }.compact)
          end
          post
        end

        def reopen(post, user:)
          post.with_lock do
            raise Facebook::StateError, "Chỉ bài đã huỷ mới mở lại được." unless post.cancelled?

            post.update!(status: "draft", cancelled_at: nil, approved_at: nil, approved_by: nil, approval_source: nil)
            Audit.record(post, "reopened", user: user)
          end
          post
        end

        # failed → scheduled (ngay). Bài "không rõ đã đăng hay chưa" cần confirm thủ công.
        def retry(post, user:, confirm_unknown: false)
          post.with_lock do
            raise Facebook::StateError, "Chỉ bài thất bại mới thử lại được." unless post.retryable?
            if post.needs_manual_check? && !confirm_unknown
              raise Facebook::StateError, "Lần đăng trước không xác định được kết quả. Hãy kiểm tra Page trước rồi xác nhận thử lại."
            end
            unless post.facebook_page_connection.publishable?
              raise Facebook::StateError, "Page chưa sẵn sàng đăng (#{post.facebook_page_connection.blocked_reason}). Kiểm tra kết nối trước."
            end

            post.rotate_schedule_token!
            post.update!(status: "scheduled", scheduled_at: Time.current, attempts: 0, next_attempt_at: nil,
                         last_error: nil, last_error_code: nil, error_kind: nil, publish_started_at: nil)
            Audit.record(post, "retried", user: user)
          end
          Scheduling.enqueue(post)
          post
        end

        # Sửa nội dung → mọi phê duyệt trước đó mất hiệu lực, bài về draft.
        def update_content(post, user:, attrs:, image: nil, remove_image: false)
          post.with_lock do
            raise Facebook::StateError, "Không sửa được bài ở trạng thái #{post.status}." unless post.editable?

            before = post.attributes.slice(*FacebookPost::CONTENT_ATTRS)
            post.assign_attributes(attrs.slice(:title, :message, :link, :post_type))
            if attrs.key?(:scheduled_at)
              tz = attrs[:timezone].presence || post.timezone
              post.timezone = tz
              post.scheduled_at = attrs[:scheduled_at].present? ? Scheduling.parse_local(attrs[:scheduled_at], tz) : nil
            end
            post.image.purge_later if remove_image && post.image.attached?
            post.image.attach(image) if image.present?
            post.post_type = "photo" if image.present? && post.post_type == "text"
            post.post_type = "text" if remove_image && post.post_type == "photo" && image.blank?

            content_changed = before != post.attributes.slice(*FacebookPost::CONTENT_ATTRS) || image.present? || remove_image
            if content_changed && !post.draft?
              post.rotate_schedule_token!
              post.status = "draft"
              post.approved_at = nil
              post.approved_by = nil
              post.approval_source = nil
              post.next_attempt_at = nil
            end
            post.save!
            Audit.record(post, "edited", user: user,
                         details: { "changed" => (before.keys.select { |k| before[k] != post[k] } + (image.present? ? [ "image" ] : [])),
                                    "approval_reset" => content_changed })
          end
          post
        end

        private

        def auto_publish?(post)
          post.facebook_page_connection.auto_publish_enabled? && post.campaign&.facebook_auto_publish?
        end
      end
    end
  end
end
