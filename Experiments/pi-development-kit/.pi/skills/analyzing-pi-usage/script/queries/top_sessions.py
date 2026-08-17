#!/usr/bin/env python3
"""Top sessions by token usage for pi usage analytics.

One row per session file. Model and role show the dominant (highest-token)
attribution in the session; title comes from the session_info name or the
first user message.
"""

from collections import defaultdict
from typing import Optional

from pi_sessions import load_sessions
from data_access.types import TopSessionRow
from .utils import resolve_date


def fetch(
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
    sessions=None,
    sessions_root=None,
    limit: int = 20,
) -> list[TopSessionRow]:
    """Top sessions by total tokens, descending."""
    start_date, end_date = resolve_date(since, until, days)
    if sessions is None:
        sessions = load_sessions(sessions_root=sessions_root, project=project,
                                 since=start_date, until=end_date)

    rows = []
    for s in sessions:
        dom_model: dict[str, int] = defaultdict(int)
        dom_role: dict[str, int] = defaultdict(int)
        inp = out = rea = 0
        for e in s.events:
            dom_model[e.model or 'unknown'] += e.total
            dom_role[e.role or 'main'] += e.total
            inp += e.input
            out += e.output
            rea += e.reasoning
        total = sum(dom_model.values())
        title = s.name or s.first_user_text or s.session_id[:8]
        rows.append(TopSessionRow(  # type: ignore
            session_id=s.session_id,
            title=title[:60],
            model=max(dom_model, key=dom_model.get) if dom_model else '',
            role=max(dom_role, key=dom_role.get) if dom_role else '',
            created=s.header_ts_day,
            tokens=total,
            input_tokens=inp,
            output_tokens=out,
            reasoning_tokens=rea,
        ))
    rows.sort(key=lambda r: r['tokens'], reverse=True)
    return rows[:limit]
