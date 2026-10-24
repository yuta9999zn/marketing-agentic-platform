# Measure claim — make an agent prove things instead of asserting them

**Intellectual property: Nguyễn Trường An. Use requires the author's permission.**

Tool name: `measure_claim`. Pure Ruby, standard library only.

    lib/cdfl_harness/skills/measure_claim.rb              ledger, power, compare, verify
    lib/cdfl_harness/tooling/tools/measure_claim_tool.rb  agent-facing tool

---

## Why it exists

The programme this was distilled from retracted **seven conclusions in three days**. Not one was a
coding error in the ordinary sense. Every one was a failure of the *procedure around* the
measurement:

| what went wrong | what would have caught it |
|---|---|
| a calibrator fitted on a slice, then scored on that same slice — twice, in two places | disjoint fit/score slices |
| a rival handicapped by a protocol shaped around one method's needs, manufacturing a **+0.077** win | asking "is the comparison fair to the baseline?" |
| the same comparison run on six datasets, the one that passed held up as evidence | counting prior tests on the same data |
| an acceptance criterion of "significant at ≥1 of 7 thresholds" — a bar noise clears routinely | one primary endpoint, fixed in advance |
| a rule refuted on new data, then quietly redrawn to fit what had been seen | locking the criterion by hash |
| mechanisms differing by 0.01–0.03 compared on windows with ±0.05–0.08 error | a power check before spending the study |

An agent that can call this tool cannot make those mistakes silently. It can still make them — but
it has to overwrite a locked record to do so, and the tool will refuse.

---

## The central rule

> **A threshold for "good enough" is only meaningful if it exceeds the standard error of the
> measurement used to test it.**

`power` enforces it. Given pilot data and the effect you hope to find, it bootstraps the metric's
standard error and answers whether that effect is above the noise floor. `detectable: false` is the
useful answer, not a failure — it means: stop tuning this axis, the sample cannot see what you are
looking for.

In the source programme, nine mechanisms differing by 0.01–0.03 AUC were selected between on
windows whose estimation error was ±0.05–0.08. The resulting automatic selector was **worse than
picking nothing** (−0.029). A single `power` call would have said so before the work began.

---

## The four operations, in the order they should be used

```ruby
tool = CDFLHarness::Tooling::Tools::MeasureClaimTool.new(ledger_path: "tmp/claims.jsonl")
registry.register(tool)
```

**1. `power`** — before spending the study.

```ruby
{ operation: "power", metric: "auc", values: pilot_scores, labels: outcomes,
  target_effect: 0.03 }
# → { standard_error: 0.041, detectable: false, smallest_worth_chasing: 0.082,
#     note: "effect is smaller than the noise of the measurement itself; ..." }
```

**2. `preregister`** — before looking at the result.

```ruby
{ operation: "preregister", claim: "blocked scorer beats ridge at the operating threshold",
  metric: "net_benefit", criterion: { direction: "greater", margin: 0.0 },
  prediction: "true", labels: outcomes }
# → { id: "pre-a1b2c3d4e5", fingerprint: "…" }
```

The fingerprint covers claim, metric, criterion **and** prediction. Editing any of them after the
fact produces a different fingerprint, so the edit is visible. Recording `labels` binds the study
to that exact dataset.

**3. `compare`** — an interval, never a point.

```ruby
{ operation: "compare", metric: "net_benefit", a: blocked_risk, b: ridge_risk, labels: outcomes }
# → { difference: 0.056, ci95: [0.027, 0.085], verdict: "a beats b" }
```

**4. `verify`** — against what was written, with multiplicity surfaced.

```ruby
{ operation: "verify", id: "pre-a1b2c3d4e5", labels: outcomes,
  observed_difference: 0.056, ci95: [0.027, 0.085] }
# → { criterion_met: true, prediction_correct: true,
#     prior_tests_on_this_data: 2,
#     multiplicity_warning: "this data has already been tested 2 time(s). At 95% confidence,
#       3 tests produce a false positive about 14% of the time. Treat this result as
#       exploratory, or hold it to a Bonferroni-adjusted alpha of 0.0167." }
```

`verify` **raises** if the data fingerprint differs from the one registered: that is not the study
that was preregistered, and the tool will not pretend otherwise.

---

## Metrics

`mean` · `accuracy` · `auc` (ties by average rank) · `net_benefit` (at the base rate, the point
where "act on everything" breaks even). Shared with the `change_risk` skill, so a claim about one
is measured on exactly the same code that produced it.

---

## What it deliberately will not do

- It will not tell you a claim is true. It tells you whether the criterion **you wrote in advance**
  was met, and how much you should discount that given how often the same data was already asked.
- It will not let a failed prediction be reinterpreted as a success. `prediction_correct` is
  recorded separately from `criterion_met`, because being right for the wrong reason is worth
  knowing about.
- It will not hide multiplicity. Repeated tests on one dataset are counted and reported every time.
