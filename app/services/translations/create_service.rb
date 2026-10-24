# frozen_string_literal: true

module Translations
  # Tạo artifact bản dịch từ artifact nguồn. Adapter do AdapterFactory chọn:
  # LLM chạy trên máy khi AI_PROVIDER=ollama, ngược lại là bản offline
  # deterministic. Kết quả LUÔN là bản nháp chờ người duyệt.
  class CreateService
    def self.call(source_artifact:, user:, target_locale:, glossary: {})
      org = source_artifact.campaign.organization
      adapter = Providers::AdapterFactory.translation_for(org: org, user: user)
      result = adapter.translate(text: source_artifact.body.to_s,
                                 source: source_artifact.locale || "vi",
                                 target: target_locale, glossary: glossary)

      artifact = source_artifact.campaign.artifacts.create!(
        kind: "translation",
        title: "#{source_artifact.title} [#{target_locale.upcase}]",
        body: result, locale: target_locale,
        channel: source_artifact.channel, created_by: user,
        ai_generated: true,
        ai_metadata: {
          "source" => "ai_workflow:translation",
          "workflow" => "translation",
          "provider" => adapter.provider_name,
          "generated_at" => Time.current.iso8601,
          "human_reviewed" => false,
          "source_artifact_id" => source_artifact.id,
          "source_version" => source_artifact.version,
          "target_locale" => target_locale
        }
      )
      AiRun.record!(org: org, user: user, workflow: "translation",
                    provider: adapter.provider_name, model: model_label,
                    input_references: { "source_artifact_id" => source_artifact.id },
                    output_artifact: artifact)
      artifact
    end

    def self.model_label
      Ai::Gateway.local_provider? ? Ai::Gateway.ollama_model : "deterministic-glossary"
    end
  end
end
