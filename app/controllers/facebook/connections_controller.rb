# frozen_string_literal: true

module Facebook
  # Kết nối Facebook Page qua OAuth chính thức của Meta.
  #
  # Luồng: show (dán link fanpage) → start (redirect tới dialog Meta, state ký +
  # nonce trong session) → callback (đổi code → token → danh sách Page, lưu
  # FacebookAuthorization mã hoá) → tự chọn Page khớp link, hoặc select_page.
  # Token không bao giờ xuất hiện trong view/params/log.
  class ConnectionsController < ApplicationController
    before_action -> { require_internal! }
    before_action :require_manage!, except: %i[show callback]
    before_action :set_connection

    def show
      @authorization = FacebookAuthorization.active.find_by(organization: current_organization, user: current_user)
      @report = @connection && Facebook::Diagnostics.call(@connection, remote: false)
      @campaigns = current_organization.campaigns.order(:name)
      @mode = Facebook::Config.mode
      @redirect_uri = callback_uri
    end

    def start
      hint = Facebook::PageUrlParser.call(params[:page_url])
      if params[:page_url].present? && !hint.present?
        return redirect_to facebook_connection_path, alert: t("marketingos.facebook.connection.bad_url")
      end

      mode = Facebook::Config.mode
      return redirect_to facebook_connection_path, alert: t("marketingos.facebook.connection.unconfigured") if mode == :unconfigured

      nonce = Facebook::OauthState.new_nonce
      session[:facebook_oauth_nonce] = nonce
      state = Facebook::OauthState.generate(user: current_user, org: current_organization, nonce: nonce,
                                            page_hint: hint.raw.presence, mode: mode.to_s)
      AuditLog.record!(org: current_organization, user: current_user, action: "facebook.oauth.started",
                       details: { "mode" => mode.to_s, "page_hint" => hint.label })
      if mode == :mock
        # Mock: không rời khỏi app — đi thẳng tới callback với code giả.
        redirect_to callback_facebook_connection_path(code: "mock_code", state: state)
      else
        redirect_to Facebook::Oauth.authorize_url(state: state, redirect_uri: callback_uri), allow_other_host: true
      end
    end

    def callback
      return unless require_manage!

      nonce = session.delete(:facebook_oauth_nonce)
      payload = Facebook::OauthState.verify!(params[:state], user: current_user, org: current_organization, nonce: nonce)

      if params[:error].present? || params[:code].blank?
        AuditLog.record!(org: current_organization, user: current_user, action: "facebook.oauth.denied",
                         details: { "error" => params[:error].to_s, "reason" => params[:error_reason].to_s })
        return redirect_to facebook_connection_path, alert: t("marketingos.facebook.connection.denied")
      end

      authorization = Facebook::BeginAuthorization.call(user: current_user, org: current_organization,
                                                        code: params[:code], redirect_uri: callback_uri,
                                                        page_hint: payload["page_hint"], mode: payload["mode"])
      if authorization.pages.empty?
        return redirect_to facebook_connection_path, alert: t("marketingos.facebook.connection.no_pages")
      end

      if (page = authorization.hinted_page)
        conn = Facebook::ConnectPage.call(authorization: authorization, page_id: page["id"], user: current_user)
        redirect_to facebook_connection_path, notice: t("marketingos.facebook.connection.connected", name: conn.page_name)
      else
        redirect_to facebook_connection_path, notice: t("marketingos.facebook.connection.choose_page")
      end
    rescue Facebook::OauthState::Invalid => e
      AuditLog.record!(org: current_organization, user: current_user, action: "facebook.oauth.state_rejected")
      redirect_to facebook_connection_path, alert: e.message
    rescue Facebook::Error => e
      redirect_to facebook_connection_path, alert: t("marketingos.facebook.connection.failed", error: e.message)
    end

    def select_page
      authorization = FacebookAuthorization.active.find_by!(organization: current_organization, user: current_user)
      conn = Facebook::ConnectPage.call(authorization: authorization, page_id: params[:page_id], user: current_user)
      redirect_to facebook_connection_path, notice: t("marketingos.facebook.connection.connected", name: conn.page_name)
    rescue Facebook::Error => e
      redirect_to facebook_connection_path, alert: e.message
    end

    def check
      return redirect_to facebook_connection_path, alert: t("marketingos.facebook.connection.none") if @connection.nil?

      report = Facebook::Diagnostics.call(@connection, remote: true)
      AuditLog.record!(org: current_organization, user: current_user, action: "facebook.page.checked", subject: @connection,
                       details: { "ok" => report.ok?, "issues" => report.issues.map { |i| i.code.to_s } })
      redirect_to facebook_connection_path,
                  notice: report.ok? ? t("marketingos.facebook.connection.check_ok") : t("marketingos.facebook.connection.check_issues", count: report.issues.size)
    end

    # Cài đặt Page: auto-publish, tạm dừng, từ khoá chặn, campaign được auto-publish.
    def update
      return redirect_to facebook_connection_path, alert: t("marketingos.facebook.connection.none") if @connection.nil?

      attrs = params.fetch(:connection, {}).permit(:auto_publish_enabled, :publishing_paused, :blocked_terms)
      before = @connection.slice(:auto_publish_enabled, :publishing_paused)
      @connection.update!(attrs)
      if params.key?(:auto_publish_campaign_ids)
        ids = Array(params[:auto_publish_campaign_ids]).map(&:to_i)
        current_organization.campaigns.update_all(facebook_auto_publish: false)
        current_organization.campaigns.where(id: ids).update_all(facebook_auto_publish: true)
      end
      AuditLog.record!(org: current_organization, user: current_user, action: "facebook.page.settings_updated",
                       subject: @connection,
                       details: { "before" => before, "after" => @connection.slice(:auto_publish_enabled, :publishing_paused),
                                  "auto_publish_campaign_ids" => params[:auto_publish_campaign_ids] }.compact)
      redirect_to facebook_connection_path, notice: t("marketingos.facebook.connection.settings_saved")
    end

    # Kill switch toàn workspace — chỉ owner/admin.
    def kill_switch
      return unless require_role!(:admin)

      paused = params[:paused] == "true"
      current_organization.update!(facebook_publishing_paused: paused)
      AuditLog.record!(org: current_organization, user: current_user,
                       action: paused ? "facebook.publishing.paused" : "facebook.publishing.resumed")
      redirect_to facebook_connection_path,
                  notice: paused ? t("marketingos.facebook.connection.paused_all") : t("marketingos.facebook.connection.resumed_all")
    end

    def destroy
      return redirect_to facebook_connection_path, alert: t("marketingos.facebook.connection.none") if @connection.nil?

      @connection.disconnect!(user: current_user)
      redirect_to facebook_connection_path, notice: t("marketingos.facebook.connection.disconnected")
    end

    private

    def set_connection
      @connection = current_organization.facebook_page_connections.active.order(updated_at: :desc).first
    end

    def require_manage! = require_role!(:manage)

    # Redirect URI phải khớp CHÍNH XÁC với giá trị khai trong Meta App.
    def callback_uri
      Facebook::Config.explicit_redirect_uri || callback_facebook_connection_url
    end
  end
end
