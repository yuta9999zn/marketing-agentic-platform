# frozen_string_literal: true

module Ai
  module Workflows
    # Nháp kịch bản/content theo loại (social_post, video_script, email, ad_copy...).
    # Dựa trên brief + persona đã có; offline deterministic; luôn draft chờ duyệt.
    class ScriptDraft
      SCRIPT_KINDS = %w[social_post video_script event_run_of_show email landing_page
                        ad_copy storyboard report].freeze
      # minLength quan trọng: model nhỏ đôi khi trả content rỗng — vẫn hợp lệ
      # kiểu dữ liệu nhưng vô dụng. Ràng buộc này khiến harness chạy vòng repair
      # thay vì tạo ra một bản nháp trống.
      MIN_CONTENT_CHARS = 40

      SCHEMA = {
        "type" => "object",
        "required" => %w[content missing_data],
        "properties" => {
          "content" => { "type" => "string", "minLength" => MIN_CONTENT_CHARS },
          "missing_data" => { "type" => "array", "items" => { "type" => "string" } }
        }
      }.freeze

      def self.call(campaign:, user:, kind:, channel: nil, prompt_template: nil)
        brief = campaign.artifact_of_kind("brief").last
        persona = campaign.artifact_of_kind("persona").last
        prompt = build_prompt(campaign, kind, brief, persona, channel, prompt_template)
        fake = fake_completion(campaign, kind, channel)
        gw = Ai::Gateway.new(org: campaign.organization, user: user, fake_completion: fake)
        result = gw.generate_structured(prompt: prompt, task: "script.draft.#{kind}",
                                        schema: SCHEMA, consent_external: false)

        # Chốt chặn cuối: thà báo lỗi rõ ràng còn hơn lưu một bản nháp rỗng.
        if result["content"].to_s.strip.blank?
          raise CDFLHarness::Errors::StructuredOutputError,
                "Model trả về nội dung rỗng — không tạo bản nháp trống."
        end

        artifact = campaign.artifacts.create!(
          kind: kind, channel: channel,
          title: "#{kind_label(kind)} — #{campaign.name}#{channel ? " (#{channel})" : ''}",
          body: result["content"], ai_generated: true, created_by: user,
          ai_metadata: {
            "source" => "ai_workflow:script_draft",
            "workflow" => "script_draft",
            "provider" => gw.provider_label,
            "prompt_sha" => Digest::SHA256.hexdigest(prompt),
            "generated_at" => Time.current.iso8601,
            "consent_external" => false,
            "human_reviewed" => false,
            "missing_data" => result["missing_data"],
            "based_on_brief_id" => brief&.id,
            "based_on_persona_id" => persona&.id,
            "prompt_template_id" => prompt_template&.id,
            "prompt_template_version" => prompt_template && "#{prompt_template.name} v#{prompt_template.version}"
          }
        )
        AiRun.record!(org: campaign.organization, user: user, workflow: "script_draft",
                      provider: gw.provider_label, model: gw.model_label.to_s,
                      prompt_template_version: prompt_template && "#{prompt_template.name} v#{prompt_template.version}",
                      input_references: { "campaign_id" => campaign.id, "kind" => kind,
                                          "prompt_template_id" => prompt_template&.id }.compact,
                      output_artifact: artifact)
        AuditLog.record!(org: campaign.organization, user: user, action: "ai.script.drafted", subject: artifact)
        artifact
      end

      def self.kind_label(kind)
        kind.humanize.titleize
      end

      # Prompt template (nếu người dùng chọn) chèn hướng dẫn + format đầu ra của
      # workspace vào giữa; ràng buộc "không bịa số liệu" luôn giữ nguyên ở cuối
      # để template không ghi đè được invariant decline-not-hallucinate.
      def self.build_prompt(campaign, kind, brief, persona, channel, prompt_template = nil)
        template_block =
          if prompt_template
            <<~TPL
              --- HƯỚNG DẪN THEO TEMPLATE "#{prompt_template.name}" (v#{prompt_template.version}) ---
              #{prompt_template.instructions}
              #{"--- ĐỊNH DẠNG ĐẦU RA ---\n#{prompt_template.output_format}" if prompt_template.output_format.present?}
            TPL
          end

        <<~PROMPT
          Viết bản nháp #{kind.humanize} cho campaign "#{campaign.name}"#{channel ? " trên kênh #{channel}" : ''}.
          Thương hiệu: #{campaign.client.name}.
          #{"Mục tiêu: #{campaign.objective}" if campaign.objective.present?}
          --- BRIEF ---
          #{brief&.body.presence || "(chưa có)"}
          --- PERSONA ---
          #{persona&.body.presence || "(chưa có)"}
          #{template_block}
          Chỉ dùng thông tin có trong brief/persona ở trên; thiếu thì đưa vào missing_data, không bịa số liệu.

          Viết TOÀN BỘ bằng tiếng Việt, kể cả các mục trong missing_data.
          Trường "content" phải là nội dung hoàn chỉnh dùng được, dài ít nhất
          #{MIN_CONTENT_CHARS} ký tự — không được để trống.

          Trả về DUY NHẤT một object JSON đúng dạng:
          {"content": "nội dung đầy đủ ở đây", "missing_data": ["thông tin còn thiếu"]}
        PROMPT
      end

      def self.fake_completion(campaign, kind, channel)
        ->(_prompt) do
          brand = campaign.client.name
          obj = campaign.objective.presence || "mục tiêu campaign"
          content =
            case kind
            when "video_script"
              <<~TXT
                ## Mở đầu (0-3s)
                Hook: "Bạn đã bao giờ #{brand} khiến một buổi chiều bận rộn dễ chịu hơn?"
                ## Thân (3-20s)
                - Vấn đề: khách hàng thiếu thời gian, cần giải pháp nhanh.
                - Giải pháp: sản phẩm/dịch vụ của #{brand} đáp ứng #{obj}.
                - Bằng chứng: số liệu/case lấy từ brief (nếu chưa có → missing_data).
                ## Kết (20-30s)
                CTA: "Thử ngay hôm nay — link ở bio."
                Ghi chú sản xuất: quay dọc 9:16, phụ đề tiếng Việt.
              TXT
            when "email"
              <<~TXT
                Subject: #{brand} — #{obj}
                Preview: Một giải pháp dành cho bạn tuần này.
                Body:
                Chào {tên},
                (Mở đầu theo persona) ...
                (Giá trị chính + bằng chứng) ...
                CTA: một hành động rõ ràng.
                Footer: unsubscribe.
              TXT
            when "ad_copy"
              <<~TXT
                Headline: #{obj} cùng #{brand}
                Primary text: (đau khăn) → (giải pháp) → (CTA)
                CTA button: Tìm hiểu thêm
                3 biến thể A/B đề xuất.
              TXT
            else # social_post và các loại khác
              <<~TXT
                🎯 Chủ đề: #{obj}
                (Bài đăng #{kind}#{channel ? " cho #{channel}" : ''})
                - Ý chính 1 theo thông điệp brief
                - Ý chính 2 gắn nỗi đau persona
                - CTA rõ ràng
                Hashtag: ##{brand.parameterize}
                Lưu ý: số liệu cụ thể cần lấy từ brief — xem missing_data.
              TXT
            end
          missing = []
          missing << "Chưa có brief được duyệt" unless campaign.artifacts.where(kind: "brief", approval_status: "approved").exists?
          missing << "Chưa có persona" unless campaign.artifacts.where(kind: "persona").exists?
          { content: content, missing_data: missing }.to_json
        end
      end
    end
  end
end
