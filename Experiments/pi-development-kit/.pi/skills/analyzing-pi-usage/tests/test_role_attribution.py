"""Role attribution: `Role:` markers on user messages, defaults, categories."""

from conftest import assistant_msg, user_msg, write_session
from pi_sessions import load_sessions
from queries.utils import role_category

TS1 = '2026-01-05T10:00:00.000Z'
TS2 = '2026-01-05T10:01:00.000Z'
TS3 = '2026-01-05T10:02:00.000Z'


def _events(root):
    sessions = load_sessions(sessions_root=root)
    return [e for s in sessions for e in s.events]


def test_default_role_is_main(sessions_root):
    write_session(sessions_root, '/tmp/p', 's1', TS1, [
        user_msg('e1', None, TS1, 'just a plain request'),
        assistant_msg('e2', 'e1', TS2, 'm', input=100),
    ])
    events = _events(sessions_root)
    assert [e.role for e in events] == ['main']


def test_role_marker_on_first_line(sessions_root):
    write_session(sessions_root, '/tmp/p', 's1', TS1, [
        user_msg('e1', None, TS1, 'Role: build-tdd\nImplement feature X'),
        assistant_msg('e2', 'e1', TS2, 'm', input=100),
    ])
    events = _events(sessions_root)
    assert events[0].role == 'build-tdd'


def test_marker_ignored_when_not_on_first_line(sessions_root):
    write_session(sessions_root, '/tmp/p', 's1', TS1, [
        user_msg('e1', None, TS1, 'Here is some text\nRole: diff-review'),
        assistant_msg('e2', 'e1', TS2, 'm', input=100),
    ])
    events = _events(sessions_root)
    assert events[0].role == 'main'


def test_role_persists_until_next_user_message(sessions_root):
    write_session(sessions_root, '/tmp/p', 's1', TS1, [
        user_msg('e1', None, TS1, 'Role: planner\nPlan it'),
        assistant_msg('e2', 'e1', TS2, 'm', input=100),
        assistant_msg('e3', 'e2', TS3, 'm', input=200),
        user_msg('e4', 'e3', TS3, 'now do other work'),
        assistant_msg('e5', 'e4', TS3, 'm', input=300),
    ])
    events = _events(sessions_root)
    assert [e.role for e in events] == ['planner', 'planner', 'main']


def test_role_walks_parent_chain(sessions_root):
    # Branching: e3's parent is e2 (assistant), whose parent is e1 (user with
    # marker) — attribution must walk up through assistant entries.
    write_session(sessions_root, '/tmp/p', 's1', TS1, [
        user_msg('e1', None, TS1, 'Role: solid-review\nreview'),
        assistant_msg('e2', 'e1', TS2, 'm', input=100),
        assistant_msg('e3', 'e2', TS3, 'm', input=200),
    ])
    events = _events(sessions_root)
    assert {e.role for e in events} == {'solid-review'}


def test_category_mapping():
    assert role_category(None) == 'build'
    assert role_category('main') == 'build'
    assert role_category('build-tdd') == 'build'
    assert role_category('diff-review') == 'review'
    assert role_category('solid-review') == 'review'
    assert role_category('world-review') == 'review'
    assert role_category('planner') == 'plan'
    assert role_category('plan-bdd') == 'plan'
    assert role_category('something-else') == 'other'
