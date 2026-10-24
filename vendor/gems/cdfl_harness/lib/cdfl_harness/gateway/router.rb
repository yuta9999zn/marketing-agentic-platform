# lib/cdfl_harness/gateway/router.rb
# frozen_string_literal: true

module CDFLHarness
  module Gateway
    # Resolve a task to [model_id, method]. method in :internal | :external.
    # External is downgraded to the local default when consent is absent or
    # external calls are disabled (port of routing.py K-4 downgrade).
    class Router
      LOCAL_FALLBACK_PROVIDER = :ollama

      def initialize(config:)
        @config = config
      end

      def resolve(task:, consent_external:, model_hint: nil)
        rule = @config.task_routing[task]
        if rule
          model = model_hint || rule[:model] || @config.model_for
          method = rule[:method] || (@config.external? ? :external : :internal)
        else
          model = model_hint || @config.model_for
          method = @config.external? ? :external : :internal
        end

        if method == :external && !(consent_external && @config.external_enabled)
          # Downgrade to a safe local model.
          return [@config.model_map[LOCAL_FALLBACK_PROVIDER], :internal]
        end

        [model, method]
      end
    end
  end
end
