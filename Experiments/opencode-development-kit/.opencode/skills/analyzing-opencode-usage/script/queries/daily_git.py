#!/usr/bin/env python3
"""Daily git statistics query for [ProjectName] LLM usage analytics.

Aggregates git commit data by day. This query is executed via git log, not directly from SQLite.
Uses read-only connections for any database access.
"""

import logging
import subprocess
from pathlib import Path
from typing import Optional
from collections import defaultdict

from .utils import _resolve_date

logger = logging.getLogger(__name__)


def fetch(
    db_path: Optional[str] = None,
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
) -> list[dict]:
    """Fetch daily git statistics.

    Args:
        db_path: Ignored (git data not from DB).
        project: Project directory (used to determine repo root).
        since: Start date (YYYY-MM-DD).
        until: End date (YYYY-MM-DD).
        days: Number of days from today (overrides since/until).

    Returns:
        List of daily statistics dictionaries.
    """
    start_date, end_date = _resolve_date(since, until, days)

    # Determine repo root - use project path or current working directory
    repo_root = None
    if project:
        # Look for .git in project path or parent directories
        # Resolve to absolute first so Path('.').parent doesn't loop on itself
        check_path = Path(project).resolve()
        while check_path and not (check_path / '.git').exists():
            check_path = check_path.parent
        if check_path:
            repo_root = str(check_path)
    else:
        repo_root = str(Path.cwd())

    skip_shas = "a877b47 2f5d923 4c13f15 f43f886"

    # Build path filter to scope git log to this project directory
    path_filter = None
    if project:
        path_filter = Path(project).name + '/'

    try:
        cmd = [
            'git',
            '-C', repo_root,
            'log',
            '--reverse',
            '--numstat',
            '--date=short',
            f'--since={start_date}',
            f'--until={end_date}T23:59:59',
            '--pretty=format:COMMIT:%h|%ad|%s',
        ]
        if path_filter:
            cmd += ['--', path_filter]

        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=60,
        )

        if result.returncode != 0:
            logger.error("Git log command failed: %s", result.stderr)
            return []

        daily = _parse_daily_git_output(result.stdout, skip_shas.split())
        return daily

    except subprocess.TimeoutExpired:
        logger.error("Git log command timed out")
        return []
    except Exception as e:
        logger.error("Unexpected error fetching daily git stats: %s", e)
        return []


def _parse_daily_git_output(output: str, skip_shas: list[str]) -> list[dict]:
    """Parse git log --numstat output into daily aggregated statistics."""
    daily = defaultdict(lambda: {'commits': 0, 'adds': 0, 'dels': 0, 'test_adds': 0, 'test_dels': 0})
    current = None

    for line in output.splitlines():
        line = line.rstrip('\n')
        if line.startswith('COMMIT:'):
            if current and current['sha'] not in skip_shas:
                d = daily[current['date']]
                d['commits'] += 1
                d['adds'] += current['adds']
                d['dels'] += current['dels']
                d['test_adds'] += current['test_adds']
                d['test_dels'] += current['test_dels']
            parts = line[7:].split('|', 2)
            current = {'sha': parts[0], 'date': parts[1], 'adds': 0, 'dels': 0, 'test_adds': 0, 'test_dels': 0}
        elif current and line and '\t' in line:
            parts = line.split('\t')
            if len(parts) >= 2:
                try:
                    a = int(parts[0]) if parts[0] != '-' else 0
                    d = int(parts[1]) if parts[1] != '-' else 0
                    current['adds'] += a
                    current['dels'] += d
                    if 'Test' in parts[2] or 'test' in parts[2].lower():
                        current['test_adds'] += a
                        current['test_dels'] += d
                except ValueError:
                    pass

    if current and current['sha'] not in skip_shas:
        d = daily[current['date']]
        d['commits'] += 1
        d['adds'] += current['adds']
        d['dels'] += current['dels']
        d['test_adds'] += current['test_adds']
        d['test_dels'] += current['test_dels']

    result = []
    for date_key in sorted(daily.keys()):
        d = daily[date_key]
        result.append({
            'date': date_key,
            'commits': d['commits'],
            'adds': d['adds'],
            'dels': d['dels'],
            'test_adds': d['test_adds'],
            'test_dels': d['test_dels'],
        })

    return result
