# frozen_string_literal: true

require_relative "cdfl_harness/version"
require_relative "cdfl_harness/errors"
require_relative "cdfl_harness/types"
require_relative "cdfl_harness/schema"
require_relative "cdfl_harness/config"

require_relative "cdfl_harness/gateway/circuit_breaker"
require_relative "cdfl_harness/gateway/structured_output"
require_relative "cdfl_harness/gateway/adapters/base"
require_relative "cdfl_harness/gateway/adapters/fake"
require_relative "cdfl_harness/gateway/router"
require_relative "cdfl_harness/gateway/middleware/pii"
require_relative "cdfl_harness/gateway/middleware/audit"
require_relative "cdfl_harness/gateway/client"
require_relative "cdfl_harness/tooling/registry"
require_relative "cdfl_harness/skills/scorers"
require_relative "cdfl_harness/tooling/tools/change_risk_tool"
require_relative "cdfl_harness/tooling/tools/measure_claim_tool"
require_relative "cdfl_harness/tooling/tools/project_readiness_tool"
require_relative "cdfl_harness/store/in_memory"

require_relative "cdfl_harness/reasoning/cdfl"
require_relative "cdfl_harness/reasoning/knowledge/coverage"
require_relative "cdfl_harness/reasoning/knowledge/store"
require_relative "cdfl_harness/reasoning/memory/record"
require_relative "cdfl_harness/reasoning/memory/tier_store"
require_relative "cdfl_harness/reasoning/memory/service"
require_relative "cdfl_harness/grounding/verifier"
require_relative "cdfl_harness/grounding/gate"

require_relative "cdfl_harness/tooling/context"
require_relative "cdfl_harness/agent/workflow"
require_relative "cdfl_harness/agent/workflows"
require_relative "cdfl_harness/agent/planner"
require_relative "cdfl_harness/agent/executor"
require_relative "cdfl_harness/agent/critic"
require_relative "cdfl_harness/agent/session"

module CDFLHarness
  class << self
    # Global default config — a project may instead build its own Config and
    # pass it explicitly to Gateway::Client / Agent::Session.
    def configure
      @config ||= Config.new
      yield @config if block_given?
      @config
    end

    def config
      @config ||= Config.new
    end

    def reset_config!
      @config = Config.new
    end
  end
end
