# lib/cdfl_harness/agent/workflows.rb
# frozen_string_literal: true

require_relative "../errors"
require_relative "workflow"

module CDFLHarness
  module Agent
    # Registry of built-in / project-defined workflows.
    class Workflows
      def initialize
        @workflows = {}
      end

      def register(workflow)
        @workflows[workflow.workflow_id] = workflow
        self
      end

      def get(workflow_id)
        @workflows[workflow_id] ||
          raise(Errors::WorkflowInputError, "unknown workflow: #{workflow_id}")
      end

      def all = @workflows.values
    end
  end
end
