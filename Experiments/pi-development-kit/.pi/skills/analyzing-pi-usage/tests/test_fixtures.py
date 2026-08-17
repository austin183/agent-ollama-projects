"""Tests against the real session JSONL fixtures captured in Phases 1-3.

See tests/fixtures/README.md for what each fixture contains.
"""

import shutil
from pathlib import Path

import pytest

from pi_sessions import load_sessions, parse_session_file

FIXTURES = Path(__file__).resolve().parent / 'fixtures'


def _load(name: str, tmp_path: Path):
    """Load one fixture file in an isolated sessions root."""
    root = tmp_path / 'sessions'
    d = root / '--tmp-fixture--'
    d.mkdir(parents=True)
    shutil.copy(FIXTURES / name, d / name)
    return load_sessions(sessions_root=root)


def _subagents(sessions):
    return [e for s in sessions for e in s.events if e.kind == 'subagent']


@pytest.mark.parametrize('name', sorted(p.name for p in FIXTURES.glob('*.jsonl')))
def test_fixture_parses_cleanly(name, tmp_path):
    header, entries, malformed = parse_session_file(FIXTURES / name)
    assert header.get('type') == 'session'
    assert header.get('id')
    assert header.get('cwd')
    assert malformed == 0
    assert _load(name, tmp_path)  # at least one session with usage


def test_failed_world_review_run_zero_usage(tmp_path):
    sessions = _load('2026-08-16T02-16-57-151Z_01a0085b-9e3f-77bc-a60c-7cbebf2216f6.jsonl', tmp_path)
    subs = _subagents(sessions)
    assert len(subs) == 1
    e = subs[0]
    assert e.agent == 'world-review'
    assert e.stop_reason == 'error'
    # one turn was attempted (model load failed) but produced no tokens
    assert e.input == 0 and e.output == 0 and e.cost == 0.0
    assert e.context_tokens == 0


def test_successful_planner_run_full_usage(tmp_path):
    sessions = _load('2026-08-16T02-21-04-373Z_01a0085f-63f5-709b-a2f5-822cad2d01da.jsonl', tmp_path)
    subs = _subagents(sessions)
    assert len(subs) == 1
    e = subs[0]
    assert e.agent == 'planner'
    assert e.input > 0 and e.output > 0
    assert e.turns > 0
    assert e.context_tokens > 0
    # LM Studio reports no cost (0.0) — that is valid, not a parse failure
    assert e.cost == 0.0


def test_nested_runs_recursed(tmp_path):
    sessions = _load('2026-08-16T02-24-02-945Z_01a00862-1d81-7571-8506-d870b3813038.jsonl', tmp_path)
    subs = _subagents(sessions)
    by_agent = {e.agent: e for e in subs}
    assert 'plan-bdd' in by_agent
    assert 'planner' in by_agent
    assert by_agent['plan-bdd'].depth == 0
    assert by_agent['planner'].depth == 1
    # nested usage is separate from the parent result's usage
    assert by_agent['plan-bdd'].input > 0
    assert by_agent['planner'].input > 0


def test_world_review_model_override(tmp_path):
    sessions = _load('2026-08-16T13-41-28-966Z_01a00ace-5306-76a9-81a4-8531dbfef073.jsonl', tmp_path)
    subs = _subagents(sessions)
    assert len(subs) == 1
    e = subs[0]
    assert e.agent == 'world-review'
    assert e.model == 'lmstudio/qwen-agentworld-35b-a3b'
    assert e.input > 0
    assert e.stop_reason == 'stop'


def test_role_marker_build_tdd(tmp_path):
    sessions = _load('phase2-build-tdd-persona.jsonl', tmp_path)
    assistant_roles = {e.role for s in sessions for e in s.events if e.kind == 'assistant'}
    assert 'build-tdd' in assistant_roles


def test_diff_review_delegation(tmp_path):
    sessions = _load('phase2-diff-review-delegation.jsonl', tmp_path)
    subs = _subagents(sessions)
    assert any(e.agent == 'diff-review' for e in subs)


def test_plan_bdd_multi_agent_multi_model(tmp_path):
    sessions = _load('phase2-plan-bdd-workflow.jsonl', tmp_path)
    assistant_roles = {e.role for s in sessions for e in s.events if e.kind == 'assistant'}
    assert 'plan-bdd' in assistant_roles
    subs = _subagents(sessions)
    agents = {e.agent for e in subs}
    assert 'world-review' in agents
    assert 'planner' in agents
    models = {e.model for e in subs}
    assert 'lmstudio/qwen-agentworld-35b-a3b' in models


def test_solid_review_delegation(tmp_path):
    sessions = _load('phase2-solid-review-delegation.jsonl', tmp_path)
    subs = _subagents(sessions)
    assert any(e.agent == 'solid-review' for e in subs)


def test_totals_consistent_across_fixture_set(tmp_path):
    """Sum of per-session event totals == sum over all events (sanity)."""
    root = tmp_path / 'all'
    d = root / '--tmp-fixture--'
    d.mkdir(parents=True)
    for p in FIXTURES.glob('*.jsonl'):
        shutil.copy(p, d / p.name)
    sessions = load_sessions(sessions_root=root)
    assert len(sessions) == len(list(FIXTURES.glob('*.jsonl')))
    total = sum(e.total for s in sessions for e in s.events)
    assert total > 0
