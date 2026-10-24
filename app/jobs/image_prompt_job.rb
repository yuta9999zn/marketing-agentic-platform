# Soạn prompt ảnh ở nền. Với model chạy trên máy, riêng bước này mất ~50 giây
# nên không thể chạy trong request web.
class ImagePromptJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(campaign_id:, user_id:, options: {})
    campaign = Campaign.find_by(id: campaign_id)
    user = User.find_by(id: user_id)
    return if campaign.nil? || user.nil?

    opts = options.symbolize_keys
    artifact = Images::CreatePromptService.call(
      campaign: campaign, user: user,
      brand: opts[:brand], objective: opts[:objective], audience: opts[:audience],
      channel: opts[:channel], dimensions: opts[:dimensions], style: opts[:style],
      exclusions: opts[:exclusions].to_s
    )
    notify(campaign, user, "image_prompt_ready",
           "artifact_id" => artifact.id, "title" => artifact.title)
  rescue StandardError => e
    Rails.logger.error("ImagePromptJob thất bại: #{e.class}: #{e.message}")
    notify(campaign, user, "image_prompt_failed", "error" => e.message.to_s.truncate(200)) if campaign && user
  end

  private

  def notify(campaign, user, kind, payload)
    Notification.create!(user: user, organization: campaign.organization, kind: kind,
                         payload: payload.merge("campaign" => campaign.name,
                                                "campaign_id" => campaign.id))
  rescue StandardError
    # best-effort
  end
end
