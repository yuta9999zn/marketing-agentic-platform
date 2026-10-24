# lib/cdfl_harness/tooling/tools/project_readiness_tool.rb
# frozen_string_literal: true

require_relative "../tool"
require_relative "../../skills/project_readiness"

module CDFLHarness
  module Tooling
    module Tools
      # The gate before the other gates: can this project be learned from at all?
      #
      # Intellectual property: Nguyễn Trường An. Use requires the author's permission.
      #
      # An agent should call this **before** `change_risk` or `measure_claim`. Those two assume a
      # project has a point where reality judges and enough recorded judgements to learn from —
      # an assumption that is often false and expensive to discover late.
      #
      # The tool answers in three states and always says what to do next:
      #
      #   not_ready        something blocks learning entirely — no gate, no signal, a leak, or a
      #                    history too thin for disciplined fitting to beat careless fitting
      #   usable_but_thin  explore, but do not act on a result yet; says how many more cases
      #   ready            proceed to change_risk `choose`
      class ProjectReadinessTool < Tool
        tool_name "project_readiness"
        description "Decide whether a project can be learned from at all, before spending effort " \
                    "on it. Checks: is there a gate that judges; are there enough recorded " \
                    "outcomes; is the failure rate workable; is the history in time order; are " \
                    "any features leaking the answer; are columns degenerate; does any signal " \
                    "exist; is the sample big enough for the effect you care about."
        scope "enterprise"
        parameters({
          "type" => "object",
          "properties" => {
            "history" => { "type" => "array",
                           "description" => "changes in time order: [{features:[..], outcome:1|0, at:<epoch, optional>}]",
                           "items" => { "type" => "object" } },
            "feature_phases" => {
              "type" => "array",
              "description" => "one per feature: {name, phase: before|at|after}. Declaring this " \
                               "turns the leakage check from UNCHECKED into a result.",
              "items" => { "type" => "object" }
            },
            "target_effect" => { "type" => "number",
                                 "description" => "optional: the difference you would want to detect" }
          },
          "required" => %w[history]
        })

        def call(args, _ctx)
          history = args["history"]
          raise ArgumentError, "history must be an array" unless history.is_a?(Array)

          history.each_with_index do |h, i|
            f = h["features"] || h[:features]
            o = h["outcome"] || h[:outcome]
            raise ArgumentError, "row #{i} needs features[] and outcome" if f.nil? || o.nil?
          end

          Skills::ProjectReadiness.assess(
            history.map { |h| symbolise(h) },
            feature_phases: args["feature_phases"],
            target_effect: args["target_effect"]
          )
        end

        private

        def symbolise(row)
          { features: row["features"] || row[:features],
            outcome: row["outcome"] || row[:outcome],
            at: row["at"] || row[:at] }
        end
      end
    end
  end
end
