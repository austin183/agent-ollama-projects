#!/usr/bin/env python3
"""Summary metrics for pi usage analytics (over parsed session JSONL)."""

from typing import Optional

from pi_sessions import all_events, load_sessions
from data_access.types import SummaryRow
from .utils import resolve_date


def _empty() -> SummaryRow:
    return SummaryRow(  # type: ignore
        total_sessions=0, total_tokens_raw=0, total_input_raw=0, total_output=0,
        total_reasoning=0, cache_read=0, cache_write=0, actual_cost=0.0,
        earliest='', latest='', model_count=0, role_count=0,
    )


def fetch(
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
    sessions=None,
    sessions_root=None,
) -> SummaryRow:
    """Aggregate summary metrics over the filtered sessions."""
    start_date, end_date = resolve_date(since, until, days)
    if sessions is None:
        sessions = load_sessions(sessions_root=sessions_root, project=project,
                                 since=start_date, until=end_date)

    events = all_events(sessions)
    if not events and not sessions:
        return _empty()

    return SummaryRow(  # type: ignore
        total_sessions=len(sessions),
        total_tokens_raw=sum(e.total for e in events),
        total_input_raw=sum(e.input for e in events),
        total_output=sum(e.output for e in events),
        total_reasoning=sum(e.reasoning for e in events),
        cache_read=sum(e.cache_read for e in events),
        cache_write=sum(e.cache_write for e in events),
        actual_cost=round(sum(e.cost for e in events), 4),
        earliest=min((e.day for e in events), default=''),
        latest=max((e.day for e in events), default=''),
        model_count=len({e.model for e in events if e.model}),
        role_count=len({e.role for e in events}),
    )


def fetch_project_range(
    project: Optional[str] = None,
    sessions_root=None,
) -> dict:
    """True all-time range and session count for a project (no date filter)."""
    sessions = load_sessions(sessions_root=sessions_root, project=project,
                             since=None, until=None, apply_date_filter=False)
    events = all_events(sessions)
    return {
        'project_since': min((e.day for e in events), default=''),
        'project_until': max((e.day for e in events), default=''),
        'total_sessions_all_time': len(sessions),
    }
