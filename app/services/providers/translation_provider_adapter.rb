# frozen_string_literal: true

module Providers
  # Contract cho translation provider. Default: FakeAdapter deterministic, offline.
  # Provider thật (DeepL/Google/...) implement cùng interface và chỉ được gọi khi
  # owner workspace cấu hình credential + consent.
  class TranslationProviderAdapter
    def translate(text:, source:, target:, glossary: {})
      raise NotImplementedError
    end

    def provider_name = self.class.name.demodulize
  end
end
