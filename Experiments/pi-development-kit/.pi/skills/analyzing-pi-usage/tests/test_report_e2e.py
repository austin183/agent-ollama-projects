"""End-to-end: fetch_all_datasets -> merge -> render_html on synthetic data."""

import json

import pytest

from conftest import (
    assistant_msg, subagent_result, tool_result_msg, user_msg, write_session,
)
from generate_report import fetch_all_datasets, _build_prod_row
from queries.utils import sessions_by_day
from aggregator.merge import merge_datasets
from render_consolidated_report import render_html

A = '2026-03-02T10:00:00.000Z'
B = '2026-03-02T10:05:00.000Z'
C = '2026-03-02T10:10:00.000Z'
D = '2026-03-03T09:00:00.000Z'
E = '2026-03-03T09:05:00.000Z'

MODEL = 'anthropic/claude-sonnet-4'


def _build_world(tmp_path):
    project_dir = tmp_path / 'proj'
    project_dir.mkdir()
    root = tmp_path / 'sessions'
    root.mkdir()
    write_session(root, str(project_dir), 's1', A, [
        user_msg('e1', None, A, 'Role: planner\nplan the feature'),
        assistant_msg('e2', 'e1', B, MODEL, input=10_000, output=500, cost=0.05),
        tool_result_msg('e3', 'e2', C, 'subagent', {'results': [
            subagent_result('planner', MODEL, input=20_000, output=1_000,
                            cost=0.20, turns=3, context=21_000),
            subagent_result('world-review', 'lmstudio/qwen-agentworld-35b-a3b',
                            input=30_000, output=2_000, cost=0.30, turns=4,
                            context=32_000),
        ]}),
    ], name='planning session')
    write_session(root, str(project_dir), 's2', D, [
        user_msg('f1', None, D, 'build it'),
        assistant_msg('f2', 'f1', E, MODEL, input=40_000, output=2_000, cost=0.40),
    ], name='build session')
    # Session summaries in the project's docs directory
    docs = project_dir / '_agent_docs' / 'sessions'
    docs.mkdir(parents=True)
    (docs / 'session-001-summary.json').write_text(json.dumps({
        'session_id': 's1', 'session_number': 1, 'date': '2026-03-02',
        'purpose': 'planning', 'agent_role': 'planner', 'outcome': 'complete',
        'files_changed': 0, 'test_files_added': 0, 'tests_added': 0,
        'assertions_added': 0, 'bugs_fixed': 0, 'learnings_written': 0,
        'plans_written': 1, 'commits': 0, 'notes': 'planned feature',
    }))
    (docs / 'session-002-summary.json').write_text(json.dumps({
        'session_id': 's2', 'session_number': 2, 'date': '2026-03-03',
        'purpose': 'development', 'agent_role': 'main', 'outcome': 'complete',
        'files_changed': 3, 'test_files_added': 1, 'tests_added': 4,
        'assertions_added': 10, 'bugs_fixed': 0, 'learnings_written': 1,
        'plans_written': 0, 'commits': 1, 'notes': 'built feature',
    }))
    return project_dir, root


@pytest.fixture
def world(tmp_path):
    return _build_world(tmp_path)


def _full_report(world):
    project_dir, root = world
    data = fetch_all_datasets(
        project_path=str(project_dir),
        since='2026-01-01', until='2026-12-31',
        sessions_root=root,
    )
    return merge_datasets(
        daily_agent=data['daily_tokens'],
        weekly=data['weekly'],
        summary_raw=data['summary_list'],
        models_data=data['models'],
        roles_data=data['roles'],
        cross_tab=data['cross_tab'],
        top_sessions=data['top_sessions'],
        productivity_raw=data['productivity_list'],
        build_prod_raw=data['build_prod_list'],
        git_commits=data['git_commits'],
        daily_git=data['daily_git'],
        cache_estimate=data['cache_estimate'],
        project_range=data['project_range'],
        project_name=project_dir.name,
        subagent_runs=data['subagent_runs'],
        session_summaries=data['session_summaries'],
    )


def test_fetch_all_datasets_shape(world):
    project_dir, root = world
    data = fetch_all_datasets(project_path=str(project_dir),
                               since='2026-01-01', until='2026-12-31',
                               sessions_root=root)
    sessions = data['sessions']
    assert len(sessions) == 2
    assert data['summary_list'][0]['total_sessions'] == 2
    # both models seen: cloud + lmstudio subagent model
    model_keys = {m['model'] for m in data['models']}
    assert MODEL in model_keys
    assert 'lmstudio/qwen-agentworld-35b-a3b' in model_keys


def test_subagent_runs_attribution(world):
    project_dir, root = world
    data = fetch_all_datasets(project_path=str(project_dir),
                               since='2026-01-01', until='2026-12-31',
                               sessions_root=root)
    sub = data['subagent_runs']
    assert sub['total_runs'] == 2
    by_agent = {a['agent']: a for a in sub['by_agent']}
    assert by_agent['planner']['runs'] == 1
    assert by_agent['world-review']['runs'] == 1
    assert sub['actual_cost'] == round(0.20 + 0.30, 4)
    assert len(sub['runs']) == 2


def test_session_summaries_join(world):
    project_dir, root = world
    data = fetch_all_datasets(project_path=str(project_dir),
                               since='2026-01-01', until='2026-12-31',
                               sessions_root=root)
    ss = data['session_summaries']
    assert ss['total'] == 2
    assert ss['by_purpose'] == {'development': 1, 'planning': 1}
    assert ss['by_role'] == {'main': 1, 'planner': 1}


def test_session_summaries_date_filtered(world):
    project_dir, root = world
    data = fetch_all_datasets(project_path=str(project_dir),
                               since='2026-03-03', until='2026-03-03',
                               sessions_root=root)
    assert data['session_summaries']['total'] == 1  # only the 03-03 summary


def test_full_report_merge(world):
    r = _full_report(world)
    assert r['meta']['title'].endswith('LLM Usage & Value Report')
    assert r['summary']['total_sessions'] == 2
    assert r['subagent_runs']['total_runs'] == 2
    assert r['session_summaries']['total'] == 2
    # productivity capped: 2 sessions, commit days = none (no git repo) -> 0
    assert r['productivity'][0]['sessions_with_changes'] == 0


def test_render_html_sections(world):
    r = _full_report(world)
    html = render_html(r)
    # core sections
    assert 'Summary Metrics' in html
    assert 'Detailed Data Tables' in html
    assert 'Token Usage by Role' in html
    # pi-specific sections
    assert 'Subagent Runs' in html
    assert 'Session Summaries' in html
    assert 'world-review' in html
    assert 'planning session' in html  # top-sessions title
    # footer sources
    assert 'session JSONL' in html
    # no opencode leftovers in visible copy
    assert 'opencode' not in html


def test_render_html_no_subagents_omits_section(tmp_path):
    # A world without subagent runs / summaries
    project_dir = tmp_path / 'proj'
    project_dir.mkdir()
    root2 = tmp_path / 'sessions2'
    root2.mkdir()
    from conftest import write_session as ws
    ws(root2, str(project_dir), 's1', A, [
        user_msg('e1', None, A, 'hi'),
        assistant_msg('e2', 'e1', B, MODEL, input=1_000, output=10),
    ])
    data = fetch_all_datasets(project_path=str(project_dir),
                               since='2026-01-01', until='2026-12-31',
                               sessions_root=root2)
    r = merge_datasets(
        daily_agent=data['daily_tokens'], weekly=data['weekly'],
        summary_raw=data['summary_list'], models_data=data['models'],
        roles_data=data['roles'], cross_tab=data['cross_tab'],
        top_sessions=data['top_sessions'],
        productivity_raw=data['productivity_list'],
        build_prod_raw=data['build_prod_list'],
        git_commits=data['git_commits'], daily_git=data['daily_git'],
        cache_estimate=data['cache_estimate'], project_range=data['project_range'],
        project_name='proj', subagent_runs=data['subagent_runs'],
        session_summaries=data['session_summaries'],
    )
    html = render_html(r)
    assert 'Subagent Runs' not in html
    assert 'Session Summaries' not in html


def test_helper_functions(world):
    project_dir, root = world
    data = fetch_all_datasets(project_path=str(project_dir),
                               since='2026-01-01', until='2026-12-31',
                               sessions_root=root)
    by_day = sessions_by_day(data['sessions'])
    assert by_day == {'2026-03-02': 1, '2026-03-03': 1}
    bp = _build_prod_row(data['sessions'])
    # main-session build-category sessions: both (planner->plan, main->build:
    # only s2 counts as build)
    assert bp['total_build_sessions'] == 1
