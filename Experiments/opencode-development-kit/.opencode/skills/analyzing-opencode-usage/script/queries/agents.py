#!/usr/bin/env python3
"""Agent usage query for [ProjectName] LLM usage analytics.

Fetches agent role breakdown statistics. Uses read-only connections and parameterized queries.
"""

from data_access.db import get_connection, run_query
from data_access.types import AgentRow
from .utils import _resolve_date, _build_where
from pathlib import Path
from typing import Optional


def fetch(
    db_path: Optional[str] = None,
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
) -> list[AgentRow]:
    """Fetch agent role usage statistics.

    Args:
        db_path: Path to SQLite database. Defaults to opencode's default location.
        project: Project directory substring filter.
        since: Start date (YYYY-MM-DD).
        until: End date (YYYY-MM-DD).
        days: Number of days from today (overrides since/until).

    Returns:
        List of AgentRow objects sorted by total tokens descending (limit 25).
    """
    start_date, end_date = _resolve_date(since, until, days)
    where, params = _build_where(project)

    sql = f"""
    SELECT
        COALESCE(agent, 'unknown') as agent,
        COUNT(*) as sessions,
        SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens_raw,
        SUM(tokens_input) as input_tokens_raw,
        SUM(tokens_output) as output_tokens_raw,
        SUM(tokens_reasoning) as reasoning_tokens_raw
    FROM session
    WHERE {where}
        AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= ?
        AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= ?
    GROUP BY agent
    ORDER BY total_tokens_raw DESC
    LIMIT 25
    """
    params = params + [start_date, end_date]

    conn = get_connection(db_path or str(Path.home() / ".local/share/opencode/opencode.db"))
    try:
        rows = run_query(conn, sql, tuple(params))
        return [
            AgentRow(  # type: ignore
                agent=r.get('agent', 'unknown'),
                sessions=r.get('sessions', 0) or 0,
                total_tokens_raw=r.get('total_tokens_raw', 0) or 0,
                input_tokens_raw=r.get('input_tokens_raw', 0) or 0,
                output_tokens_raw=r.get('output_tokens_raw', 0) or 0,
                reasoning_tokens_raw=r.get('reasoning_tokens_raw', 0) or 0,
            )
            for r in rows
        ]
    finally:
        conn.close()
