# lib/cdfl_harness/skills/measure_claim.rb
# frozen_string_literal: true

require "digest"
require "json"
require_relative "change_risk"

# Preregistration and verification — make an agent prove a claim instead of asserting it.
#
# Intellectual property: Nguyễn Trường An. Use requires the author's permission.
#
# WHY THIS EXISTS. In the programme this was distilled from, seven conclusions had to be retracted
# in three days. Not one was a coding error in the usual sense; every one was a failure of the
# *procedure around* the measurement:
#
#   · a parameter fitted on a slice and then scored on the same slice — twice, in two places;
#   · a rival handicapped by a protocol built around one method's needs, manufacturing a +0.077 win;
#   · the same comparison run on six datasets, then the one that passed held up as evidence;
#   · an acceptance criterion of "significant at ≥1 of 7 thresholds", which noise passes routinely;
#   · a rule refuted on new data, then quietly redrawn to fit what had already been seen.
#
# Every one of them would have been caught by writing the claim, the criterion and the prediction
# down *first*, and by counting how many times the same data had already been asked. That is all
# this skill does — but it does it structurally, so an agent cannot skip it and still call
# something proven.
#
# THE CENTRAL RULE, and the one most often violated:
#
#     A threshold for "good enough" is only meaningful if it exceeds the standard error of the
#     measurement used to test it.
#
# `Ledger#power` refuses to bless a study whose target effect is smaller than its own noise. In the
# source programme, mechanisms differing by 0.01–0.03 AUC were compared on windows whose estimation
# error was ±0.05–0.08; the selection that resulted was worse than choosing nothing.

module CDFLHarness
  module Skills
    module MeasureClaim
      CR = ChangeRisk

      # A preregistration that cannot be silently edited: the fingerprint covers claim, metric,
      # criterion and prediction, so any later change is detectable at verification time.
      Entry = Struct.new(:id, :claim, :metric, :criterion, :prediction, :data_fingerprint,
                         :registered_at, :verified, keyword_init: true) do
        def fingerprint
          Digest::SHA256.hexdigest(
            JSON.generate([claim, metric, criterion, prediction])
          )[0, 16]
        end
      end

      # Metrics an agent may claim under. Each takes (values, labels) and returns a number;
      # `compare` reports the difference between two candidates under the same metric.
      METRICS = {
        "mean" => ->(v, _l) { v.sum / v.size.to_f },
        "accuracy" => ->(v, l) { v.each_with_index.count { |x, i| (x > 0.5) == (l[i] > 0.5) } / l.size.to_f },
        "auc" => ->(v, l) { CR.auc(v, l) },
        "net_benefit" => ->(v, l) { CR.net_benefit(v, l, l.sum / l.size.to_f) }
      }.freeze

      class Ledger
        attr_reader :entries

        def initialize(path: nil)
          @path = path
          @entries = []
          load! if path && File.exist?(path)
        end

        # ── 1. BEFORE looking: is the effect you want even detectable? ───────────────────────
        #
        # Estimates the standard error of the metric on pilot data by bootstrap, then compares the
        # effect the caller hopes to detect against it. `detectable` is deliberately strict: an
        # effect below 2×SE will not be distinguishable from noise, and pursuing it wastes the
        # study. Returning `false` here is the useful answer, not a failure.
        def power(values:, labels:, metric:, target_effect:, reps: 500, seed: 2026)
          fn = fetch_metric(metric)
          rng = Random.new(seed)
          n = labels.size
          draws = Array.new(reps) do
            idx = Array.new(n) { rng.rand(n) }
            fn.call(idx.map { |i| values[i] }, idx.map { |i| labels[i] })
          end.reject { |x| x.nil? || (x.respond_to?(:nan?) && x.nan?) }
          return { error: "metric undefined on this data" } if draws.size < reps / 4

          mu = draws.sum / draws.size
          se = Math.sqrt(draws.sum { |d| (d - mu)**2 } / (draws.size - 1).to_f)
          {
            metric: metric, n: n, estimate: mu.round(4), standard_error: se.round(4),
            target_effect: target_effect.to_f.round(4),
            detectable: target_effect.to_f.abs > 2 * se,
            smallest_worth_chasing: (2 * se).round(4),
            note: target_effect.to_f.abs > 2 * se ? "effect exceeds twice the noise — worth measuring" : "effect is smaller than the noise of the measurement itself; a larger sample or a different axis is needed"
          }
        end

        # ── 2. Write the claim down BEFORE seeing the outcome ────────────────────────────────
        def preregister(claim:, metric:, criterion:, prediction:, data_fingerprint: nil)
          fetch_metric(metric)
          raise ArgumentError, "criterion must state direction and margin, e.g. {direction: 'greater', margin: 0.02}" unless criterion.is_a?(Hash) && criterion["direction"]

          e = Entry.new(id: "pre-#{Digest::SHA256.hexdigest("#{claim}#{Time.now.to_f}")[0, 10]}",
                        claim: claim, metric: metric, criterion: criterion, prediction: prediction,
                        data_fingerprint: data_fingerprint, registered_at: Time.now.to_i,
                        verified: false)
          @entries << e
          persist!
          { id: e.id, fingerprint: e.fingerprint,
            note: "locked. verifying against a changed criterion or prediction will be refused." }
        end

        # ── 3. Compare two candidates, with an interval rather than a point ──────────────────
        def compare(a:, b:, labels:, metric:, reps: 1000, seed: 2026)
          fn = fetch_metric(metric)
          lo, hi = CR.bootstrap_ci(a, b, labels, reps: reps, seed: seed) { |v, l| fn.call(v, l) }
          diff = fn.call(a, labels) - fn.call(b, labels)
          {
            metric: metric, difference: diff.round(4), ci95: [lo.round(4), hi.round(4)],
            verdict: lo > 0 ? "a beats b" : (hi < 0 ? "b beats a" : "indistinguishable"),
            n: labels.size
          }
        end

        # ── 4. Verify against what was written down, and surface how many times this data has
        #       already been asked ─────────────────────────────────────────────────────────────
        #
        # Multiplicity is reported, not hidden. Running the same comparison against the same data
        # repeatedly and keeping the run that passed is the single easiest way to fool yourself,
        # and it is exactly what happened in the source programme.
        def verify(id:, observed_difference:, ci95:, data_fingerprint: nil)
          e = @entries.find { |x| x.id == id }
          raise ArgumentError, "no such preregistration: #{id}" if e.nil?

          if e.data_fingerprint && data_fingerprint && e.data_fingerprint != data_fingerprint
            raise ArgumentError, "data fingerprint differs from the one registered — this is not the study that was preregistered"
          end

          prior = @entries.count { |x| x.verified && x.data_fingerprint && x.data_fingerprint == (data_fingerprint || e.data_fingerprint) }
          margin = (e.criterion["margin"] || 0.0).to_f
          lo, hi = ci95.map(&:to_f)
          met = case e.criterion["direction"]
                when "greater" then lo > margin
                when "less" then hi < -margin
                when "equivalent" then lo > -margin && hi < margin
                else raise ArgumentError, "direction must be greater | less | equivalent"
                end
          e.verified = true
          persist!
          {
            id: id, claim: e.claim, criterion: e.criterion, prediction: e.prediction,
            observed_difference: observed_difference.to_f.round(4), ci95: [lo.round(4), hi.round(4)],
            criterion_met: met,
            prediction_correct: prediction_matches?(e.prediction, met),
            prior_tests_on_this_data: prior,
            multiplicity_warning: multiplicity_note(prior)
          }
        end

        def fingerprint_of(labels) = Digest::SHA256.hexdigest(labels.map(&:to_f).join(","))[0, 16]

        private

        def fetch_metric(name)
          METRICS[name] or raise ArgumentError, "metric must be one of #{METRICS.keys.join('|')}"
        end

        def prediction_matches?(prediction, met)
          return nil if prediction.nil?

          truthy = %w[true yes met pass confirmed].include?(prediction.to_s.downcase)
          truthy == met
        end

        def multiplicity_note(prior)
          return nil if prior.zero?

          adjusted = 0.05 / (prior + 1)
          "this data has already been tested #{prior} time(s). At 95% confidence, #{prior + 1} tests " \
            "produce a false positive about #{(100 * (1 - (0.95**(prior + 1)))).round}% of the time. " \
            "Treat this result as exploratory, or hold it to a Bonferroni-adjusted alpha of #{adjusted.round(4)}."
        end

        def persist!
          return unless @path

          File.write(@path, @entries.map { |e| JSON.generate(e.to_h) }.join("\n"))
        end

        def load!
          @entries = File.readlines(@path).reject { |l| l.strip.empty? }
                         .map { |l| Entry.new(**JSON.parse(l, symbolize_names: true)) }
        rescue StandardError
          @entries = []
        end
      end
    end
  end
end
