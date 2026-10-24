# lib/cdfl_harness/types.rb
# frozen_string_literal: true

module CDFLHarness
  module Types
    # Planner output.
    PlanStep = Struct.new(:tool_name, :args, :rationale, keyword_init: true)
    Plan     = Struct.new(:steps, :rationale, keyword_init: true)

    # Critic output. action ∈ "accept" | "replan" | "escalate".
    CriticVerdict = Struct.new(:action, :reason, :issues, keyword_init: true) do
      def initialize(action:, reason:, issues: [])
        super(action: action, reason: reason, issues: issues)
      end
    end

    # One row of the agent transcript. role ∈ "planner" | "executor" | "critic".
    TranscriptEntry = Struct.new(
      :step_index, :role, :tool_name, :tool_args, :tool_result, :tool_ok, :reasoning,
      keyword_init: true
    ) do
      def initialize(step_index:, role:, tool_name: nil, tool_args: nil,
                     tool_result: nil, tool_ok: nil, reasoning: "")
        super(step_index: step_index, role: role, tool_name: tool_name, tool_args: tool_args,
              tool_result: tool_result, tool_ok: tool_ok, reasoning: reasoning)
      end
    end

    # Final result of one agent session. status ∈ :planning|:executing|:critiquing|
    # :completed|:failed|:escalated.
    SessionResult = Struct.new(
      :session_id, :workflow_id, :status, :dry_run, :plan, :transcripts,
      :critic_verdict, :tokens_used, :replan_count, :error_message,
      :grounding, :four_fold_de,
      keyword_init: true
    ) do
      def initialize(session_id:, workflow_id:, status:, dry_run:, plan: nil, transcripts: [],
                     critic_verdict: nil, tokens_used: 0, replan_count: 0, error_message: nil,
                     grounding: nil, four_fold_de: nil)
        super(session_id: session_id, workflow_id: workflow_id, status: status, dry_run: dry_run,
              plan: plan, transcripts: transcripts, critic_verdict: critic_verdict,
              tokens_used: tokens_used, replan_count: replan_count, error_message: error_message,
              grounding: grounding, four_fold_de: four_fold_de)
      end
    end
  end
end
