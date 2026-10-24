# frozen_string_literal: true

module Providers
  # Deterministic offline translation: glossary word-map + mark rõ [draft].
  # Không gọi mạng — dùng cho demo/test/preview. Output luôn là BẢN NHÁP cần review.
  class TranslationFakeAdapter < TranslationProviderAdapter
    GLOSSARY_VI_EN = {
      "chiến dịch" => "campaign", "khách hàng" => "customer", "thương hiệu" => "brand",
      "mục tiêu" => "objective", "người dùng" => "user", "nội dung" => "content",
      "thông điệp" => "message", "sản phẩm" => "product", "dịch vụ" => "service",
      "đối tượng" => "audience", "kênh" => "channel", "duyệt" => "approve",
      "bản nháp" => "draft", "lịch" => "calendar", "cuộc họp" => "meeting",
      "tiến độ" => "progress", "ngân sách" => "budget", "ra mắt" => "launch",
      "tăng" => "increase", "giảm" => "reduce", "mùa hè" => "summer"
    }.freeze

    def translate(text:, source:, target:, glossary: {})
      dict = glossary.symbolize_keys
      dict = GLOSSARY_VI_EN if dict.empty?
      out = text.to_s.dup
      dict.each { |from, to| out.gsub!(Regexp.new(Regexp.escape(from), Regexp::IGNORECASE), to.to_s) }
      header = "[Bản dịch nháp #{source}→#{target} — deterministic offline, chờ con người duyệt]\n\n"
      header + out
    end

    def provider_name = "translation_fake"
  end
end
