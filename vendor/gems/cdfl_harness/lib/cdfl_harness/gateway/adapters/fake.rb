# lib/cdfl_harness/gateway/adapters/fake.rb
# frozen_string_literal: true

require_relative "base"

module CDFLHarness
  module Gateway
    module Adapters
      # Offline adapter for tests + the demo. Pops scripted replies in order.
      # A scripted entry may be a String or a callable(prompt) -> String.
      class Fake < Base
        def initialize(completions: [], chats: [])
          @completions = completions.dup
          @chats = chats.dup
        end

        def invoke(model:, prompt:, max_tokens:)
          raise Errors::AdapterError, "Fake adapter: no more scripted completions" if @completions.empty?

          nxt = @completions.shift
          nxt.respond_to?(:call) ? nxt.call(prompt) : nxt
        end

        def invoke_chat(model:, messages:, tools: nil, tool_choice: nil, max_tokens: 1500)
          raise Errors::AdapterError, "Fake adapter: no more scripted chats" if @chats.empty?

          nxt = @chats.shift
          nxt.respond_to?(:call) ? nxt.call(messages) : nxt
        end

        def external?
          false
        end
      end
    end
  end
end
