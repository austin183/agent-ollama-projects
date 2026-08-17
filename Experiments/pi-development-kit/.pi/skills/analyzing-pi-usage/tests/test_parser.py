"""Parser basics: headers, message/compaction extraction, malformed lines."""

from conftest import (
    assistant_msg, compaction_entry, tool_result_msg, user_msg, write_session,
)
from pi_sessions import load_sessions, parse_session_file


TS1 = '2026-01-05T10:00:00.000Z'
TS2 = '2026-01-05T10:01:00.000Z'
TS3 = '2026-01-05T10:02:00.000Z'


def _basic_entries():
    return [
        user_msg('e1', None, TS1, 'hello'),
        assistant_msg('e2', 'e1', TS2, 'anthropic/claude-sonnet-4',
                      input=1000, output=50, reasoning=10, cost=0.01),
        tool_result_msg('e3', 'e2', TS3, 'bash', {'stdout': 'ok'}),
        assistant_msg('e4', 'e3', TS3, 'anthropic/claude-sonnet-4',
                      input=1200, output=70, reasoning=5, cost=0.02),
    ]


def test_parse_session_file_returns_header_entries_malformed(sessions_root):
    path = write_session(sessions_root, '/tmp/proj', 'sid-1', TS1, _basic_entries(),
                         malformed_lines=['{not json', '42'])
    header, entries, malformed = parse_session_file(path)
    assert header['id'] == 'sid-1'
    assert header['cwd'] == '/tmp/proj'
    assert len(entries) == 4
    assert malformed == 2


def test_load_sessions_extracts_assistant_events(sessions_root):
    write_session(sessions_root, '/tmp/proj', 'sid-1', TS1, _basic_entries())
    sessions = load_sessions(sessions_root=sessions_root, project='/tmp/proj')
    assert len(sessions) == 1
    events = sessions[0].events
    assert len(events) == 2  # assistant messages only (user/toolResult ignored)
    assert events[0].input == 1000
    assert events[0].output == 50
    assert events[0].reasoning == 10
    assert events[0].cost == 0.01
    assert events[0].total == 1060
    assert events[0].day == '2026-01-05'
    assert events[0].kind == 'assistant'
    assert events[0].session_id == 'sid-1'


def test_compaction_event_attributed_to_active_model(sessions_root):
    entries = [
        {'id': 'mc1', 'parentId': None, 'type': 'model_change',
         'timestamp': TS1, 'provider': 'lmstudio', 'modelId': 'qwen3.8-27b'},
        assistant_msg('e2', 'mc1', TS2, 'lmstudio/qwen3.8-27b', input=100),
        compaction_entry('c3', 'e2', TS3, input=900, output=120, cost=0.03),
    ]
    write_session(sessions_root, '/tmp/proj', 'sid-1', TS1, entries)
    sessions = load_sessions(sessions_root=sessions_root)
    events = sessions[0].events
    comp = [e for e in events if e.kind == 'compaction']
    assert len(comp) == 1
    assert comp[0].input == 900
    assert comp[0].model == 'lmstudio/qwen3.8-27b'
    assert comp[0].cost == 0.03


def test_session_name_from_session_info(sessions_root):
    write_session(sessions_root, '/tmp/proj', 'sid-1', TS1,
                  [assistant_msg('e1', None, TS2, 'm', input=10)],
                  name='my session name')
    sessions = load_sessions(sessions_root=sessions_root)
    assert sessions[0].name == 'my session name'


def test_first_user_text_captured(sessions_root):
    write_session(sessions_root, '/tmp/proj', 'sid-1', TS1,
                  [user_msg('e1', None, TS1, 'Do the thing'),
                   assistant_msg('e2', 'e1', TS2, 'm', input=10)])
    sessions = load_sessions(sessions_root=sessions_root)
    assert sessions[0].first_user_text == 'Do the thing'


def test_empty_session_file_dropped(sessions_root):
    # Header only, no usage-bearing entries
    write_session(sessions_root, '/tmp/proj', 'sid-1', TS1,
                  [user_msg('e1', None, TS1, 'hi')])
    sessions = load_sessions(sessions_root=sessions_root)
    assert sessions == []


def test_date_filter_excludes_out_of_range_sessions(sessions_root):
    write_session(sessions_root, '/tmp/proj', 'sid-1', TS1,
                  [assistant_msg('e1', None, TS2, 'm', input=10)])
    sessions = load_sessions(sessions_root=sessions_root,
                             since='2026-02-01', until='2026-02-28')
    assert sessions == []
    sessions = load_sessions(sessions_root=sessions_root,
                             since='2026-01-05', until='2026-01-05')
    assert len(sessions) == 1
