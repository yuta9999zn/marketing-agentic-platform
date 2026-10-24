# frozen_string_literal: true

module Facebook
  module Posts
    # Bài kẹt ở `publishing` quá lâu (tiến trình chết giữa chừng): KHÔNG tự đăng
    # lại — có thể đã lên Page rồi. Đọc feed gần đây của Page: thấy bài trùng nội
    # dung sau publish_started_at → nhận là published; không thấy → failed với mã
    # publish_state_unknown, người dùng kiểm tra Page rồi mới thử lại.
    class Reconcile
      def self.call(post:, client: nil)
        new(post, client || Facebook::GraphApi.client).call
      end

      def initialize(post, client)
        @post = post
        @client = client
      end

      def call
        conn = @post.facebook_page_connection
        found = nil
        begin
          if conn.token_present?
            resp = @client.get("/#{conn.page_id}/feed", fields: "id,message,created_time", limit: 25,
                                                        access_token: conn.access_token)
            since = (@post.publish_started_at || @post.updated_at) - 2.minutes
            found = Array(resp["data"]).find do |p|
              p["message"].to_s.strip == @post.message.to_s.strip &&
                (Time.zone.parse(p["created_time"].to_s) rescue Time.at(0)) >= since
            end
          end
        rescue Facebook::Error => e
          Rails.logger.warn("[facebook] reconcile ##{@post.id}: #{e.class}")
        end

        @post.with_lock do
          return :skipped unless @post.publishing?

          if found
            @post.update!(status: "published", facebook_post_id: found["id"], published_at: Time.zone.parse(found["created_time"].to_s),
                          published_via: @client.mock? ? "mock" : "live", last_error: nil, last_error_code: nil, error_kind: nil)
            Audit.record(@post, "published", details: { "facebook_post_id" => found["id"], "reconciled" => true })
            :published
          else
            @post.update!(status: "failed", error_kind: "unknown", last_error_code: "publish_state_unknown",
                          last_error: "Tiến trình đăng bị gián đoạn, không xác định được bài đã lên Page chưa. Hãy kiểm tra Page trước khi thử lại.")
            Audit.record(@post, "failed", details: { "code" => "publish_state_unknown" })
            Audit.notify(@post, "facebook_post_failed", user: @post.created_by, payload: { "error" => "publish_state_unknown" })
            :unknown
          end
        end
      end
    end
  end
end
