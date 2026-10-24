# lib/cdfl_harness/store/in_memory.rb
# frozen_string_literal: true

require_relative "base"

module CDFLHarness
  module Store
    # Single-process, dict-backed default. Good for tests + the demo + any
    # project that doesn't need durable transcripts.
    class InMemory < Base
      def initialize
        @sessions = {}
      end

      def create_session(session_id:, tenant_id:, workflow_id:, input:, dry_run:)
        @sessions[session_id] = {
          session_id: session_id, tenant_id: tenant_id, workflow_id: workflow_id,
          input: input, dry_run: dry_run, status: :planning,
          plan: nil, verdict: nil, replan_count: 0, tokens_used: 0,
          error_message: nil, transcripts: []
        }
      end

      def set_status(session_id:, status:)       = row(session_id)[:status] = status
      def persist_plan(session_id:, plan:)       = row(session_id)[:plan] = plan
      def persist_verdict(session_id:, verdict:) = row(session_id)[:verdict] = verdict
      def bump_replan(session_id:, replan_count:) = row(session_id)[:replan_count] = replan_count
      def append_transcript(session_id:, entry:)  = row(session_id)[:transcripts] << entry

      def finalize(session_id:, status:, tokens_used:, error_message:)
        r = row(session_id)
        r[:status] = status
        r[:tokens_used] = tokens_used
        r[:error_message] = error_message
      end

      def get(session_id:) = @sessions[session_id]

      private

      def row(session_id)
        @sessions[session_id] || raise(Errors::Error, "unknown session #{session_id}")
      end
    end
  end
end
