# 2026-08-08 — Analytics Skill Remaining Fixes Implementation Plan

## Overview

Address the remaining issues identified by the 2026-08-08 world-review of the CollageMaker LLM usage analytics report and the `analyzing-opencode-usage` skill. The previous plan (2026-08-06) fixed productive_sessions, `_resolve_date()`, zero-token validation, top_sessions dates, and model pricing. This plan targets the **remaining gaps** that affect data accuracy, security, and user experience.

**Source:** World-review findings from 2026-08-08 session, documented in `_agent_docs/project-timeline.md/project-timeline.md`.

## Current State Analysis

Six remaining issues were identified that were NOT covered by the 2026-08-06 plan:

1. **Key mismatches in HTML renderer** — `render_consolidated_report.py` reads `total`, `input`, `output`, `reasoning` from model/agent/cross-tab data, but `merge.py` produces `total_tokens_raw`, `input_tokens_raw`, `output_tokens_raw`, `reasoning_tokens_raw`. This causes **silent zero display** in the models table, agents table, and cross-tab.

2. **Cache lookup key normalization mismatch** — `_cache_lookups()` normalizes model names with `.replace('_', '-')` but the model IDs from the database may contain underscores, causing cache lookups to fail silently.

3. **No key validation between producer and consumer** — there is no schema validation, assertion checks, or contract tests verifying that keys produced by `merge.py` match what `render_consolidated_report.py` and `charts.py` expect.

4. **Date range discrepancy** — `meta.since` in the JSON report reflects the query filter range, not the true project start date. Legacy sessions (NULL model/agent) from May 2026 are excluded when users pass `--since 2026-07-01` or similar.

5. **SQL injection risk in legacy `estimate_cache.py`** — the standalone script uses string interpolation for SQL WHERE clauses. It has been superseded by `queries/cache_estimate.py` but is still executable.

6. **UX: Missing raw vs effective tokens explanation** — the HTML report displays "Raw Tokens" and "Effective Tokens" without any tooltip or legend explaining what these terms mean.

### Key Discoveries:

- **`render_consolidated_report.py:140`** — `d.get('total', 0)` reads from ModelRow which has `total_tokens_raw`, not `total` — **silent zero**
- **`render_consolidated_report.py:153-155`** — `d.get('input', 0)`, `d.get('output', 0)`, `d.get('reasoning', 0)` — same mismatch
- **`render_consolidated_report.py:195`** — agents section: `d.get('total', 0)` vs `total_tokens_raw`
- **`render_consolidated_report.py:230`** — cross-tab: `d.get('total', 0)` vs `total_tokens_raw`
- **`render_consolidated_report.py:806`** — cache lookup key normalization: `.replace('_', '-').replace('-', '-')[:30]`
- **`estimate_cache.py:51-60`** — `build_where()` uses f-string SQL interpolation for project, since, until
- **`render_consolidated_report.py:91-92`** — metric cards for raw/effective tokens have no `title` tooltip
- **No test file** covers key alignment between merge.py output and render_consolidated_report.py consumption
- **`test_phase4.py`** uses hand-crafted minimal dicts that do NOT match actual query output format

## Desired End State

After this plan is complete:
- Models table, agents table, and cross-tab in the HTML report display **correct token counts** (not zeros)
- Cache lookups work correctly for all model name formats (with or without underscores)
- A key validation test catches mismatches between merge.py output and renderer expectations
- `meta.since` and `meta.until` reflect the **true project date range** (including legacy sessions)
- Legacy `estimate_cache.py` is either hardened with parameterized queries or deprecated with a clear notice
- HTML report includes tooltips on raw/effective token cards and a legend explaining the distinction

### Verification:
- Regenerate CollageMaker report: models table shows non-zero token counts
- Regenerate CollageMaker report: agents table shows non-zero token counts
- Regenerate CollageMaker report: cross-tab shows non-zero token counts
- `meta.since` shows the earliest session date in the database for the project, not the query filter
- `python3 -m pytest tests/` passes including new key alignment test
- HTML report: hovering on "Raw Tokens" and "Effective Tokens" shows explanatory tooltips

## What We're NOT Doing

- **Not rewriting the two rendering paths into one** — the JSON output path and HTML rendering path serve different purposes (programmatic access vs. visual display); alignment is sufficient
- **Not adding runtime schema validation** — adding a runtime validator (e.g., pydantic) would be a significant architectural change; a contract test is the pragmatic approach
- **Not deleting `estimate_cache.py`** — it may still be useful as a standalone tool; hardening or deprecating is sufficient
- **Not adding per-agent daily session counts to the database** — this would require schema changes to opencode; the token-ratio estimation remains the best available approach
- **Not fixing the flat-rate vs per-model cost inconsistency** — both are intentionally provided as different estimation approaches (covered by previous plan)

## Implementation Approach

Four phases, ordered by impact:
1. **Key alignment fixes** — fix the silent-zero bug in the HTML renderer (highest impact: broken data display)
2. **Key validation test** — add a contract test to prevent future mismatches
3. **Date range and legacy sessions** — fix `meta.since`/`meta.until` to reflect true project range
4. **Security and UX polish** — harden legacy SQL, add tooltips and legend

---

## Phase 1: Key Alignment Fixes

### Overview
Fix the key mismatches in `render_consolidated_report.py` that cause the models table, agents table, and cross-tab to display zeros instead of actual token counts. This is the highest-impact fix because it directly affects the accuracy of the rendered report.

### Behavior Specifications

### Scenario: Models table displays correct token counts

**Given** the merge.py output contains ModelRow data with keys `total_tokens_raw`, `input_tokens_raw`, `output_tokens_raw`, `reasoning_tokens_raw`
**When** `build_models_section()` renders the models table
**Then** each row displays the correct token counts from the matching keys

| # | Given | When | Then |
|---|-------|------|------|
| 1.1.1 | ModelRow has `total_tokens_raw: 575422469` | `build_models_section()` renders the row | Total column shows `575,422,469` (not `0`) |
| 1.1.2 | ModelRow has `input_tokens_raw: 570959258` | `build_models_section()` renders the row | Input column shows `570,959,258` (not `0`) |
| 1.1.3 | ModelRow has `output_tokens_raw: 3332704` | `build_models_section()` renders the row | Output column shows `3,332,704` (not `0`) |
| 1.1.4 | ModelRow has `reasoning_tokens_raw: 1130507` | `build_models_section()` renders the row | Reasoning column shows `1,130,507` (not `0`) |

### Scenario: Agents table displays correct token counts

**Given** the merge.py output contains AgentRow data with keys `total_tokens_raw`
**When** `build_agents_section()` renders the agents table
**Then** each row displays the correct total token count

| # | Given | When | Then |
|---|-------|------|------|
| 1.2.1 | AgentRow has `total_tokens_raw: 288000000` | `build_agents_section()` renders the row | Total column shows `288,000,000` (not `0`) |

### Scenario: Cross-tab displays correct token counts

**Given** the merge.py output contains CrossTabRow data with keys `total_tokens_raw`
**When** `build_cross_tab()` renders the cross-tabulation table
**Then** each cell displays the correct token count

| # | Given | When | Then |
|---|-------|------|------|
| 1.3.1 | CrossTabRow has `total_tokens_raw: 575422469` | `build_cross_tab()` renders the cell | Cell shows `575,422,469` (not `0`) |

### Scenario: Cache lookups work for models with underscores

**Given** a model ID like `qwen/qwen3.6-27b` (no underscores) and another like `some_model_v2` (with underscores)
**When** `_cache_lookups()` normalizes model names for cache lookups
**Then** both model IDs produce consistent keys that match the cache estimate data

| # | Given | When | Then |
|---|-------|------|------|
| 1.4.1 | Model ID `qwen/qwen3.6-27b` | normalization applied | Key matches cache estimate key |
| 1.4.2 | Model ID `some_model_v2` | normalization applied | Key matches cache estimate key |

### Changes Required:

#### 1. Fix `build_models_section()` key access
**File**: `script/render_consolidated_report.py` lines 123-178

**Current (broken):**
```python
# Line 140
d.get('total', 0)
# Line 153
d.get('input', 0)
# Line 154
d.get('output', 0)
# Line 155
d.get('reasoning', 0)
```

**Fix:** Use the correct keys from ModelRow:
```python
# Line 140
d.get('total_tokens_raw', 0)
# Line 153
d.get('input_tokens_raw', 0)
# Line 154
d.get('output_tokens_raw', 0)
# Line 155
d.get('reasoning_tokens_raw', 0)
```

#### 2. Fix `build_agents_section()` key access
**File**: `script/render_consolidated_report.py` lines 181-217

**Current (broken):**
```python
# Line 195
d.get('total', 0)
```

**Fix:**
```python
# Line 195
d.get('total_tokens_raw', 0)
```

#### 3. Fix `build_cross_tab()` key access
**File**: `script/render_consolidated_report.py` lines 220-233

**Current (broken):**
```python
# Line 230
d.get('total', 0)
```

**Fix:**
```python
# Line 230
d.get('total_tokens_raw', 0)
```

#### 4. Fix cache lookup key normalization
**File**: `script/render_consolidated_report.py` lines 799-828

**Current (risky):**
```python
# Line 806
key = model_name.replace('_', '-').replace('-', '-')[:30]
```

**Fix:** Use the raw model ID as the key, matching what `cache_estimate.py` produces:
```python
# Use the model ID directly as the lookup key
key = model_name[:30]  # Truncate only for safety, no normalization
```

Alternatively, if normalization is needed for chart display, use a separate display key:
```python
key = model_name  # Raw model ID for cache lookup
display_key = model_name.replace('_', '-').replace('-', '')[30]  # For chart labels only
```

### Success Criteria:

#### Automated Verification:
- [ ] `python3 -m pytest tests/` passes (all existing tests)
- [ ] Test: `build_models_section()` with ModelRow data renders non-zero totals
- [ ] Test: `build_agents_section()` with AgentRow data renders non-zero totals
- [ ] Test: `build_cross_tab()` with CrossTabRow data renders non-zero cells
- [ ] Test: `_cache_lookups()` produces consistent keys for model IDs with underscores
- [ ] Regenerate CollageMaker report: models table shows correct token counts

#### Manual Verification:
- [ ] Open HTML report: models table displays non-zero token values
- [ ] Open HTML report: agents table displays non-zero token values
- [ ] Open HTML report: cross-tab displays non-zero values
- [ ] Verify token counts in tables match JSON data file values

---

## Phase 2: Key Validation Contract Test

### Overview
Add a test that verifies key alignment between `merge.py` output and `render_consolidated_report.py` / `charts.py` consumption. This prevents future regressions where a key rename in one module silently breaks the other.

### Behavior Specifications

### Scenario: Contract test catches key mismatches

**Given** the merge.py output contains a set of required keys for each data section
**When** the contract test runs
**Then** it fails if any required key is missing from the output

| # | Given | When | Then |
|---|-------|------|------|
| 2.1.1 | merge.py output has `total_tokens_raw` in models | contract test checks for `total_tokens_raw` | Test passes |
| 2.1.2 | merge.py output is missing `total_tokens_raw` in models | contract test checks for `total_tokens_raw` | Test fails with clear error |
| 2.1.3 | merge.py output has `total_effective` in timeseries | contract test checks for `total_effective` | Test passes |
| 2.1.4 | renderer expects `total` but merge.py produces `total_tokens_raw` | contract test cross-references both | Test fails with mismatch details |

### Changes Required:

#### 1. Add contract test file
**File**: `tests/test_key_alignment.py` (new)

**Approach:** Define the expected keys for each data section, then verify that:
1. `merge.py` output contains all expected keys
2. `render_consolidated_report.py` reads only keys that exist in the merge.py output
3. `charts.py` reads only keys that exist in the merge.py output

```python
"""Contract test: verify key alignment between merge.py output and consumers.

This test prevents silent failures where a key rename in merge.py
causes render_consolidated_report.py or charts.py to read wrong values.
"""

# Expected keys by section
MODELS_KEYS = {'model', 'sessions', 'total_tokens_raw', 'input_tokens_raw', 'output_tokens_raw', 'reasoning_tokens_raw'}
AGENTS_KEYS = {'agent', 'sessions', 'total_tokens_raw', 'input_tokens_raw', 'output_tokens_raw', 'reasoning_tokens_raw'}
CROSSTAB_KEYS = {'model', 'agent', 'sessions', 'total_tokens_raw'}
TIMESERIES_KEYS = {'date', 'sessions', 'total_tokens_raw', 'total_effective', 'build_tok', 'review_tok', 'plan_tok', 'explore_tok', 'other_tok', ...}
TOP_SESSIONS_KEYS = {'session_id', 'title', 'model', 'agent', 'created', 'tokens', 'input_tokens', 'output_tokens', 'reasoning_tokens'}

def test_models_keys_exist_in_merge_output():
    """Verify merge.py produces all expected model keys."""
    # Load actual merge output or use a representative sample
    ...

def test_renderer_only_reads_existing_keys():
    """Verify render_consolidated_report.py only accesses keys that merge.py produces."""
    # Parse render_consolidated_report.py for d.get('key', ...) calls
    # Cross-reference against expected keys
    ...
```

**Alternative approach (simpler):** Use a representative JSON output from a real report generation and verify all expected keys exist:

```python
def test_merge_output_has_all_expected_keys():
    """Load a real report JSON and verify all expected keys exist."""
    import json
    with open('test_fixtures/sample_report.json') as f:
        data = json.load(f)

    # Check top-level keys
    for key in ['meta', 'summary', 'models', 'agents', 'timeseries', ...]:
        assert key in data, f"Missing top-level key: {key}"

    # Check models keys
    for model in data.get('models', []):
        for key in MODELS_KEYS:
            assert key in model, f"Missing model key: {key} in {model.get('model', 'unknown')}"

    # Check agents keys
    for agent in data.get('agents', []):
        for key in AGENTS_KEYS:
            assert key in agent, f"Missing agent key: {key} in {agent.get('agent', 'unknown')}"
```

#### 2. Add sample report fixture
**File**: `tests/test_fixtures/sample_report.json` (new)

Generate a real report JSON for the CollageMaker project and save it as a test fixture. This ensures the contract test uses realistic data.

### Success Criteria:

#### Automated Verification:
- [ ] `python3 -m pytest tests/test_key_alignment.py` passes
- [ ] Test fails when a required key is removed from the fixture
- [ ] Test fails when a new key is added to merge.py but not to the expected keys set
- [ ] All existing tests still pass

#### Manual Verification:
- [ ] N/A — this is purely an automated safeguard

---

## Phase 3: Date Range and Legacy Sessions

### Overview
Fix the `meta.since` and `meta.until` values in the JSON report to reflect the true project date range (including legacy sessions) rather than the query filter range. This ensures the report metadata accurately represents the project's full history.

### Behavior Specifications

### Scenario: Meta date range reflects true project history

**Given** a project has sessions dating from 2026-05-10 to 2026-08-04
**When** a report is generated with `--since 2026-07-01`
**Then** `meta.since` shows `2026-05-10` (true project start) and `meta.until` shows `2026-08-04` (true project end)

| # | Given | When | Then |
|---|-------|------|------|
| 3.1.1 | Project has sessions from 2026-05-10 to 2026-08-04 | Report generated with `--since 2026-07-01` | `meta.since` = `2026-05-10` |
| 3.1.2 | Project has sessions from 2026-05-10 to 2026-08-04 | Report generated with `--since 2026-07-01` | `meta.until` = `2026-08-04` |
| 3.1.3 | Project has sessions from 2026-05-10 to 2026-08-04 | Report generated with no date filter | `meta.since` = `2026-05-10` |
| 3.1.4 | Project has sessions from 2026-05-10 to 2026-08-04 | Report generated with `--until 2026-07-15` | `meta.until` = `2026-08-04` (true end, not filter end) |

### Scenario: Legacy sessions are counted but flagged

**Given** a project has 307 legacy sessions (NULL model/agent) from May 2026
**When** a report is generated covering the full date range
**Then** legacy sessions are included in session counts but flagged in the warnings array

| # | Given | When | Then |
|---|-------|------|------|
| 3.2.1 | 307 legacy sessions with NULL model | Report generated | Session count includes legacy sessions |
| 3.2.2 | 307 legacy sessions with NULL model | Report generated | Warnings array notes legacy session count |
| 3.2.3 | Legacy sessions have 0 tokens | Report generated | Legacy sessions counted but not inflating token totals |

### Changes Required:

#### 1. Add true project date range query
**File**: `script/queries/summary.py` — add a new query or modify existing

**Approach:** Add a separate query that retrieves the true project date range (ignoring the date filter) and include it in the meta output:

```python
def fetch_project_range(project: Optional[str]) -> dict:
    """Fetch the true project date range (ignoring date filters).

    Returns the earliest and latest session dates for the project,
    including legacy sessions with NULL model/agent.
    """
    where, params = _build_where(project)
    sql = f"""
    SELECT
        MIN(strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')) as project_since,
        MAX(strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')) as project_until,
        COUNT(*) as total_sessions_all_time
    FROM session
    WHERE {where}
    """
    return fetch_one(sql, params)
```

#### 2. Update merge.py to include project range in meta
**File**: `script/aggregator/merge.py` lines 116-121

**Current:**
```python
'meta': {
    'title': ...,
    'since': summary.get('earliest', ''),   # Query-filtered range
    'until': summary.get('latest', ''),     # Query-filtered range
    'generated': date.today().isoformat(),
},
```

**Fix:**
```python
# Fetch true project range
project_range = fetch_project_range(project)

'meta': {
    'title': ...,
    'since': summary.get('earliest', ''),           # Query-filtered range (for data)
    'until': summary.get('latest', ''),             # Query-filtered range (for data)
    'project_since': project_range.get('project_since', ''),  # True project start
    'project_until': project_range.get('project_until', ''),  # True project end
    'total_sessions_all_time': project_range.get('total_sessions_all_time', 0),
    'generated': date.today().isoformat(),
},
```

#### 3. Update HTML renderer to display project range
**File**: `script/render_consolidated_report.py` line 107

**Current:**
```python
Period: {earliest} to {latest}
```

**Fix:**
```python
# If project range differs from query range, show both
if meta.get('project_since') and meta.get('project_since') != meta.get('since'):
    subtitle = f"Period: {meta['since']} to {meta['until']} (project started {meta['project_since']}, {meta.get('total_sessions_all_time', 0)} all-time sessions)"
else:
    subtitle = f"Period: {earliest} to {latest}"
```

#### 4. Add legacy session warning
**File**: `script/aggregator/merge.py` — in `_validate_models()` or new function

**Fix:** Count legacy sessions (NULL model) and add a warning:

```python
def _count_legacy_sessions(project: Optional[str]) -> int:
    """Count sessions with NULL model for the project."""
    where, params = _build_where(project)
    sql = f"SELECT COUNT(*) FROM session WHERE {where} AND model IS NULL"
    result = fetch_one(sql, params)
    return result.get('count', 0) or 0
```

Add to warnings:
```python
legacy_count = _count_legacy_sessions(project)
if legacy_count > 0:
    warnings.append(f"{legacy_count} legacy sessions with NULL model/agent are included in counts")
```

### Success Criteria:

#### Automated Verification:
- [ ] `python3 -m pytest tests/` passes
- [ ] Test: `meta.project_since` reflects earliest session date regardless of query filter
- [ ] Test: `meta.project_until` reflects latest session date regardless of query filter
- [ ] Test: Legacy session count is included in warnings when > 0
- [ ] Regenerate CollageMaker report: `meta.project_since` = `2026-05-10`

#### Manual Verification:
- [ ] Open HTML report: subtitle shows project start date when it differs from query range
- [ ] Open JSON report: `meta.project_since` and `meta.project_until` are populated
- [ ] JSON report: warnings array mentions legacy session count

---

## Phase 4: Security Hardening and UX Polish

### Overview
Harden the legacy `estimate_cache.py` script against SQL injection and add UX improvements to the HTML report for better user understanding of raw vs effective tokens.

### Behavior Specifications

### Scenario: estimate_cache.py rejects malicious input

**Given** a user passes a project name containing SQL injection characters
**When** `build_where()` constructs the WHERE clause
**Then** the input is sanitized or the query uses parameterized placeholders

| # | Given | When | Then |
|---|-------|------|------|
| 4.1.1 | project = `'; DROP TABLE session; --` | `build_where()` called | Input is sanitized or rejected |
| 4.1.2 | since = `2026-01-01' OR '1'='1` | `build_where()` called | Input is validated as date or rejected |
| 4.1.3 | until = `2026-12-31' UNION SELECT * FROM session --` | `build_where()` called | Input is validated as date or rejected |
| 4.1.4 | project = `CollageMaker` (normal input) | `build_where()` called | Query works normally |

### Scenario: HTML report explains raw vs effective tokens

**Given** a user opens the HTML report
**When** they hover over the "Raw Tokens" or "Effective Tokens" metric card
**Then** a tooltip explains what the metric means

| # | Given | When | Then |
|---|-------|------|------|
| 4.2.1 | User views summary cards | Hover over "Raw Tokens" card | Tooltip shows explanation |
| 4.2.2 | User views summary cards | Hover over "Effective Tokens" card | Tooltip shows explanation |
| 4.2.3 | User views summary cards | No hover | Cards display normally |

### Changes Required:

#### 1. Harden `estimate_cache.py` build_where()
**File**: `script/estimate_cache.py` lines 51-60

**Approach A (preferred): Replace with parameterized queries**

Since `estimate_cache.py` uses `subprocess.run(['opencode', 'db', sql, '--format', 'json'])`, we can't use `?` parameters directly. Instead, sanitize inputs:

```python
import re

def _validate_date(value: str) -> str:
    """Validate that value is a YYYY-MM-DD date string."""
    if not re.match(r'^\d{4}-\d{2}-\d{2}$', value):
        raise ValueError(f"Invalid date format: {value!r}. Expected YYYY-MM-DD.")
    return value

def _sanitize_like(value: str) -> str:
    """Escape special LIKE characters to prevent injection."""
    return value.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_')

def build_where(project=None, since=None, until=None):
    """Build WHERE clause from filter arguments with input validation."""
    parts = []
    if project:
        safe_project = _sanitize_like(project)
        parts.append(f"directory LIKE '%{safe_project}%'")
    if since:
        safe_since = _validate_date(since)
        parts.append(f"strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= '{safe_since}'")
    if until:
        safe_until = _validate_date(until)
        parts.append(f"strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= '{safe_until}'")
    return ' AND '.join(parts) if parts else '1=1'
```

**Approach B (alternative): Deprecate with notice**

Add a deprecation warning at the top of `estimate_cache.py`:

```python
import warnings
warnings.warn(
    "estimate_cache.py is deprecated. Use 'queries/cache_estimate.py' instead, "
    "which uses parameterized queries.",
    DeprecationWarning,
    stacklevel=2
)
```

#### 2. Add raw vs effective tokens tooltips
**File**: `script/render_consolidated_report.py` lines 91-92

**Current:**
```html
<div class="metric-card"><div class="metric-value">{fmt(effective)}</div><div class="metric-label">Effective Tokens</div></div>
<div class="metric-card"><div class="metric-value">{fmt(raw_total)}</div><div class="metric-label">Raw Tokens</div></div>
```

**Fix:**
```html
<div class="metric-card" title="Estimated tokens after prefix caching: only truly new input tokens + output + reasoning. Shows what you would pay if the provider supported prompt caching.">
    <div class="metric-value">{fmt(effective)}</div>
    <div class="metric-label">Effective Tokens</div>
</div>
<div class="metric-card" title="Total tokens as recorded by opencode: input + output + reasoning. Includes redundant context re-sent each turn in multi-turn sessions.">
    <div class="metric-value">{fmt(raw_total)}</div>
    <div class="metric-label">Raw Tokens</div>
</div>
```

#### 3. Add raw vs effective tokens legend
**File**: `script/render_consolidated_report.py` — after the metrics grid (after line 104)

**Fix:** Add a short explanatory paragraph:

```html
<div class="metrics-legend" style="font-size: 0.85em; color: var(--text-muted); margin-top: 0.5rem; text-align: center;">
    <strong>Effective Tokens</strong> = uncached input + output + reasoning (truly new work).
    <strong>Raw Tokens</strong> = all tokens including redundant context re-sent each turn.
    The difference represents estimated prefix caching savings.
</div>
```

### Success Criteria:

#### Automated Verification:
- [ ] `python3 -m pytest tests/` passes
- [ ] Test: `build_where()` raises ValueError for invalid date format
- [ ] Test: `build_where()` escapes `%` and `_` in project names
- [ ] Test: `build_where()` accepts valid project names and dates
- [ ] Test: HTML output contains `title` attribute on raw tokens card
- [ ] Test: HTML output contains `title` attribute on effective tokens card
- [ ] Test: HTML output contains legend text explaining raw vs effective

#### Manual Verification:
- [ ] Run `estimate_cache.py --project "'; DROP TABLE session; --"` — should error or sanitize
- [ ] Open HTML report: hover on "Raw Tokens" shows tooltip
- [ ] Open HTML report: hover on "Effective Tokens" shows tooltip
- [ ] Open HTML report: legend text is visible below the metric cards

---

## Testing Strategy

### Unit Tests:

| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.1.1 | build_models_section with ModelRow | `total_tokens_raw: 575422469` | Renders `575,422,469` |
| 1.1.2 | build_agents_section with AgentRow | `total_tokens_raw: 288000000` | Renders `288,000,000` |
| 1.1.3 | build_cross_tab with CrossTabRow | `total_tokens_raw: 575422469` | Renders `575,422,469` |
| 1.4.1 | cache_lookups key normalization | `qwen/qwen3.6-27b` | Key matches without normalization |
| 1.4.2 | cache_lookups key normalization | `some_model_v2` | Key matches without normalization |
| 2.1.1 | key_alignment models keys | Real merge.py output | All MODELS_KEYS present |
| 2.1.2 | key_alignment agents keys | Real merge.py output | All AGENTS_KEYS present |
| 2.1.3 | key_alignment timeseries keys | Real merge.py output | All TIMESERIES_KEYS present |
| 3.1.1 | project_range query | Project with sessions since 2026-05-10 | `project_since` = `2026-05-10` |
| 3.1.2 | legacy session count | 307 NULL model sessions | Warning includes count |
| 4.1.1 | build_where SQL injection | `'; DROP TABLE session; --` | ValueError or sanitized |
| 4.1.2 | build_where date validation | `not-a-date` | ValueError |
| 4.1.3 | build_where valid input | `CollageMaker`, `2026-01-01` | Valid SQL clause |
| 4.2.1 | HTML tooltip on raw tokens | Rendered HTML | `title` attribute present |
| 4.2.2 | HTML tooltip on effective tokens | Rendered HTML | `title` attribute present |
| 4.2.3 | HTML legend text | Rendered HTML | Legend paragraph present |

### Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | 1.1.1, 1.1.2, 1.1.3 | Core data accuracy — tables show zeros instead of real numbers |
| **P0** | 4.1.1, 4.1.2 | Security — SQL injection vulnerability |
| **P1** | 2.1.1, 2.1.2, 2.1.3 | Contract safety — prevents future key mismatches |
| **P1** | 3.1.1, 3.1.2 | Data integrity — accurate project date range |
| **P1** | 1.4.1, 1.4.2 | Cache lookup correctness |
| **P2** | 4.2.1, 4.2.2, 4.2.3 | UX polish — tooltips and legend |

### Integration Test:
- [ ] Regenerate full CollageMaker report after all phases — verify all tables show correct numbers, meta shows project range, and tooltips render

## Performance Considerations

- **Phase 1 key fixes**: Zero performance impact — only changing dictionary key names
- **Phase 2 contract test**: Adds one test file; negligible runtime impact
- **Phase 3 project range query**: Adds one additional SQL query per report generation — negligible (single MIN/MAX query)
- **Phase 4 input validation**: Adds regex validation and string escaping — negligible overhead for CLI tool
- **Phase 4 tooltips**: Pure HTML/CSS changes — zero runtime impact

## Migration Notes

- **Phase 1 key fixes**: Breaking change for any custom consumers that relied on the incorrect keys (`total`, `input`, etc.). The correct keys (`total_tokens_raw`, etc.) match the TypedDict definitions.
- **Phase 2 contract test**: Additive — no changes to production code
- **Phase 3 meta fields**: Additive — new keys `project_since`, `project_until`, `total_sessions_all_time` are added to `meta`; existing consumers that don't read them will not break
- **Phase 4 SQL hardening**: Breaking change for `estimate_cache.py` callers that pass invalid date formats — they will now get a `ValueError` instead of silently producing incorrect SQL
- **Phase 4 tooltips**: Additive HTML — no breaking changes

## References

- World-review findings: `_agent_docs/project-timeline.md/project-timeline.md` (2026-08-08 entry)
- Previous bug fixes plan: `_agent_docs/plans/2026-08-06-analytics-skill-bug-fixes.md`
- SKILL.md gotchas: `.opencode/skills/analyzing-opencode-usage/SKILL.md`
- Data types: `script/data_access/types.py` (ModelRow, AgentRow, CrossTabRow, TopSessionRow)
- Render functions: `script/render_consolidated_report.py` (build_models_section, build_agents_section, build_cross_tab, build_summary_cards)
- Cache estimation: `script/estimate_cache.py` (legacy), `script/queries/cache_estimate.py` (current)
- Key mismatch evidence: Research findings from 2026-08-08 exploration task
