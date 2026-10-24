class CampaignInviteAcceptancesController < ActionController::Base
  # Không dùng ApplicationController: người nhận invite có thể chưa có session.
  layout "application"
  include Authentication
  skip_before_action :require_login, only: %i[show accept]

  def show
    @token = CampaignCollaboratorToken.find_by(token: params[:token])
    redirect_to login_path, alert: "Lời mời không hợp lệ hoặc đã hết hạn." unless @token&.usable?
  end

  # Acceptance CHỈ tạo: user (nếu mới) + membership external_reviewer (restricted)
  # + CampaignCollaborator đúng campaign. KHÔNG bao giờ cấp role internal.
  def accept
    @token = CampaignCollaboratorToken.find_by(token: params[:token])
    unless @token&.usable?
      redirect_to login_path, alert: "Lời mời không hợp lệ hoặc đã hết hạn." and return
    end

    user = User.find_by(email: @token.email)
    if user.nil?
      user = User.new(email: @token.email,
                      name: params[:name].presence || @token.email.split("@").first,
                      password: params[:password])
      unless user.valid?
        flash.now[:alert] = user.errors.full_messages.to_sentence
        render :show, status: :unprocessable_entity and return
      end
      user.save!
    end

    ActiveRecord::Base.transaction do
      Membership.find_or_create_by!(organization: @token.organization, user: user) do |m|
        m.role = "external_reviewer"
      end
      @token.campaign.campaign_collaborators.find_or_create_by!(user: user) do |c|
        c.access = @token.access.presence || "approve"
      end
      @token.update!(accepted_at: Time.current)
      AuditLog.record!(org: @token.organization, user: user,
                       action: "campaign_invite.accepted", subject: @token,
                       details: { "campaign_id" => @token.campaign_id })
    end
    session[:user_id] = user.id
    session[:org_id] = @token.organization_id
    redirect_to campaign_path(@token.campaign),
                notice: "Chào mừng! Bạn là reviewer của campaign \"#{@token.campaign.name}\"."
  end
end
