class ClientsController < ApplicationController
  before_action :set_client, only: %i[show update]

  def index
    return unless require_internal!
    @clients = Client.in_org(current_organization).order(:name)
  end

  # Hồ sơ khách hàng: campaign, tiến độ, và mọi góp ý/quyết định duyệt của
  # người phía khách trên các campaign họ được mời.
  def show
    return unless require_internal!
    @campaigns = @client.campaigns.includes(:owner).order(created_at: :desc)
    campaign_ids = @campaigns.map(&:id)

    # "Người phía khách" = collaborator của chính các campaign này (client/external_reviewer).
    @client_user_ids = CampaignCollaborator.where(campaign_id: campaign_ids).pluck(:user_id).uniq

    @comments = Comment.where(campaign_id: campaign_ids, user_id: @client_user_ids)
                       .includes(:user, :artifact, :campaign).order(created_at: :desc).limit(20)
    @decisions = ApprovalDecision.joins(approval_round: :artifact)
                                 .where(user_id: @client_user_ids, artifacts: { campaign_id: campaign_ids })
                                 .includes(:user, approval_round: :artifact)
                                 .order(created_at: :desc).limit(20)
    @events = Event.where(campaign_id: campaign_ids).order(:starts_at)
  end

  def create
    return unless require_role!(:manage)
    client = Client.in_org(current_organization).create!(client_params)
    AuditLog.record!(org: current_organization, user: current_user, action: "client.created", subject: client)
    redirect_to client_path(client), notice: t("marketingos.clients.created")
  end

  def update
    return unless require_role!(:manage)
    if @client.update(client_params)
      AuditLog.record!(org: current_organization, user: current_user, action: "client.updated", subject: @client)
      redirect_to client_path(@client), notice: t("marketingos.clients.updated")
    else
      redirect_to client_path(@client), alert: @client.errors.full_messages.to_sentence
    end
  end

  private

  def set_client
    @client = Client.in_org(current_organization).find(params[:id])
  end

  def client_params
    params.require(:client).permit(:name, :industry, :notes, :contact_name, :contact_email, :contact_phone)
  end
end
