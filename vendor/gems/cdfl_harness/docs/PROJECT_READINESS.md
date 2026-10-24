# Project readiness — the gate before the other gates

**Intellectual property: Nguyễn Trường An. Use requires the author's permission.**

Tool name: `project_readiness`. Pure Ruby, standard library only.

    lib/cdfl_harness/skills/project_readiness.rb
    lib/cdfl_harness/tooling/tools/project_readiness_tool.rb

---

## Why it comes first

`change_risk` and `measure_claim` both assume something often false: that a project has a point at
which reality passes judgement, and that enough judgements have been recorded to learn from. Call
this tool **before** either of them.

The rule it encodes:

> **A project with no point at which reality judges cannot host a learner at all.**

A real operating system built entirely on measurable theory turned out to have a full test suite
(72/72 items) and **no recorded history** — every run's verdict evaporated. Nothing could be learned
from it, not because the work was poor but because nothing was written down. The remedy was not a
better model; it was one commit that started keeping the book.

---

## Three verdicts, and always a next step

| verdict | meaning |
|---|---|
| `not_ready` | something blocks learning entirely — no gate, no signal, a leak, a backwards timeline, or a history too thin |
| `usable_but_thin` | explore, but do not act on a result yet; the reply says how many more cases are needed |
| `ready` | proceed to `change_risk` `choose` |

```ruby
tool.call({ "history" => rows,
            "feature_phases" => [{ "name" => "files_touched", "phase" => "before" },
                                 { "name" => "seconds_taken", "phase" => "after" }],
            "target_effect" => 0.05 }, ctx)
```

---

## What is checked, and the measurement behind each threshold

| check | blocks when | why that number |
|---|---|---|
| **gate** | every recorded outcome is identical | a gate that never fails teaches nothing — either it is too lax, or failures are not being recorded |
| **density** | fewer than 25 cases | measured on a 25-case project: holding out a validation slice scored **0.405** while ignoring discipline scored **0.736**. Below that point, being careful actively loses. 150 before a result should be acted on. |
| **base rate** | failure rate outside 2%–98% | at 2.4% a batch needs ~126 changes to contain 3 failures; a short history then yields almost no usable batches, and pooled scores drift toward 0.5 — which looks exactly like a broken model |
| **time order** | timestamps not monotonic | training on later cases to predict earlier ones is looking at the future |
| **leakage** | any feature declared `at` or `after` the verdict | two leaks in the source programme each produced a beautiful result that collapsed when closed. Undeclared phases report **UNCHECKED**, never "clean". |
| **degeneracy** | *(warns)* constant or near-duplicate columns | constants make the design rank-deficient; near-duplicates pushed condition numbers into the 10¹⁶ range |
| **signal** | no single feature beats AUC 0.55 | if the cheapest possible model cannot rank better than chance, an elaborate one will not either — change what you observe, not how you model it |
| **power** | *(warns)* the effect you care about is inside 2×SE | mechanisms differing by 0.01–0.03 were once selected between on windows with ±0.05–0.08 error; the resulting selector was worse than choosing nothing |

---

## A worked example on real data

Run against the gate book of an operating-system project four commits after it started recording:

```
GIAO: 4 records
verdict          : not_ready
cases still needed: 146
  [blocking] gate       : every recorded outcome is the same (1.0)
  [blocking] density    : 4 cases — below the point where disciplined fitting beats careless fitting
  [blocking] base_rate  : failure rate 0.0% is extreme
  [ok]       time_order : history is in time order
  [blocking] leakage    : 1 feature(s) not observable before the verdict: seconds_taken (after)
  [thin]     degeneracy : 1 near-duplicate pair(s)
next step: fix the blocking finding first: gate — a gate that never fails teaches nothing.
```

The most useful line is the first. The project's suite passes every time, so **even at 150 commits
it would teach nothing**: a book of all-passes has no failures to learn from. The fix is to record
a finer outcome — per-item results rather than only the aggregate — so partial failures survive
into the record. That is a design change to the gate, and no amount of modelling substitutes for it.

---

## What it will not do

- It will not assume undeclared features are clean. `unchecked` is a distinct answer from `ok`.
- It will not pass a project because the numbers look nice. Every blocking finding carries the
  remedy, not just the complaint.
- It will not estimate readiness without outcomes. With none, it says so and tells you to start
  keeping the book.
