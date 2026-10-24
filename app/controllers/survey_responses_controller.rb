# Nộp phản hồi khảo sát. Người trả lời phải xem được campaign (khách hàng được
# mời cũng trả lời được) — khảo sát nội bộ, không phải form công khai.
class SurveyResponsesController < ApplicationController
  def create
    survey = Survey.joins(:campaign)
                   .where(campaigns: { organization_id: current_organization.id })
                   .find(params[:survey_id])
    return unless require_role!(:view, subject: survey.campaign)

    response = survey.survey_responses.new(
      answers: SurveyResponse.sanitize_answers(survey, permitted_answers(survey)),
      respondent_label: params[:respondent_label].presence || current_user.name
    )

    if response.save
      redirect_to survey_path(survey), notice: t("marketingos.survey.response_saved")
    else
      redirect_to survey_path(survey), alert: response.errors.full_messages.to_sentence
    end
  end

  private

  # Chỉ permit đúng khóa câu hỏi của survey này — khóa lạ bị loại ngay ở tầng params.
  def permitted_answers(survey)
    keys = survey.question_list.map { |q| q["key"] }
    raw = params[:answers]
    return {} unless raw.is_a?(ActionController::Parameters)

    raw.permit(*keys).to_h
  end
end
