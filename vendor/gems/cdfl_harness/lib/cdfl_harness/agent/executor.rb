# lib/cdfl_harness/agent/executor.rb
# frozen_string_literal: true

require_relative "../types"
require_relative "../errors"
require_relative "../reasoning/cdfl/empowerment"

module CDFLHarness
  module Agent
    # Dispatches plan steps through the tool registry. dry_run is the tool's
    # concern (it reads ctx.dry_run). Attaches empowerment consent advice for
    # irreversible steps. Hard-stops on a ToolDispatchError. Port of executor.py.
    class Executor
      def execute_steps(plan:, ctx:, registry:, starting_step_index: 1)
        entries = []
        plan.steps.each_with_index do |step, offset|
          entry = execute_one(step, ctx, registry, starting_step_index + offset)
          entries << entry
          break if entry.reasoning.start_with?("[BLOCKED]")
        end
        entries
      end

      private

      def execute_one(step, ctx, registry, step_index)
        tool = registry.fetch(step.tool_name)
        sec = tool && tool.respond_to?(:side_effect_class) ? tool.side_effect_class : "read_only"
        advice = Reasoning::CDFL::Empowerment.protection_advice(sec)

        begin
          ok, result = registry.dispatch(name: step.tool_name, args: step.args, ctx: ctx)
          base = "dispatched ok=#{ok} dry_run=#{ctx.dry_run} rationale=#{step.rationale[0, 120]}"
          reasoning = advice.needs_consent ? "#{base} | ⚠ #{advice.rationale}" : base
        rescue Errors::ToolDispatchError => e
          ok = false
          result = { "error" => e.message }
          reasoning = "[BLOCKED] #{e.message}"
        end

        Types::TranscriptEntry.new(
          step_index: step_index, role: "executor", tool_name: step.tool_name,
          tool_args: step.args, tool_result: result, tool_ok: ok, reasoning: reasoning
        )
      end
    end
  end
end
