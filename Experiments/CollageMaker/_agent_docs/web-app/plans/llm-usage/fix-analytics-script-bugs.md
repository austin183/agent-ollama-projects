# Fix Analytics Script Bugs — Implementation Plan

## Overview

Fix three data accuracy bugs in the analytics scripts (`analyzing-opencode-usage/script/`):

| # | Bug | Root Cause | Impact |
|---|-----|-----------|--------|
| 1 | Weekly field mismatch | `weekly.py` SQL aliases name agent-category breakdowns as token types | JSON output has misleading field names, components don't sum to total |
| 2 | `total_turns: 0` in cache breakdowns | Breakdown queries omit `COUNT(*)`, hardcoded to 0 | Cache breakdowns show 0 turns despite 4,253 total |
| 3 | Productivity showing 0 | Query checks `summary_files > 0` but all sessions have 0 | Shows 0 sessions with changes despite 8 commits |

## Current State Analysis

### Bug 1: Weekly field mismatch
- **`queries/weekly.py:43-45`** — `input_tokens_raw` = build agent tokens, `output_tokens_raw` = review agent tokens, `reasoning_tokens_raw` = planner agent tokens
- **`queries/weekly.py:64-66`** — Row construction uses wrong field names
- **`data_access/types.py:94-102`** — `WeeklyRow` TypedDict mirrors misleading names
- No downstream consumer reads these fields — `merge.py:114` passes through, HTML doesn't render weekly

### Bug 2: `total_turns: 0` in cache breakdowns
- **`queries/cache_estimate.py:198, 295, 392`** — Hardcode `total_turns=0` with `# Not computed for breakdown rows`
- **`queries/cache_estimate.py:175-188, 272-285, 369-382`** — SQL lacks `COUNT(*) AS total_turns`
- **`estimate_cache.py:168-251`** — Standalone script: same omission in all three breakdown queries

### Bug 3: Productivity showing 0
- **`queries/productivity.py:39`** — `SUM(CASE WHEN summary_files > 0 THEN 1 ELSE 0 END)` — all 182 sessions have `summary_files = 0`
- Git data comes from `daily_git` via `git log`, not the session table
- **`aggregator/merge.py:108`** — Passes productivity through; timeseries correctly shows commits from `daily_git`

## Desired End State

1. Weekly fields: `build_tokens`, `review_tokens`, `planner_tokens` with matching TypedDict
2. Cache breakdowns: real `total_turns` from `COUNT(*)` in each grouped query
3. Productivity: derived from git data, non-zero when commits exist

## What We're NOT Doing

- Not fixing `summary_files` in session table (opencode DB issue)
- Not adding weekly chart to HTML report
- Not changing `estimate_cache.py` CLI behavior beyond SQL fix

---

## Phase 1: Rename Weekly Fields

### Changes:

#### `queries/weekly.py:43-45` — SQL aliases
```sql
-- build agent
COALESCE(SUM(CASE WHEN agent = 'build' THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0) as build_tokens,
-- review agents
COALESCE(SUM(CASE WHEN agent IN ('diff-review','diff-review-g31','solid-review','world-review','diff-review-q35','diff-review-o32') THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0) as review_tokens,
-- planner agents
COALESCE(SUM(CASE WHEN agent IN ('planner','planner-g31','plan') THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0) as planner_tokens
```

#### `queries/weekly.py:64-66` — Row construction
```python
build_tokens=r.get('build_tokens', 0) or 0,
review_tokens=r.get('review_tokens', 0) or 0,
planner_tokens=r.get('planner_tokens', 0) or 0,
```

#### `data_access/types.py:94-102` — TypedDict
```python
class WeeklyRow(TypedDict):
    """Weekly aggregation by agent category."""
    week_start: str
    week_end: str
    sessions: int
    total_tokens_raw: int
    build_tokens: int
    review_tokens: int
    planner_tokens: int
```

### Verification:
- [ ] `python3 script/generate_report.py --project . --json 2>/dev/null | python3 -c "import json,sys; w=json.load(sys.stdin)['weekly'][0]; assert 'build_tokens' in w"`

---

## Phase 2: Fix `total_turns: 0` in Cache Breakdowns

### Changes:

#### `queries/cache_estimate.py` — `fetch_by_model` (line 177, 198)
Add `COUNT(*) AS total_turns,` after `COUNT(DISTINCT pt.session_id) AS sessions,` in SELECT.
Replace `total_turns=0,` with `total_turns=r.get('total_turns', 0) or 0,`.

#### `queries/cache_estimate.py` — `fetch_by_agent` (line 274, 295)
Same pattern.

#### `queries/cache_estimate.py` — `fetch_by_day` (line 371, 392)
Same pattern.

#### `estimate_cache.py` — by_model (line 171, 184)
Add `COUNT(*) AS total_turns,` to SQL. Add `'total_turns': r.get('total_turns', 0) or 0,` to result dict. Also add `'effective_total'` and `'raw_total'` for consistency.

#### `estimate_cache.py` — by_agent (line 200, 213)
Same pattern.

#### `estimate_cache.py` — by_day (line 229, 242)
Same pattern.

### Verification:
- [ ] `cache_estimate.by_model[*].total_turns > 0` for models with sessions
- [ ] Sum of breakdown `total_turns` equals aggregate `total_turns` (4,253)

---

## Phase 3: Fix Productivity Showing 0

### Approach
Compute `sessions_with_changes` in the merge step using `daily_git` data, since git data is external (`git log`) and can't be joined in SQL.

### Changes:

#### `queries/productivity.py` — Add per-day session counts
After the existing query, add a second query for date-to-session-count mapping:
```python
sql_daily = f"""
SELECT
    strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') as day,
    COUNT(*) as sessions
FROM session
WHERE {where}
    AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= ?
    AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= ?
GROUP BY day
"""
daily_rows = run_query(conn, sql_daily, tuple(params))
daily_sessions = {r['day']: r['sessions'] for r in daily_rows}
```

Return a dict with `total_sessions`, placeholder `sessions_with_changes=0`, `pct_with_changes=0.0`, plus `daily_sessions`.

#### `aggregator/merge.py:55` — Compute sessions_with_changes
```python
# After extracting productivity at line 55:
daily_sessions = productivity.pop('daily_sessions', {})
git_dates_with_commits = {r.get('date', '') for r in daily_git if r.get('commits', 0) > 0}
sessions_with_changes = sum(daily_sessions.get(d, 0) for d in git_dates_with_commits)
productivity['sessions_with_changes'] = sessions_with_changes
productivity['pct_with_changes'] = round(100.0 * sessions_with_changes / max(productivity.get('total_sessions', 0), 1), 1)
```

### Verification:
- [ ] `productivity[0].sessions_with_changes > 0` when commits exist
- [ ] Values match timeseries (sessions on days with `commits > 0`)

---

## Testing Strategy

### Post-fix verification:
```bash
python3 script/generate_report.py --project /Users/austin/workspace/austin183.github.io/CollageMaker --json --output /tmp/verify.json 2>/dev/null
python3 -c "
import json
d = json.load(open('/tmp/verify.json'))
# Bug 1
w = d['weekly'][0]
assert 'build_tokens' in w and 'input_tokens_raw' not in w, 'Bug 1 not fixed'
# Bug 2
for m in d['cache_estimate']['by_model']:
    if m['sessions'] > 0: assert m['total_turns'] > 0, f'Bug 2: {m[\"key\"]}'
for a in d['cache_estimate']['by_agent']:
    if a['sessions'] > 0: assert a['total_turns'] > 0, f'Bug 2: {a[\"key\"]}'
for day in d['cache_estimate']['by_day']:
    if day['sessions'] > 0: assert day['total_turns'] > 0, f'Bug 2: {day[\"key\"]}'
# Bug 3
p = d['productivity'][0]
assert p['sessions_with_changes'] > 0, f'Bug 3: {p}'
print('All bugs fixed!')
"
```

## References
- Report data: `_agent_docs/project-timeline/llm-usage/2026-07-07-collagemaker-report-data.json`
- Session table: all 182 sessions have `summary_files = 0`
