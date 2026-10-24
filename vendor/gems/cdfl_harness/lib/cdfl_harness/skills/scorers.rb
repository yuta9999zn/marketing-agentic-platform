# lib/cdfl_harness/skills/scorers.rb
# frozen_string_literal: true

require_relative "change_risk"

# Three change-risk scorers and the procedure that picks between them.
#
# Intellectual property: Nguyễn Trường An. Use requires the author's permission.
#
# Each scorer implements the same two-method contract, so they are interchangeable:
#
#     scorer.fit(rows, outcomes)   # rows = feature vectors, outcomes = 1.0 pass / 0.0 fail
#     scorer.risk(rows)            # → array of P(fail), one per row
#
# `Ridge` and `SingleFeature` need no holdout and therefore use the WHOLE window. `SenseBlocked`
# needs out-of-fold predictions to weight its blocks and to calibrate, so it obtains them by
# cross-fitting and then refits on the whole window — it uses all the data too. That symmetry is
# deliberate: an earlier protocol reserved 25% of the window for the blocked scorer's needs and
# imposed the same cut on its rivals, which manufactured a win that vanished once the rivals were
# trained properly.

module CDFLHarness
  module Skills
    CR = ChangeRisk

    # Baseline that wins on ranking more often than anything else measured. Ridge penalty chosen
    # by out-of-fold likelihood inside the window; then refit on everything.
    class Ridge
      LAMBDAS = [0.0, 0.1, 0.3, 1.0, 3.0, 10.0, 30.0].freeze

      def initialize(folds: 3) = @folds = folds

      def fit(rows, outcomes)
        @cols = CR.live_columns(rows)
        return self if @cols.empty?

        @mu, @sd = CR.standardise(rows, @cols)
        z = CR.design(rows, @cols, @mu, @sd)
        best = LAMBDAS.max_by { |lam| oof_loglik(z, outcomes, lam) }
        @w = CR.ridge_weights(z, outcomes, best)
        @lambda = best
        self
      end

      def risk(rows)
        return rows.map { 0.5 } if @w.nil?

        CR.design(rows, @cols, @mu, @sd).map { |r| 1.0 - CR.sigmoid(r.each_with_index.sum { |v, i| v * @w[i] }) }
      end

      attr_reader :lambda

      private

      def oof_loglik(z, y, lam)
        n = z.size
        parts = (0...n).group_by { |i| i * @folds / n }.values
        total = 0.0
        count = 0
        parts.each do |hold|
          train = (0...n).to_a - hold
          next if train.size < 5 || y.values_at(*train).uniq.size < 2

          w = CR.ridge_weights(z.values_at(*train), y.values_at(*train), lam)
          next if w.nil?

          hold.each do |i|
            p = CR.sigmoid(z[i].each_with_index.sum { |v, k| v * w[k] }).clamp(1e-6, 1 - 1e-6)
            total += Math.log(y[i] > 0.5 ? p : 1 - p)
            count += 1
          end
        end
        count.zero? ? -Float::INFINITY : total / count
      end
    end

    # The cheapest thing that could possibly work: the single best-correlated feature. Kept
    # because it is not a straw man — it beat every other scorer on ranking on one repository
    # (express, AUC 0.851). Always run it; if it wins, ship it and stop.
    class SingleFeature
      def fit(rows, outcomes)
        cols = CR.live_columns(rows)
        return self if cols.empty?

        ybar = outcomes.sum / outcomes.size.to_f
        @j, @sign = cols.map { |j|
          col = rows.map { |r| r[j] }
          mu = col.sum / col.size
          cov = col.each_with_index.sum { |v, i| (v - mu) * (outcomes[i] - ybar) }
          sx = Math.sqrt(col.sum { |v| (v - mu)**2 }) + 1e-12
          [j, cov / sx, cov.abs / sx]
        }.max_by { |(_, _, mag)| mag }.then { |(j, cov, _)| [j, cov.negative? ? -1.0 : 1.0] }
        col = rows.map { |r| r[@j] }
        @mu = col.sum / col.size
        @sd = Math.sqrt(col.sum { |v| (v - @mu)**2 } / col.size) + 1e-9
        self
      end

      def risk(rows)
        return rows.map { 0.5 } if @j.nil?

        rows.map { |r| 1.0 - CR.sigmoid(@sign * (r[@j] - @mu) / @sd) }
      end
    end

    # One block per sense/group of features; each block earns its own penalty and its own weight
    # from out-of-fold ranking skill; blocks with no skill are dropped entirely; the combination
    # is calibrated. Loses to Ridge on ranking about as often as it wins — but its probabilities
    # are the only ones measured to carry a decision threshold (ECE 0.046–0.075 vs 0.071–0.250).
    #
    # `blocks` maps a name to the column indices it owns. With no blocks given it degenerates to
    # one block over everything, i.e. plain ridge — which is exactly the ablation that showed
    # blocking is the component carrying about two thirds of this scorer's advantage.
    class SenseBlocked
      LAMBDAS = Ridge::LAMBDAS

      def initialize(blocks: nil, folds: 3)
        @blocks = blocks
        @folds = folds
      end

      def fit(rows, outcomes)
        live = CR.live_columns(rows)
        groups = (@blocks || { "all" => (0...(rows.first&.size || 0)).to_a })
                 .transform_values { |cs| cs & live }.reject { |_, cs| cs.empty? }
        @models = {}
        oof = {}
        groups.each do |name, cols|
          mu, sd = CR.standardise(rows, cols)
          z = CR.design(rows, cols, mu, sd)
          best = nil
          LAMBDAS.each do |lam|
            o = out_of_fold(z, outcomes, lam)
            next if o.nil?

            a = CR.auc(o, outcomes)
            next if a.nan?

            score = o.each_with_index.sum { |v, i|
              p = CR.sigmoid(v).clamp(1e-6, 1 - 1e-6)
              Math.log(outcomes[i] > 0.5 ? p : 1 - p)
            }
            best = [score, lam, o, a] if best.nil? || score > best[0]
          end
          next if best.nil?

          _, lam, o, a = best
          credit = [(a - 0.5) * 2.0, 0.0].max
          next if credit <= 0.0 # a block that cannot rank is dropped, not shrunk

          w = CR.ridge_weights(z, outcomes, lam)
          next if w.nil?

          @models[name] = { cols: cols, mu: mu, sd: sd, w: w, lambda: lam, auc: a, credit: credit }
          oof[name] = o
        end
        fit_calibrator(oof, outcomes)
        self
      end

      def risk(rows)
        z = combine(rows)
        return rows.map { 0.5 } if z.nil?

        z.map { |v| 1.0 - CR.sigmoid(@platt ? @platt[0] * v + @platt[1] : v) }
      end

      # Which block drove the score for row `i` — the explanation the other scorers cannot give.
      def dominant_block(rows, i)
        return nil if @models.empty?

        parts = block_logits(rows)
        parts.max_by { |_, v| v[i].abs }&.first
      end

      def report = @models.transform_values { |m| { auc: m[:auc].round(3), lambda: m[:lambda] } }

      private

      def out_of_fold(z, y, lam)
        n = z.size
        o = Array.new(n)
        (0...n).group_by { |i| i * @folds / n }.each_value do |hold|
          train = (0...n).to_a - hold
          return nil if train.size < 5 || y.values_at(*train).uniq.size < 2

          w = CR.ridge_weights(z.values_at(*train), y.values_at(*train), lam)
          return nil if w.nil?

          hold.each { |i| o[i] = z[i].each_with_index.sum { |v, k| v * w[k] } }
        end
        o.any?(&:nil?) ? nil : o
      end

      def block_logits(rows)
        total = @models.values.sum { |m| m[:credit] }
        @models.transform_values do |m|
          share = m[:credit] / total
          CR.design(rows, m[:cols], m[:mu], m[:sd])
            .map { |r| share * r.each_with_index.sum { |v, i| v * m[:w][i] } }
        end
      end

      def combine(rows)
        return nil if @models.empty?

        parts = block_logits(rows)
        (0...rows.size).map { |i| parts.values.sum { |v| v[i] } }
      end

      # Calibrated on the OUT-OF-FOLD combination — never on the same numbers the blocks were
      # fitted to. This is the guard that two earlier versions of this code got wrong.
      def fit_calibrator(oof, outcomes)
        @platt = nil
        return if @models.empty? || oof.empty?

        total = @models.values.sum { |m| m[:credit] }
        z = (0...outcomes.size).map do |i|
          @models.sum { |name, m| (m[:credit] / total) * (oof[name] ? oof[name][i] : 0.0) }
        end
        @platt = CR.platt(z, outcomes) if outcomes.uniq.size >= 2
      end
    end

    # The one procedure measured to work: do not guess which scorer suits a project — measure it
    # on that project's own history. Two preregistered attempts to predict the winner from a
    # summary statistic were refuted; this was not.
    module Decision
      module_function

      # `history` = [[features, outcome], ...] in time order. Returns the scorer to deploy plus
      # the evidence for it. `threshold` defaults to the base failure rate, the point at which
      # reviewing everything stops being worthwhile.
      def choose(history, blocks: nil, threshold: nil, reps: 1000, seed: 2026)
        half = history.size / 2
        early = history[0...half]
        late = history[half..] || []
        return { scorer: "ridge", reason: "history too short to decide", evidence: nil } if late.size < 30

        rows_e = early.map(&:first)
        out_e = early.map(&:last)
        rows_l = late.map(&:first)
        out_l = late.map(&:last)
        failed = out_l.map { |o| o > 0.5 ? 0.0 : 1.0 }
        pt = threshold || (failed.sum / failed.size)

        cands = { "ridge" => Ridge.new, "single_feature" => SingleFeature.new,
                  "sense_blocked" => SenseBlocked.new(blocks: blocks) }
        risks = cands.transform_values { |s| s.fit(rows_e, out_e).risk(rows_l) }
        nb = risks.transform_values { |r| CR.net_benefit(r, failed, pt) }
        base = nb["ridge"]
        winner, best = nb.max_by { |_, v| v.nan? ? -Float::INFINITY : v }

        lo, hi = CR.bootstrap_ci(risks[winner], risks["ridge"], failed, reps: reps, seed: seed) do |r, f|
          CR.net_benefit(r, f, pt)
        end
        beats_base = winner != "ridge" && lo > 0
        {
          scorer: beats_base ? winner : "ridge",
          reason: beats_base ? "#{winner} beats ridge at pt=#{pt.round(3)} (CI excludes 0)" : "no candidate beats ridge with confidence — keep the cheap default",
          evidence: { threshold: pt.round(4), net_benefit: nb.transform_values { |v| v.round(4) },
                      best_minus_ridge: (best - base).round(4), ci: [lo.round(4), hi.round(4)],
                      n_early: early.size, n_late: late.size }
        }
      end
    end
  end
end
