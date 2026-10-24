# lib/cdfl_harness/tooling/tools/measure_claim_tool.rb
# frozen_string_literal: true

require_relative "../tool"
require_relative "../../skills/measure_claim"

module CDFLHarness
  module Tooling
    module Tools
      # Makes an agent prove a claim instead of asserting it.
      #
      # Intellectual property: Nguyễn Trường An. Use requires the author's permission.
      #
      # Intended order of use, and the tool nudges toward it:
      #
      #   power       → is the effect I hope to find bigger than my own measurement noise?
      #   preregister → write the claim, the criterion and the prediction down, locked by hash
      #   compare     → measure, with an interval instead of a point estimate
      #   verify      → check against what was written, and be told how often this data was asked
      #
      # The ledger is per-tool-instance by default and can be persisted by passing `ledger_path`,
      # so preregistrations survive across sessions — which is the whole point: a claim registered
      # in one session must still bind the agent in the next.
      class MeasureClaimTool < Tool
        tool_name "measure_claim"
        description "Prove a claim rather than assert it. Operations: power (is the effect " \
                    "larger than the measurement's own noise?), preregister (lock claim + " \
                    "criterion + prediction before looking), compare (difference with a 95% " \
                    "interval), verify (check against what was registered; reports how many " \
                    "times this data has already been tested)."
        scope "enterprise"
        parameters({
          "type" => "object",
          "properties" => {
            "operation" => { "type" => "string", "enum" => %w[power preregister compare verify],
                             "description" => "power | preregister | compare | verify" },
            "metric" => { "type" => "string", "enum" => %w[mean accuracy auc net_benefit] },
            "values" => { "type" => "array", "items" => { "type" => "number" },
                          "description" => "candidate values (power)" },
            "a" => { "type" => "array", "items" => { "type" => "number" },
                     "description" => "candidate A (compare)" },
            "b" => { "type" => "array", "items" => { "type" => "number" },
                     "description" => "candidate B (compare)" },
            "labels" => { "type" => "array", "items" => { "type" => "number" },
                          "description" => "ground truth, 1 = positive" },
            "target_effect" => { "type" => "number", "description" => "effect you hope to detect (power)" },
            "claim" => { "type" => "string", "description" => "what you are claiming (preregister)" },
            "criterion" => { "type" => "object",
                             "description" => "{direction: greater|less|equivalent, margin: number}" },
            "prediction" => { "type" => "string", "description" => "what you predict: true | false" },
            "id" => { "type" => "string", "description" => "preregistration id (verify)" },
            "observed_difference" => { "type" => "number" },
            "ci95" => { "type" => "array", "items" => { "type" => "number" } }
          },
          "required" => %w[operation]
        })

        def initialize(ledger_path: nil)
          super()
          @ledger = Skills::MeasureClaim::Ledger.new(path: ledger_path)
        end

        attr_reader :ledger

        def call(args, _ctx)
          case args["operation"]
          when "power" then run_power(args)
          when "preregister" then run_preregister(args)
          when "compare" then run_compare(args)
          when "verify" then run_verify(args)
          else raise ArgumentError, "unknown operation: #{args['operation'].inspect}"
          end
        end

        private

        def nums(args, key)
          v = args[key]
          raise ArgumentError, "#{key} must be a non-empty array of numbers" unless v.is_a?(Array) && !v.empty?

          v.map(&:to_f)
        end

        def same_length!(*arrays)
          return if arrays.map(&:size).uniq.size == 1

          raise ArgumentError, "arrays must be the same length"
        end

        def run_power(args)
          values = nums(args, "values")
          labels = nums(args, "labels")
          same_length!(values, labels)
          raise ArgumentError, "target_effect required" if args["target_effect"].nil?

          @ledger.power(values: values, labels: labels, metric: args.fetch("metric", "mean"),
                        target_effect: args["target_effect"])
        end

        def run_preregister(args)
          raise ArgumentError, "claim required" if args["claim"].to_s.strip.empty?

          @ledger.preregister(claim: args["claim"], metric: args.fetch("metric", "mean"),
                              criterion: args["criterion"], prediction: args["prediction"],
                              data_fingerprint: args["labels"] ? @ledger.fingerprint_of(nums(args, "labels")) : nil)
        end

        def run_compare(args)
          a = nums(args, "a")
          b = nums(args, "b")
          labels = nums(args, "labels")
          same_length!(a, b, labels)
          @ledger.compare(a: a, b: b, labels: labels, metric: args.fetch("metric", "mean"))
                 .merge(data_fingerprint: @ledger.fingerprint_of(labels))
        end

        def run_verify(args)
          raise ArgumentError, "id required" if args["id"].to_s.empty?
          raise ArgumentError, "ci95 must be [low, high]" unless args["ci95"].is_a?(Array) && args["ci95"].size == 2

          @ledger.verify(id: args["id"], observed_difference: args.fetch("observed_difference", 0.0),
                         ci95: args["ci95"],
                         data_fingerprint: args["labels"] ? @ledger.fingerprint_of(nums(args, "labels")) : nil)
        end
      end
    end
  end
end
