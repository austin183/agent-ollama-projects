"""Cache estimation: measured path and LAG-delta fallback."""

from conftest import assistant_msg, user_msg, write_session
from pi_sessions import load_sessions
from queries import cache_estimate

TS1 = '2026-01-05T10:00:00.000Z'
TS2 = '2026-01-05T10:01:00.000Z'
TS3 = '2026-01-05T10:02:00.000Z'
TS4 = '2026-01-06T09:00:00.000Z'


def _agg(root, sessions=None):
    if sessions is None:
        sessions = load_sessions(sessions_root=root)
    return cache_estimate.fetch_aggregate(sessions=sessions)


def test_measured_cache_split(sessions_root):
    write_session(sessions_root, '/tmp/p', 's1', TS1, [
        assistant_msg('e1', None, TS1, 'm', input=1000, cache_read=900),
        assistant_msg('e2', 'e1', TS2, 'm', input=2000, cache_read=1500),
    ])
    agg = _agg(sessions_root)
    assert agg['simulated'] is False
    # uncached = (1000-900) + (2000-1500) = 100 + 500
    assert agg['estimated_uncached_input'] == 600
    assert agg['estimated_cached_input'] == 2400
    assert agg['total_input_raw'] == 3000


def test_measured_never_negative_when_input_lt_cacheread(sessions_root):
    write_session(sessions_root, '/tmp/p', 's1', TS1, [
        assistant_msg('e1', None, TS1, 'm', input=100, cache_read=500),
    ])
    agg = _agg(sessions_root)
    assert agg['estimated_uncached_input'] == 0
    assert agg['estimated_cached_input'] == 500


def test_lag_delta_fallback_when_no_cache_reads(sessions_root):
    # Growing context: 1000 -> 3000 -> 2900
    write_session(sessions_root, '/tmp/p', 's1', TS1, [
        user_msg('u0', None, TS1, 'go'),
        assistant_msg('e1', 'u0', TS1, 'lmstudio/qwen3.8-27b', input=1000),
        assistant_msg('e2', 'e1', TS2, 'lmstudio/qwen3.8-27b', input=3000),
        assistant_msg('e3', 'e2', TS3, 'lmstudio/qwen3.8-27b', input=2900),
    ])
    agg = _agg(sessions_root)
    assert agg['simulated'] is True
    # uncached: 1000 (first) + 2000 (delta) + 0 (shrinkage) = 3000
    assert agg['estimated_uncached_input'] == 3000
    # cached: 0 + (3000-2000) + 2900 = 3900
    assert agg['estimated_cached_input'] == 3900
    assert agg['total_input_raw'] == 6900


def test_single_turn_session_fallback(sessions_root):
    write_session(sessions_root, '/tmp/p', 's1', TS1, [
        assistant_msg('e1', None, TS1, 'lmstudio/qwen3.8-27b', input=42),
    ])
    agg = _agg(sessions_root)
    assert agg['estimated_uncached_input'] == 42
    assert agg['estimated_cached_input'] == 0


def test_by_model_grouping(sessions_root):
    write_session(sessions_root, '/tmp/p', 's1', TS1, [
        assistant_msg('e1', None, TS1, 'model-a', input=1000),
        assistant_msg('e2', 'e1', TS2, 'model-b', input=2000),
    ])
    sessions = load_sessions(sessions_root=sessions_root)
    rows = cache_estimate.fetch_by_model(sessions=sessions)
    by_key = {r['key']: r for r in rows}
    assert set(by_key) == {'model-a', 'model-b'}
    assert by_key['model-a']['total_input_raw'] == 1000
    assert by_key['model-b']['total_input_raw'] == 2000


def test_by_role_and_by_day_grouping(sessions_root):
    write_session(sessions_root, '/tmp/p', 's1', TS1, [
        user_msg('u1', None, TS1, 'Role: planner\nplan'),
        assistant_msg('e1', 'u1', TS1, 'm', input=1000),
        user_msg('u2', 'e1', TS4, 'build it'),
        assistant_msg('e2', 'u2', TS4, 'm', input=2000),
    ])
    sessions = load_sessions(sessions_root=sessions_root)
    by_role = {r['key']: r for r in cache_estimate.fetch_by_role(sessions=sessions)}
    assert by_role['planner']['total_input_raw'] == 1000
    assert by_role['main']['total_input_raw'] == 2000

    by_day = {r['key']: r for r in cache_estimate.fetch_by_day(sessions=sessions)}
    assert set(by_day) == {'2026-01-05', '2026-01-06'}
    assert by_day['2026-01-05']['total_input_raw'] == 1000
    # sorted ascending by key
    days = [r['key'] for r in cache_estimate.fetch_by_day(sessions=sessions)]
    assert days == sorted(days)


def test_compaction_excluded_from_turn_sequence(sessions_root):
    # Compaction usage must not participate in the LAG-delta sequence (it is
    # one summary call, not a conversation turn).
    from conftest import compaction_entry
    write_session(sessions_root, '/tmp/p', 's1', TS1, [
        assistant_msg('e1', None, TS1, 'm', input=1000),
        compaction_entry('c1', 'e1', TS2, input=9000, output=100),
        assistant_msg('e2', 'c1', TS3, 'm', input=1100),
    ])
    agg = _agg(sessions_root)
    # sequence: 1000, 1100 -> uncached 1000 + 100 = 1100 (no 9000 spike)
    assert agg['estimated_uncached_input'] == 1100
    assert agg['total_input_raw'] == 2100
