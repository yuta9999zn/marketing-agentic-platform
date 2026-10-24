# lib/cdfl_harness/reasoning/knowledge/document.rb
# frozen_string_literal: true

require "securerandom"

module CDFLHarness
  module Reasoning
    module Knowledge
      # A knowledge doc. tier: 1 regulatory, 2 curated (FOUNDATIONAL); 3 market
      # (volatile); 4 tenant notes. distance = pgvector cosine distance when
      # retrieved (nil otherwise). confidence = maturity 0..1.
      Document = Struct.new(:title, :content, :tier, :confidence, :tenant_id,
                            :category, :source, :document_id, :distance,
                            keyword_init: true) do
        def initialize(title:, content:, tenant_id:, tier: 4, confidence: 0.7,
                       category: nil, source: nil, document_id: nil, distance: nil)
          super(title: title, content: content, tier: tier, confidence: confidence,
                tenant_id: tenant_id, category: category, source: source,
                document_id: document_id || SecureRandom.uuid, distance: distance)
        end
      end
    end
  end
end
