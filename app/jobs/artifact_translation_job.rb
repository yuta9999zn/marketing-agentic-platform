# Dịch artifact ở nền. Bài dài + model chạy trên máy có thể mất hàng chục giây.
# Không raise ra ngoài: lỗi thành notification để người dùng biết.
class ArtifactTranslationJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(artifact_id:, user_id:, target_locale:)
    source = Artifact.find_by(id: artifact_id)
    user = User.find_by(id: user_id)
    return if source.nil? || user.nil?

    translated = Translations::CreateService.call(source_artifact: source, user: user,
                                                  target_locale: target_locale)
    notify(source, user, "translation_ready",
           "artifact_id" => translated.id, "title" => translated.title)
  rescue StandardError => e
    Rails.logger.error("ArtifactTranslationJob thất bại: #{e.class}: #{e.message}")
    notify(source, user, "translation_failed", "error" => e.message.to_s.truncate(200)) if source && user
  end

  private

  def notify(source, user, kind, payload)
    Notification.create!(user: user, organization: source.campaign.organization, kind: kind,
                         payload: payload.merge("campaign" => source.campaign.name))
  rescue StandardError
    # best-effort
  end
end
