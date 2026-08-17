#!/usr/bin/env python3
"""JSONL session parser for pi usage analytics.

Parses pi's JSONL session files (``~/.pi/agent/sessions/--<cwd>--/*.jsonl``)
into an in-memory structure of *token events* — one unit of LLM token
consumption each — with per-event model and role attribution.

Token sources (each counted exactly once):

1. ``message`` entries with ``role: assistant`` — the main session's LLM turns.
   Usage from ``message.usage`` (input/output/cacheRead/cacheWrite/reasoning/cost).
2. ``compaction`` entries — summary-generation usage when the entry carries a
   ``usage`` field. ``retainedTail`` is context, not new work: it is NOT summed.
3. ``message`` entries with ``role: toolResult`` from the ``subagent`` tool —
   each entry in ``message.details.results[]`` is a subagent run with its own
   ``usage`` (input/output/cacheRead/cacheWrite/cost/contextTokens/turns),
   attributed to that run's ``agent``. The parser recurses into
   ``results[i].messages[]`` to find nested subagent runs (a subagent with the
   default toolset can delegate further).

Counting discipline: ALL entries are counted, including abandoned branches.
Every entry executed and consumed tokens, even if the user later branched
away from it. Forked session files (``parentSession``) re-list their history
with identical entry ids; entries are deduplicated by id across files so each
execution is counted once (original file wins, processed first by header
timestamp).

Role attribution:

- Subagent runs: exact — ``details.results[i].agent``.
- Main-session turns (assistant + compaction): the most recent preceding
  user-message ``Role: <name>`` marker, found by walking the ``parentId``
  chain. Templates from the pi development kit expand to a first line
  ``Role: <agent>``; sessions without markers attribute to ``main``.

See ``references/pi-session-format.md`` for the full entry-type reference.
"""

import json
import logging
import os
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

# Analytics marker convention (see the pi development kit port plan):
# prompt templates for primary roles expand to a user message whose first
# line is "Role: <agent-name>".
ROLE_MARKER_RE = re.compile(r'^Role: ([a-z-]+)')

DEFAULT_ROLE = 'main'


# ── Data model ────────────────────────────────────────────────────────────────

@dataclass
class TokenEvent:
    """One unit of LLM token consumption."""
    day: str                    # YYYY-MM-DD (UTC, from entry timestamp)
    ts: float                   # unix seconds
    kind: str                   # 'assistant' | 'compaction' | 'subagent'
    model: str
    role: str
    session_id: str             # session header id
    input: int = 0
    output: int = 0
    cache_read: int = 0
    cache_write: int = 0
    reasoning: int = 0
    cost: float = 0.0
    # Subagent-only fields
    agent: str = ''
    turns: int = 0
    context_tokens: int = 0
    depth: int = 0              # 0 = direct child of the main session
    stop_reason: str = ''

    @property
    def total(self) -> int:
        """Raw tokens: input + output + reasoning (same convention as the opencode kit)."""
        return self.input + self.output + self.reasoning


@dataclass
class PiSession:
    """A parsed pi session file with its extracted token events."""
    session_id: str             # header id (uuid)
    file: str                   # path to the .jsonl file
    cwd: str
    header_ts: float
    name: str = ''              # from the latest session_info entry
    parent_session: str = ''    # header parentSession (fork source), '' if none
    first_user_text: str = ''   # first user message text, truncated (top-sessions title)
    header_ts_day: str = ''     # header timestamp day (YYYY-MM-DD)
    events: list[TokenEvent] = field(default_factory=list)
    malformed_lines: int = 0
    entry_count: int = 0

    def events_in_range(self, since: Optional[str], until: Optional[str]) -> list[TokenEvent]:
        return [e for e in self.events if _day_in_range(e.day, since, until)]


# ── Low-level parsing ─────────────────────────────────────────────────────────

def _iso_to_unix(ts: str) -> float:
    """Parse an ISO-8601 timestamp (as used in pi session entries) to unix seconds."""
    try:
        if ts.endswith('Z'):
            ts = ts[:-1] + '+00:00'
        return datetime.fromisoformat(ts).timestamp()
    except (ValueError, TypeError):
        return 0.0


def _day_in_range(day: str, since: Optional[str], until: Optional[str]) -> bool:
    if since and day < since:
        return False
    if until and day > until:
        return False
    return True


def _usage_int(u: dict, *keys) -> int:
    for k in keys:
        v = u.get(k)
        if isinstance(v, (int, float)):
            return int(v)
    return 0


def _usage_cost(u: dict) -> float:
    """Extract a dollar cost from a pi Usage object.

    Main-session usage.cost is an object ({input, output, cacheRead,
    cacheWrite, total}); subagent results carry a flat numeric cost.
    """
    c = u.get('cost')
    if isinstance(c, (int, float)):
        return float(c)
    if isinstance(c, dict):
        return float(c.get('total', 0) or 0)
    return 0.0


def _message_text(message: dict) -> str:
    """Flatten message content (string or content-block list) to text."""
    content = message.get('content')
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and block.get('type') == 'text':
                parts.append(block.get('text', ''))
        return '\n'.join(parts)
    return ''


def _extract_role_marker(message: dict) -> str:
    """Return the Role: marker from a user message, or the default role."""
    text = _message_text(message).strip()
    if text:
        m = ROLE_MARKER_RE.match(text.splitlines()[0])
        if m:
            return m.group(1)
    return DEFAULT_ROLE


def parse_session_file(path: Path) -> tuple[dict, list[dict], int]:
    """Parse one session JSONL file.

    Returns:
        (header, entries, malformed_line_count). The header is the first
        ``type: session`` object ({} when the file has none); entries are all
        non-header lines in file order. Malformed lines are skipped and
        counted, never fatal.
    """
    header: dict = {}
    entries: list[dict] = []
    malformed = 0
    with open(path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                malformed += 1
                continue
            if not isinstance(obj, dict):
                malformed += 1
                continue
            if obj.get('type') == 'session' and not header:
                header = obj
            else:
                entries.append(obj)
    return header, entries, malformed


def default_sessions_root() -> Path:
    """Default pi session storage root (override via --sessions-root)."""
    return Path(os.environ.get('PI_SESSIONS_ROOT', str(Path.home() / '.pi' / 'agent' / 'sessions')))


# ── Event extraction ──────────────────────────────────────────────────────────

class _Extractor:
    """Extracts token events from one parsed session file."""

    def __init__(self, header: dict, entries: list[dict], session: 'PiSession'):
        self.header = header
        self.entries = entries
        self.session = session
        self.by_id: dict[str, dict] = {
            e['id']: e for e in entries if isinstance(e.get('id'), str)
        }
        self.role_memo: dict[str, str] = {}
        self.model_memo: dict[str, str] = {}

    # -- role / model attribution ------------------------------------------

    def _role_for(self, entry: dict) -> str:
        """Most recent preceding user-message Role: marker (walks parentId chain)."""
        cur = self.by_id.get(entry.get('id', ''))
        seen: set = set()
        while cur and id(cur) not in seen:
            seen.add(id(cur))
            if cur.get('type') == 'message':
                msg = cur.get('message') or {}
                if msg.get('role') == 'user':
                    key = cur.get('id', '')
                    if key not in self.role_memo:
                        self.role_memo[key] = _extract_role_marker(msg)
                    return self.role_memo[key]
            parent = cur.get('parentId')
            cur = self.by_id.get(parent, None) if parent else None
        return DEFAULT_ROLE

    def _model_for(self, entry: dict) -> str:
        """Model for an entry that carries no model of its own (compaction).

        Uses the nearest preceding assistant message's model, falling back to
        the last model_change before the entry, then 'unknown'.
        """
        cur = self.by_id.get(entry.get('id', ''))
        seen: set = set()
        while cur and id(cur) not in seen:
            seen.add(id(cur))
            if cur.get('type') == 'message':
                msg = cur.get('message') or {}
                if msg.get('role') == 'assistant' and msg.get('model'):
                    return msg['model']
            elif cur.get('type') == 'model_change' and cur.get('modelId'):
                return f"{cur.get('provider', '')}/{cur['modelId']}".rstrip('/')
            parent = cur.get('parentId')
            cur = self.by_id.get(parent, None) if parent else None
        return 'unknown'

    # -- event emission ------------------------------------------------------

    def extract(self, seen_entry_ids: set) -> None:
        """Populate self.session.events.

        Entries whose id was already emitted by an earlier-processed file
        (forked history) are skipped so each execution is counted once.
        """
        session_id = self.header.get('id', '')
        name = ''
        for e in self.entries:
            if e.get('type') == 'session_info' and e.get('name'):
                name = e['name']
        self.session.name = name

        for entry in self.entries:
            eid = entry.get('id')
            if not eid or eid in seen_entry_ids:
                continue
            seen_entry_ids.add(eid)
            self.session.entry_count += 1

            day = (entry.get('timestamp') or '')[:10]
            ts = _iso_to_unix(entry.get('timestamp', ''))

            etype = entry.get('type')
            if etype == 'message':
                self._extract_message(entry, day, ts, session_id)
            elif etype == 'compaction':
                usage = entry.get('usage')
                if isinstance(usage, dict):
                    self.session.events.append(TokenEvent(
                        day=day, ts=ts, kind='compaction',
                        model=self._model_for(entry),
                        role=self._role_for(entry),
                        session_id=session_id,
                        input=_usage_int(usage, 'input'),
                        output=_usage_int(usage, 'output'),
                        cache_read=_usage_int(usage, 'cacheRead'),
                        cache_write=_usage_int(usage, 'cacheWrite'),
                        reasoning=_usage_int(usage, 'reasoning'),
                        cost=_usage_cost(usage),
                    ))
            # Other entry types (model_change, label, custom, ...) carry no usage.

    def _extract_message(self, entry: dict, day: str, ts: float, session_id: str) -> None:
        msg = entry.get('message') or {}
        role = msg.get('role')
        if role == 'user':
            if not self.session.first_user_text:
                self.session.first_user_text = _message_text(msg).strip()[:80]
        elif role == 'assistant':
            usage = msg.get('usage') or {}
            self.session.events.append(TokenEvent(
                day=day, ts=ts, kind='assistant',
                model=msg.get('model') or 'unknown',
                role=self._role_for(entry),
                session_id=session_id,
                input=_usage_int(usage, 'input'),
                output=_usage_int(usage, 'output'),
                cache_read=_usage_int(usage, 'cacheRead'),
                cache_write=_usage_int(usage, 'cacheWrite'),
                reasoning=_usage_int(usage, 'reasoning'),
                cost=_usage_cost(usage),
            ))
        elif role == 'toolResult' and msg.get('toolName') == 'subagent':
            results = (msg.get('details') or {}).get('results')
            if isinstance(results, list) and results:
                # Prefer details.results[] as the source of truth for subagent
                # usage (the toolResult's top-level usage is not populated by
                # the subagent extension).
                for result in results:
                    self._emit_subagent_result(result, day, ts, session_id, depth=0)

    def _emit_subagent_result(self, result: dict, day: str, ts: float,
                              session_id: str, depth: int) -> None:
        if not isinstance(result, dict):
            return
        agent = result.get('agent') or 'unknown'
        usage = result.get('usage') or {}
        self.session.events.append(TokenEvent(
            day=day, ts=ts, kind='subagent',
            model=result.get('model') or 'unknown',
            role=agent,
            session_id=session_id,
            input=_usage_int(usage, 'input'),
            output=_usage_int(usage, 'output'),
            cache_read=_usage_int(usage, 'cacheRead'),
            cache_write=_usage_int(usage, 'cacheWrite'),
            reasoning=0,  # subagent usage has no reasoning breakdown
            cost=_usage_cost(usage),
            agent=agent,
            turns=int(usage.get('turns', 0) or 0),
            context_tokens=int(usage.get('contextTokens', 0) or 0),
            depth=depth,
            stop_reason=result.get('stopReason', '') or '',
        ))
        # Recurse: a subagent with the default toolset can delegate further.
        # Nested usage is NOT included in the parent result's usage.
        for m in result.get('messages') or []:
            if isinstance(m, dict) and m.get('role') == 'toolResult':
                nested = (m.get('details') or {}).get('results')
                if isinstance(nested, list):
                    for r in nested:
                        self._emit_subagent_result(r, day, ts, session_id, depth=depth + 1)


# ── Loading & filtering ───────────────────────────────────────────────────────

def list_session_files(sessions_root: Optional[Path] = None) -> list[Path]:
    """All session JSONL files under the sessions root, header-timestamp ordered."""
    root = sessions_root or default_sessions_root()
    files = sorted(root.glob('*/*.jsonl')) if root.is_dir() else []
    # Order by header timestamp so original sessions are processed before
    # forks that copy their history (fork dedup: first file wins).
    def header_ts(p: Path) -> float:
        try:
            with open(p, 'r', encoding='utf-8') as f:
                first = f.readline().strip()
            return _iso_to_unix(json.loads(first).get('timestamp', ''))
        except (OSError, json.JSONDecodeError, ValueError):
            return 0.0
    return sorted(files, key=header_ts)


def session_matches_project(header: dict, project: str) -> bool:
    """Project filter: substring match on the header cwd (symlink-resolved).

    The sessions directory encoding uses the *real* path (e.g. /tmp ->
    /private/tmp on macOS), so both sides are resolved before matching.
    """
    cwd = header.get('cwd', '')
    if not cwd:
        return False
    try:
        real_project = os.path.realpath(project)
    except OSError:
        real_project = project
    real_cwd = os.path.realpath(cwd)
    return real_project in real_cwd or project in cwd


def load_sessions(
    sessions_root: Optional[Path] = None,
    project: Optional[str] = None,
    since: Optional[str] = None,
    until: Optional[str] = None,
    apply_date_filter: bool = True,
) -> list[PiSession]:
    """Load and parse session files, returning sessions with token events.

    Args:
        sessions_root: Override for the pi sessions root (default:
            ``~/.pi/agent/sessions``).
        project: Substring to match against each session's cwd (resolved).
        since/until: Inclusive YYYY-MM-DD range on event days. When
            ``apply_date_filter`` is False (e.g. for all-time project range),
            all events are kept and filtering happens in the query layer.
        apply_date_filter: See above.

    Returns:
        List of PiSession objects (only sessions matching the project filter
        and, when a date filter is applied, having at least one in-range event).
    """
    root = sessions_root or default_sessions_root()
    seen_entry_ids: set = set()
    sessions: list[PiSession] = []

    for path in list_session_files(root):
        header, entries, malformed = parse_session_file(path)
        if not header:
            continue
        if project and not session_matches_project(header, project):
            continue

        session = PiSession(
            session_id=header.get('id', ''),
            file=str(path),
            cwd=header.get('cwd', ''),
            header_ts=_iso_to_unix(header.get('timestamp', '')),
            header_ts_day=(header.get('timestamp') or '')[:10],
            parent_session=header.get('parentSession', '') or '',
            malformed_lines=malformed,
        )
        _Extractor(header, entries, session).extract(seen_entry_ids)

        if apply_date_filter and (since or until):
            session.events = session.events_in_range(since, until)
        if not session.events:
            continue
        sessions.append(session)

    return sessions


# ── Aggregation helpers (shared by query modules) ─────────────────────────────

def all_events(sessions: list[PiSession]) -> list[TokenEvent]:
    return [e for s in sessions for e in s.events]


def resolve_date(
    since: Optional[str] = None,
    until: Optional[str] = None,
    days: Optional[int] = None,
) -> tuple[str, str]:
    """Resolve a (since, until) inclusive pair; mirrors queries.utils semantics."""
    from datetime import date, timedelta
    if days is not None:
        start = (date.today() - timedelta(days=days)).isoformat()
        end = date.today().isoformat()
    else:
        start = since or '2000-01-01'
        end = until or date.today().isoformat()
    return start, end


if __name__ == '__main__':
    # Quick manual inspection: python3 pi_sessions.py [project-substring]
    proj = sys.argv[1] if len(sys.argv) > 1 else None
    ss = load_sessions(project=proj)
    for s in ss:
        print(f"{s.session_id[:8]}  {s.cwd}  name={s.name!r}  events={len(s.events)}  "
              f"malformed={s.malformed_lines}  total={sum(e.total for e in s.events)}")
