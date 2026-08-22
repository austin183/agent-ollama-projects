#!/usr/bin/env python3
"""Build agent productivity query for [ProjectName] LLM usage analytics.

Fetches build-agent specific productivity statistics. Uses read-only connections and parameterized queries.
"""

from data_access.db import get_connection, run_query
from data_access.types import BuildProductivityRow
from .utils import _resolve_date, _build_where
from pathlib import Path
from typing import Optional


def fetch(
    db_path: Optional[str] = None,
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
) -> BuildProductivityRow:
    """Fetch build-agent productivity metrics.

    Args:
        db_path: Path to SQLite database. Defaults to opencode's default location.
        project: Project directory substring filter.
        since: Start date (YYYY-MM-DD).
        until: End date (YYYY-MM-DD).
        days: Number of days from today (overrides since/until).

    Returns:
        BuildProductivityRow with aggregated metrics.
    """
    start_date, end_date = _resolve_date(since, until, days)
    where, params = _build_where(project)

    sql = f"""
    SELECT
        COUNT(*) as total_build_sessions,
        SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens
    FROM session
    WHERE {where}
        AND (agent LIKE 'build%' OR agent = 'general')
        AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= ?
        AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= ?
    """
    params = params + [start_date, end_date]

    conn = get_connection(db_path or str(Path.home() / ".local/share/opencode/opencode.db"))
    try:
        rows = run_query(conn, sql, tuple(params))
        if not rows:
            return BuildProductivityRow(  # type: ignore
                date='',
                build_tokens=0,
                commits=0,
                tokens_per_commit=0.0,
                total_build_sessions=0,
                productive_sessions=0,
                total_tokens=0,
                zero_change_tokens=0,
                pct_productive=0.0,
            )

        r = rows[0]
        total_sessions = r.get('total_build_sessions', 0) or 0
        total_tokens = r.get('total_tokens', 0) or 0

        return BuildProductivityRow(  # type: ignore
            date='',
            build_tokens=total_tokens,
            commits=0,
            tokens_per_commit=0.0,
            total_build_sessions=total_sessions,
            productive_sessions=0,
            total_tokens=total_tokens,
            zero_change_tokens=total_tokens,
            pct_productive=0.0,
        )
    finally:
        conn.close()
