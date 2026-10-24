# lib/cdfl_harness/reasoning/memory/record.rb
# frozen_string_literal: true

require "securerandom"

module CDFLHarness
  module Reasoning
    module Memory
      # Lifecycle tiers (storage stage) — distinct from cognitive type.
      TIERS = %w[L1_WORKING L2_SHORT L3_CONSOLIDATED L4_LONG].freeze
      # Cognitive categories.
      TYPES = %i[EPISODIC SEMANTIC PROCEDURAL OPERATIONAL DECISION].freeze

      CLASSIC_MEMORY_CLASS = {
        EPISODIC: "episodic", DECISION: "episodic",
        SEMANTIC: "semantic", PROCEDURAL: "procedural", OPERATIONAL: "procedural"
      }.freeze

      # Per-type trust half-life (days) — learned concepts age slowly, episodic fast.
      HALFLIFE_DAYS = { SEMANTIC: 365, PROCEDURAL: 365, DECISION: 60, OPERATIONAL: 60, EPISODIC: 30 }.freeze
      DEFAULT_HALFLIFE_DAYS = 60
      TRUST_FRESH = 0.66
      TRUST_AGING = 0.33

      # Per-source confidence ceiling (epistemic humility — never 1.0).
      CONF_CEILING = { "user" => 0.98, "consolidate" => 0.90, "rag" => 0.90, "derived" => 0.85 }.freeze
      DEFAULT_CEILING = 0.85
      EXPERIENCE_BANDS = [[0.80, "chuyên gia"], [0.55, "dày dạn"], [0.30, "thành thạo"],
                          [0.10, "tập sự"], [0.0, "mới"]].freeze

      class MemoryRecord
        attr_accessor :tenant_id, :memory_type, :content, :record_id, :tier,
                      :occurred_at, :session_id, :entity_id, :session_appearance_count,
                      :user_flagged_important, :linked_outcome_value, :metadata,
                      :confidence, :trust_source, :last_verified_at

        def initialize(tenant_id:, memory_type:, content:, record_id: nil, tier: "L1_WORKING",
                       occurred_at: nil, session_id: nil, entity_id: nil, session_appearance_count: 0,
                       user_flagged_important: false, linked_outcome_value: 0.0, metadata: nil,
                       confidence: 0.70, trust_source: nil, last_verified_at: nil)
          @tenant_id = tenant_id
          @memory_type = memory_type
          @content = content
          @record_id = record_id || SecureRandom.uuid
          @tier = tier
          @occurred_at = occurred_at || Time.now
          @session_id = session_id
          @entity_id = entity_id
          @session_appearance_count = session_appearance_count
          @user_flagged_important = user_flagged_important
          @linked_outcome_value = linked_outcome_value
          @metadata = metadata || {}
          @confidence = confidence
          @trust_source = trust_source
          @last_verified_at = last_verified_at
        end
      end

      module_function

      def classic_memory_class(memory_type)
        CLASSIC_MEMORY_CLASS[memory_type] || "semantic"
      end

      def days_between(later, earlier)
        [0, ((later - earlier) / 86_400).floor].max
      end

      # Importance 0..1 (retention). PIPELINE_UNIFIED §7.5.
      def compute_importance(record, now: Time.now)
        days_old = days_between(now, record.occurred_at)
        recency = [0.0, 1 - days_old / 90.0].max
        repeat = [1.0, record.session_appearance_count / 5.0].min
        flag = record.user_flagged_important ? 1.0 : 0.0
        outcome = record.linked_outcome_value > 10_000_000 ? 1.0 : 0.0
        [1.0, 0.2 * recency + 0.3 * repeat + 0.3 * flag + 0.2 * outcome].min
      end

      def halflife_days(memory_type)
        HALFLIFE_DAYS[memory_type] || DEFAULT_HALFLIFE_DAYS
      end

      # Believability now (decay since last verification / event). ADR-0030.
      def compute_trust(record, now: Time.now)
        base = record.last_verified_at || record.occurred_at
        age = days_between(now, base)
        hl = halflife_days(record.memory_type)
        score = (record.confidence * (0.5**(age.to_f / hl))).round(3)
        level = score >= TRUST_FRESH ? "fresh" : (score >= TRUST_AGING ? "aging" : "stale")
        unchecked = record.confidence >= 0.8 && record.last_verified_at.nil? && age > hl
        { age_days: age, score: score, level: level,
          verified: !record.last_verified_at.nil?, unchecked: unchecked, halflife: hl }
      end

      # Retrieval-ranking multiplier in [0.4, 1.0].
      def trust_factor(record, now: Time.now)
        0.4 + 0.6 * compute_trust(record, now: now)[:score]
      end

      # Validated-use bump (ADR-0032) — asymptotic learning curve toward ceiling.
      def reinforce_confidence(record, learn_rate: CDFLHarness.config.reasoning.learn_rate)
        ceiling = CONF_CEILING[record.trust_source] || DEFAULT_CEILING
        record.confidence = [ceiling, (record.confidence + learn_rate * (ceiling - record.confidence))].min.round(4)
      end

      # Tenant maturation from accumulated still-trusted knowledge ("càng nhiều
      # tháng càng biết nhiều").
      def experience_level(records, now: Time.now, k: CDFLHarness.config.reasoning.experience_k)
        return { experience: 0.0, knowledge_mass: 0.0, band: "mới", n: 0, tenure_days: 0 } if records.empty?

        mass = records.sum { |r| compute_trust(r, now: now)[:score] }
        score = (1 - Math.exp(-k * mass)).round(4)
        tenure = days_between(now, records.map(&:occurred_at).min)
        band = EXPERIENCE_BANDS.find { |thr, _name| score >= thr }.last
        { experience: score, knowledge_mass: mass.round(3), band: band, n: records.size, tenure_days: tenure }
      end
    end
  end
end
