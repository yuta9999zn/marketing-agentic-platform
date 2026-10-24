class AiRun < ApplicationRecord
  # Audit mức workflow (bổ sung cho ai_calls mức gateway — ai_calls chỉ có hash).
  belongs_to :organization
  belongs_to :user, optional: true
  belongs_to :output_artifact, class_name: "Artifact", optional: true

  validates :workflow, :provider, :model, presence: true

  def self.record!(org:, user: nil, workflow:, provider:, model:, consent_status: "not_required",
                   prompt_template_version: nil, input_references: {}, output_artifact: nil)
    create!(organization: org, user: user, workflow: workflow, provider: provider, model: model,
            consent_status: consent_status, prompt_template_version: prompt_template_version,
            input_references: input_references, output_artifact: output_artifact)
  end
end
