class TasksController < ApplicationController
  def create
    campaign = Campaign.in_org(current_organization).find(params[:task][:campaign_id])
    return unless require_role!(:edit, subject: campaign)
    task = campaign.tasks.create!(task_params)
    Reminders::ScheduleForTask.call(task)
    Notifications::Builder.notify(user: task.assignee, org: current_organization, kind: "task_assigned",
                                  payload: { "task_id" => task.id, "title" => task.title })
    AuditLog.record!(org: current_organization, user: current_user, action: "task.created", subject: task)
    redirect_to campaign_path(campaign), notice: "Đã tạo task."
  end

  def update
    task = Task.joins(:campaign).where(campaigns: { organization_id: current_organization.id }).find(params[:id])
    return unless require_role!(:edit, subject: task.campaign)
    task.update!(task_params)
    Reminders::ScheduleForTask.call(task)
    redirect_to campaign_path(task.campaign), notice: "Đã cập nhật task."
  end

  private

  # Campaign chủ của task — dùng để scope milestone/depends_on/assignee.
  def task_campaign
    return @task_campaign if defined?(@task_campaign)

    @task_campaign =
      if params[:id]
        Task.joins(:campaign).where(campaigns: { organization_id: current_organization.id })
            .find_by(id: params[:id])&.campaign
      else
        Campaign.in_org(current_organization).find_by(id: params[:task][:campaign_id])
      end
  end

  def task_params
    permitted = params.require(:task).permit(:title, :description, :assignee_id, :due_date,
                                             :status, :priority, :blocked_reason,
                                             :milestone_id, :depends_on_id)
    # Assignee phải là member cùng organization — chặn cross-tenant user qua HTTP.
    if permitted[:assignee_id].present?
      permitted[:assignee_id] = current_organization.users.find_by(id: permitted[:assignee_id])&.id
    end
    # Milestone/depends_on phải thuộc cùng campaign — id lạ bị clear thay vì accept.
    if task_campaign
      if permitted[:milestone_id].present?
        permitted[:milestone_id] = task_campaign.milestones.find_by(id: permitted[:milestone_id])&.id
      end
      if permitted[:depends_on_id].present?
        permitted[:depends_on_id] = task_campaign.tasks.find_by(id: permitted[:depends_on_id])&.id
      end
    end
    permitted
  end
end
