class EventsController < ApplicationController
  before_action :set_event, only: %i[ics rsvp]

  def create
    campaign = Campaign.in_org(current_organization).find(params[:event][:campaign_id])
    return unless require_role!(:edit, subject: campaign)
    event = campaign.events.create!(event_params)
    AuditLog.record!(org: current_organization, user: current_user, action: "event.created", subject: event)
    redirect_to campaign_path(campaign), notice: "Đã tạo sự kiện. Tải file .ics để thêm vào lịch của bạn (MVP)."
  end

  def ics
    return unless require_role!(:view, subject: @event.campaign)
    send_data @event.to_ics, filename: "event-#{@event.id}.ics", type: "text/calendar"
  end

  # RSVP của chính mình — tạo attendee nếu chưa có.
  def rsvp
    return unless require_role!(:comment, subject: @event.campaign)
    attendee = @event.event_attendees.find_or_create_by!(user: current_user)
    attendee.update!(rsvp: params[:rsvp])
    Reminders::ScheduleForEvent.call(@event, current_user)
    redirect_to campaign_path(@event.campaign, anchor: "stage-launch"), notice: "Đã ghi nhận RSVP: #{params[:rsvp]}."
  end

  private

  def set_event
    @event = Event.joins(:campaign).where(campaigns: { organization_id: current_organization.id }).find(params[:id])
  end

  def event_params
    params.require(:event).permit(:title, :starts_at, :ends_at, :location, :agenda)
  end
end
