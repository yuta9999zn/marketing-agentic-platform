# Architecture

`cdfl_harness` is two layers around one chokepoint, plus a pure Reasoning layer
wired into the agent loop. The Gateway is the only place a model is ever called;
the Agent `Session` is the only thing that touches the `Store`; everything under
`Reasoning::*` is a pure library (no LLM, no I/O except through pluggable stores).

## Module tree

```
CDFLHarness
├── Gateway                       ← the only place a model is called (≈ K-3)
│   ├── Client                      facade: complete / complete_structured / chat
│   ├── Router                      task → (model, method); external→local downgrade if !consent (≈ K-4)
│   ├── Adapters
│   │   ├── Base                    invoke / invoke_chat / external?
│   │   ├── Anthropic               Messages API (external)
│   │   ├── OpenAI                  Chat Completions (external)
│   │   ├── Ollama                  /api/generate · /api/chat (internal)
│   │   └── Fake                    scripted completions (tests / offline demo)
│   ├── StructuredOutput            extract_json (whole / fenced / first-brace) → validate → ONE repair round
│   ├── CircuitBreaker              per-adapter; opens after N failures / window, cooldown, half-open trial
│   └── Middleware
│       ├── PII                     redact email/phone/id before EXTERNAL calls (≈ K-5)
│       └── Audit                   hash sink: prompt_sha/output_sha + latency + repaired (≈ K-6)
├── Agent
│   ├── Session                     orchestrator: PLAN→EXECUTE→CRITIC, MAX_REPLAN, token budget, persistence, DE
│   ├── Planner                     1 LLM call → ordered Plan; allowed_tools enforcement; static_plan
│   ├── Executor                    dispatch each step; dry_run; empowerment advice; hard-stop on block
│   ├── Critic                      |OR| gate first → verdict (accept|replan|escalate); grounding override
│   ├── Workflow                    input_schema, allowed_tools, prompt callables, flags
│   └── Workflows                   registry of workflows
├── Tooling
│   ├── Tool                        class DSL: tool_name / description / parameters / scope (+ side_effect_class)
│   ├── Registry                    dispatch → [ok, payload]; strips forbidden args (identity from Context — K-12/K-16)
│   └── Context                     scope / tenant_id / user_id / role / dry_run
├── Reasoning
│   ├── CDFL
│   │   ├── TransitionModel         tabular P(s'|s,a) learned from observations
│   │   ├── InfoGain                IG = novelty + λ·uncertainty
│   │   ├── LookaheadPlanner        H-step Monte-Carlo expected info-gain (does not mutate the model)
│   │   ├── Agent                   TransitionModel + InfoGain + Lookahead; Boltzmann action pick
│   │   ├── HilbertMetric           DESCRIPTIVE |OR|=I(I:M) gauge + DE=S(ρ‖σ) (real-embedding eigensolver)
│   │   ├── FourFoldDE              DE dashboard: faces x/t/if_/mf (reported, never summed) + manifest_or
│   │   ├── Empowerment             option-preservation: irreversible step → consent advice
│   │   └── Types                   Transition · RolloutResult · ActionScore
│   ├── Knowledge
│   │   ├── Document                title/content/tier/confidence/distance
│   │   ├── Coverage                coverage / coverage_gate / rank_by_authority (học 1 hiểu 10)
│   │   └── Store                   contract + InMemoryStore (pgvector is a downstream swap)
│   └── Memory
│       ├── MemoryRecord            tiers × types; trust/maturation module functions
│       ├── TierStore               contract + InMemoryTierStore (one backend per tier)
│       └── Service                 facade over 4 tiers: write/retrieve/consolidate/promote/forget/verify/reinforce/link/experience
├── Grounding
│   ├── Verifier                    numeric-overlap |OR| self-verify
│   └── Gate                        evidence (transcripts) → coverage → coverage_gate (the critic bridge)
├── Schema                          JSON-Schema validation wrapper (first_error)
├── Store
│   ├── Base                        session/transcript persistence contract
│   └── InMemory                    default store
├── Types                           Plan · PlanStep · CriticVerdict · TranscriptEntry · SessionResult
└── Config · Errors · VERSION
```

## Data flow — Gateway

`Gateway::Client#complete_structured(prompt:, task:, schema:, consent_external:, max_tokens:)`:

```
resolve → PII → breaker → invoke → validate/repair → audit
```

1. **resolve** — `Router#resolve(task:, consent_external:)` → `[model, method]`
   where `method ∈ {:internal, :external}`. If an external method is requested
   but **not** (`consent_external && config.external_enabled`), the router
   **downgrades** to the local Ollama default `[ollama_model, :internal]`.
2. **PII** — `apply_input_middleware` runs the input middleware chain. For an
   external `method`, `Middleware::PII` redacts email / phone / id_number.
   (Internal calls pass through untouched.)
3. **breaker** — the call runs inside `CircuitBreaker#call`, which opens after
   `failure_threshold` failures within `window` seconds and blocks for `cooldown`.
4. **invoke** — `adapter.invoke(model:, prompt:, max_tokens:)` returns the
   completion text.
5. **validate / repair** — `StructuredOutput.validate_or_repair` extracts JSON
   (whole text → fenced block → first `{...}`), validates against the JSON-Schema,
   and on failure runs **exactly one** repair round (re-invoking the adapter with
   an augmented prompt). A second failure raises `StructuredOutputError`.
6. **audit** — `Middleware::Audit#record` stores `{ task, model, method,
   prompt_sha, output_sha, repaired, latency_ms }` to its sink (hashes, not raw
   text, by default).

`#complete` (free text) and `#chat` (multi-message + tool calls) share the same
spine minus the validate/repair step. `#chat` normalises every provider's tool
calls to the unified shape `{id, name, arguments}`.

## Data flow — Agent loop

`Agent::Session#run(workflow_id:, input:, context:, dry_run:)`:

```
validate → [ PLAN → EXECUTE → CRITIC → branch ] → finalize → consolidate → DE
                         ▲__________________│ (replan, bounded by MAX_REPLAN)
```

1. **validate** — `Schema.first_error(input, workflow.input_schema)`; on failure
   a `WorkflowInputError` is caught and returns a `SessionResult{status: :failed}`.
2. **create_session** on the `Store`.
3. **loop** (bounded):
   - **PLAN** — `Planner#plan_workflow` either runs the `static_plan` (0 tokens)
     or makes one `complete_structured(PLAN_OUTPUT_SCHEMA)` call; every step's
     `tool_name` must be in `workflow.allowed_tools`. Token budget checked here.
   - **EXECUTE** — `Executor#execute_steps` dispatches each step through the
     `Registry`; attaches **empowerment** consent advice for irreversible steps;
     **hard-stops** on a `ToolDispatchError` (`[BLOCKED]`).
   - **CRITIC** — `Critic#review_session` runs `Grounding::Gate.assess` first. For
     `llm_critic: false` workflows the gate **is** the verdict. For LLM critics,
     `complete_structured(VERDICT_OUTPUT_SCHEMA)`; if `requires_grounding` and the
     gate says "chưa đủ", an `accept` is **overridden** to `replan`.
   - **branch** — `accept`→`:completed`, `escalate`→`:escalated`, `replan`→loop
     until `max_replan` (then `:escalated`). Over-budget → break with `:failed`.
4. **finalize** on the `Store`.
5. **consolidate** — only when `status == :completed && !dry_run && memory` is
   present: write an `:OPERATIONAL` memory of the session (best-effort; a memory
   error never fails the session).
6. **DE** — assemble a `FourFoldDE` from `{data_coverage, knowledge_freshness,
   knowledge_coverage = grounding coverage, grounding_score}` and attach it.

`#run` **never raises** — any error becomes `status: :failed` with an
`error_message` in the returned `SessionResult`.

## Kaori (Python) → Ruby mapping

Each Ruby module ports the *semantics* of a specific Kaori source. (Source roots:
`services/llm-gateway` and `services/ai-orchestrator`.)

| Ruby module | Kaori Python source it ports |
|---|---|
| `Gateway::Client` | `llm-gateway` infer chokepoint (the K-3 single entrypoint) |
| `Gateway::Router` | `routing.py` (K-4 consent / external→local downgrade) |
| `Gateway::Adapters::{Anthropic,OpenAI,Ollama}` | `providers.py` (Anthropic / OpenAI / Ollama paths) |
| `Gateway::StructuredOutput` | `llm-gateway/output_validator.py` (extract → validate → one repair) |
| `Gateway::Middleware::PII` | PII redaction before external (K-5) |
| `Gateway::Middleware::Audit` | `record_ai_call` / `ai_decision_audit` (K-6) |
| `Agent::Session` | `agents/orchestrator.py` |
| `Agent::Planner` | `agents/planner.py` |
| `Agent::Executor` | `agents/executor.py` |
| `Agent::Critic` | `agents/critic.py` |
| `Agent::{Workflow,Workflows}` | `agents/workflows.py` |
| `Tooling::{Tool,Registry,Context}` | chat tool-calling with `ToolContext` (K-12/K-16) |
| `Reasoning::CDFL::{TransitionModel,Lookahead,InfoGain,Agent}` | `reasoning/cdfl/{transition_model,lookahead,information_gain,agent}.py` |
| `Reasoning::CDFL::HilbertMetric` | `cdfl/hilbert_metric.py` (descriptive gauge) |
| `Reasoning::CDFL::FourFoldDE` | `cdfl/four_fold_de.py` |
| `Reasoning::CDFL::Empowerment` | `cdfl/empowerment.py` |
| `Reasoning::Knowledge::Coverage` | `reasoning/knowledge/grounding.py` (ADR-0033, "học 1 hiểu 10") |
| `Grounding::Verifier` | `reasoning/grounding.py` (numeric |OR| self-verify) |
| `Grounding::Gate` | `agents/grounding_gate.py` (critic ↔ gate bridge) |
| `Reasoning::Memory::{Service,MemoryRecord,TierStore}` | `reasoning/memory/{service,types,stores}.py` (ADR-0030/0032) |

## Design for isolation

- **Gateway is standalone.** It knows nothing about agents — a project can use
  `Gateway::Client#complete_structured` directly for plain structured generation.
- **Reasoning is pure.** `Reasoning::*` and `Grounding::*` perform no LLM calls
  and no I/O except through pluggable stores, so they are trivially unit-testable
  with exact-value assertions (exactly as their Python originals are).
- **Session owns the Store.** `Agent::Session` is the *only* component that calls
  the `Store`; `Planner` / `Executor` / `Critic` are pure transforms
  (input → output). This mirrors Kaori's "orchestrator owns persistence" asymmetry
  and keeps the sub-agents free of side effects.
- **Adapters are independently testable.** `Fake` lets the entire loop run offline.
