#!/usr/bin/env python3
"""Productivity metrics query for [ProjectName] LLM usage analytics.

Fetches overall productivity statistics (session counts). Uses read-only connections and parameterized queries.
"""

from data_access.db import get_connection, run_query
from data_access.types import ProductivityRow
from .utils import _resolve_date, _build_where
from pathlib import Path
from typing import Any, Optional


def fetch(
    db_path: Optional[str] = None,
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
) -> dict[str, Any]:
    """Fetch productivity metrics.

    Args:
        db_path: Path to SQLite database. Defaults to opencode's default location.
        project: Project directory substring filter.
        since: Start date (YYYY-MM-DD).
        until: End date (YYYY-MM-DD).
        days: Number of days from today (overrides since/until).

    Returns:
        ProductivityRow with aggregated metrics.
    """
    start_date, end_date = _resolve_date(since, until, days)
    where, params = _build_where(project)

    sql = f"""
    SELECT COUNT(*) as total_sessions
    FROM session
    WHERE {where}
        AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= ?
        AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= ?
        AND (tokens_input + tokens_output + tokens_reasoning) > 0
    """
    params = params + [start_date, end_date]

    conn = get_connection(db_path or str(Path.home() / ".local/share/opencode/opencode.db"))
    try:
        rows = run_query(conn, sql, tuple(params))
        if not rows:
            return {  # type: ignore
                'total_sessions': 0,
                'daily_sessions': {},
            }

        total_sessions = rows[0].get('total_sessions', 0) or 0

        # Second query: per-day session count mapping for later merge with git data
        sql_daily = f"""
        SELECT
            strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') as day,
            COUNT(*) as sessions
        FROM session
        WHERE {where}
            AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= ?
            AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= ?
            AND (tokens_input + tokens_output + tokens_reasoning) > 0
        GROUP BY day
        """
        daily_rows = run_query(conn, sql_daily, tuple(params))
        daily_sessions = {r['day']: r['sessions'] for r in daily_rows}

        return {  # type: ignore
            'total_sessions': total_sessions,
            'daily_sessions': daily_sessions,
        }
    finally:
        conn.close()
