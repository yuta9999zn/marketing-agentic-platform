class CampaignInvitesController < ApplicationController
  # Invite campaign-scoped — KHÔNG cấp role workspace. Người nhận trở thành
  # external_reviewer với quyền đúng CampaignCollaborator.access của campaign này.
  before_action :set_campaign, only: %i[create]

  # Chỉ owner/manager gửi/revoke invite campaign.
  def create
    return unless require_role!(:manage, subject: @campaign)

    token = @campaign.campaign_collaborator_tokens.create!(
      email: params[:email].to_s.downcase.strip,
      access: CampaignCollaborator::ACCESS.include?(params[:access]) ? params[:access] : "approve",
      invited_by: current_user
    )
    AuditLog.record!(org: current_organization, user: current_user,
                     action: "campaign_invite.created", subject: token,
                     details: { "campaign_id" => @campaign.id, "email" => token.email,
                                "access" => token.access })
    # Dev chỉ preview/log — KHÔNG gửi mail thật (adapter :test).
    CampaignInvitesMailer.invite(token).deliver_later
    redirect_to campaign_path(@campaign, anchor: "collaborators"),
                notice: "Đã tạo lời mời reviewer cho #{token.email} (xem preview email trong log)."
  end

  def revoke
    token = CampaignCollaboratorToken.joins(:campaign)
                                     .where(campaigns: { organization_id: current_organization.id })
                                     .find(params[:id])
    return unless require_role!(:manage, subject: token.campaign)

    token.update!(revoked_at: Time.current)
    AuditLog.record!(org: current_organization, user: current_user,
                     action: "campaign_invite.revoked", subject: token)
    redirect_to campaign_path(token.campaign, anchor: "collaborators"), notice: "Đã thu hồi lời mời."
  end

  private

  def set_campaign
    @campaign = Campaign.in_org(current_organization).find(params[:campaign_id])
  end
end
