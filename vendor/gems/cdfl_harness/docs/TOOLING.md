# Tooling

Tools are how the agent acts on the world. A `Tool` declares its metadata via a
class-level DSL and runs `#call(args, ctx)`. The `Registry` dispatches by name
and — crucially — **strips identity-bearing arguments** so a tool can never take
`tenant_id` / `user_id` from the LLM's output. Identity comes only from
`Context` (the K-12 / K-16 analog).

## Writing a `Tool` subclass

Subclass `CDFLHarness::Tooling::Tool` and use the DSL:

```ruby
class RetrieveEvidence < CDFLHarness::Tooling::Tool
  tool_name   "retrieve_evidence"          # required — the dispatch key
  description "Truy hồi bằng chứng cho câu hỏi"
  parameters({                              # JSON-Schema the planner shows the LLM
    "type" => "object",
    "properties" => { "q" => { "type" => "string" } }
  })
  scope "enterprise"                        # default "enterprise"; filters list_for_scope

  # Optional — declares reversibility for the empowerment advisor.
  def side_effect_class = "read_only"       # pure | read_only | write_idempotent
                                            # | write_non_idempotent | external

  # Return any JSON-serialisable value. Raise ArgumentError for arg-validation
  # failures (the registry turns these into ok=false so the LLM can self-correct).
  def call(args, ctx)
    { "citations" => lookup(args["q"], tenant: ctx.tenant_id) }
  end
end
```

DSL summary:

| Method | Purpose | Default |
|---|---|---|
| `tool_name` | dispatch key; the planner enforces it against `allowed_tools` | `""` (must set) |
| `description` | human/LLM-readable purpose (rendered into the planner prompt) | `""` |
| `parameters` | JSON-Schema for the tool's args | `{ "type" => "object", "properties" => {} }` |
| `scope` | visibility scope; `Registry#list_for_scope` filters on it | `"enterprise"` |
| `side_effect_class` (instance) | reversibility class for empowerment advice | `"read_only"` if undefined |

`Tool.to_openai_tool` renders the OpenAI function-tool JSON for `#chat`.

## Context — identity from trusted source only

`Tooling::Context` carries the identity + scope for one dispatch. The host app
builds it from trusted headers / JWT — **never** from LLM tool arguments:

```ruby
ctx = CDFLHarness::Tooling::Context.new(
  scope: "enterprise",
  tenant_id: "...",   # from the JWT, not the model
  user_id:   "...",
  role:      "MANAGER",
  dry_run:   true     # consumed by side-effecting tools
)
```

`dry_run` flows from `Session#run(dry_run:)` into the per-dispatch `Context`, so
a side-effecting tool reads `ctx.dry_run` and short-circuits its effect when true.

## The identity-from-context rule (K-12 / K-16)

`Registry::FORBIDDEN_ARGS` = `%w[tenant_id enterprise_id user_id workspace_id
role scope]`. Before calling a tool, the registry **strips** any of these keys
from the LLM-supplied `args`. The model literally cannot smuggle a tenant id
through a tool argument; the tool must read identity from `ctx`. This is the
direct analog of Kaori K-12 (tenant_id never from query/body/header) and K-16
(chat tools never accept tenant/user from arguments).

## Dispatch contract — `[ok, payload]`

`Registry#dispatch(name:, args:, ctx:)` returns a two-element array:

```ruby
ok, payload = registry.dispatch(name: "retrieve_evidence", args: { "q" => "x" }, ctx: ctx)
# ok == true,  payload == the tool's return value
# ok == false, payload == { "error" => "..." }   (tool raised ArgumentError)
```

- An **unknown tool** raises `Errors::ToolDispatchError` — this is a *hard* block;
  the `Executor` stops the run (`[BLOCKED]`).
- A tool that raises `ArgumentError` (arg-validation) becomes `[false, {error:}]`
  — a *soft* failure; the critic judges it, and the loop can replan.

`Registry#fetch(name)` returns the tool instance (or `nil`);
`Registry#list_for_scope(scope)` returns the tools visible in a scope (used by the
planner to render the tools block).

## Worked example

```ruby
reg = CDFLHarness::Tooling::Registry.new

draft = Class.new(CDFLHarness::Tooling::Tool) do
  tool_name "draft_action"
  description "Soạn đề xuất hành động (khả hồi — chỉ là bản nháp)"
  parameters({ "type" => "object", "properties" => { "note" => { "type" => "string" } } })
  def side_effect_class = "write_idempotent"     # reversible → no consent needed
  def call(args, ctx)
    { "draft" => "Đề xuất chăm sóc VIP", "applied" => !ctx.dry_run, "note" => args["note"] }
  end
end

reg.register(draft.new)

ctx = CDFLHarness::Tooling::Context.new(scope: "enterprise", tenant_id: "t-1", dry_run: true)
ok, payload = reg.dispatch(
  name: "draft_action",
  # the model tried to inject tenant_id — it is stripped before #call sees it:
  args: { "note" => "VIP", "tenant_id" => "EVIL" },
  ctx: ctx
)
# ok == true; payload["applied"] == false (dry_run); the tool never saw "tenant_id".
```
