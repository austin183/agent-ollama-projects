# Consolidated LLM Usage & Value Report — Design Plan

**Created:** 2026-07-03  
**Status:** Draft  

## Overview

Combine the two existing reports (`generate_llm_report.sh` → `render_report.py` and `generate_value_report.sh` → `render_value_report.py`) into a single unified report that lives at `_agent_docs/project-timeline/llm-usage/YYYY-MM-DD-collagemaker-report.html`. The consolidated report uses cache-adjusted (uncached) input tokens throughout, shows code impact metrics alongside token usage, and provides both high-level charts and collapsible tabular detail.

## Why Consolidate

The two reports currently overlap heavily (~60% of sections are duplicated or near-duplicates):
- Both show token breakdowns by model, agent, day with cache approximation
- Both merge token data with git commit stats  
- Both include cost estimates (value report only) and productivity metrics (value report only)

The LLM report uses `opencode db` CLI; the value report uses `sqlite3` directly. The value report filters git by `.swift` files only; the LLM report gets all changes. The consolidated version should use a single data pipeline.

## Architecture

### Data Pipeline (single script: `generate_consolidated_report.sh`)

```
┌─────────────────────────────────────────────┐
│  generate_consolidated_report.sh            │
│                                             │
│  1. Query opencode DB (sessions + messages) │
│     - Daily token breakdown by agent cat    │
│     - Summary metrics                       │
│     - Model breakdown                       │
│     - Agent breakdown                       │
│     - Model × Agent cross-tab               │
│     - Top sessions                          │
│     - Weekly breakdown                      │
│     - Agent context efficiency (turns)      │
│     - Productivity stats                    │
│                                             │
│  2. estimate_cache.py (--project + range)   │
│     → by_model, by_agent, by_day cache data │
│                                             │
│  3. Git log --numstat (all files, not just  │
│     .swift — or configurable filter)        │
│     → daily aggregates + per-commit detail  │
│                                             │
│  4. Merge all into single JSON payload      │
│     → stdout or temp file                   │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│  render_consolidated_report.py              │
│                                             │
│  Reads JSON from stdin, produces HTML       │
│  Uses existing charts.py functions          │
│  New collapsible-table component            │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
  _agent_docs/project-timeline/llm-usage/
    YYYY-MM-DD-collagemaker-report.html
```

### Unified JSON Payload Structure

```json
{
  "meta": {
    "title": "CollageMaker — LLM Usage & Value Report",
    "since": "2026-07-01",
    "until": "2026-07-03",
    "generated": "2026-07-03 14:00 CDT"
  },
  
  "summary": {
    "total_sessions": 994,
    "total_tokens_raw": 1044879856,
    "total_tokens_effective": 90917251,
    "total_input_raw": 1035554342,
    "total_input_uncached": 81591737,
    "total_output": 5786155,
    "total_reasoning": 3539359,
    "cache_hit_pct": 92.1,
    "earliest": "2026-05-10",
    "latest": "2026-07-03",
    "model_count": 11,
    "agent_count": 19
  },

  "cost_summary": { ... },       // from value report
  "cache_cost_summary": { ... }, // from value report
  
  "productivity": { ... },        // from value report
  "build_productivity": { ... },  // from value report

  "models": [                     // raw session-level by model (from LLM report)
    {"model": "...", "sessions": N, "input": N, "output": N, "reasoning": N, "total": N}
  ],

  "agents": [                     // raw session-level by agent (from LLM report)
    {"agent": "...", "sessions": N, "total": N}
  ],

  "cross_tab": [...],             // model × agent (from LLM report)

  "top_sessions": [...],          // top sessions (from LLM report)

  "weekly": [...],                // weekly breakdown by agent category (from value report)

  "agent_context": [...],         // turns per session, avg input/turn (from value report)

  "timeseries": [                 // daily token breakdown
    {
      "date": "2026-07-01",
      "sessions": 5,
      "total_tokens_raw": 13609679,
      "input_raw": 13487202,
      "output": 90819,
      "reasoning": 31658,
      // Cache-adjusted (effective) values:
      "input_uncached": 965900,
      "total_effective": 1085877,
      "cache_hit_pct": 92.8,
      // Agent category breakdown:
      "build_tok": 12086692,
      "review_tok": 0,
      "plan_tok": 431709,
      "explore_tok": 0,
      "other_tok": 1091278,
      // Git/impact data:
      "commits": 2,
      "adds": 11300,
      "dels": 1,
      "test_adds": 0,
      "test_dels": 0,
      "tok_per_commit": 6804840,
      "tok_per_line": 1202
    }
  ],

  "cache_estimate": {             // full cache data (from both reports)
    "aggregate": {...},
    "by_model": [...],
    "by_agent": [...],
    "by_day": [...]
  },

  "phases": [                     // phase breakdown (from value report)
    {"name": "...", "start": "...", "end": "...", "tokens": N, ...}
  ],

  "most_efficient_commits": [...],// top 10 efficient commits (from value report)
  "least_efficient_commits": [...]// top 10 inefficient commits (from value report),

  "daily_agent_stacked": [...]    // merged_daily for agent-stacked chart (from value report)
}
```

## Report Layout

### 1. Summary Cards (always visible, top of page)

8-10 metric cards in a grid:

| Card | Value Source | Notes |
|------|-------------|-------|
| Effective Tokens | `summary.total_tokens_effective` | Cache-adjusted total (input_uncached + output + reasoning) |
| Raw Tokens | `summary.total_tokens_raw` | For comparison with effective |
| Sessions | `summary.total_sessions` | |
| Avg / Session | effective / sessions | Using cache-adjusted |
| Commits | sum of daily commits | |
| Lines Added | sum of daily adds | All files (not just .swift) |
| Est. Cost (Low, raw) | cost_summary | |
| Est. Cost (High, raw) | cost_summary | |
| Est. Cost (Low, w/cache) | cache_cost_summary | Green highlight |
| Cache Hit Rate | summary.cache_hit_pct | |

Subtitle line: period range, model count, agent count, generated timestamp.  
Cost estimate note below subtitle.

### 2. Token Usage by Model (chart — always visible)

Stacked horizontal bars showing uncached input / output / reasoning per model.  
Uses existing `build_models_section()` logic with cache-adjusted lookups.

### 3. Token Usage by Agent (chart — always visible)

Horizontal bars showing total effective tokens per agent role.

### 4. Model × Agent Breakdown (collapsible table)

Cross-tab of model × agent with sessions and effective token counts.  
Wrapped in `<details><summary>Model × Agent Breakdown</summary>...<table>...</table></details>`

### 5. Daily Token Trend (chart — always visible)

Stacked area chart showing input/output/reasoning over time using cache-adjusted values.

### 6. Code Impact Overview (charts + cards — always visible)

- **Impact cards:** Total commits, lines added, avg tokens/commit, avg tokens/line, reasoning %, peak tok/commit
- **Chart: Daily Token Breakdown** (stacked area, same as section 5 but focused on impact context)
- **Chart: Tokens vs. Commits** (dual-axis line chart)
- **Chart: Tokens per Commit vs. per Line Added** (dual-axis)

### 7. Cumulative Efficiency Curves (collapsible)

- Cumulative tokens vs. cumulative lines added (all files)
- Cumulative cost over time (low/high tiers)
- Rolling 7-day tokens per commit trend

### 8. Agent Category Breakdown (collapsible)

- Daily stacked bar chart: build / review / plan / explore / other tokens
- Weekly agent breakdown table

### 9. Cache Approximation (collapsible)

- Aggregate metrics cards (raw input, cached, uncached, hit rate, effective total, savings %)
- By model table
- By agent table
- By day table

### 10. Productivity Overview (collapsible)

- Sessions with file changes %, productive sessions count
- Build agent productivity stats
- Zero-commit high-token days note
- Notes about data limitations

### 11. Phase Breakdown (collapsible)

Table: phase name, dates, tokens, sessions, commits, lines added, test additions, tok/commit, tok/swift, test %, cost low/high.

### 12. Commit Efficiency (collapsible)

- Top 10 most efficient commits table
- Top 10 least efficient commits table

### 13. Agent Context Efficiency (collapsible)

Table: agent, sessions, total tokens, total turns, avg turns/session, avg input/turn.

### 14. Top Sessions (collapsible)

Top N sessions by effective token count with agent, model, title.

## Collapsible Section Design

```html
<details class="collapsible-section" open>
  <summary onclick="toggleDetails(this)">Section Title ▾</summary>
  <div class="collapsible-content">
    <!-- chart or table content -->
  </div>
</details>
```

- First 4 sections (Summary, Models, Agents, Daily Trend) are **always open** (`<details>` replaced with plain `<div>`)
- Remaining sections use `<details>` with `open` by default; user can collapse
- CSS for smooth transition and arrow indicator rotation
- JavaScript toggle handler

## Implementation Approach

### New Files

1. **`script/generate_consolidated_report.sh`** — Main entry point
   - Combines queries from both existing scripts into one pipeline
   - Uses `sqlite3` directly (like value report) for consistency and speed
   - Calls `estimate_cache.py` once with full range
   - Extracts git data (all files, configurable)
   - Merges everything into single JSON → stdout

2. **`script/render_consolidated_report.py`** — HTML renderer
   - Reads unified JSON from stdin
   - Imports existing `charts.py` for SVG chart generation
   - Reuses section-building logic patterns from both renderers
   - Adds collapsible-section wrapper component
   - Outputs self-contained HTML

### Modified Files

3. **`SKILL.md`** — Add new workflow: "Generate Consolidated Report"
4. **`templates/report.html`** — Add CSS for collapsible sections (or inline in renderer)

### Reuse Strategy

- **charts.py**: Already has `render_stacked_area`, `render_tokens_vs_commits`, `render_efficiency`, `render_cumulative_efficiency`, `render_cumulative_cost`, `render_daily_agent_stacked`, `render_rolling_tok_per_commit`, `render_test_ratio`, `render_context_efficiency_table` — all reusable
- **estimate_cache.py**: Same script, just pass appropriate flags
- **fmt() function**: Already in charts.py, import it

### Migration Path

1. Create the new consolidated script and renderer
2. Update SKILL.md with the new workflow alongside existing ones
3. Keep old scripts for backward compatibility (they're referenced elsewhere)
4. Eventually deprecate `generate_llm_report.sh` and `generate_value_report.sh` in favor of one command

## Key Design Decisions

1. **Cache-adjusted everywhere**: All token counts in the report use uncached input by default. Raw values shown only for comparison (summary cards show both, cache section shows raw vs cached).

2. **All files for git stats** (not just .swift): The value report filters by `.swift` which is too narrow for a web app like CollageMaker. Use all tracked files by default, with `--filter *.ext` option if needed.

3. **Single output location**: `_agent_docs/project-timeline/llm-usage/YYYY-MM-DD-collagemaker-report.html` — replaces both old report paths.

4. **No separate JSON data file in default mode**: The consolidated script outputs HTML directly. Add `--json` flag to also emit the merged JSON payload for programmatic use (like value report's `value-report-data.json`).

5. **Collapsible > separate pages**: Keeps everything scannable in one view but allows deep-diving into specific dimensions without cluttering the top of the page.

## SQL Query Consolidation

The consolidated script runs these queries against opencode's SQLite DB:

| # | Purpose | Source |
|---|---------|--------|
| 1 | Daily tokens by agent category | value report (already has it) |
| 2 | Agent context efficiency (turns) | value report |
| 3 | Weekly token breakdown | value report |
| 4 | Summary metrics | both (use value report's more complete version) |
| 5 | Model breakdown (top 15) | LLM report |
| 6 | Agent breakdown (top 15) | LLM report |
| 7 | Model × Agent cross-tab | LLM report |
| 8 | Top sessions by tokens | LLM report |
| 9 | Sessions with file changes | value report |
| 10 | Build agent productivity | value report |
| — | Cache estimation | estimate_cache.py (unchanged) |
| — | Git data | Both (use all files, not just .swift) |

Total: ~10 queries vs. separate pipelines running 6-9 each = net savings.

## Testing Approach

- Run against full dataset (all time) to verify merge correctness
- Compare daily totals between old reports and new consolidated report for overlapping date ranges
- Verify cache-adjusted values match `estimate_cache.py` output
- Check that collapsible sections render correctly in browser
