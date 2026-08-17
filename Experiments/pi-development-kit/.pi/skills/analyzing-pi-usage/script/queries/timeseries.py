#!/usr/bin/env python3
"""Daily token trend for pi usage analytics, with role-category breakdown."""

from collections import defaultdict
from typing import Optional

from pi_sessions import all_events, load_sessions
from data_access.types import DailyTokenRow
from .utils import resolve_date, role_category


def _day_rows(sessions, key_fn) -> list[dict]:
    """Group events by a day key, accumulating raw totals and category tokens."""
    rows: dict[str, dict] = {}
    for e in all_events(sessions):
        key = key_fn(e.day)
        if not key:
            continue
        d = rows.setdefault(key, {
            'sessions': set(), 'total': 0, 'input': 0, 'output': 0, 'reasoning': 0,
            'build': 0, 'review': 0, 'plan': 0, 'explore': 0, 'other': 0,
        })
        d['sessions'].add(e.session_id)
        d['total'] += e.total
        d['input'] += e.input
        d['output'] += e.output
        d['reasoning'] += e.reasoning
        d[role_category(e.role)] += e.total
    return [
        {
            'key': key,
            'sessions': len(d['sessions']),
            'total_tokens_raw': d['total'],
            'input_tokens_raw': d['input'],
            'output_tokens_raw': d['output'],
            'reasoning_tokens_raw': d['reasoning'],
            'build_tok_raw': d['build'],
            'review_tok_raw': d['review'],
            'plan_tok_raw': d['plan'],
            'explore_tok_raw': d['explore'],
            'other_tok_raw': d['other'],
        }
        for key, d in sorted(rows.items())
    ]


def fetch(
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
    sessions=None,
    sessions_root=None,
) -> list[DailyTokenRow]:
    """Daily token counts by role category, sorted by date."""
    start_date, end_date = resolve_date(since, until, days)
    if sessions is None:
        sessions = load_sessions(sessions_root=sessions_root, project=project,
                                 since=start_date, until=end_date)

    return [
        DailyTokenRow(date=d['key'], sessions=d['sessions'], **{k: d[k] for k in (
            'total_tokens_raw', 'input_tokens_raw', 'output_tokens_raw',
            'reasoning_tokens_raw', 'build_tok_raw', 'review_tok_raw',
            'plan_tok_raw', 'explore_tok_raw', 'other_tok_raw')})  # type: ignore
        for d in _day_rows(sessions, lambda day: day)
    ]


def fetch_weekly(
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
    sessions=None,
    sessions_root=None,
) -> list[dict]:
    """Weekly token counts by role category (ISO week key YYYY-Wnn)."""
    start_date, end_date = resolve_date(since, until, days)
    if sessions is None:
        sessions = load_sessions(sessions_root=sessions_root, project=project,
                                 since=start_date, until=end_date)

    from datetime import date

    def iso_week(day: str) -> str:
        try:
            y, w, _ = date.fromisoformat(day).isocalendar()
            return f'{y}-W{w:02d}'
        except ValueError:
            return ''

    rows = _day_rows(sessions, iso_week)
    out = []
    for d in rows:
        out.append({
            'week': d['key'],
            'total_sessions': d['sessions'],
            'total_tokens_raw': d['total_tokens_raw'],
            'build_tokens': d['build_tok_raw'],
            'review_tokens': d['review_tok_raw'],
            'planner_tokens': d['plan_tok_raw'],
        })
    return out


def fetch_monthly(
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
    sessions=None,
    sessions_root=None,
) -> list[dict]:
    """Monthly token counts (key YYYY-MM)."""
    start_date, end_date = resolve_date(since, until, days)
    if sessions is None:
        sessions = load_sessions(sessions_root=sessions_root, project=project,
                                 since=start_date, until=end_date)

    rows = _day_rows(sessions, lambda day: day[:7])
    return [
        {'month': d['key'], 'sessions': d['sessions'],
         'total_tokens_raw': d['total_tokens_raw']}
        for d in rows
    ]


def fetch_by_project(
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
    sessions=None,
    sessions_root=None,
) -> list[dict]:
    """Token usage by project directory (basename of session cwd)."""
    start_date, end_date = resolve_date(since, until, days)
    if sessions is None:
        sessions = load_sessions(sessions_root=sessions_root, since=start_date, until=end_date)

    import os
    by_dir: dict[str, dict] = defaultdict(lambda: {'sessions': set(), 'total': 0, 'models': set()})
    for s in sessions:
        name = os.path.basename(s.cwd.rstrip('/')) or s.cwd
        d = by_dir[name]
        d['sessions'].add(s.session_id)
        for e in s.events:
            d['total'] += e.total
            if e.model:
                d['models'].add(e.model)

    return [
        {'directory': name, 'sessions': len(d['sessions']), 'total_tokens': d['total'],
         'models_used': len(d['models'])}
        for name, d in sorted(by_dir.items(), key=lambda kv: kv[1]['total'], reverse=True)
    ]
