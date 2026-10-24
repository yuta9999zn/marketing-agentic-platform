# frozen_string_literal: true

module Providers
  # Chọn adapter theo cấu hình workspace. Ba nhóm, phân biệt rõ vì mức rủi ro
  # dữ liệu khác nhau:
  #
  # 1. fake      — deterministic, không gọi gì. Mặc định an toàn.
  # 2. local     — Ollama chạy trên chính máy này. Harness coi là INTERNAL
  #                (external? == false) nên KHÔNG cần consent gửi ra ngoài:
  #                dữ liệu khách hàng không rời khỏi máy.
  # 3. external  — Anthropic/OpenAI/DeepL... Bắt buộc org.ai_external_enabled.
  #
  # Yêu cầu external nhưng chưa có adapter thật → raise rõ ràng, không âm thầm
  # fallback về fake (người dùng phải biết mình đang chạy bằng gì).
  class AdapterFactory
    class ExternalNotConfigured < StandardError; end

    def self.translation_for(org:, user: nil)
      return TranslationLlmAdapter.new(org: org, user: user) if Ai::Gateway.local_provider?

      external_key = ENV["TRANSLATION_PROVIDER"].to_s
      return TranslationFakeAdapter.new if external_key.blank? || !org&.ai_external_enabled

      raise ExternalNotConfigured,
            "Translation provider \"#{external_key}\" chưa được triển khai. " \
            "Dùng AI_PROVIDER=ollama để dịch bằng mô hình chạy trên máy."
    end

    # Ollama KHÔNG tạo được ảnh (llama/qwen là model văn bản). Khi chạy local,
    # ta dùng LLM để viết prompt ảnh chất lượng cao — việc render ảnh vẫn cần
    # một dịch vụ riêng (Stable Diffusion cục bộ hoặc provider ngoài).
    def self.image_for(org:, user: nil)
      return ImagePromptLlmAdapter.new(org: org, user: user) if Ai::Gateway.local_provider?

      external_key = ENV["IMAGE_PROVIDER"].to_s
      return ImageGenerationFakeAdapter.new if external_key.blank? || !org&.ai_external_enabled

      raise ExternalNotConfigured,
            "Image provider \"#{external_key}\" chưa được triển khai. " \
            "Hiện chỉ tạo gói prompt ảnh, chưa render ảnh thật."
    end

    def self.calendar_for(_org = nil)
      CalendarFakeAdapter.new
    end
  end
end
