#!/usr/bin/env python3
"""Cache estimation queries for [ProjectName] LLM usage analytics.

Migrates logic from estimate_cache.py with refactored SQL and direct SQLite access.
All queries use read-only connections and parameterized statements.
"""

from data_access.db import get_connection, run_query
from data_access.types import CacheEstimateRow, PerSessionCacheRow
from pathlib import Path
from typing import List, Optional
from .utils import _resolve_date, _build_where


def _cache_cte(where: str) -> str:
    """Build the shared 4-level CTE chain for cache estimation queries.

    Returns the CTE block (without trailing semicolon) that all cache
    estimation queries share. Each caller appends its own SELECT clause.

    Args:
        where: SQL WHERE clause fragment for project filtering.

    Returns:
        SQL string containing the collages → msg_tokens → with_prev → per_turn
        CTE chain, ready to be concatenated with a final SELECT.
    """
    return f"""
    WITH collages AS (
        SELECT id, directory, time_created, model, agent
        FROM session s
        WHERE {where}
          AND strftime('%Y-%m-%d', s.time_created / 1000, 'unixepoch') >= ?
          AND strftime('%Y-%m-%d', s.time_created / 1000, 'unixepoch') <= ?
    ),
    msg_tokens AS (
        SELECT
            m.session_id,
            m.time_created,
            json_extract(m.data, '$.tokens.input') AS input_tokens,
            json_extract(m.data, '$.tokens.output') AS output_tokens,
            json_extract(m.data, '$.tokens.reasoning') AS reasoning_tokens,
            ROW_NUMBER() OVER (PARTITION BY m.session_id ORDER BY m.time_created) AS turn
        FROM message m
        JOIN collages c ON m.session_id = c.id
        WHERE json_extract(m.data, '$.tokens.input') IS NOT NULL
          AND json_extract(m.data, '$.role') = 'assistant'
    ),
    with_prev AS (
        SELECT
            mt.*,
            LAG(mt.input_tokens) OVER (PARTITION BY mt.session_id ORDER BY mt.time_created) AS prev_input
        FROM msg_tokens mt
    ),
    per_turn AS (
        SELECT
            *,
            CASE
                WHEN prev_input IS NULL THEN input_tokens
                WHEN input_tokens <= prev_input THEN input_tokens
                ELSE input_tokens - prev_input
            END AS new_uncached_input,
            CASE
                WHEN prev_input IS NULL THEN 0
                WHEN input_tokens <= prev_input THEN 0
                ELSE prev_input
            END AS cached_input
        FROM with_prev
    )
    """


def fetch_aggregate(
    db_path: Optional[str] = None,
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
) -> CacheEstimateRow:
    """Fetch aggregated cache estimate data."""
    start_date, end_date = _resolve_date(since, until, days)
    where, params = _build_where(project)
    params = params + [start_date, end_date]

    sql = _cache_cte(where) + """
    SELECT
        COUNT(DISTINCT session_id) AS sessions,
        COUNT(*) AS total_turns,
        SUM(input_tokens) AS total_input_raw,
        SUM(new_uncached_input) AS estimated_uncached_input,
        SUM(cached_input) AS estimated_cached_input,
        ROUND(100.0 * SUM(cached_input) / NULLIF(SUM(input_tokens), 0), 1) AS cache_hit_pct,
        SUM(output_tokens) AS total_output,
        SUM(reasoning_tokens) AS total_reasoning
    FROM per_turn
    """

    conn = get_connection(db_path or str(Path.home() / ".local/share/opencode/opencode.db"))
    try:
        rows = run_query(conn, sql, tuple(params))
        if not rows:
            return CacheEstimateRow(  # type: ignore
                sessions=0,
                total_turns=0,
                total_input_raw=0,
                estimated_uncached_input=0,
                estimated_cached_input=0,
                cache_hit_pct=0.0,
                total_output=0,
                total_reasoning=0,
                effective_total=0,
                raw_total=0,
            )

        r = rows[0]
        total_input = r.get('total_input_raw', 0) or 0
        cached = r.get('estimated_cached_input', 0) or 0
        uncached = r.get('estimated_uncached_input', 0) or 0
        output = r.get('total_output', 0) or 0
        reasoning = r.get('total_reasoning', 0) or 0

        return CacheEstimateRow(  # type: ignore
            sessions=r.get('sessions', 0) or 0,
            total_turns=r.get('total_turns', 0) or 0,
            total_input_raw=total_input,
            estimated_uncached_input=uncached,
            estimated_cached_input=cached,
            cache_hit_pct=r.get('cache_hit_pct', 0) or 0,
            total_output=output,
            total_reasoning=reasoning,
            effective_total=uncached + output + reasoning,
            raw_total=total_input + output + reasoning,
        )
    finally:
        conn.close()


def fetch_by_model(
    db_path: Optional[str] = None,
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
) -> List[CacheEstimateRow]:
    """Fetch cache estimates grouped by model."""
    start_date, end_date = _resolve_date(since, until, days)
    where, params = _build_where(project)
    params = params + [start_date, end_date]

    sql = _cache_cte(where) + """
    SELECT
        COALESCE(json_extract(c.model, '$.id'), 'unknown') AS model,
        COUNT(DISTINCT pt.session_id) AS sessions,
        COUNT(*) AS total_turns,
        SUM(pt.input_tokens) AS total_input_raw,
        SUM(pt.new_uncached_input) AS estimated_uncached_input,
        SUM(pt.cached_input) AS estimated_cached_input,
        ROUND(100.0 * SUM(pt.cached_input) / NULLIF(SUM(pt.input_tokens), 0), 1) AS cache_hit_pct,
        SUM(pt.output_tokens) AS total_output,
        SUM(pt.reasoning_tokens) AS total_reasoning
    FROM per_turn pt
    JOIN collages c ON pt.session_id = c.id
    GROUP BY json_extract(c.model, '$.id')
    ORDER BY total_input_raw DESC
    """

    conn = get_connection(db_path or str(Path.home() / ".local/share/opencode/opencode.db"))
    try:
        rows = run_query(conn, sql, tuple(params))
        return [
            CacheEstimateRow(  # type: ignore
                key=r.get('model', 'unknown'),
                value=r.get('model', 'unknown'),
                sessions=r.get('sessions', 0) or 0,
                total_turns=r.get('total_turns', 0) or 0,
                total_input_raw=r.get('total_input_raw', 0) or 0,
                estimated_uncached_input=r.get('estimated_uncached_input', 0) or 0,
                estimated_cached_input=r.get('estimated_cached_input', 0) or 0,
                cache_hit_pct=r.get('cache_hit_pct', 0) or 0,
                total_output=r.get('total_output', 0) or 0,
                total_reasoning=r.get('total_reasoning', 0) or 0,
                effective_total=(r.get('estimated_uncached_input', 0) or 0) +
                               (r.get('total_output', 0) or 0) +
                               (r.get('total_reasoning', 0) or 0),
                raw_total=(r.get('total_input_raw', 0) or 0) +
                         (r.get('total_output', 0) or 0) +
                         (r.get('total_reasoning', 0) or 0),
            )
            for r in rows
        ]
    finally:
        conn.close()


def fetch_by_agent(
    db_path: Optional[str] = None,
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
) -> List[CacheEstimateRow]:
    """Fetch cache estimates grouped by agent."""
    start_date, end_date = _resolve_date(since, until, days)
    where, params = _build_where(project)
    params = params + [start_date, end_date]

    sql = _cache_cte(where) + """
    SELECT
        COALESCE(c.agent, 'unknown') AS agent,
        COUNT(DISTINCT pt.session_id) AS sessions,
        COUNT(*) AS total_turns,
        SUM(pt.input_tokens) AS total_input_raw,
        SUM(pt.new_uncached_input) AS estimated_uncached_input,
        SUM(pt.cached_input) AS estimated_cached_input,
        ROUND(100.0 * SUM(pt.cached_input) / NULLIF(SUM(pt.input_tokens), 0), 1) AS cache_hit_pct,
        SUM(pt.output_tokens) AS total_output,
        SUM(pt.reasoning_tokens) AS total_reasoning
    FROM per_turn pt
    JOIN collages c ON pt.session_id = c.id
    GROUP BY c.agent
    ORDER BY total_input_raw DESC
    """

    conn = get_connection(db_path or str(Path.home() / ".local/share/opencode/opencode.db"))
    try:
        rows = run_query(conn, sql, tuple(params))
        return [
            CacheEstimateRow(  # type: ignore
                key=r.get('agent', 'unknown'),
                value=r.get('agent', 'unknown'),
                sessions=r.get('sessions', 0) or 0,
                total_turns=r.get('total_turns', 0) or 0,
                total_input_raw=r.get('total_input_raw', 0) or 0,
                estimated_uncached_input=r.get('estimated_uncached_input', 0) or 0,
                estimated_cached_input=r.get('estimated_cached_input', 0) or 0,
                cache_hit_pct=r.get('cache_hit_pct', 0) or 0,
                total_output=r.get('total_output', 0) or 0,
                total_reasoning=r.get('total_reasoning', 0) or 0,
                effective_total=(r.get('estimated_uncached_input', 0) or 0) +
                               (r.get('total_output', 0) or 0) +
                               (r.get('total_reasoning', 0) or 0),
                raw_total=(r.get('total_input_raw', 0) or 0) +
                         (r.get('total_output', 0) or 0) +
                         (r.get('total_reasoning', 0) or 0),
            )
            for r in rows
        ]
    finally:
        conn.close()


def fetch_by_day(
    db_path: Optional[str] = None,
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
) -> List[CacheEstimateRow]:
    """Fetch cache estimates grouped by day."""
    start_date, end_date = _resolve_date(since, until, days)
    where, params = _build_where(project)
    params = params + [start_date, end_date]

    sql = _cache_cte(where) + """
    SELECT
        strftime('%Y-%m-%d', c.time_created / 1000, 'unixepoch') AS day,
        COUNT(DISTINCT pt.session_id) AS sessions,
        COUNT(*) AS total_turns,
        SUM(pt.input_tokens) AS total_input_raw,
        SUM(pt.new_uncached_input) AS estimated_uncached_input,
        SUM(pt.cached_input) AS estimated_cached_input,
        ROUND(100.0 * SUM(pt.cached_input) / NULLIF(SUM(pt.input_tokens), 0), 1) AS cache_hit_pct,
        SUM(pt.output_tokens) AS total_output,
        SUM(pt.reasoning_tokens) AS total_reasoning
    FROM per_turn pt
    JOIN collages c ON pt.session_id = c.id
    GROUP BY day
    ORDER BY day
    """

    conn = get_connection(db_path or str(Path.home() / ".local/share/opencode/opencode.db"))
    try:
        rows = run_query(conn, sql, tuple(params))
        return [
            CacheEstimateRow(  # type: ignore
                key=r.get('day', ''),
                value=r.get('day', ''),
                sessions=r.get('sessions', 0) or 0,
                total_turns=r.get('total_turns', 0) or 0,
                total_input_raw=r.get('total_input_raw', 0) or 0,
                estimated_uncached_input=r.get('estimated_uncached_input', 0) or 0,
                estimated_cached_input=r.get('estimated_cached_input', 0) or 0,
                cache_hit_pct=r.get('cache_hit_pct', 0) or 0,
                total_output=r.get('total_output', 0) or 0,
                total_reasoning=r.get('total_reasoning', 0) or 0,
                effective_total=(r.get('estimated_uncached_input', 0) or 0) +
                               (r.get('total_output', 0) or 0) +
                               (r.get('total_reasoning', 0) or 0),
                raw_total=(r.get('total_input_raw', 0) or 0) +
                         (r.get('total_output', 0) or 0) +
                         (r.get('total_reasoning', 0) or 0),
            )
            for r in rows
        ]
    finally:
        conn.close()


def fetch_sessions(
    db_path: Optional[str] = None,
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
) -> List[PerSessionCacheRow]:
    """Fetch per-session cache estimates."""
    start_date, end_date = _resolve_date(since, until, days)
    where, params = _build_where(project)
    params = params + [start_date, end_date]

    sql = _cache_cte(where) + """
    SELECT
        pt.session_id,
        c.agent,
        json_extract(c.model, '$.id') AS model,
        c.title,
        strftime('%Y-%m-%d %H:%M', c.time_created / 1000, 'unixepoch') AS created,
        COUNT(*) AS turns,
        SUM(pt.input_tokens) AS total_input_raw,
        SUM(pt.new_uncached_input) AS estimated_uncached_input,
        SUM(pt.cached_input) AS estimated_cached_input,
        ROUND(100.0 * SUM(pt.cached_input) / NULLIF(SUM(pt.input_tokens), 0), 1) AS cache_hit_pct,
        SUM(pt.output_tokens) AS total_output,
        SUM(pt.reasoning_tokens) AS total_reasoning,
        MIN(pt.input_tokens) AS min_input,
        MAX(pt.input_tokens) AS max_input
    FROM per_turn pt
    JOIN collages c ON pt.session_id = c.id
    GROUP BY pt.session_id
    ORDER BY total_input_raw DESC
    """

    conn = get_connection(db_path or str(Path.home() / ".local/share/opencode/opencode.db"))
    try:
        rows = run_query(conn, sql, tuple(params))
        return [
            PerSessionCacheRow(  # type: ignore
                session_id=r.get('session_id', ''),
                agent=r.get('agent', ''),
                model=r.get('model', ''),
                title=r.get('title', '') or '',
                created=r.get('created', ''),
                turns=r.get('turns', 0) or 0,
                total_input_raw=r.get('total_input_raw', 0) or 0,
                estimated_uncached_input=r.get('estimated_uncached_input', 0) or 0,
                estimated_cached_input=r.get('estimated_cached_input', 0) or 0,
                cache_hit_pct=r.get('cache_hit_pct', 0) or 0,
                total_output=r.get('total_output', 0) or 0,
                total_reasoning=r.get('total_reasoning', 0) or 0,
                min_input=r.get('min_input', 0) or 0,
                max_input=r.get('max_input', 0) or 0,
            )
            for r in rows
        ]
    finally:
        conn.close()
