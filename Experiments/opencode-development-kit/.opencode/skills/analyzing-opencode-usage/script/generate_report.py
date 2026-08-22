#!/usr/bin/env python3
"""Entry point for generating [ProjectName] LLM usage reports.

This script wires all query modules and the aggregator to produce
a complete JSON report, optionally rendered as HTML.
"""

import argparse
import json
import sys
from datetime import date
from pathlib import Path

# Add script directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from queries import summary, daily_tokens, models, agents, cross_tab, top_sessions, agents_detailed, weekly, productivity, build_productivity, git_commits, daily_git, cache_estimate as cache_queries
from aggregator.merge import merge_datasets
from queries.utils import _resolve_date


def fetch_all_datasets(
    project_path: str | None,
    since: str | None,
    until: str | None,
    days: int | None,
) -> dict:
    """Fetch all query datasets.

    Args:
        project_path: Project directory to filter by.
        since: Start date (YYYY-MM-DD).
        until: End date (YYYY-MM-DD).
        days: Number of days from today.

    Returns:
        Dictionary with all fetched data ready for merging.
    """
    start_date, end_date = _resolve_date(since, until, days)

    # Fetch all datasets
    # Project range takes no date params: the true all-time range, filter-independent
    project_range_data = summary.fetch_project_range(project=project_path)
    summary_data = summary.fetch(project=project_path, since=start_date, until=end_date)
    daily_tokens_data = daily_tokens.fetch(project=project_path, since=start_date, until=end_date)
    models_data = models.fetch(project=project_path, since=start_date, until=end_date)
    agents_data = agents.fetch(project=project_path, since=start_date, until=end_date)
    cross_tab_data = cross_tab.fetch(project=project_path, since=start_date, until=end_date)
    top_sessions_data = top_sessions.fetch(project=project_path, since=start_date, until=end_date)
    agents_detailed_data = agents_detailed.fetch(project=project_path, since=start_date, until=end_date)
    weekly_data = weekly.fetch(project=project_path, since=start_date, until=end_date)
    productivity_data = productivity.fetch(project=project_path, since=start_date, until=end_date)
    build_productivity_data = build_productivity.fetch(project=project_path, since=start_date, until=end_date)
    git_commits_data = git_commits.fetch(project=project_path, since=start_date, until=end_date)
    daily_git_data = daily_git.fetch(project=project_path, since=start_date, until=end_date)

    # Cache estimates - need aggregate, by_day, by_model, by_agent
    cache_agg = cache_queries.fetch_aggregate(project=project_path, since=start_date, until=end_date)
    cache_by_day = cache_queries.fetch_by_day(project=project_path, since=start_date, until=end_date)
    cache_by_model = cache_queries.fetch_by_model(project=project_path, since=start_date, until=end_date)
    cache_by_agent = cache_queries.fetch_by_agent(project=project_path, since=start_date, until=end_date)

    cache_estimate = {
        'aggregate': cache_agg,
        'by_day': cache_by_day,
        'by_model': cache_by_model,
        'by_agent': cache_by_agent,
    }

    return {
        'project_range': project_range_data,
        'summary_list': [summary_data] if summary_data else [],
        'daily_tokens': daily_tokens_data,
        'models': models_data,
        'agents': agents_data,
        'cross_tab': cross_tab_data,
        'top_sessions': top_sessions_data,
        'agents_detailed': agents_detailed_data,
        'weekly': weekly_data,
        'productivity_list': [productivity_data] if productivity_data else [],
        'build_prod_list': [build_productivity_data] if build_productivity_data else [],
        'cache_estimate': cache_estimate,
        'git_commits': git_commits_data,
        'daily_git': daily_git_data,
    }


def main():
    parser = argparse.ArgumentParser(
        description='Generate [ProjectName] LLM usage report',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument('--project', required=True, help='Project folder path (absolute or relative)')
    parser.add_argument('--since', help='Start date (YYYY-MM-DD)')
    parser.add_argument('--until', help='End date (YYYY-MM-DD)')
    parser.add_argument('--days', type=int, help='Last N days (overrides since/until)')
    parser.add_argument('--json', action='store_true', help='Output JSON instead of HTML')
    parser.add_argument('--output', help='Output file path')

    args = parser.parse_args()

    # Validate project path exists
    project_path = Path(args.project)
    if not project_path.exists():
        print(f"Error: Project path does not exist: {args.project}", file=sys.stderr)
        sys.exit(1)

    # Resolve dates
    start_date, end_date = _resolve_date(args.since, args.until, args.days)

    # Progress indication
    print(f"Fetching data for project: {args.project} ({start_date} to {end_date})...", file=sys.stderr)

    # Fetch all datasets
    data = fetch_all_datasets(
        project_path=args.project,
        since=start_date,
        until=end_date,
        days=None,  # Already resolved above; prevent double-resolution
    )

    print("Merging datasets...", file=sys.stderr)

    # Derive project name from path basename
    project_name = Path(args.project).name

    # Merge into final report structure
    output = merge_datasets(
        daily_agent=data['daily_tokens'],
        agents_detailed=data['agents_detailed'],
        weekly=data['weekly'],
        summary_raw=data['summary_list'],
        models_data=data['models'],
        agents_data=data['agents'],
        cross_tab=data['cross_tab'],
        top_sessions=data['top_sessions'],
        productivity_raw=data['productivity_list'],
        build_prod_raw=data['build_prod_list'],
        git_commits=data['git_commits'],
        daily_git=data['daily_git'],
        cache_estimate=data['cache_estimate'],
        project_range=data['project_range'],
        project_name=project_name,
    )

    # Add generated timestamp
    output['meta']['generated'] = date.today().isoformat()

    print("Rendering report...", file=sys.stderr)

    # Output
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
            print(f"Error: Could not import render_consolidated_report.py: {e}", file=sys.stderr)
            print("Falling back to JSON output. Use --json flag explicitly for clarity.", file=sys.stderr)
            # Fallback to JSON output instead of exiting
            if args.output:
                Path(args.output).write_text(json_output)
            else:
                print(json_output)


if __name__ == '__main__':
    main()
