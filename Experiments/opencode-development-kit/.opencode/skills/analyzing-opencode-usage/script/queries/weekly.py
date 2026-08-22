#!/usr/bin/env python3
"""Weekly aggregation query for [ProjectName] LLM usage analytics.

Fetches weekly token counts grouped by agent category. Uses read-only connections and parameterized queries.
"""

from data_access.db import get_connection, run_query
from data_access.types import WeeklyRow
from .utils import _resolve_date, _build_where
from pathlib import Path
from typing import Optional


def fetch(
    db_path: Optional[str] = None,
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
) -> list[WeeklyRow]:
    """Fetch weekly token aggregation.

    Args:
        db_path: Path to SQLite database. Defaults to opencode's default location.
        project: Project directory substring filter.
        since: Start date (YYYY-MM-DD).
        until: End date (YYYY-MM-DD).
        days: Number of days from today (overrides since/until).

    Returns:
        List of WeeklyRow objects sorted by week.
    """
    start_date, end_date = _resolve_date(since, until, days)
    where, params = _build_where(project)

    sql = f"""
    SELECT
        strftime('%Y-W%W', time_created / 1000, 'unixepoch') as week,
        MIN(strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')) as week_start,
        MAX(strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')) as week_end,
        COUNT(*) as sessions,
        SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens_raw,
        COALESCE(SUM(CASE WHEN agent LIKE 'build%' OR agent = 'general' THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0) as build_tokens,
        COALESCE(SUM(CASE WHEN agent IN ('diff-review','diff-review-g31','solid-review','solid-review-g31','world-review','diff-review-q35','diff-review-o32') THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0) as review_tokens,
        COALESCE(SUM(CASE WHEN agent IN ('planner','planner-g31','planner-g4','plan') THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0) as planner_tokens
    FROM session
    WHERE {where}
        AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= ?
        AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= ?
    GROUP BY week
    ORDER BY week
    """
    params = params + [start_date, end_date]

    conn = get_connection(db_path or str(Path.home() / ".local/share/opencode/opencode.db"))
    try:
        rows = run_query(conn, sql, tuple(params))
        return [
            WeeklyRow(  # type: ignore
                week_start=r.get('week_start', ''),
                week_end=r.get('week_end', ''),
                sessions=r.get('sessions', 0) or 0,
                total_tokens_raw=r.get('total_tokens_raw', 0) or 0,
                build_tokens=r.get('build_tokens', 0) or 0,
                review_tokens=r.get('review_tokens', 0) or 0,
                planner_tokens=r.get('planner_tokens', 0) or 0,
            )
            for r in rows
        ]
    finally:
        conn.close()
