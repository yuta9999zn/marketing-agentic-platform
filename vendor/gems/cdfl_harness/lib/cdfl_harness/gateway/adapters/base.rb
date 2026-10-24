# lib/cdfl_harness/gateway/adapters/base.rb
# frozen_string_literal: true

require_relative "../../errors"

module CDFLHarness
  module Gateway
    module Adapters
      # Every provider adapter implements #invoke (single prompt -> text) and,
      # for tool-calling, #invoke_chat. #external? tells the router whether
      # PII redaction + consent gating apply.
      class Base
        def invoke(model:, prompt:, max_tokens:)
          raise NotImplementedError, "#{self.class}#invoke"
        end

        # Returns a Hash: { content:, model_used:, tool_calls:, finish_reason: }.
        def invoke_chat(model:, messages:, tools: nil, tool_choice: nil, max_tokens: 1500)
          raise NotImplementedError, "#{self.class}#invoke_chat"
        end

        def external?
          false
        end
      end
    end
  end
end
