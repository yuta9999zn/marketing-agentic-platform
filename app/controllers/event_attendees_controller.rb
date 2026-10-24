class EventAttendeesController < ApplicationController
  # RSVP cho chính mình — hoặc mời attendee (edit quyền campaign).
  def create
    event = Event.joins(:campaign).where(campaigns: { organization_id: current_organization.id }).find(params[:event_id])
    return unless require_role!(:edit, subject: event.campaign)

    users = current_organization.users.where(id: Array(params[:user_ids]))
    users.each do |u|
      event.event_attendees.find_or_create_by!(user: u)
      Reminders::ScheduleForEvent.call(event, u)
    end
    redirect_to campaign_path(event.campaign, anchor: "stage-launch"), notice: "Đã mời #{users.size} người tham dự."
  end

  def rsvp
    event = Event.joins(:campaign).where(campaigns: { organization_id: current_organization.id }).find(params[:event_id])
    return unless require_role!(:comment, subject: event.campaign)

    attendee = event.event_attendees.find_or_create_by!(user: current_user)
    attendee.update!(rsvp: params[:rsvp])
    Reminders::ScheduleForEvent.call(event, current_user)
    redirect_to campaign_path(event.campaign, anchor: "stage-launch"), notice: "Đã ghi nhận RSVP: #{params[:rsvp]}."
  end
end
