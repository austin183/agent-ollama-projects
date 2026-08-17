"""Commit→session change attribution (Pi-Session trailers).

Covers the three layers: `_parse_commits` (trailer extraction from git log
output), `summarize_attribution` (per-session aggregation), and the full
fetch→join→merge→render path on a real temp git repo.
"""

import os
import subprocess

import pytest

from conftest import assistant_msg, user_msg, write_session
from queries.git_commits import (
    _parse_commits,
    fetch,
    fetch_daily,
    summarize_attribution,
)

S1 = '11111111-2222-3333-4444-555555555555'
S2 = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
UNKNOWN = '99999999-8888-7777-6666-555555555555'
MSG_END = '\x1e'


def _commit_block(sha, date, subject, body=None, numstat=('10\t5\tsrc/foo.py',),
                  trailer=None):
    """One commit as it appears in the `git log --numstat` format we parse."""
    msg_lines = [subject]
    if body:
        msg_lines.append('')
        msg_lines.extend(body)
    if trailer is not None:
        msg_lines.append('')
        msg_lines.append(trailer)
    out = [f'COMMIT:{sha}|{date}|{subject}']
    out.append('MSG:' + '\n'.join(msg_lines))
    out.append(MSG_END)
    out.extend(numstat)
    return '\n'.join(out)


# ── _parse_commits: trailer extraction ───────────────────────────────────────

def test_parse_trailer_present():
    out = _commit_block('abc1234', '2026-03-02', 'feat: thing',
                        body=['body line'], trailer=f'Pi-Session: {S1}')
    commits = _parse_commits(out)
    assert len(commits) == 1
    assert commits[0]['session_id'] == S1
    assert commits[0]['adds'] == 10
    assert commits[0]['dels'] == 5
    assert commits[0]['message'] == 'feat: thing'


def test_parse_no_trailer():
    out = _commit_block('abc1234', '2026-03-02', 'chore: thing',
                        body=['plain body'])
    commits = _parse_commits(out)
    assert commits[0]['session_id'] is None


def test_parse_subject_only_message():
    out = _commit_block('abc1234', '2026-03-02', 'tiny change',
                        numstat=())
    commits = _parse_commits(out)
    assert commits[0]['session_id'] is None
    assert commits[0]['adds'] == 0


def test_parse_malformed_trailer_rejected():
    out = _commit_block('abc1234', '2026-03-02', 'x',
                        trailer='Pi-Session: not-a-uuid')
    assert _parse_commits(out)[0]['session_id'] is None


def test_parse_trailer_case_normalized():
    upper = S1.upper()
    out = _commit_block('abc1234', '2026-03-02', 'x', trailer=f'Pi-Session: {upper}')
    assert _parse_commits(out)[0]['session_id'] == S1


def test_parse_multiple_trailers_last_wins():
    out = _commit_block('abc1234', '2026-03-02', 'x',
                        body=[f'Pi-Session: {S2}', f'Pi-Session: {S1}'])
    assert _parse_commits(out)[0]['session_id'] == S1


def test_parse_tab_in_message_body():
    out = _commit_block('abc1234', '2026-03-02', 'x',
                        body=['line with\ttab inside'],
                        numstat=('1\t1\tsrc/a.py',),
                        trailer=f'Pi-Session: {S1}')
    commits = _parse_commits(out)
    assert len(commits) == 1
    assert commits[0]['session_id'] == S1
    assert commits[0]['adds'] == 1


def test_parse_binary_numstat_after_trailer():
    out = _commit_block('abc1234', '2026-03-02', 'x',
                        trailer=f'Pi-Session: {S1}',
                        numstat=('-\t-\timg/logo.png', '3\t1\tsrc/b.py'))
    commits = _parse_commits(out)
    assert commits[0]['session_id'] == S1
    assert commits[0]['adds'] == 3
    assert commits[0]['dels'] == 1


def test_parse_body_line_looking_like_marker_not_split():
    # A body line starting with "COMMIT:" but lacking the sha|date shape must
    # stay inside the message (it cannot match the validated marker regex).
    out = _commit_block('abc1234', '2026-03-02', 'x',
                        body=['COMMIT: this is not a marker',
                              f'Pi-Session: {S1}'])
    commits = _parse_commits(out)
    assert len(commits) == 1
    assert commits[0]['session_id'] == S1


def test_parse_two_commits_mixed():
    out = '\n'.join([
        _commit_block('aaa1111', '2026-03-02', 'first',
                      trailer=f'Pi-Session: {S1}',
                      numstat=('2\t0\tsrc/a.py',)),
        _commit_block('bbb2222', '2026-03-02', 'second',
                      numstat=('0\t4\tsrc/b.py',)),
    ])
    commits = _parse_commits(out)
    assert [c['session_id'] for c in commits] == [S1, None]
    assert commits[1]['is_test'] is False


# ── summarize_attribution ────────────────────────────────────────────────────

def test_summarize_empty():
    s = summarize_attribution([])
    assert s == {'attributed_commits': 0, 'unattributed_commits': 0,
                 'sessions_measured': 0, 'by_session': {}}


def test_summarize_mixed():
    commits = [
        {'session_id': S1, 'adds': 10, 'dels': 2, 'test_adds': 4, 'test_dels': 0},
        {'session_id': S1, 'adds': 1, 'dels': 0, 'test_adds': 0, 'test_dels': 1},
        {'session_id': None, 'adds': 5, 'dels': 5, 'test_adds': 0, 'test_dels': 0},
        {'session_id': S2, 'adds': 7, 'dels': 3, 'test_adds': 0, 'test_dels': 0},
    ]
    s = summarize_attribution(commits)
    assert s['attributed_commits'] == 3
    assert s['unattributed_commits'] == 1
    assert s['sessions_measured'] == 2
    assert s['by_session'][S1] == {'commits': 2, 'adds': 11, 'dels': 2,
                                   'test_adds': 4, 'test_dels': 1}
    assert s['by_session'][S2]['commits'] == 1


# ── Real git repo integration ────────────────────────────────────────────────

@pytest.fixture
def git_repo(tmp_path):
    """Temp git repo with three commits: trailer / none / unknown trailer."""
    repo = tmp_path / 'repo'
    repo.mkdir()

    def git(*args, date='2026-03-02T12:00:00Z'):
        env = dict(os.environ,
                   GIT_AUTHOR_DATE=date, GIT_COMMITTER_DATE=date)
        subprocess.run(
            ['git', '-C', str(repo), *args],
            check=True, capture_output=True, text=True, env=env)

    git('init', '-q')
    git('config', 'user.email', 'test@example.com')
    git('config', 'user.name', 'Test')

    (repo / 'a.py').write_text('x = 1\n')
    git('add', 'a.py')
    git('commit', '-q', '-m', f'feat: first change\n\nPi-Session: {S1}')

    (repo / 'b.py').write_text('y = 2\n')
    git('add', 'b.py')
    git('commit', '-q', '-m', 'chore: unattributed change')

    (repo / 'c.py').write_text('z = 3\n')
    git('add', 'c.py')
    git('commit', '-q', '-m',
        f'feat: unknown session\n\nPi-Session: {UNKNOWN}',
        date='2026-03-03T12:00:00Z')
    return repo


def test_fetch_reads_trailers(git_repo):
    commits = fetch(project=str(git_repo), since='2026-01-01', until='2026-12-31')
    assert [c['session_id'] for c in commits] == [S1, None, UNKNOWN]
    assert [c['adds'] for c in commits] == [1, 1, 1]


def test_fetch_daily_shape_unchanged(git_repo):
    daily = fetch_daily(project=str(git_repo), since='2026-01-01',
                        until='2026-12-31')
    assert [(r['date'], r['commits'], r['adds']) for r in daily] == [
        ('2026-03-02', 2, 2),
        ('2026-03-03', 1, 1),
    ]


def test_fetch_date_range_excludes(git_repo):
    commits = fetch(project=str(git_repo), since='2026-03-03', until='2026-03-03')
    assert [c['session_id'] for c in commits] == [UNKNOWN]


# ── E2E: fetch → join → merge → render ───────────────────────────────────────

MODEL = 'anthropic/claude-sonnet-4'
A = '2026-03-02T10:00:00.000Z'
B = '2026-03-02T10:05:00.000Z'


def _attribution_world(tmp_path):
    """Project that is a git repo; a session whose id matches a trailer."""
    project = tmp_path / 'proj'
    project.mkdir()
    root = tmp_path / 'sessions'
    root.mkdir()
    # Work session: planner persona (dominant role 'planner'), named.
    write_session(root, str(project), S1, A, [
        user_msg('e1', None, A, 'Role: planner\nplan it'),
        assistant_msg('e2', 'e1', B, MODEL, input=10_000, output=500, cost=0.05),
    ], name='planning session')
    # The repo's commit names S1 in its trailer.
    def git(*args, date='2026-03-02T12:00:00Z'):
        env = dict(os.environ, GIT_AUTHOR_DATE=date, GIT_COMMITTER_DATE=date)
        subprocess.run(['git', '-C', str(project), *args], check=True,
                       capture_output=True, text=True, env=env)
    git('init', '-q')
    git('config', 'user.email', 'test@example.com')
    git('config', 'user.name', 'Test')
    (project / 'a.py').write_text('x = 1\n')
    git('add', 'a.py')
    git('commit', '-q', '-m', f'feat: planned change\n\nPi-Session: {S1}')
    return project, root


def test_e2e_report_attribution(tmp_path):
    from aggregator.merge import merge_datasets
    from generate_report import fetch_all_datasets, join_change_attribution
    from render_consolidated_report import render_html

    project, root = _attribution_world(tmp_path)
    data = fetch_all_datasets(project_path=str(project),
                              since='2026-01-01', until='2026-12-31',
                              sessions_root=root)
    attribution = join_change_attribution(data['sessions'], data['git_commits'])
    assert attribution['attributed_commits'] == 1
    assert attribution['unattributed_commits'] == 0
    row = attribution['by_session'][S1]
    assert row['commits'] == 1 and row['adds'] == 1
    assert row['role'] == 'planner'
    assert row['title'] == 'planning session'

    report = merge_datasets(
        daily_agent=data['daily_tokens'], weekly=data['weekly'],
        summary_raw=data['summary_list'], models_data=data['models'],
        roles_data=data['roles'], cross_tab=data['cross_tab'],
        top_sessions=data['top_sessions'],
        productivity_raw=data['productivity_list'],
        build_prod_raw=data['build_prod_list'],
        git_commits=data['git_commits'], daily_git=data['daily_git'],
        cache_estimate=data['cache_estimate'],
        project_range=data['project_range'], project_name=project.name,
        subagent_runs=data['subagent_runs'],
        session_summaries=data['session_summaries'],
        change_attribution=attribution,
    )
    prod = report['productivity'][0]
    assert prod['sessions_with_changes_measured'] == 1
    assert prod['sessions_with_changes'] >= 1
    assert report['change_attribution']['by_session'][S1]['role'] == 'planner'

    html = render_html(report)
    assert 'Change Attribution' in html
    assert 'planning session' in html
    assert 'Pi-Session:' in html  # footer convention note
    assert '1 measured' in html   # productivity card label


def test_e2e_unknown_session_id_still_counts(tmp_path):
    """A trailer naming a session not in the loaded set: counted, unlabelled."""
    from aggregator.merge import merge_datasets
    from generate_report import fetch_all_datasets, join_change_attribution

    project, root = _attribution_world(tmp_path)
    data = fetch_all_datasets(project_path=str(project),
                              since='2026-01-01', until='2026-12-31',
                              sessions_root=root)
    # Retarget the trailer at an unknown session id.
    for c in data['git_commits']:
        if c['session_id'] == S1:
            c['session_id'] = UNKNOWN
    attribution = join_change_attribution(data['sessions'], data['git_commits'])
    row = attribution['by_session'][UNKNOWN]
    assert row['role'] is None and row['title'] is None
    assert attribution['sessions_measured'] == 1
    report = merge_datasets(
        daily_agent=data['daily_tokens'], weekly=data['weekly'],
        summary_raw=data['summary_list'], models_data=data['models'],
        roles_data=data['roles'], cross_tab=data['cross_tab'],
        top_sessions=data['top_sessions'],
        productivity_raw=data['productivity_list'],
        build_prod_raw=data['build_prod_list'],
        git_commits=data['git_commits'], daily_git=data['daily_git'],
        cache_estimate=data['cache_estimate'],
        project_range=data['project_range'], project_name=project.name,
        subagent_runs=data['subagent_runs'],
        session_summaries=data['session_summaries'],
        change_attribution=attribution,
    )
    assert report['productivity'][0]['sessions_with_changes_measured'] == 1


def test_no_trailers_legacy_path(tmp_path):
    """No trailers anywhere: pure estimate, no attribution block in HTML."""
    from aggregator.merge import merge_datasets
    from generate_report import fetch_all_datasets, join_change_attribution
    from render_consolidated_report import render_html

    project, root = _attribution_world(tmp_path)
    data = fetch_all_datasets(project_path=str(project),
                              since='2026-01-01', until='2026-12-31',
                              sessions_root=root)
    attribution = join_change_attribution(data['sessions'], data['git_commits'])
    for c in data['git_commits']:
        c['session_id'] = None  # simulate a pre-convention repo
    attribution = join_change_attribution(data['sessions'], data['git_commits'])
    assert attribution['attributed_commits'] == 0
    report = merge_datasets(
        daily_agent=data['daily_tokens'], weekly=data['weekly'],
        summary_raw=data['summary_list'], models_data=data['models'],
        roles_data=data['roles'], cross_tab=data['cross_tab'],
        top_sessions=data['top_sessions'],
        productivity_raw=data['productivity_list'],
        build_prod_raw=data['build_prod_list'],
        git_commits=data['git_commits'], daily_git=data['daily_git'],
        cache_estimate=data['cache_estimate'],
        project_range=data['project_range'], project_name=project.name,
        subagent_runs=data['subagent_runs'],
        session_summaries=data['session_summaries'],
        change_attribution=attribution,
    )
    prod = report['productivity'][0]
    assert prod['sessions_with_changes_measured'] == 0
    # Zeroed block (not omitted): the renderer leaves the section out when
    # by_session is empty.
    assert report['change_attribution']['attributed_commits'] == 0
    assert report['change_attribution']['by_session'] == {}
    html = render_html(report)
    assert 'Change Attribution' not in html
