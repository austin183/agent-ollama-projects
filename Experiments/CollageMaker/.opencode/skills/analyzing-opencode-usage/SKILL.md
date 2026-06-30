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
bash .opencode/skills/analyzing-opencode-usage/script/analytics.sh --project CollageMaker --month --models --agents

# JSON output for programmatic use
bash .opencode/skills/analyzing-opencode-usage/script/analytics.sh --summary --models --json
```

## Workflows

### Generate HTML Report

Produces a self-contained HTML report with charts, tables, and code impact metrics.

```bash
# Last 30 days (default)
bash .opencode/skills/analyzing-opencode-usage/script/generate_llm_report.sh

# Custom range or output location
bash .opencode/skills/analyzing-opencode-usage/script/generate_llm_report.sh \
  --days 7 --output /tmp/report.html

# With daily activity data companion file
bash .opencode/skills/analyzing-opencode-usage/script/generate_llm_report.sh \
  --days 30 --activity
```

**Output:** HTML report at the specified path, plus `*-daily-data.json` when `--activity` is used. The JSON contains per-day token counts, commit SHAs with full messages, and session file references for use by the activity summary workflow below.

### Generate Daily Activity Summary

Agent-driven workflow that produces a human-readable daily activity markdown from the report data:

1. Run `generate_llm_report.sh --activity` to produce `daily-data.json` (see above)
2. Read `daily-data.json` for the date range, per-day token counts, and session file references
3. For each day with commits, read the referenced session files from `_agent_docs/project-timeline/sessions/`
4. Follow `references/activity-template.md` to structure the summary (overview paragraph + per-day sections)
5. Output to `<date-range>-collagemaker-daily-activity-summary.md` alongside the HTML report

The activity template specifies including total tokens broken down by type, session counts, commit SHAs with full messages, and a narrative overview of what was accomplished each day.

### Generate Token Value Analysis Report

Produces a comprehensive HTML report combining token consumption with code output metrics (commits, lines added, test ratios, efficiency curves).

```bash
# Last 30 days for CollageMaker (default)
bash .opencode/skills/analyzing-opencode-usage/script/generate_value_report.sh

# Custom project and date range
bash .opencode/skills/analyzing-opencode-usage/script/generate_value_report.sh \
  --project MyProject --output /tmp/value-report.json

# Regenerate HTML from existing JSON data
python3 .opencode/skills/analyzing-opencode-usage/script/render_value_report.py < value-report-data.json > token-value-report.html
```

**Output:** `value-report-data.json` (merged DB + git data) and optionally the rendered HTML. The report includes cumulative efficiency curves, cumulative cost estimates (low/high tiers), agent-stacked daily breakdowns, rolling tokens-per-commit trends, test ratio over time, commit efficiency rankings, and agent context efficiency tables. Cost estimates use two tiers: cheap ($0.05/M input, $0.15/M output) and expensive ($0.50/M input, $1.50/M output).

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
| `summary_files` | integer | Files changed in session |
| `summary_additions` | integer | Lines added |
| `summary_deletions` | integer | Lines deleted |
| `time_created` | integer | Milliseconds since epoch |
| `title` | text | Session title |

## Gotchas

- **`time_created` is milliseconds** — divide by 1000 before `unixepoch`, or multiply epoch seconds by 1000 for comparisons
- **`model` is JSON** — use `json_extract(model, '$.id')` to get the model name; grouping by raw `model` splits on variant fields (providerID differences, legacy formats without prefix)
- **Duplicate model entries** — even after `json_extract`, slight JSON variations can cause duplicates. Aggregate by extracted ID before grouping: GROUP BY then SUM aggregates afterward
- **Legacy sessions** — 307+ sessions have `NULL` model and agent (pre-schema); handle with `COALESCE` or `WHERE model IS NOT NULL`
- **No user prompts stored** — the `session_input` table is empty; only session titles are available for context
- **`opencode stats` is all-time only** — use `opencode db` for any filtered analysis

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

**`references/report.html`** — Self-contained HTML report template with charts, tables, and code impact metrics. Filled by `generate_llm_report.sh`.

**`references/activity-template.md`** — Structure for daily activity summaries from `daily-data.json`: overview paragraph, token breakdowns, session counts, and commit SHAs per day.

**`references/session-summary.json`** — JSON template for session summary files. Used by `validate_summaries.sh` to check structural validity. Agents should copy this template at the end of each session and fill in all fields before writing to `_agent_docs/project-timeline/sessions/`.
