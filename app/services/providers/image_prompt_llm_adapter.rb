# frozen_string_literal: true

module Providers
  # Viết prompt tạo ảnh bằng LLM chạy trên máy (Ollama).
  #
  # QUAN TRỌNG — vẫn KHÔNG render ảnh: qwen/llama là model văn bản, không sinh
  # được hình. Việc adapter này làm là biến vài dòng brief rời rạc thành một
  # prompt ảnh có cấu trúc, đủ chi tiết để đem sang công cụ tạo ảnh bất kỳ.
  # Muốn ra ảnh thật cần chạy thêm một dịch vụ riêng (xem docs/PHASE3_REPORT.md).
  class ImagePromptLlmAdapter < ImageGenerationProviderAdapter
    def initialize(org: nil, user: nil)
      @org = org
      @user = user
    end

    def generate(prompt:, dimensions:, style:, exclusions: [])
      excl = Array(exclusions).compact_blank
      gateway = Ai::Gateway.new(org: @org, user: @user)
      enhanced =
        begin
          gateway.generate_text(prompt: build_prompt(prompt, dimensions, style, excl),
                                task: "image.prompt", max_tokens: 700).to_s.strip
        rescue CDFLHarness::Errors::Error
          nil # LLM hỏng thì vẫn trả gói prompt cơ bản, không làm hỏng thao tác
        end

      base = [prompt, "Style: #{style}", "Size: #{dimensions}",
              excl.present? ? "Tránh: #{excl.join(', ')}" : nil].compact.join(" | ")

      {
        "kind" => "image_prompt_package",
        "final_prompt" => enhanced.presence || base,
        "base_prompt" => base,
        "enhanced_by_llm" => enhanced.present?,
        "note" => "Prompt do mô hình chạy trên máy soạn. CHƯA phải ảnh — đem prompt này " \
                  "sang công cụ tạo ảnh để render, và duyệt trước khi dùng thương mại.",
        "approval_required" => true
      }
    end

    def provider_name = "image_prompt_#{Ai::Gateway.provider_name}"

    private

    def build_prompt(brief, dimensions, style, exclusions)
      <<~PROMPT
        Bạn là giám đốc nghệ thuật. Viết một prompt tạo ảnh chi tiết, dùng được ngay
        với công cụ tạo ảnh (Stable Diffusion, Midjourney, DALL·E).

        Thông tin chiến dịch:
        #{brief}

        Ràng buộc kỹ thuật:
        - Tỷ lệ/kích thước: #{dimensions}
        - Phong cách: #{style}
        #{exclusions.present? ? "- Tuyệt đối tránh: #{exclusions.join(', ')}" : ''}

        Prompt phải mô tả rõ, theo thứ tự: chủ thể chính → bối cảnh → bố cục và góc máy
        → ánh sáng → tông màu → chất liệu/kết cấu → tâm trạng ảnh. Dùng danh từ và tính từ
        cụ thể, tránh từ trừu tượng.

        Không mô tả chữ viết trong ảnh (công cụ tạo ảnh viết chữ rất kém).
        Không bịa thêm thông tin sản phẩm chưa có ở trên.

        Chỉ trả về nội dung prompt. Không giải thích, không đánh số, không tiêu đề.
      PROMPT
    end
  end
end
