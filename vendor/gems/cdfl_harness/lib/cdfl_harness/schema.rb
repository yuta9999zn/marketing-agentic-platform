# lib/cdfl_harness/schema.rb
# frozen_string_literal: true

require "json_schemer"

module CDFLHarness
  # Thin wrapper over json-schemer so the rest of the codebase never touches
  # the library directly. Schemas are plain Ruby Hashes (JSON-Schema 2020-12).
  module Schema
    module_function

    def schemer(schema)
      JSONSchemer.schema(schema, meta_schema: "https://json-schema.org/draft/2020-12/schema")
    end

    def valid?(data, schema)
      schemer(schema).valid?(data)
    end

    # One-line first error, or nil when valid. Used by structured-output repair
    # and workflow-input validation to build a useful message.
    def first_error(data, schema)
      err = schemer(schema).validate(data).first
      return nil if err.nil?

      ptr = err["data_pointer"].to_s.empty? ? "/" : err["data_pointer"]
      "#{err['error']} at #{ptr}"
    end

    def errors(data, schema)
      schemer(schema).validate(data).map do |err|
        ptr = err["data_pointer"].to_s.empty? ? "/" : err["data_pointer"]
        "#{err['error']} at #{ptr}"
      end
    end

    # True when the schema itself is a valid JSON-Schema document.
    def schema_valid?(schema)
      JSONSchemer.valid_schema?(schema)
    rescue StandardError
      false
    end
  end
end
