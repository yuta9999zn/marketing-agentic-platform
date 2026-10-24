# CDFL — Convergent Dual-Field Learning

`Reasoning::CDFL::*` is the Ruby port of the **NNL-NTHT** algorithm (Nhất Nguyên
Luận – Nhị Trường Học Thuyết) from the thesis of **Nguyễn Trường An**. It models
learning as the convergence of two fields and reports what is *not yet known* as
a four-faced "dark" dashboard. The Hilbert `I(I:M)` gauge is ported in full but
is **descriptive only** — never on the action-selection path.

> **Citations.** Canonical 12-step algorithm: `Thuật toán tương ứng.docx`.
> Dynamics: `Phan_IV_Dong_hoc_CDFL` (Phần IV). Empirical verification:
> `Phan_IX_Nghiem_chung` (Phần IX — REPORT_V8 / V10 / V11). Author:
> **Nguyễn Trường An**, `D:\Luận văn nhất nguyên 2 trường luận giao thoa`.

## NNL-NTHT in one page

- **IF** (tâm trường / inner field) = an agent's **belief** `σ` + **representation**
  `Φ` (two branches: what it holds true, and the language it can express it in).
- **MF** (vật trường / matter field) = the **environment** state `ρ_MF`, dynamic.
- **OR** (vùng giao thoa / resonant overlap) = the resonant overlap of *IF-known*
  ⋈ *MF-known* where the resonance `γ > 0` marks **true knowledge**. Knowledge
  `K = Φ(OR)`. The **knowledge gap** is `D = |MF| − |OR|`.
- **DE** (vùng tối / Dark Existence) = everything outside OR, reported as **four
  faces** (below). Faces overlap, so DE is *never* the sum of its faces.
- **Two dots** (âm–dương):
  - **black dots** `γ < 0` = illusion / stale belief held as true — the
    false-positive, the AI-safety / calibration problem.
  - **white dots** = DE regions with high `∂OR` potential = intuition / frontier,
    where exploration most grows OR.
- **Action**: `a_t = argmax E[Δ|OR_true|(a)]` — pick the action that most expands
  *true* overlap across all four faces (raise white dots, revisit black dots,
  refresh stale `DE_T`).
- **Continual loop**: there is no hard stop — DE always regrows as MF moves and
  beliefs age. The system records *local-momentary* fullness ("Aha!" /
  `local_resonance`). The ideal limit `max|OR| ⟺ min DE ⟺ ρ_MF = σ_IF` is reachable
  only locally; globally `D ≥ D_min > 0` (an asymptote).
- **Multi-agent / empowerment**: preserving the **diversity of other IFs** enriches
  the *global* OR. Destroying another agent shrinks the shared option space `|OR|`
  — so option-preservation is the ground of AI safety (see `Empowerment` below).

## Dynamics equations (Phần IV)

```
IF_{t+1} = IF_t + α · ∇_IF K        # belief/representation ascends the knowledge gradient
MF_{t+1} = Ψ(MF_t, a_t)            # the world evolves under the chosen action
OR_{t+1} = IF_{t+1} ∩ MF_{t+1}     # overlap re-formed from the updated fields
J        = max |OR|                # the objective: maximise true overlap
```

## The Ruby modules

`Reasoning::CDFL` operationalises the dynamics as a learned planner (the parts
that *do* drive action) plus measurement primitives (the parts that only observe).

### `TransitionModel` — `Ψ` learned, tabular `P(s'|s,a)`
Counts observed `(s, a, s')` transitions and estimates `P(s'|s,a)` by frequency.
This is the **critical** component — the Phần IX ablation shows removing it costs
**−31.6 pp**. Supports recency decay (`tick`), sampling (`sample_next`), and
construction from a process-mining `direct_follows` map.

### `InfoGain` — `IG = novelty + λ · uncertainty`
The exploration scorer (a proxy for `E[Δ|OR|]`):

```
novelty(s')      = 1 / √(N(s')   + 1)     # state-visit count
uncertainty(s,a) = 1 / √(n(s,a)  + 1)     # state-action count
IG(s,a,s')       = novelty(s') + λ · uncertainty(s,a)
```

`λ` is `uncertainty_weight` (default `1.0`); an overall `information_gain_weight`
scales the result.

### `LookaheadPlanner` — H-step Monte-Carlo
For each candidate action, rolls out `num_rollouts` trajectories of `horizon`
steps through the (un-mutated) `TransitionModel`, summing `InfoGain` along each,
and returns `ActionScore{action, mean_score, best_score, visit_proxy}`. Interior
rollout steps are weighted-sampled by info-gain. The planner **never mutates the
model** — rollouts only sample.

### `Agent` — Boltzmann action pick
Combines `TransitionModel + InfoGain + LookaheadPlanner`. `#step(state)` scores
the action space and picks with a **Boltzmann (softmax)** distribution at
`temperature`; `temperature ≤ 0` is greedy (max mean_score, ties broken by lower
visit_proxy). `#observe_transition` updates the model unless `freeze_model`.

### `FourFoldDE` — the Dark-Existence dashboard
Reports DE across **four faces** (Tiên đề 4–5), each a "dark fraction" in `[0,1]`:

| Face | Meaning | Built from |
|---|---|---|
| `x`  | `DE_X` — space unvisited | `1 − data_coverage` |
| `t`  | `DE_T` — knowledge gone stale | `1 − knowledge_freshness` |
| `if_`| `DE_IF` — what `Φ` can't yet represent | `1 − knowledge_coverage` |
| `mf` | `DE_MF` — world not yet exposed | `1 − grounding_score` |

`FourFoldDE.assemble(data_coverage:, knowledge_freshness:, knowledge_coverage:,
grounding_score:)` clips each input to `[0,1]`. The struct exposes `#faces`,
`#max_dark`, and `#manifest_or = 1 − (x + t + if_ + mf)/4` (a coarse "how much is
manifest" summary). **Faces overlap → they are reported, never summed** into a
single DE.

### `Empowerment` — option-preservation / consent
An *irreversible* side-effect shrinks others' future option-space `|OR|`; a
*reversible* one preserves it. `protection_advice(side_effect_class,
reversible_alternative_exists:)` → `ProtectionAdvice{preserves_options,
needs_consent, prefer_reversible, rationale}`:

- `REVERSIBLE_CLASSES = %w[pure read_only write_idempotent]` → preserves options,
  no consent needed.
- `OPTION_SHRINKING_CLASSES = %w[write_non_idempotent external]` → needs consent
  (prefer a reversible alternative if one exists). **Advisory only — never
  auto-blocks.** The `Executor` attaches this advice to irreversible steps.

## HilbertMetric — a DESCRIPTIVE gauge (not on the action path)

`Reasoning::CDFL::HilbertMetric` ports the v10/v11 information-geometry primitives:

```
S(ρ)        = −tr(ρ log ρ)                       # von Neumann entropy
I(I:M)      = S(ρ_I) + S(ρ_M) − S(ρ_IM)          # the |OR| proxy (mutual information)
DE          = S(ρ ‖ σ) = tr(ρ ln ρ) − tr(ρ ln σ) # the Dark-Existence quantity (relative entropy)
```

`I(I:M)` is the quantum mutual information between the inner subsystem `ρ_I` and
the matter subsystem `ρ_M` (obtained by partial trace of the joint `ρ_IM`) — the
information-theoretic stand-in for `|OR|`.

> **The v11 caveat — descriptive only.** Phần IX (REPORT_V11) showed that using
> this gauge to *actively select* actions is **no better than random**. So the
> framework is treated as **descriptive / diagnostic**: the harness uses it for
> observability (measuring overlap and dark mass), and **never** puts it on the
> action-selection path. Action selection is driven by the learned
> `TransitionModel` + `InfoGain` lookahead, not by `HilbertMetric`.

### Real-embedding implementation note

Ruby's stdlib has no complex Hermitian eigensolver. The port uses the
**real-embedding trick**: a Hermitian `H = A + iB` maps to the real **symmetric**
`2n × 2n` matrix `[[A, −B], [B, A]]`, whose eigenvalues equal `H`'s eigenvalues,
each **doubled**. The code then uses stdlib `Matrix#eigensystem` (real symmetric)
and divides by 2 to undo the doubling (e.g. in `von_neumann_entropy`). Partial
trace and the matrix logarithm (for relative entropy) are hand-rolled over the
embedding. Exact-value RSpec specs (ported from the Python tests) pin the results.

---

## Cập nhật theo Phụ lục F (γ vận hành hoá) — `Reasoning::CDFL::Resonance`

> **Bối cảnh.** Phần lõi ở trên port bản CDFL **V8–V11**: thăm dò lái bằng `InfoGain`
> (novelty + uncertainty) và coi `γ` như *khái niệm*. Thesis sau đó **sửa** (Phụ lục F,
> `Phu_luc_F_Co_che_Giao_thoa`): `γ` được **vận hành hoá** thành một *skill score* đo được,
> trục cam kết `e` suy từ `σ`, Tứ Tượng suy từ `(e, γ)`, và — quan trọng — **dò đốm đen phải
> dùng `γ < 0` so THỰC TẠI**, không phải novelty/ensemble-disagreement. Module `Resonance`
> mang bản sửa này vào harness.

```
γ = [S(ρ‖u) − S(ρ‖σ)] / [S(ρ‖u) + S(ρ‖σ)]     # F.4 — +1 cộng hưởng / 0 chưa / −1 ảo tưởng
e = s / (1 + s),  s = S(σ‖u) / D                # F.11 — cam kết, tính CHỈ từ σ
```

> **Sửa F.11 (2026-08) — `e` chuẩn hoá theo chiều.** Bản cũ dùng **TỔNG** `S(σ‖u) = Σ_i log(σ0/σ_i)`
> không chia `D`, nên `e` trở thành hàm của SỐ CHIỀU: cùng một độ sắc, hệ 30 chiều luôn "cam kết
> hơn" hệ 3 chiều — vô lý — và **bão hoà**: với `D=30, σ≈0,05, σ0=0,30` thì `S≈53,7 ⇒ e≈0,982`
> gần như luôn luôn. Đo được (`ontogeny_x_v5.py` mục E0): dải động `e` bản tổng **0,178** so với
> `γ` **0,798**; bản **TRUNG BÌNH** đạt **0,588** (gấp **3,3×**). Bản tổng làm mặt phẳng Tứ Tượng
> `(γ, e)` **sụp thành một đường**. Bản trung bình **bất biến theo `D`**, giữ nguyên hai đầu mút
> (`σ=σ0 ⇒ e=0`; `σ→0 ⇒ e→1`) và giữ nguyên toàn bộ diễn giải Tứ Tượng.
> Bản tổng còn giữ dưới tên `Resonance.commitment_sum` **chỉ để tái lập số cũ**.

- `Resonance.gamma(dark_vs_u:, dark_vs_sigma:)` — γ từ hai độ tối `S(ρ‖·) ≥ 0`.
- `Resonance.gamma_for_transition(model, s, a, s_next)` — **nối γ vào `TransitionModel`**:
  `σ = P(·|s,a)`, `u` = đều trên `known_states`, `ρ = s'` quan sát → `γ = (ln|known| + ln P) /
  (ln|known| − ln P)`. Đây chính là skill score của mô hình dịch chuyển (đo được, held-out).
- `Resonance.commitment(dark_sigma_vs_u:, dims: 1)` — `e` từ `S(σ‖u)`, **chia cho `dims`** (số
  chiều mà `S` đã cộng dồn trên đó). `dims: 1` = độ tối đã chuẩn hoá sẵn / trường hợp một chiều.
- `Resonance.commitment_from_sigmas(sigmas:, sigma0:)` — **lối gọi khuyến nghị**: `e` thẳng từ danh
  sách `σ_i` và `σ0`, không thể quên chuẩn hoá theo chiều.
- `Resonance.commitment_sum(dark_sigma_vs_u:)` — **[legacy]** bản TỔNG cũ, bão hoà theo `D`.
- `Resonance.sixiang(e, γ)` — Tứ Tượng: Lão Dương (OR thật) / Thiếu Âm (đốm tối) / Thiếu Dương
  (đốm sáng) / Lão Âm (DE sâu), theo F.5.
- `Resonance.black_dot?(e, γ)` — **đốm đen = `e > 0 & γ < 0`** (cam kết mà sai). Phần IX TN 6.5:
  error-seek `γ<0` tìm **92,8%** vùng khó; ensemble-disagreement/novelty né vùng khó (**4,6%**)
  và mù trước đốm tối. ⇒ Với việc *bắt đốm đen*, `γ<0` thay thế cách thăm dò novelty của lõi cũ.

> **Kỷ luật chống Goodhart (F.11).** `γ` là thước đo **sau-kết-cục trên held-out**, không đưa
> trực tiếp làm hàm mục tiêu huấn luyện. `HilbertMetric` (mô tả-only, cảnh báo v11) vẫn không
> nằm trên đường chọn hành động — điểm này bản sửa KHÔNG đổi.
>
> **Trạng thái tích hợp.** `Resonance` đã có mặt và đo được; việc thay `InfoGain` bằng error-seek
> `γ<0` làm scorer *mặc định* trên đường hành động là bước kế (lõi cũ giữ làm proxy tham chiếu).
