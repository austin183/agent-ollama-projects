#!/usr/bin/env python3
"""Cache estimation for pi usage analytics.

Two data paths per session file:

1. **Measured (primary):** when any assistant turn carries a nonzero
   provider-reported ``cacheRead``/``cacheWrite`` (Anthropic/OpenAI/Google),
   the cache split is real: ``uncached = max(input - cacheRead, 0)`` per
   turn. No estimation needed.
2. **LAG-delta fallback:** when all cache fields are 0 (e.g. LM Studio),
   port the opencode kit's delta method: sort the session's assistant turns
   by timestamp; ``effective_input[n] = max(input[n] - input[n-1], 0)`` with
   the first turn keeping its full input. Disclaim as simulated.

Only main-session assistant turns participate (one per LLM turn). Compaction
usage is a single summary-generation call, not a turn sequence; subagent
results are aggregates without per-turn sequences. Both are still counted in
raw token totals elsewhere.
"""

from typing import Optional

from pi_sessions import load_sessions
from data_access.types import CacheEstimateRow
from .utils import resolve_date


def _session_turn_rows(session) -> list[dict]:
    """Per-session assistant turns as (rows, used_measured_cache)."""
    turns = sorted(
        (e for e in session.events if e.kind == 'assistant'),
        key=lambda e: e.ts,
    )
    measured = any(t.cache_read + t.cache_write > 0 for t in turns)
    rows = []
    prev_input = None
    for t in turns:
        if measured:
            uncached = max(t.input - t.cache_read, 0)
            cached = t.cache_read
        elif prev_input is None:
            uncached, cached = t.input, 0
        else:
            delta = t.input - prev_input
            uncached = max(delta, 0)
            cached = t.input - uncached
        prev_input = t.input
        rows.append({
            'day': t.day, 'model': t.model or 'unknown', 'role': t.role or 'main',
            'session_id': t.session_id, 'input': t.input,
            'uncached': uncached, 'cached': cached,
            'output': t.output, 'reasoning': t.reasoning,
            'measured': measured,
        })
    return rows


def _aggregate(rows: list[dict], measured: bool) -> dict:
    total_input = sum(r['input'] for r in rows)
    uncached = sum(r['uncached'] for r in rows)
    cached = sum(r['cached'] for r in rows)
    output = sum(r['output'] for r in rows)
    reasoning = sum(r['reasoning'] for r in rows)
    return {
        'sessions': len({r['session_id'] for r in rows}),
        'total_turns': len(rows),
        'total_input_raw': total_input,
        'estimated_uncached_input': uncached,
        'estimated_cached_input': cached,
        'cache_hit_pct': round(100.0 * cached / total_input, 1) if total_input else 0.0,
        'total_output': output,
        'total_reasoning': reasoning,
        'effective_total': uncached + output + reasoning,
        'raw_total': total_input + output + reasoning,
        'simulated': not measured,
    }


def _fetch(project, since, until, days, sessions, sessions_root, key_fn):
    start_date, end_date = resolve_date(since, until, days)
    if sessions is None:
        sessions = load_sessions(sessions_root=sessions_root, project=project,
                                 since=start_date, until=end_date)

    all_rows: list[dict] = []
    for s in sessions:
        all_rows.extend(_session_turn_rows(s))

    if key_fn is None:
        agg = _aggregate(all_rows, any(r['measured'] for r in all_rows))
        agg['key'], agg['value'] = None, 'aggregate'
        return _row_from_agg('aggregate', agg)

    grouped: dict[str, list[dict]] = {}
    for r in all_rows:
        key = key_fn(r)
        if key:
            grouped.setdefault(key, []).append(r)

    out = []
    for key in sorted(grouped, key=lambda k: -sum(r['input'] for r in grouped[k])):
        rows = grouped[key]
        agg = _aggregate(rows, any(r['measured'] for r in rows))
        agg['key'], agg['value'] = key, key
        out.append(_row_from_agg(key, agg))
    return out


def _row_from_agg(key: str, agg: dict) -> CacheEstimateRow:
    return CacheEstimateRow(  # type: ignore
        key=key, value=key,
        sessions=agg['sessions'], total_turns=agg['total_turns'],
        total_input_raw=agg['total_input_raw'],
        estimated_uncached_input=agg['estimated_uncached_input'],
        estimated_cached_input=agg['estimated_cached_input'],
        cache_hit_pct=agg['cache_hit_pct'],
        total_output=agg['total_output'],
        total_reasoning=agg['total_reasoning'],
        effective_total=agg['effective_total'],
        raw_total=agg['raw_total'],
        simulated=agg.get('simulated', True),
    )


def fetch_aggregate(project=None, since=None, until=None, days=None,
                    sessions=None, sessions_root=None) -> CacheEstimateRow:
    """Aggregate cache estimate (measured or simulated)."""
    return _fetch(project, since, until, days, sessions, sessions_root, None)


def fetch_by_model(project=None, since=None, until=None, days=None,
                   sessions=None, sessions_root=None) -> list[CacheEstimateRow]:
    """Cache estimate breakdown by model."""
    return _fetch(project, since, until, days, sessions, sessions_root,
                  lambda r: r['model'])


def fetch_by_role(project=None, since=None, until=None, days=None,
                  sessions=None, sessions_root=None) -> list[CacheEstimateRow]:
    """Cache estimate breakdown by role."""
    return _fetch(project, since, until, days, sessions, sessions_root,
                  lambda r: r['role'])


def fetch_by_day(project=None, since=None, until=None, days=None,
                 sessions=None, sessions_root=None) -> list[CacheEstimateRow]:
    """Cache estimate breakdown by day, sorted ascending."""
    rows = _fetch(project, since, until, days, sessions, sessions_root,
                  lambda r: r['day'])
    rows.sort(key=lambda r: r['key'])
    return rows
