# lib/cdfl_harness/gateway/middleware/pii.rb
# frozen_string_literal: true

module CDFLHarness
  module Gateway
    module Middleware
      # K-5 analog: redact high-frequency Vietnamese-context PII before an
      # EXTERNAL call. Internal calls pass through untouched. Idempotent.
      class PII
        PATTERNS = [
          [/\b[\w.+-]+@[\w.-]+\.[a-zA-Z]{2,}\b/, "[email]"],
          [/\b(?:\+84|84|0)[3-9]\d{8}\b/, "[phone]"],
          [/\b\d{9,12}\b/, "[id_number]"]
        ].freeze

        def call(prompt:, method:)
          return prompt unless method == :external

          PATTERNS.reduce(prompt) { |acc, (re, repl)| acc.gsub(re, repl) }
        end
      end
    end
  end
end
