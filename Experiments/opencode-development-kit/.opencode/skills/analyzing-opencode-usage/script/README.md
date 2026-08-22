#!/usr/bin/env python3
"""
[ProjectName] LLM Usage Report Generator

Generates comprehensive HTML/JSON reports from opencode's SQLite database.
All token counts use cache-adjusted (uncached) input to reflect realistic consumption.

Quick Start
-----------
Generate HTML report for last 30 days:
    python3 generate_report.py --project /path/to/project --output report.html

Generate JSON output:
    python3 generate_report.py --project /path/to/project --json --output data.json

Custom date range:
    python3 generate_report.py --project /path/to/project --since 2026-07-01 --until 2026-07-31

Arguments
---------
--project PATH    Project directory (required). Can be absolute or relative.
--since DATE      Start date (YYYY-MM-DD). Default: 2000-01-01.
--until DATE      End date (YYYY-MM-DD). Default: today.
--days N          Last N days (overrides since/until).
--json            Output JSON instead of HTML.
--output FILE     Write to file instead of stdout.

Output
------
HTML report includes: summary cards, token breakdowns by model/agent, daily trends,
code impact metrics, cache analysis, productivity stats, and top sessions.

JSON payload contains the same data in structured format for programmatic use.

Architecture
------------
- Query modules: Modular SQL queries with read-only database access
- Aggregator: Merges raw data into unified report structure
- Renderer: HTML output using Chart.js visualizations
- All data structures use strict Python TypedDicts for type safety
"""
