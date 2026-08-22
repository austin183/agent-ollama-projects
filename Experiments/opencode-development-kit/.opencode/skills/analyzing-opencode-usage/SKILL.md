---
name: analyzing-opencode-usage
description: Query opencode's SQLite database for token usage analytics across projects, models, agents, and time ranges. Use when analyzing opencode session data, token consumption, model performance, project activity, or usage trends.
---

# Analyzing opencode Usage

Query opencode's SQLite database for token usage analytics. The database is a single SQLite file shared across all projects.

## Quick Start

```bash
# Locate the database
opencode db path

# All-time summary
bash .opencode/skills/analyzing-opencode-usage/script/analytics.sh

# Last 7 days by model
bash .opencode/skills/analyzing-opencode-usage/script/analytics.sh --week --models

# Specific project and date range
bash .opencode/skills/analyzing-opencode-usage/script/analytics.sh --project [ProjectName] --month --models --agents

# JSON output for programmatic use
bash .opencode/skills/analyzing-opencode-usage/script/analytics.sh --summary --models --json

# Cache-approximated token usage
bash .opencode/skills/analyzing-opencode-usage/script/analytics.sh --project [ProjectName] --cache

# Generate HTML consolidated report (last 30 days)
python3 .opencode/skills/analyzing-opencode-usage/script/generate_report.py --project . --output report.html

# Validate session summaries
bash .opencode/skills/analyzing-opencode-usage/script/validate_summaries.sh
```

## Workflows

### Generate Consolidated Report

Produces a single unified HTML report combining token analytics (LLM report) with code impact metrics (value report). **All token counts use cache-adjusted (uncached) input** to reflect realistic consumption after prefix caching. Git stats cover all tracked files, not just `.swift`.

```bash
# Last 30 days (default) — outputs HTML directly
python3 .opencode/skills/analyzing-opencode-usage/script/generate_report.py --project . --output report.html

# Custom range or output location
python3 .opencode/skills/analyzing-opencode-usage/script/generate_report.py \
  --project . --days 7 --output /tmp/report.html

# Also emit merged JSON payload for programmatic use
python3 .opencode/skills/analyzing-opencode-usage/script/generate_report.py \
  --project . --json --output data.json
```

**Output:** Self-contained HTML report at specified location. With `--json`, emits structured JSON alongside or instead of HTML. The consolidated report includes: summary cards with effective tokens and cost, token breakdowns by model and agent (cache-adjusted), daily trend chart, code impact overview with efficiency metrics, collapsible sections for cumulative curves, agent category breakdown, cache approximation, productivity stats, phase breakdown, commit efficiency rankings, agent context efficiency, and top sessions.

**Cost Analysis:** The report includes a dedicated Cost Analysis section using per-model cloud-equivalent pricing (via `model_pricing.py`). It shows actual cost ($0, all models run locally via LM Studio) alongside cloud-equivalent costs with and without prefix caching, per-model cost breakdown, cumulative cost over time, and "$X.XX saved thanks to prefix caching" in dollar amounts.

**Architecture:** Single Python script (`generate_report.py`) queries the opencode DB via read-only SQLite connections, calls cache estimate modules, extracts git data for all tracked files, merges everything into a unified JSON payload through typed aggregation, then renders HTML using `render_consolidated_report.py`.

**Collapsible section design:** Top 5 sections (Summary Cards, Token Usage by Model/Agent, Daily Trend, Code Impact Overview) are always visible. Remaining sections use `<details>` elements that collapse on load (`i >= 4`) but can be expanded by clicking the header. CSS provides smooth arrow rotation and hover feedback.

### Generate Daily Activity Summary

Agent-driven workflow that produces a human-readable daily activity markdown from report data:

1. Run `generate_report.py --json` to produce `<report-name>-data.json`
2. Read the JSON for the date range, per-day token counts, and session file references
3. For each day with commits, read the referenced session files from `[docs directory]/sessions/`
4. Follow `references/activity-template.md` to structure the summary (overview paragraph + per-day sections)
5. Output to `<date-range>-collagemaker-daily-activity-summary.md` alongside the HTML report

The activity template specifies including total tokens broken down by type, session counts, commit SHAs with full messages, and a narrative overview of what was accomplished each day.

### Validate Session Summaries

Scans session summary JSON files for structural validity against the template schema.

```bash
# Use defaults (root computed from script location)
bash .opencode/skills/analyzing-opencode-usage/script/validate_summaries.sh

# Strict mode — exit 1 if any summary has missing fields
bash .opencode/skills/analyzing-opencode-usage/script/validate_summaries.sh --strict

# Custom paths (e.g., when called from a different location)
bash .opencode/skills/analyzing-opencode-usage/script/validate_summaries.sh \
  --root /path/to/project \
  --sessions-dir /path/to/sessions \
  --template references/session-summary.json
```

**Output:** Summary counts (total, valid, invalid), missing field reports, and breakdowns by purpose/outcome/agent-role. Exit code 0 = all valid (or non-strict). Exit code 1 in `--strict` mode when any summary is invalid.

## Script Reference

Run `bash .opencode/skills/analyzing-opencode-usage/script/analytics.sh [FLAGS]`. All sections are combinable.

**Sections:**

| Flag | Output |
|------|--------|
| `--summary` (default) | Sessions, tokens, date range, counts |
| `--models` | Token usage by model (input/output/reasoning) |
| `--agents` | Token usage by agent role |
| `--model-agents` | Model × agent cross-tabulation |
| `--timeseries` | Daily token trend |
| `--weekly` | Weekly token trend |
| `--monthly` | Monthly token trend |
| `--projects` | Token usage by project directory |
| `--top-sessions <N>` | Top N sessions by token count |
| `--impact` | File change statistics |
| `--cache` | Prefix cache approximation (from per-message data) |

**Filters:**

| Flag | Effect |
|------|--------|
| `--project <pattern>` | Substring match on directory |
| `--since YYYY-MM-DD` | Start date (inclusive) |
| `--until YYYY-MM-DD` | End date (inclusive) |
| `--days <N>` | Last N days |
| `--week` | Last 7 days |
| `--month` | Last 30 days |
| `--all` | No date filter |
| `--json` | Machine-readable JSON output |

### Cache Estimation Script

The `estimate_cache.py` script analyzes per-message token data from the `message` table to estimate prefix caching impact:

```bash
# Aggregate summary (JSON)
python3 .opencode/skills/analyzing-opencode-usage/script/estimate_cache.py --project [ProjectName] --since 2026-07-01

# Human-readable text
python3 .opencode/skills/analyzing-opencode-usage/script/estimate_cache.py --project [ProjectName] --since 2026-07-01 --text

# Breakdown by model/agent/day
python3 .opencode/skills/analyzing-opencode-usage/script/estimate_cache.py --project [ProjectName] --since 2026-07-01 --by model

# Per-session detail
python3 .opencode/skills/analyzing-opencode-usage/script/estimate_cache.py --project [ProjectName] --since 2026-07-01 --sessions
```

**How it works:** Each multi-turn session re-sends growing context. By comparing each turn's input tokens against the previous turn (via `LAG()` window function), the shared prefix is estimated as cached. Only the delta is truly new. Typical cache hit rates: 70–95%.

**Options:**

| Flag | Effect |
|------|--------|
| `--by model` | Breakdown by model |
| `--by agent` | Breakdown by agent role |
| `--by day` | Breakdown by date (timeseries) |
| `--sessions` | Per-session detail |
| `--text` | Human-readable output (default: JSON) |

**JSON output structure:**

```json
{
  "aggregate": {
    "sessions": 36,
    "total_turns": 857,
    "total_input_raw": 55000000,
    "estimated_uncached_input": 4300000,
    "estimated_cached_input": 50700000,
    "cache_hit_pct": 92.1,
    "effective_total": 4900000,
    "raw_total": 55600000
  },
  "by_model": [...],
  "by_agent": [...],
  "by_day": [...],
  "sessions": [...]
}
```

### Model Pricing Script

The `model_pricing.py` module provides cloud-equivalent cost estimates for locally-run models. All models run locally via LM Studio (actual cost: $0), but this computes what they would cost through cloud APIs.

```bash
# Enrich models data with cost (standalone)
python3 .opencode/skills/analyzing-opencode-usage/script/model_pricing.py < models.json

# As a module (used internally by generate_report.py)
python3 -c "
from model_pricing import get_pricing, compute_cost, enrich_models_with_cost
pricing = get_pricing('qwen/qwen3.6-27b')  # {'input': 0.50, 'output': 1.50, 'cached_input': 0.05}
cost = compute_cost('qwen/qwen3.6-27b', 1000000, 500000, 800000)
# {'raw_cost': 1.25, 'cache_adjusted_cost': 0.89, 'cache_savings': 0.36}
"
```

**Pricing rates** (per 1M tokens): Real cloud pricing for known cloud models (GPT-4o, Claude Sonnet 4, etc.) and cloud-equivalent estimates for local models. Unknown models fall back to $0.50/M input + $1.50/M output. **These are hypothetical rates for comparison purposes only — actual local execution cost is $0.**

**Cost display in reports:**
- **Primary Y-axis** (left): Cloud-equivalent cost from per-model pricing × token counts
- **Secondary display**: Cache-adjusted cost using `estimated_uncached_input` instead of raw input
- **Annotation**: "Actual cost: $0 (all models run on local LM Studio)"
- **Cache savings**: "$X.XX saved via prompt context caching" in dollar amounts alongside percentage
- **Daily cost curves**: Use average per-token rates derived from per-model pricing. May not reflect exact model mix per day — treat as estimates.

## Direct SQL Queries

When the script isn't enough, use `opencode db` with raw SQL:

```bash
opencode db "SELECT ..." --format json
```

**Key patterns from the session table:**

- **Model normalization**: `json_extract(model, '$.id')` — the `model` column is JSON, not a plain string
- **Date conversion**: `strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')` — `time_created` is milliseconds
- **Date filtering**: `WHERE strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= '2026-06-01'`
- **Total tokens**: `tokens_input + tokens_output + tokens_reasoning`

**Common queries:**

```sql
-- Token usage by model (any time range)
SELECT
  json_extract(model, '$.id') as model,
  COUNT(*) as sessions,
  SUM(tokens_input + tokens_output + tokens_reasoning) as total
FROM session
WHERE strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= '2026-06-01'
GROUP BY json_extract(model, '$.id')
ORDER BY total DESC;

-- Daily token trend
SELECT
  strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') as day,
  COUNT(*) as sessions,
  SUM(tokens_input + tokens_output + tokens_reasoning) as total
FROM session
GROUP BY day
ORDER BY day;

-- Top sessions by token count
SELECT
  title, directory, agent,
  json_extract(model, '$.id') as model,
  tokens_input + tokens_output + tokens_reasoning as total
FROM session
ORDER BY total DESC
LIMIT 20;

-- Token usage by project
SELECT
  directory,
  COUNT(*) as sessions,
  SUM(tokens_input + tokens_output + tokens_reasoning) as total
FROM session
GROUP BY directory
ORDER BY total DESC;
```

## Schema Reference

**`session` table — key columns:**

| Column | Type | Notes |
|--------|------|-------|
| `model` | text (JSON) | `{"id":"qwen/qwen3.6-27b","providerID":"lmstudio"}` |
| `agent` | text | Role: build, explore, diff-review, planner, etc. |
| `directory` | text | Working directory for the session |
| `tokens_input` | integer | Input tokens |
| `tokens_output` | integer | Output tokens |
| `tokens_reasoning` | integer | Reasoning tokens |
| `tokens_cache_read` | integer | Cache read tokens |
| `tokens_cache_write` | integer | Cache write tokens |
| `summary_files` | integer | **Always 0** — never populated, do not use |
| `summary_additions` | integer | **Always 0** — never populated, do not use |
| `summary_deletions` | integer | **Always 0** — never populated, do not use |
| `time_created` | integer | Milliseconds since epoch |
| `title` | text | Session title |

## Gotchas

- **`time_created` is milliseconds** — divide by 1000 before `unixepoch`, or multiply epoch seconds by 1000 for comparisons
- **`model` is JSON** — use `json_extract(model, '$.id')` to get the model name; grouping by raw `model` splits on variant fields (providerID differences, legacy formats without prefix)
- **Duplicate model entries** — even after `json_extract`, slight JSON variations can cause duplicates. Aggregate by extracted ID before grouping: GROUP BY then SUM aggregates afterward
- **Legacy sessions** — 307+ sessions have `NULL` model and agent (pre-schema); handle with `COALESCE` or `WHERE model IS NOT NULL`
- **No user prompts stored** — the `session_input` table is empty; only session titles are available for context
- **`opencode stats` is all-time only** — use `opencode db` for any filtered analysis
- **`tokens_cache_read`/`tokens_cache_write` are always 0** — the DB columns exist but LM Studio doesn't populate them. Use `estimate_cache.py` for prefix cache approximation from per-message data
- **`summary_files`/`summary_additions`/`summary_deletions` are always 0** — these columns are never populated. For productivity metrics, match session dates to git commit dates instead
- **Raw vs effective token comparison trap** — with 90%+ cache hit rates, raw tokens are 10-14× effective tokens. Always compare like with like: raw vs raw, effective vs effective. Mixing produces wildly misleading numbers
- **Agent category `Total` column key mismatch** — chart tables read `total_effective`, not `total_tokens`. A one-character key mismatch causes silent zero display
- **Two rendering paths** — `generate_report.py` produces JSON, then `render_consolidated_report.py` renders HTML from the same JSON. But `charts.py` reads JSON data directly. A key mismatch in one place doesn't show in the other — validate both paths
- **Cached input values are 10-20× larger than effective tokens** — on charts they obscure the effective token lines. Keep cached values in data tables only, not on trend charts
- **Cache hit rate is a simulated estimate** — the reported cache hit rate (typically 70–95%) is computed from per-message token deltas, not actual provider cache performance. Each multi-turn session re-sends growing context; the shared prefix between consecutive turns is estimated as "cached." This is an approximation of what prefix caching would achieve, not a measurement of real caching behavior
- **Productive sessions are estimated from token ratios** — the "Build Agent Productive" metric estimates build sessions on commit dates using proportional token-ratio approximation (build tokens / total effective tokens per day). Per-agent daily session counts are not available in the database, so this is not an exact count

## Data Conventions

### Agent Naming Patterns

Agent names use prefixes with hyphenated variants. Use `LIKE` patterns, not exact matches:

| Pattern | Matches |
|---------|---------|
| `agent LIKE 'build%'` | `build`, `build-docs`, `build-test`, `build-tdd`, `build-debug`, `build-quick-work` |
| `agent LIKE 'planner%'` | `planner`, `planner-g31`, `planner-g4` |
| `agent LIKE 'solid-review%'` | `solid-review`, `solid-review-g31` |
| `agent LIKE 'diff-review%'` | `diff-review`, `diff-review-g31` |

### Effective Tokens (Primary Metric)

The meaningful measure of LLM work is **effective tokens**: uncached input + output + reasoning. Raw tokens are misleading due to 90%+ prefix cache hit rates. Use `estimate_cache.py` to compute effective tokens from per-message data.

### Git-Based Productivity

Since `summary_files` is always 0, compute productivity by matching session dates to git commit dates. Count sessions on commit dates as "sessions with changes." Typical ratio: ~40% of sessions result in commits.

## Data Validation Checklist

When building or modifying analytics queries, verify:

1. **All expected keys exist** — check merged output has every key the renderer expects (e.g., `total_effective`, `pct_productive`, `zero_change_tokens`)
2. **Agent category sums match** — per-category token sums should add up to `total_effective`
3. **TypedDict matches return mapping** — all fields in the query's return mapping must be declared in the corresponding TypedDict
4. **Key alignment across rendering paths** — verify key names are consistent between JSON output, HTML renderer, and chart functions

## Shell/JQ Gotchas

- **jq field access with dots**: Use `.["field.name"]` syntax, not `.field.name`
- **Shell escaping**: Backslashes in jq string interpolation cause shell issues; prefer Python for complex transformations
- **Nested objects**: `.[0].model` works but `..model` fails — use array indexing or Python

## Advanced Query Patterns

### Weekly model adoption timeline

```sql
SELECT 
  strftime('%Y-W%W', time_created / 1000, 'unixepoch') as week,
  json_extract(model, '$.id') as model_id,
  COUNT(*) as sessions,
  SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens
FROM session
WHERE directory LIKE '%ProjectName%'
GROUP BY week, model_id
ORDER BY week, total_tokens DESC;
```

### Model first/last used dates (adoption timeline)

```sql
SELECT 
  json_extract(model, '$.id') as model,
  MIN(strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')) as first_used,
  MAX(strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')) as last_used,
  COUNT(*) as total_sessions
FROM session
WHERE directory LIKE '%ProjectName%' AND model IS NOT NULL
GROUP BY model;
```

### Percentage breakdown per week

```sql
WITH weekly AS (
  SELECT 
    strftime('%Y-W%W', time_created / 1000, 'unixepoch') as week,
    json_extract(model, '$.id') as model_id,
    SUM(tokens_input + tokens_output + tokens_reasoning) as tokens
  FROM session
  WHERE directory LIKE '%ProjectName%'
  GROUP BY week, model_id
),
totals AS (
  SELECT week, SUM(tokens) as total FROM weekly GROUP BY week
)
SELECT w.week, w.model_id, w.tokens, 
       ROUND(w.tokens * 100.0 / t.total, 1) as pct
FROM weekly w JOIN totals t ON w.week = t.week
ORDER BY w.week, w.tokens DESC;
```

### COALESCE patterns for legacy sessions

```sql
-- Replace NULL models with "unknown" 
SELECT COALESCE(json_extract(model, '$.id'), 'unknown') as model, COUNT(*) FROM session GROUP BY 1;

-- Include legacy sessions in agent breakdown
SELECT COALESCE(agent, 'unassigned') as agent, SUM(tokens_input + tokens_output) as total FROM session GROUP BY 1;
```

## Python Post-Processing Template

For complex aggregations beyond what the script or shell can handle:

```python
import subprocess, json

# Get JSON output from opencode db
result = subprocess.run(
    ['opencode', 'db', sql_query, '--format', 'json'],
    capture_output=True, text=True
)
data = json.loads(result.stdout)

# Process and format as needed
for row in data:
    print(f"{row['week']}: {row['model_id']} ({row['pct']}%)")
```

This is more reliable than jq for multi-line output with dotted field names.

## Templates

**`./references/activity-template.md`** — Structure for daily activity summaries: overview paragraph, token breakdowns, session counts, and commit SHAs per day.

**`./references/session-summary.json`** — JSON template for session summary files. Used by `validate_summaries.sh` to check structural validity. Agents should copy this template at the end of each session and fill in all fields before writing to `[docs directory]/sessions/`.
