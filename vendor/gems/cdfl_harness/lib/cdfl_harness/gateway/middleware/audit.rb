# lib/cdfl_harness/gateway/middleware/audit.rb
# frozen_string_literal: true

require "digest"

module CDFLHarness
  module Gateway
    module Middleware
      # K-6 analog: an audit hook. Stores hashes (not raw text) by default so a
      # project can wire it to a DB without leaking prompts. `sink` is any
      # callable(row_hash); defaults to a no-op.
      class Audit
        def initialize(sink: nil)
          @sink = sink || ->(_row) {}
        end

        def record(task:, model:, method:, prompt:, completion:, repaired:, latency_ms:)
          row = {
            task: task, model: model, method: method,
            prompt_sha: Digest::SHA256.hexdigest(prompt.to_s),
            output_sha: Digest::SHA256.hexdigest(completion.to_s),
            repaired: repaired, latency_ms: latency_ms
          }
          @sink.call(row)
          row
        end
      end
    end
  end
end
