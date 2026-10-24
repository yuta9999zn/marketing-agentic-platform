# lib/cdfl_harness/tooling/registry.rb
# frozen_string_literal: true

require_relative "../errors"
require_relative "tool"
require_relative "context"

module CDFLHarness
  module Tooling
    # Holds tool instances and dispatches by name. Identity-bearing args are
    # stripped before dispatch so a tool can NEVER take tenant/user from the
    # LLM's arguments (K-12/K-16) — those come only from Context.
    class Registry
      FORBIDDEN_ARGS = %w[tenant_id enterprise_id user_id workspace_id role scope].freeze

      def initialize
        @tools = {}
      end

      def register(tool)
        name = tool.class.tool_name
        raise Errors::ConfigError, "tool has no name" if name.nil? || name.empty?

        @tools[name] = tool
        self
      end

      def fetch(name)
        @tools[name]
      end

      def list_for_scope(scope)
        @tools.values.select { |t| t.class.scope == scope }
      end

      # Returns [ok, payload]. Raises ToolDispatchError for hard violations
      # (unknown tool); a tool-side ArgumentError becomes [false, {error:}].
      def dispatch(name:, args:, ctx:)
        tool = @tools[name]
        raise Errors::ToolDispatchError, "unknown tool: #{name}" if tool.nil?

        safe = (args || {}).reject { |k, _| FORBIDDEN_ARGS.include?(k.to_s) }
        begin
          [true, tool.call(safe, ctx)]
        rescue ArgumentError => e
          [false, { "error" => e.message }]
        end
      end
    end
  end
end
