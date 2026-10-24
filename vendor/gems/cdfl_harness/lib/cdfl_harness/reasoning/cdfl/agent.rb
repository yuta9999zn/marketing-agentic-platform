# lib/cdfl_harness/reasoning/cdfl/agent.rb
# frozen_string_literal: true

require_relative "transition_model"
require_relative "info_gain"
require_relative "lookahead"

module CDFLHarness
  module Reasoning
    module CDFL
      # Convergent Dual-Field Learning agent — combines TransitionModel +
      # InfoGain + LookaheadPlanner. Picks the action with max expected info
      # gain (≈ E[Δ|OR|]) with optional Boltzmann noise. Port of agent.py.
      class Agent
        def initialize(action_space:, horizon: 5, num_rollouts: 6,
                       uncertainty_weight: 1.0, information_gain_weight: 1.0,
                       temperature: 0.1, freeze_model: false, seed: nil)
          raise ArgumentError, "action_space must be non-empty" if action_space.nil? || action_space.empty?
          raise ArgumentError, "horizon must be >= 1" if horizon < 1
          raise ArgumentError, "num_rollouts must be >= 1" if num_rollouts < 1
          raise ArgumentError, "temperature must be >= 0" if temperature.negative?

          @action_space = action_space.to_a
          @temperature = temperature
          @freeze_model = freeze_model
          @rng = seed.nil? ? Random.new : Random.new(seed)
          @model = TransitionModel.new(rng: @rng)
          scorer = InfoGain.new(uncertainty_weight: uncertainty_weight,
                                information_gain_weight: information_gain_weight)
          @planner = LookaheadPlanner.new(horizon: horizon, num_rollouts: num_rollouts,
                                          scorer: scorer, rng: @rng)
        end

        attr_reader :model, :planner

        def step(state)
          scored = @planner.score_actions(@model, state, @action_space)
          pick_with_temperature(scored)
        end

        def observe_transition(state, action, next_state, _reward = 0.0)
          return if @freeze_model

          @model.observe(state, action, next_state)
        end

        def score_actions(state)
          @planner.score_actions(@model, state, @action_space)
        end

        def transition_counts = @model.num_transitions_seen

        private

        def pick_with_temperature(scored)
          return @action_space[@rng.rand(@action_space.size)] if scored.empty?

          if @temperature <= 0
            return scored.min_by { |s| [-s.mean_score, s.visit_proxy] }.action
          end

          max = scored.map(&:mean_score).max
          weights = scored.map { |s| Math.exp((s.mean_score - max) / @temperature) }
          total = weights.sum
          r = @rng.rand * total
          acc = 0.0
          scored.each_with_index { |s, i| acc += weights[i]; return s.action if r <= acc }
          scored.last.action
        end
      end
    end
  end
end
