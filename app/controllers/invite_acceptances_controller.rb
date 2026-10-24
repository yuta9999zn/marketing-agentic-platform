class InviteAcceptancesController < ApplicationController
  skip_before_action :require_login
  layout "application"

  def show
    @invitation = Invitation.find_by(token: params[:token])
    redirect_to login_path, alert: "Lời mời không hợp lệ hoặc đã hết hạn." unless @invitation&.usable?
  end

  def accept
    @invitation = Invitation.find_by(token: params[:token])
    unless @invitation&.usable?
      redirect_to login_path, alert: "Lời mời không hợp lệ hoặc đã hết hạn." and return
    end

    user = User.find_by(email: @invitation.email)
    if user.nil?
      user = User.new(email: @invitation.email, name: params[:name].presence || @invitation.email.split("@").first,
                      password: params[:password])
      unless user.valid?
        flash.now[:alert] = user.errors.full_messages.to_sentence
        render :show, status: :unprocessable_entity and return
      end
      user.save!
    end

    ActiveRecord::Base.transaction do
      Membership.find_or_create_by!(organization: @invitation.organization, user: user) do |m|
        m.role = @invitation.role
      end
      @invitation.update!(accepted_at: Time.current)
      AuditLog.record!(org: @invitation.organization, user: user, action: "member.joined", subject: user)
    end
    session[:user_id] = user.id
    session[:org_id] = @invitation.organization_id
    redirect_to root_path, notice: "Chào mừng bạn vào #{@invitation.organization.name}!"
  end
end
