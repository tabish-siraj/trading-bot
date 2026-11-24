# PROJECT MAP: ML-Filtered Multi-Asset Trading System (MT5)

> **Agent: read this entire file at the start of every session.** It is the single source of truth for what we are building, why, in what order, and what "done" means for each step. If the user's instructions conflict with this file, point out the conflict and ask before proceeding. Update the **Status Tracker** and **Decision Log** at the end of any session that changes them.

---

## 1. What we are building

A systematic trading system for MetaTrader 5 (MT5) that:

1. Runs a **simple, rules-based base strategy** with an economic rationale.
2. Uses a **rules-based meta-filter first**, then an **ML meta-filter**, to decide whether to take or skip each base-strategy signal.
3. Wraps everything in a **fixed, non-negotiable risk layer**.
4. Starts on **gold (XAUUSD)**, then expands to other liquid markets (silver, BTC, ETH, oil, possibly more) **only after gold passes every gate**.
5. Eventually adds a **self-learning loop** (scheduled retraining) and a **news/context layer**, both strictly after the core is proven.

**Primary goal:** find out, as cheaply and honestly as possible, whether a real edge exists after realistic costs. A finding of "no edge here" is a valid, valuable outcome, not a failure of the project.

**Not a goal:** maximizing a backtest curve. Any result that looks too good is treated as a bug until proven otherwise.

---

## 2. Environment and constraints

| Item | Value |
|---|---|
| Platform | MetaTrader 5 |
| MT5 runtime | Windows VM or Windows VPS. MT5 is Windows-native; the dev machine is macOS, so the EA, Strategy Tester and demo terminal all live on Windows. Record the exact environment in `docs/runtime.md`. |
| Dev workstation | macOS, for Python research and editing. Code that must run inside MT5 is transferred to the Windows runtime. |
| Broker / account | Exness, **demo only** until explicitly promoted (see Section 5). Account type (raw-spread vs standard) must be pinned and recorded before any cost modelling. |
| Hosting | Windows runtime now, VPS later (Phase 5 onward) |
| Research language | Python (pandas, numpy, scikit-learn; LightGBM/XGBoost optional; ONNX only if the Phase 3 export constraint allows it) |
| Execution language | MQL5 Expert Advisor (EA) |
| First instrument | XAUUSD |
| Later instruments | XAGUSD (silver), BTCUSD, ETHUSD, oil (UKOIL/USOIL or broker equivalent), others TBD |
| Broker physics artifact | `config/assets/XAUUSD.yaml`, committed: contract size, tick size/value, lot min/max/step, stop/freeze levels, swap (incl. Wednesday triple), netting vs hedging, trading hours, commission. Verify in Market Watch; never assume. |
| Capital at risk | None. Demo only. No live trading without explicit written approval from the user. |

**Symbol names differ by broker and account type** (suffixes, different oil naming). Always verify exact symbol names, contract sizes, tick sizes, trading hours, and swap rules in the MT5 Market Watch / symbol specification before working on any instrument. Never assume.

**Broker physics are committed, not remembered.** Every verified value (contract size, tick size and value, lot min/max/step, stop and freeze levels, swap including the Wednesday triple, netting vs hedging, trading hours, commission, account type) goes into `config/assets/<SYMBOL>.yaml` with the date and MT5 build it was verified against. If a later phase needs a number, it reads the file; if the file is missing a number, that is a blocker, not a cue to guess.

**Disclaimer for the agent to keep in mind:** nothing here is financial advice, and no profitability is promised. Most retail strategies do not survive realistic costs. Plan for that possibility.

---

## 3. Non-negotiable principles (apply to every phase)

1. **Gates, not vibes.** Each phase has a pass/fail check. No phase starts until the previous one passes. No phase is skipped.
2. **Pass criteria are written down BEFORE looking at results.** Fill in the numeric thresholds in the phase's "Pre-registered criteria" block first, then run the test. Do not move the goalposts after seeing results.
3. **Count every trial.** Maintain a Trial Log (Section 9). Every strategy variant, parameter set, feature set, or model tried counts. The more trials, the more skeptical we must be of the best one.
4. **Costs are always in.** Spread, commission (if any), slippage, and swap are modeled in every backtest from the first one. A backtest without costs is not a result.
5. **No look-ahead, no leakage.** Features at time *t* use only data available at or before the decision time. Labels are computed strictly forward. Validation uses time-ordered splits with purging and an embargo.
6. **Simple before complex.** Rules baseline first, then regularized linear/logistic, gradient boosting only if it earns its place out-of-sample.
7. **The risk layer is fixed and untouchable.** No ML component, retraining loop, or optimizer may modify position-size caps, daily loss cap, spread filter, or demo lock. They are hard-coded or live in a config the model cannot write to.
8. **Parity is verified, not assumed.** Python features/signals must match MT5 EA output on the same data before trusting any MT5 result.
9. **One new thing at a time.** Each added layer (ML, news, new asset, retraining) must demonstrably improve out-of-sample, after-cost results, or it is removed.
10. **If a phase fails, fix it or drop it.** Do not push forward on a failed gate.
11. **Power before precision.** Before running any experiment, state the smallest effect the available sample could detect. If the effect you need is below that, get more data, broaden the candidate population, or simplify the method — do not run an underpowered test and call the result "inconclusive."
12. **Rules before models.** The first meta-filter is a small set of explainable rules derived from Phase 2 diagnostics. An ML model must beat that rules baseline out-of-sample, after costs, or it is not used.
13. **The holdout is enforced by code, not discipline.** Held-out data lives in a separate location with exactly one reader and a committed access log. Pre-registered criteria are hashed before each test run.
14. **Log the trial before you run it.** Append the trial to the Trial Log and commit it *before* executing. Reported significance must account for the total number of trials (multiple-testing correction).
15. **Comparisons are paired and nested.** When comparing a filter to its base, compare per-trade outcomes on the same trades, and tune every threshold, feature set, and hyperparameter inside the training fold. Never select anything on the evaluation set.
16. **Kill criteria exist before the first experiment.** Project-level and phase-level stop conditions, including a time budget, are agreed before Phase 2 starts.

---

## 4. Roadmap overview

| Phase | Name | Core question | Status |
|---|---|---|---|
| 0 | Foundation | Is the platform and risk layer ready? | Done (artifacts to be captured in the repo — see Phase 0b) |
| 0b | Repo + walking skeleton | Does a trivial signal reach the demo and log end-to-end? | Not started |
| 1 | Data | Do we have clean, gap-free, UTC-consistent data with cost info? | Not started |
| 1.5 | Statistical power check | Can this sample even detect the edge we need? | Not started |
| 2 | Base strategy | Is the plain strategy roughly breakeven or better after costs? | Not started |
| 3 | ML meta-filter | Does ML beat the plain strategy out-of-sample, with confidence? | Not started |
| 4 | Port to MT5 | Does the EA reproduce Python signals exactly? | Not started |
| 5 | Strategy Tester + demo | Do MT5 results and demo execution match the backtest? | Not started |
| 6 | Robustness and kill criteria | Does the edge survive stress, and when do we stop? | Not started |
| 7 | Self-learning loop | Does scheduled retraining improve things without adding instability? | Not started |
| 8 | News / context layer | Does each context input improve results? | Not started |
| 9 | Multi-asset expansion | Does the framework generalize, asset by asset? | Not started |

Note: robustness (Phase 6) was added to the original plan, and the self-learning loop was pushed later because it is the riskiest and least certain layer. News calendar filtering (the cheap part of Phase 8) may be tested early, but only as a **separate pre-registered trial** logged and reported apart from the clean Phase 2 baseline — never folded into it.

Phase 0b (repo + walking skeleton) and Phase 1.5 (statistical power check) were inserted after the first review: the first proves the plumbing before any research investment, the second stops an underpowered ML experiment before it starts. Phase 0b is required because, at the time of the first review, the working directory contained none of the Phase 0 artifacts and was not a git repository; "done" is not the same as "captured."

---

## 5. Phase details

### Phase 0: Foundation (DONE)

**Delivered**
- MT5 on Exness demo account.
- Base EA containing the **risk layer**: position sizing, daily loss cap, spread filter, demo lock.
- Signal logic in the base EA is a placeholder and will be replaced.

**Standing rules from this phase**
- The demo lock stays on. Removing it requires explicit user approval.
- The risk layer code is not edited by any later phase except to add per-instrument parameters in config.

---

### Phase 0b: Repo and walking skeleton (do first)

**Why:** Phase 0 is marked done, but the working directory currently holds no EA, no risk-layer source, and no git history. Until the artifacts are captured and a trivial end-to-end path is proven, every later phase rests on an unverified foundation.

**Tasks**
1. `git init`, first commit of `PROJECT_MAP.md`, and a `.gitignore`. Make `PROJECT_MAP.md` reachable as `AGENTS.md` (symlink or copy) so every agent session loads it automatically.
2. Capture the Phase 0 EA and risk-layer source into `mt5/experts/`, with a short README of the MT5 build and the account/symbol settings it assumes.
3. Refactor the risk layer into a module with a narrow interface (`check(proposedOrder) -> approve | reject(reason) | resize(lots)`), unit-testable in isolation. Keep it out of the strategy file so later work cannot edit it by accident.
4. Build the **walking skeleton**: placeholder signal → risk check → demo order → structured log (signal time, intended vs fill price, slippage, spread at entry, skip reason). One order is enough to prove the plumbing.
5. Pin the runtime: confirm where MT5 actually runs (Windows VM/VPS), record the MT5 build number, and confirm Strategy Tester tick availability. Write it down in `docs/runtime.md`.

**Gate:** the skeleton places and logs at least one demo order, the risk module has passing tests, and the risk-layer source is committed.

**Captured EA — known issues to fix before/at Phase 2**
- Session and server-day boundaries use **server time** (`TimeCurrent`, `dt.hour`), not UTC. This is the DST trap the plan warns about; it must move to UTC before any session strategy.
- Position sizing and the daily loss cap use **account balance**, not equity. Switch deliberately and document the choice.
- If computed lots fall below the broker minimum, the trade is **skipped** rather than rounded up to min lot. Keep or change deliberately; either way, document it.
- `InpMinAtr` is a hardcoded price-unit threshold for gold. Replace with a regime-normalised measure in Phase 2.
- The spread cap is a single global value. Phase 2 needs a spread-by-hour table.
- The signal is **trend-pullback**, a placeholder. Only the risk layer carries into Phase 2, whose primary candidate is session breakout.

---

### Phase 1: Data

**Goal:** a trustworthy historical dataset for XAUUSD (and a repeatable pipeline we can rerun for other symbols later).

**Tasks**
0. **Pre-check first (30 minutes, before building anything):** export the maximum available XAUUSD history from the Exness demo and record row counts and date range. If that history is too short for the Phase 1.5 power check, change the data source *before* building the pipeline.
1. Export XAUUSD bars from the Exness MT5 demo: M1 and M5 required, M15 if needed. Export as much history as the broker provides.
2. Capture **spread per bar** (MT5 bar spread is a snapshot, not a full cost history; treat it as an approximation).
3. **Convert all timestamps to UTC.** Exness server time is not UTC and shifts with US daylight saving. Determine the server offset rules explicitly, handle the DST transitions, and document them. A silent offset error can break any session-based strategy.
4. Cross-check against an **independent source** (for example Dukascopy tick/bar data) for price agreement, gaps, and history length. Demo history is often shorter than expected. Also pull a **tick-level validation window** for realistic fill and cost modelling, even if research runs on bars.
5. Build a cleaning and validation script that is deterministic and rerunnable.
6. Store raw data and cleaned data separately. Never overwrite raw.
7. **Split off the final holdout mechanically** into `data/holdout/` (by time, e.g. the last 20%). Only `scripts/holdout_eval.py` may read it, and every read appends to `logs/holdout_access.log` (committed). The main research code must have no path that can touch this folder.
8. Pin broker physics into `config/assets/XAUUSD.yaml` (see Section 2). Verify every value in Market Watch; never assume.

**Validation checks**
- No unexplained gaps (known market closures like weekends and holidays are documented, not "gaps").
- No duplicate timestamps, no non-monotonic times.
- No negative or zero prices, no bar where high < low, no absurd spikes without explanation.
- Spread series sane: widening around rollover and news is visible and plausible.
- Timezone check: known events (for example the daily rollover gap, major data releases) line up at the expected UTC times, in both DST and non-DST periods.
- **DST mismatch test:** the US and EU switch DST on different dates. For the 2–3 week windows each spring and autumn where they disagree, verify that a fixed wall-clock event (London open, NY open) maps to the expected UTC time. Session strategies break silently here.
- Row counts and date ranges documented.

**Pre-registered criteria (fill in before running)**
- Minimum history length: ______ years
- Maximum tolerated unexplained gap rate: ______ %
- Maximum price disagreement vs independent source: ______
- Holdout fraction and cut date (fixed before any backtest): ______

**Gate:** clean data, documented UTC handling, validation report produced, holdout physically separated, and the report reviewed with the user.

**Deliverables:** `data/raw/`, `data/clean/`, `data/holdout/`, `logs/holdout_access.log`, `config/assets/XAUUSD.yaml`, `data_pipeline` scripts, `reports/data_validation.md`.

---

### Phase 1.5: Statistical power check (gate before Phase 2)

**Goal:** decide, from the data actually available, whether an ML meta-filter can ever be shown to help — before investing in one.

**Tasks**
1. From the cleaned history, estimate the realistic candidate count per year for the Phase 2 design (broad breakout population: London and NY sessions plus retests).
2. Estimate trade-level noise (standard deviation of R per trade) from a crude first-pass backtest. This is a planning number, not a result.
3. Compute the **minimum detectable effect (MDE)**: the smallest improvement in expectancy a paired comparison could detect with the available out-of-sample trade count, at the chosen confidence level.
4. Write down the effect size worth pursuing and compare it to the MDE.

**Pre-registered criteria (fill in before running)**
- Expected candidates per year: ______
- Std dev of R per trade: ______
- Required effect to pursue: ______ R per trade
- MDE at the planned sample: ______ R per trade
- Decision rule: proceed only if required effect > MDE. Otherwise broaden the candidate population, lengthen history, or drop the ML layer in favour of rules.

**Gate:** the MDE is smaller than the effect worth pursuing, or the plan is changed until it is. Record the numbers.

**Deliverables:** `reports/phase1_5_power.md`, updated Decision Log.

---

### Phase 2: Base strategy

**Goal:** find out whether a plain, explainable strategy has any edge after costs, before any ML.

**Primary candidate: Session breakout (broad candidate population)**
- Define the Asian-session range (UTC hours fixed and documented).
- Treat **every breakout attempt** as a candidate: London open and NY open, plus a defined retest/re-entry rule. Do **not** cap at one trade per day; that cap starves the Phase 3 learner. The meta-filter — not an arbitrary cap — is what prunes trades.
- Define explicitly: range window, breakout trigger, entry method, stop-loss, take-profit or exit rule, time stop, retest definition, spread filter. All of these are part of the versioned strategy spec.
- Report **candidate count** separately from **taken-trade count**; the gap is exactly what the filter will work on.

**Rationale for the broad population:** ~250 candidates/year leaves Phase 3 underpowered (see Phase 1.5). Multiple sessions and retests multiply the learning signal without pretending the edge is stronger.

**Optional second candidate (at most one):** a momentum or trend-following variant. If two candidates are compared, **both count as trials** and are judged against the same pre-registered criteria.

**Expectation to hold honestly:** the Asian-range breakout on gold is widely known. The plain version may be marginal after costs. Finding that out cheaply is the point of this phase.

**Backtest requirements**
- Real spread (from Phase 1 data), plus slippage assumption, plus commission/swap if applicable. Model breakout entries with **adverse slippage** (stop entries during breakouts are systematically worse than a constant assumption), and use a "spread by hour" table rather than one global average.
- Use a stressed-cost scenario as well (for example spread x1.5–x2, extra slippage).
- Report: candidate count, taken-trade count, win rate, average win/loss, net expectancy per trade in price units and in R, profit factor, max drawdown, longest drawdown, equity curve, monthly returns, performance by year, by session, by day of week.
- Parameter sensitivity: show results across a neighborhood of parameters, not just the single best one. A good strategy works across a plateau, not at a spike.
- The **final holdout is excluded mechanically** from every Phase 2 run (Phase 1 task 7). There is no code path that reports on it; do not "peek" with a full-history run.
- News-calendar filtering is **not** part of the Phase 2 baseline. If tested now, it is a separate pre-registered trial, logged and reported separately.

**Pre-registered criteria (fill in before running)**
- Minimum candidate count: ______
- Minimum taken trades after costs: ______
- Minimum net expectancy after costs: ______ R per trade
- Maximum drawdown acceptable: ______ %
- Must remain non-negative under stressed costs: yes / no
- Time budget before reassessment: ______ weeks (project-level kill criterion, agreed now — see Phase 6)

**Gate:** roughly breakeven or better after costs and passing the pre-registered criteria. If hopeless, **change the base strategy** before adding anything. Do not rescue a bad base with ML. If the gate is underpowered rather than failed, return to Phase 1.5 rather than pushing on.

**Deliverables:** `strategies/session_breakout` spec and code, `reports/phase2_backtest.md`, updated Trial Log.

---

### Phase 3: ML meta-filter

**Goal:** a model that scores each base-strategy candidate trade as take or skip, and improves out-of-sample, after-cost results.

**Concept:** the base strategy generates candidates. The model does not invent trades; it only filters them. The sample size equals the base strategy's candidate count. The broad Phase 2 design (London, NY, retests) is deliberately chosen so that count is large enough for a filter to be learnable — but this is still small data, and overfitting is the main enemy.

**Labels**
- The label is the **realized outcome of the actual exit rule**, produced by the same trade simulator used in Phase 2, net of costs. Label = sign of realized R (or a documented threshold). This avoids the intrabar path ambiguity of "reached +1R before −1R": on M1 bars you do not know whether the high or the low printed first, and that noise corrupts every model downstream.
- If a triple-barrier proxy is used instead, define explicit tie-breaking, document the resulting bias, and keep the definition fixed across all experiments.
- Never build the label from information later than the documented decision/exit logic.

**Features (start small: 4-6, expand to at most ~10-15 only if justified)**
- Trend distance in ATR units (price vs moving average, normalized).
- RSI.
- Bollinger %B.
- Volume z-score (tick volume, normalized).
- Time of day and day of week (cyclical encoding).
- Spread (current spread relative to its typical level).
- Asian range size relative to ATR.
- Recent volatility regime (for example ATR percentile).
- All features must be normalized, stationary-ish, and computable in MQL5 with the same logic.

**Filters, in this order — each must beat the previous out-of-sample, after costs**
0. **Rules baseline (required first filter):** a small set of explainable skip rules derived from Phase 2 diagnostics (for example: skip if spread > X, skip if ATR percentile > 95, skip defined time windows). This is cheap, robust at small sample sizes, and the honest benchmark every model must beat.
1. Regularized logistic regression (readable, hard to overfit). It must beat the rules baseline, not just the unfiltered base.
2. Gradient boosting (LightGBM/XGBoost, shallow, heavily regularized), only if step 1 is not enough and the sample size supports it.
- **Export constraint:** prefer linear/coefficient export. ONNX is allowed only if boosting is genuinely required *and* the extra parity risk is accepted. Never choose a model you cannot faithfully reproduce in MQL5.

**Output:** a probability or score in [-1, 1] (or [0, 1]) per candidate.
- **Phase 3 use: binary take/skip with a threshold.**
- **The threshold is part of the model, not a free parameter.** It is chosen inside the training fold and applied unchanged to the test fold. Selecting the threshold on out-of-sample data is leakage.
- Score-driven position sizing is **deferred** until the binary filter is proven, then only allowed inside the risk layer's fixed caps.

**Validation protocol**
- Walk-forward (expanding or rolling) with **purged and embargoed** splits.
- Costs included in every evaluation.
- The final holdout is touched **once**, at the end, through the single holdout reader; the read is logged.
- Compare each filter to (a) the **rules baseline** and (b) the **unfiltered base**, on the **same trades and period**. Use a **paired** bootstrap on per-trade differences — the filtered set is a subset of the base trades, so the comparison is paired and far less noisy than two independent arms.
- "Beats baseline" means a **statistically meaningful, multiple-testing-corrected** improvement. Report confidence intervals on expectancy and Sharpe-like metrics, and apply a correction for the total number of trials (deflated Sharpe, White's Reality Check / SPA). Raw p-values from a search over many variants are not evidence.
- Threshold, features, and hyperparameters are chosen **inside** each training fold; the test fold is untouched.
- Check feature importance and stability across folds. Unstable importance suggests noise-fitting.
- For a binary take/skip decision, report **discrimination** (AUC, precision/recall at the chosen threshold) as well as **calibration**; calibration mainly matters if size is later driven by probability.
- Run a **shuffled-label sanity test**: with labels shuffled, the model must show no edge. If it does, there is leakage.

**Pre-registered criteria (fill in before running)**
- Minimum OOS trades after filtering: ______
- Required improvement in expectancy vs **rules baseline**: ______ R (and vs unfiltered base: ______ R), with paired CI excluding zero: yes / no
- Maximum acceptable drop in trade count from filtering: ______ %
- Required fold consistency (fraction of folds beating both baselines): ______
- Multiple-testing correction applied: yes / no (must be yes)

**Gate:** the chosen filter beats **both** the rules baseline and the unfiltered base out-of-sample, costs included, with a multiple-testing-corrected confidence interval, and passes the shuffled-label test. If ML cannot beat the rules, the rules are what ships. Otherwise the plain strategy (or a new base) is what we continue with.

**Deliverables:** `features/` module, `models/` with versioned artifacts and metadata (training window, features, parameters, metrics), `reports/phase3_ml.md`, updated Trial Log.

---

### Phase 4: Port to MT5

**Goal:** the EA computes exactly what Python computes.

**Tasks**
0. **Indicator conformance suite first:** compute ATR, RSI (Wilder vs simple/EMA seeding), Bollinger, and every moving average in both Python and MQL5 on a fixed golden dataset, and reconcile to tolerance *before* touching strategy logic. Parity bugs are cheapest to kill in isolation.
1. Export the model: coefficients and scaler parameters for linear models, or ONNX for boosting (only if the Phase 3 export constraint allowed it).
2. Re-implement the feature calculations in MQL5. Match definitions exactly (indicator smoothing method, period, bar indexing, which bar is "closed").
3. Build a **parity test**: export EA-computed features and signals on the same historical window, and compare to Python output row by row.
4. Embed the model version and feature spec in the EA so a mismatch is detectable.

**Common hidden bugs to check**
- Off-by-one bar (using the forming bar vs the last closed bar).
- Different indicator initialization or smoothing (Wilder vs simple/EMA).
- Timezone: server time vs UTC inside the EA.
- Normalization parameters differing from the training scaler.
- Floating-point or rounding differences in thresholds.
- Position sizing or price rounding disagreeing with the symbol's tick size, lot step, and stop level from `config/assets/<SYMBOL>.yaml`.

**Pre-registered criteria**
- Feature match tolerance: ______ (for example max abs diff < 1e-6 for normalized features)
- Signal match rate required: ______ % (target 100% on candidates, explain any difference)

**Gate:** EA signals match Python on the same data. Any mismatch is fixed before moving on.

**Deliverables:** EA with strategy and model integrated, parity report `reports/phase4_parity.md`.

---

### Phase 5: Strategy Tester and demo

**Goal:** confirm MT5 backtest behavior and real demo execution match expectations.

**Tasks**
1. Run MT5 Strategy Tester with **real ticks** (best available tick modeling) over the same period as the Python backtest. Compare trade lists and PnL.
2. Run on a **demo account (on a VPS)** for at least several weeks.
3. Log every trade: signal time, intended price, fill price, slippage, spread at entry, reason for skip.
4. Compare demo vs backtest: fills, slippage, spreads, rejected orders, latency.

**Important statistical caveat:** even with the broad candidate population, several weeks gives only tens to low hundreds of trades. **A demo period cannot prove an edge.** Its purpose is to test execution mechanics and catch bugs, not to validate profitability. Do not treat a good demo month as proof, and do not panic over a bad one either.

**Pre-registered criteria**
- Maximum allowed difference between Python and MT5 tester trade lists: ______
- Maximum average slippage vs modeled slippage: ______
- Minimum demo duration and trade count before review: ______ weeks / ______ trades
- Zero unexplained order errors or risk-layer violations.

**Gate:** demo behavior matches the backtest on mechanics (fills, slippage, spread), the risk layer behaves exactly as designed (daily cap triggers, spread filter blocks, size caps hold), and no unexplained discrepancies remain.

**Deliverables:** `reports/phase5_tester_vs_python.md`, demo trade journal, `reports/phase5_demo_review.md`.

---

### Phase 6: Robustness and kill criteria

**Goal:** make sure the result is not fragile, and define in advance when to stop.

**Robustness tests**
- Parameter sensitivity heatmaps (neighborhood stability).
- Monte Carlo on trade order and on bootstrapped trades (drawdown distribution, risk of ruin).
- Stressed costs: spread x1.5 to x2, higher slippage, missed fills.
- Regime splits: performance by year, by volatility regime, by trend vs range periods.
- Remove the top N best trades and check whether the edge survives.
- Data-source swap: re-run on independent data (for example Dukascopy) to confirm the result is not an artifact of the Exness feed.

**Kill criteria (define numerically before going further)**

**Note:** the project-level kill rule, the time budget, and the "two consecutive base strategies" rule are agreed **before Phase 2** (see Phase 2 criteria and Phase 1.5). This section fills in the strategy-specific numbers that only make sense once the strategy exists; it does not defer the decision to stop.

- Stop and reassess if demo/live-demo drawdown exceeds ______ %.
- Stop if rolling N-trade expectancy falls below ______ for ______ consecutive windows.
- Stop if execution costs exceed modeled costs by more than ______ %.
- Abandon the strategy if it fails Phase 6 robustness with no fix that is both simple and principled.
- Abandon the **project** (or pivot the base strategy) if two consecutive base strategies fail Phase 2 or Phase 3 gates.

**Gate:** the edge survives stress tests with acceptable degradation, and kill criteria are written and agreed.

**Deliverables:** `reports/phase6_robustness.md`, written kill criteria in this file.

---

### Phase 7: Self-learning loop

**Goal:** scheduled retraining that keeps the model current **without** adding instability.

**Prerequisite:** Phases 2 to 6 show a real, robust edge. If not, this phase is skipped or dropped. Automated retraining on small data tends to add noise.

**Design**
- Scheduled retraining (for example monthly or quarterly), not continuous.
- Retrain with the same walk-forward, purged validation used in Phase 3.
- **Promotion rule:** a candidate model replaces the current one only if it beats the current model out-of-sample, after costs, with confidence, over a defined recent window. Otherwise keep the current model.
- Versioning: every model stored with training window, features, metrics, and a rollback path.
- **The risk layer is untouchable, enforced technically.** The EA verifies a hash of `config/risk_global.yaml` at startup and refuses to run on mismatch. The retraining pipeline runs in a separate process/directory with read-only access to risk config and the MT5 experts directory, so it *cannot* write to them.
- Drift monitoring: feature distribution drift, score distribution drift, rolling expectancy, hit rate vs expectation. Alerts on decay.
- Human approval step before any new model goes onto the demo or live EA, at least initially.

**Pre-registered criteria**
- Retraining cadence: ______
- Promotion margin and confidence requirement: ______
- Drift alert thresholds: ______

**Gate:** over a historical simulation of the retraining process (simulate it in the past, honestly), auto-retraining is at least as good as a fixed model and is not noticeably more unstable.

**Deliverables:** `retraining/` pipeline, model registry, monitoring dashboard or report, `reports/phase7_retraining.md`.

---

### Phase 8: News and context layer

**Goal:** add outside context only where it demonstrably helps. Each piece is tested separately and stays only if it improves out-of-sample, after-cost results.

**Order (cheapest and safest first)**
1. **Economic-calendar filter:** skip or reduce trading in a window around high-impact events (for example NFP, CPI, FOMC). This mostly reduces tail risk and can be tested early, as a separate pre-registered trial alongside Phase 2 (never folded into the baseline).
2. **Market context features:** VIX, dollar index (DXY) or dollar proxy, real yields, Fear & Greed index (mainly relevant for crypto). Add as features to the Phase 3 model, one at a time, and test.
3. **LLM headline scoring in shadow mode:** the LLM scores news headlines, but the score is only logged, not traded. Evaluate after enough data whether the score has predictive value. Promote only if it adds value out-of-sample.

**Rules**
- Every external data source must be timestamped to when it was actually available (no look-ahead via revised or backfilled data).
- External dependencies must fail safe: if a feed is down, the system defaults to its conservative behavior (for example, skip trading around unknown events), never to "assume all clear."

**Gate (per component):** measurable out-of-sample improvement after costs, otherwise remove it.

**Deliverables:** `context/` modules, `reports/phase8_<component>.md` per component.

---

### Phase 9: Multi-asset expansion

**Goal:** extend the proven framework to other markets, one asset at a time, **without** assuming results transfer.

**Rule:** gold must fully pass Phases 1 to 6 first. Every new asset then goes through its own Phases 1 to 6. A new asset is a new hypothesis, not a copy-paste. Reuse the pipeline and risk layer, not the conclusions.

**Suggested order (adjust with the user)**
1. **Silver (XAGUSD):** closest to gold, highly correlated, shares session behavior but is more volatile with wider spreads. Good first transfer test.
2. **Oil (UKOIL/USOIL or broker equivalent):** different drivers (inventory data, OPEC, geopolitics). Check how the broker handles CFD contract rolls and weekend gaps.
3. **BTC (BTCUSD) and ETH (ETHUSD):** trade 24/7 (check broker weekend availability and spread behavior), very different volatility regime, no traditional session structure. The Asian-range breakout idea may not apply and a different base strategy may be needed.
4. Others (indices, FX majors) only after the above, if ever.

**Per-asset checklist (repeat for each)**
1. Pull symbol specs from MT5: contract size, tick size and value, min/max/step lot, margin, swap, trading hours, typical spread by hour.
2. Define session logic in UTC for that asset (or state that sessions do not apply).
3. Phase 1 data pipeline and validation.
4. Choose a base strategy suited to the asset's liquidity structure. Do not force the gold strategy onto it.
5. Phase 2 baseline with costs. Phase 3 ML filter. Phase 4 parity. Phase 5 tester and demo. Phase 6 robustness.
6. Per-asset risk parameters (position sizing based on that asset's ATR and tick value, spread cap, daily loss cap) set in config. Global account-level limits stay in force across all assets.

**Portfolio-level rules once more than one asset runs**
- **Global daily loss cap and max total exposure** across all assets, enforced by the risk layer.
- **Correlation awareness:** gold and silver move together, BTC and ETH move together. Treat correlated positions as partly the same bet when sizing and capping.
- Maximum number of simultaneous positions across the portfolio.
- Separate model per asset at first. Consider pooled or shared models only if per-asset data is too thin and pooling demonstrably helps out-of-sample.
- Portfolio-level monitoring: combined drawdown, per-asset contribution, correlation drift.

**Gate (per asset):** the asset passes its own Phases 1 to 6. If it fails, it is dropped or its base strategy is changed, and nothing else is affected.

**Deliverables:** `assets/<symbol>/` folder per asset with config, data, strategy, models, and reports.

---

## 6. Suggested project structure

```
project/
  PROJECT_MAP.md              <- this file
  AGENTS.md                   <- symlink/copy of PROJECT_MAP.md (auto-loaded each session)
  docs/runtime.md             <- where MT5 runs, build number, tick availability
  config/
    risk_global.yaml          <- fixed account-level limits (hash-checked; not writable by ML)
    assets/XAUUSD.yaml        <- per-asset params (symbol specs, session UTC, spread cap)
  data/
    raw/                      <- never overwritten
    clean/
    holdout/                  <- final holdout; only scripts/holdout_eval.py may read
  scripts/
    holdout_eval.py           <- single reader of data/holdout/
  data_pipeline/
  strategies/
  features/
  models/                     <- versioned artifacts + metadata
  retraining/                 <- Phase 7+ (read-only access to risk config)
  context/                    <- Phase 8+
  mt5/
    experts/                  <- EA source
    experts/risk/             <- isolated risk module with narrow interface + tests
    parity/                   <- parity test outputs
  reports/
  logs/
    trial_log.md
    decision_log.md
    holdout_access.log        <- append-only record of every holdout read
  assets/                     <- Phase 9 per-asset folders
```

---

## 7. Status Tracker (agent: keep this updated)

| Phase | Status | Gate passed? | Date | Notes |
|---|---|---|---|---|
| 0 Foundation | Done | Yes | | Risk layer written; signal logic placeholder; artifacts captured in repo (Phase 0b) |
| 0b Repo + walking skeleton | In progress | No | 2026-11-24 | Repo, structure and EA captured; risk-module refactor + demo skeleton pending |
| 1 Data | Not started | No | | Holdout split + DST mismatch test now mandatory |
| 1.5 Statistical power check | Not started | No | | Gates the ML layer; MDE vs required effect |
| 2 Base strategy | Not started | No | | Broad session-breakout candidate population decided |
| 3 ML meta-filter | Not started | No | | Rules baseline first; ML must beat it |
| 4 Port to MT5 | Not started | No | | Indicator conformance suite first |
| 5 Tester + demo | Not started | No | | |
| 6 Robustness + kill criteria | Not started | No | | Project-level kills/time budget moved before Phase 2 |
| 7 Self-learning loop | Not started | No | | |
| 8 News / context | Not started | No | | |
| 9 Multi-asset | Not started | No | | |

**Current phase:** 0b (Repo and walking skeleton)
**Next action:** on the Windows runtime, refactor the risk layer into `mt5/experts/risk/` with tests, then place one demo order through the skeleton and verify the structured log. Fill in `docs/runtime.md`.

---

## 8. Decision Log (agent: append new decisions)

| Date | Decision | Reason |
|---|---|---|
| | Platform: MT5 on Exness demo | Starting point |
| | Instrument: XAUUSD first | Liquid, session-structured, user preference |
| | ML used as meta-filter on a base strategy, not as the strategy | Smaller search space, less overfitting, explainable |
| | Models start linear/regularized | Small sample size per asset |
| | Risk layer is fixed and untouchable by ML | Safety |
| | Position sizing stays fixed/binary until the filter is proven | Noisy scores amplify errors |
| | Multi-asset expansion only after gold passes Phases 1 to 6 | Avoid scaling an unproven system |
| 2026-11-24 | Phase 2 candidate population is broad: London + NY breakouts plus retests; no one-trade/day cap | ~250 candidates/year leaves Phase 3 underpowered; broaden the learning signal |
| 2026-11-24 | A rules-based filter is the required first meta-filter; ML must beat it | Cheap, robust at small N, and matches "simple before complex" |
| 2026-11-24 | Added Phase 1.5 statistical power check as a gate before Phase 2 | Stop an underpowered ML experiment before it starts |
| 2026-11-24 | Holdout enforced mechanically (single reader + access log) | Phase 2 diagnostics would otherwise expose the holdout |
| 2026-11-24 | Label = realized outcome of the actual exit rule | Avoid intrabar path ambiguity of +1R/−1R on M1 bars |
| 2026-11-24 | Paired bootstrap + thresholds tuned in-fold + multiple-testing correction | Filtered set is a subset of base trades; threshold-on-OOS is the main leakage bug |
| 2026-11-24 | Added Phase 0b (repo + walking skeleton) before research | Phase 0 artifacts were not in the repo; prove plumbing cheaply first |
| 2026-11-24 | Project-level kill criteria and time budget agreed before Phase 2 | Avoid sunk-cost drift and post-hoc goalpost moves |
| 2026-11-24 | ONNX only if linear export fails and parity cost is accepted | ONNX in MT5 adds a large class of parity bugs |
| 2026-11-24 | Captured Phase 0 EA at `mt5/experts/GoldTrendPullbackEA.mq5`; fixed the `.mlq5` extension | MT5 requires `.mq5`; repo was otherwise empty |
| 2026-11-24 | The captured EA's trend-pullback signal is a placeholder; only the risk layer carries into Phase 2 | Phase 2 primary candidate is session breakout |

**Open decisions**
- Whether to also test the optional momentum candidate in Phase 2 (if yes, both count as trials).
- Pre-registered numeric thresholds for Phases 1, 1.5, 2 and 3 (to be set with the user before running).
- Where MT5 actually runs (Windows VM vs VPS) and which MT5 build to pin.

---

## 9. Trial Log (agent: append every strategy, parameter set, feature set, or model tried)

| # | Date | Phase | What was tried | Result summary | Notes |
|---|---|---|---|---|---|
| | | | | | |

The total number of trials is part of every report. More trials mean more skepticism about the best result.

**Commit each trial row *before* running it.** A trial is any strategy variant, parameter set, feature set, threshold, filter, data source, or model tried. Reported significance must apply a multiple-testing correction (deflated Sharpe / SPA) that accounts for the total count.

---

## 10. How the agent should behave

1. **Start every session** by reading this file, then stating the current phase, last gate result, and the next action.
2. **Do not skip ahead.** If the user asks for something from a later phase (for example news or a new asset), note which gate is still open and ask whether to proceed or finish the gate first.
3. **Ask for pre-registered criteria** before running any gate test. Do not run a test with thresholds undefined.
4. **Report honestly.** Show costs, trade counts, confidence intervals, and failures. Flag anything suspiciously good, and look for leakage first.
5. **Never touch the risk layer or the demo lock** without explicit user instruction, and warn about the consequences.
6. **Never move toward live trading.** Moving from demo to live is a separate, explicit decision by the user, only after consistent, well-understood results, and is out of scope for this document.
7. **Keep deliverables reproducible:** fixed random seeds, versioned data and models, scripts instead of manual steps.
8. **Update the Status Tracker, Decision Log, and Trial Log** at the end of each working session.
9. **Remember the limits:** no result is a promise of profit, nothing here is financial advice, and "no edge found" is an acceptable outcome.
10. **State the power before the test.** For any gate, say what effect the available sample can detect; refuse to run an underpowered test and call it evidence.
11. **Never read the holdout outside `scripts/holdout_eval.py`.** Any holdout read goes into `logs/holdout_access.log`; if you want to "sanity check" against it, stop.
12. **Commit the trial row before running it**, and apply a multiple-testing correction when reporting significance.
13. **Prefer rules to models.** If a simple rule matches the ML filter out-of-sample, ship the rule.

---

## 11. Glossary

- **EA:** Expert Advisor, an automated trading program in MT5.
- **ATR:** Average True Range, a volatility measure used for normalization.
- **R:** risk unit; 1R is the amount risked on a trade (distance to the stop).
- **Expectancy:** average net result per trade, in R or currency, after costs.
- **Meta-filter:** a model that decides whether to take a signal generated by another strategy.
- **Walk-forward:** repeated train-then-test on later data, mimicking real-time use.
- **Purging / embargo:** removing training samples whose labels overlap the test period, and leaving a gap after it, to prevent leakage.
- **Final holdout:** data set aside and evaluated once, at the end.
- **Parity test:** verifying two implementations (Python and MQL5) produce identical outputs.
- **Shadow mode:** running a component and logging its output without letting it affect trades.
- **Kill criteria:** pre-agreed conditions under which we stop or abandon a strategy or the project.
- **Power / MDE:** the minimum detectable effect — the smallest improvement a given sample and test can distinguish from noise. Power must be checked before the experiment, not after.
- **Rules baseline:** a small set of explainable skip rules used as the first meta-filter; any model must beat it out-of-sample.
- **Paired bootstrap:** resampling per-trade differences on the *same* trades, used to compare a filter against its base without the noise of two independent samples.
- **Deflated Sharpe / SPA (Reality Check):** significance adjustments for the number of trials tried; raw p-values from a search are not evidence.
- **Walking skeleton:** a minimal end-to-end path (data → signal → order → log) built early to prove the plumbing before deep research.
- **Holdout lockbox:** held-out data in a separate location with a single reader and an append-only access log, so the holdout cannot be seen by accident.
