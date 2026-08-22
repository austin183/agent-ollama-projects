#!/usr/bin/env python3
"""Shared utilities for query modules.

Contains helper functions used across multiple query modules to avoid duplication.
"""

import logging
from datetime import date, timedelta
from typing import Any, Optional, Tuple

logger = logging.getLogger(__name__)


def _resolve_date(
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None
) -> Tuple[str, str]:
    """Resolve date range from arguments or defaults.

    Args:
        since: Start date (YYYY-MM-DD). None or empty string uses default.
        until: End date (YYYY-MM-DD). None or empty string uses today.
        days: Number of days from today (overrides since/until).

    Returns:
        Tuple of (start_date, end_date) as ISO format strings.

    Raises:
        ValueError: If since or until is provided but not a valid YYYY-MM-DD date.
    """
    if days is not None:
        start_date = (date.today() - timedelta(days=days)).isoformat()
        end_date = date.today().isoformat()
    else:
        # Use _parse_or_default for input validation: rejects literal 'None'
        # string, empty strings, and any string that isn't a valid YYYY-MM-DD date.
        # Falls back to default with a logged warning for invalid values.
        start_date = _parse_or_default(since, "2000-01-01")
        end_date = _parse_or_default(until, date.today().isoformat())

    return start_date, end_date


def _parse_or_default(value: Optional[str], default: str) -> str:
    """Parse a date string, returning default if None, empty, or invalid.

    Rejects literal 'None' string and any string that isn't a valid YYYY-MM-DD date.
    Logs a warning when falling back to default due to an invalid value.
    """
    if value is None or value.strip() == '' or value.strip().lower() == 'none':
        return default
    try:
        date.fromisoformat(value)
        return value
    except (ValueError, TypeError):
        logger.warning("Invalid date '%s', using default '%s'", value, default)
        return default


def _build_where(project: Optional[str]) -> Tuple[str, list]:
    """Build WHERE clause and parameters for project filtering.

    Args:
        project: Project directory path filter. Uses the full path to match
                 only sessions from that specific workspace.

    Returns:
        Tuple of (where_clause, params_list).
    """
    parts: list[str] = []
    params: list[Any] = []

    if project:
        parts.append("directory LIKE ?")
        params.append(f'%{project}%')

    where = ' AND '.join(parts) if parts else '1=1'
    return (where, params)
