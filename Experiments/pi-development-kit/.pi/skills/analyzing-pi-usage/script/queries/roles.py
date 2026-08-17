#!/usr/bin/env python3
"""Role usage breakdown for pi usage analytics.

Roles are the pi counterpart of opencode's per-session agents: the main
session's role comes from the `Role: <name>` user-message marker (default
`main`), subagent runs carry their exact agent name.
"""

from collections import defaultdict
from typing import Optional

from pi_sessions import all_events, load_sessions
from data_access.types import RoleRow
from .utils import resolve_date


def fetch(
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
    sessions=None,
    sessions_root=None,
    limit: int = 25,
) -> list[RoleRow]:
    """Role usage statistics, sorted by total tokens descending."""
    start_date, end_date = resolve_date(since, until, days)
    if sessions is None:
        sessions = load_sessions(sessions_root=sessions_root, project=project,
                                 since=start_date, until=end_date)

    by_role: dict[str, dict] = defaultdict(lambda: {
        'sessions': set(), 'input': 0, 'output': 0, 'reasoning': 0, 'total': 0})
    for e in all_events(sessions):
        r = by_role[e.role or 'main']
        r['sessions'].add(e.session_id)
        r['input'] += e.input
        r['output'] += e.output
        r['reasoning'] += e.reasoning
        r['total'] += e.total

    rows = [
        RoleRow(  # type: ignore
            role=role,
            sessions=len(d['sessions']),
            input_tokens_raw=d['input'],
            output_tokens_raw=d['output'],
            reasoning_tokens_raw=d['reasoning'],
            total_tokens_raw=d['total'],
        )
        for role, d in by_role.items()
    ]
    rows.sort(key=lambda r: r['total_tokens_raw'], reverse=True)
    return rows[:limit]
