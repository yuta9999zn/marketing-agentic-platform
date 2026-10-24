# lib/cdfl_harness/tooling/context.rb
# frozen_string_literal: true

module CDFLHarness
  module Tooling
    # Identity + scope for one tool dispatch. Built from trusted headers/JWT by
    # the host app — NEVER from LLM tool arguments (K-12/K-16). dry_run is
    # consumed by side-effecting tools.
    Context = Struct.new(:scope, :tenant_id, :user_id, :role, :dry_run, keyword_init: true) do
      def initialize(scope:, tenant_id: nil, user_id: nil, role: nil, dry_run: false)
        super(scope: scope, tenant_id: tenant_id, user_id: user_id, role: role, dry_run: dry_run)
      end
    end
  end
end
