# lib/cdfl_harness/agent/planner.rb
# frozen_string_literal: true

require "json"
require_relative "../types"
require_relative "../errors"

module CDFLHarness
  module Agent
    # Single LLM call → ordered tool steps (Plan). Port of agents/planner.py.
    class Planner
      PLAN_OUTPUT_SCHEMA = {
        "$schema" => "https://json-schema.org/draft/2020-12/schema",
        "type" => "object", "additionalProperties" => false,
        "required" => %w[steps rationale],
        "properties" => {
          "steps" => {
            "type" => "array", "minItems" => 1, "maxItems" => 10,
            "items" => {
              "type" => "object", "additionalProperties" => false,
              "required" => %w[tool_name args rationale],
              "properties" => {
                "tool_name" => { "type" => "string", "minLength" => 1 },
                "args" => { "type" => "object" },
                "rationale" => { "type" => "string", "maxLength" => 500 }
              }
            }
          },
          "rationale" => { "type" => "string", "maxLength" => 2000 }
        }
      }.freeze

      def initialize(gateway:)
        @gateway = gateway
      end

      # Returns [Plan, tokens_used].
      def plan_workflow(workflow:, input:, registry:, scope: "enterprise")
        if workflow.static_plan
          steps = workflow.static_plan.call(input)
          steps.each_with_index do |s, i|
            unless workflow.allowed_tool?(s.tool_name)
              raise ArgumentError, "static plan step #{i + 1} tool '#{s.tool_name}' not in workflow allowed_tools"
            end
          end
          return [Types::Plan.new(steps: steps, rationale: "(static plan — no LLM planner)"), 0]
        end

        tools_block = render_tools(registry, workflow.allowed_tools, scope)
        prompt = "#{workflow.planner_prompt.call(input)}\n\n#{tools_block}"
        parsed = @gateway.complete_structured(
          prompt: prompt, task: "agent.plan.#{workflow.workflow_id}",
          schema: PLAN_OUTPUT_SCHEMA, consent_external: false, max_tokens: 2000
        )

        steps = parsed.fetch("steps").map do |s|
          Types::PlanStep.new(tool_name: s["tool_name"], args: s["args"] || {}, rationale: s["rationale"] || "")
        end
        steps.each_with_index do |s, i|
          unless workflow.allowed_tool?(s.tool_name)
            raise ArgumentError, "planner picked tool '#{s.tool_name}' (step #{i + 1}) not in workflow allowed_tools=#{workflow.allowed_tools.sort}"
          end
        end
        [Types::Plan.new(steps: steps, rationale: parsed["rationale"] || ""), 0]
      end

      private

      def render_tools(registry, allowed, scope)
        lines = ["Tool có sẵn:"]
        registry.list_for_scope(scope).each do |tool|
          name = tool.class.tool_name
          next unless allowed.include?(name)

          lines << "  • #{name} — #{tool.class.description}\n      params: #{JSON.generate(tool.class.parameters)}"
        end
        if lines.size == 1
          raise Errors::ConfigError, "planner has no tools — workflow allowed_tools ∩ registry is empty"
        end

        lines.join("\n")
      end
    end
  end
end
