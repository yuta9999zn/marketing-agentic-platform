# lib/cdfl_harness/tooling/tools/change_risk_tool.rb
# frozen_string_literal: true

require_relative "../tool"
require_relative "../../skills/scorers"

module CDFLHarness
  module Tooling
    module Tools
      # Exposes the change-risk skill to an agent as one tool with three operations.
      #
      # Intellectual property: Nguyễn Trường An. Use requires the author's permission.
      #
      # The tool deliberately refuses to pick a scorer for the agent by default: `choose` measures
      # on the project's own history and returns the evidence. Two attempts to predict the right
      # scorer from a summary statistic were preregistered and refuted, so the tool does not offer
      # that shortcut — an agent that wants a scorer must either name one or pay for the
      # measurement.
      class ChangeRiskTool < Tool
        tool_name "change_risk"
        description "Score code changes by risk, or decide which scorer suits this project. " \
                    "Operations: choose (measure on own history, recommend a scorer + evidence), " \
                    "score (fit on history, score new changes), explain (which feature block " \
                    "drove a score)."
        scope "enterprise"
        parameters({
          "type" => "object",
          "properties" => {
            "operation" => { "type" => "string", "enum" => %w[choose score explain],
                             "description" => "choose | score | explain" },
            "history" => { "type" => "array",
                           "description" => "past changes in time order: [{features:[..], outcome:1|0}]",
                           "items" => { "type" => "object" } },
            "candidates" => { "type" => "array",
                              "description" => "new changes to score: [{features:[..]}]",
                              "items" => { "type" => "object" } },
            "scorer" => { "type" => "string", "enum" => %w[ridge single_feature sense_blocked],
                          "description" => "required for score/explain" },
            "blocks" => { "type" => "object",
                          "description" => "optional {block_name: [column indices]} for sense_blocked" },
            "threshold" => { "type" => "number",
                             "description" => "operating threshold; defaults to the base failure rate" }
          },
          "required" => %w[operation history]
        })

        def call(args, _ctx)
          history = parse_history(args["history"])
          raise ArgumentError, "history needs at least 40 rows with both outcomes" if too_thin?(history)

          blocks = symbolise_blocks(args["blocks"])
          case args["operation"]
          when "choose"  then Skills::Decision.choose(history, blocks: blocks, threshold: args["threshold"])
          when "score"   then run_score(args, history, blocks)
          when "explain" then run_explain(args, history, blocks)
          else raise ArgumentError, "unknown operation: #{args['operation'].inspect}"
          end
        end

        private

        def parse_history(raw)
          raise ArgumentError, "history must be an array" unless raw.is_a?(Array)

          raw.map do |h|
            f = h["features"] || h[:features]
            o = h["outcome"] || h[:outcome]
            raise ArgumentError, "each history row needs features[] and outcome" if f.nil? || o.nil?

            [Array(f).map(&:to_f), o.to_f]
          end
        end

        def too_thin?(history)
          history.size < 40 || history.map(&:last).uniq.size < 2
        end

        def symbolise_blocks(blocks)
          return nil if blocks.nil?

          blocks.to_h { |k, v| [k.to_s, Array(v).map(&:to_i)] }
        end

        def build(name, blocks)
          case name
          when "ridge" then Skills::Ridge.new
          when "single_feature" then Skills::SingleFeature.new
          when "sense_blocked" then Skills::SenseBlocked.new(blocks: blocks)
          else raise ArgumentError, "scorer must be one of ridge|single_feature|sense_blocked"
          end
        end

        def candidate_rows(args)
          rows = Array(args["candidates"]).map { |c| Array(c["features"] || c[:features]).map(&:to_f) }
          raise ArgumentError, "candidates required" if rows.empty?

          rows
        end

        def run_score(args, history, blocks)
          scorer = build(args["scorer"], blocks).fit(history.map(&:first), history.map(&:last))
          rows = candidate_rows(args)
          { scorer: args["scorer"], risk: scorer.risk(rows).map { |v| v.round(4) } }
        end

        def run_explain(args, history, blocks)
          raise ArgumentError, "explain only works with sense_blocked" unless args["scorer"] == "sense_blocked"

          scorer = Skills::SenseBlocked.new(blocks: blocks).fit(history.map(&:first), history.map(&:last))
          rows = candidate_rows(args)
          { scorer: "sense_blocked", blocks_used: scorer.report,
            risk: scorer.risk(rows).map { |v| v.round(4) },
            dominant_block: rows.each_index.map { |i| scorer.dominant_block(rows, i) } }
        end
      end
    end
  end
end
