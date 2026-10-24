# lib/cdfl_harness/agent/critic.rb
# frozen_string_literal: true

require_relative "../types"
require_relative "../grounding/gate"

module CDFLHarness
  module Agent
    # Reviews the executor transcript → verdict (accept|replan|escalate). Runs
    # the |OR| grounding gate first; for non-LLM workflows the gate IS the
    # verdict; for LLM workflows with requires_grounding an ungrounded accept is
    # overridden to replan. Port of agents/critic.py.
    class Critic
      VERDICT_OUTPUT_SCHEMA = {
        "$schema" => "https://json-schema.org/draft/2020-12/schema",
        "type" => "object", "additionalProperties" => false,
        "required" => %w[action reason],
        "properties" => {
          "action" => { "type" => "string", "enum" => %w[accept replan escalate] },
          "reason" => { "type" => "string", "minLength" => 1, "maxLength" => 1500 },
          "issues" => { "type" => "array", "maxItems" => 10, "items" => { "type" => "string", "maxLength" => 200 } }
        }
      }.freeze

      def initialize(gateway:)
        @gateway = gateway
      end

      def review_session(workflow:, input:, plan:, transcripts:)
        grounding = Grounding::Gate.assess(transcripts)
        note = "\n\n[Cổng |OR| — độ phủ bằng chứng]: #{(grounding[:coverage] * 100).round}% " \
               "(#{grounding[:band]}); #{grounding[:evidence_count]} trích dẫn, #{grounding[:memory_hits]} ký ức. #{grounding[:note]}"

        unless workflow.llm_critic
          action = grounding[:can_generalize] ? "accept" : "replan"
          reason = "Cổng |OR| (tất định): độ phủ #{(grounding[:coverage] * 100).round}% (#{grounding[:band]}). #{grounding[:note]}"
          return Types::CriticVerdict.new(action: action, reason: reason[0, 1500],
                                          issues: action == "accept" ? [] : ["|OR| grounding insufficient"])
        end

        prompt = workflow.critic_prompt.call(plan, transcripts, input) + note
        parsed = @gateway.complete_structured(
          prompt: prompt, task: "agent.critic.#{workflow.workflow_id}",
          schema: VERDICT_OUTPUT_SCHEMA, consent_external: false, max_tokens: 1500
        )
        verdict = Types::CriticVerdict.new(action: parsed["action"], reason: parsed["reason"], issues: parsed["issues"] || [])

        if workflow.requires_grounding && !grounding[:can_generalize] && verdict.action == "accept"
          verdict = Types::CriticVerdict.new(
            action: "replan",
            reason: ("Cổng |OR|: chưa đủ cơ sở (#{(grounding[:coverage] * 100).round}%) để chấp nhận — " \
                     "cần truy hồi thêm bằng chứng trước khi kết luận. #{verdict.reason}")[0, 1500],
            issues: (verdict.issues + ["|OR| grounding insufficient"]).first(10)
          )
        end
        verdict
      end
    end
  end
end
