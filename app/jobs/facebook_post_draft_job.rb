# Sinh bản nháp bài Facebook bằng AI ở nền (model thật mất 20-90 giây).
class FacebookPostDraftJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(connection_id:, user_id:, brief:, campaign_id: nil, tone: nil, goal: nil, artifact_id: nil)
    connection = FacebookPageConnection.find_by(id: connection_id)
    user = User.find_by(id: user_id)
    return if connection.nil? || user.nil?

    campaign = connection.organization.campaigns.find_by(id: campaign_id)
    artifact = campaign&.artifacts&.find_by(id: artifact_id)
    post = Ai::Workflows::FacebookPostDraft.call(connection: connection, user: user, brief: brief,
                                                 campaign: campaign, tone: tone, goal: goal, artifact: artifact)
    Notifications::Builder.notify(user: user, org: connection.organization, kind: "facebook_draft_ready",
                                  payload: { "facebook_post_id" => post.id, "title" => post.title })
  rescue StandardError => e
    Rails.logger.error("FacebookPostDraftJob thất bại: #{e.class}: #{e.message}")
    Notifications::Builder.notify(user: user, org: connection.organization, kind: "facebook_draft_failed",
                                  payload: { "error" => e.message.to_s.truncate(200) }) if user && connection
  end
end
