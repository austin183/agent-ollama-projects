"""Forked session files must not double-count shared history."""

from conftest import assistant_msg, user_msg, write_session
from pi_sessions import load_sessions

A1 = '2026-01-05T10:00:00.000Z'
A2 = '2026-01-05T10:01:00.000Z'
B1 = '2026-01-05T12:00:00.000Z'


def test_fork_history_deduped_first_file_wins(sessions_root):
    shared = [
        user_msg('e1', None, A1, 'start'),
        assistant_msg('e2', 'e1', A2, 'm', input=1000),
    ]
    # Original session
    write_session(sessions_root, '/tmp/p', 'orig', A1, shared)
    # Fork replays the same entry ids, then continues
    write_session(sessions_root, '/tmp/p', 'fork', B1,
                  shared + [assistant_msg('e9', 'e2', B1, 'm', input=5000)],
                  parent_session='orig')

    sessions = load_sessions(sessions_root=sessions_root)
    # Both files have usage; fork is a separate session
    assert len(sessions) == 2
    total = sum(e.total for s in sessions for e in s.events)
    # e2 counted once (1000) + fork's own turn (5000); NOT 1000 twice
    assert total == 6000


def test_fork_processed_after_original_by_header_ts(sessions_root):
    shared = [assistant_msg('e2', None, A2, 'm', input=1000)]
    # Deliberately write the fork file first on disk; ordering must come
    # from header timestamps, not filesystem order.
    write_session(sessions_root, '/tmp/p', 'fork', B1,
                  shared + [assistant_msg('e9', 'e2', B1, 'm', input=5000)],
                  parent_session='orig')
    write_session(sessions_root, '/tmp/p', 'orig', A1, shared)

    sessions = load_sessions(sessions_root=sessions_root)
    total = sum(e.total for s in sessions for e in s.events)
    assert total == 6000


def test_no_fork_unaffected(sessions_root):
    write_session(sessions_root, '/tmp/p', 's1', A1,
                  [assistant_msg('e1', None, A2, 'm', input=100)])
    write_session(sessions_root, '/tmp/p', 's2', A1,
                  [assistant_msg('f1', None, A2, 'm', input=200)])
    sessions = load_sessions(sessions_root=sessions_root)
    assert len(sessions) == 2
    assert sum(e.total for s in sessions for e in s.events) == 300
