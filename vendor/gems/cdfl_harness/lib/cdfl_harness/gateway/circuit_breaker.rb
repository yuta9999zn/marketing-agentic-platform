# lib/cdfl_harness/gateway/circuit_breaker.rb
# frozen_string_literal: true

require_relative "../errors"

module CDFLHarness
  module Gateway
    # Per-adapter breaker. Opens after `failure_threshold` failures inside
    # `window` seconds; blocks for `cooldown` seconds; a success while
    # half-open resets it. `clock` is injectable for deterministic tests.
    class CircuitBreaker
      def initialize(name:, failure_threshold: 5, window: 30, cooldown: 60, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @name = name
        @failure_threshold = failure_threshold
        @window = window
        @cooldown = cooldown
        @clock = clock
        @failures = []        # timestamps of recent failures
        @opened_at = nil
      end

      def call
        now = @clock.call
        if @opened_at
          raise Errors::AdapterError, "circuit open for #{@name}" if now - @opened_at < @cooldown

          @opened_at = nil    # half-open: allow one trial
          @failures.clear
        end

        begin
          result = yield
          @failures.clear     # success closes the window
          result
        rescue StandardError
          record_failure(now)
          raise
        end
      end

      private

      def record_failure(now)
        @failures << now
        @failures.reject! { |t| now - t > @window }
        @opened_at = now if @failures.size >= @failure_threshold
      end
    end
  end
end
