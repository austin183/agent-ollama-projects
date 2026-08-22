#!/usr/bin/env python3
"""Git commit statistics for pi usage analytics.

pi does not record per-session file changes, so change attribution comes
from two sources:

1. **Measured** — a `Pi-Session: <uuid>` commit trailer (kit convention, see
   the committer agent and SKILL.md) names the session that made the commit's
   changes. Parsed here into `commit['session_id']`.
2. **Estimated** — when no trailer is present, the report falls back to
   matching session dates to commit dates.
"""

import logging
import os
import re
import subprocess
from collections import defaultdict
from pathlib import Path
from typing import Optional

from .utils import resolve_date

logger = logging.getLogger(__name__)

# `Pi-Session: <uuid>` trailer line (git trailer format: last paragraph of the
# commit message). UUID shape: 8-4-4-4-12 hex. Last occurrence wins.
_PI_SESSION_RE = re.compile(
    r'^Pi-Session:\s*([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}'
    r'-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s*$',
    re.MULTILINE,
)

# A genuine marker line is `COMMIT:<sha>|<YYYY-MM-DD>|…` — the shape check
# keeps commit-message body lines that happen to start with "COMMIT:"
# from being misparsed as new commits (now that %B is in the output).
_COMMIT_MARKER_RE = re.compile(r'^COMMIT:[0-9a-f]{7,40}\|\d{4}-\d{2}-\d{2}\|')

# Record separator terminating the message block (%x1e in the log format).
_MSG_END = '\x1e'


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
            # Explicit UTC bounds: bare dates are parsed as local time and
            # Apple Git's date-only parsing is unreliable at boundaries.
            f'--since={start_date}T00:00:00Z', f'--until={end_date}T23:59:59Z',
            # %B (full message) ends with a newline, so %x1e lands on its own
            # line — an unambiguous message terminator.
            '--pretty=format:COMMIT:%h|%ad|%s%nMSG:%B%x1e',
        ]
        if path_filter:
            cmd += ['--', path_filter]
        # TZ=UTC so --date=short buckets commits by UTC day, matching the
        # UTC-day bucketing of session events (local time would mis-join
        # commits across the UTC date boundary).
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=60,
            env={**os.environ, 'TZ': 'UTC'})
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


def _extract_session_id(message: str) -> Optional[str]:
    """Pull the `Pi-Session:` trailer (last one wins) from a commit message."""
    matches = _PI_SESSION_RE.findall(message)
    return matches[-1].lower() if matches else None


def _parse_commits(output: str) -> list[dict]:
    commits = []
    current = None
    in_msg = False
    msg_parts: list[str] = []

    def close_msg() -> None:
        nonlocal in_msg, msg_parts
        if current is not None and in_msg:
            current['session_id'] = _extract_session_id('\n'.join(msg_parts))
        in_msg = False
        msg_parts = []

    # Split on '\n' only: str.splitlines() also breaks on \x1e (the message
    # terminator) and would never surface it as a line.
    for line in output.split('\n'):
        line = line.rstrip('\n')
        if _COMMIT_MARKER_RE.match(line):
            if current:
                close_msg()
                commits.append(current)
            parts = line[7:].split('|', 2)
            current = {
                'sha': parts[0],
                'date': parts[1],
                'message': parts[2] if len(parts) > 2 else '',
                'session_id': None,
                'adds': 0, 'dels': 0,
                'test_adds': 0, 'test_dels': 0,
                'is_test': False,
            }
        elif current is None:
            continue
        elif in_msg:
            if line.endswith(_MSG_END):
                content = line[:-len(_MSG_END)]
                if content:
                    msg_parts.append(content)
                close_msg()
            else:
                msg_parts.append(line)
        elif line.startswith('MSG:'):
            in_msg = True
            msg_parts = [line[len('MSG:'):]]
        elif line and '\t' in line:
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
        close_msg()
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
    """Per-commit git statistics with numstat add/del counts.

    Each commit dict carries `session_id` — the UUID from a `Pi-Session:`
    commit trailer (the session that made the changes), or None when the
    commit predates the convention / carries no trailer.
    """
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


def summarize_attribution(commits: list[dict]) -> dict:
    """Aggregate per-session change attribution from `Pi-Session:` trailers.

    Returns `{'attributed_commits', 'unattributed_commits', 'sessions_measured',
    'by_session': {session_id: {commits, adds, dels, test_adds, test_dels}}}`.
    All-zero for a commit set without trailers (pure-estimate path).
    """
    by_session: dict[str, dict] = {}
    attributed = 0
    for c in commits:
        sid = c.get('session_id')
        if not sid:
            continue
        attributed += 1
        row = by_session.setdefault(sid, {
            'commits': 0, 'adds': 0, 'dels': 0,
            'test_adds': 0, 'test_dels': 0,
        })
        row['commits'] += 1
        row['adds'] += c.get('adds', 0)
        row['dels'] += c.get('dels', 0)
        row['test_adds'] += c.get('test_adds', 0)
        row['test_dels'] += c.get('test_dels', 0)
    return {
        'attributed_commits': attributed,
        'unattributed_commits': len(commits) - attributed,
        'sessions_measured': len(by_session),
        'by_session': by_session,
    }
