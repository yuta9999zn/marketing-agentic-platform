class SurveyResponse < ApplicationRecord
  belongs_to :survey

  validate :survey_accepting_responses, on: :create
  validate :answers_not_empty

  # Chỉ giữ câu trả lời khớp khóa câu hỏi của survey — bỏ mọi khóa lạ gửi kèm.
  def self.sanitize_answers(survey, raw)
    allowed = survey.question_list.map { |q| q["key"] }
    raw.to_h.slice(*allowed).transform_values { |v| v.to_s.strip }.reject { |_, v| v.blank? }
  end

  private

  def survey_accepting_responses
    errors.add(:base, "Khảo sát chưa mở nhận phản hồi.") unless survey&.open?
  end

  def answers_not_empty
    errors.add(:answers, "chưa có câu trả lời nào") if answers.blank?
  end
end
