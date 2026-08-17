#!/usr/bin/env python3
"""pi-analytics — Query pi's session JSONL files for usage analytics.

Port of the opencode kit's analytics.sh (which queried opencode's SQLite DB
via `opencode db`). The flag surface is the same, except:
  - --agents / --model-agents became --roles / --model-roles
    (--agents and --model-agents still work as aliases)
  - --impact is git-based (pi does not record per-session file changes)
  - --subagents reports per-run subagent attribution (pi-only capability)
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from pi_sessions import load_sessions
from queries import (
    summary, models, roles, cross_tab, timeseries, top_sessions,
    cache_estimate, git_commits,
)
from queries.utils import resolve_date, sessions_by_day


# ── Formatting helpers ───────────────────────────────────────────────────────

def fmt_num(n: int) -> str:
    """Format a number with commas."""
    sign = '-' if n < 0 else ''
    s = str(abs(int(n)))
    parts = []
    while len(s) > 3:
        parts.append(s[-3:])
        s = s[:-3]
    parts.append(s)
    return sign + ','.join(reversed(parts))


def fmt_tokens(n: float) -> str:
    """Format tokens in human-readable form."""
    n = int(n)
    if n >= 1_000_000_000:
        return f'{n / 1_000_000_000:.1f}B'
    if n >= 1_000_000:
        return f'{n / 1_000_000:.1f}M'
    if n >= 1_000:
        return f'{n / 1_000:.1f}K'
    return str(n)


def section(title: str) -> None:
    print()
    print('━' * 72)
    print(f'  {title}')
    print('━' * 72)


def print_filter(args) -> None:
    filters = []
    if args.project:
        filters.append(f'project: {args.project}')
    if args.since:
        filters.append(f'since: {args.since}')
    if args.until:
        filters.append(f'until: {args.until}')
    if filters:
        print(f'  Filter: {", ".join(filters)}')


# ── Sections ─────────────────────────────────────────────────────────────────

def show_summary(args, sessions) -> dict:
    section('pi Usage Summary')
    print_filter(args)
    data = summary.fetch(sessions=sessions)
    avg = data['total_tokens_raw'] // data['total_sessions'] if data['total_sessions'] else 0
    print()
    print(f"  Sessions:          {fmt_num(data['total_sessions'])}")
    print(f"  Models:            {data['model_count']}")
    print(f"  Roles:             {data['role_count']}")
    print(f"  Date range:        {data['earliest']} → {data['latest']}")
    print()
    print("  Tokens:")
    print(f"    Input:           {fmt_num(data['total_input_raw'])} ({fmt_tokens(data['total_input_raw'])})")
    print(f"    Output:          {fmt_num(data['total_output'])} ({fmt_tokens(data['total_output'])})")
    print(f"    Reasoning:       {fmt_num(data['total_reasoning'])} ({fmt_tokens(data['total_reasoning'])})")
    print(f"    Cache read:      {fmt_num(data['cache_read'])} ({fmt_tokens(data['cache_read'])})")
    print(f"    Cache write:     {fmt_num(data['cache_write'])} ({fmt_tokens(data['cache_write'])})")
    print(f"    Total:           {fmt_num(data['total_tokens_raw'])} ({fmt_tokens(data['total_tokens_raw'])})")
    print(f"  Avg per session:   {fmt_num(avg)} ({fmt_tokens(avg)})")
    if data.get('actual_cost'):
        print(f"  Actual cost:       ${data['actual_cost']:,.2f} (from recorded usage)")
    return data


def show_models(args, sessions) -> list[dict]:
    section('Token Usage by Model')
    print_filter(args)
    rows = models.fetch(sessions=sessions)
    print()
    print(f"  {'Model':<35} {'Sess':>6} {'Input':>12} {'Output':>12} {'Reason':>12} {'Total':>12}")
    print('  ' + '─' * 95)
    for r in rows:
        model = (r['model'] or 'unknown')[:35]
        print(f"  {model:<35} {r['sessions']:>6} "
              f"{fmt_tokens(r['input_tokens_raw']):>12} {fmt_tokens(r['output_tokens_raw']):>12} "
              f"{fmt_tokens(r['reasoning_tokens_raw']):>12} {fmt_tokens(r['total_tokens_raw']):>12}")
    return rows


def show_roles(args, sessions) -> list[dict]:
    section('Token Usage by Role')
    print_filter(args)
    rows = roles.fetch(sessions=sessions)
    print()
    print(f"  {'Role':<25} {'Sess':>6} {'Total':>14} {'Avg/Session':>14}")
    print('  ' + '─' * 63)
    for r in rows:
        role = (r['role'] or '(none)')[:25]
        total = r['total_tokens_raw']
        avg = total // r['sessions'] if r['sessions'] else 0
        print(f"  {role:<25} {r['sessions']:>6} "
              f"{fmt_tokens(total):>14} {fmt_tokens(avg):>14}")
    return rows


def show_model_roles(args, sessions) -> list[dict]:
    section('Model × Role Breakdown')
    print_filter(args)
    rows = cross_tab.fetch(sessions=sessions)
    print()
    print(f"  {'Model':<30} {'Role':<20} {'Sess':>5} {'Total':>14} {'Avg/Session':>14}")
    print('  ' + '─' * 87)
    for r in rows[:30]:
        model = (r['model'] or 'unknown')[:30]
        role = (r['role'] or '(none)')[:20]
        total = r['total_tokens_raw']
        avg = total // r['sessions'] if r['sessions'] else 0
        print(f"  {model:<30} {role:<20} {r['sessions']:>5} "
              f"{fmt_tokens(total):>14} {fmt_tokens(avg):>14}")
    return rows


def show_timeseries(args, sessions) -> list[dict]:
    section('Daily Token Trend')
    print_filter(args)
    rows = timeseries.fetch(sessions=sessions)
    print()
    print(f"  {'Date':<12} {'Sess':>6} {'Tokens':>14}")
    print('  ' + '─' * 36)
    for r in rows:
        print(f"  {r['date']:<12} {r['sessions']:>6} {fmt_tokens(r['total_tokens_raw']):>14}")
    return rows


def show_weekly(args, sessions) -> list[dict]:
    section('Weekly Token Trend')
    print_filter(args)
    rows = timeseries.fetch_weekly(sessions=sessions)
    print()
    print(f"  {'Week':<10} {'Sess':>6} {'Tokens':>14}")
    print('  ' + '─' * 34)
    for r in rows:
        print(f"  {r['week']:<10} {r['total_sessions']:>6} {fmt_tokens(r['total_tokens_raw']):>14}")
    return rows


def show_monthly(args, sessions) -> list[dict]:
    section('Monthly Token Trend')
    print_filter(args)
    rows = timeseries.fetch_monthly(sessions=sessions)
    print()
    print(f"  {'Month':<8} {'Sess':>6} {'Tokens':>14}")
    print('  ' + '─' * 32)
    for r in rows:
        print(f"  {r['month']:<8} {r['sessions']:>6} {fmt_tokens(r['total_tokens_raw']):>14}")
    return rows


def show_projects(args, sessions) -> list[dict]:
    section('Token Usage by Project')
    print_filter(args)
    rows = timeseries.fetch_by_project(sessions=sessions)
    print()
    print(f"  {'Directory':<60} {'Sess':>5} {'Total':>14} {'Models':>8}")
    print('  ' + '─' * 93)
    for r in rows:
        directory = r['directory']
        if len(directory) > 60:
            directory = '...' + directory[-57:]
        print(f"  {directory:<60} {r['sessions']:>5} {fmt_tokens(r['total_tokens']):>14} {r['models_used']:>8}")
    return rows


def show_top_sessions(args, sessions) -> list[dict]:
    section(f'Top {args.top_n} Sessions by Token Usage')
    print_filter(args)
    rows = top_sessions.fetch(sessions=sessions, limit=args.top_n)
    print()
    print(f"  {'Date':<12} {'Role':<20} {'Model':<30} {'Title':<35} {'Tokens':>10}")
    print('  ' + '─' * 112)
    for r in rows:
        created = r['created'][:12]
        role = (r['role'] or '(none)')[:20]
        model = (r['model'] or 'unknown')[:30]
        title = r['title'][:32] + '...' if len(r['title']) > 35 else r['title']
        print(f"  {created:<12} {role:<20} {model:<30} {title:<35} {fmt_tokens(r['tokens']):>10}")
    return rows


def show_impact(args, sessions) -> dict:
    """File change impact, git-based (pi does not record per-session changes)."""
    section('File Change Impact (git)')
    print_filter(args)

    since, until = resolve_date(args.since, args.until, args.days)
    commits = git_commits.fetch(project=args.project, since=since, until=until)
    daily_git = git_commits.fetch_daily(project=args.project, since=since, until=until)

    # Measured attribution (Pi-Session trailers) where present.
    attr = git_commits.summarize_attribution(commits)
    git_dates = {r['date'] for r in daily_git if r['commits'] > 0}
    if attr['attributed_commits'] > 0:
        # Estimate only the unattributed remainder (their commit days).
        est_dates = {c['date'] for c in commits if not c.get('session_id')}
    else:
        est_dates = git_dates
    # Distinct sessions on commit days (not events — a session has many turns).
    s_by_day = sessions_by_day(sessions)
    sessions_with_changes = sum(n for day, n in s_by_day.items() if day in est_dates)

    total_commits = sum(r['commits'] for r in daily_git)
    total_adds = sum(r['adds'] for r in daily_git)
    total_dels = sum(r['dels'] for r in daily_git)
    total_test_adds = sum(r['test_adds'] for r in daily_git)

    print()
    print(f"  Sessions in range:            {len(sessions)}")
    if attr['attributed_commits'] > 0:
        print(f"  Commits attributed:           {attr['attributed_commits']} of {total_commits} "
              f"(Pi-Session trailer)")
        print(f"  Sessions with changes:        {attr['sessions_measured']} (measured) "
              f"+ {sessions_with_changes} est. for unattributed")
    else:
        print(f"  Sessions on commit days:      {sessions_with_changes} "
              f"(date-matched estimate — pi does not record per-session file changes)")
    print()
    print(f"  {'Date':<12} {'Commits':>8} {'Lines +':>10} {'Lines -':>10} {'Test +':>10}")
    print('  ' + '─' * 56)
    for r in sorted(daily_git, key=lambda x: x['date']):
        print(f"  {r['date']:<12} {r['commits']:>8} {fmt_num(r['adds']):>10} "
              f"{fmt_num(r['dels']):>10} {fmt_num(r['test_adds']):>10}")
    print()
    print(f"  Totals: {total_commits} commits, +{fmt_num(total_adds)} / -{fmt_num(total_dels)} lines "
          f"(+{fmt_num(total_test_adds)} test)")
    return {
        'sessions': len(sessions),
        'sessions_with_changes': sessions_with_changes,
        'sessions_with_changes_measured': attr['sessions_measured'],
        'attributed_commits': attr['attributed_commits'],
        'unattributed_commits': attr['unattributed_commits'],
        'commits': total_commits,
        'adds': total_adds, 'dels': total_dels, 'test_adds': total_test_adds,
        'daily': daily_git,
    }


def show_cache(args, sessions) -> dict:
    section('Prefix Cache Approximation')
    print_filter(args)
    agg = cache_estimate.fetch_aggregate(sessions=sessions)
    by_model = cache_estimate.fetch_by_model(sessions=sessions)
    by_role = cache_estimate.fetch_by_role(sessions=sessions)

    print()
    print("  Aggregate:")
    print(f"    Raw input:        {fmt_num(agg['total_input_raw'])} ({fmt_tokens(agg['total_input_raw'])})")
    print(f"    Est. uncached:    {fmt_num(agg['estimated_uncached_input'])} ({fmt_tokens(agg['estimated_uncached_input'])})")
    print(f"    Est. cached:      {fmt_num(agg['estimated_cached_input'])} ({fmt_tokens(agg['estimated_cached_input'])})")
    print(f"    Cache hit rate:   {agg['cache_hit_pct']}%")
    mode = ('simulated (LAG-delta fallback — no real cache reads in range)'
            if agg.get('simulated') else 'measured (provider-reported cache reads)')
    print(f"    Estimation mode:  {mode}")
    print()
    print(f"  {'Model':<35} {'Sess':>6} {'Raw Input':>12} {'Uncached':>12} {'Hit %':>8}")
    print('  ' + '─' * 77)
    for r in by_model:
        model = (r['key'] or 'unknown')[:35]
        print(f"  {model:<35} {r['sessions']:>6} {fmt_tokens(r['total_input_raw']):>12} "
              f"{fmt_tokens(r['estimated_uncached_input']):>12} {r['cache_hit_pct']:>7}%")
    print()
    print(f"  {'Role':<25} {'Sess':>6} {'Raw Input':>12} {'Uncached':>12} {'Hit %':>8}")
    print('  ' + '─' * 67)
    for r in by_role:
        role = (r['key'] or 'main')[:25]
        print(f"  {role:<25} {r['sessions']:>6} {fmt_tokens(r['total_input_raw']):>12} "
              f"{fmt_tokens(r['estimated_uncached_input']):>12} {r['cache_hit_pct']:>7}%")
    return {'aggregate': agg, 'by_model': by_model, 'by_role': by_role,
            'by_day': cache_estimate.fetch_by_day(sessions=sessions)}


def show_subagents(args, sessions) -> dict:
    section('Subagent Runs')
    print_filter(args)
    runs = [e for s in sessions for e in s.events if e.kind == 'subagent']
    if not runs:
        print()
        print('  No subagent runs in this period.')
        return {}

    by_agent: dict[str, dict] = {}
    for e in runs:
        d = by_agent.setdefault(e.agent, {'runs': 0, 'turns': 0, 'input': 0, 'output': 0, 'cost': 0.0})
        d['runs'] += 1
        d['turns'] += e.turns
        d['input'] += e.input
        d['output'] += e.output
        d['cost'] += e.cost

    total_tokens = sum(e.input + e.output for e in runs)
    total_cost = sum(e.cost for e in runs)
    print()
    print(f"  Runs:              {len(runs)}")
    print(f"  LLM turns:         {sum(e.turns for e in runs)}")
    print(f"  Tokens (in+out):   {fmt_num(total_tokens)} ({fmt_tokens(total_tokens)})")
    print(f"  Actual cost:       ${total_cost:,.4f}")
    print()
    print(f"  {'Agent':<25} {'Runs':>6} {'Turns':>7} {'Tokens':>12} {'Cost':>12}")
    print('  ' + '─' * 66)
    for agent, d in sorted(by_agent.items(), key=lambda kv: kv[1]['input'] + kv[1]['output'], reverse=True):
        print(f"  {agent[:25]:<25} {d['runs']:>6} {d['turns']:>7} "
              f"{fmt_tokens(d['input'] + d['output']):>12} ${d['cost']:>11.4f}")
    return {
        'total_runs': len(runs),
        'by_agent': [{'agent': a, **d} for a, d in by_agent.items()],
        'runs': [
            {'agent': e.agent, 'model': e.model, 'day': e.day, 'session': e.session_id[:8],
             'turns': e.turns, 'context_tokens': e.context_tokens, 'input': e.input,
             'output': e.output, 'cost': e.cost, 'depth': e.depth, 'stop_reason': e.stop_reason}
            for e in sorted(runs, key=lambda e: e.ts)
        ],
    }


# ── Argument parsing ─────────────────────────────────────────────────────────

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="pi-analytics — Query pi's session JSONL files for usage analytics.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""examples:
  %(prog)s                               # all-time summary
  %(prog)s --week --models               # last 7 days by model
  %(prog)s --project [ProjectName]       # [ProjectName] only
  %(prog)s --summary --models --json     # JSON output
  %(prog)s --project [ProjectName] --cache --subagents""")
    p.add_argument('--project', help='Filter by project directory (substring match)')
    p.add_argument('--since', help='Start date (inclusive, YYYY-MM-DD)')
    p.add_argument('--until', help='End date (inclusive, YYYY-MM-DD; defaults to today)')
    p.add_argument('--days', type=int, help='Last N days (overrides --since)')
    p.add_argument('--week', action='store_true', help='Last 7 days')
    p.add_argument('--month', action='store_true', help='Last 30 days')
    p.add_argument('--all', action='store_true', help='All-time (no date filter)')
    p.add_argument('--models', action='store_true', help='Token usage by model')
    p.add_argument('--roles', action='store_true', help='Token usage by role')
    p.add_argument('--agents', action='store_true', help=argparse.SUPPRESS)  # alias
    p.add_argument('--model-roles', action='store_true', help='Model × role cross-tab')
    p.add_argument('--model-agents', action='store_true', help=argparse.SUPPRESS)  # alias
    p.add_argument('--timeseries', action='store_true', help='Daily token trend')
    p.add_argument('--weekly', action='store_true', help='Weekly token trend')
    p.add_argument('--monthly', action='store_true', help='Monthly token trend')
    p.add_argument('--projects', action='store_true', help='Token usage by project/directory')
    p.add_argument('--top-sessions', nargs='?', const=20, type=int, default=None,
                   metavar='N', help='Top N sessions by token count (default 20)')
    p.add_argument('--impact', action='store_true', help='File change impact (git-based)')
    p.add_argument('--cache', action='store_true', help='Prefix cache approximation')
    p.add_argument('--subagents', action='store_true', help='Subagent run attribution')
    p.add_argument('--summary', action='store_true', help='High-level overview (default if no flags)')
    p.add_argument('--json', action='store_true', help='Output raw JSON instead of formatted text')
    p.add_argument('--sessions-root', help='Override pi sessions root (default ~/.pi/agent/sessions)')
    p.add_argument('--docs-dir', help="[docs directory] with sessions/ summaries (for --json summary join)")
    return p


def main() -> int:
    args = build_parser().parse_args()

    # Date resolution: --days / --week / --month set --since; --all clears filters
    if args.all:
        args.since = None
        args.until = None
        args.days = None
    if args.days:
        args.since, _ = resolve_date(None, None, args.days)
    elif args.week:
        args.since, _ = resolve_date(None, None, 7)
    elif args.month:
        args.since, _ = resolve_date(None, None, 30)

    # Parse the JSONL once; every section reads the shared structure
    sessions = load_sessions(
        sessions_root=args.sessions_root,
        project=args.project,
        since=args.since,
        until=args.until,
    )

    want = {
        'summary': args.summary,
        'models': args.models,
        'roles': args.roles or args.agents,
        'model_roles': args.model_roles or args.model_agents,
        'timeseries': args.timeseries,
        'weekly': args.weekly,
        'monthly': args.monthly,
        'projects': args.projects,
        'top_sessions': args.top_sessions is not None,
        'impact': args.impact,
        'cache': args.cache,
        'subagents': args.subagents,
    }
    if not any(want.values()):
        want['summary'] = True

    if args.top_sessions is None:
        args.top_n = 20
    else:
        args.top_n = args.top_sessions

    if args.json:
        import contextlib
        import io

        out = {}
        for key, fn in (
            ('summary', lambda: [show_summary(args, sessions)]),
            ('models', lambda: show_models(args, sessions)),
            ('roles', lambda: show_roles(args, sessions)),
            ('model_roles', lambda: show_model_roles(args, sessions)),
            ('timeseries', lambda: show_timeseries(args, sessions)),
            ('weekly', lambda: show_weekly(args, sessions)),
            ('monthly', lambda: show_monthly(args, sessions)),
            ('projects', lambda: show_projects(args, sessions)),
            ('top_sessions', lambda: show_top_sessions(args, sessions)),
            ('impact', lambda: [show_impact(args, sessions)]),
            ('cache', lambda: [show_cache(args, sessions)]),
            ('subagents', lambda: [show_subagents(args, sessions)]),
        ):
            if want[key]:
                buf = io.StringIO()
                with contextlib.redirect_stdout(buf):
                    data = fn()  # section's text output is discarded in JSON mode
                out[key] = data
        print(json.dumps(out, indent=2, default=str))
        return 0

    if want['summary']:
        show_summary(args, sessions)
    if want['models']:
        show_models(args, sessions)
    if want['roles']:
        show_roles(args, sessions)
    if want['model_roles']:
        show_model_roles(args, sessions)
    if want['timeseries']:
        show_timeseries(args, sessions)
    if want['weekly']:
        show_weekly(args, sessions)
    if want['monthly']:
        show_monthly(args, sessions)
    if want['projects']:
        show_projects(args, sessions)
    if want['top_sessions']:
        show_top_sessions(args, sessions)
    if want['impact']:
        show_impact(args, sessions)
    if want['cache']:
        show_cache(args, sessions)
    if want['subagents']:
        show_subagents(args, sessions)
    print()
    return 0


if __name__ == '__main__':
    sys.exit(main())
