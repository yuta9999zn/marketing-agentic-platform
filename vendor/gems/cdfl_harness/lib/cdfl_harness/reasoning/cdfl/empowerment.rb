# lib/cdfl_harness/reasoning/cdfl/empowerment.rb
# frozen_string_literal: true

module CDFLHarness
  module Reasoning
    module CDFL
      # Empowerment / option-preservation. An IRREVERSIBLE side-effect shrinks
      # others' future option-space (|OR|) → surface for consent. A REVERSIBLE
      # one preserves options → safe. Advisory only; never auto-blocks. Port of
      # empowerment.py.
      module Empowerment
        REVERSIBLE_CLASSES = %w[pure read_only write_idempotent].freeze
        OPTION_SHRINKING_CLASSES = %w[write_non_idempotent external].freeze

        ProtectionAdvice = Struct.new(:preserves_options, :needs_consent, :prefer_reversible, :rationale,
                                      keyword_init: true)

        module_function

        def option_preserving?(side_effect_class)
          REVERSIBLE_CLASSES.include?(side_effect_class)
        end

        def protection_advice(side_effect_class, reversible_alternative_exists: false)
          if option_preserving?(side_effect_class)
            return ProtectionAdvice.new(
              preserves_options: true, needs_consent: false, prefer_reversible: false,
              rationale: "Hành động khả hồi — bảo toàn không-gian-lựa-chọn (OR) của tác tử khác."
            )
          end

          if reversible_alternative_exists
            return ProtectionAdvice.new(
              preserves_options: false, needs_consent: true, prefer_reversible: true,
              rationale: "Có lựa chọn KHẢ HỒI tương đương — ưu tiên nó để bảo toàn OR của người dùng; " \
                         "nếu vẫn cần hành động bất khả hồi, xin phê duyệt."
            )
          end

          ProtectionAdvice.new(
            preserves_options: false, needs_consent: true, prefer_reversible: false,
            rationale: "Hành động BẤT KHẢ HỒI — thu hẹp không-gian-lựa-chọn của tác tử khác; " \
                       "cần con người phê duyệt trước (empowerment)."
          )
        end
      end
    end
  end
end
