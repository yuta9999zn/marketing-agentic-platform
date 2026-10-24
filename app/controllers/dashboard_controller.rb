class DashboardController < ApplicationController
  CHART_DAYS = 30

  def index
    org = current_organization

    # Mọi query đều đi qua CampaignAccessScope — client/external_reviewer
    # chỉ thấy campaign được mời, kể cả count/task/event/activity.
    campaign_ids = Access::CampaignAccessScope.ids_for(user: current_user, org: org, role: current_role)
    campaign_scope = Access::CampaignAccessScope.call(user: current_user, org: org, role: current_role)

    @campaigns_count = campaign_scope.count
    @tasks_open_count = Task.where(campaign_id: campaign_ids).open.count
    @pending_approvals_count = Artifact.where(campaign_id: campaign_ids, approval_status: "in_review").count

    @my_tasks = Task.where(campaign_id: campaign_ids, assignee: current_user)
                    .open.order(due_date: :asc).includes(:campaign).limit(6)

    approve_ok = policy_for.allowed?(:approve)
    @my_approvals = if approve_ok
      Artifact.where(campaign_id: campaign_ids, approval_status: "in_review")
              .order(updated_at: :asc).includes(:campaign).limit(5)
    else
      Artifact.none
    end

    @attention_campaigns = campaign_scope
      .where(id: Task.open.overdue.select(:campaign_id))
      .or(campaign_scope.where(id: Artifact.where(approval_status: "in_review").select(:campaign_id)))
      .includes(:client).limit(4)

    @week_events = Event.where(campaign_id: campaign_ids)
                        .where(starts_at: Time.current.beginning_of_day..7.days.from_now.end_of_day)
                        .order(starts_at: :asc).includes(:campaign)

    # Audit log chưa có scope campaign an toàn → campaign-scoped role không
    # thấy activity gì thay vì thấy activity toàn workspace.
    @recent_activity = campaign_scoped_role? ? AuditLog.none : AuditLog.where(organization: org).order(created_at: :desc).limit(6)

    @notifications = current_user.notifications.where(organization: org).order(created_at: :desc).limit(5)
    @is_internal = !campaign_scoped_role?

    load_marketing_overview(org, campaign_ids)
  end

  private

  # Số liệu cho hero/KPI/biểu đồ — toàn bộ lấy từ DB thật (artifact, bài
  # Facebook, lượt gọi AI). Không có số nào là giả.
  def load_marketing_overview(org, campaign_ids)
    window = CHART_DAYS.days.ago.beginning_of_day..Time.current.end_of_day
    prev_window = (2 * CHART_DAYS).days.ago.beginning_of_day...CHART_DAYS.days.ago.beginning_of_day

    artifacts = Artifact.where(campaign_id: campaign_ids)
    fb_scope = @is_internal ? FacebookPost.in_org(org) : FacebookPost.none

    @content_30d = artifacts.where(created_at: window).count
    @content_prev = artifacts.where(created_at: prev_window).count
    @fb_pending_count = fb_scope.awaiting_approval.count
    @fb_scheduled_count = fb_scope.where(status: "scheduled").count
    @fb_published_30d = fb_scope.where(status: "published", published_at: window).count
    @fb_published_prev = fb_scope.where(status: "published", published_at: prev_window).count
    @fb_failed_count = fb_scope.where(status: "failed").count
    @ai_calls_30d = @is_internal ? AiCall.where(organization: org, created_at: window).count : 0
    @ai_calls_prev = @is_internal ? AiCall.where(organization: org, created_at: prev_window).count : 0
    @ai_calls_month = @is_internal ? AiCall.where(organization: org, created_at: Time.current.beginning_of_month..).count : 0

    @chart_days = (0...CHART_DAYS).map { |i| (CHART_DAYS - 1 - i).days.ago.to_date }
    created_by_day = artifacts.where(created_at: window).group("date(created_at)").count
    published_by_day = fb_scope.where(status: "published", published_at: window).group("date(published_at)").count
    @chart_created = @chart_days.map { |d| created_by_day.fetch(d.to_s, 0) }
    @chart_published = @chart_days.map { |d| published_by_day.fetch(d.to_s, 0) }

    @fb_connection = @is_internal ? org.facebook_page_connections.active.order(updated_at: :desc).first : nil
    @fb_upcoming = fb_scope.upcoming.includes(:facebook_page_connection).limit(5)
    @fb_recent = fb_scope.recent_activity.includes(:facebook_page_connection).limit(5)
    @recent_content = artifacts.includes(:campaign).order(updated_at: :desc).limit(3)
  end
end
