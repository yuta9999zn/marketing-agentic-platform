# lib/cdfl_harness/grounding/verifier.rb
# frozen_string_literal: true

module CDFLHarness
  module Grounding
    # Number-overlap |OR| self-verify (CR-0018). Share of an insight's numeric
    # claims matched to measured facts. Heuristic; errs toward NOT flagging.
    # Port of reasoning/grounding.py.
    module Verifier
      Grounding = Struct.new(:score, :n_claims, :n_matched, :flagged, keyword_init: true)

      NUM_RE = /-?\d[\d.,]*\d|-?\d/.freeze

      module_function

      def to_float(tok)
        s = tok.strip.gsub(/%/, "").gsub(/\s/, "")
        return nil if s.empty? || ["-", ".", ","].include?(s)

        has_comma = s.include?(",")
        has_dot = s.include?(".")
        if has_comma && has_dot
          if s.rindex(",") > s.rindex(".")
            s = s.delete(".").tr(",", ".")
          else
            s = s.delete(",")
          end
        elsif has_comma
          a, _, b = s.partition(",")
          s = (s.count(",") == 1 && [1, 2].include?(b.length)) ? "#{a}.#{b}" : s.delete(",")
        elsif has_dot
          unless s.count(".") == 1 && [1, 2].include?(s.rpartition(".").last.length)
            s = s.delete(".")
          end
        end
        Float(s)
      rescue ArgumentError
        nil
      end

      def extract_claims(text)
        (text || "").scan(NUM_RE).filter_map { |m| to_float(m) }
      end

      def collect_facts(payload)
        facts = []
        walk = lambda do |x|
          case x
          when true, false then nil
          when Integer, Float then facts << x.to_f
          when String then facts.concat(extract_claims(x))
          when Hash then x.each_value { |v| walk.call(v) }
          when Array then x.each { |v| walk.call(v) }
          end
        end
        walk.call(payload)
        facts
      end

      def matches?(claim, facts, tol:)
        candidates = [claim, claim / 100.0, claim * 100.0]
        facts.any? do |f|
          scale = [f.abs, 1.0].max
          candidates.any? { |c| (c - f).abs <= tol * scale }
        end
      end

      def ground_claims(text, facts, tol: CDFLHarness.config.reasoning.grounding_tol)
        claims = extract_claims(text)
        return Grounding.new(score: 1.0, n_claims: 0, n_matched: 0, flagged: []) if claims.empty?

        flagged = claims.reject { |c| matches?(c, facts, tol: tol) }
        matched = claims.size - flagged.size
        Grounding.new(score: (matched.to_f / claims.size).round(4),
                      n_claims: claims.size, n_matched: matched, flagged: flagged)
      end

      def disclaimer_for(g)
        if g.flagged.any?
          nums = g.flagged.first(5).map { |x| x == x.to_i ? x.to_i.to_s : x.to_s }.join(", ")
          "⚠ #{g.flagged.size} số chưa khớp dữ liệu đo được (#{nums}) — kiểm chứng trước khi hành động."
        else
          "AI tạo từ dữ liệu — nên kiểm chứng trước khi quyết định."
        end
      end
    end
  end
end
