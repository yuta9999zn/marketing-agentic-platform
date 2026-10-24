# lib/cdfl_harness/config.rb
# frozen_string_literal: true

module CDFLHarness
  # All harness configuration in one object. A project sets it once via
  # CDFLHarness.configure, or builds its own and passes it explicitly.
  class Config
    EXTERNAL_PROVIDERS = %i[anthropic openai].freeze

    attr_accessor :provider, :api_keys, :model_map, :default_model, :ollama_host,
                  :task_routing, :consent_external, :external_enabled,
                  :max_replan, :max_tokens_per_session, :narrative_max_tokens,
                  :middleware, :store, :knowledge_store, :memory_service,
                  :reasoning, :logger, :adapter_override

    def initialize
      @provider = :fake
      @api_keys = {}                 # { anthropic: "sk-...", openai: "sk-..." }
      @model_map = {                 # provider => default model id
        anthropic: "claude-opus-4-8",
        openai: "gpt-4o",
        ollama: "qwen2.5:14b",
        fake: "fake-model"
      }
      @default_model = nil           # explicit override; else model_map[provider]
      @ollama_host = "http://localhost:11434"
      @task_routing = {}             # "task.glob" => { model:, method: }  (method ∈ :internal|:external)
      @consent_external = false
      @external_enabled = false      # master kill-switch for any external call
      @max_replan = 2
      @max_tokens_per_session = 6000
      @narrative_max_tokens = 400
      @middleware = []               # Array of objects responding to #call(prompt:, method:) (input)
      @store = nil                   # Store::Base (Part 2); defaults to in-memory there
      @knowledge_store = nil         # Reasoning::Knowledge::Store
      @memory_service = nil          # Reasoning::Memory::Service
      @reasoning = ReasoningConfig.new
      @logger = nil
      @adapter_override = nil        # inject a built adapter instance (tests / Fake)
    end

    def external?
      EXTERNAL_PROVIDERS.include?(@provider)
    end

    def model_for(provider = @provider)
      @default_model || @model_map[provider]
    end

    # Tunable reasoning thresholds — env-readable, never hardcoded at call sites.
    class ReasoningConfig
      attr_accessor :coverage_k, :gen_min, :gen_caution, :sim_floor,
                    :mem_mass, :mem_cap, :w_authority, :w_maturity,
                    :learn_rate, :experience_k, :grounding_tol

      def initialize
        @coverage_k    = env_f("CDFL_KB_COVERAGE_K", 0.6)
        @gen_min       = env_f("CDFL_KB_GEN_MIN", 0.60)
        @gen_caution   = env_f("CDFL_KB_GEN_CAUTION", 0.30)
        @sim_floor     = env_f("CDFL_KB_SIM_FLOOR", 0.35)
        @mem_mass      = env_f("CDFL_MEM_MASS", 0.2)
        @mem_cap       = env_f("CDFL_MEM_CAP", 3).to_i
        @w_authority   = env_f("CDFL_KB_W_AUTHORITY", 0.15)
        @w_maturity    = env_f("CDFL_KB_W_MATURITY", 0.10)
        @learn_rate    = env_f("CDFL_MEM_LEARN_RATE", 0.15)
        @experience_k  = env_f("CDFL_MEM_EXPERIENCE_K", 0.15)
        @grounding_tol = env_f("CDFL_GROUNDING_TOL", 0.02)
      end

      def env_f(name, default)
        v = ENV.fetch(name, nil)
        v.nil? ? default : Float(v)
      rescue ArgumentError, TypeError
        default
      end
    end
  end
end
