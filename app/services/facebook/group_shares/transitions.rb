# frozen_string_literal: true

module Facebook
  module GroupShares
    # Các thao tác trên một lượt chia sẻ. Người dùng tự đăng trong nhóm rồi
    # đánh dấu kết quả ở đây; mọi thay đổi đều ghi audit và đồng bộ lời nhắc.
    module Transitions
      module_function

      # pending → posted | rejected | skipped
      def complete(share, user:, status:, group_post_url: nil, note: nil)
        status = status.to_s
        raise ArgumentError, I18n.t("marketingos.facebook_groups.errors.bad_status") unless FacebookGroupShare::DONE_STATUSES.include?(status)

        share.with_lock do
          raise Facebook::StateError, I18n.t("marketingos.facebook_groups.errors.not_pending") unless share.pending?

          share.update!(status: status, completed_at: Time.current, completed_by: user,
                        group_post_url: (group_post_url.to_s.strip.presence if status == "posted"),
                        note: note.to_s.strip.presence)
        end
        Reminders.cancel(share)
        audit(share, status, user, "group_post_url" => share.group_post_url, "note" => share.note)
        share
      end

      # posted | rejected | skipped → pending (bấm nhầm, hoặc admin nhóm duyệt lại).
      def reopen(share, user:)
        share.with_lock do
          raise Facebook::StateError, I18n.t("marketingos.facebook_groups.errors.not_done") unless share.done?

          share.update!(status: "pending", completed_at: nil, completed_by: nil)
        end
        Reminders.schedule(share) if share.scheduled_at > Time.current
        audit(share, "reopened", user)
        share
      end

      # Đổi giờ hẹn và/hoặc người phụ trách, sửa nội dung riêng cho nhóm.
      def update(share, user:, scheduled_at: nil, assignee_id: nil, message: nil)
        raise Facebook::StateError, I18n.t("marketingos.facebook_groups.errors.not_pending") unless share.pending?

        attrs = {}
        if scheduled_at.present?
          at = Facebook::Posts::Scheduling.parse_local(scheduled_at, share.timezone)
          raise ArgumentError, I18n.t("marketingos.facebook_groups.errors.start_in_past") if at < Time.current - 1.minute

          attrs[:scheduled_at] = at
        end
        if assignee_id.present?
          assignee = FacebookGroupShare.assignable_users(share.organization).find_by(id: assignee_id)
          raise ArgumentError, I18n.t("marketingos.facebook_groups.errors.bad_assignee") if assignee.nil?

          attrs[:assignee] = assignee
        end
        unless message.nil?
          text = message.to_s.strip
          attrs[:message] = text.presence
          attrs[:ai_variant] = false if text != share.message.to_s.strip
        end
        return share if attrs.empty?

        share.update!(attrs)
        Reminders.schedule(share)
        audit(share, "updated", user, "changed" => attrs.keys.map(&:to_s))
        share
      end

      def remove(share, user:)
        raise Facebook::StateError, I18n.t("marketingos.facebook_groups.errors.not_pending") unless share.pending?

        Reminders.cancel(share)
        audit(share, "removed", user)
        share.destroy!
      end

      def audit(share, action, user, details = {})
        AuditLog.record!(org: share.organization, user: user, action: "facebook.group_share.#{action}", subject: share,
                         details: { "facebook_post_id" => share.facebook_post_id, "group_id" => share.facebook_group_id,
                                    "group" => share.facebook_group.name }.merge(details.compact))
      end
    end
  end
end
