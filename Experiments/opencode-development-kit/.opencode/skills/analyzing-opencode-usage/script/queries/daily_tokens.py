#!/usr/bin/env python3
"""Daily token usage query for [ProjectName] LLM usage analytics.

Fetches daily token counts grouped by agent category (build, review, plan, explore, other).
Uses read-only connections and parameterized queries.
"""

from data_access.db import get_connection, run_query
from data_access.types import DailyTokenRow
from .utils import _resolve_date, _build_where
from pathlib import Path
from typing import Optional


def fetch(
    db_path: Optional[str] = None,
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
) -> list[DailyTokenRow]:
    """Fetch daily token counts by agent category.

    Args:
        db_path: Path to SQLite database. Defaults to opencode's default location.
        project: Project directory substring filter.
        since: Start date (YYYY-MM-DD).
        until: End date (YYYY-MM-DD).
        days: Number of days from today (overrides since/until).

    Returns:
        List of DailyTokenRow objects sorted by date.
    """
    start_date, end_date = _resolve_date(since, until, days)
    where, params = _build_where(project)

    sql = f"""
    SELECT
        strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') as date,
        COUNT(*) as sessions,
        SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens_raw,
        COALESCE(SUM(tokens_input), 0) as input_tokens,
        COALESCE(SUM(tokens_output), 0) as output_tokens,
        COALESCE(SUM(tokens_reasoning), 0) as reasoning_tokens,
        COALESCE(SUM(CASE WHEN agent LIKE 'build%' OR agent = 'general' THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0) as build_tok,
        COALESCE(SUM(CASE WHEN agent IN ('diff-review','diff-review-g31','solid-review','solid-review-g31','world-review','diff-review-q35','diff-review-o32') THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0) as review_tok,
        COALESCE(SUM(CASE WHEN agent IN ('planner','planner-g31','planner-g4','plan') THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0) as plan_tok,
        COALESCE(SUM(CASE WHEN agent = 'explore' THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0) as explore_tok,
        COALESCE(SUM(CASE WHEN agent NOT LIKE 'build%' AND agent NOT IN ('explore','diff-review','diff-review-g31','solid-review','solid-review-g31','world-review','diff-review-q35','diff-review-o32','planner','planner-g31','planner-g4','plan','general') THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0) as other_tok
    FROM session
    WHERE {where}
        AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= ?
        AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= ?
    GROUP BY date
    ORDER BY date
    """
    params = params + [start_date, end_date]

    conn = get_connection(db_path or str(Path.home() / ".local/share/opencode/opencode.db"))
    try:
        rows = run_query(conn, sql, tuple(params))
        return [
            DailyTokenRow(  # type: ignore
                date=r.get('date', ''),
                sessions=r.get('sessions', 0) or 0,
                total_tokens_raw=r.get('total_tokens_raw', 0) or 0,
                input_tokens_raw=r.get('input_tokens', 0) or 0,
                output_tokens_raw=r.get('output_tokens', 0) or 0,
                reasoning_tokens_raw=r.get('reasoning_tokens', 0) or 0,
                build_tok_raw=r.get('build_tok', 0) or 0,
                review_tok_raw=r.get('review_tok', 0) or 0,
                plan_tok_raw=r.get('plan_tok', 0) or 0,
                explore_tok_raw=r.get('explore_tok', 0) or 0,
                other_tok_raw=r.get('other_tok', 0) or 0,
            )
            for r in rows
        ]
    finally:
        conn.close()
