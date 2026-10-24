class CollaboratorsController < ApplicationController
  before_action :set_campaign, only: %i[create]

  # Cấp/tắt quyền truy cập campaign cho user trong org (client portal scope).
  def create
    return unless require_role!(:manage, subject: @campaign)
    user = current_organization.users.find_by(id: params[:user_id])
    return redirect_to campaign_path(@campaign), alert: "Người dùng không thuộc organization." if user.nil?

    access = CampaignCollaborator::ACCESS.include?(params[:access]) ? params[:access] : "view"
    @campaign.campaign_collaborators.find_or_create_by!(user: user) do |c|
      c.access = access
    end
    AuditLog.record!(org: current_organization, user: current_user, action: "collaborator.added",
                     subject: @campaign, details: { "user_id" => user.id, "access" => access })
    redirect_to campaign_path(@campaign, anchor: "collaborators"), notice: "Đã cấp quyền truy cập cho #{user.name}."
  end

  # Route shallow DELETE /collaborators/:id (không có campaign_id) — tìm
  # collaborator scoped theo org rồi authorize trên campaign của nó.
  def destroy
    collab = CampaignCollaborator.joins(:campaign)
                                 .where(campaigns: { organization_id: current_organization.id })
                                 .find(params[:id])
    return unless require_role!(:manage, subject: collab.campaign)

    collab.destroy!
    AuditLog.record!(org: current_organization, user: current_user, action: "collaborator.removed",
                     subject: collab.campaign, details: { "user_id" => collab.user_id })
    redirect_to campaign_path(collab.campaign, anchor: "collaborators"), notice: "Đã thu hồi quyền truy cập."
  end

  private

  def set_campaign
    @campaign = Campaign.in_org(current_organization).find(params[:campaign_id])
  end
end
