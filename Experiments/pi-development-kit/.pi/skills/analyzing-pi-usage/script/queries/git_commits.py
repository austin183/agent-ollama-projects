#!/usr/bin/env python3
"""Git commit statistics for pi usage analytics.

Ported unchanged in behavior from the opencode kit (git-based, not DB-based):
productivity is computed by matching session dates to commit dates, since
neither harness records per-session file-change counts.
"""

import logging
import subprocess
from collections import defaultdict
from pathlib import Path
from typing import Optional

from .utils import resolve_date

logger = logging.getLogger(__name__)


def _find_repo(start: Path) -> Optional[Path]:
    """Nearest ancestor of ``start`` containing a .git, or None.

    Bounded: Path('/').parent == Path('/'), so stop at the filesystem root.
    """
    check = start
    while True:
        if (check / '.git').exists():
            return check
        if check == check.parent:
            return None
        check = check.parent


def _repo_root_and_filter(project: Optional[str]) -> tuple[Optional[str], Optional[str]]:
    """Resolve (repo_root, path_filter) for git scoping.

    Returns (None, None) when no git data applies. path_filter is the
    project's path relative to the repo root (trailing '/'), or None when
    the project IS the repo root.
    """
    if project:
        p = Path(project).expanduser()
        if not p.is_absolute():
            p = Path.cwd() / p
        p = p.resolve()
        # 1) The project's own repo (its own directory or an ancestor).
        if p.exists():
            repo = _find_repo(p)
            if repo is not None:
                rel = p.relative_to(repo)
                return str(repo), (None if rel == Path('.') else f'{rel.as_posix()}/')
        # 2) The CWD repo, but only when it actually contains the project
        #    (e.g. relative project names resolved against the CWD).
        cwd_repo = _find_repo(Path.cwd())
        if cwd_repo is not None:
            try:
                rel = p.relative_to(cwd_repo)
            except ValueError:
                rel = None
            if rel is not None:
                return str(cwd_repo), (None if rel == Path('.') else f'{rel.as_posix()}/')
        # 3) Project outside any repo: no git data, rather than guessing.
        return None, None
    return str(Path.cwd()), None


def _run_git_log(repo_root: Optional[str], path_filter: Optional[str], start_date: str, end_date: str) -> Optional[str]:
    if repo_root is None:
        return None
    try:
        cmd = [
            'git', '-C', repo_root,
            'log', '--reverse', '--numstat', '--date=short',
            f'--since={start_date}', f'--until={end_date}T23:59:59',
            '--pretty=format:COMMIT:%h|%ad|%s',
        ]
        if path_filter:
            cmd += ['--', path_filter]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        if result.returncode != 0:
            logger.error("Git log command failed: %s", result.stderr)
            return None
        return result.stdout
    except subprocess.TimeoutExpired:
        logger.error("Git log command timed out")
        return None
    except Exception as e:
        logger.error("Unexpected error fetching git commits: %s", e)
        return None


def _parse_commits(output: str) -> list[dict]:
    commits = []
    current = None
    for line in output.splitlines():
        line = line.rstrip('\n')
        if line.startswith('COMMIT:'):
            if current:
                commits.append(current)
            parts = line[7:].split('|', 2)
            current = {
                'sha': parts[0],
                'date': parts[1],
                'message': parts[2] if len(parts) > 2 else '',
                'adds': 0, 'dels': 0,
                'test_adds': 0, 'test_dels': 0,
                'is_test': False,
            }
        elif current and line and '\t' in line:
            parts = line.split('\t')
            if len(parts) >= 3:
                try:
                    a = int(parts[0]) if parts[0] != '-' else 0
                    d = int(parts[1]) if parts[1] != '-' else 0
                    fpath = parts[2]
                    current['adds'] += a
                    current['dels'] += d
                    if 'Test' in fpath or 'test' in fpath.lower():
                        current['test_adds'] += a
                        current['test_dels'] += d
                        current['is_test'] = True
                except ValueError:
                    pass
    if current:
        commits.append(current)

    cum_all = 0
    cum_test = 0
    for c in commits:
        cum_all += c['adds'] - c['dels']
        cum_test += c['test_adds'] - c['test_dels']
        c['cum_all'] = cum_all
        c['cum_test'] = cum_test
    return commits


def fetch(
    db_path: Optional[str] = None,   # ignored (kept for call-site parity)
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
) -> list[dict]:
    """Per-commit git statistics with numstat add/del counts."""
    start_date, end_date = resolve_date(since, until, days)
    repo_root, path_filter = _repo_root_and_filter(project)
    output = _run_git_log(repo_root, path_filter, start_date, end_date)
    if output is None:
        return []
    return _parse_commits(output)


def fetch_daily(
    db_path: Optional[str] = None,   # ignored (kept for call-site parity)
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
) -> list[dict]:
    """Daily git aggregates (commits/adds/dels with test-file breakdown)."""
    commits = fetch(project=project, since=since, until=until, days=days)
    daily: dict[str, dict] = defaultdict(
        lambda: {'commits': 0, 'adds': 0, 'dels': 0, 'test_adds': 0, 'test_dels': 0})
    for c in commits:
        d = daily[c['date']]
        d['commits'] += 1
        d['adds'] += c['adds']
        d['dels'] += c['dels']
        d['test_adds'] += c['test_adds']
        d['test_dels'] += c['test_dels']
    return [
        {'date': k, **daily[k]}
        for k in sorted(daily)
    ]
