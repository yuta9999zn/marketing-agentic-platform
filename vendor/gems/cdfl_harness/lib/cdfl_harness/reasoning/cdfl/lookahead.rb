# lib/cdfl_harness/reasoning/cdfl/lookahead.rb
# frozen_string_literal: true

require_relative "types"
require_relative "info_gain"

module CDFLHarness
  module Reasoning
    module CDFL
      # H-step Monte-Carlo planner. Does NOT mutate the model (rollouts sample
      # only). Port of lookahead.py.
      class LookaheadPlanner
        attr_reader :horizon, :num_rollouts, :scorer, :rng

        def initialize(horizon: 5, num_rollouts: 6, scorer: nil, rng: nil)
          raise ArgumentError, "horizon must be >= 1" if horizon < 1
          raise ArgumentError, "num_rollouts must be >= 1" if num_rollouts < 1

          @horizon = horizon
          @num_rollouts = num_rollouts
          @scorer = scorer || InfoGain.new
          @rng = rng || Random.new
        end

        def rollout(model, start, first_action)
          trajectory = []
          total_ig = 0.0
          state = start
          action = first_action
          @horizon.times do
            next_state = model.sample_next(state, action)
            total_ig += @scorer.score(model, state, action, next_state)
            trajectory << Transition.new(state: state, action: action, next_state: next_state)
            state = next_state
            candidates = model.actions_from(state)
            break if candidates.empty?

            weights = candidates.map { |a| @scorer.score(model, state, a) }
            action = weighted_pick(candidates, weights)
          end
          RolloutResult.new(trajectory: trajectory, total_information_gain: total_ig)
        end

        def score_actions(model, state, candidate_actions)
          return [] if candidate_actions.empty?

          candidate_actions.map do |action|
            rollouts = Array.new(@num_rollouts) { rollout(model, state, action) }
            igs = rollouts.map(&:total_information_gain)
            ActionScore.new(
              action: action,
              mean_score: igs.sum / igs.size,
              best_score: igs.max,
              visit_proxy: model.state_action_count(state, action)
            )
          end
        end

        def best_action(model, state, candidate_actions)
          scored = score_actions(model, state, candidate_actions)
          raise ArgumentError, "candidate_actions must be non-empty" if scored.empty?

          scored.min_by { |s| [-s.mean_score, s.visit_proxy] }.action
        end

        private

        def weighted_pick(items, weights)
          total = weights.sum
          return items[@rng.rand(items.size)] if total <= 0

          r = @rng.rand * total
          acc = 0.0
          items.each_with_index { |it, i| acc += weights[i]; return it if r <= acc }
          items.last
        end
      end
    end
  end
end
