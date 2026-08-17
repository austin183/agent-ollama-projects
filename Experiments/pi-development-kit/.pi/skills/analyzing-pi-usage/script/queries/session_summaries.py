#!/usr/bin/env python3
"""Join with [docs directory]/sessions/*.json session summaries.

Session summaries are the human-curated companion to pi's raw JSONL (purpose,
outcome, decisions, role, pi session ID). This query aggregates them for the
productivity section: purpose/outcome/role breakdowns, date-filtered.
"""

import json
import logging
from pathlib import Path
from typing import Optional

from .utils import resolve_date

logger = logging.getLogger(__name__)

DEFAULT_DOCS_DIRS = ('_agent_docs', 'docs')


def find_sessions_dir(project: str, docs_dir: Optional[str] = None) -> Optional[Path]:
    """Locate the session summaries directory for a project.

    Explicit ``docs_dir`` wins; otherwise probe the kit's conventional
    locations (``_agent_docs``, then ``docs``).
    """
    root = Path(project)
    if docs_dir:
        p = (root / docs_dir).resolve() if not Path(docs_dir).is_absolute() else Path(docs_dir)
        return p if p.is_dir() else None
    for name in DEFAULT_DOCS_DIRS:
        p = root / name / 'sessions'
        if p.is_dir():
            return p
    return None


def fetch(
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
    docs_dir: Optional[str] = None,
) -> dict:
    """Aggregate session summaries for a project within the date range.

    Returns:
        dict with 'total', 'by_purpose', 'by_outcome', 'by_role'
        (all empty when no summaries directory exists).
    """
    start_date, end_date = resolve_date(since, until, days)
    empty = {'total': 0, 'by_purpose': {}, 'by_outcome': {}, 'by_role': {}}
    if not project:
        return empty

    sessions_dir = find_sessions_dir(project, docs_dir)
    if not sessions_dir:
        return empty

    by_purpose: dict[str, int] = {}
    by_outcome: dict[str, int] = {}
    by_role: dict[str, int] = {}
    total = 0

    for f in sorted(sessions_dir.glob('*.json')):
        try:
            with open(f, 'r', encoding='utf-8') as fp:
                data = json.load(fp)
        except (json.JSONDecodeError, OSError) as e:
            logger.warning("Skipping unparseable summary %s: %s", f.name, e)
            continue
        if not isinstance(data, dict):
            continue
        day = str(data.get('date', ''))
        if not day or day < start_date or day > end_date:
            continue
        total += 1
        purpose = str(data.get('purpose', 'unknown'))
        outcome = str(data.get('outcome', 'unknown'))
        role = str(data.get('agent_role', 'unknown'))
        by_purpose[purpose] = by_purpose.get(purpose, 0) + 1
        by_outcome[outcome] = by_outcome.get(outcome, 0) + 1
        by_role[role] = by_role.get(role, 0) + 1

    return {
        'total': total,
        'by_purpose': dict(sorted(by_purpose.items())),
        'by_outcome': dict(sorted(by_outcome.items())),
        'by_role': dict(sorted(by_role.items())),
    }
