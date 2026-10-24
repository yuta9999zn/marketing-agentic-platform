# Cài đặt cá nhân (mọi role, kể cả client): ngôn ngữ UI + cấu hình nhắc nhở.
# Chỉ sửa được chính mình — không nhận user_id từ params.
class UserSettingsController < ApplicationController
  def show; end

  def update
    if current_user.update(settings_params)
      # Đổi lead time → reminder queued theo lead cũ thành stale; lịch nhắc được
      # dựng lại ngay cho task/event còn hiệu lực của chính user này.
      Reminders::Resync.call(user: current_user, org: current_organization) if lead_or_channel_changed?
      AuditLog.record!(org: current_organization, user: current_user,
                       action: "user.settings_updated", subject: current_user)
      redirect_to safe_return_path, notice: t("marketingos.settings.saved")
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  # Chỉ nhận đường dẫn nội bộ (bắt đầu bằng một "/") — chặn open redirect.
  def safe_return_path
    candidate = params[:return_to].to_s
    candidate.start_with?("/") && !candidate.start_with?("//") ? candidate : settings_path
  end

  def lead_or_channel_changed?
    current_user.saved_change_to_reminder_lead_minutes? || current_user.saved_change_to_reminder_channel?
  end

  def settings_params
    params.require(:user).permit(:locale, :reminder_lead_minutes, :reminder_channel)
  end
end
