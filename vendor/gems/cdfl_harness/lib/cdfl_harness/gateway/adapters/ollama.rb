# lib/cdfl_harness/gateway/adapters/ollama.rb
# frozen_string_literal: true

require "net/http"
require "json"
require_relative "base"
require_relative "../../errors"

module CDFLHarness
  module Gateway
    module Adapters
      # Local Ollama adapter (internal). Port of providers.py Ollama path.
      class Ollama < Base
        def initialize(host: ENV.fetch("OLLAMA_HOST", "http://localhost:11434"), timeout: 120)
          @host = host
          @timeout = timeout
        end

        def invoke(model:, prompt:, max_tokens:)
          body = { model: model, prompt: prompt, stream: false,
                   options: { num_predict: max_tokens, temperature: 0.1 } }
          post("/api/generate", body).fetch("response", "")
        end

        def invoke_chat(model:, messages:, tools: nil, tool_choice: nil, max_tokens: 1500)
          body = { model: model, messages: messages, stream: false,
                   options: { num_predict: max_tokens, temperature: 0.1 } }
          body[:tools] = tools if tools && !tools.empty?
          data = post("/api/chat", body)
          msg = data["message"] || {}
          raw = msg["tool_calls"] || []
          tool_calls = raw.empty? ? nil : raw.each_with_index.map do |c, i|
            fn = c["function"] || {}
            { "id" => c["id"] || "ollama_#{i}", "name" => fn["name"].to_s, "arguments" => fn["arguments"] || {} }
          end
          { content: msg["content"].to_s, model_used: model, tool_calls: tool_calls,
            finish_reason: tool_calls ? "tool_calls" : "stop" }
        end

        def external? = false

        private

        def post(path, body)
          uri = URI("#{@host}#{path}")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = uri.scheme == "https"
          http.read_timeout = @timeout
          req = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
          req.body = JSON.generate(body)
          resp = http.request(req)
          raise Errors::AdapterError, "ollama #{path} → #{resp.code}: #{resp.body[0, 200]}" unless resp.code.to_i == 200

          JSON.parse(resp.body)
        rescue JSON::ParserError => e
          raise Errors::AdapterError, "ollama bad JSON: #{e.message}"
        rescue SocketError, Timeout::Error => e
          raise Errors::AdapterError, "ollama unreachable: #{e.message}"
        end
      end
    end
  end
end
