# Invariants

These are the safety/correctness invariants `cdfl_harness` carries over from
Kaori (the `K-*` numbers reference Kaori's `CLAUDE.md` §4). Each maps to the
module that enforces it and the doc that explains it.

| # | Invariant | Enforced by | Ref |
|---|---|---|---|
| 1 | **Single LLM chokepoint** | `Gateway::Client` | K-3 · [GATEWAY](GATEWAY.md) |
| 2 | **Consent / external→local downgrade** | `Gateway::Router` | K-4 · [GATEWAY](GATEWAY.md) |
| 3 | **PII redaction before external** | `Gateway::Middleware::PII` | K-5 · [GATEWAY](GATEWAY.md) |
| 4 | **Identity from Context (forbidden args stripped)** | `Tooling::Registry` + `Tooling::Context` | K-12/K-16 · [TOOLING](TOOLING.md) |
| 5 | **Bounded loop** | `Agent::Session` (`max_replan`, `max_tokens_per_session`) | [AGENT_LOOP](AGENT_LOOP.md) |
| 6 | **Decline, don't hallucinate** | `Reasoning::Knowledge::Coverage` + `Grounding::Gate` + `requires_grounding` override | K-3 · [COVERAGE_GATE](COVERAGE_GATE.md) |
| 7 | **`dry_run` ⇒ no side effects + no consolidation** | `Tooling::Context#dry_run` + `Agent::Session` | [AGENT_LOOP](AGENT_LOOP.md) |
| 8 | **Option-preservation / consent for irreversible steps** | `Reasoning::CDFL::Empowerment` (via `Agent::Executor`) | [CDFL](CDFL.md) |
| 9 | **Memory writes are best-effort, never fail a session** | `Agent::Session#consolidate` | [MEMORY_PALACE](MEMORY_PALACE.md) |

## Details

### 1. Single LLM chokepoint (K-3)
Every model call goes through `Gateway::Client` (`complete` / `complete_structured`
/ `chat`). Adapters, the router, the breaker and middleware are gateway internals;
no agent or reasoning module calls a provider directly. One place to govern cost,
consent, PII, validation, and audit.

### 2. Consent / external→local downgrade (K-4)
`Router#resolve` routes to an external provider **only** when both
`consent_external: true` (per call) **and** `config.external_enabled` (the master
kill-switch) hold. Otherwise it downgrades to the local Ollama default and
`:internal`. The safe default is always local. (See the 4-case table in
[GATEWAY](GATEWAY.md).)

### 3. PII redaction before external (K-5)
`Middleware::PII#call(prompt:, method:)` redacts email / phone / id_number — but
**only when `method == :external`**. Internal calls pass through untouched. The
redaction is idempotent. It runs as input middleware before the adapter call.

### 4. Identity from Context, forbidden args stripped (K-12/K-16)
`Registry::FORBIDDEN_ARGS` (`tenant_id`, `enterprise_id`, `user_id`,
`workspace_id`, `role`, `scope`) are stripped from LLM-supplied tool args before
dispatch. A tool can only obtain identity from the `Tooling::Context` the host app
built from trusted JWT/headers — the model cannot smuggle a tenant id through a
tool argument.

### 5. Bounded loop
`Agent::Session` caps re-planning at `config.max_replan` (default `2`; exceeding
it → `:escalated`) and total tokens at `config.max_tokens_per_session`
(default `6000`; exceeding it breaks the loop with `:failed`). No unbounded
agent loops.

### 6. Decline, don't hallucinate (K-3)
The coverage gate computes `coverage = 1 − exp(−k·Σ sim·confidence)` over
foundational tiers only and bands it (`đủ` / `thận trọng` / `chưa đủ`). When
coverage is `chưa đủ`, `can_generalize` is `false`. `Grounding::Gate` applies a
similarity floor and a memory-mass cap so weak/abundant-but-shallow evidence
can't inflate confidence. With `workflow.requires_grounding`, an ungrounded
`accept` is overridden to `replan`. The gate errs toward declining.

### 7. `dry_run` ⇒ no side effects + no consolidation
`dry_run` flows from `Session#run` into each per-dispatch `Context`; side-effecting
tools read `ctx.dry_run` and short-circuit. A `dry_run` session is **never**
consolidated into memory (`status == :completed && !dry_run && memory` is the
guard). So a dry run is fully observable yet inert.

### 8. Option-preservation / consent for irreversible steps
`Empowerment.protection_advice(side_effect_class)` marks
`write_non_idempotent` / `external` steps as needing human consent (they shrink
others' option-space `|OR|`), while `pure` / `read_only` / `write_idempotent`
steps preserve options. The `Executor` attaches this advice to irreversible
steps. **Advisory only — it never auto-blocks**; the host app decides.

### 9. Memory writes are best-effort, never fail a session
`Session#consolidate` is wrapped so any error during the memory write is
swallowed (`rescue StandardError; nil`). A failing memory store can never turn a
successful session into a failure — memory is an enhancement, not a dependency of
the result.
