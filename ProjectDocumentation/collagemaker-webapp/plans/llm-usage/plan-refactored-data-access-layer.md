# Refactored Data Access Layer for CollageMaker Analytics

## Overview

This document outlines the plan to refactor the CollageMaker LLM usage report generation from a bash script with embedded Python into a clean, modular Python architecture with strict type safety and read-only database access.

## Current State

- Single bash script (`generate_consolidated_report.sh`) mixes SQL queries, shell logic, and Python merge code (~770 lines)
- Standalone Python script (`estimate_cache.py`) for cache estimation
- Hard to test, extend, or reuse individual datasets
- Mixed raw and cache-adjusted values scattered throughout

## Target Architecture

```
.script/
├── generate_report.py           # Single entry point
├── data_access/
│   ├── __init__.py
│   ├── db.py                    # Read-only SQLite connections, query runner
│   ├── types.py                 # All TypedDict definitions (strict)
│   └── queries/                 # Refactored SQL modules
│       ├── summary.py
│       ├── daily_tokens.py
│       ├── models.py
│       ├── agents.py
│       ├── cross_tab.py
│       ├── top_sessions.py
│       ├── agent_context.py
│       ├── weekly.py
│       ├── productivity.py
│       ├── build_productivity.py
│       ├── git_commits.py
│       ├── daily_git.py
│       └── cache_estimate.py
├── aggregator/
│   ├── __init__.py
│   └── merge.py                 # Pure Python aggregation logic
└── render_consolidated_report.py  # HTML renderer (unchanged)

tests/
├── conftest.py                  # Shared pytest fixtures and utilities
├── unit/                        # Unit tests for query modules
│   ├── test_summary.py
│   ├── test_daily_tokens.py
│   ├── test_models.py
│   ├── test_agents.py
│   ├── test_cross_tab.py
│   ├── test_top_sessions.py
│   ├── test_agent_context.py
│   ├── test_weekly.py
│   ├── test_productivity.py
│   ├── test_build_productivity.py
│   ├── test_git_commits.py
│   ├── test_daily_git.py
│   └── test_cache_estimate.py
├── integration/                 # Integration tests (full pipeline)
│   ├── test_json_output.py
│   └── test_aggregator.py
├── visual/                      # Visual regression tests
│   ├── test_html_visual.py
│   └── baseline/                # Baseline screenshots and DOM snapshots
├── performance/                 # Performance benchmarks
│   ├── test_db_locking.py
│   └── test_query_timing.py
├── edge_cases/                  # Edge case tests
│   ├── test_empty_results.py
│   ├── test_invalid_dates.py
│   ├── test_special_characters.py
│   ├── test_database_locked.py
│   └── test_schema_evolution.py
├── regression/                  # Regression tests against baseline data
│   ├── test_json_regression.py
│   ├── test_html_regression.py
│   └── baseline/                # Baseline JSON and HTML files
└── fixtures/                    # Test database seed scripts
    └── seed_data.py
```

## Key Design Principles

1. **Read-only database access** — All SQLite connections use `PRAGMA query_only=ON`
2. **Strict typing** — All data structures are `TypedDict` with required fields; use `NotRequired` for optional fields
3. **Refactored SQL** — Consistent CTE patterns, parameterized queries (no string interpolation), concise documentation
4. **Single project per run** — `--project` argument resolves to absolute path
5. **No external dependencies** — Only standard library modules
6. **Verbose type definitions** — Explicit fields everywhere for IDE support and early error detection

## Data Model

All datasets include both raw and cache-adjusted fields where applicable:

```python
class Summary(TypedDict):
    sessions: int
    total_tokens_raw: int
    total_input_raw: int
    total_output: int
    total_reasoning: int
    cache_hit_pct: float
    earliest: str
    latest: str
    model_count: int
    agent_count: int

class DailyTokenRow(TypedDict):
    date: str
    sessions: int
    # Raw values
    total_tokens_raw: int
    input_tokens_raw: int
    output_tokens_raw: int
    reasoning_tokens_raw: int
    build_tok_raw: int
    review_tok_raw: int
    plan_tok_raw: int
    explore_tok_raw: int
    other_tok_raw: int
    # Cache-adjusted (added by aggregator)
    input_tokens_uncached: NotRequired[int]
    output_tokens_cached: NotRequired[int]
    reasoning_tokens_cached: NotRequired[int]
    total_effective: NotRequired[int]

# Similar for ModelRow, AgentRow, CrossTabRow, GitCommitRow, etc.
```

## Data Flow

1. **`generate_report.py`** parses arguments and calls query modules
2. **Query modules** return raw datasets (lists of TypedDicts)
3. **Aggregator (`merge.py`)** combines raw datasets into final JSON structure
4. **HTML renderer** consumes final JSON and renders report

Example flow for cache adjustment:
```
Raw DB: session.tokens_input = 13,487,202
Query `models.py` returns: {'model': 'qwen', 'input_tokens_raw': 13,487,202}
Cache estimate returns: {by_model: [{'model': 'qwen', 'estimated_uncached_input': 965,900}]}
Aggregator merges → {'model': 'qwen', 'input_tokens_raw': 13,487,202, 'input_tokens_uncached': 965,900}
```

## Database Module (`data_access/db.py`)

```python
import sqlite3
from pathlib import Path
from typing import Any

def get_connection(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path, timeout=30.0, isolation_level='IMMEDIATE')
    conn.row_factory = sqlite3.Row
    return conn

def run_query(conn: sqlite3.Connection, sql: str, params: tuple = ()) -> list[dict]:
    cursor = conn.execute(sql, params)
    columns = [desc[0] for desc in cursor.description]
    return [dict(zip(columns, row)) for row in cursor.fetchall()]
```

## Query Module Pattern

Each `queries/*.py` follows this template:

```python
from ..types import DailyTokenRow
from ..db import get_connection, run_query
from pathlib import Path

def fetch(project_path: str | None = None, since: str | None = None, until: str | None = None) -> list[DailyTokenRow]:
    conn = get_connection(Path.home() / ".local/share/opencode/opencode.db")
    try:
        sql = """
        WITH date_range AS (
            SELECT 
                COALESCE(?::date, '2000-01-01') as start_date,
                COALESCE(?::date, date('now')) as end_date
        )
        SELECT ... FROM session s WHERE ... GROUP BY date ORDER BY date
        """
        params = (since, until, f'%{project_path}%' if project_path else '%')
        rows = run_query(conn, sql, params)
        return [DailyTokenRow(**row) for row in rows]
    finally:
        conn.close()
```

## Aggregator (`aggregator/merge.py`)

Input: raw datasets (dicts/lists)
Output: unified JSON structure matching current `output` dict

Responsibilities:
- Merge daily rows with cache estimates (compute `input_tokens_uncached`, etc.)
- Enrich models with cost data (call `model_pricing` functions)
- Compute cumulative values, rolling averages, efficiency metrics
- Build phase breakdowns

## Entry Point (`generate_report.py`)

```python
#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path

from data_access.queries import summary, daily_tokens, models, cache_estimate, ...
from aggregator.merge import merge_datasets
from render_consolidated_report import render_html

def resolve_date(since: str | None, until: str | None, days: int | None) -> tuple[str, str]:
    # Resolve from args or database
    pass

def main():
    parser = argparse.ArgumentParser(description='Generate CollageMaker LLM usage report')
    parser.add_argument('--project', required=True, help='Project folder path (absolute)')
    parser.add_argument('--since', help='Start date (YYYY-MM-DD)')
    parser.add_argument('--until', help='End date (YYYY-MM-DD)')
    parser.add_argument('--days', type=int, help='Last N days')
    parser.add_argument('--json', action='store_true', help='Output JSON instead of HTML')
    parser.add_argument('--output', help='Output file path')
    args = parser.parse_args()

    since, until = resolve_date(args.since, args.until, args.days)

    datasets = {
        'summary': summary.fetch(project_path=args.project, since=since, until=until),
        'daily_tokens': daily_tokens.fetch(project_path=args.project, since=since, until=until),
        # ... other queries
    }

    output = merge_datasets(datasets)

    if args.json or args.output.endswith('.json'):
        print(json.dumps(output, indent=2))
    else:
        html = render_html(output)
        if args.output:
            Path(args.output).write_text(html)
        else:
            print(html)

if __name__ == '__main__':
    main()
```

## Migration Steps

### Phase 1: Foundation (read-only connections, strict types)
- [ ] `data_access/db.py`: read-only SQLite connections with `PRAGMA query_only=ON`
- [ ] `data_access/types.py`: all TypedDicts for raw and enriched data structures
- [ ] `queries/cache_estimate.py`: migrate current `estimate_cache.py` logic, refactor SQL with CTEs
- [ ] **Tests**: Unit tests for db.py (connection safety), types.py (type validation)

### Phase 2: Core Query Extraction
- [ ] Extract `summary`, `daily_tokens`, `models`, `agents` from bash script
- [ ] Refactor each SQL query to be parameterized and consistent (SQLite-compatible syntax)
- [ ] **Unit tests per query module** (fixture database, 60+ tests total):
  - [ ] `summary.py`: U-SUM-001 to U-SUM-005 (valid/empty results, date filtering, TypedDict types)
  - [ ] `daily_tokens.py`: U-DT-001 to U-DT-005 (month boundaries, phase tokens, raw/cache fields)
  - [ ] `models.py`: U-MOD-001 to U-MOD-003 (raw vs cache fields, multi-model handling)
  - [ ] `agents.py`: U-AGT-001 to U-AGT-002 (agent normalization, usage counts)
  - [ ] `cross_tab.py`: U-CT-001 to U-CT-002 (model-agent relationships)
  - [ ] `top_sessions.py`: U-TS-001 to U-TS-002 (sorting, data completeness)
  - [ ] `agent_context.py`: U-AC-001 (context type aggregation)
  - [ ] `weekly.py`: U-WK-001 (week numbering, date ranges)
  - [ ] `productivity.py`: U-PRD-001 (efficiency metrics)
  - [ ] `build_productivity.py`: U-BP-001 (build-phase token rates)
  - [ ] `git_commits.py`: U-GC-001 (commit data structure)
  - [ ] `daily_git.py`: U-DG-001 (daily git stats)
  - [ ] `cache_estimate.py`: U-CE-001 to U-CE-002 (cache estimation logic)

### Phase 3: Aggregator
- [ ] Create `aggregator/merge.py`
- [ ] Move current Python merge logic (~400 lines) into clean, typed functions
- [ ] **Integration tests for aggregator** (fixture database with full dataset):
  - [ ] I-JSON-001: Minimal valid dataset (5 sessions) → complete JSON structure
  - [ ] I-JSON-002: Large dataset (100+ sessions) → performance < 5s, correct aggregation
  - [ ] I-JSON-003: Complex project filtering → JSON filtered correctly
  - [ ] I-JSON-004: Date range edge cases (cross-year) → correct weekly/daily breakdowns
  - [ ] I-JSON-005: Cache adjustment integration → cache-adjusted fields populated
  - [ ] I-JSON-006: Git integration → git data merged with token data
  - [ ] I-JSON-007: Empty database → zero values, empty lists

### Phase 4: Entry Point
- [ ] Create `generate_report.py` as the single entry point
- [ ] Wire all queries + aggregator
- [ ] **Regression tests for JSON output** (compare against baseline `-data.json` files):
  - [ ] R-JS-001: Summary data equality (`summary-data.json`)
  - [ ] R-JS-002: Daily tokens data equality (`daily-tokens-data.json`)
  - [ ] R-JS-003: Models data equality (`models-data.json`)
  - [ ] R-JS-004: Agents data equality (`agents-data.json`)
  - [ ] R-JS-005: Cross-tab data equality (`cross-tab-data.json`)
  - [ ] R-JS-006: Top sessions data equality (`top-sessions-data.json`)
- [ ] **Performance tests** (concurrent reads, query timing):
  - [ ] P-DBL-001: Single query < 500ms on typical dataset
  - [ ] P-DBL-002: Concurrent reads with database writer → no locks > 30s
  - [ ] P-DBL-003: Full report generation < 10s for 1000 sessions
  - [ ] P-DBL-004: Database connection overhead < 100ms per connection

### Phase 5: HTML Rendering
- [ ] Run `render_consolidated_report.py` with new JSON structure
- [ ] **Visual diff tests** (compare against baseline HTML):
  - [ ] V-HTML-001: Overall layout and structure (DOM tree comparison)
  - [ ] V-HTML-002: Summary card values (numeric value extraction)
  - [ ] V-HTML-003: Charts and graphs (canvas pixel comparison)
  - [ ] V-HTML-004: Tables and data grids (table content diff)
  - [ ] V-HTML-005: Responsive layout (screenshots at breakpoints)
  - [ ] V-HTML-006: Color scheme and styling (screenshot comparison)

### Phase 6: Documentation & Cleanup
- [ ] Write concise `README.md` in `.opencode/skills/analyzing-opencode-usage/script/`
- [ ] Remove `generate_consolidated_report.sh`
- [ ] **Final comprehensive test suite**:
  - [ ] Edge case tests (10+ scenarios): empty DB, malformed dates, special characters, locked DB, missing columns, etc.
  - [ ] All unit tests pass with ≥95% coverage on query modules
  - [ ] All integration tests pass (JSON structure valid)
  - [ ] All visual diff tests pass (HTML identical to baseline)
  - [ ] All performance tests pass (queries < 500ms, no locks > 30s)
  - [ ] All regression tests pass (backward compatibility verified)

## Testing Strategy

### Test Architecture
- **Fixture Database**: In-memory or temp SQLite databases seeded with realistic data
- **Validation**: TypedDict field types, JSON schema validation, DOM comparison, pixel matching
- **Tools**: pytest with fixtures, Playwright for visual testing, pytest-benchmark for performance

### Comprehensive Test Coverage

**1. Unit Tests (60+ tests)** — per query module
- Validate SQL output and TypedDict types
- Empty result handling, date boundaries, phase token aggregation
- 95% line coverage on query modules

**2. Integration Tests (7 scenarios)** — full pipeline validation
- Minimal dataset, large dataset (100+ sessions), project filtering, date boundaries
- Cache adjustment, git integration, empty database scenarios
- JSON structure and numeric precision verification

**3. Visual Diff Tests (6 tests)** — HTML output equivalence
- DOM tree comparison, numeric value extraction, canvas pixel matching
- Table content diff, responsive layout at breakpoints, color scheme validation

**4. Performance Tests (5 metrics)** — real-world operational concerns
- Single query execution time (< 500ms)
- Concurrent reads with database writer (no locks > 30s)
- Full report generation (< 10s for 1000 sessions)
- Database connection overhead (< 100ms per connection)
- Large dataset scaling (linear/sub-linear to 10,000 sessions)

**5. Edge Case Tests (10+ scenarios)** — real-world robustness
- Empty database, malformed dates, special characters in paths
- Extremely large date ranges, null values, incomplete data
- Database file not found, read-only connection attempts, long project paths
- Database locked scenarios, schema evolution (missing columns)

**6. Regression Tests (7 tests)** — backward compatibility
- JSON output equality against baseline `*-data.json` files
- HTML visual equivalence against existing reports

### Execution Strategy
```bash
# Parallel test execution where possible
pytest tests/unit -v --cov=data_access --cov-report=html
pytest tests/integration -v
pytest tests/visual -v --chromium
pytest tests/performance -v --benchmark-enable
pytest tests/edge_cases -v
pytest tests/regression -v

# Or run all: pytest tests/ -v --cov=data_access --cov-report=html
```

### Critical Pre-Test Fixes Required
1. Implement `PRAGMA query_only=ON` in `get_connection()`
2. Replace PostgreSQL syntax (`?::date`) with SQLite-compatible `date(?)`
3. Remove `isolation_level='IMMEDIATE'` (use autocommit for read-only)
4. Add CLI `--db-path` argument to override hardcoded path
5. Implement proper error handling with user-friendly messages
6. Consider connection pooling for large datasets (>1000 sessions)

## Known Constraints & Pushbacks

1. **SQLite locking** — Using read-only connections with `timeout=30` and WAL mode. Retry logic deferred if issues arise.
2. **Foreign key constraints** — Not enabled; opencode DB schema doesn't enforce them.
3. **Named parameters** — SQLite only supports `?` placeholders. Parameter order documented in each module.
4. **Performance** — Open/close per query is acceptable for small reports (<1000 sessions). Connection pooling deferred.
5. **Type safety** — Verbose TypedDicts are intentional; improves IDE support and error detection.

## Success Criteria

### Automated Verification
- [ ] All unit tests pass (≥95% coverage on query modules)
- [ ] All integration tests pass (JSON structure valid)
- [ ] All visual diff tests pass (HTML identical to baseline)
- [ ] All performance tests pass (queries < 500ms, no locks > 30s)
- [ ] All edge case tests pass (graceful handling)
- [ ] All regression tests pass (backward compatibility verified)

### Manual Verification
- [ ] Report generation completes without errors
- [ ] Output JSON matches expected format
- [ ] HTML report renders correctly in browser
- [ ] No database locking issues with concurrent access
- [ ] Edge cases handled gracefully with informative errors

### Design Principles Compliance
- [ ] All queries use read-only connections (`PRAGMA query_only=ON`)
- [ ] All data structures are strict TypedDicts
- [ ] SQL queries are parameterized (no string interpolation)
- [ ] JSON output is byte-for-byte identical to current `*-data.json`
- [ ] HTML output is visually identical to current reports
- [ ] No external dependencies introduced
- [ ] Documentation is concise and clear

## Related Documents

- Current report generator: `.opencode/skills/analyzing-opencode-usage/script/generate_consolidated_report.sh`
- Cache estimation script: `.opencode/skills/analyzing-opencode-usage/script/estimate_cache.py`
- HTML renderer: `.opencode/skills/analyzing-opencode-usage/script/render_consolidated_report.py`
