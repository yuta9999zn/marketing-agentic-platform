# lib/cdfl_harness/reasoning/cdfl/info_gain.rb
# frozen_string_literal: true

module CDFLHarness
  module Reasoning
    module CDFL
      # Information Gain scorer. IG(s,a) = novelty(s') + λ·uncertainty(s,a).
      # Port of information_gain.py.
      class InfoGain
        attr_reader :uncertainty_weight, :information_gain_weight

        def initialize(uncertainty_weight: 1.0, information_gain_weight: 1.0)
          @uncertainty_weight = uncertainty_weight
          @information_gain_weight = information_gain_weight
        end

        def novelty(model, state)
          1.0 / Math.sqrt(model.state_visit_count(state) + 1)
        end

        def uncertainty(model, state, action)
          1.0 / Math.sqrt(model.state_action_count(state, action) + 1)
        end

        def score(model, state, action, next_state = nil)
          target = next_state.nil? ? state : next_state
          raw = novelty(model, target) + @uncertainty_weight * uncertainty(model, state, action)
          @information_gain_weight * raw
        end
      end
    end
  end
end
