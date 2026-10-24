# lib/cdfl_harness/gateway/adapters/anthropic.rb
# frozen_string_literal: true

require "net/http"
require "json"
require_relative "base"
require_relative "../../errors"

module CDFLHarness
  module Gateway
    module Adapters
      # Anthropic Messages API adapter (external). Caller redacts PII first.
      # Port of providers.py Anthropic path. Defaults to a current Claude model.
      class Anthropic < Base
        ENDPOINT = "https://api.anthropic.com/v1/messages"
        API_VERSION = "2023-06-01"

        def initialize(api_key: ENV.fetch("ANTHROPIC_API_KEY", nil), timeout: 60)
          raise Errors::ConfigError, "Anthropic adapter requires an api_key" if api_key.nil? || api_key.empty?

          @api_key = api_key
          @timeout = timeout
        end

        def invoke(model:, prompt:, max_tokens:)
          data = post(model: model, max_tokens: max_tokens, messages: [{ role: "user", content: prompt }])
          (data["content"] || []).select { |b| b["type"] == "text" }.map { |b| b["text"] }.join
        end

        def invoke_chat(model:, messages:, tools: nil, tool_choice: nil, max_tokens: 1500)
          system = messages.select { |m| m["role"] == "system" }.map { |m| m["content"] }.compact.join("\n\n")
          chat = messages.select { |m| %w[user assistant].include?(m["role"]) }
                         .map { |m| { role: m["role"], content: m["content"] || "" } }
          body = { model: model, max_tokens: max_tokens, messages: chat }
          body[:system] = system unless system.empty?
          if tools && !tools.empty?
            body[:tools] = tools.map do |t|
              fn = t[:function] || t["function"] || {}
              # Tool.to_openai_tool emits SYMBOL keys; a hand-built tool may use
              # STRING keys. Accept both so the tool name/schema is never dropped.
              { name:         fn[:name] || fn["name"],
                description:  fn[:description] || fn["description"] || "",
                input_schema: fn[:parameters] || fn["parameters"] || {} }
            end
          end
          data = post(**body)
          blocks = data["content"] || []
          text = blocks.select { |b| b["type"] == "text" }.map { |b| b["text"] }.join
          tool_blocks = blocks.select { |b| b["type"] == "tool_use" }
          tool_calls = tool_blocks.empty? ? nil : tool_blocks.map { |b| { "id" => b["id"], "name" => b["name"], "arguments" => b["input"] || {} } }
          fr = data["stop_reason"] || (tool_calls ? "tool_calls" : "stop")
          fr = "tool_calls" if fr == "tool_use"
          { content: text, model_used: model, tool_calls: tool_calls, finish_reason: fr }
        end

        def external? = true

        private

        def post(**body)
          uri = URI(ENDPOINT)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.read_timeout = @timeout
          req = Net::HTTP::Post.new(uri.path,
                                    "x-api-key" => @api_key, "anthropic-version" => API_VERSION,
                                    "content-type" => "application/json")
          req.body = JSON.generate(body)
          resp = http.request(req)
          raise Errors::AdapterError, "anthropic → #{resp.code}: #{resp.body[0, 200]}" unless resp.code.to_i == 200

          JSON.parse(resp.body)
        rescue JSON::ParserError => e
          raise Errors::AdapterError, "anthropic bad JSON: #{e.message}"
        rescue SocketError, Timeout::Error => e
          raise Errors::AdapterError, "anthropic unreachable: #{e.message}"
        end
      end
    end
  end
end
