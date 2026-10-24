# lib/cdfl_harness/reasoning/cdfl/transition_model.rb
# frozen_string_literal: true

require_relative "types"

module CDFLHarness
  module Reasoning
    module CDFL
      # Tabular P(s'|s,a) learned from observed transitions (CRITICAL component
      # — ablation −31.6pp). Port of transition_model.py.
      class TransitionModel
        def initialize(rng: Random.new, recency_decay: 1.0)
          unless recency_decay > 0.0 && recency_decay <= 1.0
            raise ArgumentError, "recency_decay must be in (0,1], got #{recency_decay}"
          end

          @counts = Hash.new { |h, k| h[k] = Hash.new(0.0) } # [s,a] => { s' => count }
          @state_visits = Hash.new(0.0)
          @known_states = []
          @known_set = {}
          @rng = rng
          @decay = recency_decay
        end

        def observe(state, action, next_state)
          @counts[[state, action]][next_state] += 1
          record_state(state)
          record_state(next_state)
          nil
        end

        def observe_many(transitions)
          transitions.each { |t| observe(t.state, t.action, t.next_state) }
        end

        def tick
          return if @decay >= 1.0

          @state_visits.each_key { |s| @state_visits[s] *= @decay }
          @counts.each_value { |bucket| bucket.each_key { |s| bucket[s] *= @decay } }
          nil
        end

        def probability(state, action, next_state)
          bucket = @counts[[state, action]]
          total = bucket.values.sum
          return 0.0 if total.zero?

          bucket[next_state] / total
        end

        def sample_next(state, action)
          bucket = @counts[[state, action]]
          total = bucket.values.sum
          return weighted_choice(bucket) if total.positive?
          return @known_states[@rng.rand(@known_states.size)] unless @known_states.empty?

          state
        end

        def state_visit_count(state)  = @state_visits[state]
        def state_action_count(state, action) = @counts[[state, action]].values.sum
        def known_states = @known_states.dup
        def num_transitions_seen = @state_visits.values.sum

        # Internal: actions ever observed from `state` (used by the planner's
        # rollout interior steps).
        def actions_from(state)
          @counts.keys.select { |(s, _a)| s == state }.map { |(_s, a)| a }.uniq
        end

        def self.from_direct_follows(direct_follows, rng: Random.new)
          model = new(rng: rng)
          direct_follows.each do |(from_type, to_type), count|
            count.to_i.times { model.observe(from_type, to_type, to_type) }
          end
          model
        end

        private

        def record_state(state)
          unless @known_set.key?(state)
            @known_states << state
            @known_set[state] = true
          end
          @state_visits[state] += 1
        end

        def weighted_choice(bucket)
          total = bucket.values.sum
          r = @rng.rand * total
          acc = 0.0
          bucket.each { |k, w| acc += w; return k if r <= acc }
          bucket.keys.last
        end
      end
    end
  end
end
