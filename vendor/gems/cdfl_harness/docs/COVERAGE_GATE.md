# Coverage gate — "học 1 hiểu 10"

The coverage gate is the harness's anti-hallucination guard (ADR-0033, the K-3
analog). The principle is *học 1 hiểu 10* — "learn one, understand ten": when an
agent has **enough durable foundational knowledge** it may generalise; when it
doesn't, it **declines instead of hallucinating**. The gate lives in
`Reasoning::Knowledge::Coverage` and is enforced in the agent loop through
`Grounding::Gate`.

## The coverage formula

```
coverage = 1 − exp(−k · Σ sim · confidence)     over FOUNDATIONAL docs only
```

- `sim` = `max(0, 1 − distance)` — the retrieval similarity of a knowledge doc
  (`distance` is pgvector cosine distance; `nil` → `0.0`).
- `confidence` = the doc's maturity in `[0,1]`.
- `k` = `config.reasoning.coverage_k` (default `0.6`, env `CDFL_KB_COVERAGE_K`).
- The sum runs **only over foundational tiers** — `FOUNDATIONAL_TIERS = [1, 2]`.

`1 − exp(−k·mass)` is a saturating curve: more (and stronger) foundational
evidence pushes coverage toward 1, with diminishing returns.

## Why only foundational tiers count

Knowledge docs carry a tier:

| Tier | Kind | Counts toward coverage? |
|---|---|---|
| 1 | regulatory | **yes** (foundational) |
| 2 | curated | **yes** (foundational) |
| 3 | market / volatile | no |
| 4 | tenant notes | no |

Durable *understanding* should grow over time from stable, authoritative
knowledge — not from volatile market chatter or a tenant's transient notes. A
pile of tier-3/4 hits could otherwise inflate "coverage" without the agent
actually understanding the domain. Excluding the volatile/tenant tiers means the
gate measures real foundational grounding, which is exactly what should license
generalisation.

## The bands

`coverage_gate(coverage)` → `{ can_generalize:, band:, coverage:, note: }`:

| Band | Condition | `can_generalize` | Meaning |
|---|---|---|---|
| `đủ` | `coverage ≥ gen_min` (`0.60`) | `true` | enough to generalise (học 1 hiểu 10) |
| `thận trọng` | `gen_caution ≤ coverage < gen_min` (`0.30`–`0.60`) | `true` | generalise **cautiously**, state assumptions |
| `chưa đủ` | `coverage < gen_caution` (`0.30`) | `false` | **do not** generalise — gather more foundational knowledge |

Thresholds: `gen_min = config.reasoning.gen_min` (env `CDFL_KB_GEN_MIN`),
`gen_caution = config.reasoning.gen_caution` (env `CDFL_KB_GEN_CAUTION`).

## Decline-not-hallucinate (K-3)

When the band is `chưa đủ`, `can_generalize` is `false`. The correct behaviour is
to **decline / ask for more evidence**, never to silently fabricate an answer.
The gate errs toward declining: the formula is conservative and the bands set a
real floor before generalisation is licensed. This is the Ruby embodiment of
Kaori's K-3 ("enough foundational knowledge → generalise, else decline — no
hallucination").

## How the critic enforces it — `Grounding::Gate`

`Grounding::Gate.assess(transcripts, k:)` turns the evidence the agent actually
gathered into a coverage band:

1. Scan executor transcript rows.
2. From `retrieve_evidence` results, collect each citation's `similarity`,
   **floored** — only sims `≥ sim_floor` (`config.reasoning.sim_floor`, default
   `0.35`, env `CDFL_KB_SIM_FLOOR`) contribute. This drops weak, barely-relevant
   hits that would otherwise pad coverage.
3. From `recall_memory` results, add a **capped** memory contribution:
   `mem_mass · min(memory_hits, mem_cap)` (`mem_mass` default `0.2`, env
   `CDFL_MEM_MASS`; `mem_cap` default `3`, env `CDFL_MEM_CAP`). The cap stops a
   flood of memory hits from manufacturing confidence.
4. `coverage = 1 − exp(−k · mass)`, then run `coverage_gate(coverage)` and merge
   in `evidence_count` + `memory_hits`.

The `Critic` consumes this:
- For `llm_critic: false` workflows the **gate is the verdict** —
  `can_generalize ? "accept" : "replan"`.
- For LLM critics, if `workflow.requires_grounding` and the gate says "chưa đủ",
  an `"accept"` verdict is **overridden to `"replan"`** with a `|OR|` note.

All knobs are `Config::ReasoningConfig` fields, **env-readable and never
hardcoded at call sites** — a host project tunes the gate without touching code.
