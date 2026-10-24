# frozen_string_literal: true

module Facebook
  module Posts
    # Đăng MỘT bài lên Page. Đây là nơi duy nhất gọi endpoint publish của Meta.
    #
    # Bất biến:
    # - Chỉ bài `scheduled` (đã qua approved) mới được đăng; schedule_token phải khớp
    #   (job cũ sau khi đổi lịch/huỷ sẽ tự bỏ qua).
    # - Chuyển sang `publishing` trong khoá DB trước khi gọi API → hai job trùng
    #   không thể cùng đăng (idempotency).
    # - Chỉ đánh dấu `published` khi Meta trả về ID bài. Permalink là best-effort.
    # - Lỗi tạm thời → backoff có giới hạn; lỗi quyền/token/validation/policy → failed ngay.
    class Publish
      Result = Struct.new(:outcome, :post, :error, keyword_init: true)
      STUCK_AFTER = 10.minutes

      def self.call(post:, schedule_token: nil, client: nil)
        new(post, schedule_token, client).call
      end

      def initialize(post, schedule_token, client)
        @post = post
        @token = schedule_token
        @client = client
      end

      def call
        claimed = claim!
        return claimed unless claimed.outcome == :claimed

        attempt = @post.facebook_publish_attempts.create!(attempt_number: @post.attempts, outcome: "started",
                                                          started_at: Time.current, mock: client.mock?)
        begin
          remote = Publisher.new(@post, client).publish
          mark_published!(remote, attempt)
          Result.new(outcome: :published, post: @post)
        rescue Facebook::ApiError, Facebook::NetworkError => e
          handle_failure(e, attempt)
        rescue Facebook::ConfigurationError => e
          fail_permanently!(attempt, code: "configuration", message: e.message, kind: "permanent")
        rescue StandardError => e
          # Bug nội bộ: KHÔNG retry mù — hiển thị lỗi để người dùng/dev thấy.
          Rails.logger.error("[facebook] publish ##{@post.id} lỗi bất ngờ: #{e.class}: #{e.message}")
          fail_permanently!(attempt, code: "internal_error", message: "#{e.class}: #{e.message}".truncate(300), kind: "unknown")
        end
      end

      private

      def client = @client ||= Facebook::GraphApi.client

      # Khoá dòng, kiểm tra điều kiện, chuyển sang publishing. Mọi lý do bỏ qua
      # trả về outcome rõ ràng (không raise).
      def claim!
        @post.with_lock do
          @post.reload
          return Result.new(outcome: :stale_token, post: @post) if @token && @post.schedule_token != @token
          return Result.new(outcome: :not_scheduled, post: @post) unless @post.scheduled?
          return Result.new(outcome: :not_due, post: @post) if @post.effective_run_at > Time.current + 5.seconds

          conn = @post.facebook_page_connection
          if (reason = conn.blocked_reason)
            # Kill switch / tạm dừng: giữ nguyên scheduled, sweeper sẽ thử lại sau khi mở.
            @post.facebook_publish_attempts.create!(attempt_number: @post.attempts + 1, outcome: "skipped",
                                                    error_code: reason.to_s, started_at: Time.current,
                                                    finished_at: Time.current, mock: conn.mock?)
            return Result.new(outcome: :paused, post: @post)
          end

          issues = Validate.call(@post)
          if issues.any?
            @post.update!(status: "publishing")
            @post.update!(status: "failed", error_kind: "permanent", last_error_code: issues.first.to_s,
                          last_error: "Không đạt kiểm tra trước khi đăng: #{issues.join(', ')}", next_attempt_at: nil)
            @post.facebook_publish_attempts.create!(attempt_number: @post.attempts + 1, outcome: "permanent_failure",
                                                    error_kind: "permanent", error_code: issues.first.to_s,
                                                    error_message: issues.join(", "), started_at: Time.current,
                                                    finished_at: Time.current, mock: conn.mock?)
            Audit.record(@post, "failed", details: { "code" => issues.first.to_s, "issues" => issues.map(&:to_s) })
            Audit.notify(@post, "facebook_post_failed", user: @post.created_by, payload: { "error" => issues.join(", ") })
            return Result.new(outcome: :invalid, post: @post)
          end

          @post.update!(status: "publishing", publish_started_at: Time.current, attempts: @post.attempts + 1,
                        next_attempt_at: nil)
          Result.new(outcome: :claimed, post: @post)
        end
      end

      def mark_published!(remote, attempt)
        @post.with_lock do
          @post.update!(status: "published", facebook_post_id: remote[:post_id], permalink_url: remote[:permalink_url],
                        published_at: remote[:created_time] || Time.current,
                        published_via: client.mock? ? "mock" : "live",
                        last_error: nil, last_error_code: nil, error_kind: nil, next_attempt_at: nil)
        end
        attempt.update!(outcome: "success", remote_post_id: remote[:post_id], finished_at: Time.current)
        Audit.record(@post, "published", details: { "facebook_post_id" => remote[:post_id],
                                                    "via" => @post.published_via, "attempt" => attempt.attempt_number })
        Audit.notify(@post, "facebook_post_published", user: @post.created_by,
                     payload: { "permalink_url" => @post.permalink_url, "via" => @post.published_via })
      end

      def handle_failure(error, attempt)
        kind = error.respond_to?(:kind) ? error.kind : :network
        info = error.is_a?(Facebook::ApiError) ? error.to_h : { kind: kind, message: error.message }
        transient = error.transient?

        if transient && @post.attempts < @post.max_attempts
          next_at = Backoff.next_attempt_at(@post.attempts)
          @post.with_lock do
            @post.update!(status: "scheduled", next_attempt_at: next_at, error_kind: "transient",
                          last_error_code: kind.to_s, last_error: error.message)
          end
          attempt.update!(outcome: "transient_failure", error_kind: kind.to_s, error_code: info[:code]&.to_s,
                          error_subcode: info[:subcode]&.to_s, http_status: info[:http_status],
                          fbtrace_id: info[:fbtrace_id], error_message: error.message, finished_at: Time.current)
          Audit.record(@post, "retry_scheduled", details: { "attempt" => @post.attempts, "next_attempt_at" => next_at.utc.iso8601,
                                                            "code" => info[:code], "kind" => kind.to_s })
          Scheduling.enqueue(@post)
          Result.new(outcome: :retry_scheduled, post: @post, error: error)
        else
          reflect_on_connection(kind, error)
          final_kind = transient ? "transient" : "permanent"
          code = transient ? "max_attempts_exhausted" : kind.to_s
          fail_permanently!(attempt, code: code, message: error.message, kind: final_kind, info: info)
        end
      end

      def fail_permanently!(attempt, code:, message:, kind:, info: {})
        @post.with_lock do
          @post.update!(status: "failed", error_kind: kind, last_error_code: code, last_error: message, next_attempt_at: nil)
        end
        attempt.update!(outcome: "permanent_failure", error_kind: kind, error_code: info[:code]&.to_s || code,
                        error_subcode: info[:subcode]&.to_s, http_status: info[:http_status],
                        fbtrace_id: info[:fbtrace_id], error_message: message, finished_at: Time.current)
        Audit.record(@post, "failed", details: { "code" => code, "kind" => kind, "attempt" => @post.attempts })
        Audit.notify(@post, "facebook_post_failed", user: @post.created_by, payload: { "error" => message.to_s.truncate(200) })
        Result.new(outcome: :failed, post: @post)
      end

      # Token hết hạn / thiếu quyền → phản ánh lên kết nối để dashboard hiện chẩn đoán.
      def reflect_on_connection(kind, error)
        conn = @post.facebook_page_connection
        case kind
        when :token_expired
          conn.update_columns(status: "token_expired", last_error_code: "token_expired", last_error: error.message, updated_at: Time.current)
        when :permission
          conn.update_columns(status: "permission_missing", last_error_code: "permission", last_error: error.message, updated_at: Time.current)
        end
      end
    end

    # Gọi đúng endpoint theo loại bài. Trả về { post_id:, permalink_url:, created_time: }.
    class Publisher
      def initialize(post, client)
        @post = post
        @client = client
        @conn = post.facebook_page_connection
      end

      def publish
        token = @conn.access_token
        raise Facebook::ConfigurationError, "Page không có token." if token.blank?

        post_id =
          case @post.post_type
          when "photo" then publish_photo(token)
          else publish_feed(token)
          end
        raise Facebook::ApiError.new("Meta không trả về ID bài đăng") if post_id.blank?

        { post_id: post_id }.merge(fetch_permalink(post_id, token))
      end

      private

      # POST /{page-id}/feed — bài text, kèm link nếu có.
      def publish_feed(token)
        params = { message: @post.message, access_token: token }
        params[:link] = @post.link if @post.link.present?
        resp = @client.post("/#{@conn.page_id}/feed", params)
        resp["id"]
      end

      # POST /{page-id}/photos (multipart `source`) — trả về post_id của bài trên feed.
      def publish_photo(token)
        blob = @post.image.blob
        resp = blob.open do |file|
          @client.post_multipart("/#{@conn.page_id}/photos", { message: @post.message, access_token: token },
                                 file: { io: file, filename: blob.filename.to_s, content_type: blob.content_type })
        end
        resp["post_id"].presence || resp["id"]
      end

      # Best-effort: bài ĐÃ đăng; không lấy được permalink thì không được coi là thất bại.
      def fetch_permalink(post_id, token)
        resp = @client.get("/#{post_id}", fields: "permalink_url,created_time", access_token: token)
        { permalink_url: resp["permalink_url"],
          created_time: (Time.zone.parse(resp["created_time"].to_s) rescue nil) }
      rescue Facebook::Error => e
        Rails.logger.warn("[facebook] không lấy được permalink cho #{post_id}: #{e.class}")
        { permalink_url: nil, created_time: nil }
      end
    end
  end
end
