#!/usr/bin/env python3
"""Entry point for generating pi LLM usage reports.

Wires the JSONL data layer (pi_sessions) and query modules to the aggregator,
producing a complete JSON report, optionally rendered as HTML.

Unlike the opencode kit (one SQLite round-trip per query), pi's JSONL files
are parsed ONCE per run and all query modules read from the shared in-memory
session structure.
"""

import argparse
import json
import sys
from datetime import date
from pathlib import Path

# Add script directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from pi_sessions import load_sessions
from queries import (
    summary, models, roles, cross_tab, timeseries, top_sessions,
    cache_estimate as cache_queries, git_commits, session_summaries,
)
from aggregator.merge import merge_datasets
from queries.utils import resolve_date


def fetch_all_datasets(
    project_path: str,
    since: str,
    until: str,
    sessions_root: str | None = None,
    docs_dir: str | None = None,
) -> dict:
    """Fetch all query datasets.

    Args:
        project_path: Project directory to filter by (cwd substring match).
        since: Start date (YYYY-MM-DD), inclusive.
        until: End date (YYYY-MM-DD), inclusive.
        sessions_root: Override for the pi sessions root.
        docs_dir: [docs directory] containing sessions/ summaries.

    Returns:
        Dictionary with all fetched data ready for merging.
    """
    root = Path(sessions_root) if sessions_root else None

    # Parse the JSONL once; every query module reads this structure.
    sessions = load_sessions(sessions_root=root, project=project_path,
                             since=since, until=until)

    # Subagent run attribution (from parent-session subagent tool results)
    subagent_events = [e for s in sessions for e in s.events if e.kind == 'subagent']
    by_agent: dict[str, dict] = {}
    for e in subagent_events:
        d = by_agent.setdefault(e.agent, {
            'agent': e.agent, 'runs': 0, 'turns': 0, 'total_input': 0,
            'total_output': 0, 'total_cost': 0.0, 'models': set()})
        d['runs'] += 1
        d['turns'] += e.turns
        d['total_input'] += e.input
        d['total_output'] += e.output
        d['total_cost'] += e.cost
        if e.model:
            d['models'].add(e.model)
    agent_rows = [
        {
            'agent': d['agent'], 'runs': d['runs'], 'turns': d['turns'],
            'total_input': d['total_input'], 'total_output': d['total_output'],
            'total_cost': round(d['total_cost'], 4),
            'models': sorted(d['models']),
        }
        for d in sorted(by_agent.values(),
                        key=lambda x: x['total_input'] + x['total_output'], reverse=True)
    ]
    subagent_runs = {
        'total_runs': len(subagent_events),
        'total_turns': sum(e.turns for e in subagent_events),
        'total_context_tokens': sum(e.context_tokens for e in subagent_events),
        'total_input': sum(e.input for e in subagent_events),
        'total_output': sum(e.output for e in subagent_events),
        'actual_cost': round(sum(e.cost for e in subagent_events), 4),
        'by_agent': agent_rows,
        'runs': [
            {
                'agent': e.agent, 'model': e.model, 'day': e.day,
                'session_id': e.session_id[:8], 'turns': e.turns,
                'context_tokens': e.context_tokens, 'input': e.input,
                'output': e.output, 'cost': e.cost, 'depth': e.depth,
                'stop_reason': e.stop_reason,
            }
            for e in sorted(subagent_events, key=lambda e: e.ts)
        ],
    }

    return {
        'sessions': sessions,
        # Project range takes no date params: the true all-time range,
        # filter-independent
        'project_range': summary.fetch_project_range(project=project_path,
                                                     sessions_root=root),
        'summary_list': [summary.fetch(project=project_path, since=since,
                                       until=until, sessions=sessions)],
        'daily_tokens': timeseries.fetch(project=project_path, since=since,
                                         until=until, sessions=sessions),
        'weekly': timeseries.fetch_weekly(project=project_path, since=since,
                                          until=until, sessions=sessions),
        'models': models.fetch(project=project_path, since=since,
                               until=until, sessions=sessions),
        'roles': roles.fetch(project=project_path, since=since,
                             until=until, sessions=sessions),
        'cross_tab': cross_tab.fetch(project=project_path, since=since,
                                     until=until, sessions=sessions),
        'top_sessions': top_sessions.fetch(project=project_path, since=since,
                                           until=until, sessions=sessions),
        # Productivity: total sessions + per-day session counts (for the
        # git-date join in merge)
        'productivity_list': [{
            'total_sessions': len(sessions),
            'daily_sessions': _sessions_by_day(sessions),
        }],
        # Build-role session totals (build-* roles + main, per category mapping)
        'build_prod_list': [_build_prod_row(sessions)],
        'cache_estimate': {
            'aggregate': cache_queries.fetch_aggregate(sessions=sessions),
            'by_day': cache_queries.fetch_by_day(sessions=sessions),
            'by_model': cache_queries.fetch_by_model(sessions=sessions),
            'by_role': cache_queries.fetch_by_role(sessions=sessions),
        },
        'git_commits': git_commits.fetch(project=project_path, since=since, until=until),
        'daily_git': git_commits.fetch_daily(project=project_path, since=since, until=until),
        'session_summaries': session_summaries.fetch(project=project_path, since=since,
                                                     until=until, docs_dir=docs_dir),
        'subagent_runs': subagent_runs,
    }


def _sessions_by_day(sessions) -> dict:
    """Per-day session counts (a session counts once per day it has events)."""
    from collections import defaultdict
    by_day: dict = defaultdict(set)
    for s in sessions:
        for e in s.events:
            by_day[e.day].add(s.session_id)
    return {day: len(ids) for day, ids in by_day.items()}


def _build_prod_row(sessions) -> dict:
    """Build-role productivity metrics (main + build-* roles)."""
    from queries.utils import role_category
    build_sessions = set()
    total_tokens = 0
    for s in sessions:
        s_tokens = 0
        for e in s.events:
            if role_category(e.role) == 'build':
                s_tokens += e.total
        if s_tokens > 0:
            build_sessions.add(s.session_id)
            total_tokens += s_tokens
    return {
        'date': '',
        'build_tokens': total_tokens,
        'commits': 0,
        'tokens_per_commit': 0.0,
        'total_build_sessions': len(build_sessions),
        'productive_sessions': 0,
        'total_tokens': total_tokens,
        'zero_change_tokens': total_tokens,
        'pct_productive': 0.0,
    }


def main():
    parser = argparse.ArgumentParser(
        description='Generate pi LLM usage report',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument('--project', required=True,
                        help='Project folder path (matched against session cwd)')
    parser.add_argument('--since', help='Start date (YYYY-MM-DD)')
    parser.add_argument('--until', help='End date (YYYY-MM-DD)')
    parser.add_argument('--days', type=int, help='Last N days (overrides since/until)')
    parser.add_argument('--sessions-root',
                        help='Override pi sessions root (default ~/.pi/agent/sessions)')
    parser.add_argument('--docs-dir',
                        help="[docs directory] with sessions/ summaries (default: auto-detect _agent_docs or docs)")
    parser.add_argument('--json', action='store_true', help='Output JSON instead of HTML')
    parser.add_argument('--output', help='Output file path')

    args = parser.parse_args()

    project_path = Path(args.project)

    # Resolve dates
    start_date, end_date = resolve_date(args.since, args.until, args.days)

    print(f"Fetching data for project: {args.project} ({start_date} to {end_date})...",
          file=sys.stderr)

    data = fetch_all_datasets(
        project_path=str(project_path),
        since=start_date,
        until=end_date,
        sessions_root=args.sessions_root,
        docs_dir=args.docs_dir,
    )

    print("Merging datasets...", file=sys.stderr)

    project_name = project_path.name

    output = merge_datasets(
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
        project_name=project_name,
        subagent_runs=data['subagent_runs'],
        session_summaries=data['session_summaries'],
    )

    # Add generated timestamp
    output['meta']['generated'] = date.today().isoformat()

    print("Rendering report...", file=sys.stderr)

    json_output = json.dumps(output, indent=2)

    if args.json or (args.output and args.output.endswith('.json')):
        if args.output:
            Path(args.output).write_text(json_output)
        else:
            print(json_output)
    else:
        # Render HTML using the existing renderer
        try:
            from render_consolidated_report import render_html
            html = render_html(output)
            if args.output:
                Path(args.output).write_text(html)
            else:
                print(html)
        except ImportError as e:
            print(f"Error: Could not import render_consolidated_report.py: {e}",
                  file=sys.stderr)
            print("Falling back to JSON output. Use --json flag explicitly for clarity.",
                  file=sys.stderr)
            if args.output:
                Path(args.output).write_text(json_output)
            else:
                print(json_output)


if __name__ == '__main__':
    main()
