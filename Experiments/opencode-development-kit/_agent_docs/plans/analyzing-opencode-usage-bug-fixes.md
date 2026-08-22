# analyzing-opencode-usage Bug Fixes Implementation Plan

## Overview

Fix 12 verified bugs in the `analyzing-opencode-usage` skill that produce incorrect data, waste compute, or mislead users. The bugs span date resolution, session counting, cost calculations, hardcoded phase dates, shared mutable state, dead code, SQL duplication, and documentation gaps.

**Spec:** `_agent_docs/specifications/analyzing-opencode-usage-improvements.md`

## Current State Analysis

The skill consists of a Python report generator (`generate_report.py`) that orchestrates 12+ query modules, merges results via `aggregator/merge.py`, and renders HTML. All query modules share `_resolve_date()` from `queries/utils.py` to compute date ranges. The system has 5 critical bugs that corrupt report data, 5 important bugs that cause silent issues or waste compute, and 2 documentation gaps.

### Key Discoveries

- **`queries/utils.py:36`** — `str(None)` produces the literal string `'None'` when only one of `since`/`until` is provided. Works by accident (SQLite ASCII comparison `'N'` > `'9'`) but is fragile.
- **`generate_report.py:21-42`** — Exact duplicate of `_resolve_date()` with the same `str(None)` bug. Also called redundantly: `main()` resolves dates at line 129, then `fetch_all_datasets()` resolves them again at line 62 with `days=args.days` still set, potentially overriding already-resolved dates.
- **`aggregator/merge.py:85-86`** — `productive_build_sessions` sums `r.get('sessions', 0)` for ALL sessions on commit dates, not just build-category sessions. The `sessions` field in `merged_daily` is total sessions, not build sessions.
- **`aggregator/merge.py:117-128`** — `cost_summary` uses `flat_totals` (flat-rate tiers) while `model_pricing` uses `compute_total_cost` (per-model rates). The two methods produce different totals ($361 vs $371 in the CollageMaker report) with no explanation.
- **`aggregator/merge.py:120-121`** — `cost_summary` omits `reasoning_tokens` entirely, silently excluding reasoning token costs from the cost summary display.
- **`aggregator/merge.py:143`** — `daily_agent_stacked` and `timeseries` share the same list reference. The comment claims this is "intentional" but any downstream mutation corrupts both.
- **`aggregator/merge.py:457-462`** — Phase dates hardcoded to May-June 2026. Any report outside this window produces all-zero phases.
- **`queries/summary.py:39`** — `COUNT(*)` includes zero-token sessions, inflating session counts and skewing averages.
- **`queries/cache_estimate.py`** — Identical 4-level CTE chain (`collages → msg_tokens → with_prev → per_turn`) repeated verbatim 5 times across `fetch_aggregate`, `fetch_by_model`, `fetch_by_agent`, `fetch_by_day`, and `fetch_sessions`. ~200 lines of duplicated SQL.
- **`queries/productivity.py:39-40`** — `SUM(CASE WHEN summary_files > 0 ...)` always returns 0 since `summary_files` is never populated. Results are overwritten in `merge.py:78-79`.
- **`model_pricing.py:57`** — Unknown models silently fall back to qwen/qwen3.6-27b rates ($0.50/$1.50) with no logging or reporting.
- **`references/activity-template.md`** — Referenced by SKILL.md but does not exist.
- **`SKILL.md:193-194`** — Cost example shows `$0.80/$0.79` which doesn't match actual rates for the example values.

## Desired End State

After this plan is complete:

1. **All date-filtered queries** use a single, correct `_resolve_date()` that never returns `'None'`
2. **Session counts** exclude zero-token sessions from `total_sessions`
3. **Build productivity** correctly counts only build-category sessions on commit dates
4. **Cost calculations** use a single source of truth (per-model rates) with reasoning tokens included
5. **Phase breakdown** returns empty list when no phases are configured, instead of all-zero hardcoded phases
6. **`daily_agent_stacked`** is an independent copy, immune to mutation of `timeseries`
7. **`cache_estimate.py`** has a single shared CTE builder function
8. **`productivity.py`** no longer runs dead SQL for `summary_files`
9. **Model pricing** logs a warning when fallback pricing is used and reports unknown models
10. **Documentation** references exist and examples are accurate

## What We're NOT Doing

- **Part B new metrics (Q1-Q5)** — per-agent/per-model daily breakdowns, cost-per-day, progress-vs-bugfix attribution, token ratios, and novel efficiency metrics are feature additions, not bug fixes
- **HTML renderer changes** — only fixing data pipeline bugs; chart rendering is out of scope
- **Schema changes** — no modifications to the opencode SQLite database
- **`fetch_sessions` in cache_estimate.py** — this function exists but is never called by `generate_report.py`; we still deduplicate its CTE but don't wire it into the report pipeline
- **Adding `purpose_tag` to session summaries** — this is an open question from the spec, deferred to a future plan

## Implementation Approach

Three phases, ordered by impact on data correctness:

1. **Phase 1 (P0):** Fix bugs that produce wrong numbers in reports — date resolution, session counting, cost calculations, build productivity
2. **Phase 2 (P1):** Fix structural correctness issues — shared mutable state, dead code, hardcoded phases, model pricing fallback
3. **Phase 3 (P2):** Maintainability and documentation — SQL deduplication, missing references, wrong examples

---

## Phase 1: Critical Data Correctness

### Overview

Fix 5 bugs that directly produce incorrect numbers in generated reports. These are the highest-priority items because they undermine trust in all report data.

### Behavior Specifications

#### B1/B10/R1: `_resolve_date()` returns `'None'` string + duplicate function

**Component Behavior — `_resolve_date()`:**

| # | Given | When | Then |
|---|-------|------|------|
| 1.1.1.1 | `since='2026-08-01'`, `until=None`, `days=None` | `_resolve_date()` is called | Returns `('2026-08-01', <today>)` — `until` defaults to today |
| 1.1.1.2 | `since=None`, `until='2026-08-01'`, `days=None` | `_resolve_date()` is called | Returns `('2000-01-01', '2026-08-01')` — `since` defaults to epoch |
| 1.1.1.3 | `since='2026-08-01'`, `until='2026-08-07'`, `days=None` | `_resolve_date()` is called | Returns `('2026-08-01', '2026-08-07')` — both values preserved |
| 1.1.1.4 | `since=None`, `until=None`, `days=7` | `_resolve_date()` is called | Returns `(<today-7>, <today>)` — `days` overrides both |
| 1.1.1.5 | `since=None`, `until=None`, `days=None` | `_resolve_date()` is called | Returns `('2000-01-01', <today>)` — both default |
| 1.1.1.6 | Return value is `(str, str)` | — | Neither element is the string `'None'` |

**User Behavior:**

| # | Given | When | Then |
|---|-------|------|------|
| 1.1.2.1 | User runs `generate_report.py --since 2026-08-01` (no `--until`) | Report is generated | Report includes data from 2026-08-01 through today, not empty or erroring |
| 1.1.2.2 | User runs `generate_report.py --until 2026-08-07` (no `--since`) | Report is generated | Report includes data from project start through 2026-08-07 |

**Changes Required:**

#### 1. Fix `queries/utils.py:_resolve_date()`

**File:** `.opencode/skills/analyzing-opencode-usage/script/queries/utils.py`
**Changes:** Add fallback logic when only one of `since`/`until` is provided. Remove unnecessary `str()` calls.

```python
def _resolve_date(
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None
) -> Tuple[str, str]:
    """Resolve date range from arguments or defaults."""
    if days is not None:
        start_date = (date.today() - timedelta(days=days)).isoformat()
        end_date = date.today().isoformat()
    else:
        start_date = since if since else "2000-01-01"
        end_date = until if until else date.today().isoformat()

    return start_date, end_date
```

#### 2. Remove duplicate from `generate_report.py`

**File:** `.opencode/skills/analyzing-opencode-usage/script/generate_report.py`
**Changes:** Delete lines 11 (`from datetime import date, timedelta`) and lines 21-42 (the `resolve_date` function). Add import at line 19:

```python
from queries.utils import _resolve_date
```

Update all call sites in `generate_report.py` to use `_resolve_date` instead of `resolve_date`:
- Line 62: `start_date, end_date = _resolve_date(since, until, days)`
- Line 129: `start_date, end_date = _resolve_date(args.since, args.until, args.days)`

Fix the redundant double-call: `fetch_all_datasets()` receives already-resolved dates from `main()` at lines 135-139, but also receives `days=args.days`. Since `fetch_all_datasets` calls `_resolve_date(since, until, days)` internally, passing `days=args.days` will trigger the `days` branch and override the resolved dates. Fix by passing `days=None` from `main()`:

```python
data = fetch_all_datasets(
    project_path=args.project,
    since=start_date,
    until=end_date,
    days=None,  # Already resolved in main(); prevent double-resolution
)
```

---

#### B5: Zero-token sessions inflate counts

**Pure Function Behavior — SQL query:**

| # | Given | When | Then |
|---|-------|------|------|
| 1.2.1.1 | DB has 100 sessions, 2 with all-token columns = 0 | `summary.fetch()` runs | `total_sessions` returns 98 |
| 1.2.1.2 | DB has 100 sessions, 2 with all-token columns = 0 | `summary.fetch()` runs | `total_tokens_raw` is unchanged (zero-token sessions contribute 0) |

**User Behavior:**

| # | Given | When | Then |
|---|-------|------|------|
| 1.2.2.1 | Report includes 2 zero-token sessions among 300 total | User reads summary cards | Session count shows 298, not 300 |
| 1.2.2.2 | Productivity % = sessions_with_changes / total_sessions | Zero-token sessions excluded from total | Productivity % is not artificially deflated |

**Changes Required:**

#### 3. Filter zero-token sessions in `queries/summary.py`

**File:** `.opencode/skills/analyzing-opencode-usage/script/queries/summary.py`
**Changes:** Add filter to the SQL WHERE clause at line 51:

```sql
    WHERE {where}
        AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= ?
        AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= ?
        AND (tokens_input + tokens_output + tokens_reasoning) > 0
```

Also apply the same filter to `queries/productivity.py` lines 42-44 (both the main query and the `sql_daily` sub-query at lines 68-70) since productivity counts should also exclude zero-token sessions.

---

#### B2: `productive_sessions` counts all sessions, not build sessions

**Component Behavior — `merge.py` build productivity:**

| # | Given | When | Then |
|---|-------|------|------|
| 1.3.1.1 | `merged_daily` row has `sessions=5`, `build_tok=1000` on a commit date | `productive_build_sessions` is computed | Only build-category sessions are counted, not all 5 |
| 1.3.1.2 | `productive_build_sessions` is in output | — | Value is <= `total_build_sessions` (subset cannot exceed superset) |

**Changes Required:**

#### 4. Fix build session counting in `aggregator/merge.py`

**File:** `.opencode/skills/analyzing-opencode-usage/script/aggregator/merge.py`
**Changes:** The `merged_daily` rows don't have a per-category session count — only total `sessions`. We need to add per-category session counts to the daily token data. The simplest fix: use the `agents_detailed` data to compute a per-day, per-category session breakdown, or approximate by using the token ratio.

The cleanest approach: add a per-category session count query. But since `daily_tokens.py` already groups by agent category, we can add session counts per category there. Alternatively, we can approximate: on each day, the fraction of build tokens relative to total tokens approximates the fraction of build sessions.

**Recommended approach:** Modify `queries/daily_tokens.py` to return per-category session counts. Add `build_sessions`, `review_sessions`, etc. columns to the GROUP BY query. Then in `merge.py:85-86`, use `r.get('build_sessions', 0)` instead of `r.get('sessions', 0)`.

If modifying `daily_tokens.py` is too invasive, use the token-ratio approximation in `merge.py`:

```python
productive_build_sessions = sum(
    round(r.get('sessions', 0) * r.get('build_tok', 0) / max(r.get('total_effective', 1), 1))
    for r in merged_daily
    if r.get('date', '') in git_dates_with_commits
)
```

This approximates build sessions as the build-token fraction of total sessions per day.

---

#### B3: Cost calculation inconsistency + missing reasoning tokens

**Component Behavior — cost summary:**

| # | Given | When | Then |
|---|-------|------|------|
| 1.4.1.1 | Report has models with reasoning tokens | `cost_summary` is built | `reasoning_tokens` field is present in `cost_summary` |
| 1.4.1.2 | `cost_summary` and `model_pricing` both report costs | — | Both use per-model rates as the primary cost source |
| 1.4.1.3 | Flat-rate costs still needed for chart display | — | Flat-rate costs are labeled as "estimates" and per-model costs are labeled as "primary" |

**Changes Required:**

#### 5. Unify cost calculation in `aggregator/merge.py`

**File:** `.opencode/skills/analyzing-opencode-usage/script/aggregator/merge.py`
**Changes:**

(a) Add `reasoning_tokens` to `cost_summary` at line 122:
```python
'cost_summary': {
    'total_cheap': flat_totals['cheap_raw'],
    'total_expensive': flat_totals['expensive_raw'],
    'total_per_model': pricing_totals['total_raw_cost'],
    'input_tokens': summary.get('total_input_raw', 0),
    'output_tokens': summary.get('total_output', 0),
    'reasoning_tokens': summary.get('total_reasoning', 0),
},
```

(b) Add `total_per_model` (from `pricing_totals['total_raw_cost']`) as the primary cost figure. Keep flat-rate totals for backward compatibility but clearly label them as tier estimates.

(c) Update `cache_cost_summary` similarly to include a per-model cache-adjusted total.

---

### Success Criteria:

#### Automated Verification:
- [ ] `_resolve_date('2026-08-01', None, None)` returns `('2026-08-01', <today>)` not `('2026-08-01', 'None')`
- [ ] `_resolve_date(None, '2026-08-07', None)` returns `('2000-01-01', '2026-08-07')`
- [ ] `generate_report.py` has no `resolve_date` function defined locally
- [ ] `generate_report.py` imports `_resolve_date` from `queries.utils`
- [ ] `generate_report.py` passes `days=None` to `fetch_all_datasets`
- [ ] `queries/summary.py` SQL includes `(tokens_input + tokens_output + tokens_reasoning) > 0`
- [ ] `queries/productivity.py` SQL includes the same zero-token filter
- [ ] `cost_summary` in merged output contains `reasoning_tokens` key
- [ ] `cost_summary` in merged output contains `total_per_model` key
- [ ] `productive_build_sessions` <= total build sessions in any report

#### Manual Verification:
- [ ] Run `generate_report.py --since 2026-08-01` (no --until) — report generates without error
- [ ] Run `generate_report.py --until 2026-08-07` (no --since) — report includes data from project start
- [ ] Open generated report JSON — `cost_summary.reasoning_tokens` matches `summary.total_reasoning`
- [ ] Open generated report JSON — `build_productivity[0].productive_sessions` <= total build sessions
- [ ] Session count in report matches `COUNT(*) WHERE tokens > 0` from DB

---

## Phase 2: Structural Correctness

### Overview

Fix 4 bugs that cause silent data corruption, wasted compute, or broken features for non-default date ranges.

### Behavior Specifications

#### B8: `daily_agent_stacked` shares mutable reference with `timeseries`

**Component Behavior:**

| # | Given | When | Then |
|---|-------|------|------|
| 2.1.1.1 | `merge_datasets()` returns output dict | `output['timeseries'].sort()` is called | `output['daily_agent_stacked']` is NOT affected |
| 2.1.1.2 | `merge_datasets()` returns output dict | `output['daily_agent_stacked'].append({...})` is called | `output['timeseries']` length is unchanged |

**Changes Required:**

#### 6. Deep copy `daily_agent_stacked` in `aggregator/merge.py`

**File:** `.opencode/skills/analyzing-opencode-usage/script/aggregator/merge.py`
**Changes:** Line 143 — replace shared reference with a shallow copy:

```python
'timeseries': merged_daily,
'daily_agent_stacked': list(merged_daily),  # Independent copy to prevent mutation bleed
```

Remove the misleading comment on lines 140-142.

---

#### B9: Dead `summary_files` query in `productivity.py`

**Component Behavior:**

| # | Given | When | Then |
|---|-------|------|------|
| 2.2.1.1 | `productivity.fetch()` is called | Query executes | SQL does NOT reference `summary_files` column |
| 2.2.1.2 | `productivity.fetch()` returns result | — | Result contains `total_sessions` and `daily_sessions` keys |

**Changes Required:**

#### 7. Remove dead SQL in `queries/productivity.py`

**File:** `.opencode/skills/analyzing-opencode-usage/script/queries/productivity.py`
**Changes:** Simplify the first SQL query (lines 36-45) to only select `total_sessions`:

```python
sql = f"""
SELECT COUNT(*) as total_sessions
FROM session
WHERE {where}
    AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= ?
    AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= ?
    AND (tokens_input + tokens_output + tokens_reasoning) > 0
"""
```

Remove `sessions_with_changes` and `pct_with_changes` from the return dict at lines 77-80 since they are always overwritten in `merge.py`. The return dict should be:

```python
return {
    'total_sessions': total_sessions,
    'daily_sessions': daily_sessions,
}
```

Also add the zero-token filter (from B5) to the `sql_daily` sub-query.

---

#### B4/R5: Hardcoded phase dates produce empty phases

**User Behavior:**

| # | Given | When | Then |
|---|-------|------|------|
| 2.3.2.1 | Report date range is July-August 2026 | `_build_phases()` runs | Returns `[]` (empty list) — no misleading all-zero phases |
| 2.3.2.2 | Report date range is May-June 2026 (matching hardcoded dates) | `_build_phases()` runs | Still returns `[]` — hardcoded phases are removed entirely |

**Changes Required:**

#### 8. Remove hardcoded phases from `aggregator/merge.py`

**File:** `.opencode/skills/analyzing-opencode-usage/script/aggregator/merge.py`
**Changes:** Replace `_build_phases()` (lines 455-475) with a no-op that returns an empty list. The function signature stays for API compatibility:

```python
def _build_phases(merged_daily: list[dict]) -> list[dict]:
    """Build phase breakdowns.

    Returns empty list. Phase definitions are project-specific and should be
    configured externally via a phases file. Hardcoded dates were removed as
    they produced all-zero results for any report outside the original window.
    """
    return []
```

This is the safest approach. Making phases configurable via CLI (R5 in the spec) is a feature addition deferred to a future plan.

---

#### B6: Model pricing fallback for custom models

**Component Behavior:**

| # | Given | When | Then |
|---|-------|------|------|
| 2.4.1.1 | `model_id='agents-a1'` (not in `MODEL_PRICING`) | `get_pricing(model_id)` is called | Returns fallback rates AND logs a warning |
| 2.4.1.2 | `model_id='big-pickle'` (not in `MODEL_PRICING`) | `get_pricing(model_id)` is called | Returns fallback rates AND logs a warning |
| 2.4.1.3 | `model_id='qwen/qwen3.6-27b'` (in `MODEL_PRICING`) | `get_pricing(model_id)` is called | Returns explicit rates, no warning |
| 2.4.1.4 | `model_id=None` | `get_pricing(model_id)` is called | Returns fallback rates, no warning (None is expected) |

**Changes Required:**

#### 9. Add fallback warning to `model_pricing.py`

**File:** `.opencode/skills/analyzing-opencode-usage/script/model_pricing.py`
**Changes:**

(a) Add `import logging` at the top
(b) Modify `get_pricing()` to log when fallback is used for a known (non-None) model:

```python
import logging

logger = logging.getLogger(__name__)

# Track which models have triggered fallback warnings (avoid repeated logging)
_FALLBACK_WARNED: set = set()

def get_pricing(model_id):
    """Get pricing dict for a model. Falls back to generic pricing if unknown."""
    if not model_id:
        return MODEL_PRICING['fallback']
    if model_id in MODEL_PRICING:
        return MODEL_PRICING[model_id]
    # Unknown model — warn once per model ID
    if model_id not in _FALLBACK_WARNED:
        logger.warning(
            "Model '%s' not found in pricing table. Using fallback rates "
            "(input: $0.50/M, output: $1.50/M). Add to MODEL_PRICING for accuracy.",
            model_id
        )
        _FALLBACK_WARNED.add(model_id)
    return MODEL_PRICING['fallback']
```

(c) Add explicit pricing entries for known custom models that appear in the data:

```python
MODEL_PRICING = {
    # ... existing entries ...
    # Custom/local models
    'agents-a1':            {'input': 0.50,  'output': 1.50,  'cached_input': 0.05},
    'big-pickle':           {'input': 0.50,  'output': 1.50,  'cached_input': 0.05},
    # ...
}
```

Note: The rates for `agents-a1` and `big-pickle` are the same as the fallback since we don't know their actual cloud-equivalent pricing. The key improvement is that they are explicit entries, not silent fallbacks.

---

### Success Criteria:

#### Automated Verification:
- [ ] `list(merge_output['timeseries']) is not merge_output['daily_agent_stacked']` — different objects
- [ ] `queries/productivity.py` does not contain `summary_files` in any SQL
- [ ] `queries/productivity.py` return dict does not include `sessions_with_changes` or `pct_with_changes`
- [ ] `_build_phases()` returns `[]`
- [ ] `model_pricing.py` contains `logging.warning` call in `get_pricing()`
- [ ] `model_pricing.py` has `_FALLBACK_WARNED` set to prevent repeated warnings
- [ ] `model_pricing.py` has explicit entries for `agents-a1` and `big-pickle`

#### Manual Verification:
- [ ] Run report for July-August 2026 — `phases` field is `[]`, not all-zero phases
- [ ] Run report with `agents-a1` model — stderr shows one warning about fallback pricing
- [ ] Run report with known model — no fallback warning on stderr

---

## Phase 3: Maintainability & Documentation

### Overview

Fix 3 issues that increase maintenance burden, risk of future bugs, or mislead users reading documentation.

### Behavior Specifications

#### B7: Duplicated CTE in `cache_estimate.py`

**Component Behavior:**

| # | Given | When | Then |
|---|-------|------|------|
| 2.5.1.1 | Cache estimation logic needs to change (e.g., `LAG` strategy) | Developer edits the shared CTE builder | All 5 `fetch_*` functions use the updated logic automatically |
| 2.5.1.2 | `cache_estimate.py` is loaded | — | No duplicate CTE SQL blocks exist in the file |

**Changes Required:**

#### 10. Extract shared CTE in `queries/cache_estimate.py`

**File:** `.opencode/skills/analyzing-opencode-usage/script/queries/cache_estimate.py`
**Changes:** Extract the common 4-level CTE chain into a helper function. Each `fetch_*` function appends its own `SELECT ... FROM per_turn ...` clause.

```python
def _cache_cte(where: str) -> str:
    """Build the shared 4-level CTE chain for cache estimation queries.

    Returns the CTE block (without trailing semicolon) that all cache
    estimation queries share. Each caller appends its own SELECT clause.
    """
    return f"""
    WITH collages AS (
        SELECT id, directory, time_created, model, agent
        FROM session s
        WHERE {where}
          AND strftime('%Y-%m-%d', s.time_created / 1000, 'unixepoch') >= ?
          AND strftime('%Y-%m-%d', s.time_created / 1000, 'unixepoch') <= ?
    ),
    msg_tokens AS (
        SELECT
            m.session_id,
            m.time_created,
            json_extract(m.data, '$.tokens.input') AS input_tokens,
            json_extract(m.data, '$.tokens.output') AS output_tokens,
            json_extract(m.data, '$.tokens.reasoning') AS reasoning_tokens,
            ROW_NUMBER() OVER (PARTITION BY m.session_id ORDER BY m.time_created) AS turn
        FROM message m
        JOIN collages c ON m.session_id = c.id
        WHERE json_extract(m.data, '$.tokens.input') IS NOT NULL
          AND json_extract(m.data, '$.role') = 'assistant'
    ),
    with_prev AS (
        SELECT
            mt.*,
            LAG(mt.input_tokens) OVER (PARTITION BY mt.session_id ORDER BY mt.time_created) AS prev_input
        FROM msg_tokens mt
    ),
    per_turn AS (
        SELECT
            *,
            CASE
                WHEN prev_input IS NULL THEN input_tokens
                WHEN input_tokens <= prev_input THEN input_tokens
                ELSE input_tokens - prev_input
            END AS new_uncached_input,
            CASE
                WHEN prev_input IS NULL THEN 0
                WHEN input_tokens <= prev_input THEN 0
                ELSE prev_input
            END AS cached_input
        FROM with_prev
    )
    """
```

Then each function builds its query as:
```python
sql = _cache_cte(where) + """
SELECT
    COUNT(DISTINCT session_id) AS sessions,
    ...
FROM per_turn
"""
```

Expected reduction: ~200 lines of duplicated SQL → ~40 lines in `_cache_cte()` + 5 thin SELECT clauses.

---

#### B11: Missing `references/activity-template.md`

**Changes Required:**

#### 11. Create `references/activity-template.md`

**File:** `.opencode/skills/analyzing-opencode-usage/references/activity-template.md`
**Changes:** Create the file referenced by SKILL.md (line 418). The template should match the description in SKILL.md: "Structure for daily activity summaries: overview paragraph, token breakdowns, session counts, and commit SHAs per day."

Content (minimal template matching the SKILL.md description):

```markdown
# Daily Activity Summary: {date_range}

## Overview

{Total sessions, total effective tokens, total commits for the period}

## Daily Breakdown

### {date}

**Tokens:** {input} input, {output} output, {reasoning} reasoning ({effective} effective)
**Sessions:** {count} sessions across {agent_count} agents
**Commits:** {count} commits

{list of commit SHAs with messages}

...
```

---

#### B12: SKILL.md cost example is wrong

**Changes Required:**

#### 12. Fix cost example in SKILL.md

**File:** `.opencode/skills/analyzing-opencode-usage/SKILL.md`
**Changes:** Update lines 193-194. The current example:

```python
cost = compute_cost('qwen/qwen3.6-27b', 1000000, 500000, 800000)
# {'raw_cost': 0.80, 'cache_adjusted_cost': 0.79, 'cache_savings': 0.01}
```

Let me verify the correct values:
- `input_tokens=1000000`, `output_tokens=500000`, `cached_input=800000`
- Pricing for `qwen/qwen3.6-27b`: input=$0.50/M, output=$1.50/M, cached_input=$0.05/M
- `raw_cost = 1000000 * 0.50/1M + 500000 * 1.50/1M = 0.50 + 0.75 = 1.25`
- `uncached = 1000000 - 800000 = 200000`
- `cache_adjusted = 200000 * 0.50/1M + 800000 * 0.05/1M + 500000 * 1.50/1M = 0.10 + 0.04 + 0.75 = 0.89`
- `cache_savings = 1.25 - 0.89 = 0.36`

Corrected example:
```python
cost = compute_cost('qwen/qwen3.6-27b', 1000000, 500000, 800000)
# {'raw_cost': 1.25, 'cache_adjusted_cost': 0.89, 'cache_savings': 0.36}
```

---

### Success Criteria:

#### Automated Verification:
- [ ] `cache_estimate.py` contains exactly one `_cache_cte` function
- [ ] No `WITH collages AS` appears more than once in `cache_estimate.py`
- [ ] `cache_estimate.py` line count reduced by at least 100 lines
- [ ] `references/activity-template.md` exists and is non-empty
- [ ] `SKILL.md` cost example output matches `compute_cost(1000000, 500000, 800000)` actual output

#### Manual Verification:
- [ ] Run `generate_report.py` — cache estimate results match pre-change values (no regression)
- [ ] Run `validate_summaries.sh` — no errors related to missing template
- [ ] Read SKILL.md cost example — values are mathematically correct

---

## Testing Strategy

### Verification Commands

Run the report generator with various date configurations to verify all fixes:

```bash
cd .opencode/skills/analyzing-opencode-usage/script

# Test B1/B10: Partial date arguments
python3 generate_report.py --project . --since 2026-08-01 --json --output /tmp/test-since-only.json
python3 generate_report.py --project . --until 2026-08-07 --json --output /tmp/test-until-only.json

# Test B5: Verify session count excludes zero-token sessions
python3 generate_report.py --project . --json --output /tmp/test-full.json
# Then check: report.summary.total_sessions matches DB COUNT(*) WHERE tokens > 0

# Test B3: Verify cost_summary includes reasoning_tokens
python3 -c "import json; d=json.load(open('/tmp/test-full.json')); print(d['cost_summary'].get('reasoning_tokens', 'MISSING'))"

# Test B2: Verify productive_build_sessions <= total build sessions
python3 -c "
import json
d=json.load(open('/tmp/test-full.json'))
bp = d['build_productivity'][0]
print(f'productive_sessions={bp[\"productive_sessions\"]}')
"

# Test B4: Verify phases is empty for current date range
python3 -c "import json; d=json.load(open('/tmp/test-full.json')); print(f'phases={d[\"phases\"]}')"

# Test B6: Check for fallback warnings
python3 generate_report.py --project . --json --output /tmp/test-pricing.json 2>&1 | grep -i "fallback\|not found in pricing"

# Test B8: Verify timeseries and daily_agent_stacked are independent
python3 -c "
import json
d=json.load(open('/tmp/test-full.json'))
print(f'timeseries len={len(d[\"timeseries\"])}, stacked len={len(d[\"daily_agent_stacked\"])}')
print(f'same length={len(d[\"timeseries\"]) == len(d[\"daily_agent_stacked\"])}')
"
```

### Regression Guards

- Run the report against the same project/date range before and after changes; compare `summary.total_tokens_effective`, `models_with_cost`, and `timeseries` values — they should not change (except for B5 which intentionally reduces session counts)
- Cache estimate results must be byte-identical before and after CTE extraction (B7)

---

## Performance Considerations

- **B7 (CTE extraction)** is purely refactor — no performance change expected
- **B9 (dead SQL removal)** removes one unnecessary query execution per report generation — minor performance improvement
- **B1/B10 (date consolidation)** removes one function call path — negligible
- No changes introduce new database queries or increase query complexity

---

## Migration Notes

- The `cost_summary` structure gains two new keys (`total_per_model`, `reasoning_tokens`). Any downstream consumers reading `cost_summary` should be updated to handle these new fields (they are additive, not breaking).
- The `productivity` return dict loses two keys (`sessions_with_changes`, `pct_with_changes`) that were always placeholder values (0 and 0.0). These are computed in `merge.py` and set on the `productivity` dict before it reaches the output, so the final JSON output is unchanged.
- The `phases` field changes from a list of 4 all-zero phase objects to an empty list `[]`. HTML renderers that iterate over `phases` should handle empty lists gracefully (they already do via the `<details>` collapsible section pattern).

---

## Known Behaviors

| Decision | Rationale |
|----------|-----------|
| `_resolve_date` defaults `since` to `2000-01-01` | Matches existing behavior; captures all historical sessions |
| `_resolve_date` defaults `until` to `date.today()` | Matches existing behavior; captures sessions through today |
| Zero-token sessions excluded from `total_sessions` | They contribute no data and skew all per-session averages |
| Build sessions approximated via token ratio | Per-category session counts don't exist in `daily_tokens`; token ratio is the best available proxy |
| Phases return empty list | Hardcoded dates are project-specific; making them configurable is a feature addition |
| Fallback pricing warns once per model | Avoids log spam while alerting the operator to unknown models |
| `daily_agent_stacked` uses shallow copy | The list contains dicts; shallow copy prevents list-level mutations (append, sort, pop) from bleeding between keys. Dict-level mutations are prevented by JSON serialization. |

---

## Priority Ordering

| Priority | Bugs | Rationale |
|----------|------|-----------|
| **P0** | B1, B10, B5, B2, B3 | Produce wrong numbers in reports — undermines all data trust |
| **P1** | B8, B9, B4, B6 | Silent corruption, wasted compute, broken features for non-default ranges |
| **P2** | B7, B11, B12 | Maintenance burden and documentation accuracy |

---

## References

- Specification: `_agent_docs/specifications/analyzing-opencode-usage-improvements.md`
- SKILL.md: `.opencode/skills/analyzing-opencode-usage/SKILL.md`
- Session summary template: `.opencode/skills/analyzing-opencode-usage/references/session-summary.json`
- Script entry point: `.opencode/skills/analyzing-opencode-usage/script/generate_report.py`
