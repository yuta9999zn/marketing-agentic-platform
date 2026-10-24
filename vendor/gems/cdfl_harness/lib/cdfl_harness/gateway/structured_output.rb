# lib/cdfl_harness/gateway/structured_output.rb
# frozen_string_literal: true

require "json"
require_relative "../errors"
require_relative "../schema"

module CDFLHarness
  module Gateway
    # Port of llm-gateway/output_validator.py: pull JSON out of a free-text
    # completion, validate against a JSON-Schema, and run exactly ONE repair
    # round on failure. Returns [parsed_hash, was_repaired].
    module StructuredOutput
      module_function

      FENCE_RE = /```(?:json|JSON)?\s*\n?(?<body>.*?)\n?```/m

      # Returns [parsed_hash_or_nil, error_message_or_nil]. Exactly one is non-nil.
      def extract_json(completion)
        return [nil, "empty completion"] if completion.nil? || completion.strip.empty?

        text = completion.strip

        whole = try_parse(text)
        return non_object_or(whole) unless whole.nil?

        if (m = FENCE_RE.match(text))
          body = m[:body].strip
          parsed = try_parse(body)
          return non_object_or(parsed) unless parsed.nil?
        end

        bstart = text.index("{")
        bend = text.rindex("}")
        if bstart && bend && bstart < bend
          parsed = try_parse(text[bstart..bend])
          return [parsed, nil] if parsed.is_a?(Hash)
        end

        [nil, "no JSON object found in completion"]
      end

      def validate_or_repair(completion:, schema:, original_prompt:, retry_fn:)
        parsed, extract_error = extract_json(completion)
        if parsed
          verr = Schema.first_error(parsed, schema)
          return [parsed, false] if verr.nil?

          first_error = verr
        else
          first_error = extract_error || "could not parse JSON"
        end

        augmented = repair_prompt(original_prompt: original_prompt, schema: schema,
                                  error: first_error, bad_completion: completion)
        begin
          repaired_completion = retry_fn.call(augmented)
        rescue StandardError => e
          raise Errors::StructuredOutputError.new("repair attempt failed: #{e}",
                                                  attempts: 2, last_completion: completion, last_error: first_error)
        end

        parsed2, extract_error2 = extract_json(repaired_completion)
        if parsed2.nil?
          raise Errors::StructuredOutputError.new("repaired completion had no JSON object",
                                                  attempts: 2, last_completion: repaired_completion, last_error: extract_error2)
        end
        verr2 = Schema.first_error(parsed2, schema)
        if verr2
          raise Errors::StructuredOutputError.new("repaired completion did not match schema",
                                                  attempts: 2, last_completion: repaired_completion, last_error: verr2)
        end
        [parsed2, true]
      end

      def repair_prompt(original_prompt:, schema:, error:, bad_completion:)
        bad = bad_completion.to_s
        bad = "#{bad[0, 1000]}...[truncated]" if bad.length > 1000
        <<~PROMPT
          Your previous response failed JSON schema validation.

          Original request:
          #{original_prompt}

          Required JSON schema:
          #{JSON.generate(schema)}

          Validation error:
          #{error}

          Your previous (invalid) response:
          #{bad}

          Return ONLY a JSON object that matches the schema. No prose, no markdown fences, no explanation. Just the JSON.
        PROMPT
      end

      # ----- helpers -----
      def try_parse(text)
        JSON.parse(text)
      rescue JSON::ParserError
        nil
      end

      def non_object_or(parsed)
        return [parsed, nil] if parsed.is_a?(Hash)

        [nil, "top-level JSON is #{parsed.class}, not object"]
      end
    end
  end
end
