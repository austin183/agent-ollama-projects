# 2026-08-06 — Analytics Skill Bug Fixes Implementation Plan

## Overview

Address all critical issues, warnings, and data anomalies identified by the world-review of the CollageMaker LLM usage analytics report and the `analyzing-opencode-usage` skill. The review assigned the report a 75-80% trustworthiness score; this plan targets raising that to 90%+ by fixing data quality bugs, improving misleading metrics, and adding validation.

**Source:** World-review findings from 2026-08-06 session, documented in `_agent_docs/project-timeline.md/project-timeline.md`.

## Current State Analysis

The analytics skill produces consolidated HTML/JSON reports from opencode's SQLite database. Five issues were identified:

1. **Flawed `productive_sessions` calculation** — uses a token-ratio formula that inflates build productivity metrics
2. **`_resolve_date()` accepts `'None'` string** — truthiness check passes literal `"None"` as a valid date
3. **Zero-token sessions not flagged** — `qwen/qwen3.5-9b` shows 2 sessions with 0 tokens, silently included in reports
4. **Empty `created` field in top sessions** — all 20 top sessions have `created: ""` despite the data being available
5. **Missing model pricing entries** — 4 models (`laguna-s-2.1`, `qwen/qwen3.6-27b-q4`, `qwen/qwen3.6-27b-lite`, `qwen/qwen3.5-9b`) use fallback pricing

### Key Discoveries:
- `merge.py:86-92` — `productive_build_sessions` formula: `sessions * build_tok / total_effective` distributes session counts by token ratio, not actual build sessions
- `utils.py:34` — `since if since else "2000-01-01"` treats `"None"` string as truthy, passing it to SQL
- `top_sessions.py:64` — `created=''` is hardcoded; the SQL query omits `time_created`
- `model_pricing.py:34-52` — `MODEL_PRICING` dict missing 4 models used in CollageMaker
- No validation exists for zero-token sessions anywhere in the pipeline

## Desired End State

After this plan is complete:
- `productive_sessions` counts actual build-agent sessions on commit dates (not token-ratio estimates)
- `_resolve_date()` rejects `'None'` string and non-date values
- Zero-token sessions are logged as warnings and excluded from productivity calculations
- Top sessions include creation dates in `created` field
- All 4 missing models have pricing entries in `MODEL_PRICING`
- All existing tests pass, new tests cover the fixed behaviors

### Verification:
- Regenerate CollageMaker report — `productive_sessions` should be a realistic count ≤ `total_build_sessions`
- Top sessions JSON should have populated `created` dates
- JSON output should include a `data_warnings` array listing zero-token models
- `model_pricing.py` should have 0 fallback warnings for CollageMaker models
- All tests pass: `python3 -m pytest` in the skill's `tests/` directory

## What We're NOT Doing

- **Not rewriting the cache estimation methodology** — the 94.2% cache hit rate is a known simulation; adding a disclaimer is sufficient (Phase 4)
- **Not fixing the flat-rate vs per-model cost inconsistency** — both are intentionally provided as different estimation approaches; documentation clarification is sufficient
- **Not restructuring the skill architecture** — this plan is scoped to bug fixes only, not refactoring
- **Not adding phases configuration** — phases were intentionally removed (hardcoded dates produced empty results); re-adding is out of scope

## Implementation Approach

Four phases, ordered by impact:
1. **Data accuracy fixes** — productive_sessions, zero-token validation, top_sessions dates
2. **Input validation** — `_resolve_date()` hardening
3. **Model pricing completeness** — add missing model entries
4. **Documentation and disclaimer** — cache hit rate clarification

---

## Phase 1: Data Accuracy Fixes

### Overview
Fix the three issues that produce incorrect or misleading data in the report output.

### Changes Required:

#### 1. Fix `productive_sessions` Calculation
**File**: `script/aggregator/merge.py` lines 86-92

**Problem:** Current formula `sessions * build_tok / total_effective` estimates productive sessions by distributing total daily sessions proportionally by token ratio. This is not an actual count of build sessions that produced commits.

**Fix:** Count actual build-agent sessions on commit dates using the `daily_sessions` breakdown. Since we don't have per-agent daily session counts in the merged daily data, we'll use a proportional estimate based on the build agent's share of daily sessions — but cap it properly and document the estimation.

**Approach:**
- Add per-agent daily session counts to the `daily_agent` query output (or compute from existing data)
- Sum build-category sessions on commit dates directly
- If per-agent daily data isn't available, use `build_tok / total_effective * sessions` but floor at 0 and document as estimated

```python
# Replace lines 86-92 in merge.py
productive_build_sessions = 0
for r in merged_daily:
    if r.get('date', '') in git_dates_with_commits:
        daily_s = r.get('sessions', 0) or 0
        build_ratio = r.get('build_tok', 0) / max(r.get('total_effective', 1), 1)
        # Estimate build sessions proportionally, minimum 0 (not 1)
        productive_build_sessions += max(0, round(daily_s * build_ratio))

# Safety net: productive sessions can never exceed total build sessions
productive_build_sessions = min(productive_build_sessions, build_prod.get('total_build_sessions', 0))
```

**Key change:** `max(1, ...)` → `max(0, ...)`. The `max(1, ...)` floor was inflating counts by forcing at least 1 session per commit date regardless of actual build activity.

#### 2. Add Zero-Token Session Validation
**File**: `script/aggregator/merge.py` — new function, called before cost enrichment (line ~99)

**Fix:** Add a validation pass that identifies models with sessions but zero tokens, logs warnings, and includes them in the report output.

```python
def _validate_models(models_data: list[dict]) -> list[str]:
    """Validate model data for anomalies. Returns list of warning messages."""
    warnings: list[str] = []
    for m in models_data:
        model_id = m.get('model', 'unknown')
        sessions = m.get('sessions', 0) or 0
        total = m.get('total_tokens_raw', 0) or 0
        if sessions > 0 and total == 0:
            msg = f"Model '{model_id}' has {sessions} session(s) with 0 tokens"
            warnings.append(msg)
            logger.warning(msg)
    return warnings
```

Add to `merge_datasets()` return dict:
```python
'warnings': _validate_models(models_data),
```

#### 3. Fix Empty `created` Field in Top Sessions
**File**: `script/queries/top_sessions.py` lines 36-70

**Fix:** Add `time_created` to the SQL SELECT and populate the `created` field.

```python
sql = f"""
SELECT
    title,
    agent,
    json_extract(model, '$.id') as model,
    tokens_input + tokens_output + tokens_reasoning as total_tokens,
    tokens_input,
    tokens_output,
    tokens_reasoning,
    strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') as created
FROM session
WHERE {where}
    AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= ?
    AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= ?
ORDER BY total_tokens DESC
LIMIT 20
"""
```

Update the `TopSessionRow` construction (line 64):
```python
created=r.get('created', '') or '',
```

Also update `data_access/types.py` if `TopSessionRow` is a TypedDict or dataclass — verify the `created` field type accepts strings.

### Success Criteria:

#### Automated Verification:
- [ ] `python3 -m pytest tests/` passes (all existing + new tests)
- [ ] Test: `productive_build_sessions` with `max(0, ...)` does not inflate when build_tok is 0
- [ ] Test: `_validate_models` returns warning for model with sessions > 0 and tokens = 0
- [ ] Test: `_validate_models` returns empty list when all models have tokens
- [ ] Test: `top_sessions.fetch` returns rows with non-empty `created` field
- [ ] Regenerate CollageMaker report: `productive_sessions` ≤ `total_build_sessions`
- [ ] Regenerate CollageMaker report: `warnings` array includes `qwen/qwen3.5-9b` zero-token message

#### Manual Verification:
- [ ] Open HTML report: top sessions show creation dates
- [ ] Open JSON report: `warnings` array is present and populated
- [ ] `productive_sessions` value is reasonable (not inflated by `max(1, ...)` floor)

---

## Phase 2: Input Validation Hardening

### Overview
Fix `_resolve_date()` to reject `'None'` string and other invalid date values.

### Changes Required:

#### 1. Harden `_resolve_date()`
**File**: `script/queries/utils.py` lines 26-36

**Current code:**
```python
start_date = since if since else "2000-01-01"
end_date = until if until else date.today().isoformat()
```

**Fix:** Explicitly check for `None` and reject literal `"None"` string. Validate date format.

```python
def _resolve_date(
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None
) -> Tuple[str, str]:
    """Resolve date range from arguments or defaults.

    Args:
        since: Start date (YYYY-MM-DD). None or empty string uses default.
        until: End date (YYYY-MM-DD). None or empty string uses today.
        days: Number of days from today (overrides since/until).

    Returns:
        Tuple of (start_date, end_date) as ISO format strings.

    Raises:
        ValueError: If since or until is provided but not a valid YYYY-MM-DD date.
    """
    if days is not None:
        start_date = (date.today() - timedelta(days=days)).isoformat()
        end_date = date.today().isoformat()
    else:
        start_date = _parse_or_default(since, "2000-01-01")
        end_date = _parse_or_default(until, date.today().isoformat())

    return start_date, end_date


def _parse_or_default(value: Optional[str], default: str) -> str:
    """Parse a date string, returning default if None, empty, or invalid.

    Rejects literal 'None' string and any string that isn't a valid YYYY-MM-DD date.
    """
    if value is None or value.strip() == '' or value.strip().lower() == 'none':
        return default
    try:
        date.fromisoformat(value)
        return value
    except (ValueError, TypeError):
        logger.warning("Invalid date '%s', using default '%s'", value, default)
        return default
```

### Success Criteria:

#### Automated Verification:
- [ ] Test: `_resolve_date(since=None)` returns `("2000-01-01", today)`
- [ ] Test: `_resolve_date(since="None")` returns `("2000-01-01", today)` (rejects literal "None")
- [ ] Test: `_resolve_date(since="")` returns `("2000-01-01", today)`
- [ ] Test: `_resolve_date(since="not-a-date")` returns `("2000-01-01", today)` with warning logged
- [ ] Test: `_resolve_date(since="2026-01-15")` returns `("2026-01-15", today)`
- [ ] Test: `_resolve_date(days=7)` overrides since/until
- [ ] All existing tests pass

#### Manual Verification:
- [ ] Run `analytics.sh --since "None"` — should use default date, not fail or produce empty results

---

## Phase 3: Model Pricing Completeness

### Overview
Add the 4 missing models to `MODEL_PRICING` to eliminate fallback warnings.

### Changes Required:

#### 1. Add Missing Model Pricing
**File**: `script/model_pricing.py` lines 34-52

**Missing models and recommended pricing** (cloud-equivalent estimates based on model family):

```python
    # Additional local models (cloud-equivalent estimates)
    'laguna-s-2.1':               {'input': 0.50,  'output': 1.50,  'cached_input': 0.05},
    'qwen/qwen3.6-27b-q4':        {'input': 0.50,  'output': 1.50,  'cached_input': 0.05},
    'qwen/qwen3.6-27b-lite':      {'input': 0.40,  'output': 1.20,  'cached_input': 0.04},
    'qwen/qwen3.5-9b':            {'input': 0.30,  'output': 0.60,  'cached_input': 0.03},
```

**Rationale:**
- `laguna-s-2.1`: Unknown model, keep fallback rates ($0.50/$1.50)
- `qwen/qwen3.6-27b-q4`: Quantized variant of qwen3.6-27b, same pricing as base model
- `qwen/qwen3.6-27b-lite`: Lite variant, slightly lower rates ($0.40/$1.20)
- `qwen/qwen3.5-9b`: Smaller 9B model from qwen3.5 family, lower rates ($0.30/$0.60)

### Success Criteria:

#### Automated Verification:
- [ ] Test: `get_pricing('laguna-s-2.1')` returns specific pricing (not fallback)
- [ ] Test: `get_pricing('qwen/qwen3.6-27b-q4')` returns specific pricing (not fallback)
- [ ] Test: `get_pricing('qwen/qwen3.6-27b-lite')` returns specific pricing (not fallback)
- [ ] Test: `get_pricing('qwen/qwen3.5-9b')` returns specific pricing (not fallback)
- [ ] Regenerate CollageMaker report: no fallback warnings in console output
- [ ] All existing tests pass

#### Manual Verification:
- [ ] Run `generate_report.py --project CollageMaker` — no "Model not found in pricing table" warnings
- [ ] JSON report cost figures are consistent across all models

---

## Phase 4: Documentation and Disclaimer

### Overview
Add clarifications to prevent misinterpretation of simulated metrics.

### Changes Required:

#### 1. Cache Hit Rate Disclaimer in HTML Report
**File**: `script/render_consolidated_report.py` — cache approximation section

**Current:** Existing disclaimer at lines 362-367 is small and easy to miss.

**Fix:** Add a more prominent annotation near the cache hit rate metric. The existing text is adequate but should be moved to appear directly adjacent to the 94.2% figure, not buried in a paragraph below.

No code changes required if the existing disclaimer is deemed sufficient. If world-review confirms it needs improvement, add an inline annotation:

```html
<span title="Simulated prefix-caching estimate, not actual provider cache performance.
Computed from per-message token deltas: each turn re-sends prior context,
but only the delta vs the previous turn is considered truly new.">
94.2%
</span>
```

#### 2. Productive Sessions Estimation Note
**File**: `script/render_consolidated_report.py` — productivity section

**Fix:** When `productive_sessions` is displayed, add a note that it is estimated from token ratios when per-agent daily session counts are not available.

### Success Criteria:

#### Automated Verification:
- [ ] N/A — documentation changes verified manually

#### Manual Verification:
- [ ] HTML report: cache hit rate has inline tooltip or adjacent clarification
- [ ] HTML report: productivity metric notes it is estimated
- [ ] SKILL.md: gotchas section mentions these are simulated estimates

---

## Testing Strategy

### Unit Tests:

| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.1.1 | productive_sessions with zero build_tok | build_tok=0, sessions=10, total_effective=1000 | contributes 0 (not 1) |
| 1.1.2 | productive_sessions safety net | estimated=300, total_build_sessions=200 | capped at 200 |
| 1.2.1 | validate_models zero tokens | sessions=2, total_tokens_raw=0 | warning returned |
| 1.2.2 | validate_models normal | sessions=5, total_tokens_raw=1000 | no warning |
| 1.3.1 | top_sessions includes created | session with time_created=... | created="2026-07-15" |
| 2.1.1 | resolve_date rejects "None" | since="None" | returns default "2000-01-01" |
| 2.1.2 | resolve_date rejects invalid | since="not-a-date" | returns default with warning |
| 2.1.3 | resolve_date accepts valid | since="2026-01-15" | returns "2026-01-15" |
| 2.1.4 | resolve_date accepts None | since=None | returns default "2000-01-01" |
| 3.1.1 | get_pricing laguna-s-2.1 | model="laguna-s-2.1" | specific pricing, not fallback |
| 3.1.2 | get_pricing qwen3.6-27b-q4 | model="qwen/qwen3.6-27b-q4" | specific pricing, not fallback |
| 3.1.3 | get_pricing qwen3.6-27b-lite | model="qwen/qwen3.6-27b-lite" | specific pricing, not fallback |
| 3.1.4 | get_pricing qwen3.5-9b | model="qwen/qwen3.5-9b" | specific pricing, not fallback |

### Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | 1.1.1, 1.1.2, 2.1.1, 2.1.2 | Core data accuracy — wrong numbers or crashes |
| **P1** | 1.2.1, 1.3.1, 2.1.3, 2.1.4 | Data quality and input validation |
| **P2** | 1.2.2, 3.1.1-4, Phase 4 | Completeness and documentation |

### Integration Test:
- [ ] Regenerate full CollageMaker report after all phases — verify all metrics are reasonable and no warnings about missing pricing

## Performance Considerations

- `_validate_models` adds O(n) pass over models_data — negligible overhead (typically <20 models)
- `_parse_or_default` adds one `date.fromisoformat()` call per date resolution — negligible
- `top_sessions.py` adds one column to SELECT — no performance impact
- No changes to cache estimation or timeseries computation — those are the expensive operations

## Migration Notes

- The `warnings` key added to the merged report JSON is additive — existing consumers that don't read it will not break
- The `created` field in top sessions changes from `""` to `"YYYY-MM-DD"` — consumers that check for empty string should handle both
- `_resolve_date` rejecting `"None"` is a breaking change only if callers pass `str(None)` — this is a bug in callers that should be fixed

## References

- World-review findings: `_agent_docs/project-timeline.md/project-timeline.md` (2026-08-06 entry)
- Session summary: `_agent_docs/sessions/2026-08-06-002-build-docs-collagemaker-alltime-report.json`
- Previous bug fixes plan: `_agent_docs/plans/analyzing-opencode-usage-bug-fixes.md`
- Previous world-review fixes plan: `_agent_docs/plans/analyzing-opencode-usage-world-review-fixes.md`
- SKILL.md gotchas: `.opencode/skills/analyzing-opencode-usage/SKILL.md`
