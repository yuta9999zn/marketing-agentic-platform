# frozen_string_literal: true

module Facebook
  # Luồng OAuth Facebook Login (server-side, response_type=code) + đổi token.
  # Chỉ dùng endpoint chính thức của Meta:
  #   GET  https://www.facebook.com/{v}/dialog/oauth
  #   GET  https://graph.facebook.com/{v}/oauth/access_token
  #   GET  https://graph.facebook.com/{v}/me/accounts
  #   GET  https://graph.facebook.com/{v}/debug_token
  class Oauth
    PAGE_FIELDS = "id,name,category,link,username,tasks,picture{url},access_token"

    class << self
      def authorize_url(state:, redirect_uri:)
        raise Facebook::ConfigurationError, "Chưa cấu hình FACEBOOK_APP_ID/FACEBOOK_APP_SECRET." unless Facebook::Config.configured?

        query = { client_id: Facebook::Config.app_id, redirect_uri: redirect_uri, state: state,
                  scope: Facebook::Config.scopes.join(","), response_type: "code" }
        "#{Facebook::Config.dialog_host}/#{Facebook::Config.graph_version}/dialog/oauth?#{URI.encode_www_form(query)}"
      end

      # code → user access token (ngắn hạn) → đổi sang dài hạn (~60 ngày).
      # Page token lấy từ user token dài hạn sẽ không hết hạn (theo tài liệu Meta),
      # trừ khi người dùng đổi mật khẩu/thu hồi quyền.
      def exchange_code(code:, redirect_uri:)
        short = client.get("/oauth/access_token", client_id: Facebook::Config.app_id,
                                                  client_secret: Facebook::Config.app_secret,
                                                  redirect_uri: redirect_uri, code: code)
        long = client.get("/oauth/access_token", grant_type: "fb_exchange_token",
                                                 client_id: Facebook::Config.app_id,
                                                 client_secret: Facebook::Config.app_secret,
                                                 fb_exchange_token: short.fetch("access_token"))
        expires_in = long["expires_in"].to_i
        { token: long.fetch("access_token"),
          expires_at: expires_in.positive? ? Time.current + expires_in.seconds : nil }
      rescue KeyError
        raise Facebook::ApiError.new("Phản hồi OAuth thiếu access_token")
      end

      # Danh sách Page người dùng quản lý (kèm page token). Theo phân trang tối đa 5 trang.
      def pages(user_token)
        pages = []
        after = nil
        5.times do
          params = { fields: PAGE_FIELDS, limit: 100, access_token: user_token }
          params[:after] = after if after
          resp = client.get("/me/accounts", params)
          pages.concat(Array(resp["data"]))
          after = resp.dig("paging", "cursors", "after")
          break if after.blank? || resp.dig("paging", "next").blank?
        end
        pages
      end

      # Chẩn đoán token: quyền đã cấp, còn hạn không. Dùng app token.
      def debug_token(token)
        resp = client.get("/debug_token", input_token: token, access_token: Facebook::Config.app_access_token)
        resp.fetch("data", {})
      end

      def client = Facebook::GraphApi.client
    end
  end
end
