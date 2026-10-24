class InvitationsMailer < ApplicationMailer
  # Giao dịch email mời — dev dùng log/preview; production cấu hình SMTP/Resend qua ENV.
  def invite(invitation)
    @invitation = invitation
    @org = invitation.organization
    @accept_url = accept_invite_url(token: invitation.token)
    mail to: invitation.email, subject: "[MarketingOS] Lời mời vào #{@org.name}"
  end
end
