# frozen_string_literal: true

module Providers
  # Contract cho image generation provider.
  class ImageGenerationProviderAdapter
    def generate(prompt:, dimensions:, style:, exclusions: [])
      raise NotImplementedError
    end

    def provider_name = self.class.name.demodulize
  end
end
