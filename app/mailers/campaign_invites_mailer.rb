class CampaignInvitesMailer < ApplicationMailer
  # Dev: adapter test/log — preview only, không gửi thật.
  def invite(token)
    @token = token
    @campaign = token.campaign
    @accept_url = accept_campaign_invite_url(token: token.token)
    mail to: token.email, subject: "[MarketingOS] Mời duyệt campaign #{@campaign.name}"
  end
end
