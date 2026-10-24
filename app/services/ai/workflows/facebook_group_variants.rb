# frozen_string_literal: true

module Ai
  module Workflows
    # Viết mỗi nhóm một phiên bản hơi khác của bài Page, để cùng một nội dung
    # không bị đăng y hệt vào nhiều nhóm (Facebook giảm hiển thị nội dung trùng).
    #
    # Giữ nguyên dữ kiện (giá, địa chỉ, SĐT...), chỉ đổi câu mở đầu, cách diễn đạt
    # và hashtag; tôn trọng luật từng nhóm (vd nhóm cấm link → không chèn link).
    # Kết quả chỉ là gợi ý: người dùng xem lại trước khi tự đăng.
    class FacebookGroupVariants
      SCHEMA = {
        "type" => "object",
        "required" => %w[variants],
        "properties" => {
          "variants" => {
            "type" => "array",
            "items" => {
              "type" => "object",
              "required" => %w[index message],
              "properties" => { "index" => { "type" => "integer" }, "message" => { "type" => "string", "minLength" => 20 } }
            }
          }
        }
      }.freeze

      OPENERS = [ "📢", "🏡", "✨", "👉", "🔥", "📍" ].freeze

      def self.call(shares:, user:)
        shares = shares.select(&:pending?)
        return [] if shares.empty?

        post = shares.first.facebook_post
        org = post.organization
        prompt = build_prompt(post, shares)
        gw = Ai::Gateway.new(org: org, user: user, fake_completion: fake_completion(post, shares))
        result = gw.generate_structured(prompt: prompt, task: "facebook.group.variants", schema: SCHEMA, consent_external: false)

        by_index = Array(result["variants"]).to_h { |v| [ v["index"].to_i, v["message"].to_s.strip ] }
        updated = []
        shares.each_with_index do |share, i|
          text = by_index[i + 1]
          next if text.blank?

          share.update!(message: text.truncate(FacebookPost::MAX_MESSAGE_LENGTH, omission: ""), ai_variant: true)
          updated << share
        end

        AiRun.record!(org: org, user: user, workflow: "facebook_group_variants", provider: gw.provider_label,
                      model: gw.model_label.to_s,
                      input_references: { "facebook_post_id" => post.id, "group_share_ids" => shares.map(&:id) })
        AuditLog.record!(org: org, user: user, action: "facebook.group_share.ai_variants", subject: post,
                         details: { "provider" => gw.provider_label, "count" => updated.size })
        updated
      end

      def self.build_prompt(post, shares)
        groups = shares.each_with_index.map do |s, i|
          g = s.facebook_group
          rules = [ g.rules_note.presence, ("KHÔNG được chèn link" unless g.allows_links) ].compact.join("; ")
          "#{i + 1}. Nhóm \"#{g.name}\"#{" — luật: #{rules}" if rules.present?}"
        end

        <<~PROMPT
          Đây là bài đã đăng trên Fanpage "#{post.facebook_page_connection.page_name}":
          --- BÀI GỐC ---
          #{post.message.to_s.truncate(4000)}
          --- HẾT ---

          Viết lại bài này thành #{shares.size} phiên bản để người dùng TỰ đăng vào các hội nhóm sau:
          #{groups.join("\n")}

          Quy tắc:
          - Giữ nguyên mọi dữ kiện: giá, diện tích, địa chỉ, số điện thoại, thời gian. Không bịa thêm khuyến mãi, số liệu.
          - Mỗi phiên bản khác nhau rõ ở câu mở đầu, cách diễn đạt và bộ hashtag; độ dài tương đương bài gốc.
          - Tôn trọng luật của từng nhóm. Nhóm cấm link thì tuyệt đối không có URL.
          - Văn phong tự nhiên như thành viên chia sẻ trong nhóm, không spam, không viết hoa toàn bộ.
          Viết TOÀN BỘ bằng tiếng Việt.

          Trả về DUY NHẤT một object JSON:
          {"variants": [{"index": 1, "message": "..."}, {"index": 2, "message": "..."}]}
        PROMPT
      end

      # Offline (AI_PROVIDER=fake): biến thể xác định, đủ để thử luồng UI.
      def self.fake_completion(post, shares)
        ->(_prompt) do
          base = post.message.to_s.strip
          base = base.gsub(%r{https?://\S+}, "").squeeze(" ").strip
          variants = shares.each_with_index.map do |s, i|
            g = s.facebook_group
            opener = "#{OPENERS[i % OPENERS.size]} Chia sẻ với các thành viên nhóm #{g.name}:"
            body = g.allows_links && post.permalink_url.present? ? "#{base}\n\nXem bài gốc: #{post.permalink_url}" : base
            { index: i + 1, message: "#{opener}\n\n#{body}" }
          end
          { variants: variants }.to_json
        end
      end
    end
  end
end
