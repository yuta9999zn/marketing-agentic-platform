# Khảo sát gắn với campaign: tạo, mở/đóng, xem kết quả, và cho AI phân tích
# thành insight. Mọi truy vấn scope qua campaign trong organization hiện tại.
class SurveysController < ApplicationController
  before_action :set_campaign, only: %i[create]
  before_action :set_survey, only: %i[show update analyse]

  def show
    return unless require_role!(:view, subject: @survey.campaign)
    @responses = @survey.survey_responses.order(created_at: :desc)
  end

  def create
    return unless require_internal! && require_role!(:edit, subject: @campaign)

    survey = @campaign.surveys.new(title: params[:title], description: params[:description],
                                   created_by: current_user, questions: parsed_questions)
    if survey.save
      AuditLog.record!(org: current_organization, user: current_user,
                       action: "survey.created", subject: survey)
      redirect_to survey_path(survey), notice: t("marketingos.survey.created")
    else
      redirect_to campaign_path(@campaign, anchor: "surveys"),
                  alert: survey.errors.full_messages.to_sentence
    end
  end

  # Đổi trạng thái draft → open → closed.
  def update
    return unless require_internal! && require_role!(:edit, subject: @survey.campaign)

    status = params[:status].to_s
    return redirect_to survey_path(@survey), alert: t("marketingos.survey.bad_status") unless
      Survey::STATUSES.include?(status)

    @survey.update!(status: status)
    AuditLog.record!(org: current_organization, user: current_user,
                     action: "survey.status_changed", subject: @survey,
                     details: { "status" => status })
    redirect_to survey_path(@survey), notice: t("marketingos.survey.status_updated")
  end

  # AI đọc phản hồi thật và viết bản phân tích — luôn là draft chờ duyệt.
  def analyse
    return unless require_internal! && require_role!(:edit, subject: @survey.campaign)
    if @survey.response_count.zero?
      return redirect_to survey_path(@survey), alert: t("marketingos.survey.no_data")
    end

    unless Ai::Gateway.synchronous?
      status = Ai::Availability.status
      unless status.ready?
        return redirect_to survey_path(@survey),
                           alert: t("marketingos.ai.not_ready",
                                    detail: t("marketingos.ai_status.#{status.detail}",
                                              default: t("marketingos.ai_status.unreachable")))
      end

      AiDraftJob.perform_later(kind: "survey_insight", campaign_id: @survey.campaign_id,
                               user_id: current_user.id, survey_id: @survey.id)
      return redirect_to survey_path(@survey), notice: t("marketingos.ai.queued", model: status.model)
    end

    artifact = Ai::Workflows::SurveyInsight.call(survey: @survey, user: current_user)
    redirect_to artifact_path(artifact), notice: t("marketingos.survey.analysed")
  rescue ArgumentError => e
    redirect_to survey_path(@survey), alert: e.message
  rescue CDFLHarness::Errors::Error => e
    redirect_to survey_path(@survey),
                alert: t("marketingos.survey.ai_failed", detail: e.message)
  end

  private

  def set_campaign
    @campaign = Campaign.in_org(current_organization).find(params[:campaign_id])
  end

  def set_survey
    @survey = Survey.joins(:campaign)
                    .where(campaigns: { organization_id: current_organization.id })
                    .find(params[:id])
  end

  # Câu hỏi nhập dạng mỗi dòng một câu; khóa sinh từ nội dung để ổn định.
  def parsed_questions
    params[:questions].to_s.split(/\r?\n/).map(&:strip).reject(&:blank?).map do |line|
      { "key" => line.parameterize.underscore.presence || SecureRandom.hex(4),
        "label" => line, "kind" => "text" }
    end
  end
end
