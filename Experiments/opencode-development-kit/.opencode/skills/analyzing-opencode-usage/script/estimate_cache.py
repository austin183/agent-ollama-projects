#!/usr/bin/env python3
"""Estimate prefix caching impact from opencode's per-message token data.

Analyzes the `message` table to compute how much of each session's input tokens
would be served from a prefix cache if the provider supported it. The algorithm
compares each turn's input count against the previous turn: the shared prefix
is cached, only the delta is uncached.

Note: this standalone script builds its SQL as a single statement string for
`opencode db`, so all filter inputs are validated/escaped in build_where().
The report pipeline (generate_report.py) uses queries/cache_estimate.py
instead, which uses parameterized queries.

Usage:
    # Aggregate summary (JSON to stdout)
    python3 estimate_cache.py

    # With filters
    python3 estimate_cache.py --project [ProjectName] --since 2026-07-01

    # Breakdown by model
    python3 estimate_cache.py --project [ProjectName] --since 2026-07-01 --by model

    # Breakdown by agent
    python3 estimate_cache.py --project [ProjectName] --since 2026-07-01 --by agent

    # Breakdown by day (timeseries)
    python3 estimate_cache.py --project [ProjectName] --since 2026-07-01 --by day

    # Per-session detail
    python3 estimate_cache.py --project [ProjectName] --since 2026-07-01 --sessions

    # Human-readable summary (for shell scripts)
    python3 estimate_cache.py --project [ProjectName] --since 2026-07-01 --text
"""

import argparse
import json
import re
import subprocess
import sys
from datetime import date, datetime, timedelta

# Strict YYYY-MM-DD format gate for --since / --until values
_DATE_RE = re.compile(r'^\d{4}-\d{2}-\d{2}$')


def _validate_date(value: str) -> str:
    """Validate that value is a real YYYY-MM-DD date; return it unchanged.

    Raises:
        ValueError: If value does not match YYYY-MM-DD or is not a valid
            calendar date (e.g. 2026-13-45).
    """
    if not _DATE_RE.match(value):
        raise ValueError(f"Invalid date format: {value!r}. Expected YYYY-MM-DD.")
    try:
        datetime.strptime(value, '%Y-%m-%d')
    except ValueError:
        raise ValueError(
            f"Invalid date: {value!r} matches YYYY-MM-DD but is not a valid calendar date."
        ) from None
    return value


def _sanitize_like(value: str) -> str:
    """Escape a value for safe use inside a SQL LIKE pattern string.

    Escapes the LIKE wildcards (% and _), the backslash used as the LIKE
    escape character, and the single quote that delimits the SQL string
    literal (doubled, per SQL standard). The generated clause must include
    ESCAPE '\\' for the wildcard escapes to take effect in SQLite.
    """
    return (value
            .replace('\\', '\\\\')
            .replace('%', '\\%')
            .replace('_', '\\_')
            .replace("'", "''"))


def query(sql):
    """Run a SQL query against opencode's SQLite DB and return JSON."""
    result = subprocess.run(
        ['opencode', 'db', sql, '--format', 'json'],
        capture_output=True, text=True, timeout=120
    )
    if result.returncode != 0:
        print(f"Query failed: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    return json.loads(result.stdout)


def build_where(project=None, since=None, until=None):
    """Build WHERE clause from filter arguments with input validation.

    since/until must be valid YYYY-MM-DD dates (raises ValueError otherwise);
    project is escaped for safe use in a LIKE pattern, so quote-injection
    payloads and LIKE wildcards in the name are treated as inert literals.

    Args:
        project: Directory substring filter
        since: Start date (inclusive), YYYY-MM-DD
        until: End date (inclusive), YYYY-MM-DD

    Returns:
        SQL WHERE clause string ('1=1' when no filters are given).
    """
    parts = []
    if project:
        safe_project = _sanitize_like(project)
        parts.append(f"directory LIKE '%{safe_project}%' ESCAPE '\\'")
    if since:
        safe_since = _validate_date(since)
        parts.append(f"strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= '{safe_since}'")
    if until:
        safe_until = _validate_date(until)
        parts.append(f"strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= '{safe_until}'")
    return ' AND '.join(parts) if parts else '1=1'


def fmt(v):
    """Format token count for display."""
    if v >= 1e9:
        return f'{v/1e9:.1f}B'
    if v >= 1e6:
        return f'{v/1e6:.1f}M'
    if v >= 1e3:
        return f'{v/1e3:.1f}K'
    return f'{v:,}'


def compute_cache_estimate(project=None, since=None, until=None, by=None, sessions=False):
    """Compute cache approximation and return structured results.

    Args:
        project: Directory substring filter
        since: Start date (inclusive), YYYY-MM-DD
        until: End date (inclusive), YYYY-MM-DD
        by: Breakdown dimension: None (aggregate), 'model', 'agent', 'day'
        sessions: Include per-session detail

    Returns:
        dict with 'aggregate' and optionally 'sessions' keys
    """
    where = build_where(project, since, until)

    # Core CTE: per-turn cache estimation from message table
    core_sql = f"""
    WITH collages AS (
        SELECT id, directory, time_created, model, agent
        FROM session
        WHERE {where}
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

    result = {}

    # ── Aggregate ──────────────────────────────────────────────────────────
    agg_sql = core_sql + """
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
    agg_rows = query(agg_sql)
    agg = agg_rows[0] if agg_rows else {}
    result['aggregate'] = {
        'sessions': agg.get('sessions', 0) or 0,
        'total_turns': agg.get('total_turns', 0) or 0,
        'total_input_raw': agg.get('total_input_raw', 0) or 0,
        'estimated_uncached_input': agg.get('estimated_uncached_input', 0) or 0,
        'estimated_cached_input': agg.get('estimated_cached_input', 0) or 0,
        'cache_hit_pct': agg.get('cache_hit_pct', 0) or 0,
        'total_output': agg.get('total_output', 0) or 0,
        'total_reasoning': agg.get('total_reasoning', 0) or 0,
        'effective_total': (agg.get('estimated_uncached_input', 0) or 0)
                          + (agg.get('total_output', 0) or 0)
                          + (agg.get('total_reasoning', 0) or 0),
        'raw_total': (agg.get('total_input_raw', 0) or 0)
                    + (agg.get('total_output', 0) or 0)
                    + (agg.get('total_reasoning', 0) or 0),
    }

    # ── Breakdown by model ────────────────────────────────────────────────
    if by == 'model' or by is None:
        model_sql = core_sql + """
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
        model_rows = query(model_sql) if by == 'model' or by is None else []
        result['by_model'] = [{
            'model': r.get('model', 'unknown'),
            'sessions': r.get('sessions', 0) or 0,
            'total_turns': r.get('total_turns', 0) or 0,
            'total_input_raw': r.get('total_input_raw', 0) or 0,
            'estimated_uncached_input': r.get('estimated_uncached_input', 0) or 0,
            'estimated_cached_input': r.get('estimated_cached_input', 0) or 0,
            'cache_hit_pct': r.get('cache_hit_pct', 0) or 0,
            'total_output': r.get('total_output', 0) or 0,
            'total_reasoning': r.get('total_reasoning', 0) or 0,
            'effective_total': (r.get('estimated_uncached_input', 0) or 0)
                              + (r.get('total_output', 0) or 0)
                              + (r.get('total_reasoning', 0) or 0),
            'raw_total': (r.get('total_input_raw', 0) or 0)
                         + (r.get('total_output', 0) or 0)
                         + (r.get('total_reasoning', 0) or 0),
        } for r in model_rows]

    # ── Breakdown by agent ────────────────────────────────────────────────
    if by == 'agent' or by is None:
        agent_sql = core_sql + """
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
        agent_rows = query(agent_sql) if by == 'agent' or by is None else []
        result['by_agent'] = [{
            'agent': r.get('agent', 'unknown'),
            'sessions': r.get('sessions', 0) or 0,
            'total_turns': r.get('total_turns', 0) or 0,
            'total_input_raw': r.get('total_input_raw', 0) or 0,
            'estimated_uncached_input': r.get('estimated_uncached_input', 0) or 0,
            'estimated_cached_input': r.get('estimated_cached_input', 0) or 0,
            'cache_hit_pct': r.get('cache_hit_pct', 0) or 0,
            'total_output': r.get('total_output', 0) or 0,
            'total_reasoning': r.get('total_reasoning', 0) or 0,
            'effective_total': (r.get('estimated_uncached_input', 0) or 0)
                              + (r.get('total_output', 0) or 0)
                              + (r.get('total_reasoning', 0) or 0),
            'raw_total': (r.get('total_input_raw', 0) or 0)
                         + (r.get('total_output', 0) or 0)
                         + (r.get('total_reasoning', 0) or 0),
        } for r in agent_rows]

    # ── Breakdown by day ──────────────────────────────────────────────────
    if by == 'day' or by is None:
        day_sql = core_sql + """
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
        day_rows = query(day_sql) if by == 'day' or by is None else []
        result['by_day'] = [{
            'day': r.get('day', ''),
            'sessions': r.get('sessions', 0) or 0,
            'total_turns': r.get('total_turns', 0) or 0,
            'total_input_raw': r.get('total_input_raw', 0) or 0,
            'estimated_uncached_input': r.get('estimated_uncached_input', 0) or 0,
            'estimated_cached_input': r.get('estimated_cached_input', 0) or 0,
            'cache_hit_pct': r.get('cache_hit_pct', 0) or 0,
            'total_output': r.get('total_output', 0) or 0,
            'total_reasoning': r.get('total_reasoning', 0) or 0,
            'effective_total': (r.get('estimated_uncached_input', 0) or 0)
                              + (r.get('total_output', 0) or 0)
                              + (r.get('total_reasoning', 0) or 0),
            'raw_total': (r.get('total_input_raw', 0) or 0)
                         + (r.get('total_output', 0) or 0)
                         + (r.get('total_reasoning', 0) or 0),
        } for r in day_rows]

    # ── Per-session detail ────────────────────────────────────────────────
    if sessions:
        sess_sql = core_sql + """
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
        sess_rows = query(sess_sql)
        result['sessions'] = [{
            'session_id': r.get('session_id', ''),
            'agent': r.get('agent', ''),
            'model': r.get('model', ''),
            'title': r.get('title', '') or '',
            'created': r.get('created', ''),
            'turns': r.get('turns', 0) or 0,
            'total_input_raw': r.get('total_input_raw', 0) or 0,
            'estimated_uncached_input': r.get('estimated_uncached_input', 0) or 0,
            'estimated_cached_input': r.get('estimated_cached_input', 0) or 0,
            'cache_hit_pct': r.get('cache_hit_pct', 0) or 0,
            'total_output': r.get('total_output', 0) or 0,
            'total_reasoning': r.get('total_reasoning', 0) or 0,
            'min_input': r.get('min_input', 0) or 0,
            'max_input': r.get('max_input', 0) or 0,
        } for r in sess_rows]

    return result


def render_text(data):
    """Render human-readable text summary from cache estimate data."""
    a = data['aggregate']
    lines = []
    lines.append("")
    lines.append("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    lines.append("  Cache Approximation Summary")
    lines.append("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    lines.append("")
    lines.append(f"  Sessions analyzed:    {a['sessions']}")
    lines.append(f"  Total turns:          {a['total_turns']}")
    lines.append("")
    lines.append("  Raw input tokens:       " + fmt(a['total_input_raw']))
    lines.append("  Est. cached input:      " + fmt(a['estimated_cached_input']))
    lines.append("  Est. uncached input:    " + fmt(a['estimated_uncached_input']))
    lines.append("  Cache hit rate:         " + str(a['cache_hit_pct']) + "%")
    lines.append("")
    lines.append("  Raw total (input+out+reason): " + fmt(a['raw_total']))
    lines.append("  Effective total (w/cache):    " + fmt(a['effective_total']))
    savings = a['raw_total'] - a['effective_total']
    savings_pct = round(100.0 * savings / a['raw_total'], 1) if a['raw_total'] > 0 else 0
    lines.append("  Tokens saved by cache:    " + fmt(savings) + f" ({savings_pct}%)")

    if 'by_model' in data and data['by_model']:
        lines.append("")
        lines.append("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        lines.append("  Cache Impact by Model")
        lines.append("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        lines.append("")
        lines.append(f"  {'Model':<35} {'Sess':>5} {'Raw Input':>12} {'Uncached':>12} {'Cached':>12} {'Hit%':>6}")
        lines.append("  " + "─" * 84)
        for r in data['by_model']:
            lines.append(
                f"  {r['model']:<35} {r['sessions']:>5} "
                f"{fmt(r['total_input_raw']):>12} {fmt(r['estimated_uncached_input']):>12} "
                f"{fmt(r['estimated_cached_input']):>12} {r['cache_hit_pct']:>5}%"
            )

    if 'by_agent' in data and data['by_agent']:
        lines.append("")
        lines.append("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        lines.append("  Cache Impact by Agent")
        lines.append("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        lines.append("")
        lines.append(f"  {'Agent':<25} {'Sess':>5} {'Raw Input':>12} {'Uncached':>12} {'Cached':>12} {'Hit%':>6}")
        lines.append("  " + "─" * 74)
        for r in data['by_agent']:
            lines.append(
                f"  {r['agent']:<25} {r['sessions']:>5} "
                f"{fmt(r['total_input_raw']):>12} {fmt(r['estimated_uncached_input']):>12} "
                f"{fmt(r['estimated_cached_input']):>12} {r['cache_hit_pct']:>5}%"
            )

    if 'by_day' in data and data['by_day']:
        lines.append("")
        lines.append("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        lines.append("  Cache Impact by Day")
        lines.append("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        lines.append("")
        lines.append(f"  {'Date':<12} {'Sess':>5} {'Raw Input':>12} {'Uncached':>12} {'Cached':>12} {'Hit%':>6}")
        lines.append("  " + "─" * 64)
        for r in data['by_day']:
            lines.append(
                f"  {r['day']:<12} {r['sessions']:>5} "
                f"{fmt(r['total_input_raw']):>12} {fmt(r['estimated_uncached_input']):>12} "
                f"{fmt(r['estimated_cached_input']):>12} {r['cache_hit_pct']:>5}%"
            )

    if 'sessions' in data and data['sessions']:
        lines.append("")
        lines.append("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        lines.append("  Per-Session Cache Estimates")
        lines.append("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        lines.append("")
        lines.append(f"  {'Date':<14} {'Agent':<15} {'Turns':>5} {'Raw Input':>12} {'Uncached':>12} {'Cached':>12} {'Hit%':>6}")
        lines.append("  " + "─" * 80)
        for r in data['sessions']:
            lines.append(
                f"  {r['created']:<14} {r['agent']:<15} {r['turns']:>5} "
                f"{fmt(r['total_input_raw']):>12} {fmt(r['estimated_uncached_input']):>12} "
                f"{fmt(r['estimated_cached_input']):>12} {r['cache_hit_pct']:>5}%"
            )

    lines.append("")
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(
        description='Estimate prefix caching impact from opencode session data.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --project [ProjectName] --since 2026-07-01
  %(prog)s --project [ProjectName] --since 2026-07-01 --by model
  %(prog)s --project [ProjectName] --since 2026-07-01 --sessions
  %(prog)s --project [ProjectName] --since 2026-07-01 --text

Breakdown options:
  --by model   Group cache estimates by model
  --by agent   Group cache estimates by agent role
  --by day     Group cache estimates by date (timeseries)

Output:
  Default: JSON with aggregate + requested breakdowns
  --text:    Human-readable summary (for shell scripts)
  --sessions: Include per-session detail in output
"""
    )
    parser.add_argument('--project', default=None, help='Directory substring filter')
    parser.add_argument('--since', default=None, help='Start date (inclusive), YYYY-MM-DD')
    parser.add_argument('--until', default=None, help='End date (inclusive), YYYY-MM-DD')
    parser.add_argument('--days', type=int, default=None, help='Last N days (overrides --since)')
    parser.add_argument('--week', action='store_true', help='Last 7 days')
    parser.add_argument('--month', action='store_true', help='Last 30 days')
    parser.add_argument('--all', action='store_true', help='No date filter')
    parser.add_argument('--by', choices=['model', 'agent', 'day'], default=None,
                        help='Breakdown dimension')
    parser.add_argument('--sessions', action='store_true',
                        help='Include per-session detail')
    parser.add_argument('--text', action='store_true',
                        help='Output human-readable text instead of JSON')

    args = parser.parse_args()

    # Resolve date range
    since = args.since
    until = args.until
    if args.week:
        since = (date.today() - timedelta(days=7)).isoformat()
    elif args.month:
        since = (date.today() - timedelta(days=30)).isoformat()
    elif args.days:
        since = (date.today() - timedelta(days=args.days)).isoformat()
    # --all means no date filter (since/until stay None)

    # Compute estimates
    try:
        data = compute_cache_estimate(
            project=args.project,
            since=since,
            until=until,
            by=args.by,
            sessions=args.sessions
        )
    except ValueError as e:
        # Invalid filter input (e.g. malformed --since/--until date)
        print(f"error: {e}", file=sys.stderr)
        sys.exit(2)

    if args.text:
        print(render_text(data))
    else:
        print(json.dumps(data, indent=2))


if __name__ == '__main__':
    main()
