# lib/cdfl_harness/reasoning/memory/service.rb
# frozen_string_literal: true

require "set"
require_relative "record"
require_relative "tier_store"

module CDFLHarness
  module Reasoning
    module Memory
      # Facade over 4 TierStores (cung điện ký ức). Synchronous port of
      # memory/service.py. Default tiers, importance promotion, associative
      # recall, trust ranking, maturation.
      class Service
        DEFAULT_TIER = {
          EPISODIC: "L2_SHORT", SEMANTIC: "L4_LONG", PROCEDURAL: "L4_LONG",
          OPERATIONAL: "L3_CONSOLIDATED", DECISION: "L3_CONSOLIDATED"
        }.freeze
        PROMOTION_THRESHOLD = 0.7
        FORGET_THRESHOLD = 0.3
        FORGET_AGE_DAYS = 90

        def initialize(l1: nil, l2: nil, l3: nil, l4: nil)
          @l1 = l1 || InMemoryTierStore.new("L1_WORKING")
          @l2 = l2 || InMemoryTierStore.new("L2_SHORT")
          @l3 = l3 || InMemoryTierStore.new("L3_CONSOLIDATED")
          @l4 = l4 || InMemoryTierStore.new("L4_LONG")
        end

        attr_reader :l1, :l2, :l3, :l4

        def write(tenant_id, memory_type, content, session_id: nil, entity_id: nil,
                  metadata: nil, user_flagged_important: false, linked_outcome_value: 0.0)
          tier = DEFAULT_TIER.fetch(memory_type)
          rec = MemoryRecord.new(
            tenant_id: tenant_id, memory_type: memory_type, content: content, tier: tier,
            session_id: session_id, entity_id: entity_id, metadata: metadata || {},
            user_flagged_important: user_flagged_important, linked_outcome_value: linked_outcome_value
          )
          tier_store(tier).put(rec)
        end

        def retrieve(tenant_id, query, top_k: 5, tier: "auto", session_id: nil,
                     entity_id: nil, entity_boost: 2.0, expand_links: true,
                     expand_limit: nil, min_score: 0.0, now: Time.now)
          walk = tier == "auto" ? [@l2, @l3, @l4] : [tier_store(tier)]
          scored = []
          all_by_id = {}
          walk.each do |store|
            store.list_all(tenant_id).each do |r|
              next if store.tier == "L2_SHORT" && session_id && r.session_id != session_id

              all_by_id[r.record_id] = r
              score = Memory.cheap_text_match(query, r.content)
              next unless score.positive? && score >= min_score

              score *= entity_boost if entity_id && r.entity_id == entity_id
              score *= Memory.trust_factor(r, now: now)
              scored << [score, r]
            end
          end

          scored.sort_by! { |s, _r| -s }
          results = scored.first(top_k).map { |_s, r| r }

          # reinforce retrieval signal (appearance bump persisted)
          results.each do |r|
            r.session_appearance_count += 1
            tier_store(r.tier).put(r)
          end

          if expand_links
            remaining = expand_limit || top_k
            seen = results.map(&:record_id).to_set
            results.dup.each do |r|
              break if remaining <= 0

              (r.metadata["links"] || []).each do |lid|
                break if remaining <= 0

                nb = all_by_id[lid]
                next if nb.nil? || seen.include?(nb.record_id)

                results << nb
                seen << nb.record_id
                remaining -= 1
              end
            end
          end
          results
        end

        def verify(tenant_id, record_id, now: Time.now)
          each_store do |store|
            r = store.get(tenant_id, record_id)
            next unless r

            r.last_verified_at = now
            store.put(r)
            return true
          end
          false
        end

        def reinforce(tenant_id, record_id, now: Time.now)
          each_store do |store|
            r = store.get(tenant_id, record_id)
            next unless r

            r.last_verified_at = now
            Memory.reinforce_confidence(r)
            store.put(r)
            return true
          end
          false
        end

        def link(tenant_id, a_id, b_id, mutual: true)
          pairs = mutual ? [[a_id, b_id], [b_id, a_id]] : [[a_id, b_id]]
          found = false
          pairs.each do |src, dst|
            each_store do |store|
              r = store.get(tenant_id, src)
              next unless r

              links = (r.metadata["links"] || [])
              links << dst unless links.include?(dst)
              r.metadata["links"] = links
              store.put(r)
              found = true
              break
            end
          end
          found
        end

        def experience(tenant_id, now: Time.now)
          recs = @l4.list_all(tenant_id) + @l3.list_all(tenant_id)
          Memory.experience_level(recs, now: now)
        end

        def consolidate(tenant_id)
          moved = 0
          @l2.list_all(tenant_id).each do |r|
            @l2.delete(tenant_id, r.record_id)
            r.tier = "L3_CONSOLIDATED"
            @l3.put(r)
            moved += 1
          end
          moved
        end

        def promote(tenant_id, importance_threshold: PROMOTION_THRESHOLD, now: Time.now)
          moved = 0
          @l3.list_all(tenant_id).each do |r|
            next unless Memory.compute_importance(r, now: now) > importance_threshold

            @l3.delete(tenant_id, r.record_id)
            r.tier = "L4_LONG"
            @l4.put(r)
            moved += 1
          end
          moved
        end

        def forget(tenant_id, full_tenant_wipe: false, below_score: FORGET_THRESHOLD,
                   age_days: FORGET_AGE_DAYS, now: Time.now)
          if full_tenant_wipe
            return [@l1, @l2, @l3, @l4].sum { |s| s.forget(tenant_id) }
          end

          cutoff = now - age_days * 86_400
          wiped = 0
          @l3.list_all(tenant_id).each do |r|
            next unless r.occurred_at < cutoff && Memory.compute_importance(r, now: now) < below_score

            @l3.delete(tenant_id, r.record_id)
            wiped += 1
          end
          wiped
        end

        private

        def tier_store(tier)
          { "L1_WORKING" => @l1, "L2_SHORT" => @l2,
            "L3_CONSOLIDATED" => @l3, "L4_LONG" => @l4 }.fetch(tier)
        end

        def each_store
          [@l1, @l2, @l3, @l4].each { |s| yield s }
        end
      end
    end
  end
end
