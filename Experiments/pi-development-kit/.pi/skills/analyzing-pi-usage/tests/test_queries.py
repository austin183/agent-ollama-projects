"""Query modules: summary, models, roles, cross-tab, timeseries, top sessions,
plus project and date filtering."""

from conftest import assistant_msg, subagent_result, tool_result_msg, user_msg, write_session
from pi_sessions import load_sessions
from queries import summary, models, roles, cross_tab, timeseries, top_sessions

A = '2026-01-05T10:00:00.000Z'
B = '2026-01-05T10:01:00.000Z'
C = '2026-02-10T10:00:00.000Z'
D = '2026-02-10T10:01:00.000Z'


def _build_two_projects(root):
    # Project alpha: two sessions on two days, two models, two roles
    write_session(root, '/data/alpha', 's1', A, [
        user_msg('e1', None, A, 'Role: planner\nplan'),
        assistant_msg('e2', 'e1', B, 'model-a', input=1000, output=100, cost=0.01),
        assistant_msg('e3', 'e2', B, 'model-b', input=2000, output=200, cost=0.02),
    ], name='alpha planning')
    write_session(root, '/data/alpha', 's2', C, [
        user_msg('f1', None, C, 'go'),
        assistant_msg('f2', 'f1', D, 'model-a', input=4000, output=400, cost=0.04),
    ], name='alpha build')
    # Project beta: one session
    write_session(root, '/data/beta', 's3', A, [
        assistant_msg('g1', None, B, 'model-a', input=500, output=50, cost=0.005),
    ])


def test_summary_totals(sessions_root):
    _build_two_projects(sessions_root)
    sessions = load_sessions(sessions_root=sessions_root)
    s = summary.fetch(sessions=sessions)
    assert s['total_sessions'] == 3
    assert s['total_input_raw'] == 1000 + 2000 + 4000 + 500
    assert s['total_output'] == 100 + 200 + 400 + 50
    assert s['total_tokens_raw'] == s['total_input_raw'] + s['total_output']
    assert s['actual_cost'] == round(0.01 + 0.02 + 0.04 + 0.005, 4)
    assert s['model_count'] == 2
    assert s['earliest'] == '2026-01-05'
    assert s['latest'] == '2026-02-10'


def test_project_filter(sessions_root):
    _build_two_projects(sessions_root)
    sessions = load_sessions(sessions_root=sessions_root, project='/data/alpha')
    assert len(sessions) == 2
    s = summary.fetch(sessions=sessions)
    assert s['total_sessions'] == 2
    assert s['total_input_raw'] == 1000 + 2000 + 4000


def test_date_filter(sessions_root):
    _build_two_projects(sessions_root)
    sessions = load_sessions(sessions_root=sessions_root,
                             since='2026-01-01', until='2026-01-31')
    s = summary.fetch(sessions=sessions)
    assert s['total_sessions'] == 2  # s1 + s3
    assert s['total_input_raw'] == 1000 + 2000 + 500


def test_models_grouping(sessions_root):
    _build_two_projects(sessions_root)
    sessions = load_sessions(sessions_root=sessions_root)
    rows = models.fetch(sessions=sessions)
    by_model = {r['model']: r for r in rows}
    assert by_model['model-a']['total_tokens_raw'] == (1000 + 100) + (4000 + 400) + (500 + 50)
    assert by_model['model-b']['total_tokens_raw'] == 2200
    assert by_model['model-a']['sessions'] == 3
    # sorted by total desc
    assert rows[0]['model'] == 'model-a'


def test_roles_grouping(sessions_root):
    _build_two_projects(sessions_root)
    sessions = load_sessions(sessions_root=sessions_root, project='/data/alpha')
    rows = roles.fetch(sessions=sessions)
    by_role = {r['role']: r for r in rows}
    assert by_role['planner']['total_tokens_raw'] == 1100 + 2200  # s1's two turns
    assert by_role['main']['total_tokens_raw'] == 4400


def test_cross_tab(sessions_root):
    _build_two_projects(sessions_root)
    sessions = load_sessions(sessions_root=sessions_root, project='/data/alpha')
    rows = cross_tab.fetch(sessions=sessions)
    keys = {(r['model'], r['role']) for r in rows}
    assert ('model-a', 'planner') in keys
    assert ('model-a', 'main') in keys
    assert ('model-b', 'planner') in keys


def test_timeseries_daily_with_categories(sessions_root):
    _build_two_projects(sessions_root)
    sessions = load_sessions(sessions_root=sessions_root, project='/data/alpha')
    rows = timeseries.fetch(sessions=sessions)
    by_day = {r['date']: r for r in rows}
    assert set(by_day) == {'2026-01-05', '2026-02-10'}
    d1 = by_day['2026-01-05']
    assert d1['sessions'] == 1
    assert d1['total_tokens_raw'] == 3300
    # planner role -> plan category
    assert d1['plan_tok_raw'] == 3300
    assert d1['build_tok_raw'] == 0
    d2 = by_day['2026-02-10']
    assert d2['build_tok_raw'] == 4400  # main -> build category
    assert [r['date'] for r in rows] == sorted(by_day)


def test_timeseries_weekly_monthly(sessions_root):
    _build_two_projects(sessions_root)
    sessions = load_sessions(sessions_root=sessions_root, project='/data/alpha')
    weekly = timeseries.fetch_weekly(sessions=sessions)
    weeks = {r['week'] for r in weekly}
    assert len(weeks) == 2
    monthly = timeseries.fetch_monthly(sessions=sessions)
    months = {r['month'] for r in monthly}
    assert months == {'2026-01', '2026-02'}


def test_by_project_uses_cwd_basename(sessions_root):
    _build_two_projects(sessions_root)
    sessions = load_sessions(sessions_root=sessions_root)
    rows = timeseries.fetch_by_project(sessions=sessions)
    by_dir = {r['directory']: r for r in rows}
    assert set(by_dir) == {'alpha', 'beta'}
    assert by_dir['alpha']['sessions'] == 2
    assert by_dir['beta']['sessions'] == 1


def test_top_sessions(sessions_root):
    _build_two_projects(sessions_root)
    sessions = load_sessions(sessions_root=sessions_root)
    rows = top_sessions.fetch(sessions=sessions, limit=2)
    assert len(rows) == 2
    assert rows[0]['session_id'] == 's2'  # 4400 tokens, the biggest
    assert rows[0]['title'] == 'alpha build'  # from session_info name
    assert rows[0]['tokens'] == 4400
    assert rows[0]['role'] == 'main'
    assert rows[0]['created'] == '2026-02-10'


def test_top_sessions_title_falls_back_to_user_text(sessions_root):
    write_session(sessions_root, '/data/p', 's1', A, [
        user_msg('e1', None, A, 'a distinctive request'),
        assistant_msg('e2', 'e1', B, 'm', input=10),
    ])
    sessions = load_sessions(sessions_root=sessions_root)
    rows = top_sessions.fetch(sessions=sessions)
    assert rows[0]['title'] == 'a distinctive request'


def test_subagent_events_included_in_totals(sessions_root):
    write_session(sessions_root, '/data/p', 's1', A, [
        assistant_msg('e1', None, B, 'm', input=100),
        tool_result_msg('e2', 'e1', B, 'subagent', {'results': [
            subagent_result('planner', 'model-x', input=900, output=90,
                            cost=0.09, turns=2, context=990),
        ]}),
    ])
    sessions = load_sessions(sessions_root=sessions_root)
    s = summary.fetch(sessions=sessions)
    assert s['total_input_raw'] == 100 + 900
    assert s['role_count'] == 2  # main + planner (subagent role)
    roles_rows = {r['role']: r for r in roles.fetch(sessions=sessions)}
    assert roles_rows['planner']['total_tokens_raw'] == 990
