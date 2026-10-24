# frozen_string_literal: true

module Providers
  # Offline placeholder: KHÔNG tạo ảnh thật — trả về prompt đã chuẩn hoá + metadata
  # để designer đem sang công cụ có kiểm soát. Không gọi mạng.
  class ImageGenerationFakeAdapter < ImageGenerationProviderAdapter
    def generate(prompt:, dimensions:, style:, exclusions: [])
      {
        "kind" => "image_prompt_package",
        "final_prompt" => [prompt, "Style: #{style}", "Size: #{dimensions}",
                           exclusions.present? ? "Tránh: #{exclusions}" : nil].compact.join(" | "),
        "note" => "Offline placeholder — cần provider thật (owner cấu hình) để render ảnh.",
        "approval_required" => true
      }
    end

    def provider_name = "image_fake"
  end
end
