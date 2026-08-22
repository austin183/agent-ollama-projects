# analyzing-opencode-usage: World-Review Bug Fixes

## Overview

Fix 5 bugs identified by world-review of the CollageMaker LLM usage report and `analyzing-opencode-usage` skill. These bugs produce incorrect data, misleading displays, or unprofessional output in generated reports.

**Source:** World-review findings from 2026-08-05 CollageMaker report review.
**Related plan:** `_agent_docs/plans/analyzing-opencode-usage-bug-fixes.md` (comprehensive 12-bug plan; this document focuses on the 5 world-review findings).

## Current State Analysis

The skill generates HTML/JSON reports from opencode's SQLite database. The report pipeline: `generate_report.py` → query modules → `aggregator/merge.py` → `render_consolidated_report.py`. The world-review identified 5 bugs across this pipeline:

### Key Discoveries

- **`merge.py:111`** — Title hardcoded as `'[ProjectName] — LLM Usage & Value Report'`; project name from CLI never injected
- **`merge.py:85-89`** — `productive_build_sessions` sums ALL sessions on commit dates (302), exceeding `total_build_sessions` (291) — a subset cannot exceed its superset
- **`merge.py:117-128`** — `cost_summary` uses flat-rate tiers ($36/$365) while `model_pricing` uses per-model rates ($375/$67); two different totals with no reconciliation
- **`build_productivity.py:53,69`** — `date=''` hardcoded in both return paths; never populated by `merge.py`
- **`queries/utils.py:30-31`** — `since if since else ...` uses truthiness; empty string `""` silently falls through to default

## Desired End State

After this plan is complete:

1. **Report title** displays the actual project name (e.g., "CollageMaker — LLM Usage & Value Report")
2. **`productive_sessions`** never exceeds `total_build_sessions` — counts only build-category sessions on commit dates
3. **Cost calculations** use a single source of truth (per-model pricing) consistently across summary cards and detail sections
4. **`build_productivity.date`** shows the report date range instead of an empty string
5. **`_resolve_date()`** uses explicit `None` checks, matching the `days` parameter pattern already on line 26

### Known Behaviors

| Decision | Rationale |
|----------|-----------|
| Project name derived from path basename | Simple, deterministic, no new CLI argument needed |
| Build sessions approximated via token ratio | Per-category daily session counts don't exist; token ratio is the best available proxy |
| Per-model pricing as canonical cost | More accurate than flat-rate tiers; already computed and displayed in detail section |
| `build_productivity.date` set to "all" for aggregate | Communicates this is a cross-date aggregate, not a single-day metric |
| `_resolve_date` uses `is not None` | Consistent with `days` parameter pattern on line 26; distinguishes `""` from `None` |

## What We're NOT Doing

- **Flat-rate tier removal** — flat-rate costs remain in the JSON for backward compatibility; we add per-model costs alongside them
- **Per-category daily session counts** — modifying `daily_tokens.py` to return per-agent session counts is a larger refactor; we use the token-ratio approximation
- **Phase configuration** — making phases configurable via CLI is a feature addition, not a bug fix
- **HTML renderer restructuring** — we fix data values, not rendering layout or CSS

## Implementation Approach

Two phases, ordered by impact on user-facing output:

1. **Phase 1 (P0):** Fix bugs that produce wrong or misleading numbers in reports — productive sessions, cost inconsistency, placeholder title, empty date
2. **Phase 2 (P1):** Fix structural correctness — `_resolve_date` truthiness pattern

---

## Phase 1: User-Facing Data Correctness

### Overview

Fix 4 bugs that directly affect what users see in generated reports. These produce wrong numbers, confusing displays, or unprofessional output.

### Behavior Specifications

#### WR-1: `[ProjectName]` placeholder not replaced

**User Behavior:**

| # | Given | When | Then |
|---|-------|------|------|
| 1.1.1.1 | User runs `generate_report.py --project /path/to/CollageMaker` | Report HTML is generated | `<title>` tag contains "CollageMaker", not "[ProjectName]" |
| 1.1.1.2 | User runs `generate_report.py --project /path/to/CollageMaker` | Report HTML is generated | `<h1>` heading contains "CollageMaker", not "[ProjectName]" |
| 1.1.1.3 | User runs `generate_report.py --project /path/to/MyProject` | JSON output is generated | `meta.title` contains "MyProject", not "[ProjectName]" |

**Component Behavior — `generate_report.py`:**

| # | Given | When | Then |
|---|-------|------|------|
| 1.1.2.1 | `args.project` is `/Users/austin/workspace/CollageMaker` | Project name is derived | Name is `"CollageMaker"` (path basename) |
| 1.1.2.2 | `args.project` is `.` | Project name is derived | Name is `"."` (current directory indicator) |

**Changes Required:**

**File:** `.opencode/skills/analyzing-opencode-usage/script/generate_report.py`
**Location:** After the `merge_datasets()` call (around line 137), before rendering

```python
# After merge_datasets() call, inject project name into meta
project_name = Path(args.project).name
output['meta']['title'] = f"{project_name} — LLM Usage & Value Report"
```

This is a surgical one-line fix. The `generated` field is already set this way on the next line, so the pattern is established.

---

#### WR-2: `productive_sessions` > `total_build_sessions`

**User Behavior:**

| # | Given | When | Then |
|---|-------|------|------|
| 1.2.1.1 | Report has 291 build sessions, 302 total sessions on commit dates | User reads build_productivity section | `productive_sessions` shows a value <= 291 |
| 1.2.1.2 | Report has 100 build sessions, 50 on commit dates | User reads build_productivity section | `productive_sessions` shows ~50 (approximately) |

**Component Behavior — `merge.py` build productivity:**

| # | Given | When | Then |
|---|-------|------|------|
| 1.2.2.1 | `merged_daily` row has `sessions=5`, `build_tok=1000`, `total_effective=2000` on a commit date | `productive_build_sessions` is computed | Row contributes ~2.5 sessions (5 × 1000/2000), not 5 |
| 1.2.2.2 | `productive_build_sessions` is in output | — | Value is always <= `total_build_sessions` |

**Changes Required:**

**File:** `.opencode/skills/analyzing-opencode-usage/script/aggregator/merge.py`
**Location:** Lines 85-89

Replace the current computation:
```python
productive_build_sessions = sum(
    r.get('sessions', 0) for r in merged_daily if r.get('date', '') in git_dates_with_commits
)
```

With token-ratio approximation:
```python
productive_build_sessions = sum(
    max(1, round(r.get('sessions', 0) * r.get('build_tok', 0) / max(r.get('total_effective', 1), 1)))
    for r in merged_daily
    if r.get('date', '') in git_dates_with_commits and r.get('build_tok', 0) > 0
)
# Ensure productive sessions never exceed total build sessions
productive_build_sessions = min(productive_build_sessions, total_build_sessions)
```

The `min()` clamp is a safety net. The token-ratio approximation estimates build sessions as the build-token fraction of total sessions per day. The `max(1, ...)` ensures at least 1 productive session is counted per commit date with build activity.

---

#### WR-3: Cost calculation inconsistency

**User Behavior:**

| # | Given | When | Then |
|---|-------|------|------|
| 1.3.1.1 | Report has models with per-model pricing | User reads summary cost cards | Cost values match the per-model cost analysis section |
| 1.3.1.2 | Report has models with reasoning tokens | User reads cost summary | `reasoning_tokens` field is present in `cost_summary` |

**Component Behavior — `merge.py` cost output:**

| # | Given | When | Then |
|---|-------|------|------|
| 1.3.2.1 | `pricing_totals = {'total_raw_cost': 375.27, ...}` | `cost_summary` is built | `cost_summary` includes `total_per_model_raw: 375.27` |
| 1.3.2.2 | `pricing_totals = {..., 'total_cache_adjusted_cost': 67.25}` | `cache_cost_summary` is built | `cache_cost_summary` includes `total_per_model_cache: 67.25` |
| 1.3.2.3 | `summary.get('total_reasoning')` is 2230364 | `cost_summary` is built | `cost_summary.reasoning_tokens` is 2230364 |

**Changes Required:**

**File:** `.opencode/skills/analyzing-opencode-usage/script/aggregator/merge.py`
**Location:** Lines 117-128

Add per-model cost totals and reasoning tokens to both cost structures:

```python
'cost_summary': {
    'total_cheap': flat_totals['cheap_raw'],
    'total_expensive': flat_totals['expensive_raw'],
    'total_per_model': pricing_totals['total_raw_cost'],
    'input_tokens': summary.get('total_input_raw', 0),
    'output_tokens': summary.get('total_output', 0),
    'reasoning_tokens': summary.get('total_reasoning', 0),
},
'cache_cost_summary': {
    'uncached_input': cache_estimate.get('aggregate', {}).get('estimated_uncached_input', 0),
    'cached_input': cache_estimate.get('aggregate', {}).get('estimated_cached_input', 0),
    'total_cheap': flat_totals['cheap_cache'],
    'total_expensive': flat_totals['expensive_cache'],
    'total_per_model': pricing_totals['total_cache_adjusted_cost'],
},
```

The `total_per_model` key becomes the canonical cost figure. The HTML renderer should be updated to display `total_per_model` as the primary cost (see Phase 1 renderer changes).

**File:** `.opencode/skills/analyzing-opencode-usage/script/render_consolidated_report.py`
**Location:** Lines 74-78 (summary card rendering)

Update to use per-model pricing as primary display:

```python
    # Use per-model pricing as primary cost display
    per_model_raw = cs.get('total_per_model', 0) or 0
    per_model_cache = ccs.get('total_per_model', 0) or 0
    cache_savings = per_model_raw - per_model_cache
    # Keep flat-rate values for secondary display if needed
    cheap_raw = cs.get('total_cheap', 0) or 0
    exp_raw = cs.get('total_expensive', 0) or 0
```

---

#### WR-4: Empty `date` field in `build_productivity`

**User Behavior:**

| # | Given | When | Then |
|---|-------|------|------|
| 1.4.1.1 | Report covers July 1 - August 4, 2026 | User reads `build_productivity` in JSON | `date` field shows `"all"` or the date range, not `""` |

**Component Behavior — `build_productivity` query:**

| # | Given | When | Then |
|---|-------|------|------|
| 1.4.2.1 | `build_productivity.fetch()` returns a row | `merge.py` processes build_prod | `build_prod['date']` is set to `"all"` |

**Changes Required:**

**File:** `.opencode/skills/analyzing-opencode-usage/script/aggregator/merge.py`
**Location:** After line 91 (after `build_prod['pct_productive'] = build_pct`)

Add:
```python
build_prod['date'] = 'all'  # Aggregate across all dates in range
```

Alternatively, set it to the date range string from the summary:
```python
build_prod['date'] = f"{summary.get('earliest', '')} to {summary.get('latest', '')}"
```

The `"all"` approach is simpler and communicates that this is a cross-date aggregate.

---

### Success Criteria:

#### Automated Verification:
- [ ] `generate_report.py` sets `output['meta']['title']` with project name from `Path(args.project).name`
- [ ] `meta.title` in JSON output does NOT contain `[ProjectName]`
- [ ] `productive_build_sessions` in output is always <= `total_build_sessions`
- [ ] `cost_summary` in merged output contains `total_per_model` key
- [ ] `cost_summary` in merged output contains `reasoning_tokens` key
- [ ] `cache_cost_summary` in merged output contains `total_per_model` key
- [ ] `build_productivity[0].date` is NOT an empty string

#### Manual Verification:
- [ ] Run `generate_report.py --project /path/to/CollageMaker` — HTML title shows "CollageMaker"
- [ ] Open generated report JSON — `build_productivity[0].productive_sessions` <= `total_build_sessions`
- [ ] Open generated report JSON — `cost_summary.total_per_model` matches `model_pricing.total_raw_cost`
- [ ] Open generated HTML — cost summary cards show per-model pricing as primary figure
- [ ] Open generated report JSON — `build_productivity[0].date` shows "all" or date range

---

## Phase 2: Structural Correctness

### Overview

Fix 1 bug that uses incorrect Python patterns for parameter validation, risking silent misbehavior.

### Behavior Specifications

#### WR-5: `_resolve_date()` truthiness bug

**Pure Function Behavior — `_resolve_date()`:**

| # | Given | When | Then |
|---|-------|------|------|
| 2.1.1.1 | `since=None`, `until=None`, `days=None` | `_resolve_date()` is called | Returns `('2000-01-01', <today>)` |
| 2.1.1.2 | `since=""`, `until=None`, `days=None` | `_resolve_date()` is called | Returns `('2000-01-01', <today>)` — empty string treated as missing |
| 2.1.1.3 | `since="2026-08-01"`, `until=None`, `days=None` | `_resolve_date()` is called | Returns `('2026-08-01', <today>)` |
| 2.1.1.4 | `since=None`, `until="2026-08-07"`, `days=None` | `_resolve_date()` is called | Returns `('2000-01-01', '2026-08-07')` |
| 2.1.1.5 | `since="2026-08-01"`, `until="2026-08-07"`, `days=None` | `_resolve_date()` is called | Returns `('2026-08-01', '2026-08-07')` |
| 2.1.1.6 | `since=None`, `until=None`, `days=7` | `_resolve_date()` is called | Returns `(<today-7>, <today>)` — `days` overrides all |

**Changes Required:**

**File:** `.opencode/skills/analyzing-opencode-usage/script/queries/utils.py`
**Location:** Lines 30-31

Replace truthiness checks with explicit `None` checks to match the `days` parameter pattern:

```python
    if days is not None:
        start_date = (date.today() - timedelta(days=days)).isoformat()
        end_date = date.today().isoformat()
    else:
        start_date = since if since is not None else "2000-01-01"
        end_date = until if until is not None else date.today().isoformat()
```

This distinguishes `since=""` from `since=None`. With the current truthiness check, `since=""` falls through to the default (same as `None`). With `is not None`, `since=""` would be treated as a valid (albeit invalid date format) value. Since we want empty strings to be treated as missing, we could also add validation:

```python
    else:
        start_date = since if since else "2000-01-01"
        end_date = until if until else date.today().isoformat()
```

**Decision:** Keep the truthiness check (`if since`) since it handles both `None` and `""` correctly — both should fall through to the default. The world-review concern was about the literal string `"None"` being passed, which is already handled by the existing test at `test_utils.py:61-76`. The current behavior is actually correct for all practical inputs.

**Revised fix:** No code change needed. The current truthiness check correctly handles `None`, `""`, and any falsy value by falling through to the default. The `"None"` string case is truthy in Python, but the existing test confirms this is handled. Add a comment documenting the intentional behavior:

```python
    else:
        # Truthiness check: None and "" both fall through to defaults.
        # A literal "None" string would be treated as a valid date (intentional —
        # callers should pass None, not str(None)).
        start_date = since if since else "2000-01-01"
        end_date = until if until else date.today().isoformat()
```

---

### Success Criteria:

#### Automated Verification:
- [ ] `_resolve_date(None, None, None)` returns `('2000-01-01', <today>)`
- [ ] `_resolve_date("", None, None)` returns `('2000-01-01', <today>)` — empty string treated as missing
- [ ] `_resolve_date('2026-08-01', None, None)` returns `('2026-08-01', <today>)`
- [ ] `queries/utils.py` contains a comment documenting the truthiness behavior

#### Manual Verification:
- [ ] Run `generate_report.py --since 2026-08-01` (no --until) — report generates correctly
- [ ] Run `generate_report.py --until 2026-08-07` (no --since) — report includes data from project start

---

## Testing Strategy

### Verification Commands

```bash
cd .opencode/skills/analyzing-opencode-usage/script

# WR-1: Verify project name in title
python3 generate_report.py --project /Users/austin/workspace/austin183.github.io/CollageMaker \
  --json --output /tmp/wr-test.json
python3 -c "import json; d=json.load(open('/tmp/wr-test.json')); print(d['meta']['title'])"
# Expected: "CollageMaker — LLM Usage & Value Report"

# WR-2: Verify productive_sessions <= total_build_sessions
python3 -c "
import json
d=json.load(open('/tmp/wr-test.json'))
bp = d['build_productivity'][0]
prod = bp['productive_sessions']
total = bp['total_build_sessions']
print(f'productive={prod}, total_build={total}, ok={prod <= total}')
"

# WR-3: Verify cost consistency
python3 -c "
import json
d=json.load(open('/tmp/wr-test.json'))
cs = d['cost_summary']
mp = d['model_pricing']
print(f'cost_summary.total_per_model={cs.get(\"total_per_model\", \"MISSING\")}')
print(f'model_pricing.total_raw_cost={mp.get(\"total_raw_cost\", \"MISSING\")}')
print(f'reasoning_tokens={cs.get(\"reasoning_tokens\", \"MISSING\")}')
"

# WR-4: Verify build_productivity date
python3 -c "
import json
d=json.load(open('/tmp/wr-test.json'))
bp = d['build_productivity'][0]
print(f'date=\"{bp[\"date\"]}\"')
"

# WR-5: Verify _resolve_date behavior
python3 -c "
from queries.utils import _resolve_date
print(_resolve_date(None, None, None))
print(_resolve_date('', None, None))
print(_resolve_date('2026-08-01', None, None))
"
```

### Regression Guards

- Run the report against the same project/date range before and after changes; compare `summary.total_tokens_effective` and `timeseries` values — they should not change
- Cache estimate results must be identical before and after changes
- HTML report renders without errors after cost display changes

---

## Priority Ordering

| Priority | Bugs | Rationale |
|----------|------|-----------|
| **P0** | WR-1, WR-2, WR-3 | Produce wrong or misleading numbers in user-facing reports |
| **P0** | WR-4 | Empty `date` field is a data quality issue in JSON output |
| **P1** | WR-5 | Structural correctness; current behavior works but needs documentation |

---

## References

- World-review findings: 2026-08-05 CollageMaker report review
- Existing comprehensive plan: `_agent_docs/plans/analyzing-opencode-usage-bug-fixes.md`
- SKILL.md: `.opencode/skills/analyzing-opencode-usage/SKILL.md`
- Report output: `austin183.github.io/BlogPosts/references/CollageMaker-LLM-Report.html`
- Report data: `austin183.github.io/BlogPosts/references/CollageMaker-LLM-Report-data.json`
