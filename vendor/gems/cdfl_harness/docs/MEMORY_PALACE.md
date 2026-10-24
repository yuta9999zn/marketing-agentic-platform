# Memory palace — "cung điện ký ức"

`Reasoning::Memory::Service` is the synchronous Ruby port of Kaori's memory
palace (ADR-0030 trust + ADR-0032 maturation/associative recall). It organises an
agent's accumulated knowledge along **two orthogonal axes**, decays trust over
time, *matures* with use, recalls associatively, and feeds a memory→KB promotion
loop. The in-memory backend ships; real stores are pluggable.

## Two orthogonal axes

A `MemoryRecord` has both a **lifecycle tier** (where it sits in its storage
journey) and a **cognitive type** (what kind of memory it is). These are
independent.

**Lifecycle tiers** (`Memory::TIERS`):

| Tier | Stage |
|---|---|
| `L1_WORKING` | scratch / working set |
| `L2_SHORT` | short-term (session-scoped on retrieve) |
| `L3_CONSOLIDATED` | consolidated |
| `L4_LONG` | long-term |

**Cognitive types** (`Memory::TYPES`) and their default landing tier:

| Type | Default tier |
|---|---|
| `EPISODIC` | `L2_SHORT` |
| `SEMANTIC` | `L4_LONG` |
| `PROCEDURAL` | `L4_LONG` |
| `OPERATIONAL` | `L3_CONSOLIDATED` |
| `DECISION` | `L3_CONSOLIDATED` |

### Classic-taxonomy view

`Memory.classic_memory_class(type)` maps the 5 types onto the textbook taxonomy:
`EPISODIC` / `DECISION` → `"episodic"`, `SEMANTIC` → `"semantic"`,
`PROCEDURAL` / `OPERATIONAL` → `"procedural"`.

## Importance (retention) — PIPELINE_UNIFIED §7.5

`Memory.compute_importance(record)` ∈ `[0,1]`:

```
recency = max(0, 1 − days_old/90)
repeat  = min(1, session_appearance_count/5)
flag    = user_flagged_important ? 1 : 0
outcome = linked_outcome_value > 10_000_000 ? 1 : 0
importance = min(1, 0.2·recency + 0.3·repeat + 0.3·flag + 0.2·outcome)
```

Importance drives `promote` (L3→L4) and `forget`.

## Trust decay — "is this still believable?"

`Memory.compute_trust(record)` decays confidence since the record was last
verified (or, failing that, since it occurred):

```
trust = confidence · 0.5 ^ (age_days / half_life)
```

Per-type half-lives (`HALFLIFE_DAYS`, days) — learned concepts age slowly,
episodic memories fast:

| Type | Half-life (days) |
|---|---|
| `SEMANTIC`, `PROCEDURAL` | 365 |
| `DECISION`, `OPERATIONAL` | 60 |
| `EPISODIC` | 30 |

Trust levels: `fresh ≥ 0.66`, `aging ≥ 0.33`, else `stale`. A
**"confident-but-unchecked"** flag fires when `confidence ≥ 0.8`, the record was
never verified, and `age > half_life` — i.e. a high-confidence memory that has
aged past its half-life without verification (a calibration risk; the CDFL "black
dot"). `Memory.trust_factor(record)` ∈ `[0.4, 1.0]` is the retrieval-ranking
multiplier derived from trust.

## Maturation — "càng nhiều tháng càng biết nhiều"

Two mechanisms make the palace *better* with use:

- **`reinforce_confidence(record)`** (ADR-0032) — a validated use bumps confidence
  along an asymptotic learning curve toward a **per-source ceiling** (never 1.0 —
  epistemic humility):
  ```
  confidence ← confidence + learn_rate · (ceiling − confidence)
  ```
  Ceilings (`CONF_CEILING`): `user 0.98`, `consolidate 0.90`, `rag 0.90`,
  `derived 0.85` (default `0.85`). `learn_rate` = `config.reasoning.learn_rate`
  (default `0.15`, env `CDFL_MEM_LEARN_RATE`).

- **`experience_level(records)`** — a tenant's maturation from accumulated
  still-trusted knowledge:
  ```
  knowledge_mass = Σ trust(record)
  experience     = 1 − exp(−k · knowledge_mass)
  ```
  `k` = `config.reasoning.experience_k` (default `0.15`, env
  `CDFL_MEM_EXPERIENCE_K`). Bands by score (`EXPERIENCE_BANDS`):
  `chuyên gia ≥ 0.80`, `dày dạn ≥ 0.55`, `thành thạo ≥ 0.30`, `tập sự ≥ 0.10`,
  else `mới`. So more months of trusted memory ⇒ a higher experience band —
  literally "the longer it runs, the more it knows".

## Operations (`Service`)

| Method | What it does |
|---|---|
| `write(tenant, type, content, ...)` | store a record at its type's default tier |
| `retrieve(tenant, query, top_k:, ...)` | trust-ranked text match + entity boost + associative recall |
| `consolidate(tenant)` | move all `L2_SHORT` → `L3_CONSOLIDATED` |
| `promote(tenant, importance_threshold:)` | `L3 → L4` for records above the importance threshold (`0.7`) |
| `forget(tenant, ...)` | TTL/importance eviction from L3, or `full_tenant_wipe` (GDPR) across all tiers |
| `verify(tenant, id)` | reset the decay clock (`last_verified_at = now`) |
| `reinforce(tenant, id)` | reset decay **and** climb the confidence curve |
| `link(tenant, a, b, mutual:)` | add an associative edge between two records |
| `experience(tenant)` | report the tenant maturation band over L3+L4 |

## Associative recall

`retrieve` works in three layers:
1. **Cheap text match** (`cheap_text_match` = token-set Jaccard, Unicode-aware)
   across the walked tiers (`L2/L3/L4` by default; L2 is filtered to the current
   `session_id`).
2. **Entity boost** — multiply the score by `entity_boost` (default `2.0`) when
   `entity_id` matches.
3. **Trust ranking** — multiply by `trust_factor(record)`, sort, take `top_k`,
   and bump each result's `session_appearance_count` (a retrieval signal).
4. **One-hop associative recall** — expand along each result's `metadata["links"]`
   (built by `link`), pulling in connected records up to `expand_limit`.

## Memory → KB promotion loop

A successful, non-dry agent session is consolidated into an `:OPERATIONAL` memory
(see [`AGENT_LOOP.md`](AGENT_LOOP.md)). Over time, repeatedly-reinforced,
high-trust memories represent durable understanding that belongs in the knowledge
base — the *memory → KB promotion loop*: operational memories that mature can be
distilled into `Reasoning::Knowledge::Document`s, where they then count toward the
[coverage gate](COVERAGE_GATE.md). The harness ships the **in-memory** stores
(`InMemoryTierStore`); the `TierStore` and `Knowledge::Store` contracts let a
project swap in Redis / Postgres / Neo4j / pgvector for the durable side of this
loop (see [`EXTENDING.md`](EXTENDING.md)).
