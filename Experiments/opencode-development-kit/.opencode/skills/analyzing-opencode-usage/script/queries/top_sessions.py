#!/usr/bin/env python3
"""Top sessions query for [ProjectName] LLM usage analytics.

Fetches top sessions by total token usage. Uses read-only connections and parameterized queries.
"""

from data_access.db import get_connection, run_query
from data_access.types import TopSessionRow
from .utils import _resolve_date, _build_where
from pathlib import Path
from typing import Optional


def fetch(
    db_path: Optional[str] = None,
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
) -> list[TopSessionRow]:
    """Fetch top sessions by token usage.

    Args:
        db_path: Path to SQLite database. Defaults to opencode's default location.
        project: Project directory substring filter.
        since: Start date (YYYY-MM-DD).
        until: End date (YYYY-MM-DD).
        days: Number of days from today (overrides since/until).

    Returns:
        List of TopSessionRow objects sorted by total tokens descending (limit 20).
    """
    start_date, end_date = _resolve_date(since, until, days)
    where, params = _build_where(project)

    sql = f"""
    SELECT
        title,
        agent,
        json_extract(model, '$.id') as model,
        tokens_input + tokens_output + tokens_reasoning as total_tokens,
        tokens_input,
        tokens_output,
        tokens_reasoning,
        strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') as created
    FROM session
    WHERE {where}
        AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= ?
        AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= ?
    ORDER BY total_tokens DESC
    LIMIT 20
    """
    params = params + [start_date, end_date]

    conn = get_connection(db_path or str(Path.home() / ".local/share/opencode/opencode.db"))
    try:
        rows = run_query(conn, sql, tuple(params))
        return [
            TopSessionRow(  # type: ignore
                session_id=r.get('session_id', '') or r.get('title', ''),
                title=r.get('title', ''),
                model=r.get('model', ''),
                agent=r.get('agent', ''),
                created=r.get('created', '') or '',
                tokens=r.get('total_tokens', 0) or 0,
                input_tokens=r.get('tokens_input', 0) or 0,
                output_tokens=r.get('tokens_output', 0) or 0,
                reasoning_tokens=r.get('tokens_reasoning', 0) or 0,
            )
            for r in rows
        ]
    finally:
        conn.close()
