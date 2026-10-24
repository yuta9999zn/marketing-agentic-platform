# Chạy workflow AI ở nền. Model chạy trên máy mất 20-90 giây nên không thể
# chạy trong request web.
#
# Job KHÔNG raise ra ngoài: mọi lỗi đều thành notification cho người dùng —
# thất bại phải nhìn thấy được, không được im lặng.
class AiDraftJob < ApplicationJob
  queue_as :default

  # Không retry: sinh nội dung không idempotent, chạy lại sẽ tạo bản nháp trùng.
  discard_on ActiveJob::DeserializationError

  def perform(kind:, campaign_id:, user_id:, channel: nil, prompt_template_id: nil, survey_id: nil)
    campaign = Campaign.find_by(id: campaign_id)
    user = User.find_by(id: user_id)
    return if campaign.nil? || user.nil?

    artifact = generate(kind: kind, campaign: campaign, user: user, channel: channel,
                        prompt_template_id: prompt_template_id, survey_id: survey_id)
    return if artifact.nil?

    notify(campaign, user, "ai_draft_ready",
           "artifact_id" => artifact.id, "title" => artifact.title, "kind" => artifact.kind)
  rescue StandardError => e
    Rails.logger.error("AiDraftJob thất bại: #{e.class}: #{e.message}")
    notify(campaign, user, "ai_draft_failed",
           "kind" => kind, "error" => e.message.to_s.truncate(200)) if campaign && user
  end

  private

  def generate(kind:, campaign:, user:, channel:, prompt_template_id:, survey_id:)
    case kind
    when "brief"        then Ai::Workflows::CampaignBrief.call(campaign: campaign, user: user, consent_external: false)
    when "persona"      then Ai::Workflows::PersonaDraft.call(campaign: campaign, user: user, consent_external: false)
    when "content_plan" then Ai::Workflows::ContentPlan.call(campaign: campaign, user: user, consent_external: false)
    when "survey_insight"
      survey = campaign.surveys.find_by(id: survey_id)
      survey && Ai::Workflows::SurveyInsight.call(survey: survey, user: user)
    when *Ai::Workflows::ScriptDraft::SCRIPT_KINDS
      template = PromptTemplate.in_org(campaign.organization).find_by(id: prompt_template_id)
      Ai::Workflows::ScriptDraft.call(campaign: campaign, user: user, kind: kind,
                                      channel: channel, prompt_template: template)
    end
  end

  def notify(campaign, user, kind, payload)
    Notification.create!(user: user, organization: campaign.organization, kind: kind,
                         payload: payload.merge("campaign" => campaign.name,
                                                "campaign_id" => campaign.id))
  rescue StandardError
    # Notification là best-effort — không để nó nuốt kết quả đã sinh được.
  end
end
