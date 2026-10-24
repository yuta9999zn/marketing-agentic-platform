# frozen_string_literal: true

module Ai
  module Workflows
    # Tạo bản nháp content plan (kênh × chủ đề × thời điểm) từ brief + persona.
    class ContentPlan
      SCHEMA = {
        "type" => "object",
        "required" => %w[items],
        "properties" => {
          "items" => {
            "type" => "array",
            "items" => {
              "type" => "object",
              "required" => %w[week channel topic format],
              "properties" => {
                "week" => { "type" => "integer" },
                "channel" => { "type" => "string" },
                "topic" => { "type" => "string" },
                "format" => { "type" => "string" }
              }
            }
          },
          "missing_data" => { "type" => "array", "items" => { "type" => "string" } }
        }
      }.freeze

      def self.call(campaign:, user:, consent_external: false)
        brief = campaign.artifact_of_kind("brief").last
        persona = campaign.artifact_of_kind("persona").last
        prompt = build_prompt(campaign, brief, persona)
        fake = fake_completion(persona)
        gw = Ai::Gateway.new(org: campaign.organization, user: user, fake_completion: fake)
        result = gw.generate_structured(prompt: prompt, task: "content.plan.draft",
                                        schema: SCHEMA, consent_external: consent_external)

        artifact = campaign.artifacts.create!(
          kind: "content_plan", title: "Content plan — #{campaign.name}",
          body: format_body(result), ai_generated: true, created_by: user,
          ai_metadata: {
            "source" => "ai_workflow:content_plan",
            "workflow" => "content_plan",
            "provider" => gw.provider_label,
            "prompt_sha" => Digest::SHA256.hexdigest(prompt),
            "generated_at" => Time.current.iso8601,
            "consent_external" => consent_external,
            "human_reviewed" => false,
            "based_on_brief_id" => brief&.id,
            "based_on_persona_id" => persona&.id
          }
        )
        AiRun.record!(org: campaign.organization, user: user, workflow: "content_plan",
                      provider: gw.provider_label, model: gw.model_label.to_s,
                      consent_status: consent_external ? "consented" : "not_required",
                      input_references: { "campaign_id" => campaign.id,
                                          "brief_id" => brief&.id, "persona_id" => persona&.id },
                      output_artifact: artifact)
        AuditLog.record!(org: campaign.organization, user: user, action: "ai.content_plan.drafted", subject: artifact)
        artifact
      end

      def self.build_prompt(campaign, brief, persona)
        <<~PROMPT
          Lập content plan 4 tuần cho campaign "#{campaign.name}".
          Dựa trên brief và persona dưới đây. Chỉ đề xuất kênh có trong persona; thiếu dữ liệu thì đưa vào missing_data.
          --- BRIEF ---
          #{brief&.body || "(chưa có)"}
          --- PERSONA ---
          #{persona&.body || "(chưa có)"}
          Trả về JSON đúng schema.
        PROMPT
      end

      def self.fake_completion(persona)
        channels = persona ? ["Facebook", "Email", "Google"] : ["Facebook", "Email"]
        ->(_prompt) do
          topics = [
            "Vấn đề & nỗi đau khách hàng", "Giải pháp & khác biệt", "Case study / bằng chứng",
            "Ưu đãi & CTA chuyển đổi"
          ]
          formats = ["bài viết dài + ảnh", "carousel", "video ngắn", "email newsletter"]
          items = (1..4).flat_map do |week|
            channels.map do |channel|
              { week: week, channel: channel,
                topic: "#{topics[week - 1]} (#{channel})",
                format: formats[(week + channels.index(channel)) % formats.size] }
            end
          end
          missing = persona ? [] : ["Chưa có persona — kế hoạch chỉ mang tính khung"]
          { items: items, missing_data: missing }.to_json
        end
      end

      def self.format_body(result)
        weeks = result["items"].group_by { |i| i["week"] }.sort
        <<~MD
          #{weeks.map { |week, items| "### Tuần #{week}\n#{items.map { |i| "- **#{i['channel']}** · #{i['topic']} (#{i['format']})" }.join("\n")}" }.join("\n\n")}

          #{result["missing_data"].present? ? "## ⚠️ Cần bổ sung\n#{result['missing_data'].map { |m| "- #{m}" }.join("\n")}" : ""}
        MD
      end
    end
  end
end
