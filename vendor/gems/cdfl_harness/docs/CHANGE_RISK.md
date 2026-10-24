# Change risk — a skill, and the evidence behind it

**Intellectual property: Nguyễn Trường An. Use requires the author's permission.**

Score code changes by risk, and decide which scorer is worth deploying on a given project.
Pure Ruby, no gems beyond the standard library. Tool name: `change_risk`.

    lib/cdfl_harness/skills/change_risk.rb          measurement utilities + linear algebra
    lib/cdfl_harness/skills/scorers.rb              three scorers + the decision procedure
    lib/cdfl_harness/tooling/tools/change_risk_tool.rb   agent-facing tool

---

## What the agent gets

```ruby
tool = CDFLHarness::Tooling::Tools::ChangeRiskTool.new
registry.register(tool)
```

| operation | what it does |
|---|---|
| `choose`  | measures on the project's own history, recommends a scorer, returns the evidence |
| `score`   | fits on history, returns P(fail) for new changes |
| `explain` | (blocked scorer only) names the feature block that drove each score |

`history` is a list of `{features: [...], outcome: 1|0}` **in time order**, where `outcome` is 1
for pass and 0 for fail, and the features were observable **before** the outcome was known. At
least 40 rows with both outcomes; `choose` needs ~100 to say anything useful.

---

## Three scorers, because there is no best one

| scorer | what it is | where it won |
|---|---|---|
| `ridge` | one penalised linear model over all features, penalty chosen out-of-fold | **ranking**, on most repositories measured |
| `single_feature` | the one best-correlated column | **ranking**, on `express` (AUC 0.851 — beat everything) |
| `sense_blocked` | one block per feature group; each earns its own penalty and its own weight from out-of-fold ranking skill; blocks with no skill are **dropped**; the combination is calibrated | **probability quality**, everywhere measured (ECE 0.046–0.075 vs 0.071–0.250) |

Measured across six public repositories (flutter, vue, express, requests, scrapy, Chart.js) plus
two private ones, under a protocol where every method gets the full history window.

The ranking column and the probability column disagree, and that is the point: **a scorer that
ranks well can still be useless for a decision**, because ranking says nothing about *how many*
changes to review. Only calibrated probabilities carry a threshold.

---

## Why `choose` measures instead of guessing

Two rules for predicting the right scorer from a summary statistic were **preregistered and
refuted**:

1. *"deploy the blocked scorer when the incumbent's ECE ≥ 0.12"* — refuted on `express`
   (miscalibrated incumbent, blocked scorer still lost).
2. *"…and when it does not lose more than 0.02 AUC"* — refuted on `scrapy` (rule said don't
   deploy; the blocked scorer delivered +0.056 net benefit at the operating threshold).

So `Decision.choose` does the only thing that survived: split the project's history in half, fit
on the first, measure **net benefit** on the second at the operating threshold, and take the
winner only if a bootstrap CI excludes zero. Otherwise it keeps `ridge`, the cheap default.

Net benefit (Vickers & Elkin) is the metric because it is the only one denominated in decisions:

    net benefit = (failures caught)/n − (false alarms)/n × pt/(1−pt)

At `pt` = the base failure rate — the default — "review everything" has net benefit exactly zero,
which makes it the natural operating point.

Measured differences at that point: **+0.056** (scrapy), **+0.043** (vue), ~0 (requests, express,
Chart.js). Where it wins, it is worth about **4–6 extra real failures caught per 100 changes**,
net of the cost of reviewing the false alarms.

---

## Four disciplines the skill enforces

Each cost days in the programme this was distilled from, and each is now structural rather than
remembered:

1. **Fit and score on disjoint slices** — `disjoint_halves` returns `nil` rather than let a caller
   quietly reuse one slice for both. Fitting a calibrator on a slice and scoring it there inflated
   a result twice before it was caught.
2. **Every method gets the full window.** `Ridge` and `SingleFeature` take no holdout because they
   need none. Reserving 25% of the window for the blocked scorer's needs and imposing the same cut
   on its rivals manufactured a +0.077 win that vanished when the rivals were trained properly.
3. **Batch size scales with the base rate** — `batch_size`. A fixed batch of 6 on a repository with
   a 2.4% failure rate leaves 87% of batches with nothing to rank, and pooled AUC drifts to 0.5,
   which looks exactly like a broken model.
4. **AUC handles ties by average rank** — without it a constant predictor scores ~0.85 and hides a
   real defect.

Two more guards are inside the scorers: dead columns (no variance in the training window) are
dropped before fitting, and the blocked scorer's calibrator is fitted on **out-of-fold**
combinations only.

---

## What this skill will not do

- It will not tell you which scorer suits a project without measuring. That shortcut was tried
  twice and refuted twice.
- It will not help at a lax threshold. When `pt` is well below the base rate, every scorer ties
  with "review everything" — the right answer there is to review everything.
- It needs a real gate. Without recorded outcomes per change there is nothing to fit, and the tool
  raises rather than guess.
