# lib/cdfl_harness/gateway/client.rb
# frozen_string_literal: true

require_relative "../config"
require_relative "../errors"
require_relative "circuit_breaker"
require_relative "structured_output"
require_relative "router"
require_relative "adapters/base"
require_relative "adapters/fake"
require_relative "adapters/ollama"
require_relative "adapters/anthropic"
require_relative "adapters/openai"
require_relative "middleware/pii"
require_relative "middleware/audit"

module CDFLHarness
  module Gateway
    # The single LLM chokepoint. Resolves a model, runs input middleware
    # (PII), calls the adapter inside a breaker, validates structured output,
    # and records an audit row.
    class Client
      def initialize(config: CDFLHarness.config)
        @config = config
        @router = Router.new(config: config)
        @breaker = CircuitBreaker.new(name: "gateway")
        @audit = config.middleware.find { |m| m.is_a?(Middleware::Audit) } || Middleware::Audit.new
        @input_mw = config.middleware.reject { |m| m.is_a?(Middleware::Audit) }
      end

      def complete(prompt:, task:, consent_external: false, max_tokens: 2000)
        model, method = @router.resolve(task: task, consent_external: consent_external)
        eff_prompt = apply_input_middleware(prompt, method)
        started = monotonic
        completion = @breaker.call { adapter.invoke(model: model, prompt: eff_prompt, max_tokens: max_tokens) }
        @audit.record(task: task, model: model, method: method, prompt: eff_prompt,
                      completion: completion, repaired: false, latency_ms: ms_since(started))
        completion
      end

      def complete_structured(prompt:, task:, schema:, consent_external: false, max_tokens: 2000)
        model, method = @router.resolve(task: task, consent_external: consent_external)
        eff_prompt = apply_input_middleware(prompt, method)
        started = monotonic
        invoke = ->(p) { @breaker.call { adapter.invoke(model: model, prompt: p, max_tokens: max_tokens) } }
        completion = invoke.call(eff_prompt)
        parsed, repaired = StructuredOutput.validate_or_repair(
          completion: completion, schema: schema, original_prompt: eff_prompt, retry_fn: invoke
        )
        @audit.record(task: task, model: model, method: method, prompt: eff_prompt,
                      completion: completion, repaired: repaired, latency_ms: ms_since(started))
        parsed
      end

      def chat(messages:, task:, tools: nil, tool_choice: nil, consent_external: false, max_tokens: 1500)
        model, method = @router.resolve(task: task, consent_external: consent_external)
        @breaker.call do
          adapter.invoke_chat(model: model, messages: messages, tools: tools,
                              tool_choice: tool_choice, max_tokens: max_tokens)
        end
      end

      private

      def adapter
        @adapter ||= @config.adapter_override || build_adapter
      end

      def build_adapter
        case @config.provider
        when :fake then Adapters::Fake.new
        when :ollama then Adapters::Ollama.new(host: @config.ollama_host)
        when :anthropic then Adapters::Anthropic.new(api_key: @config.api_keys[:anthropic])
        when :openai then Adapters::OpenAI.new(api_key: @config.api_keys[:openai])
        else
          raise Errors::ConfigError, "unknown provider #{@config.provider.inspect}"
        end
      end

      def apply_input_middleware(prompt, method)
        @input_mw.reduce(prompt) { |acc, mw| mw.call(prompt: acc, method: method) }
      end

      def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      def ms_since(t) = ((monotonic - t) * 1000).to_i
    end
  end
end
