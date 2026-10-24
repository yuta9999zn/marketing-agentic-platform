# lib/cdfl_harness/grounding/gate.rb
# frozen_string_literal: true

require_relative "../reasoning/knowledge/coverage"

module CDFLHarness
  module Grounding
    # |OR| grounding gate for the agent critic (RAG×harness step 2). Turns the
    # evidence the agent gathered (retrieve_evidence citations + recall_memory
    # hits) into a coverage score, then runs the "học 1 hiểu 10" coverage_gate.
    # Pure + deterministic. Port of agents/grounding_gate.py.
    module Gate
      module_function

      def cfg = CDFLHarness.config.reasoning

      def assess(transcripts, k: cfg.coverage_k)
        sims = []
        memory_hits = 0
        transcripts.each do |entry|
          next unless role_of(entry) == "executor"

          name = name_of(entry)
          res = result_of(entry)
          if name == "retrieve_evidence"
            (res["citations"] || []).each do |c|
              s = c.is_a?(Hash) ? c["similarity"] : nil
              sims << [0.0, s.to_f].max if s.is_a?(Numeric)
            end
          elsif name == "recall_memory"
            memory_hits += (res["recalled"] || 0).to_i
          end
        end

        relevant_mass = sims.select { |s| s >= cfg.sim_floor }.sum
        mass = relevant_mass + cfg.mem_mass * [memory_hits, cfg.mem_cap].min
        coverage = (1.0 - Math.exp(-k * mass)).round(4)
        gate = Reasoning::Knowledge::Coverage.coverage_gate(coverage)
        gate.merge(evidence_count: sims.size, memory_hits: memory_hits)
      end

      # duck-typed accessors (Struct or TranscriptEntry or Hash)
      def role_of(e)   = e.respond_to?(:role) ? e.role : e[:role]
      def name_of(e)   = e.respond_to?(:tool_name) ? e.tool_name : e[:tool_name]

      def result_of(e)
        r = e.respond_to?(:tool_result) ? e.tool_result : e[:tool_result]
        r.is_a?(Hash) ? r : {}
      end
    end
  end
end
