# Agent loop

`Agent::Session` is the orchestrator. It validates input, then runs a bounded
**PLAN → EXECUTE → CRITIC** loop, persisting every step, consolidating successful
non-dry sessions into memory, and attaching a four-fold DE dashboard to the
result. **`Session#run` never raises** — every failure becomes a structured
`SessionResult{status: :failed}`.

```
CDFLHarness::Agent::Session.new(config:, workflows:, registry:, gateway: nil, store: nil, memory_service: nil)
  #run(workflow_id:, input:, context:, dry_run: true) → CDFLHarness::Types::SessionResult
```

## The loop

```
                 ┌─────────────────────────────────────────────┐
 validate input  │                                             │
   (input_schema)│   ┌────────┐   ┌─────────┐   ┌────────┐     │
        │        └──▶│  PLAN  │──▶│ EXECUTE │──▶│ CRITIC │──┐  │
        ▼            └────────┘   └─────────┘   └────────┘  │  │
  create_session         ▲                          │       │  │
                         │                          ▼       │  │
                         │                   ┌──────────────┴──┐│
                         │  replan           │ accept  → completed
                         └───────────────────│ escalate→ escalated
                            (≤ MAX_REPLAN)    │ replan  → loop
                                              └─────────────────┘
                                       │
                  finalize → consolidate (success & !dry_run) → four-fold DE
```

### PLAN
`Planner#plan_workflow` returns `[Plan, tokens_used]`. If the workflow declares a
`static_plan`, it runs that (0 tokens, no LLM); otherwise it makes one
`gateway.complete_structured(PLAN_OUTPUT_SCHEMA)` call. Either way **every**
step's `tool_name` must be in `workflow.allowed_tools` or it raises.

### EXECUTE
`Executor#execute_steps` dispatches each `PlanStep` through the `Registry`,
producing one `TranscriptEntry` per step. It consults
`Reasoning::CDFL::Empowerment.protection_advice(side_effect_class)` and appends
consent advice for irreversible steps. It **hard-stops** the moment a step is
`[BLOCKED]` (a `ToolDispatchError`) — later steps are not run.

### CRITIC
`Critic#review_session` returns a `CriticVerdict{action, reason, issues}`:
- It runs `Grounding::Gate.assess(transcripts)` first.
- For `llm_critic: false` workflows the **gate is the verdict**:
  `can_generalize → "accept"`, else `"replan"`.
- For LLM critics it calls `gateway.complete_structured(VERDICT_OUTPUT_SCHEMA)`.
  If `workflow.requires_grounding` and the gate says "chưa đủ", an `"accept"` is
  **overridden to `"replan"`** (decline-not-hallucinate).

### BRANCH + bounds
| verdict | result |
|---|---|
| `accept` | `status = :completed`, break |
| `escalate` | `status = :escalated`, break |
| `replan` | loop again; after `config.max_replan` extra rounds → `:escalated` |

Two hard bounds (both env-configurable via `Config`):
- **`max_replan`** (default `2`) — caps re-planning loops.
- **`max_tokens_per_session`** (default `6000`) — checked after each PLAN; if
  exceeded the loop breaks with `error_message: "token_budget_exceeded: ..."`.

## Transcript shape

`transcripts` is an inline array of `Types::TranscriptEntry`:

```ruby
TranscriptEntry(
  step_index:, role:,          # role ∈ "planner" | "executor" | "critic"
  tool_name:, tool_args:, tool_result:, tool_ok:,  # set on executor rows
  reasoning:                   # plan rationale / dispatch note / verdict reason
)
```

A planner row and a critic row carry `reasoning`; executor rows additionally
carry the tool name/args/result and `tool_ok`.

## Session owns persistence; sub-agents are pure

This asymmetry is deliberate (and ported from Kaori's orchestrator):

- **`Session`** is the *only* component that calls the `Store`
  (`create_session`, `set_status`, `append_transcript`, `persist_plan`,
  `persist_verdict`, `bump_replan`, `finalize`). It also owns the memory
  consolidation and DE assembly.
- **`Planner` / `Executor` / `Critic`** are pure transforms — input → output, no
  Store, no memory writes. They are unit-tested in isolation against the `Fake`
  adapter.

The default store is `Store::InMemory`; a project passes its own `Store::Base`
subclass via `config.store` or the `store:` keyword.

## Wiring points

The loop is where the Reasoning layer plugs in:

| Wiring | Where | What it does |
|---|---|---|
| **critic ↔ grounding gate** | `Critic` → `Grounding::Gate.assess` | turns gathered evidence into a coverage band; gates/overrides the verdict |
| **success ↔ memory consolidation** | `Session#consolidate` | on `:completed && !dry_run`, writes an `:OPERATIONAL` memory of the session |
| **irreversible step ↔ empowerment** | `Executor` → `Empowerment.protection_advice` | flags steps that need human consent (option-preservation) |
| **result ↔ four-fold DE** | `Session` → `FourFoldDE.assemble` | attaches the Dark-Existence dashboard to the result |

## "Never raises out of `run`" guarantee

Inside `#run`, the loop body is wrapped so any `Errors::Error` or `StandardError`
is caught and turned into `status: :failed, error_message:`. An invalid-input /
unknown-workflow `WorkflowInputError` raised before the session row exists is
caught at the method boundary and also returns a `SessionResult{status: :failed}`
(with `session_id: nil`). Memory consolidation is additionally wrapped so a
memory error can **never** fail a session. Callers always get a structured
`SessionResult` — never an exception. (Mirrors Kaori's "no 500 escapes the
orchestrator".)
