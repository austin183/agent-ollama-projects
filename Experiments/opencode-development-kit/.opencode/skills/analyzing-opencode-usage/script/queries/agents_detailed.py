#!/usr/bin/env python3
"""Agent context efficiency query for [ProjectName] LLM usage analytics.

Fetches agent context metrics including turns and input per turn. Uses read-only connections and parameterized queries.
"""

from data_access.db import get_connection, run_query
from data_access.types import AgentContextRow
from .utils import _resolve_date, _build_where
from pathlib import Path
from typing import Optional


def fetch(
    db_path: Optional[str] = None,
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
) -> list[AgentContextRow]:
    """Fetch agent context efficiency metrics.

    Args:
        db_path: Path to SQLite database. Defaults to opencode's default location.
        project: Project directory substring filter.
        since: Start date (YYYY-MM-DD).
        until: End date (YYYY-MM-DD).
        days: Number of days from today (overrides since/until).

    Returns:
        List of AgentContextRow objects sorted by total tokens descending.
    """
    start_date, end_date = _resolve_date(since, until, days)
    where, params = _build_where(project)

    sql = f"""
    SELECT
        s.agent,
        COUNT(*) as sessions,
        SUM(s.tokens_input + s.tokens_output + s.tokens_reasoning) as total_tokens_raw,
        SUM(s.tokens_input) as input_tokens_raw,
        SUM(s.tokens_output) as output_tokens_raw,
        SUM(s.tokens_reasoning) as reasoning_tokens_raw
    FROM session s
    WHERE {where}
        AND strftime('%Y-%m-%d', s.time_created / 1000, 'unixepoch') >= ?
        AND strftime('%Y-%m-%d', s.time_created / 1000, 'unixepoch') <= ?
    GROUP BY s.agent
    ORDER BY total_tokens_raw DESC
    """
    params = params + [start_date, end_date]

    conn = get_connection(db_path or str(Path.home() / ".local/share/opencode/opencode.db"))
    try:
        rows = run_query(conn, sql, tuple(params))
        return [
            AgentContextRow(  # type: ignore
                context_type=r.get('agent', 'unknown'),
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

