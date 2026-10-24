# lib/cdfl_harness/agent/workflow.rb
# frozen_string_literal: true

module CDFLHarness
  module Agent
    # A workflow definition. prompt builders are callables; flags control the
    # critic + grounding behaviour. static_plan (optional) skips the LLM planner.
    Workflow = Struct.new(
      :workflow_id, :input_schema, :allowed_tools,
      :planner_prompt, :critic_prompt, :static_plan,
      :llm_critic, :requires_grounding,
      keyword_init: true
    ) do
      def initialize(workflow_id:, input_schema:, allowed_tools:, planner_prompt:,
                     critic_prompt:, static_plan: nil, llm_critic: true, requires_grounding: false)
        super(workflow_id: workflow_id, input_schema: input_schema,
              allowed_tools: allowed_tools.to_a, planner_prompt: planner_prompt,
              critic_prompt: critic_prompt, static_plan: static_plan,
              llm_critic: llm_critic, requires_grounding: requires_grounding)
      end

      def allowed_tool?(name) = allowed_tools.include?(name)
    end
  end
end
