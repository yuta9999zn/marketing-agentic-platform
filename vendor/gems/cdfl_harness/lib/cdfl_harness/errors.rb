# lib/cdfl_harness/errors.rb
# frozen_string_literal: true

module CDFLHarness
  module Errors
    class Error < StandardError; end

    # Bad configuration (no adapter, missing key in strict mode, etc.).
    class ConfigError < Error; end

    # A provider adapter failed (HTTP error, circuit open, no scripted reply).
    class AdapterError < Error; end

    # Caller asked for an external provider but consent/keys are not present.
    class ConsentDeniedError < Error; end

    # Workflow input failed JSON-schema validation.
    class WorkflowInputError < Error; end

    # Session blew its token budget.
    class TokenBudgetExceeded < Error; end

    # A tool dispatch was blocked (unknown tool, forbidden arg, scope/auth).
    class ToolDispatchError < Error; end

    # The gateway could not produce schema-valid JSON after the repair round.
    class StructuredOutputError < Error
      attr_reader :attempts, :last_completion, :last_error

      def initialize(message = "structured output failed", attempts: 1,
                     last_completion: nil, last_error: nil)
        super(message)
        @attempts = attempts
        @last_completion = last_completion
        @last_error = last_error
      end
    end
  end
end
