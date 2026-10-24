# cdfl_harness

A pluggable Ruby **LLM + agent harness** that ports the *semantics* (not the
line-by-line code) of Kaori's Python `llm-gateway` + `ai-orchestrator/agents`,
plus the **NNL-NTHT** reasoning layer from the thesis of *Nguyễn Trường An*.

It gives any Ruby project three things in one gem:

1. **An LLM gateway** — a single chokepoint to call models: pluggable provider
   adapters (Anthropic / OpenAI / Ollama / a `Fake` for tests), task→model
   routing with consent-based external→local downgrade, structured-output
   validation with one repair round, and optional PII/audit hooks.
2. **A PLAN → EXECUTE → CRITIC agent loop** — bounded re-plan + token budget, a
   safe tool registry (identity from `Context`, never from LLM args), inline
   transcripts, and pluggable persistence. `Session#run` **never raises**.
3. **The NNL-NTHT reasoning layer**:
   - **CDFL** (Convergent Dual-Field Learning): IF/MF/OR/DE dynamics, the four-fold
     Dark-Existence dashboard, empowerment / option-preservation, and the
     *descriptive* Hilbert `I(I:M)` gauge.
   - **"Học 1 hiểu 10"** — the foundational-knowledge **coverage gate**: enough
     durable knowledge → generalise; too little → **decline instead of
     hallucinating** (K-3).
   - **Cung điện ký ức** (memory palace) — 4 lifecycle tiers × 5 cognitive types
     with trust-decay, maturation, associative recall, and a memory→KB promotion
     loop.

---

## Install

In a host project's `Gemfile` (note the **space** in the path — keep the quotes):

```ruby
gem "cdfl_harness", path: "D:/CDFL harness"
```

```bash
bundle install
```

Then `require "cdfl_harness"`.

### Toolchain on this machine

Ruby **3.3** is installed at `C:\Ruby33-x64`. On Windows, run Ruby commands in
**PowerShell** with the Ruby bin prepended to `PATH` for the session — otherwise
a Node `bundle` shim shadows the real Bundler:

```powershell
$env:Path = "C:\Ruby33-x64\bin;" + $env:Path
bundle install
bundle exec rspec
```

---

## Quickstart

Condensed from [`examples/insight_to_action.rb`](examples/insight_to_action.rb)
— a grounded "insight → action" workflow that runs fully offline on the `Fake`
adapter:

```ruby
require "cdfl_harness"

# 1. Build a tool registry (identity comes from Context, never from args).
reg = CDFLHarness::Tooling::Registry.new
retrieve = Class.new(CDFLHarness::Tooling::Tool) do
  tool_name "retrieve_evidence"; description "Truy hồi bằng chứng"
  def call(_args, _ctx)
    { "citations" => [{ "similarity" => 0.91, "snippet" => "Doanh thu Q1 +18%." },
                      { "similarity" => 0.84, "snippet" => "VIP đóng góp 62%." }] }
  end
end
reg.register(retrieve.new)

# 2. Define a workflow (deterministic |OR| critic enforcing học-1-hiểu-10).
wf = CDFLHarness::Agent::Workflow.new(
  workflow_id: "insight-to-action",
  input_schema: { "type" => "object", "required" => ["question"],
                  "properties" => { "question" => { "type" => "string" } } },
  allowed_tools: %w[retrieve_evidence],
  planner_prompt: ->(i) { "Lập kế hoạch: #{i['question']}" },
  critic_prompt:  ->(_p, _t, _i) { "Đánh giá" },
  static_plan: ->(_i) { [CDFLHarness::Types::PlanStep.new(
    tool_name: "retrieve_evidence", args: { "q" => "doanh thu" }, rationale: "thu thập")] },
  llm_critic: false, requires_grounding: true
)

# 3. Wire config + workflows + registry, then run the session.
cfg = CDFLHarness::Config.new
cfg.provider = :fake
cfg.adapter_override = CDFLHarness::Gateway::Adapters::Fake.new(completions: [])
cfg.memory_service  = CDFLHarness::Reasoning::Memory::Service.new
wfs = CDFLHarness::Agent::Workflows.new.tap { |w| w.register(wf) }
session = CDFLHarness::Agent::Session.new(config: cfg, workflows: wfs, registry: reg)
ctx = CDFLHarness::Tooling::Context.new(scope: "enterprise", tenant_id: "t-1")

result = session.run(workflow_id: "insight-to-action",
                     input: { "question" => "Vì sao doanh thu Q1 tăng?" },
                     context: ctx, dry_run: true)

# 4. Read the structured result — no exceptions ever escape #run.
result.status          # => :completed | :failed | :escalated
result.grounding       # => { coverage:, band:, can_generalize:, evidence_count:, memory_hits:, note: }
result.four_fold_de    # => CDFLHarness::Reasoning::CDFL::FourFoldDE (x/t/if_/mf + manifest_or)
```

---

## Providers

Choose a provider on the `Config`:

```ruby
cfg = CDFLHarness::Config.new
cfg.provider  = :anthropic   # :anthropic | :openai | :ollama | :fake
cfg.api_keys  = { anthropic: ENV["ANTHROPIC_API_KEY"], openai: ENV["OPENAI_API_KEY"] }
cfg.ollama_host = "http://localhost:11434"
```

- **`:fake`** (default) — scripted completions; no network. Used for tests + the demo.
- **`:ollama`** — local, always *internal* (`external?` is `false`).
- **`:anthropic` / `:openai`** — *external*; keys come from `config.api_keys`.

**External calls are double-gated.** The `Router` only routes to an external
provider when **both** `consent_external: true` (per call) **and**
`config.external_enabled = true` (the master kill-switch) hold. Otherwise it
**downgrades** to the local Ollama default. Before any external call, the PII
middleware redacts the prompt. See [`docs/GATEWAY.md`](docs/GATEWAY.md) and
[`docs/INVARIANTS.md`](docs/INVARIANTS.md).

---

## Docs index

| Doc | What it covers |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Module tree, gateway + agent data-flow, Kaori→Ruby mapping, isolation design |
| [`docs/GATEWAY.md`](docs/GATEWAY.md) | Adapters, chat tool-call shape, router/consent downgrade, structured output + repair, breaker, middleware |
| [`docs/AGENT_LOOP.md`](docs/AGENT_LOOP.md) | PLAN→EXECUTE→CRITIC semantics, bounds, transcript, persistence, wiring points, never-raises guarantee |
| [`docs/TOOLING.md`](docs/TOOLING.md) | Writing a `Tool`, `Context`, identity-from-context safety (K-12/K-16), dispatch contract |
| [`docs/PROJECT_READINESS.md`](docs/PROJECT_READINESS.md) | `project_readiness` skill: the gate before the other gates — is there a gate at all, enough cases, a workable base rate, a leak, any signal, enough power |
| [`docs/CHANGE_RISK.md`](docs/CHANGE_RISK.md) | `change_risk` skill: three scorers (ridge · single-feature · sense-blocked), the net-benefit decision procedure, and the four measurement disciplines it enforces |
| [`docs/MEASURE_CLAIM.md`](docs/MEASURE_CLAIM.md) | `measure_claim` skill: power check, preregistration locked by hash, interval comparison, verification with multiplicity surfaced |
| [`docs/CDFL.md`](docs/CDFL.md) | NNL-NTHT → algorithm map; IF/MF/OR/DE; four-fold; empowerment; Hilbert gauge caveat (cites the thesis) |
| [`docs/COVERAGE_GATE.md`](docs/COVERAGE_GATE.md) | "Học 1 hiểu 10": coverage math, bands, decline-not-hallucinate (K-3) |
| [`docs/MEMORY_PALACE.md`](docs/MEMORY_PALACE.md) | Cung điện ký ức: tiers × types, trust decay, maturation, associative recall, promotion→KB loop |
| [`docs/EXTENDING.md`](docs/EXTENDING.md) | Add an adapter / store / middleware; register workflows + tools; embed in a host app |
| [`docs/INVARIANTS.md`](docs/INVARIANTS.md) | The invariants carried over (chokepoint, consent downgrade, PII, identity-from-context, bounded loop, no-hallucinate gate, dry_run, empowerment, best-effort memory) |

---

## Run tests & the demo

```powershell
$env:Path = "C:\Ruby33-x64\bin;" + $env:Path

bundle exec rspec                       # the full suite (Part 1 + Part 2)
ruby -Ilib examples/insight_to_action.rb  # the runnable demo
```

The demo prints the transcript, the `|OR|` coverage band, and the four-fold DE
dashboard line.

---

## License

MIT © 2026 Nguyen Truong An. See [`LICENSE`](LICENSE).
