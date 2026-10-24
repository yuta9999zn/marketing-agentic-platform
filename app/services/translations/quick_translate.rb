# frozen_string_literal: true

module Translations
  # Dịch nhanh một đoạn văn bản ngay tại chỗ — dùng cho góp ý của khách hàng
  # hoặc đoạn text người dùng bôi đen. KHÔNG tạo artifact, không tạo version:
  # đây là công cụ đọc hiểu, không phải bước sản xuất nội dung.
  #
  # Vẫn ghi AiRun để audit đầy đủ: mọi lời gọi model đều có dấu vết.
  class QuickTranslate
    MAX_CHARS = 2000 # dịch nhanh phải nhanh — đoạn dài thì dùng nút dịch artifact

    Result = Struct.new(:text, :provider, :truncated, keyword_init: true)

    def self.call(text:, org:, user:, target_locale: "en", source_locale: nil)
      body = text.to_s.strip
      raise ArgumentError, "Không có nội dung để dịch." if body.blank?

      truncated = body.length > MAX_CHARS
      body = body[0, MAX_CHARS] if truncated

      adapter = Providers::AdapterFactory.translation_for(org: org, user: user)
      translated = adapter.translate(text: body, source: source_locale.presence || "vi",
                                     target: target_locale, glossary: {})

      AiRun.record!(org: org, user: user, workflow: "quick_translate",
                    provider: adapter.provider_name,
                    model: Translations::CreateService.model_label,
                    input_references: { "chars" => body.length, "target" => target_locale })

      Result.new(text: translated, provider: adapter.provider_name, truncated: truncated)
    end
  end
end
