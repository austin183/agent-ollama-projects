# Change Request: analyzing-opencode-usage — Bug Fixes and Token Efficiency Metrics

**Date:** 2026-08-01
**Status:** Draft — awaiting discussion
**Triggered by:** CollageMaker LLM usage report review (2026-08-01)

---

## Goal

Make the `analyzing-opencode-usage` skill bug-free and focused on answering real questions about token usage efficiency. The tool should reliably answer:

1. How many tokens did each agent use from each LLM per day? How do those numbers change over the project's life?
2. What is our approximate cost per day?
3. How many tokens are used to progress the project vs. fix bugs or regressions?
4. What are our token ratios for tests, lines added, and features?
5. What else can we infer from the data to measure token efficiency?

---

## Part A: Bug Fixes

### Critical — Produces Wrong Data

| # | Bug | File(s) | Impact |
|---|-----|---------|--------|
| **B1** | `_resolve_date()` returns string `'None'` | `queries/utils.py:36`, `generate_report.py:42` | `str(None)` produces `'None'` used as SQL parameter. Works by accident (ASCII `'N'` > `'9'`) but is fragile. Could break with different collations or future SQLite versions. Affects ALL date-filtered queries. |
| **B2** | `productive_sessions` > `total_build_sessions` | `aggregator/merge.py:89` | Counts ALL sessions on commit dates (295), not just build sessions (286). A subset cannot exceed its superset. Corrupts build productivity metrics. |
| **B3** | Cost calculation inconsistency | `aggregator/merge.py:117-128` | `cost_summary` uses flat rates ($361) while `model_pricing` uses per-model rates ($371). $10 discrepancy with no explanation. Destroys trust in cost estimates. |
| **B4** | Hardcoded phase dates produce empty phases | `aggregator/merge.py:457-462` | May-June 2026 date ranges produce all-zero phases for any report outside that window. Broken for all current/future reports. |
| **B5** | Zero-token sessions inflate counts | `queries/summary.py` (and others) | 2 sessions with 0 tokens inflate session counts and skew averages (tokens/session, tokens/agent). |

### Important — Edge Cases or Maintenance Risks

| # | Bug | File(s) | Impact |
|---|-----|---------|--------|
| **B6** | Model pricing fallback for custom models | `model_pricing.py` | `agents-a1` (86M tokens) and `big-pickle` use generic $0.50/$1.50 rates instead of explicit pricing. Cost estimates for these models are unreliable. |
| **B7** | Massive SQL duplication in cache_estimate.py | `queries/cache_estimate.py` | Same 4-level CTE repeated 5 times (~200 lines). High risk of divergence if one copy is updated and others aren't. |
| **B8** | `daily_agent_stacked` shares object with `timeseries` | `aggregator/merge.py:143` | In-place mutation of one reference corrupts the other. |
| **B9** | Dead SQL computation | `queries/productivity.py:39-40` | `summary_files > 0` always returns 0. Wastes compute and indicates obsolete logic. |
| **B10** | Duplicate `resolve_date()` function | `queries/utils.py` + `generate_report.py` | Identical function in two places. Fixes to one won't propagate. |

### Documentation

| # | Issue | File(s) | Impact |
|---|-------|---------|--------|
| **B11** | Missing `references/` directory | `.opencode/skills/analyzing-opencode-usage/` | SKILL.md references `session-summary.json` and `activity-template.md` that don't exist. |
| **B12** | SKILL.md cost example is wrong | `SKILL.md:193-194` | Documented output ($0.80/$0.79) doesn't match actual rates. |

---

## Part B: New Metrics and Queries

### Q1: Per-Agent, Per-Model, Per-Day Token Usage

**Question:** How many tokens did each agent use from each LLM per day? How do those numbers change over the life of the project?

**Current state:**
- `timeseries` has per-day data by agent *category* (build/review/plan/explore/other) — not individual agents
- `cross_tab` has model × agent totals — not per-day
- No 3D breakdown exists

**Required work:**
- New query: `model_agent_daily.py` — groups by `(date, model, agent)` with input/output/reasoning tokens
- New query: `model_agent_daily_cache.py` — cache-adjusted version using per-message data
- Add `model_agent_daily` section to merged report JSON
- HTML renderer: stacked area chart or heatmap showing model × agent × day

**Data available:** Yes — session table has `model`, `agent`, `time_created`, and token columns.

---

### Q2: Approximate Cost Per Day

**Question:** What is our approximate cost per day?

**Current state:**
- `timeseries` has `daily_cost_cheap` and `daily_cost_expensive` using flat rates
- No per-model daily cost breakdown
- Two cost methods (flat vs per-model) produce inconsistent totals

**Required work:**
- **Prerequisite:** Fix B3 (cost inconsistency) and B6 (model pricing fallback)
- New query: `daily_cost.py` — joins daily token usage by model with per-model pricing
- Add `daily_cost` section to merged report with per-model breakdown
- Unify cost calculation: single source of truth using per-model rates
- HTML renderer: daily cost bar chart with per-model stacking

**Data available:** Yes — daily token counts by model + pricing table.

---

### Q3: Progress vs. Bug-Fixing Tokens

**Question:** How many tokens are used to progress the project vs. fix bugs or regressions?

**Current state:**
- NO data for this. No "purpose" field on sessions.
- Agent names hint at purpose (`build-debug`, `build-test`) but don't distinguish "new feature" from "bug fix"
- Session titles exist but aren't categorized

**Proposed approach:**
- Parse git commit messages for conventional commit prefixes: `fix:` → bug-fixing, `feat:` → progress, `refactor:` → maintenance, `test:` → testing, `docs:` → documentation
- Attribute session tokens to commit categories by matching session dates to commit dates
- For sessions on days with mixed commit types, split tokens proportionally

**Required work:**
- New query: `commit_categories.py` — parses commit messages for conventional commit prefixes
- New aggregation: map session tokens to commit categories
- Add `work_type_breakdown` section to report

**Limitations:**
- Only works for sessions on commit dates (~58% of sessions)
- Non-conventional commit messages won't be categorized
- Sessions with multiple purposes on the same day can't be precisely attributed

**Open question:** Should we add a `purpose_tag` field to session summaries for explicit categorization?

---

### Q4: Token Ratios for Tests, Lines Added, Features

**Question:** What are our token ratios for tests, lines added, features?

**Current state:**
- `timeseries` has `test_ratio` (test adds / total adds %), `tok_per_commit`, `tok_per_line`
- No way to separate "feature" tokens from "test" tokens or "refactor" tokens at the session level

**Proposed approach:**
- Link sessions to specific git commits via date matching
- If a session's git diff shows mostly `test/` directory changes → "test tokens"
- If it shows `src/` changes → "feature tokens"
- Compute `tokens_per_test_line`, `tokens_per_feature_line`, `tokens_per_refactor_line`

**Required work:**
- New query: `file_change_categories.py` — categorizes git changes by directory/path patterns
- New aggregation: map session tokens to file change categories
- Add `token_ratios` section to report

**Limitations:**
- Requires per-commit file change data (available via `git log --name-only`)
- Can't distinguish "feature" from "refactor" without commit message parsing (see Q3)

---

### Q5: Novel Efficiency Metrics

**Question:** What else can we infer from the data to measure token efficiency?

**Proposed metrics (all derivable from existing data):**

| Metric | Formula | Insight |
|--------|---------|---------|
| **Context-to-Output Ratio** | `input_tokens / output_tokens` per session/day | High ratio = context bloat (LLM fed excessive context, generates little code) |
| **Zero-Change Session Rate** | `sessions_with_0_commits / total_sessions` | Wasted tokens — exploration loops, failed debugging, reasoning loops |
| **Cache Efficiency Trend** | `cache_hit_pct` over time | Rising rate with stable tokens = improving prompt efficiency |
| **Token Density** | `total_effective_tokens / (adds + dels)` | Normalized measure of tokens per line of code changed |
| **Agent Overlap** | Sessions where multiple agents run on same day | Potential redundancy — are agents doing overlapping work? |
| **Session Complexity** | `turns_per_session` from message table | Longer sessions may indicate harder problems or inefficient agent behavior |
| **Refinement Loops** | Multiple turns modifying same file before commit | Tokens spent tweaking code before finalization |

**Required work:**
- New query: `session_complexity.py` — turns per session from message table
- New aggregation: compute all novel metrics in `merge.py`
- Add `efficiency_metrics` section to report
- HTML renderer: efficiency dashboard with trend charts

---

## Part C: Refactoring

### R1: Consolidate `_resolve_date()`
- **Files:** `queries/utils.py`, `generate_report.py`
- **Action:** Remove duplicate from `generate_report.py`, import from `queries.utils`
- **Fix:** Default `until` to `date.today().isoformat()` when `None`

### R2: Extract shared CTE in `cache_estimate.py`
- **File:** `queries/cache_estimate.py`
- **Action:** Extract `collages → msg_tokens → with_prev → per_turn` CTE chain into a shared base query or SQL view. Each function adds its own `SELECT ... GROUP BY` on top.
- **Benefit:** ~200 lines of duplication reduced to ~40 lines of shared logic + 5 thin wrappers

### R3: Deep copy `daily_agent_stacked`
- **File:** `aggregator/merge.py:143`
- **Action:** `'daily_agent_stacked': list(merged_daily)` or `merged_daily.copy()`

### R4: Remove dead `summary_files` query
- **File:** `queries/productivity.py`
- **Action:** Remove `SUM(CASE WHEN summary_files > 0 THEN 1 ELSE 0 END)` — always 0

### R5: Make phases configurable
- **File:** `aggregator/merge.py:457-462`
- **Action:** Accept phases from `--phases-file` CLI argument or skip section if no phases configured. Remove hardcoded dates.

---

## Part D: Implementation Phases

### Phase 1: Bug Fixes (Prerequisites)
- B1: Fix `_resolve_date()` — `str(None)` → `date.today().isoformat()`
- B2: Fix `productive_sessions` counting
- B3: Unify cost calculation to per-model rates
- B4: Remove or make phases configurable
- B5: Exclude zero-token sessions from counts
- B6: Add explicit pricing for custom models
- R1-R4: Refactoring tasks

### Phase 2: Core New Metrics
- Q1: Model × Agent × Day breakdown
- Q2: Per-model daily cost
- Q5: Novel efficiency metrics (context-to-output ratio, zero-change rate, etc.)

### Phase 3: Advanced Attribution
- Q3: Progress vs bug-fixing tokens (commit message parsing)
- Q4: Token ratios by file change category
- R5: Phases configuration

### Phase 4: Report Enhancements
- HTML renderer updates for new sections
- Dashboard layout with efficiency metrics
- SKILL.md documentation updates

---

## Open Questions for Discussion

1. **Session purpose tagging:** Should we add a `purpose_tag` field to session summaries? This would require agents to self-report their work type (feature/bugfix/refactor/test/docs) in their session summaries. More accurate than commit message parsing but requires behavior change.

2. **Per-commit session attribution:** Currently we match sessions to commits by date. Should we try harder to link specific sessions to specific commits? The opencode DB doesn't store commit SHAs per session, but we could infer from timing proximity.

3. **Custom model pricing:** Who maintains the pricing table for custom models like `agents-a1`? Should pricing be configurable per-project?

4. **Report scope across paths:** CollageMaker has sessions under 3 different directory paths. Should the tool support path aliases or a "project name" concept that maps to multiple paths?

5. **Novel metrics priority:** Which of the 7 proposed efficiency metrics (context-to-output ratio, zero-change rate, cache efficiency trend, token density, agent overlap, session complexity, refinement loops) should we implement first?

6. **Cost display:** Should the report show a single cost number (per-model rates) or keep the cheap/expensive tier comparison? The tier comparison is useful for understanding model mix impact but creates confusion.

---

## Files Affected

| File | Changes |
|------|---------|
| `queries/utils.py` | Fix `_resolve_date()`, consolidate with `generate_report.py` |
| `queries/cache_estimate.py` | Extract shared CTE |
| `queries/summary.py` | Exclude zero-token sessions |
| `queries/productivity.py` | Remove dead `summary_files` query |
| `queries/daily_tokens.py` | May need per-model breakdown |
| `aggregator/merge.py` | Fix `productive_sessions`, unify cost, add new metrics, deep copy |
| `model_pricing.py` | Add custom model pricing, fix fallback documentation |
| `generate_report.py` | Remove duplicate `resolve_date()`, add CLI args for new features |
| `render_consolidated_report.py` | Add new chart sections |
| `SKILL.md` | Update documentation, fix examples, document new features |
| `references/session-summary.json` | Already created |
| New: `queries/model_agent_daily.py` | Model × Agent × Day query |
| New: `queries/daily_cost.py` | Per-model daily cost |
| New: `queries/session_complexity.py` | Turns per session |
| New: `queries/commit_categories.py` | Commit message parsing |
