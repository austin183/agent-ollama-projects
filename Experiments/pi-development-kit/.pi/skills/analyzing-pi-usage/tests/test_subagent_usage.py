"""Subagent run attribution from parent-session tool results (incl. nesting)."""

from conftest import (
    assistant_msg, subagent_result, tool_result_msg, user_msg, write_session,
)
from pi_sessions import load_sessions

TS1 = '2026-01-05T10:00:00.000Z'
TS2 = '2026-01-05T10:01:00.000Z'
TS3 = '2026-01-05T10:02:00.000Z'


def _subagent_events(root):
    sessions = load_sessions(sessions_root=root)
    return [e for s in sessions for e in s.events if e.kind == 'subagent']


def test_single_subagent_run_attributed(sessions_root):
    write_session(sessions_root, '/tmp/p', 's1', TS1, [
        user_msg('e1', None, TS1, 'review it'),
        assistant_msg('e2', 'e1', TS2, 'm', input=100),
        tool_result_msg('e3', 'e2', TS3, 'subagent', {'results': [
            subagent_result('diff-review', 'anthropic/claude-sonnet-4',
                            input=50000, output=2000, cost=0.25,
                            turns=7, context=52000),
        ]}),
    ])
    events = _subagent_events(sessions_root)
    assert len(events) == 1
    e = events[0]
    assert e.agent == 'diff-review'
    assert e.model == 'anthropic/claude-sonnet-4'
    assert e.input == 50000
    assert e.output == 2000
    assert e.cost == 0.25
    assert e.turns == 7
    assert e.context_tokens == 52000
    assert e.depth == 0
    assert e.stop_reason == 'end_turn'
    # role is set to the agent name for role queries
    assert e.role == 'diff-review'


def test_multiple_results_in_one_tool_call(sessions_root):
    write_session(sessions_root, '/tmp/p', 's1', TS1, [
        tool_result_msg('e3', None, TS2, 'subagent', {'results': [
            subagent_result('world-review', 'lmstudio/qwen-agentworld-35b-a3b',
                            input=1000, output=100, cost=0.01, turns=2, context=1100),
            subagent_result('planner', 'anthropic/claude-sonnet-4',
                            input=2000, output=200, cost=0.02, turns=3, context=2200),
        ]}),
    ])
    events = _subagent_events(sessions_root)
    assert {e.agent for e in events} == {'world-review', 'planner'}


def test_nested_subagent_runs_recursed(sessions_root):
    # results[i].messages[] holds raw message objects (not JSONL entries)
    nested_planner = [{
        'role': 'toolResult', 'toolName': 'subagent', 'toolCallId': 'call_n1',
        'usage': None,
        'details': {'results': [
            subagent_result('planner', 'anthropic/claude-sonnet-4',
                            input=3000, output=300, cost=0.03, turns=4, context=3300),
        ]},
    }]
    write_session(sessions_root, '/tmp/p', 's1', TS1, [
        tool_result_msg('e3', None, TS2, 'subagent', {'results': [
            subagent_result('plan-bdd', 'anthropic/claude-sonnet-4',
                            input=8000, output=800, cost=0.08, turns=6,
                            context=8800, messages=nested_planner),
        ]}),
    ])
    events = _subagent_events(sessions_root)
    assert len(events) == 2
    by_agent = {e.agent: e for e in events}
    assert by_agent['plan-bdd'].depth == 0
    assert by_agent['planner'].depth == 1
    # nested usage is NOT included in the parent result's usage
    assert sum(e.input for e in events) == 8000 + 3000


def test_failed_run_zero_usage_still_counted(sessions_root):
    write_session(sessions_root, '/tmp/p', 's1', TS1, [
        tool_result_msg('e3', None, TS2, 'subagent', {'results': [
            subagent_result('world-review', 'lmstudio/qwen-agentworld-35b-a3b',
                            input=0, output=0, cost=0.0, turns=0, context=0,
                            stop='error'),
        ]}),
    ])
    events = _subagent_events(sessions_root)
    assert len(events) == 1
    assert events[0].stop_reason == 'error'
    assert events[0].input == 0


def test_non_subagent_tool_results_ignored(sessions_root):
    write_session(sessions_root, '/tmp/p', 's1', TS1, [
        tool_result_msg('e3', None, TS2, 'bash', {'stdout': 'x'}),
        tool_result_msg('e4', 'e3', TS3, 'read', {'content': 'y'}),
    ])
    assert _subagent_events(sessions_root) == []
