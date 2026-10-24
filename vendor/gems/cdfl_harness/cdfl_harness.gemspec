# frozen_string_literal: true

require_relative "lib/cdfl_harness/version"

Gem::Specification.new do |spec|
  spec.name        = "cdfl_harness"
  spec.version     = CDFLHarness::VERSION
  spec.authors     = ["Nguyen Truong An"]
  spec.summary     = "Pluggable LLM + agent harness with CDFL reasoning, coverage gate, and memory palace"
  spec.description = "A provider-agnostic Ruby harness: an LLM gateway (Anthropic/OpenAI/Ollama), " \
                     "a PLAN->EXECUTE->CRITIC agent loop, and the NNL-NTHT reasoning layer " \
                     "(CDFL, 'học 1 hiểu 10' coverage gate, memory palace)."
  spec.homepage    = "https://example.com/cdfl_harness"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir["lib/**/*.rb", "README.md", "docs/**/*.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "json_schemer", "~> 2.0"
  spec.add_dependency "matrix", "~> 0.4"

  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "webmock", "~> 3.19"
end
