class WorkspaceSettingsController < ApplicationController
  # AI workspace settings — chỉ owner/admin (cap admin) được bật external AI.
  before_action :require_admin!

  def update_ai
    enabled = params[:ai_external_enabled] == "true"
    current_organization.update!(ai_external_enabled: enabled)
    AuditLog.record!(org: current_organization, user: current_user,
                     action: "settings.ai_external.#{enabled ? 'enabled' : 'disabled'}")
    redirect_to members_path,
                notice: enabled ? "Đã bật AI provider ngoài (mỗi lần gọi vẫn cần xác nhận riêng + ENV AI_EXTERNAL_ENABLED)." : "Đã tắt AI provider ngoài."
  end

  private

  def require_admin!
    return if policy_for.allowed?(:admin)
    redirect_to root_path, alert: "Chỉ owner/admin được thay đổi cài đặt workspace."
  end
end
