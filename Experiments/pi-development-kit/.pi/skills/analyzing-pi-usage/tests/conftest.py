"""Shared test setup: sys.path, synthetic session-file builders, fixture paths.

The builders construct pi session JSONL files in the exact live shape (see
references/pi-session-format.md) so parser tests never depend on the host's
~/.pi data.
"""

import json
import sys
from pathlib import Path

import pytest

SCRIPT_DIR = Path(__file__).resolve().parent.parent / 'script'
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

FIXTURES_DIR = Path(__file__).resolve().parent / 'fixtures'


# ── Synthetic session builders ───────────────────────────────────────────────

def encode_dir(cwd: str) -> str:
    """Sessions-root directory encoding for a cwd (see format reference)."""
    return '--' + cwd.replace('/', '-') + '--'


def write_session(
    root: Path,
    cwd: str,
    session_id: str,
    ts: str,
    entries: list[dict],
    name: str | None = None,
    parent_session: str | None = None,
    malformed_lines: list[str] | None = None,
) -> Path:
    """Write one synthetic session file under a sessions root."""
    d = root / encode_dir(cwd)
    d.mkdir(parents=True, exist_ok=True)
    header = {
        'type': 'session', 'version': 3, 'id': session_id,
        'timestamp': ts, 'cwd': cwd,
    }
    if parent_session:
        header['parentSession'] = parent_session
    lines = [json.dumps(header)]
    for e in entries:
        lines.append(json.dumps(e))
    if name is not None:
        lines.append(json.dumps({'type': 'session_info', 'name': name}))
    for m in malformed_lines or []:
        lines.append(m)
    path = d / f'{ts}_{session_id}.jsonl'
    path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    return path


def user_msg(eid: str, parent: str | None, ts: str, text: str) -> dict:
    return {
        'id': eid, 'parentId': parent, 'type': 'message', 'timestamp': ts,
        'message': {'role': 'user',
                    'content': [{'type': 'text', 'text': text}]},
    }


def assistant_msg(
    eid: str, parent: str | None, ts: str, model: str,
    input: int, output: int = 0, reasoning: int = 0,
    cache_read: int = 0, cache_write: int = 0, cost: float = 0.0,
    provider: str = 'test',
) -> dict:
    return {
        'id': eid, 'parentId': parent, 'type': 'message', 'timestamp': ts,
        'message': {
            'role': 'assistant', 'model': model, 'provider': provider,
            'content': [],
            'usage': {
                'input': input, 'output': output,
                'cacheRead': cache_read, 'cacheWrite': cache_write,
                'reasoning': reasoning,
                'totalTokens': input + output + reasoning,
                'cost': {'input': 0.0, 'output': 0.0, 'cacheRead': 0.0,
                         'cacheWrite': 0.0, 'total': cost},
            },
        },
    }


def tool_result_msg(eid: str, parent: str | None, ts: str, tool: str,
                    details: dict | None = None) -> dict:
    return {
        'id': eid, 'parentId': parent, 'type': 'message', 'timestamp': ts,
        'message': {
            'role': 'toolResult', 'toolName': tool,
            'toolCallId': f'call_{eid}', 'details': details or {},
            'usage': None,
        },
    }


def subagent_result(
    agent: str, model: str, input: int, output: int, cost: float,
    turns: int, context: int, stop: str = 'end_turn',
    messages: list[dict] | None = None,
) -> dict:
    """One entry of a subagent toolResult's details.results array."""
    r = {
        'agent': agent, 'model': model, 'stopReason': stop,
        'usage': {
            'input': input, 'output': output, 'cacheRead': 0, 'cacheWrite': 0,
            'cost': cost, 'contextTokens': context, 'turns': turns,
        },
    }
    if messages is not None:
        r['messages'] = messages
    return r


def compaction_entry(eid: str, parent: str | None, ts: str,
                     input: int, output: int, reasoning: int = 0,
                     cost: float = 0.0) -> dict:
    return {
        'id': eid, 'parentId': parent, 'type': 'compaction', 'timestamp': ts,
        'usage': {'input': input, 'output': output, 'cacheRead': 0,
                  'cacheWrite': 0, 'reasoning': reasoning,
                  'totalTokens': input + output + reasoning,
                  'cost': {'total': cost}},
    }


# ── Fixtures ─────────────────────────────────────────────────────────────────

@pytest.fixture
def sessions_root(tmp_path) -> Path:
    """Empty sessions root ready for write_session()."""
    root = tmp_path / 'sessions'
    root.mkdir()
    return root
