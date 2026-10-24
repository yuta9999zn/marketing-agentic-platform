# frozen_string_literal: true

module Facebook
  # Hoàn tất callback OAuth: đổi code → token dài hạn → lấy danh sách Page →
  # lưu thành FacebookAuthorization (token mã hoá, hết hạn 15 phút) để người
  # dùng chọn Page. Chế độ mock bỏ qua Meta hoàn toàn.
  class BeginAuthorization
    def self.call(user:, org:, code:, redirect_uri:, page_hint: nil, mode: nil)
      mode ||= Facebook::Config.mode.to_s
      raise Facebook::ConfigurationError, "Meta app chưa được cấu hình." if mode == "unconfigured"

      token, expires_at, pages, scopes =
        if mode == "mock"
          raise Facebook::ConfigurationError, "Mock mode không được phép trên production." if Rails.env.production?

          [ "mock_user_token", nil, Facebook::GraphApi::MockClient::MOCK_PAGES.map(&:dup), Facebook::Config::REQUIRED_SCOPES ]
        else
          exch = Facebook::Oauth.exchange_code(code: code, redirect_uri: redirect_uri)
          pages = Facebook::Oauth.pages(exch[:token])
          scopes = begin
            Array(Facebook::Oauth.debug_token(exch[:token])["scopes"])
          rescue Facebook::Error
            [] # chẩn đoán best-effort; không chặn kết nối
          end
          [ exch[:token], exch[:expires_at], pages, scopes ]
        end

      FacebookAuthorization.where(user: user, organization: org).delete_all
      FacebookAuthorization.create!(
        organization: org, user: user, mode: mode, page_hint: page_hint.presence,
        user_token: token, token_expires_at: expires_at, granted_scopes: scopes,
        page_tokens: pages.to_h { |p| [ p["id"].to_s, p["access_token"].to_s ] },
        pages: pages.map { |p| FacebookAuthorization.public_page_attrs(p) },
        expires_at: FacebookAuthorization::TTL.from_now
      )
    end
  end
end
