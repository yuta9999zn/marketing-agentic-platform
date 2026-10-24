# lib/cdfl_harness/reasoning/cdfl/types.rb
# frozen_string_literal: true

module CDFLHarness
  module Reasoning
    module CDFL
      Transition  = Struct.new(:state, :action, :next_state, keyword_init: true)
      ActionScore = Struct.new(:action, :mean_score, :best_score, :visit_proxy, keyword_init: true)
      RolloutResult = Struct.new(:trajectory, :total_information_gain, keyword_init: true) do
        def initialize(trajectory: [], total_information_gain: 0.0)
          super(trajectory: trajectory, total_information_gain: total_information_gain)
        end
      end
    end
  end
end
