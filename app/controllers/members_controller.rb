class MembersController < ApplicationController
  before_action :require_admin!

  def index
    @memberships = current_organization.memberships.includes(:user)
    @invitations = current_organization.invitations.order(created_at: :desc)
    @invitation = Invitation.new(role: "copywriter")
  end

  # Invite qua signed token có expiry + revoke. Email chỉ là giao dịch mời —
  # MVP gửi qua mailer log/preview, không tự gửi ra ngoài.
  def invite
    invitation = current_organization.invitations.create!(
      email: params[:invitation][:email].downcase.strip,
      role: params[:invitation][:role],
      invited_by: current_user
    )
    AuditLog.record!(org: current_organization, user: current_user, action: "member.invited",
                     subject: invitation, details: { "role" => invitation.role })
    InvitationsMailer.invite(invitation).deliver_later
    redirect_to members_path, notice: "Đã tạo lời mời (xem preview email trong log/Mailpit)."
  end

  def revoke
    invitation = current_organization.invitations.find(params[:id])
    invitation.update!(revoked_at: Time.current)
    AuditLog.record!(org: current_organization, user: current_user, action: "member.invite_revoked", subject: invitation)
    redirect_to members_path, notice: "Đã thu hồi lời mời."
  end

  def update_role
    membership = current_organization.memberships.find(params[:id])
    membership.update!(role: params[:membership][:role])
    AuditLog.record!(org: current_organization, user: current_user, action: "member.role_changed",
                     subject: membership, details: { "new_role" => membership.role })
    redirect_to members_path, notice: "Đã đổi vai trò."
  end

  private

  def require_admin!
    return if policy_for.allowed?(:admin)
    redirect_to root_path, alert: "Chỉ owner/admin được quản lý thành viên."
  end
end
