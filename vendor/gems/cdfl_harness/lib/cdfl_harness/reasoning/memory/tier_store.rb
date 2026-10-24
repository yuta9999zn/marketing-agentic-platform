# lib/cdfl_harness/reasoning/memory/tier_store.rb
# frozen_string_literal: true

require "set"
require_relative "record"

module CDFLHarness
  module Reasoning
    module Memory
      # One backend per tier. Contract; a project swaps Redis/Postgres/Neo4j.
      class TierStore
        def put(record); raise NotImplementedError; end
        def get(tenant_id, record_id); raise NotImplementedError; end
        def list_all(tenant_id); raise NotImplementedError; end
        def delete(tenant_id, record_id); raise NotImplementedError; end
        def forget(tenant_id); raise NotImplementedError; end
      end

      class InMemoryTierStore < TierStore
        attr_reader :tier

        def initialize(tier)
          @tier = tier
          @records = {}             # [tenant_id, record_id] => record
          @by_tenant = Hash.new { |h, k| h[k] = [] }
        end

        def put(record)
          record.tier = @tier
          key = [record.tenant_id, record.record_id]
          @by_tenant[record.tenant_id] << record.record_id unless @records.key?(key)
          @records[key] = record
          record
        end

        def get(tenant_id, record_id) = @records[[tenant_id, record_id]]

        def list_all(tenant_id)
          @by_tenant[tenant_id].map { |rid| @records[[tenant_id, rid]] }.compact
        end

        def delete(tenant_id, record_id)
          key = [tenant_id, record_id]
          return false unless @records.key?(key)

          @records.delete(key)
          @by_tenant[tenant_id].delete(record_id)
          true
        end

        def forget(tenant_id)
          ids = @by_tenant.delete(tenant_id) || []
          ids.each { |rid| @records.delete([tenant_id, rid]) }
          ids.size
        end
      end

      module_function

      # Tiny in-memory retrieval scoring: token-set jaccard 0..1. Unicode-aware.
      def cheap_text_match(query, text)
        q = tokens(query)
        t = tokens(text)
        return 0.0 if q.empty? || t.empty?

        (q & t).size.to_f / (q | t).size
      end

      def tokens(str)
        str.to_s.downcase.scan(/\p{L}+/).to_set
      end
    end
  end
end
