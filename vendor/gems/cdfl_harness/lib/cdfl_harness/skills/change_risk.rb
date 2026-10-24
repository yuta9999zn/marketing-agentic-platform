# lib/cdfl_harness/skills/change_risk.rb
# frozen_string_literal: true

# Change-risk scoring — a skill distilled from a measured programme.
#
# Intellectual property: Nguyễn Trường An. Use requires the author's permission.
#
# WHAT THIS IS. Given a project's history of changes — each with a feature vector observed BEFORE
# the change was judged, and an outcome (did it later need fixing / did the gate fail) — score new
# changes by risk, and decide which scorer is worth deploying on THIS project.
#
# WHY THREE SCORERS AND NOT ONE. Measured on six public repositories (flutter, vue, express,
# requests, scrapy, Chart.js) plus two private ones, under a protocol where every method gets the
# full history window:
#
#   ranking quality (AUC) : `ridge` wins or ties everywhere. `single_feature` — literally the one
#                           best-correlated column — beat everything on express (0.851 vs 0.835).
#   probability quality   : `sense_blocked` wins on all measured repos (ECE 0.046–0.075 vs
#                           0.071–0.250). Its probabilities can carry a threshold; the others'
#                           cannot.
#   decision value        : at the operating threshold, `sense_blocked` gave +0.056 (scrapy) and
#                           +0.043 (vue) net benefit over ridge — and nothing on requests,
#                           express, Chart.js.
#
# So there is no single best scorer, and — this was tested and failed twice — **no rule predicts
# which one wins on a new project**. A rule based on miscalibration (ECE ≥ 0.12) was preregistered
# and refuted on scrapy. What works is `Decision.choose`: measure net benefit on the first half of
# *your own* history and let that decide.
#
# THE DISCIPLINE IS PART OF THE SKILL. Four failures cost days of work in the source programme and
# are encoded here so they cannot recur silently:
#
#   1. fit and score on DISJOINT slices (`disjoint_halves`) — fitting a calibrator on a slice and
#      then scoring it on the same slice inflated a result twice before it was caught;
#   2. every method gets the FULL window (`Ridge`/`SingleFeature` take no holdout) — reserving 25%
#      for one method's needs and imposing that cut on its rivals manufactured a fake +0.077 win;
#   3. batch size scales with the base rate (`batch_size`) — a fixed batch of 6 on a repo with a
#      2.4% failure rate leaves 87% of batches with nothing to rank, and pooled AUC drifts to 0.5;
#   4. AUC handles ties by average rank (`auc`) — without it a constant predictor scored 0.850.
#
# No gems beyond the standard library.

module CDFLHarness
  module Skills
    module ChangeRisk
      module_function

      # ── linear algebra (small, dense, symmetric) ───────────────────────────────────────────
      # Gaussian elimination with partial pivoting. The systems here are (features+1)², i.e. tens
      # of rows; a hand-rolled solver avoids a dependency and is exact enough.
      def solve(a, b)
        n = b.size
        m = Array.new(n) { |i| a[i].dup << b[i] }
        n.times do |c|
          piv = (c...n).max_by { |r| m[r][c].abs }
          return nil if m[piv][c].abs < 1e-12

          m[c], m[piv] = m[piv], m[c]
          ((c + 1)...n).each do |r|
            f = m[r][c] / m[c][c]
            (c..n).each { |k| m[r][k] -= f * m[c][k] }
          end
        end
        x = Array.new(n, 0.0)
        (n - 1).downto(0) do |r|
          s = m[r][n] - ((r + 1)...n).sum { |k| m[r][k] * x[k] }
          x[r] = s / m[r][r]
        end
        x
      end

      def sigmoid(z) = 1.0 / (1.0 + Math.exp(-z.clamp(-30.0, 30.0)))

      # ── measurement utilities ─────────────────────────────────────────────────────────────
      # AUC with AVERAGE RANKS for ties. Without tie handling a constant predictor scores ~0.85
      # instead of 0.5 — a bug that survived two rounds of review in the source programme.
      def auc(scores, labels)
        pos = labels.count { |l| l > 0.5 }
        neg = labels.size - pos
        return Float::NAN if pos.zero? || neg.zero?

        order = scores.each_with_index.sort_by { |s, _| s }
        ranks = Array.new(scores.size, 0.0)
        i = 0
        while i < order.size
          j = i
          j += 1 while j + 1 < order.size && order[j + 1][0] == order[i][0]
          avg = ((i + 1) + (j + 1)) / 2.0
          (i..j).each { |k| ranks[order[k][1]] = avg }
          i = j + 1
        end
        sum_pos = labels.each_with_index.sum { |l, k| l > 0.5 ? ranks[k] : 0.0 }
        (sum_pos - pos * (pos + 1) / 2.0) / (pos * neg)
      end

      # Expected Calibration Error — the axis on which the blocked scorer consistently wins.
      def ece(probs, labels, bins: 10)
        n = probs.size
        return Float::NAN if n.zero?

        (0...bins).sum do |b|
          lo = b / bins.to_f
          hi = (b + 1) / bins.to_f
          idx = (0...n).select { |i| probs[i] >= lo && (b == bins - 1 ? probs[i] <= hi : probs[i] < hi) }
          next 0.0 if idx.empty?

          mp = idx.sum { |i| probs[i] } / idx.size
          ml = idx.sum { |i| labels[i] } / idx.size
          idx.size / n.to_f * (ml - mp).abs
        end
      end

      # Net benefit at a threshold (Vickers & Elkin). Units: failures caught per change, net of
      # the cost of false alarms. This is the only measure that answers "should I act on this?" —
      # AUC cannot, because ranking says nothing about HOW MANY changes to review.
      def net_benefit(risk, failed, pt)
        n = failed.size
        return Float::NAN if n.zero? || pt >= 1.0

        tp = (0...n).count { |i| risk[i] >= pt && failed[i] > 0.5 }
        fp = (0...n).count { |i| risk[i] >= pt && failed[i] < 0.5 }
        tp / n.to_f - (fp / n.to_f) * (pt / (1 - pt))
      end

      # Batch size must scale with the base rate: aim for >= 3 expected failures per batch.
      def batch_size(base_failure_rate, min_expected: 3.0)
        [[(min_expected / [base_failure_rate, 1e-6].max).round, 6].max, 200].min
      end

      # Fit-slice and score-slice must be DISJOINT. Returns nil when the slice is too short to
      # split — callers must handle that rather than quietly reuse one slice for both.
      def disjoint_halves(indices, min_each: 3)
        return nil if indices.size < 2 * min_each

        k = indices.size / 2
        [indices[0...k], indices[k..]]
      end

      def bootstrap_ci(values_a, values_b, labels, reps: 1000, seed: 2026, &metric)
        rng = Random.new(seed)
        n = labels.size
        diffs = Array.new(reps) do
          idx = Array.new(n) { rng.rand(n) }
          ya = idx.map { |i| values_a[i] }
          yb = idx.map { |i| values_b[i] }
          yl = idx.map { |i| labels[i] }
          metric.call(ya, yl) - metric.call(yb, yl)
        end.reject(&:nan?)
        return [Float::NAN, Float::NAN] if diffs.size < reps / 4

        diffs.sort!
        [diffs[(diffs.size * 0.025).floor], diffs[(diffs.size * 0.975).floor]]
      end

      # ── shared fitting helpers ────────────────────────────────────────────────────────────
      # Columns with no variance in the training window are dropped. A single dead column makes
      # the design matrix rank-deficient; measured on a real repo where one feature was constant.
      def live_columns(rows)
        return [] if rows.empty?

        (0...rows.first.size).select do |j|
          col = rows.map { |r| r[j] }
          mu = col.sum / col.size
          col.sum { |v| (v - mu)**2 } > 1e-12
        end
      end

      def standardise(rows, cols)
        mu = cols.map { |j| rows.sum { |r| r[j] } / rows.size.to_f }
        sd = cols.each_with_index.map do |j, k|
          Math.sqrt(rows.sum { |r| (r[j] - mu[k])**2 } / rows.size.to_f) + 1e-9
        end
        [mu, sd]
      end

      def design(rows, cols, mu, sd)
        rows.map { |r| cols.each_with_index.map { |j, k| (r[j] - mu[k]) / sd[k] } + [1.0] }
      end

      def ridge_weights(z, y, lambda)
        d = z.first.size
        a = Array.new(d) { |i| Array.new(d) { |j| z.sum { |row| row[i] * row[j] } } }
        (0...(d - 1)).each { |i| a[i][i] += lambda } # intercept is never penalised
        b = (0...d).map { |i| z.each_with_index.sum { |row, k| row[i] * (y[k] * 2 - 1) } }
        solve(a, b)
      end

      # Platt scaling p = sigmoid(a*z + b), fitted by Newton steps. MUST be fitted on a slice
      # disjoint from the one it is scored on.
      def platt(z, y, steps: 60)
        a = 1.0
        b = 0.0
        steps.times do
          p = z.map { |v| sigmoid(a * v + b) }
          g0 = z.each_with_index.sum { |v, i| (y[i] - p[i]) * v }
          g1 = y.each_with_index.sum { |t, i| t - p[i] }
          w = p.map { |v| v * (1 - v) + 1e-9 }
          h00 = z.each_with_index.sum { |v, i| w[i] * v * v }
          h01 = z.each_with_index.sum { |v, i| w[i] * v }
          h11 = w.sum
          det = h00 * h11 - h01 * h01
          break if det.abs < 1e-12

          da = (g0 * h11 - g1 * h01) / det
          db = (g1 * h00 - g0 * h01) / det
          a += da
          b += db
          break if da.abs < 1e-9 && db.abs < 1e-9
        end
        [a, b]
      end
    end
  end
end
