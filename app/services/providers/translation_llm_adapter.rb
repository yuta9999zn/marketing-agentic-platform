# frozen_string_literal: true

module Providers
  # Dịch bằng mô hình ngôn ngữ qua Ai::Gateway (mặc định Ollama chạy trên máy).
  #
  # Dùng generate_text chứ không phải generate_structured: dịch thuật không cần
  # JSON, và ép model nhỏ trả JSON làm hỏng văn bản có xuống dòng/emoji.
  #
  # Output vẫn là BẢN NHÁP chờ người duyệt — giống hệt adapter offline.
  class TranslationLlmAdapter < TranslationProviderAdapter
    LANGUAGE_NAMES = {
      "vi" => "tiếng Việt", "en" => "tiếng Anh", "ja" => "tiếng Nhật",
      "ko" => "tiếng Hàn", "zh" => "tiếng Trung"
    }.freeze

    # Cắt đầu vào để không vượt context của model nhỏ và không treo request.
    MAX_INPUT_CHARS = 6000

    def initialize(org: nil, user: nil)
      @org = org
      @user = user
    end

    def translate(text:, source:, target:, glossary: {})
      body = text.to_s
      truncated = body.length > MAX_INPUT_CHARS
      body = body[0, MAX_INPUT_CHARS] if truncated

      gateway = Ai::Gateway.new(org: @org, user: @user)
      output = gateway.generate_text(
        prompt: build_prompt(body, source, target, glossary),
        task: "translation.#{source}.#{target}",
        max_tokens: 3000
      )

      result = strip_preamble(output)
      result += "\n\n[Ghi chú: bản gốc dài hơn giới hạn dịch, phần cuối chưa được dịch.]" if truncated
      result
    end

    def provider_name = "translation_#{Ai::Gateway.provider_name}"

    private

    def build_prompt(text, source, target, glossary)
      src = LANGUAGE_NAMES.fetch(source.to_s, source.to_s)
      tgt = LANGUAGE_NAMES.fetch(target.to_s, target.to_s)
      glossary_block =
        if glossary.present?
          "Bắt buộc dùng các thuật ngữ sau:\n" +
            glossary.map { |from, to| "- #{from} → #{to}" }.join("\n") + "\n"
        end

      <<~PROMPT
        Dịch đoạn văn bản marketing dưới đây từ #{src} sang #{tgt}.

        Yêu cầu bắt buộc:
        - Giữ nguyên cấu trúc: xuống dòng, gạch đầu dòng, tiêu đề.
        - Giữ nguyên tên riêng, tên thương hiệu, số liệu, đơn vị và ngày tháng.
        - Dịch theo văn phong marketing tự nhiên, không dịch từng từ máy móc.
        - TUYỆT ĐỐI KHÔNG thêm bất cứ nội dung nào không có trong bản gốc:
          không thêm hashtag, không thêm emoji, không thêm câu kêu gọi hành động,
          không thêm lời chào. Bản gốc có bao nhiêu ý thì bản dịch có đúng bấy nhiêu ý.
        - Emoji và hashtag CÓ SẴN trong bản gốc thì giữ nguyên vị trí.
        - Câu nào không rõ nghĩa thì dịch sát nghĩa nhất có thể, không suy diễn.
        #{glossary_block}
        Chỉ trả về phần đã dịch. Không thêm lời giải thích, không thêm tiêu đề "Bản dịch:".

        --- VĂN BẢN GỐC ---
        #{text}
        --- HẾT VĂN BẢN GỐC ---
      PROMPT
    end

    # Model nhỏ hay thêm câu mở đầu kiểu "Here is the translation:" dù đã dặn.
    # Cắt bỏ dòng đầu nếu nó là lời dẫn chứ không phải nội dung.
    PREAMBLE = /\A\s*(here (is|'s) [^\n:]*:|bản dịch[^\n:]*:|translation:|dịch:)\s*\n?/i

    def strip_preamble(output)
      out = output.to_s.strip
      out = out.sub(PREAMBLE, "").strip
      # Model đôi khi bọc toàn bộ trong khối code — bóc ra.
      if out.start_with?("```") && out.end_with?("```")
        out = out.sub(/\A```[a-z]*\n?/i, "").sub(/\n?```\z/, "").strip
      end
      out
    end
  end
end
