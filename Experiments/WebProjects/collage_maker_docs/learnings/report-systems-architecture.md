# Two Report Systems for opencode Token Analytics

**Created:** 2026-07-03  
**Topic:** Report generation architecture — `generate_llm_report.sh` vs `generate_value_report.sh`  

## TL;DR

There are two separate report pipelines that query the same opencode SQLite DB but use different approaches, produce overlapping sections, and output to different locations. They should be consolidated into one unified pipeline.

## The Two Pipelines

### Pipeline 1: LLM Usage Report
- **Script:** `script/generate_llm_report.sh` → `script/render_report.py`
- **Template:** `templates/report.html` (string.Template with `$PLACEHOLDER` substitution)
- **DB access:** `opencode db "SQL" --format json` CLI wrapper
- **Git data:** All files via `git log --numstat` (awk-based parsing)
- **Output:** `_agent_docs/project-timeline/llm-usage/YYYY-MM-DD-collagemaker-llm-report.html`
- **Sections:** Summary, Models stacked bars, Agents horizontal bars, Model×Agent cross-tab, Daily timeseries table, Top sessions table, Code impact (3 charts + summary table), Cache approximation tables

### Pipeline 2: Token Value Analysis Report
- **Script:** `script/generate_value_report.sh` → `script/render_value_report.py`
- **Template:** None — renders full HTML inline in Python
- **DB access:** Direct `sqlite3` CLI to `$HOME/.local/share/opencode/opencode.db`
- **Git data:** `.swift` files only via `git log --numstat` (Python parsing with SKIP_SHAS)
- **Output:** `./value-report-data.json` + `token-value-report.html` (project root, not in llm-usage/)
- **Sections:** Summary (with cost cards), Phase breakdown table, Productivity overview, Efficiency curves (cumulative tokens vs lines), Cumulative cost chart, Cache approximation, Daily agent stacked chart, Rolling tok/commit, Test ratio over time, Commit efficiency tables, Weekly agent breakdown, Agent context efficiency

## Key Architectural Differences

| Aspect | LLM Report | Value Report |
|--------|-----------|--------------|
| DB client | `opencode db` wrapper | Direct `sqlite3` |
| Git scope | All tracked files | `.swift` only |
| Template style | String.Template with placeholders | Inline HTML in Python f-strings |
| Cache data | Passed as 9th CLI arg to render script | Same — passed via JSON payload |
| Output location | `_agent_docs/project-timeline/llm-usage/` | Project root (`./`) |
| Period scope | Configurable `--days` / `--since/--until` | All-time (no date filter) |

## Data Overlap (~60%)

Both reports compute:
1. Token breakdown by model (with cache adjustment via `_cache_lookups()`)
2. Token breakdown by agent (with cache adjustment)
3. Daily token timeseries (LLM report has raw; value report has agent-category breakdown)
4. Code impact metrics from git data merged with daily tokens
5. Cache approximation section (by model, agent, day)

## Why Consolidation Makes Sense

1. **Duplicate queries**: Both run similar SQL against the same DB for summaries, models, agents, timeseries
2. **Inconsistent git scope**: Value report misses non-swift changes; LLM report gets everything but doesn't break down by file type
3. **Split output locations**: Reports land in different directories making them hard to find
4. **Different DB access patterns**: One uses `opencode db`, the other direct `sqlite3` — confusing for new agents
5. **Wasted effort**: Adding a new chart means modifying both renderers

## Consolidation Plan

See `_agent_docs/plans/consolidated-llm-value-report.md` for full design. Key decisions:
- Single script using `sqlite3` directly (faster, more consistent)
- All files for git data (not just `.swift`)
- Unified JSON payload with both raw and cache-adjusted values
- Collapsible sections for tabular detail, always-visible charts at top
- Output to `_agent_docs/project-timeline/llm-usage/YYYY-MM-DD-collagemaker-report.html`

## Gotchas Discovered

1. **Both reports use the same `charts.py`** — all SVG chart functions are shared and reusable
2. **The `_cache_lookups()` helper in `render_report.py`** is a well-designed pattern: builds lookup maps from cache estimate data keyed by model/agent/day name, used consistently across all sections to swap raw→uncached values
3. **Value report's JSON payload (`value-report-data.json`) is the more complete data structure** — it has `merged_daily` with agent categories, cumulative values, cost estimates, and git stats all in one place. This should be the canonical data model.
4. **LLM report's template approach (string.Template)** is simpler but less flexible than value report's inline Python HTML generation
5. **SKIP_SHAS in value report** filters out known bad commits — this pattern should carry over to consolidated version
