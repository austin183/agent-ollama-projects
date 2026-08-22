# Cache Estimation Scripts — Gotchas

## `estimate_cache.py` breakdown queries guarded too narrowly

When `--by` is not specified (default `None`), all three breakdown queries should run (aggregate + model + agent + day). The outer `if` blocks correctly checked `if by == 'model' or by is None:`, but the inner `query()` calls were guarded with `if by == 'model' else []`, skipping the queries when `by is None`.

**Fix:** Change all three query guards:
```python
# Before (broken)
model_rows = query(model_sql) if by == 'model' else []
agent_rows = query(agent_sql) if by == 'agent' else []
day_rows = query(day_sql) if by == 'day' else []

# After (fixed)
model_rows = query(model_sql) if by == 'model' or by is None else []
agent_rows = query(agent_sql) if by == 'agent' or by is None else []
day_rows = query(day_sql) if by == 'day' or by is None else []
```

**Location:** `.opencode/skills/analyzing-opencode-usage/script/estimate_cache.py` lines 182, 212, 241.

## `render_report.py` requires `templates/report.html`

The report renderer uses Python's `string.Template` and loads its template from `templates/report.html` relative to the script's parent directory. This file was never created, causing `generate_llm_report.sh` to fail with "Error: Template not found".

**Fix:** Create `templates/report.html` with all placeholders from the `substitutions` dict in `render_report.py`: `$TITLE`, `$PERIOD`, `$GENERATED`, `$SUMMARY_METRICS`, `$MODELS_SECTION`, `$AGENTS_SECTION`, `$CROSSTAB_SECTION`, `$TIMESERIES_SECTION`, `$TOP_SESSIONS_SECTION`, `$CACHE_SECTION`, `$CODE_IMPACT_SECTION`, `$DAILY_ACTIVITY_LINK`.

**Location:** `.opencode/skills/analyzing-opencode-usage/templates/report.html` (new file).

## JavaScript template literals clash with Python `string.Template`

In the HTML template, JavaScript template literals like `` `${date}` `` are interpreted as Python `string.Template` placeholders. This causes "Missing placeholder in template: 'date'" errors.

**Fix:** Escape the `$` by doubling it: `` $${date} `` produces a literal `$` in the output, yielding the correct `${date}` in the rendered HTML.

**Location:** `.opencode/skills/analyzing-opencode-usage/templates/report.html` — all JavaScript template literal expressions.
