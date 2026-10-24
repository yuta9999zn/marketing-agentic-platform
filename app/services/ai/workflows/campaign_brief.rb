# frozen_string_literal: true

module Ai
  module Workflows
    # Tạo bản nháp campaign brief có cấu trúc. Luôn là DRAFT — con người duyệt cuối.
    class CampaignBrief
      SCHEMA = {
        "type" => "object",
        "required" => %w[background objectives audience key_messages deliverables missing_data],
        "properties" => {
          "background" => { "type" => "string" },
          "objectives" => { "type" => "array", "items" => { "type" => "string" } },
          "audience" => { "type" => "string" },
          "key_messages" => { "type" => "array", "items" => { "type" => "string" } },
          "deliverables" => { "type" => "array", "items" => { "type" => "string" } },
          "missing_data" => { "type" => "array", "items" => { "type" => "string" } }
        }
      }.freeze

      def self.call(campaign:, user:, consent_external: false)
        prompt = build_prompt(campaign)
        fake = fake_completion(campaign)
        gw = Ai::Gateway.new(org: campaign.organization, user: user, fake_completion: fake)
        result = gw.generate_structured(prompt: prompt, task: "campaign.brief.draft",
                                        schema: SCHEMA, consent_external: consent_external)

        body = format_body(result)
        artifact = campaign.artifacts.create!(
          kind: "brief", title: "Brief — #{campaign.name}", body: body,
          ai_generated: true, created_by: user,
          ai_metadata: {
            "source" => "ai_workflow:campaign_brief",
            "workflow" => "campaign_brief",
            "provider" => gw.provider_label,
            "task" => "campaign.brief.draft",
            "prompt_sha" => Digest::SHA256.hexdigest(prompt),
            "generated_at" => Time.current.iso8601,
            "consent_external" => consent_external,
            "human_reviewed" => false,
            "missing_data" => result["missing_data"]
          }
        )
        AiRun.record!(org: campaign.organization, user: user, workflow: "campaign_brief",
                      provider: gw.provider_label, model: gw.model_label.to_s,
                      consent_status: consent_external ? "consented" : "not_required",
                      input_references: { "campaign_id" => campaign.id }, output_artifact: artifact)
        AuditLog.record!(org: campaign.organization, user: user, action: "ai.brief.drafted",
                         subject: artifact, details: { "campaign_id" => campaign.id })
        artifact
      end

      def self.build_prompt(campaign)
        <<~PROMPT
          Bạn là strategist marketing. Soạn bản nháp brief cho campaign sau, tiếng Việt, ngắn gọn, cụ thể.
          Nếu thiếu dữ liệu đầu vào, liệt kê rõ vào missing_data thay vì bịa số liệu.
          Tên campaign: #{campaign.name}
          Mục tiêu tổng quát: #{campaign.objective.presence || "(chưa có)"}
          Khách hàng: #{campaign.client.name} — ngành #{campaign.client.industry.presence || "không rõ"}
          Thời gian: #{campaign.start_date} → #{campaign.end_date}
          Trạng thái: #{campaign.status}
          Trả về JSON đúng schema.
        PROMPT
      end

      def self.fake_completion(campaign)
        # Offline deterministic draft — mô phỏng "AI tạo nháp + chỉ ra thiếu dữ liệu".
        ->(_prompt) do
          {
            background: "Bối cảnh: #{campaign.client.name} cần một chiến dịch marketing tích hợp cho \"#{campaign.name}\".",
            objectives: [
              "Tăng nhận diện thương hiệu trong phân khúc #{campaign.client.industry.presence || 'mục tiêu'}",
              "Tạo lead/chuyển đổi đo được trong thời gian campaign",
              campaign.objective.presence || "Đạt mục tiêu tổng quát đã nêu"
            ].compact,
            audience: "Khách hàng mục tiêu 25–40 tuổi, quan tâm #{campaign.client.industry.presence || 'lĩnh vực của khách hàng'}.",
            key_messages: [
              "Thông điệp chính: giá trị cốt lõi của #{campaign.client.name}",
              "Thông điệp phụ: bằng chứng/kết quả cụ thể",
              "CTA: hành động rõ ràng, một bước"
            ],
            deliverables: ["Content plan 4 tuần", "Bộ bài đăng social", "Landing page brief", "Kịch bản email"],
            missing_data: [].tap { |m|
              m << "Chưa có mục tiêu định lượng (KPI)" if campaign.objective.blank?
              m << "Chưa có ngân sách" if campaign.objective.to_s !~ /ngân sách/i
              m << "Chưa có thời gian cụ thể" if campaign.start_date.blank? || campaign.end_date.blank?
            }
          }.to_json
        end
      end

      def self.format_body(result)
        <<~MD
          ## Bối cảnh
          #{result["background"]}

          ## Mục tiêu
          #{result["objectives"].map { |o| "- #{o}" }.join("\n")}

          ## Đối tượng
          #{result["audience"]}

          ## Thông điệp chính
          #{result["key_messages"].map { |m| "- #{m}" }.join("\n")}

          ## Deliverables
          #{result["deliverables"].map { |d| "- #{d}" }.join("\n")}

          ## ⚠️ Dữ liệu còn thiếu (AI không tự bổ sung)
          #{(result["missing_data"].presence || ["Không phát hiện"]).map { |m| "- #{m}" }.join("\n")}
        MD
      end
    end
  end
end
