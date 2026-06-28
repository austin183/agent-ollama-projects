#!/usr/bin/env python3
"""Collect per-day activity data for agent-driven daily activity summaries.

Usage: python3 collect_daily_data.py --session-dir PATH < data.json > daily-data.json

Reads merged JSON from stdin (same format as render_report.py), matches session files
to days via git log, and outputs a structured daily-data.json file that agents can use
to generate human-readable activity summaries.
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path


def fmt(v):
    """Format token count for display (reuse from charts.py)."""
    if v >= 1e9:
        return f'{v/1e9:.1f}B'
    if v >= 1e6:
        return f'{v/1e6:.1f}M'
    if v >= 1e3:
        return f'{v/1e3:.1f}K'
    return f'{v:,}'


def get_session_files_for_day(session_dir, date):
    """Find session files touched on a given date via git log.
    
    Runs: git log --format="%H %s" --name-only --since="DATE" --until="DATE+1"
    Filters for files matching session-*.md pattern in session_dir.
    Returns list of session filenames (e.g., ["session-042.md", "session-043.md"])
    
    Falls back to empty list if git log fails or no matches found.
    """
    session_path = Path(session_dir).resolve()
    if not session_path.exists():
        return []
    
    # Find git repo root by walking up from session directory
    git_root = session_path
    while git_root != git_root.parent:
        if (git_root / '.git').exists():
            break
        git_root = git_root.parent
    try:
        # Get all files touched on this day (date inclusive, next day exclusive)
        result = subprocess.run(
            ['git', 'log', '--format=%H %s', '--name-only',
             f'--since={date}', f'--until={date}T23:59:59'],
            capture_output=True, text=True, cwd=str(git_root)
        )
        
        if result.returncode != 0:
            return []
        
        # Parse output to find session files
        session_files = []
        for line in result.stdout.split('\n'):
            line = line.strip().strip('"')
            if not line or line.startswith('commit '):
                continue
            
            # Only process lines that look like file paths (contain '/')
            if '/' not in line:
                continue
                
            filename = Path(line).name
            check_path = session_path / filename
            exists = check_path.is_file()
            
            if exists and filename.startswith('session-') and filename.endswith('.md'):
                session_files.append(filename)
        
        result_count = len(session_files)
        return sorted(set(session_files))
    
    except Exception as e:
        print(f"Warning: Failed to query git for {date}: {e}", file=sys.stderr)
        return []


def collect_daily_data(data, session_dir):
    """Build daily-data.json structure from merged data + git-based session matching."""
    
    token_map = data.get('token_map', {})
    git_map = data.get('git_map', {})
    
    # Find git repo root once for all git operations
    session_path = Path(session_dir).resolve()
    git_root = session_path
    while git_root != git_root.parent:
        if (git_root / '.git').exists():
            break
        git_root = git_root.parent
    
    # Build days array with token stats + git info + session files
    all_dates = sorted(set(list(token_map.keys()) + list(git_map.keys())))
    
    days = []
    for date in all_dates:
        d = token_map.get(date, None)
        commits_info = git_map.get(date, (0, 0, 0))
        commits = commits_info[0]
        adds = commits_info[1]
        dels = commits_info[2]
        
        # Get session files for this day via git
        if commits > 0:
            session_files = get_session_files_for_day(session_dir, date)
        else:
            session_files = []
        
        # Build day data structure
        day_data = {
            'date': date,
            'tokens': {
                'total': d['total_tokens'] if d else 0,
                'input': d['input_tokens'] if d else 0,
                'output': d['output_tokens'] if d else 0,
                'reasoning': d['reasoning_tokens'] if d else 0
            },
            'sessions': d['sessions'] if d else 0,
            'git': {
                'commits': commits,
                'adds': adds,
                'dels': dels,
                'shas': []  # Will be populated below if there are commits
            },
            'session_files': session_files
        }
        
        # If there are commits, get commit SHAs and messages via git log
        if commits > 0:
            try:
                result = subprocess.run(
                    ['git', 'log', '--format=%H %s', f'--since={date}', f'--until={date}T23:59:59'],
                    capture_output=True, text=True, cwd=str(git_root)
                )
                
                if result.returncode == 0:
                    for line in result.stdout.split('\n'):
                        line = line.strip().strip('"')
                        if not line or line.startswith('commit '):
                            continue
                        
                        # Parse "SHA message" format
                        parts = line.split(' ', 1)
                        sha = parts[0]
                        message = parts[1] if len(parts) > 1 else ''
                        day_data['git']['shas'].append({
                            'sha': sha,
                            'message': message
                        })
            except Exception as e:
                print(f"Warning: Failed to query git commits for {date}: {e}", file=sys.stderr)
        
        days.append(day_data)
    
    # Calculate totals
    total_tokens = sum(d['tokens']['total'] for d in days)
    total_input = sum(d['tokens']['input'] for d in days)
    total_output = sum(d['tokens']['output'] for d in days)
    total_reasoning = sum(d['tokens']['reasoning'] for d in days)
    total_sessions = sum(d['sessions'] for d in days)
    total_commits = sum(d['git']['commits'] for d in days)
    total_adds = sum(d['git']['adds'] for d in days)
    total_dels = sum(d['git']['dels'] for d in days)
    
    # Build output structure matching plan spec
    result = {
        'period': {
            'since': data.get('since', ''),
            'until': data.get('until', '')
        },
        'totals': {
            'tokens': {
                'total': total_tokens,
                'input': total_input,
                'output': total_output,
                'reasoning': total_reasoning
            },
            'sessions': total_sessions,
            'commits': total_commits,
            'lines_added': total_adds,
            'lines_deleted': total_dels
        },
        'days': days
    }
    
    return result


def main():
    """Parse args, read JSON from stdin, output daily-data.json."""
    parser = argparse.ArgumentParser(
        description='Collect per-day activity data for agent-driven summaries.'
    )
    parser.add_argument(
        '--session-dir', 
        required=True,
        help='Path to _agent_docs/project-timeline/sessions/'
    )
    args = parser.parse_args()
    
    # Read all data from stdin
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON input: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Collect daily data
    result = collect_daily_data(data, args.session_dir)
    
    # Output as formatted JSON
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
