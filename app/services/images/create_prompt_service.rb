# frozen_string_literal: true

module Images
  # Image studio: đóng gói prompt + metadata thành artifact image_prompt.
  # Fake adapter — không render ảnh, không gửi dữ liệu ra ngoài.
  class CreatePromptService
    def self.call(campaign:, user:, brand:, objective:, audience:, channel:,
                  dimensions:, style:, exclusions: "")
      adapter = Providers::AdapterFactory.image_for(org: campaign.organization, user: user)
      prompt = [brand, objective, audience].compact_blank.join(". ")
      result = adapter.generate(prompt: prompt, dimensions: dimensions, style: style,
                                exclusions: exclusions.to_s.split(/[,;]/).map(&:strip).compact_blank)

      artifact = campaign.artifacts.create!(
        kind: "image_prompt", title: "Image prompt — #{brand} (#{channel.presence || 'general'})",
        body: result["final_prompt"] + "\n\n" + result["note"],
        channel: channel, created_by: user, ai_generated: true,
        ai_metadata: {
          "source" => "ai_workflow:image_prompt",
          "workflow" => "image_prompt",
          "provider" => adapter.provider_name,
          "generated_at" => Time.current.iso8601,
          "human_reviewed" => false,
          "dimensions" => dimensions,
          "style" => style,
          "exclusions" => exclusions,
          "brand" => brand,
          "approval_required_before_export" => true,
          "enhanced_by_llm" => result["enhanced_by_llm"] || false,
          "licensing_note" => "Kiểm tra quyền sử dụng asset trước khi xuất bản."
        }
      )
      AiRun.record!(org: campaign.organization, user: user, workflow: "image_prompt",
                    provider: adapter.provider_name,
                    model: Ai::Gateway.local_provider? ? Ai::Gateway.ollama_model : "offline-placeholder",
                    input_references: { "campaign_id" => campaign.id }, output_artifact: artifact)
      artifact
    end
  end
end
