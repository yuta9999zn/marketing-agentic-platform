# lib/cdfl_harness/agent/session.rb
# frozen_string_literal: true

require "securerandom"
require_relative "../types"
require_relative "../errors"
require_relative "../schema"
require_relative "../store/in_memory"
require_relative "../reasoning/cdfl/four_fold_de"
require_relative "../reasoning/memory/service"
require_relative "../grounding/gate"
require_relative "workflows"
require_relative "planner"
require_relative "executor"
require_relative "critic"

module CDFLHarness
  module Agent
    # The orchestrator: validate → PLAN→EXECUTE→CRITIC loop, bounded re-plan +
    # token budget, persistence, memory consolidation, four-fold DE. Never
    # raises out of #run — failures land in status: :failed. Port of
    # agents/orchestrator.py.
    class Session
      def initialize(config: CDFLHarness.config, workflows:, registry:,
                     gateway: nil, store: nil, memory_service: nil)
        @config = config
        @workflows = workflows
        @registry = registry
        @gateway = gateway || Gateway::Client.new(config: config)
        @store = store || config.store || Store::InMemory.new
        @memory = memory_service || config.memory_service
        @planner = Planner.new(gateway: @gateway)
        @executor = Executor.new
        @critic = Critic.new(gateway: @gateway)
      end

      def run(workflow_id:, input:, context:, dry_run: true)
        # Unknown workflow + invalid input both raise WorkflowInputError here,
        # before a session row exists → caught by the method-level rescue at the
        # bottom of #run, which returns a :failed SessionResult (never raises out).
        workflow = @workflows.get(workflow_id)
        validate_input!(input, workflow)

        session_id = SecureRandom.uuid
        @store.create_session(session_id: session_id, tenant_id: context.tenant_id,
                              workflow_id: workflow_id, input: input, dry_run: dry_run)

        transcripts = []
        tokens = 0
        replan = 0
        last_plan = nil
        last_verdict = nil
        error_message = nil
        status = :failed
        ctx = with_dry_run(context, dry_run)

        begin
          loop do
            @store.set_status(session_id: session_id, status: :planning)
            plan, ptoks = @planner.plan_workflow(workflow: workflow, input: input, registry: @registry, scope: ctx.scope)
            tokens += ptoks
            last_plan = plan
            transcripts << add(session_id, Types::TranscriptEntry.new(step_index: transcripts.size, role: "planner", reasoning: plan.rationale.to_s.empty? ? "(no rationale)" : plan.rationale))
            @store.persist_plan(session_id: session_id, plan: plan)

            if tokens > @config.max_tokens_per_session
              error_message = "token_budget_exceeded: #{tokens} > #{@config.max_tokens_per_session}"
              break
            end

            @store.set_status(session_id: session_id, status: :executing)
            start_idx = transcripts.size
            @executor.execute_steps(plan: plan, ctx: ctx, registry: @registry, starting_step_index: start_idx).each do |e|
              transcripts << add(session_id, e)
            end

            @store.set_status(session_id: session_id, status: :critiquing)
            verdict = @critic.review_session(workflow: workflow, input: input, plan: plan, transcripts: transcripts)
            last_verdict = verdict
            transcripts << add(session_id, Types::TranscriptEntry.new(step_index: transcripts.size, role: "critic", reasoning: verdict.reason))
            @store.persist_verdict(session_id: session_id, verdict: verdict)

            case verdict.action
            when "accept"
              status = :completed
              break
            when "escalate"
              status = :escalated
              break
            else # replan
              replan += 1
              @store.bump_replan(session_id: session_id, replan_count: replan)
              if replan > @config.max_replan
                status = :escalated
                error_message = "max_replan_reached: #{@config.max_replan}"
                break
              end
            end
          end
        rescue Errors::Error => e
          error_message = "agent_error: #{e.message}"
          status = :failed
        rescue StandardError => e
          error_message = "unhandled: #{e.message}"
          status = :failed
        end

        @store.finalize(session_id: session_id, status: status, tokens_used: tokens, error_message: error_message)

        consolidate(workflow_id, last_plan, last_verdict, transcripts, context, input) if status == :completed && !dry_run && @memory

        grounding = Grounding::Gate.assess(transcripts)
        four_fold = Reasoning::CDFL::FourFoldDE.assemble(
          data_coverage: 1.0, knowledge_freshness: 1.0,
          knowledge_coverage: grounding[:coverage], grounding_score: grounding[:coverage]
        )

        Types::SessionResult.new(
          session_id: session_id, workflow_id: workflow_id, status: status, dry_run: dry_run,
          plan: last_plan, transcripts: transcripts, critic_verdict: last_verdict,
          tokens_used: tokens, replan_count: replan, error_message: error_message,
          grounding: grounding, four_fold_de: four_fold
        )
      rescue Errors::WorkflowInputError => e
        # unknown workflow / invalid input before the session row exists
        Types::SessionResult.new(session_id: nil, workflow_id: workflow_id, status: :failed,
                                 dry_run: dry_run, error_message: e.message)
      end

      private

      def validate_input!(input, workflow)
        err = Schema.first_error(input, workflow.input_schema)
        raise Errors::WorkflowInputError, "workflow '#{workflow.workflow_id}' input invalid: #{err}" if err
      end

      def add(session_id, entry)
        @store.append_transcript(session_id: session_id, entry: entry)
        entry
      end

      def with_dry_run(context, dry_run)
        Tooling::Context.new(scope: context.scope, tenant_id: context.tenant_id,
                             user_id: context.user_id, role: context.role, dry_run: dry_run)
      end

      def consolidate(workflow_id, plan, verdict, transcripts, context, input)
        question = (input["question"] || "").to_s.strip
        intent = question.empty? ? (plan&.rationale || "").to_s.strip : question
        intent = "(không rõ)" if intent.empty?
        evidence = evidence_summary(transcripts)
        actions = transcripts.select { |t| t.role == "executor" && t.tool_name }.map(&:tool_name)
        outcome = verdict ? verdict.action : "completed"
        content = "[#{workflow_id}] Hỏi: #{intent[0, 200]} → #{outcome}. " \
                  "Cơ sở: #{evidence.empty? ? '(không có bằng chứng)' : evidence} | " \
                  "Hành động: #{actions.first(6).join(', ')}."
        @memory.write(context.tenant_id, :OPERATIONAL, content,
                      metadata: { "workflow_id" => workflow_id, "outcome" => outcome,
                                  "question" => question.empty? ? nil : question })
      rescue StandardError
        nil # memory must never fail a session
      end

      def evidence_summary(transcripts)
        snippets = []
        transcripts.each do |t|
          next unless t.role == "executor" && t.tool_name == "retrieve_evidence"

          res = t.tool_result.is_a?(Hash) ? t.tool_result : {}
          (res["citations"] || []).each do |c|
            snip = c.is_a?(Hash) ? c["snippet"].to_s.strip : ""
            snippets << snip[0, 160] unless snip.empty?
            break if snippets.size >= 3
          end
          break if snippets.size >= 3
        end
        snippets.join(" · ")
      end
    end
  end
end
