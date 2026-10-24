# Gateway

The Gateway is the **single LLM chokepoint** (the K-3 analog): every model call
in the harness goes through `Gateway::Client`. Nothing else in the codebase
talks to a provider directly. This gives one place to enforce routing, consent,
PII redaction, structured-output validation, circuit-breaking, and audit.

```
CDFLHarness::Gateway::Client
  #complete(prompt:, task:, consent_external:, max_tokens:)            → String
  #complete_structured(prompt:, task:, schema:, consent_external:, max_tokens:) → Hash
  #chat(messages:, task:, tools:, tool_choice:, consent_external:, max_tokens:) → Hash
```

**Invariant: every model call goes through the Client.** Adapters, the router,
the breaker, and the middleware are internals of the gateway; agents call the
`Client`, never an adapter.

## Adapters

Every adapter subclasses `Gateway::Adapters::Base` and implements three methods:

```ruby
def invoke(model:, prompt:, max_tokens:)                              # → String
def invoke_chat(model:, messages:, tools: nil, tool_choice: nil, max_tokens: 1500)  # → Hash
def external?                                                          # → true | false
```

`external?` tells the router whether PII redaction + consent gating apply.

| Adapter | Endpoint(s) | `external?` | Notes |
|---|---|---|---|
| `Fake` | none | `false` | scripted `completions:` array; used by tests + the demo |
| `Ollama` | `POST /api/generate`, `POST /api/chat` | `false` | local; host from `config.ollama_host` / `OLLAMA_HOST` |
| `Anthropic` | `POST /v1/messages` | `true` | system hoisted to a top-level `system` field; tool shape renamed to `{name, description, input_schema}` |
| `OpenAI` | `POST /v1/chat/completions` | `true` | tool-call `arguments` JSON-decoded from string |

`Anthropic` and `OpenAI` raise `Errors::ConfigError` if constructed without an
api key. Any non-200 / unreachable host / bad JSON becomes `Errors::AdapterError`.

### Unified chat tool-call shape

Providers disagree on tool-call JSON. `#chat` (and each adapter's `invoke_chat`)
normalises every provider's tool calls into one shape:

```ruby
{ "id" => "...", "name" => "tool_name", "arguments" => { ... } }
```

The returned chat hash is `{ content:, model_used:, tool_calls:, finish_reason: }`
where `tool_calls` is `nil` when the model returned plain text, and
`finish_reason` is normalised so a tool-call turn always reads `"tool_calls"`.

## Router — resolution + consent downgrade

`Router#resolve(task:, consent_external:, model_hint: nil)` returns
`[model_id, method]` with `method ∈ {:internal, :external}`:

1. If `config.task_routing[task]` exists, use its `:model` / `:method`; otherwise
   the model is `config.model_for` and the method is `:external` when the
   configured provider is external, else `:internal`.
2. **Downgrade rule** — if the resolved `method` is `:external` but **not**
   (`consent_external && config.external_enabled`), the router returns the local
   Ollama default and `:internal` instead.

So an external call requires **two** gates to both hold:

| `consent_external` (per call) | `config.external_enabled` (master) | Result |
|---|---|---|
| `false` | `false` | downgrade → local (`:internal`) |
| `false` | `true`  | downgrade → local (`:internal`) |
| `true`  | `false` | downgrade → local (`:internal`) |
| `true`  | `true`  | external call allowed |

This mirrors Kaori's K-4: external is opt-in per call *and* gated by a master
kill-switch; the safe default is always local.

## StructuredOutput — extract → validate → ONE repair

`StructuredOutput.validate_or_repair(completion:, schema:, original_prompt:,
retry_fn:)` → `[parsed_hash, was_repaired]`.

**Extraction strategies** (`extract_json`), tried in order:
1. **whole** — parse the entire (stripped) completion as JSON.
2. **fenced** — pull the body out of a ```` ```json ... ``` ```` (or bare ```` ``` ````) block.
3. **first-brace** — slice from the first `{` to the last `}` and parse that.

The top-level value must be a JSON **object** (Hash); a non-object is a failure.

**Repair** — if extraction or schema validation fails, the gateway builds a
repair prompt (original request + schema + the exact validation error + the bad
completion, truncated) and re-invokes the adapter **exactly once** via `retry_fn`.
A second failure raises `Errors::StructuredOutputError` (carrying `attempts`,
`last_completion`, `last_error`). `complete_structured` records `repaired: true`
in the audit row when the repair round was used.

## CircuitBreaker

`CircuitBreaker.new(name:, failure_threshold: 5, window: 30, cooldown: 60,
clock:)`. Per-adapter (the `Client` holds one named `"gateway"`).

- A failure timestamps; failures older than `window` seconds are dropped.
- Reaching `failure_threshold` failures inside the window **opens** the breaker;
  while open, calls raise `AdapterError "circuit open"` for `cooldown` seconds.
- After the cooldown the breaker goes **half-open** (one trial allowed); a success
  clears the window and closes it. `clock` is injectable for deterministic tests.

## Middleware

Two opt-in hooks, configured via `config.middleware = [...]`:

- **`Middleware::PII`** (K-5 analog) — `call(prompt:, method:)` redacts
  Vietnamese-context PII (`email → [email]`, `phone → [phone]`, 9–12-digit
  `id_number → [id_number]`) **only when `method == :external`**. Internal calls
  pass through. Idempotent — safe to apply twice.
- **`Middleware::Audit`** (K-6 analog) — `record(task:, model:, method:, prompt:,
  completion:, repaired:, latency_ms:)` builds a row containing
  `prompt_sha`/`output_sha` (SHA-256 **hashes**, not raw text) and calls a
  `sink` callable (default no-op). A project wires the sink to a DB without
  leaking prompts. The `Client` always records an audit row after a call.

Input middleware (everything except `Audit`) runs as a `reduce` over the prompt
before the adapter call; `Audit` runs after.
