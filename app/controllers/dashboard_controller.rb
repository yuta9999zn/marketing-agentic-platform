class DashboardController < ApplicationController
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
  end
end
