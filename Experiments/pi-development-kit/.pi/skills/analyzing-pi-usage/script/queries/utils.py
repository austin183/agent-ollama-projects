#!/usr/bin/env python3
"""Shared utilities for pi usage query modules.

Contains the role-category mapping (daily/weekly stacked breakdowns), the
model-id adapter for the pricing table, and the date-resolution helper.
"""

import logging
from datetime import date, timedelta
from typing import Optional, Tuple

logger = logging.getLogger(__name__)

# Role → daily/weekly category mapping.
#
# Mirrors the opencode kit's agent categories: opencode's default "general"
# session role counted as build, so pi's unmarked main-session work (role
# "main") maps to the same bucket. "explore" has no pi counterpart and stays
# in the shape for report parity (always 0).
REVIEW_ROLES = frozenset({'diff-review', 'solid-review', 'world-review'})
PLAN_ROLES = frozenset({'planner', 'plan-bdd'})


def role_category(role: Optional[str]) -> str:
    """Map a role to its stacked-chart category.

    Categories: build (main + build-*), review, plan, explore (unused), other.
    """
    role = role or 'main'
    if role == 'main' or role.startswith('build'):
        return 'build'
    if role in REVIEW_ROLES:
        return 'review'
    if role in PLAN_ROLES:
        return 'plan'
    return 'other'


def pricing_model_id(model: str) -> str:
    """Adapt a pi model id (``provider/model``) to the pricing table's keys.

    The pricing table is provider-agnostic (copied from the opencode kit); pi
    records ids as e.g. ``lmstudio/qwen-agentworld-35b-a3b`` while the table
    keys are ``qwen-agentworld-35b-a3b``. Strip the ``lmstudio/`` prefix only
    when the remainder is a known table key, so cloud provider ids
    (``anthropic/claude-sonnet-4``) look up unchanged.
    """
    if model and model.startswith('lmstudio/'):
        stripped = model[len('lmstudio/'):]
        from model_pricing import MODEL_PRICING
        if stripped in MODEL_PRICING:
            return stripped
    return model


def resolve_date(
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
) -> Tuple[str, str]:
    """Resolve date range from arguments or defaults (inclusive YYYY-MM-DD)."""
    if days is not None:
        start_date = (date.today() - timedelta(days=days)).isoformat()
        end_date = date.today().isoformat()
    else:
        start_date = _parse_or_default(since, "2000-01-01")
        end_date = _parse_or_default(until, date.today().isoformat())
    return start_date, end_date


def _parse_or_default(value: Optional[str], default: str) -> str:
    """Parse a date string, returning default if None, empty, or invalid."""
    if value is None or value.strip() == '' or value.strip().lower() == 'none':
        return default
    try:
        date.fromisoformat(value)
        return value
    except (ValueError, TypeError):
        logger.warning("Invalid date '%s', using default '%s'", value, default)
        return default


def load_sessions_for(project: Optional[str], since: Optional[str], until: Optional[str],
                      sessions_root=None):
    """Convenience: load (and date-filter) sessions for a query.

    Query modules accept a pre-loaded ``sessions`` list so a report run parses
    the JSONL once; this is the fallback when a query is called standalone.
    """
    from pathlib import Path
    from pi_sessions import load_sessions
    root = Path(sessions_root) if sessions_root else None
    return load_sessions(sessions_root=root, project=project, since=since, until=until)
