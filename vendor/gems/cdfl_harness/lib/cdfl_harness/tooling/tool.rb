# lib/cdfl_harness/tooling/tool.rb
# frozen_string_literal: true

module CDFLHarness
  module Tooling
    # Base class for tools. Class-level DSL declares the metadata the registry
    # + planner introspect; instances run #call(args, ctx).
    class Tool
      class << self
        def tool_name(value = nil)
          @tool_name = value if value
          @tool_name || ""
        end

        def description(value = nil)
          @description = value if value
          @description || ""
        end

        def parameters(value = nil)
          @parameters = value if value
          @parameters || { "type" => "object", "properties" => {} }
        end

        def scope(value = nil)
          @scope = value if value
          @scope || "enterprise"
        end

        def to_openai_tool
          { type: "function",
            function: { name: tool_name, description: description, parameters: parameters } }
        end
      end

      # Override in subclasses. Return any JSON-serialisable value. Raise
      # ArgumentError for arg-validation failures (registry turns these into
      # ok=false so the LLM can self-correct).
      def call(_args, _ctx)
        raise NotImplementedError, "#{self.class}#call"
      end
    end
  end
end
