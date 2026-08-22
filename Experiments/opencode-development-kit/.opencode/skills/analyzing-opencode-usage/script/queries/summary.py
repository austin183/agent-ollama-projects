#!/usr/bin/env python3
"""Summary metrics query for [ProjectName] LLM usage analytics.

Fetches aggregated summary data from the opencode database. Uses read-only
connections and parameterized queries.
"""

from data_access.db import get_connection, run_query
from data_access.types import SummaryRow
from .utils import _resolve_date, _build_where
from pathlib import Path
from typing import Optional


def fetch(
    db_path: Optional[str] = None,
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
) -> SummaryRow:
    """Fetch summary metrics.

    Args:
        db_path: Path to SQLite database. Defaults to opencode's default location.
        project: Project directory substring filter.
        since: Start date (YYYY-MM-DD).
        until: End date (YYYY-MM-DD).
        days: Number of days from today (overrides since/until).

    Returns:
        SummaryRow with aggregated metrics.
    """
    start_date, end_date = _resolve_date(since, until, days)
    where, params = _build_where(project)

    sql = f"""
    SELECT
        COUNT(*) as total_sessions,
        SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens_raw,
        SUM(tokens_input) as total_input_raw,
        SUM(tokens_output) as total_output,
        SUM(tokens_reasoning) as total_reasoning,
        MIN(strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')) as earliest,
        MAX(strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')) as latest,
        COUNT(DISTINCT COALESCE(json_extract(model, '$.id'), 'unknown')) as model_count,
        COUNT(DISTINCT COALESCE(agent, 'unknown')) as agent_count
    FROM session
    WHERE {where}
        AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= ?
        AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= ?
    """
    params = params + [start_date, end_date]

    conn = get_connection(db_path or str(Path.home() / ".local/share/opencode/opencode.db"))
    try:
        rows = run_query(conn, sql, tuple(params))
        if not rows:
            return SummaryRow(  # type: ignore
                total_sessions=0,
                total_tokens_raw=0,
                total_input_raw=0,
                total_output=0,
                total_reasoning=0,
                cache_hit_pct=0.0,
                earliest='',
                latest='',
                model_count=0,
                agent_count=0,
            )

        r = rows[0]
        return SummaryRow(  # type: ignore
            total_sessions=r.get('total_sessions', 0) or 0,
            total_tokens_raw=r.get('total_tokens_raw', 0) or 0,
            total_input_raw=r.get('total_input_raw', 0) or 0,
            total_output=r.get('total_output', 0) or 0,
            total_reasoning=r.get('total_reasoning', 0) or 0,
            cache_hit_pct=0.0,
            earliest=r.get('earliest', '') or '',
            latest=r.get('latest', '') or '',
            model_count=r.get('model_count', 0) or 0,
            agent_count=r.get('agent_count', 0) or 0,
        )
    finally:
        conn.close()


def fetch_project_range(
    db_path: Optional[str] = None,
    project: Optional[str] = None,
) -> dict:
    """Fetch the true all-time date range and session counts for a project.

    Unlike fetch(), this query takes NO date parameters — it ignores the
    report's date filter by construction, so the returned range reflects the
    project's full history rather than the queried window.

    Args:
        db_path: Path to SQLite database. Defaults to opencode's default location.
        project: Project directory substring filter.

    Returns:
        dict with keys:
            project_since: Earliest session date (YYYY-MM-DD), '' if no sessions.
            project_until: Latest session date (YYYY-MM-DD), '' if no sessions.
            total_sessions_all_time: All-time session count (int).
            legacy_sessions: Sessions with NULL model (no model/agent
                attribution, 0 tokens) (int).
    """
    where, params = _build_where(project)

    sql = f"""
    SELECT
        MIN(strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')) as project_since,
        MAX(strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')) as project_until,
        COUNT(*) as total_sessions_all_time,
        SUM(CASE WHEN model IS NULL THEN 1 ELSE 0 END) as legacy_sessions
    FROM session
    WHERE {where}
    """

    conn = get_connection(db_path or str(Path.home() / ".local/share/opencode/opencode.db"))
    try:
        rows = run_query(conn, sql, tuple(params))
        r = rows[0] if rows else {}
        return {
            'project_since': r.get('project_since', '') or '',
            'project_until': r.get('project_until', '') or '',
            'total_sessions_all_time': r.get('total_sessions_all_time', 0) or 0,
            'legacy_sessions': r.get('legacy_sessions', 0) or 0,
        }
    finally:
        conn.close()
