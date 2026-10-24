class NotificationsController < ApplicationController
  def index
    @notifications = current_user.notifications.where(organization: current_organization).order(created_at: :desc)
  end

  def mark_read
    current_user.notifications.where(organization: current_organization, read_at: nil)
                 .update_all(read_at: Time.current)
    redirect_to notifications_path
  end
end
