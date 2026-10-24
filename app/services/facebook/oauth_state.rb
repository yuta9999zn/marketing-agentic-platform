# frozen_string_literal: true

module Facebook
  # Tham số `state` của OAuth: token ký bằng message_verifier của app, chứa
  # user/org/nonce/page_hint, hết hạn 10 phút. Nonce ĐỒNG THỜI nằm trong session
  # của trình duyệt bắt đầu luồng — callback phải khớp cả chữ ký lẫn session,
  # nên state bị đánh cắp hoặc dùng ở trình duyệt khác đều bị từ chối (CSRF).
  class OauthState
    TTL = 10.minutes
    PURPOSE = :facebook_oauth

    class Invalid < Facebook::Error; end

    class << self
      def generate(user:, org:, nonce:, page_hint: nil, mode: "live")
        verifier.generate({ "user_id" => user.id, "org_id" => org.id, "nonce" => nonce,
                            "page_hint" => page_hint.presence, "mode" => mode },
                          purpose: PURPOSE, expires_in: TTL)
      end

      def new_nonce = SecureRandom.hex(16)

      # Trả về payload khi hợp lệ; raise Invalid cho MỌI trường hợp khác
      # (sai chữ ký, hết hạn, sai user/org, nonce không khớp session).
      def verify!(token, user:, org:, nonce:)
        payload = verifier.verified(token.to_s, purpose: PURPOSE)
        raise Invalid, "State không hợp lệ hoặc đã hết hạn." if payload.nil?
        raise Invalid, "State không thuộc phiên đăng nhập này." unless payload["user_id"] == user.id && payload["org_id"] == org.id
        raise Invalid, "State không khớp trình duyệt bắt đầu kết nối." if nonce.blank? || !ActiveSupport::SecurityUtils.secure_compare(payload["nonce"].to_s, nonce.to_s)

        payload
      end

      private

      def verifier = Rails.application.message_verifier("facebook_oauth_state")
    end
  end
end
