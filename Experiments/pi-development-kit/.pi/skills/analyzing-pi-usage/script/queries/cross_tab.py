#!/usr/bin/env python3
"""Model × role cross-tabulation for pi usage analytics."""

from collections import defaultdict
from typing import Optional

from pi_sessions import all_events, load_sessions
from data_access.types import CrossTabRow
from .utils import resolve_date


def fetch(
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
    sessions=None,
    sessions_root=None,
) -> list[CrossTabRow]:
    """Model-role cross-tabulation, sorted by total tokens descending."""
    start_date, end_date = resolve_date(since, until, days)
    if sessions is None:
        sessions = load_sessions(sessions_root=sessions_root, project=project,
                                 since=start_date, until=end_date)

    by_pair: dict[tuple, dict] = defaultdict(lambda: {'sessions': set(), 'total': 0})
    for e in all_events(sessions):
        pair = (e.model or 'unknown', e.role or 'main')
        by_pair[pair]['sessions'].add(e.session_id)
        by_pair[pair]['total'] += e.total

    rows = [
        CrossTabRow(  # type: ignore
            model=model,
            role=role,
            sessions=len(d['sessions']),
            total_tokens_raw=d['total'],
        )
        for (model, role), d in by_pair.items()
    ]
    rows.sort(key=lambda r: r['total_tokens_raw'], reverse=True)
    return rows
