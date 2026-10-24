# frozen_string_literal: true

module Ai
  module Workflows
    # Sinh bài Facebook: caption + hashtag + CTA + gợi ý ảnh. Đi qua Ai::Gateway
    # (chokepoint, fake adapter offline khi AI_PROVIDER=fake). Kết quả LUÔN là
    # FacebookPost ở trạng thái draft — không bao giờ tự đăng.
    class FacebookPostDraft
      SCHEMA = {
        "type" => "object",
        "required" => %w[caption hashtags call_to_action image_suggestions missing_data],
        "properties" => {
          "title" => { "type" => "string" },
          "caption" => { "type" => "string", "minLength" => 30 },
          "hashtags" => { "type" => "array", "items" => { "type" => "string" } },
          "call_to_action" => { "type" => "string" },
          "image_suggestions" => { "type" => "array", "items" => { "type" => "string" } },
          "missing_data" => { "type" => "array", "items" => { "type" => "string" } }
        }
      }.freeze

      def self.call(connection:, user:, brief:, campaign: nil, tone: nil, goal: nil, artifact: nil)
        org = connection.organization
        prompt = build_prompt(connection, campaign, brief, tone, goal, artifact)
        gw = Ai::Gateway.new(org: org, user: user, fake_completion: fake_completion(connection, campaign, brief, goal))
        result = gw.generate_structured(prompt: prompt, task: "facebook.post.draft", schema: SCHEMA, consent_external: false)

        caption = result["caption"].to_s.strip
        raise CDFLHarness::Errors::StructuredOutputError, "Model trả về caption rỗng." if caption.blank?

        hashtags = Array(result["hashtags"]).map { |h| h.to_s.strip.sub(/\A#?/, "#").delete(" ") }.reject { |h| h == "#" }.uniq.first(10)
        cta = result["call_to_action"].to_s.strip
        message = [ caption, cta.presence, hashtags.join(" ").presence ].compact.join("\n\n")

        post = FacebookPost.create!(
          organization: org, facebook_page_connection: connection, campaign: campaign, artifact: artifact,
          created_by: user, status: "draft", post_type: "text", timezone: Time.zone.name,
          title: result["title"].presence || brief.to_s.truncate(70),
          message: message, ai_generated: true,
          ai_metadata: {
            "source" => "ai_workflow:facebook_post_draft", "provider" => gw.provider_label,
            "model" => gw.model_label.to_s, "prompt_sha" => Digest::SHA256.hexdigest(prompt),
            "generated_at" => Time.current.iso8601, "brief" => brief.to_s.truncate(500),
            "tone" => tone, "goal" => goal, "hashtags" => hashtags, "call_to_action" => cta,
            "image_suggestions" => Array(result["image_suggestions"]).first(5),
            "missing_data" => Array(result["missing_data"]), "human_reviewed" => false
          }
        )
        AiRun.record!(org: org, user: user, workflow: "facebook_post_draft", provider: gw.provider_label,
                      model: gw.model_label.to_s,
                      input_references: { "campaign_id" => campaign&.id, "facebook_post_id" => post.id,
                                          "artifact_id" => artifact&.id }.compact)
        AuditLog.record!(org: org, user: user, action: "facebook.post.ai_drafted", subject: post,
                         details: { "provider" => gw.provider_label })
        post
      end

      def self.build_prompt(connection, campaign, brief, tone, goal, artifact)
        <<~PROMPT
          Viết một bài đăng Facebook cho Page "#{connection.page_name}"#{campaign ? " trong campaign \"#{campaign.name}\" (thương hiệu #{campaign.client.name})" : ''}.
          Yêu cầu/chủ đề: #{brief}
          #{"Mục tiêu: #{goal}" if goal.present?}
          #{"Giọng điệu: #{tone}" if tone.present?}
          #{"--- NỘI DUNG GỐC ---\n#{artifact.body.to_s.truncate(3000)}" if artifact}
          #{"--- MỤC TIÊU CAMPAIGN ---\n#{campaign.objective}" if campaign&.objective.present?}

          Quy tắc:
          - caption: 80-400 chữ, mở đầu bằng câu hook, chia đoạn ngắn, có thể dùng 1-3 emoji phù hợp.
          - hashtags: 3-8 hashtag tiếng Việt không dấu hoặc tiếng Anh, liên quan trực tiếp.
          - call_to_action: một câu kêu gọi hành động rõ ràng.
          - image_suggestions: 2-3 mô tả ảnh/ý tưởng hình ảnh đi kèm.
          - Không bịa số liệu, giá, khuyến mãi; thiếu thông tin thì ghi vào missing_data.
          - Không nội dung vi phạm chính sách Meta (lừa đảo, y tế sai lệch, kỳ thị, trước/sau...).
          Viết TOÀN BỘ bằng tiếng Việt.

          Trả về DUY NHẤT một object JSON:
          {"title": "tên ngắn", "caption": "...", "hashtags": ["#..."], "call_to_action": "...", "image_suggestions": ["..."], "missing_data": ["..."]}
        PROMPT
      end

      # Bỏ dấu tiếng Việt để làm hashtag (I18n.transliterate mặc định làm mất ư/ơ/đ).
      def self.hashtag_slug(text)
        str = text.to_s.dup
        str.force_encoding(Encoding::UTF_8) unless str.encoding == Encoding::UTF_8
        str.scrub.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").tr("đĐ", "dD").parameterize.delete("-")
      end

      def self.fake_completion(connection, campaign, brief, goal)
        ->(_prompt) do
          brand = campaign&.client&.name || connection.page_name
          topic = brief.to_s.strip.presence || "chủ đề của tuần"
          {
            title: "Bài đăng: #{topic.truncate(50)}",
            caption: "✨ #{topic.capitalize} cùng #{brand}!\n\nBạn đang tìm một giải pháp thật sự phù hợp? " \
                     "Đội ngũ #{brand} đã chuẩn bị sẵn những điều bạn cần — rõ ràng, nhanh chóng và đáng tin cậy.\n\n" \
                     "#{goal.present? ? "Mục tiêu của chúng tôi: #{goal}." : 'Hãy cho chúng tôi biết bạn quan tâm điều gì nhất.'}",
            hashtags: [ "##{hashtag_slug(brand)}", "#marketing", "##{hashtag_slug(topic).first(30)}" ],
            call_to_action: "👉 Nhắn tin cho #{brand} ngay hôm nay để được tư vấn.",
            image_suggestions: [ "Ảnh sản phẩm/dịch vụ nổi bật trên nền sáng, logo #{brand} góc dưới",
                                "Ảnh khách hàng đang sử dụng dịch vụ, cảm xúc tích cực" ],
            missing_data: campaign ? [] : [ "Chưa gắn campaign — thiếu brief và persona để cá nhân hoá nội dung" ]
          }.to_json
        end
      end
    end
  end
end
