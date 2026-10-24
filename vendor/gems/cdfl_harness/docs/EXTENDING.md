# Extending the harness

Every pluggable seam in `cdfl_harness` is a small contract you implement and pass
through `Config` (or a keyword). This doc covers the five common extensions:
provider adapters, stores, middleware, workflows + tools, and embedding the gem
in a host app.

## Add a provider adapter

Subclass `Gateway::Adapters::Base` and implement three methods:

```ruby
module MyApp
  class VertexAdapter < CDFLHarness::Gateway::Adapters::Base
    def initialize(api_key:)
      raise CDFLHarness::Errors::ConfigError, "key required" if api_key.to_s.empty?
      @api_key = api_key
    end

    # single prompt → text
    def invoke(model:, prompt:, max_tokens:)
      # ... HTTP call; raise Errors::AdapterError on non-200 / bad JSON / unreachable
    end

    # multi-message + tools → { content:, model_used:, tool_calls:, finish_reason: }
    # normalise tool calls to the unified shape { "id", "name", "arguments" }
    def invoke_chat(model:, messages:, tools: nil, tool_choice: nil, max_tokens: 1500)
      # ...
    end

    def external? = true   # true ⇒ PII redaction + consent gating apply
  end
end
```

Wire it in one of two ways:

```ruby
# (a) inject a built instance — best for tests and one-off providers
cfg.adapter_override = MyApp::VertexAdapter.new(api_key: ENV["VERTEX_KEY"])

# (b) add a case to Gateway::Client#build_adapter for a first-class provider
#     when :vertex then Adapters::Vertex.new(api_key: @config.api_keys[:vertex])
```

`adapter_override` always wins over `build_adapter`.

## Add a `Store` (session persistence)

Subclass `Store::Base` and implement its contract (the harness only ever calls
these methods):

```ruby
class PgStore < CDFLHarness::Store::Base
  def create_session(session_id:, tenant_id:, workflow_id:, input:, dry_run:); ...; end
  def set_status(session_id:, status:); ...; end
  def append_transcript(session_id:, entry:); ...; end
  def persist_plan(session_id:, plan:); ...; end
  def persist_verdict(session_id:, verdict:); ...; end
  def bump_replan(session_id:, replan_count:); ...; end
  def finalize(session_id:, status:, tokens_used:, error_message:); ...; end
  def get(session_id:); ...; end
end

cfg.store = PgStore.new          # or pass store: ... to Session.new
```

## Add a `Knowledge::Store` or a `Memory::TierStore`

Both are tiny contracts with shipped in-memory defaults.

```ruby
# Knowledge — swap in pgvector + a real retriever
class PgVectorKB < CDFLHarness::Reasoning::Knowledge::Store
  def put(doc, scope_tenant_id:); ...; end
  def list_documents(tenant_id, limit: 100); ...; end
end
cfg.knowledge_store = PgVectorKB.new

# Memory — one backend per lifecycle tier (Redis/Postgres/Neo4j)
class RedisTierStore < CDFLHarness::Reasoning::Memory::TierStore
  attr_reader :tier
  def initialize(tier) = @tier = tier
  def put(record); ...; end
  def get(tenant_id, record_id); ...; end
  def list_all(tenant_id); ...; end
  def delete(tenant_id, record_id); ...; end
  def forget(tenant_id); ...; end
end

mem = CDFLHarness::Reasoning::Memory::Service.new(
  l1: RedisTierStore.new("L1_WORKING"), l2: RedisTierStore.new("L2_SHORT"),
  l3: RedisTierStore.new("L3_CONSOLIDATED"), l4: RedisTierStore.new("L4_LONG")
)
cfg.memory_service = mem
```

## Add a middleware

Input middleware is any object responding to `call(prompt:, method:)` returning a
(possibly transformed) prompt; it runs in a `reduce` before the adapter call:

```ruby
class Tagger
  def call(prompt:, method:) = "[#{method}] #{prompt}"
end
cfg.middleware = [CDFLHarness::Gateway::Middleware::PII.new, Tagger.new]
```

For audit, supply a sink to `Middleware::Audit` (it receives the hashed row):

```ruby
audit = CDFLHarness::Gateway::Middleware::Audit.new(sink: ->(row) { MyLog.write(row) })
cfg.middleware = [CDFLHarness::Gateway::Middleware::PII.new, audit]
```

The `Client` picks the `Audit` instance out of `config.middleware` (or builds a
default one) and treats everything else as input middleware.

## Register workflows + tools

```ruby
reg = CDFLHarness::Tooling::Registry.new
reg.register(MyTool.new)                       # see TOOLING.md for the Tool DSL

wf = CDFLHarness::Agent::Workflow.new(
  workflow_id: "my-flow",
  input_schema: { "type" => "object", "required" => ["q"],
                  "properties" => { "q" => { "type" => "string" } } },
  allowed_tools: %w[my_tool],
  planner_prompt: ->(i)        { "Plan for #{i['q']}" },
  critic_prompt:  ->(_p,_t,_i) { "Review" },
  # optional flags:
  static_plan: nil,            # ->(input) { [PlanStep, ...] } to skip the LLM planner
  llm_critic: true,            # false ⇒ the |OR| gate is the verdict
  requires_grounding: false    # true ⇒ override an ungrounded accept → replan
)
wfs = CDFLHarness::Agent::Workflows.new.tap { |w| w.register(wf) }
```

## Embed the harness in a host app

The whole integration is: build a `Config`, a `Workflows` registry, a tool
`Registry`, then call `Session#run`:

```ruby
require "cdfl_harness"

cfg = CDFLHarness::Config.new
cfg.provider = :ollama                          # or :anthropic/:openai (+ api_keys, external_enabled)
cfg.store           = PgStore.new
cfg.memory_service  = mem
cfg.middleware      = [CDFLHarness::Gateway::Middleware::PII.new, audit]

session = CDFLHarness::Agent::Session.new(config: cfg, workflows: wfs, registry: reg)

# Context identity comes from YOUR trusted source (JWT/headers), never the LLM:
ctx = CDFLHarness::Tooling::Context.new(scope: "enterprise", tenant_id: jwt.tenant_id,
                                        user_id: jwt.user_id, role: jwt.role)

result = session.run(workflow_id: "my-flow", input: { "q" => "..." },
                     context: ctx, dry_run: false)
# result is always a SessionResult — #run never raises.
```

You can also use the gateway **standalone**, without the agent loop:

```ruby
client = CDFLHarness::Gateway::Client.new(config: cfg)
hash = client.complete_structured(prompt: "...", task: "report.summary",
                                  schema: my_schema, consent_external: false)
```

All reasoning thresholds live on `config.reasoning` (a `Config::ReasoningConfig`)
and are env-readable — override them there, not at call sites.
