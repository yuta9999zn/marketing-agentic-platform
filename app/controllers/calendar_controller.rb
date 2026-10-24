class CalendarController < ApplicationController
  # Content calendar: lịch tháng gộp 3 nguồn thật — sự kiện, task có hạn,
  # artifact có due_date (ngày dự kiến đăng/giao). Scope theo campaign mà
  # người dùng được phép thấy.
  def index
    return unless require_internal!

    @month = parse_month(params[:month])
    range = @month.beginning_of_month..@month.end_of_month
    campaign_ids = Access::CampaignAccessScope.ids_for(user: current_user, org: current_organization,
                                                       role: current_role)

    events = Event.where(campaign_id: campaign_ids, starts_at: range.first.beginning_of_day..range.last.end_of_day)
                  .includes(:campaign)
    tasks = Task.where(campaign_id: campaign_ids, due_date: range).includes(:campaign, :assignee)
    artifacts = Artifact.where(campaign_id: campaign_ids, due_date: range).includes(:campaign)

    @entries_by_date = Hash.new { |h, k| h[k] = [] }
    events.each { |e| @entries_by_date[e.starts_at.in_time_zone.to_date] << entry_for_event(e) }
    tasks.each { |t| @entries_by_date[t.due_date] << entry_for_task(t) }
    artifacts.each { |a| @entries_by_date[a.due_date] << entry_for_artifact(a) }

    @upcoming = Event.where(campaign_id: campaign_ids).where(starts_at: Time.current..)
                     .includes(:campaign).order(:starts_at).limit(8)
    @channels = artifacts.map(&:channel).compact_blank.uniq.sort
  end

  private

  # Tháng lạ / format sai → tháng hiện tại. Không bao giờ raise từ query param.
  def parse_month(value)
    Date.strptime(value.to_s, "%Y-%m")
  rescue Date::Error, TypeError
    Date.current.beginning_of_month
  end

  def entry_for_event(event)
    { type: "event", title: event.title, campaign: event.campaign,
      time: event.starts_at.in_time_zone.strftime("%H:%M"), url: campaign_path(event.campaign),
      meta: event.location }
  end

  def entry_for_task(task)
    { type: task.overdue? ? "task_overdue" : "task", title: task.title, campaign: task.campaign,
      time: nil, url: campaign_path(task.campaign, anchor: "stage-tasks"),
      meta: task.assignee&.name }
  end

  def entry_for_artifact(artifact)
    { type: "content", title: artifact.title, campaign: artifact.campaign,
      time: nil, url: artifact_path(artifact), meta: artifact.channel }
  end
end
