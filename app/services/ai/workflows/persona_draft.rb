# frozen_string_literal: true

module Ai
  module Workflows
    # Tạo bản nháp persona từ brief + dữ liệu campaign. Draft only.
    class PersonaDraft
      SCHEMA = {
        "type" => "object",
        "required" => %w[name age_range occupation pains needs channels],
        "properties" => {
          "name" => { "type" => "string" },
          "age_range" => { "type" => "string" },
          "occupation" => { "type" => "string" },
          "pains" => { "type" => "array", "items" => { "type" => "string" } },
          "needs" => { "type" => "array", "items" => { "type" => "string" } },
          "channels" => { "type" => "array", "items" => { "type" => "string" } }
        }
      }.freeze

      def self.call(campaign:, user:, consent_external: false)
        brief = campaign.artifact_of_kind("brief").last
        prompt = build_prompt(campaign, brief)
        fake = fake_completion(campaign)
        gw = Ai::Gateway.new(org: campaign.organization, user: user, fake_completion: fake)
        result = gw.generate_structured(prompt: prompt, task: "persona.draft",
                                        schema: SCHEMA, consent_external: consent_external)

        artifact = campaign.artifacts.create!(
          kind: "persona", title: "Persona — #{result['name']}", body: format_body(result),
          ai_generated: true, created_by: user,
          ai_metadata: {
            "source" => "ai_workflow:persona_draft",
            "workflow" => "persona_draft",
            "provider" => gw.provider_label,
            "prompt_sha" => Digest::SHA256.hexdigest(prompt),
            "generated_at" => Time.current.iso8601,
            "consent_external" => consent_external,
            "human_reviewed" => false,
            "based_on_brief_id" => brief&.id
          }
        )
        AiRun.record!(org: campaign.organization, user: user, workflow: "persona_draft",
                      provider: gw.provider_label, model: gw.model_label.to_s,
                      consent_status: consent_external ? "consented" : "not_required",
                      input_references: { "campaign_id" => campaign.id,
                                          "brief_id" => brief&.id }, output_artifact: artifact)
        AuditLog.record!(org: campaign.organization, user: user, action: "ai.persona.drafted", subject: artifact)
        artifact
      end

      def self.build_prompt(campaign, brief)
        <<~PROMPT
          Dựa trên brief dưới đây, tạo MỘT persona khách hàng mục tiêu cho campaign "#{campaign.name}".
          Chỉ dùng thông tin có trong brief; thiếu thì ghi chung chung, không bịa số liệu định lượng.
          --- BRIEF ---
          #{brief&.body || "(chưa có brief — đây là rủi ro, hãy ghi rõ vàooccupation là 'cần bổ sung brief')"}
          Trả về JSON đúng schema.
        PROMPT
      end

      def self.fake_completion(campaign)
        industry = campaign.client.industry.presence || "thị trường của khách hàng"
        ->(_prompt) do
          {
            name: "Minh Anh — Khách hàng nghiên cứu kỹ",
            age_range: "28–38",
            occupation: "Chuyên viên quản lý / chủ doanh nghiệp nhỏ trong lĩnh vực #{industry}",
            pains: ["Thiếu thời gian tìm hiểu giải pháp", "Lo ngại chi phí không rõ ràng", "Nhiều lựa chọn gây nhiễu"],
            needs: ["Bằng chứng và case cụ thể", "So sánh giá trị rõ ràng", "Onboarding đơn giản"],
            channels: ["Facebook", "Zalo", "Email", "Tìm kiếm Google"]
          }.to_json
        end
      end

      def self.format_body(result)
        <<~MD
          **#{result['name']}** · #{result['age_range']} · #{result['occupation']}

          ### Nỗi đau
          #{result['pains'].map { |p| "- #{p}" }.join("\n")}

          ### Nhu cầu
          #{result['needs'].map { |n| "- #{n}" }.join("\n")}

          ### Kênh tiếp cận
          #{result['channels'].map { |c| "- #{c}" }.join("\n")}
        MD
      end
    end
  end
end
