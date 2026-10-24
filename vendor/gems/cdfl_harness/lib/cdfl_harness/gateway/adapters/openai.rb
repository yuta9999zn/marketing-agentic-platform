# lib/cdfl_harness/gateway/adapters/openai.rb
# frozen_string_literal: true

require "net/http"
require "json"
require_relative "base"
require_relative "../../errors"

module CDFLHarness
  module Gateway
    module Adapters
      # OpenAI Chat Completions adapter (external). Caller redacts PII first.
      # Port of providers.py OpenAI path.
      class OpenAI < Base
        ENDPOINT = "https://api.openai.com/v1/chat/completions"

        def initialize(api_key: ENV.fetch("OPENAI_API_KEY", nil), timeout: 60)
          raise Errors::ConfigError, "OpenAI adapter requires an api_key" if api_key.nil? || api_key.empty?

          @api_key = api_key
          @timeout = timeout
        end

        def invoke(model:, prompt:, max_tokens:)
          data = post(model: model, messages: [{ role: "user", content: prompt }],
                      max_tokens: max_tokens, temperature: 0.1)
          dig_content(data)
        end

        def invoke_chat(model:, messages:, tools: nil, tool_choice: nil, max_tokens: 1500)
          body = { model: model, messages: messages, max_tokens: max_tokens, temperature: 0.1 }
          if tools && !tools.empty?
            body[:tools] = tools
            body[:tool_choice] = tool_choice || "auto"
          end
          data = post(**body)
          choice = (data["choices"] || [{}]).first
          msg = choice["message"] || {}
          raw = msg["tool_calls"] || []
          tool_calls = raw.empty? ? nil : raw.map do |c|
            fn = c["function"] || {}
            args = fn["arguments"]
            args = (JSON.parse(args) rescue {}) if args.is_a?(String)
            { "id" => c["id"], "name" => fn["name"].to_s, "arguments" => args || {} }
          end
          { content: msg["content"].to_s, model_used: model, tool_calls: tool_calls,
            finish_reason: choice["finish_reason"] || (tool_calls ? "tool_calls" : "stop") }
        end

        def external? = true

        private

        def dig_content(data)
          ((data["choices"] || [{}]).first["message"] || {})["content"].to_s
        end

        def post(**body)
          uri = URI(ENDPOINT)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.read_timeout = @timeout
          req = Net::HTTP::Post.new(uri.path, "Authorization" => "Bearer #{@api_key}",
                                              "Content-Type" => "application/json")
          req.body = JSON.generate(body)
          resp = http.request(req)
          raise Errors::AdapterError, "openai → #{resp.code}: #{resp.body[0, 200]}" unless resp.code.to_i == 200

          JSON.parse(resp.body)
        rescue JSON::ParserError => e
          raise Errors::AdapterError, "openai bad JSON: #{e.message}"
        rescue SocketError, Timeout::Error => e
          raise Errors::AdapterError, "openai unreachable: #{e.message}"
        end
      end
    end
  end
end
