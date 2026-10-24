# frozen_string_literal: true

module Facebook
  # Kiểm tra sức khoẻ kết nối: token còn hợp lệ, đủ quyền, đủ vai trò trên Page.
  # Mỗi vấn đề kèm hướng xử lý cụ thể — người dùng không cần hiểu mã lỗi Meta.
  class Diagnostics
    Issue = Struct.new(:code, :severity, :params, keyword_init: true)
    Report = Struct.new(:ok, :issues, :checked_at, :token_scopes, :token_expires_at, keyword_init: true) do
      def ok? = ok
    end

    def self.call(connection, remote: true)
      new(connection).call(remote: remote)
    end

    def initialize(connection)
      @conn = connection
    end

    def call(remote: true)
      issues = []
      issues << Issue.new(code: :disconnected, severity: :error) if @conn.disconnected?
      issues << Issue.new(code: :deploy_kill_switch, severity: :warning) unless Facebook::Config.publishing_enabled?
      issues << Issue.new(code: :org_paused, severity: :warning) if @conn.organization.facebook_publishing_paused?
      issues << Issue.new(code: :page_paused, severity: :warning) if @conn.publishing_paused?
      issues << Issue.new(code: :unconfigured, severity: :error) if @conn.connection_mode == "live" && !Facebook::Config.configured?
      issues << Issue.new(code: :mock_mode, severity: :info) if @conn.connection_mode == "mock"

      scopes = @conn.granted_scopes
      expires_at = @conn.token_expires_at
      if remote && !@conn.disconnected? && @conn.access_token.present?
        begin
          data = Facebook::Oauth.debug_token(@conn.access_token)
          scopes = Array(data["scopes"]).presence || scopes
          expires_at = data["expires_at"].to_i.positive? ? Time.zone.at(data["expires_at"].to_i) : nil
          issues << Issue.new(code: :token_invalid, severity: :error) if data.key?("is_valid") && !data["is_valid"]
          # Gọi thêm một endpoint bằng page token — kiểm tra token sống thật.
          Facebook::GraphApi.client.get("/#{@conn.page_id}", fields: "id,name", access_token: @conn.access_token)
        rescue Facebook::ApiError => e
          issues << Issue.new(code: e.kind == :token_expired ? :token_expired : :api_error, severity: :error,
                              params: { message: e.message })
        rescue Facebook::NetworkError => e
          issues << Issue.new(code: :network, severity: :warning, params: { message: e.message })
        rescue Facebook::ConfigurationError => e
          issues << Issue.new(code: :cipher, severity: :error, params: { message: e.message })
        end
      end

      missing = Facebook::Config::REQUIRED_SCOPES - Array(scopes)
      issues << Issue.new(code: :missing_scopes, severity: :error, params: { scopes: missing.join(", ") }) if missing.any? && scopes.present?
      missing_tasks = Facebook::Config::REQUIRED_PAGE_TASKS - Array(@conn.page_tasks)
      issues << Issue.new(code: :missing_page_role, severity: :error, params: { tasks: missing_tasks.join(", ") }) if missing_tasks.any? && @conn.page_tasks.present?
      issues << Issue.new(code: :token_expiring, severity: :warning, params: { at: expires_at }) if expires_at && expires_at < 7.days.from_now
      issues << Issue.new(code: :token_expired, severity: :error) if expires_at && expires_at < Time.current && issues.none? { |i| i.code == :token_expired }

      report = Report.new(ok: issues.none? { |i| i.severity == :error }, issues: issues,
                          checked_at: Time.current, token_scopes: scopes, token_expires_at: expires_at)
      persist(report, scopes, expires_at)
      report
    end

    private

    def persist(report, scopes, expires_at)
      return if @conn.disconnected?

      new_status =
        if report.issues.any? { |i| %i[token_expired token_invalid].include?(i.code) } then "token_expired"
        elsif report.issues.any? { |i| %i[missing_scopes missing_page_role].include?(i.code) } then "permission_missing"
        elsif report.issues.any? { |i| i.code == :api_error } then "error"
        else "connected"
        end
      first_error = report.issues.find { |i| i.severity == :error }
      @conn.update_columns(status: new_status, last_checked_at: report.checked_at,
                           granted_scopes: scopes.presence || @conn.granted_scopes,
                           token_expires_at: expires_at,
                           last_error_code: first_error&.code&.to_s,
                           last_error: first_error&.params&.dig(:message),
                           updated_at: Time.current)
    end
  end
end
