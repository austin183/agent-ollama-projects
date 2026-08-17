#!/usr/bin/env python3
"""Model usage breakdown for pi usage analytics."""

from collections import defaultdict
from typing import Optional

from pi_sessions import all_events, load_sessions
from data_access.types import ModelRow
from .utils import resolve_date


def fetch(
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
    sessions=None,
    sessions_root=None,
    limit: int = 20,
) -> list[ModelRow]:
    """Model usage statistics, sorted by total tokens descending."""
    start_date, end_date = resolve_date(since, until, days)
    if sessions is None:
        sessions = load_sessions(sessions_root=sessions_root, project=project,
                                 since=start_date, until=end_date)

    by_model: dict[str, dict] = defaultdict(lambda: {
        'sessions': set(), 'input': 0, 'output': 0, 'reasoning': 0, 'total': 0})
    for e in all_events(sessions):
        m = by_model[e.model or 'unknown']
        m['sessions'].add(e.session_id)
        m['input'] += e.input
        m['output'] += e.output
        m['reasoning'] += e.reasoning
        m['total'] += e.total

    rows = [
        ModelRow(  # type: ignore
            model=model,
            sessions=len(d['sessions']),
            input_tokens_raw=d['input'],
            output_tokens_raw=d['output'],
            reasoning_tokens_raw=d['reasoning'],
            total_tokens_raw=d['total'],
        )
        for model, d in by_model.items()
    ]
    rows.sort(key=lambda r: r['total_tokens_raw'], reverse=True)
    return rows[:limit]
