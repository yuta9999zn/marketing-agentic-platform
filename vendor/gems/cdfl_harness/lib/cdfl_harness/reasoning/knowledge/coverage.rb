# lib/cdfl_harness/reasoning/knowledge/coverage.rb
# frozen_string_literal: true

module CDFLHarness
  module Reasoning
    module Knowledge
      # ADR-0033 — the "học 1 hiểu 10" gate. High foundational coverage → the
      # reasoner may generalise; low coverage → decline (don't hallucinate, K-3).
      # Only foundational tiers (1,2) count: durable understanding, not volatile
      # market notes. Port of knowledge/grounding.py.
      module Coverage
        FOUNDATIONAL_TIERS = [1, 2].freeze

        module_function

        def cfg = CDFLHarness.config.reasoning

        def similarity(doc)
          d = doc.distance
          return 0.0 if d.nil?

          [0.0, 1.0 - d].max
        end

        def tier_rank(tier)
          [0.0, (5 - tier) / 4.0].max
        end

        def authority_score(doc, w_authority: cfg.w_authority, w_maturity: cfg.w_maturity)
          similarity(doc) + w_authority * tier_rank(doc.tier) + w_maturity * doc.confidence.to_f
        end

        def rank_by_authority(docs, w_authority: cfg.w_authority, w_maturity: cfg.w_maturity)
          docs.sort_by { |d| -authority_score(d, w_authority: w_authority, w_maturity: w_maturity) }
        end

        # 1 − exp(−k · Σ sim·confidence) over FOUNDATIONAL docs only.
        def coverage(docs, k: cfg.coverage_k)
          mass = docs.select { |d| FOUNDATIONAL_TIERS.include?(d.tier) }
                     .sum { |d| similarity(d) * d.confidence.to_f }
          (1.0 - Math.exp(-k * mass)).round(4)
        end

        def coverage_gate(coverage, gen_min: cfg.gen_min, gen_caution: cfg.gen_caution)
          pct = (coverage * 100).round
          if coverage >= gen_min
            { can_generalize: true, band: "đủ", coverage: coverage,
              note: "Độ phủ tri thức nền #{pct}% — đủ để khái quát hoá (học 1 hiểu 10)." }
          elsif coverage >= gen_caution
            { can_generalize: true, band: "thận trọng", coverage: coverage,
              note: "Độ phủ tri thức nền #{pct}% — khái quát hoá THẬN TRỌNG, nêu rõ giả định." }
          else
            { can_generalize: false, band: "chưa đủ", coverage: coverage,
              note: "Độ phủ tri thức nền chỉ #{pct}% — CHƯA khái quát hoá; cần bổ sung kiến thức nền." }
          end
        end
      end
    end
  end
end
