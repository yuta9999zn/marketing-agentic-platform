# lib/cdfl_harness/store/base.rb
# frozen_string_literal: true

module CDFLHarness
  module Store
    # Persistence contract for agent sessions. A project swaps this for a DB
    # adapter; the harness only calls these methods.
    class Base
      def create_session(session_id:, tenant_id:, workflow_id:, input:, dry_run:); raise NotImplementedError; end
      def set_status(session_id:, status:); raise NotImplementedError; end
      def append_transcript(session_id:, entry:); raise NotImplementedError; end
      def persist_plan(session_id:, plan:); raise NotImplementedError; end
      def persist_verdict(session_id:, verdict:); raise NotImplementedError; end
      def bump_replan(session_id:, replan_count:); raise NotImplementedError; end
      def finalize(session_id:, status:, tokens_used:, error_message:); raise NotImplementedError; end
      def get(session_id:); raise NotImplementedError; end
    end
  end
end
