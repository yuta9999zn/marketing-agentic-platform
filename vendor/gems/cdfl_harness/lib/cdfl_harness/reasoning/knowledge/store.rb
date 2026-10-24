# lib/cdfl_harness/reasoning/knowledge/store.rb
# frozen_string_literal: true

require_relative "document"

module CDFLHarness
  module Reasoning
    module Knowledge
      # Pluggable KB store contract.
      class Store
        def put(doc, scope_tenant_id:); raise NotImplementedError; end
        def list_documents(tenant_id, limit: 100); raise NotImplementedError; end
      end

      # In-memory default. A project swaps in pgvector + a real retriever.
      class InMemoryStore < Store
        def initialize
          @by_tenant = Hash.new { |h, k| h[k] = {} }
        end

        def put(doc, scope_tenant_id:)
          @by_tenant[scope_tenant_id][doc.document_id] = doc
          doc
        end

        def list_documents(tenant_id, limit: 100)
          @by_tenant[tenant_id].values.first(limit)
        end
      end
    end
  end
end
