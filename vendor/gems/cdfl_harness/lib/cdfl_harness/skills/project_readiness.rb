# lib/cdfl_harness/skills/project_readiness.rb
# frozen_string_literal: true

require_relative "change_risk"

# Is this project ready to be learned from at all?
#
# Intellectual property: Nguyễn Trường An. Use requires the author's permission.
#
# THE GATE BEFORE THE OTHER GATES. Both `change_risk` and `measure_claim` assume something that is
# often false: that the project has a place where reality passes judgement, and that enough of
# those judgements have been recorded to learn from. Checking that first is not bureaucracy — it
# is the difference between a measurement and a decoration.
#
# The rule this encodes, from the source programme:
#
#     A project with no point at which reality judges cannot host a learner at all.
#
# A real operating system built entirely on measurable theory was found to have a full test suite
# (72/72) and **no recorded history** — every run's verdict evaporated. Nothing could be learned
# from it, not because the work was poor but because nothing was written down. The fix was not a
# better model; it was one commit that started keeping the book.
#
# WHAT IS CHECKED, and the measurement behind each threshold:
#
#   gate exists      outcomes present, both classes seen. Without this: nothing.
#   density          ~150 cases before a learner is worth building. Below ~25 the disciplined
#                    approach LOSES to the careless one — measured, 0.405 vs 0.736 on a 15-case
#                    project, because holding out a validation slice starves an already-thin fit.
#   base rate        extremes make batching impossible: at a 2.4% failure rate a batch needs ~126
#                    changes to contain 3 failures, so a short history yields almost no usable
#                    batches — and pooled scores drift toward 0.5, which looks like a broken model.
#   leakage          each feature must be observable BEFORE the verdict. Declared per feature; an
#                    undeclared feature set is reported as UNCHECKED rather than assumed clean,
#                    because two leaks in the source programme each produced a beautiful result
#                    that collapsed when closed.
#   degeneracy       constant columns make the design matrix rank-deficient; near-duplicates
#                    inflate condition numbers into the 10^16 range.
#   signal           if the best single feature cannot rank better than chance, no model built on
#                    these features will either. Cheapest possible existence proof.
#   power            the smallest effect this sample could distinguish. If it is larger than the
#                    difference you care about, the project is not ready for that question yet.

module CDFLHarness
  module Skills
    module ProjectReadiness
      CR = ChangeRisk

      MIN_TO_LEARN = 150       # cases with outcomes before a learner is worth building
      MIN_TO_TRY = 25          # below this, disciplined fitting loses to careless fitting
      BASE_RATE_FLOOR = 0.02   # outside [floor, 1-floor] batching becomes impractical
      SIGNAL_FLOOR = 0.55      # best single feature must beat this to prove any signal exists

      module_function

      # `history`      : [{features: [...], outcome: 1|0, at: <optional epoch>}, ...] in time order
      # `feature_phases`: optional [{name:, phase: "before"|"at"|"after"}, ...], one per column.
      #                   Supplying it is what turns the leakage check from UNCHECKED into a result.
      def assess(history, feature_phases: nil, target_effect: nil)
        findings = []
        return no_gate(findings) if history.nil? || history.empty?

        rows = history.map { |h| Array(h[:features] || h["features"]).map(&:to_f) }
        out = history.map { |h| (h[:outcome] || h["outcome"]).to_f }
        times = history.map { |h| h[:at] || h["at"] }

        findings << check_gate(out)
        findings << check_density(out)
        findings << check_base_rate(out)
        findings << check_order(times)
        findings << check_leakage(feature_phases, rows.first&.size)
        findings << check_degeneracy(rows)
        signal = check_signal(rows, out)
        findings << signal
        findings << check_power(rows, out, target_effect) if target_effect

        findings.compact!
        blocking = findings.select { |f| f[:severity] == "blocking" }
        verdict = if blocking.any?
                    "not_ready"
                  elsif findings.any? { |f| f[:severity] == "thin" }
                    "usable_but_thin"
                  else
                    "ready"
                  end
        { verdict: verdict, cases_with_outcomes: out.size,
          cases_still_needed: [MIN_TO_LEARN - out.size, 0].max,
          findings: findings, next_step: next_step(verdict, findings, out.size) }
      end

      # ── individual checks ──────────────────────────────────────────────────────────────────
      def no_gate(findings)
        { verdict: "not_ready", cases_with_outcomes: 0, cases_still_needed: MIN_TO_LEARN,
          findings: findings + [{ check: "gate", severity: "blocking",
                                  detail: "no recorded outcomes at all",
                                  remedy: "record one line per change: what changed, and whether it later needed fixing. Without this nothing else can be measured." }],
          next_step: "start keeping the book — a gate that judges, recorded per change" }
      end

      def check_gate(out)
        return { check: "gate", severity: "ok", detail: "outcomes present, both classes seen" } if out.uniq.size >= 2

        { check: "gate", severity: "blocking",
          detail: "every recorded outcome is the same (#{out.first})",
          remedy: "a gate that never fails teaches nothing. Either the gate is too lax, or failures are not being recorded." }
      end

      def check_density(out)
        n = out.size
        if n >= MIN_TO_LEARN
          { check: "density", severity: "ok", detail: "#{n} cases with outcomes" }
        elsif n >= MIN_TO_TRY
          { check: "density", severity: "thin",
            detail: "#{n} cases — enough to try, not enough to trust",
            remedy: "#{MIN_TO_LEARN - n} more cases before a result should be acted on" }
        else
          { check: "density", severity: "blocking",
            detail: "#{n} cases — below the point where disciplined fitting beats careless fitting",
            remedy: "measured on a #{MIN_TO_TRY}-case project: holding out a validation slice scored 0.405 while ignoring discipline scored 0.736. Collect at least #{MIN_TO_TRY} cases first." }
        end
      end

      def check_base_rate(out)
        rate = 1.0 - (out.sum / out.size.to_f)
        batch = CR.batch_size(rate)
        usable = out.size / [batch, 1].max
        if rate < BASE_RATE_FLOOR || rate > 1 - BASE_RATE_FLOOR
          { check: "base_rate", severity: "blocking",
            detail: "failure rate #{(rate * 100).round(1)}% is extreme",
            remedy: "a batch would need ~#{batch} changes to contain 3 failures, giving only ~#{usable} usable batches. Either widen what counts as a failure, or collect far more history." }
        elsif usable < 10
          { check: "base_rate", severity: "thin",
            detail: "failure rate #{(rate * 100).round(1)}% implies batches of ~#{batch}, only ~#{usable} of them",
            remedy: "estimates from fewer than ~10 batches carry intervals too wide to decide on" }
        else
          { check: "base_rate", severity: "ok",
            detail: "failure rate #{(rate * 100).round(1)}%, ~#{usable} usable batches of ~#{batch}" }
        end
      end

      def check_order(times)
        known = times.compact
        return { check: "time_order", severity: "unchecked", detail: "no timestamps supplied; history assumed to be in time order" } if known.size < times.size

        sorted = known.each_cons(2).all? { |a, b| a.to_f <= b.to_f }
        return { check: "time_order", severity: "ok", detail: "history is in time order" } if sorted

        { check: "time_order", severity: "blocking",
          detail: "timestamps are not monotonic",
          remedy: "training on later cases to predict earlier ones is looking at the future. Sort by time before measuring." }
      end

      def check_leakage(phases, n_features)
        if phases.nil? || phases.empty?
          return { check: "leakage", severity: "unchecked",
                   detail: "feature phases not declared",
                   remedy: "declare, per feature, whether it is observable BEFORE the verdict, AT it, or AFTER. Undeclared is not the same as clean — two leaks in the source programme each produced a beautiful result that collapsed when closed." }
        end

        bad = phases.each_with_index.filter_map do |p, i|
          phase = (p[:phase] || p["phase"]).to_s.downcase
          name = p[:name] || p["name"] || "feature[#{i}]"
          "#{name} (#{phase})" unless phase == "before"
        end
        if bad.any?
          { check: "leakage", severity: "blocking",
            detail: "#{bad.size} feature(s) are not observable before the verdict: #{bad.first(5).join(', ')}",
            remedy: "any feature known only at or after the gate leaks the answer. Remove them or re-derive them from what was knowable earlier." }
        elsif n_features && phases.size != n_features
          { check: "leakage", severity: "thin",
            detail: "#{phases.size} phases declared for #{n_features} features — some are undeclared",
            remedy: "declare every feature; a single undeclared leak is enough" }
        else
          { check: "leakage", severity: "ok", detail: "all #{phases.size} features declared observable before the verdict" }
        end
      end

      def check_degeneracy(rows)
        return nil if rows.empty?

        live = CR.live_columns(rows)
        dead = rows.first.size - live.size
        dup = near_duplicates(rows, live)
        if dead.zero? && dup.empty?
          { check: "degeneracy", severity: "ok", detail: "no dead or near-duplicate columns" }
        else
          bits = []
          bits << "#{dead} column(s) constant" if dead.positive?
          bits << "#{dup.size} near-duplicate pair(s) (|r| > 0.95)" if dup.any?
          { check: "degeneracy", severity: "thin", detail: bits.join("; "),
            remedy: "constant columns make the design rank-deficient and near-duplicates inflate it; the scorers drop dead columns automatically, but a feature that never varies is telling you it is not being measured" }
        end
      end

      def check_signal(rows, out)
        return nil if rows.empty? || out.uniq.size < 2

        best = CR.live_columns(rows).map do |j|
          a = CR.auc(rows.map { |r| r[j] }, out)
          a.nan? ? 0.5 : [a, 1 - a].max
        end.max || 0.5
        if best >= SIGNAL_FLOOR
          { check: "signal", severity: "ok",
            detail: "best single feature reaches AUC #{best.round(3)} — some signal exists" }
        else
          { check: "signal", severity: "blocking",
            detail: "no single feature beats AUC #{SIGNAL_FLOOR} (best #{best.round(3)})",
            remedy: "if the cheapest possible model cannot rank better than chance, a more elaborate one will not either. The features are not carrying information about this outcome — change what you observe, not how you model it." }
        end
      end

      def check_power(rows, out, target)
        return nil if rows.empty? || out.uniq.size < 2

        pos = out.count { |o| o > 0.5 }
        neg = out.size - pos
        se = Math.sqrt(0.25 / [[pos, neg].min, 1].max) # rough SE of an AUC on this many minority cases
        if target.to_f.abs > 2 * se
          { check: "power", severity: "ok",
            detail: "an effect of #{target} exceeds twice the sampling error (#{(2 * se).round(3)})" }
        else
          { check: "power", severity: "thin",
            detail: "an effect of #{target} is inside the noise (2×SE ≈ #{(2 * se).round(3)})",
            remedy: "this sample cannot distinguish differences that small. Either accept a larger effect as the bar, or collect more cases — tuning below the noise floor is wasted work." }
        end
      end

      def near_duplicates(rows, live)
        pairs = []
        live.combination(2).each do |i, j|
          ci = rows.map { |r| r[i] }
          cj = rows.map { |r| r[j] }
          pairs << [i, j] if correlation(ci, cj).abs > 0.95
        end
        pairs
      end

      def correlation(a, b)
        n = a.size.to_f
        ma = a.sum / n
        mb = b.sum / n
        cov = a.each_with_index.sum { |v, i| (v - ma) * (b[i] - mb) }
        sa = Math.sqrt(a.sum { |v| (v - ma)**2 })
        sb = Math.sqrt(b.sum { |v| (v - mb)**2 })
        return 0.0 if sa < 1e-12 || sb < 1e-12

        cov / (sa * sb)
      end

      def next_step(verdict, findings, n)
        case verdict
        when "not_ready"
          f = findings.find { |x| x[:severity] == "blocking" }
          "fix the blocking finding first: #{f[:check]} — #{f[:remedy]}"
        when "usable_but_thin"
          "you can explore, but do not act on a result yet; #{[MIN_TO_LEARN - n, 0].max} more cases before trusting one"
        else
          "ready — run change_risk `choose` to see whether any scorer earns its place on this project"
        end
      end
    end
  end
end
