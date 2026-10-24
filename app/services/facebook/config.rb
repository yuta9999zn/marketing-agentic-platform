# frozen_string_literal: true

module Facebook
  # Toàn bộ cấu hình Meta app đọc từ ENV — không hard-code, không lưu DB.
  #
  # Ba chế độ:
  # - :live         — FACEBOOK_APP_ID + FACEBOOK_APP_SECRET có giá trị → gọi Graph API thật.
  # - :mock         — FACEBOOK_MOCK_MODE=true, CHỈ ngoài production: mô phỏng toàn bộ
  #                   OAuth + publish để chạy UI/test không cần Meta. Bài đăng mock
  #                   luôn gắn nhãn published_via="mock", không bao giờ lẫn với thật.
  # - :unconfigured — chưa có gì: mọi thao tác publish thất bại rõ ràng (permanent).
  class Config
    DEFAULT_GRAPH_VERSION = "v23.0"
    # Quyền tối thiểu cho tính năng đã triển khai (đọc danh sách Page, đăng bài):
    # - pages_show_list:       liệt kê Page người dùng quản lý (/me/accounts)
    # - pages_manage_posts:    tạo/xoá bài trên Page
    # - pages_read_engagement: bắt buộc đi kèm pages_manage_posts để đọc nội dung Page
    REQUIRED_SCOPES = %w[pages_show_list pages_read_engagement pages_manage_posts].freeze
    # Page task cần có để đăng bài (vai trò admin/editor trên Page).
    REQUIRED_PAGE_TASKS = %w[CREATE_CONTENT].freeze

    class << self
      def app_id = ENV["FACEBOOK_APP_ID"].presence
      def app_secret = ENV["FACEBOOK_APP_SECRET"].presence
      def graph_version = ENV["FACEBOOK_GRAPH_API_VERSION"].presence || DEFAULT_GRAPH_VERSION
      def graph_host = "https://graph.facebook.com"
      def dialog_host = "https://www.facebook.com"
      def explicit_redirect_uri = ENV["FACEBOOK_REDIRECT_URI"].presence

      def configured? = app_id.present? && app_secret.present?

      # Mock chỉ tồn tại ngoài production. Đặt FACEBOOK_MOCK_MODE=true trên
      # production bị bỏ qua (và cảnh báo) — không bao giờ mô phỏng đăng thật.
      def mock_mode?
        return false if Rails.env.production?

        ENV["FACEBOOK_MOCK_MODE"] == "true"
      end

      def mode
        return :mock if mock_mode?
        return :live if configured?

        :unconfigured
      end

      # Kill switch cấp triển khai (ENV). Kill switch cấp workspace nằm ở
      # organizations.facebook_publishing_paused.
      def publishing_enabled? = ENV.fetch("FACEBOOK_PUBLISHING_ENABLED", "true") != "false"

      def app_access_token = "#{app_id}|#{app_secret}"

      def scopes = REQUIRED_SCOPES

      def max_attempts = ENV.fetch("FACEBOOK_PUBLISH_MAX_ATTEMPTS", 5).to_i.clamp(1, 10)
    end
  end
end
