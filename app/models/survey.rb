class Survey < ApplicationRecord
  STATUSES = %w[draft open closed].freeze
  QUESTION_KINDS = %w[text choice scale].freeze

  belongs_to :campaign
  belongs_to :created_by, class_name: "User", optional: true
  has_many :survey_responses, dependent: :destroy

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :questions_well_formed

  scope :open_now, -> { where(status: "open") }

  def open? = status == "open"
  def response_count = survey_responses.count

  # Câu hỏi dạng [{ "key" =>, "label" =>, "kind" => }]. Key dùng làm khóa trong
  # answers nên phải ổn định và không trùng.
  def question_list
    Array(questions).filter_map do |q|
      next unless q.is_a?(Hash) && q["label"].present?

      { "key" => q["key"].presence || q["label"].to_s.parameterize.underscore,
        "label" => q["label"].to_s,
        "kind" => QUESTION_KINDS.include?(q["kind"]) ? q["kind"] : "text" }
    end
  end

  private

  def questions_well_formed
    return if questions.blank?

    errors.add(:questions, "phải là danh sách câu hỏi") unless questions.is_a?(Array)
    return unless questions.is_a?(Array)

    keys = question_list.map { |q| q["key"] }
    errors.add(:questions, "có câu hỏi trùng khóa") if keys.uniq.size != keys.size
  end
end
