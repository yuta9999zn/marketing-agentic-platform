# lib/cdfl_harness/reasoning/cdfl/four_fold_de.rb
# frozen_string_literal: true

module CDFLHarness
  module Reasoning
    module CDFL
      # Dark-Existence dashboard (Tiên đề 4-5): DE across four faces — không
      # gian (x), thời gian (t), IF chưa biết (if_), MF chưa biết (mf). Faces
      # overlap, so they are reported, NEVER summed. Port of four_fold_de.py.
      FourFoldDE = Struct.new(:x, :t, :if_, :mf, keyword_init: true) do
        def faces = { "x" => x, "t" => t, "if" => if_, "mf" => mf }
        def max_dark = [x, t, if_, mf].max
        def manifest_or = 1.0 - (x + t + if_ + mf) / 4.0
      end

      module FourFoldDE_Builder
        def self.clip01(v)
          v < 0 ? 0.0 : (v > 1 ? 1.0 : v.to_f)
        end
      end

      class FourFoldDE
        # Build the four-fold DE from four manifest-fractions in [0,1]
        # (1 = fully known on that face). dark face = 1 − signal.
        def self.assemble(data_coverage:, knowledge_freshness:, knowledge_coverage:, grounding_score:)
          c = FourFoldDE_Builder
          new(
            x: 1.0 - c.clip01(data_coverage),
            t: 1.0 - c.clip01(knowledge_freshness),
            if_: 1.0 - c.clip01(knowledge_coverage),
            mf: 1.0 - c.clip01(grounding_score)
          )
        end
      end
    end
  end
end
