#!/usr/bin/env bash
# generate_value_report.sh — Collect data for the Token Value Analysis report.
# Queries opencode's SQLite DB + git log, merges by date, emits a JSON file.
#
# Usage: ./generate_value_report.sh [OPTIONS]
#   --output PATH       Output JSON path (default: ./value-report-data.json)
#   --project PATTERN   Directory filter for session queries (default: CollageMaker)
#   --skip-shas LIST    Space-separated commit SHAs to exclude from git stats

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="./value-report-data.json"
PROJECT="CollageMaker"
SKIP_SHAS="a877b47 2f5d923 4c13f15 f43f886"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)   OUTPUT="$2"; shift 2 ;;
    --project)  PROJECT="$2"; shift 2 ;;
    --skip-shas) SKIP_SHAS="$2"; shift 2 ;;
    *)          echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

DB_CMD="sqlite3"
DB_PATH="${HOME}/.local/share/opencode/opencode.db"

query() {
  $DB_CMD "$DB_PATH" -json "$1"
}

echo "Generating Token Value Analysis data..." >&2
echo "  Output: ${OUTPUT}" >&2
echo "  Project filter: ${PROJECT}" >&2

# Escape single quotes in PROJECT to prevent SQL injection
PROJECT_ESCAPED="${PROJECT//\'/\'\'}"

# Verify we're in a git repository
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: Not a git repository. Run from within a git repo." >&2
  exit 1
fi

# ── 1. Daily tokens by agent category ────────────────────────────────────────
echo "  Querying daily tokens by agent..." >&2
DAILY_AGENT_JSON=$(query "
  SELECT
    strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') as day,
    COUNT(*) as sessions,
    SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens,
    COALESCE(SUM(tokens_input), 0) as input_tokens,
    COALESCE(SUM(tokens_output), 0) as output_tokens,
    COALESCE(SUM(tokens_reasoning), 0) as reasoning_tokens,
    COALESCE(SUM(CASE WHEN agent = 'build' THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0) as build_tok,
    COALESCE(SUM(CASE WHEN agent IN ('diff-review','diff-review-g31','solid-review','world-review','diff-review-q35','diff-review-o32') THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0) as review_tok,
    COALESCE(SUM(CASE WHEN agent IN ('planner','planner-g31','plan') THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0) as plan_tok,
    COALESCE(SUM(CASE WHEN agent = 'explore' THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0) as explore_tok,
    COALESCE(SUM(CASE WHEN agent NOT IN ('build','explore','diff-review','diff-review-g31','solid-review','world-review','diff-review-q35','diff-review-o32','planner','planner-g31','plan') THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0) as other_tok
  FROM session
  WHERE directory LIKE '%${PROJECT_ESCAPED}%'
  GROUP BY day
  ORDER BY day
")

# ── 2. Agent context efficiency (turns per session) ──────────────────────────
echo "  Querying agent context efficiency..." >&2
AGENT_CONTEXT_JSON=$(query "
  SELECT
    s.agent,
    COUNT(*) as sessions,
    SUM(s.tokens_input + s.tokens_output + s.tokens_reasoning) as total_tokens,
    SUM(s.tokens_input) as total_input,
    SUM(turn_counts.turns) as total_turns,
    ROUND(1.0 * SUM(turn_counts.turns) / COUNT(*), 2) as avg_turns,
    ROUND(1.0 * SUM(s.tokens_input) / NULLIF(SUM(turn_counts.turns), 0), 0) as avg_input_per_turn
  FROM session s
  JOIN (
    SELECT
      session_id,
      COUNT(*) as turns
    FROM message
    WHERE json_extract(data, '$.role') = 'user'
    GROUP BY session_id
  ) turn_counts ON turn_counts.session_id = s.id
  WHERE s.directory LIKE '%${PROJECT_ESCAPED}%'
  GROUP BY s.agent
  ORDER BY total_tokens DESC
")

# ── 3. Weekly token breakdown ────────────────────────────────────────────────
echo "  Querying weekly breakdown..." >&2
WEEKLY_JSON=$(query "
  SELECT
    strftime('%Y-W%W', time_created / 1000, 'unixepoch') as week,
    MIN(strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')) as week_start,
    MAX(strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')) as week_end,
    COUNT(*) as sessions,
    SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens,
    COALESCE(SUM(CASE WHEN agent = 'build' THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0) as build_tok,
    COALESCE(SUM(CASE WHEN agent IN ('diff-review','diff-review-g31','solid-review','world-review','diff-review-q35','diff-review-o32') THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0) as review_tok,
    COALESCE(SUM(CASE WHEN agent IN ('planner','planner-g31','plan') THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0) as plan_tok,
    COALESCE(SUM(CASE WHEN agent = 'explore' THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0) as explore_tok,
    COALESCE(SUM(CASE WHEN agent NOT IN ('build','explore','diff-review','diff-review-g31','solid-review','world-review','diff-review-q35','diff-review-o32','planner','planner-g31','plan') THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END), 0) as other_tok
  FROM session
  WHERE directory LIKE '%${PROJECT_ESCAPED}%'
  GROUP BY week
  ORDER BY week
")

# ── 4. Summary metrics ───────────────────────────────────────────────────────
echo "  Querying summary metrics..." >&2
SUMMARY_JSON=$(query "
  SELECT
    COUNT(*) as total_sessions,
    SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens,
    SUM(tokens_input) as total_input,
    SUM(tokens_output) as total_output,
    SUM(tokens_reasoning) as total_reasoning,
    MIN(strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')) as earliest,
    MAX(strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')) as latest,
    COUNT(DISTINCT COALESCE(json_extract(model, '$.id'), 'unknown')) as model_count,
    COUNT(DISTINCT COALESCE(agent, 'unknown')) as agent_count
  FROM session
  WHERE directory LIKE '%${PROJECT_ESCAPED}%'
")

# ── 5. Git data: all Swift commits with numstat ──────────────────────────────
echo "  Extracting git Swift stats..." >&2
SWIFT_GIT_JSON=$(SKIP_SHAS="$SKIP_SHAS" git log --reverse --numstat --date=short --pretty=format:'COMMIT:%h|%ad|%s' -- '*.swift' 2>/dev/null | python3 -c "
import sys, json, os

skip_shas = set(os.environ.get('SKIP_SHAS', '').split())
commits = []
current = None
for line in sys.stdin:
    line = line.rstrip('\n')
    if line.startswith('COMMIT:'):
        if current and current['sha'] not in skip_shas:
            commits.append(current)
        parts = line[7:].split('|', 2)
        current = {
            'sha': parts[0],
            'date': parts[1],
            'message': parts[2] if len(parts) > 2 else '',
            'adds': 0,
            'dels': 0,
            'test_adds': 0,
            'test_dels': 0,
            'is_test': False
        }
    elif current and line and '\t' in line:
        parts = line.split('\t')
        if len(parts) >= 2:
            try:
                a = int(parts[0]) if parts[0] != '-' else 0
                d = int(parts[1]) if parts[1] != '-' else 0
                fpath = parts[2] if len(parts) > 2 else ''
                current['adds'] += a
                current['dels'] += d
                if 'Test' in fpath or 'test' in fpath.lower():
                    current['test_adds'] += a
                    current['test_dels'] += d
                    current['is_test'] = True
            except ValueError:
                pass
if current and current['sha'] not in skip_shas:
    commits.append(current)

# Compute cumulative
cum_swift = 0
cum_test = 0
for c in commits:
    cum_swift += c['adds'] - c['dels']
    cum_test += c['test_adds'] - c['test_dels']
    c['cum_swift'] = cum_swift
    c['cum_test'] = cum_test

print(json.dumps(commits))
" 2>/dev/null || echo "[]")

# ── 6. Git data: daily aggregates ────────────────────────────────────────────
echo "  Computing daily git aggregates..." >&2
DAILY_GIT_JSON=$(SKIP_SHAS="$SKIP_SHAS" git log --reverse --numstat --date=short --pretty=format:'COMMIT:%h|%ad|%s' -- '*.swift' 2>/dev/null | python3 -c "
import sys, json, os
from collections import defaultdict

skip_shas = set(os.environ.get('SKIP_SHAS', '').split())
daily = defaultdict(lambda: {'commits': 0, 'adds': 0, 'dels': 0, 'test_adds': 0, 'test_dels': 0, 'dates': set()})
current = None
for line in sys.stdin:
    line = line.rstrip('\n')
    if line.startswith('COMMIT:'):
        if current and current['sha'] not in skip_shas:
            d = daily[current['date']]
            d['commits'] += 1
            d['adds'] += current['adds']
            d['dels'] += current['dels']
            d['test_adds'] += current['test_adds']
            d['test_dels'] += current['test_dels']
        parts = line[7:].split('|', 2)
        current = {'sha': parts[0], 'date': parts[1], 'adds': 0, 'dels': 0, 'test_adds': 0, 'test_dels': 0}
    elif current and line and '\t' in line:
        parts = line.split('\t')
        if len(parts) >= 2:
            try:
                a = int(parts[0]) if parts[0] != '-' else 0
                d = int(parts[1]) if parts[1] != '-' else 0
                fpath = parts[2] if len(parts) > 2 else ''
                current['adds'] += a
                current['dels'] += d
                if 'Test' in fpath or 'test' in fpath.lower():
                    current['test_adds'] += a
                    current['test_dels'] += d
            except ValueError:
                pass
if current and current['sha'] not in skip_shas:
    d = daily[current['date']]
    d['commits'] += 1
    d['adds'] += current['adds']
    d['dels'] += current['dels']
    d['test_adds'] += current['test_adds']
    d['test_dels'] += current['test_dels']

# Output as list sorted by date
result = []
for date in sorted(daily.keys()):
    d = daily[date]
    result.append({
        'date': date,
        'commits': d['commits'],
        'adds': d['adds'],
        'dels': d['dels'],
        'test_adds': d['test_adds'],
        'test_dels': d['test_dels']
    })
print(json.dumps(result))
" 2>/dev/null || echo "[]")

# ── 7. Sessions with file changes (productivity) ─────────────────────────────
echo "  Querying productivity stats..." >&2
PRODUCTIVITY_JSON=$(query "
  SELECT
    COUNT(*) as total_sessions,
    SUM(CASE WHEN summary_files > 0 THEN 1 ELSE 0 END) as sessions_with_changes,
    ROUND(100.0 * SUM(CASE WHEN summary_files > 0 THEN 1 ELSE 0 END) / COUNT(*), 1) as pct_with_changes
  FROM session
  WHERE directory LIKE '%${PROJECT_ESCAPED}%'
")

# ── 8. Build agent productivity ──────────────────────────────────────────────
echo "  Querying build agent productivity..." >&2
BUILD_PRODUCTIVITY_JSON=$(query "
  SELECT
    COUNT(*) as total_build_sessions,
    SUM(CASE WHEN summary_files > 0 THEN 1 ELSE 0 END) as productive_sessions,
    SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens,
    SUM(CASE WHEN summary_files = 0 THEN tokens_input + tokens_output + tokens_reasoning ELSE 0 END) as zero_change_tokens,
    ROUND(100.0 * SUM(CASE WHEN summary_files > 0 THEN 1 ELSE 0 END) / COUNT(*), 1) as pct_productive
  FROM session
  WHERE directory LIKE '%${PROJECT_ESCAPED}%' AND agent = 'build'
")

# ── Merge all data into single JSON ──────────────────────────────────────────
echo "  Merging data..." >&2
python3 -c "
import sys, json

# Parse all inputs
daily_agent = json.loads(sys.argv[1]) if sys.argv[1] else []
agent_context = json.loads(sys.argv[2]) if sys.argv[2] else []
weekly = json.loads(sys.argv[3]) if sys.argv[3] else []
summary = json.loads(sys.argv[4])[0] if sys.argv[4] else {}
swift_commits = json.loads(sys.argv[5]) if sys.argv[5] else []
daily_git = json.loads(sys.argv[6]) if sys.argv[6] else []
productivity = json.loads(sys.argv[7])[0] if sys.argv[7] else {}
build_prod = json.loads(sys.argv[8])[0] if sys.argv[8] else {}

# Build daily token map for merging with git data
token_map = {}
for r in daily_agent:
    token_map[r['day']] = {
        'total_tokens': r.get('total_tokens', 0) or 0,
        'sessions': r.get('sessions', 0) or 0,
        'input_tokens': r.get('input_tokens', 0) or 0,
        'output_tokens': r.get('output_tokens', 0) or 0,
        'reasoning_tokens': r.get('reasoning_tokens', 0) or 0,
        'build_tok': r.get('build_tok', 0) or 0,
        'review_tok': r.get('review_tok', 0) or 0,
        'plan_tok': r.get('plan_tok', 0) or 0,
        'explore_tok': r.get('explore_tok', 0) or 0,
        'other_tok': r.get('other_tok', 0) or 0
    }

# Merge git data into daily rows
git_map = {}
for r in daily_git:
    git_map[r['date']] = {
        'commits': r.get('commits', 0),
        'adds': r.get('adds', 0),
        'dels': r.get('dels', 0),
        'test_adds': r.get('test_adds', 0),
        'test_dels': r.get('test_dels', 0)
    }

# Build merged daily rows for charts
merged_daily = []
all_dates = sorted(set(list(token_map.keys()) + list(git_map.keys())))
for date in all_dates:
    t = token_map.get(date, {})
    g = git_map.get(date, {})
    merged_daily.append({
        'date': date,
        'sessions': t.get('sessions', 0),
        'total_tokens': t.get('total_tokens', 0),
        'input_tokens': t.get('input_tokens', 0),
        'output_tokens': t.get('output_tokens', 0),
        'reasoning_tokens': t.get('reasoning_tokens', 0),
        'build_tok': t.get('build_tok', 0),
        'review_tok': t.get('review_tok', 0),
        'plan_tok': t.get('plan_tok', 0),
        'explore_tok': t.get('explore_tok', 0),
        'other_tok': t.get('other_tok', 0),
        'commits': g.get('commits', 0),
        'adds': g.get('adds', 0),
        'dels': g.get('dels', 0),
        'test_adds': g.get('test_adds', 0),
        'test_dels': g.get('test_dels', 0)
    })

# Compute cumulative values for efficiency curves
cum_tokens = 0
cum_swift = 0
cum_test = 0
for r in merged_daily:
    cum_tokens += r['total_tokens']
    cum_swift += r['adds']
    cum_test += r['test_adds']
    r['cum_tokens'] = cum_tokens
    r['cum_swift'] = cum_swift
    r['cum_test'] = cum_test

# Compute 7-day rolling tokens per commit
for i, r in enumerate(merged_daily):
    start = max(0, i - 6)
    window = merged_daily[start:i+1]
    window_tokens = sum(w['total_tokens'] for w in window)
    window_commits = sum(w['commits'] for w in window)
    if window_commits > 0:
        r['rolling_tok_per_commit'] = round(window_tokens / window_commits)
    elif i > 0 and merged_daily[i-1].get('rolling_tok_per_commit', 0) > 0:
        r['rolling_tok_per_commit'] = merged_daily[i-1]['rolling_tok_per_commit']
    else:
        r['rolling_tok_per_commit'] = 0

# Compute test ratio
for r in merged_daily:
    total_adds = r['adds']
    r['test_ratio'] = round(100.0 * r['test_adds'] / total_adds, 1) if total_adds > 0 else 0

# Compute per-commit efficiency for top/least efficient commits
# Map commit date -> daily tokens for attribution
commit_efficiency = []
for c in swift_commits:
    date = c['date']
    t = token_map.get(date, {})
    daily_tokens = t.get('total_tokens', 0)
    daily_commits = git_map.get(date, {}).get('commits', 0)
    tok_per_commit = round(daily_tokens / daily_commits) if daily_commits > 0 else 0
    lines_changed = c['adds'] + c['dels']
    tok_per_line = round(tok_per_commit / lines_changed) if lines_changed > 0 else 0
    commit_efficiency.append({
        'sha': c['sha'],
        'date': c['date'],
        'message': c['message'],
        'adds': c['adds'],
        'dels': c['dels'],
        'lines_changed': lines_changed,
        'tok_per_commit': tok_per_commit,
        'tok_per_line': tok_per_line,
        'is_test': c.get('is_test', False)
    })

# Top 10 most efficient (lowest tok/line, min 1 line changed)
most_efficient = sorted(
    [c for c in commit_efficiency if c['lines_changed'] > 0],
    key=lambda c: c['tok_per_line']
)[:10]

# Top 10 least efficient (highest tok/line, min 1 line changed)
least_efficient = sorted(
    [c for c in commit_efficiency if c['lines_changed'] > 0],
    key=lambda c: c['tok_per_line'],
    reverse=True
)[:10]

# Phase summary
phases = [
    {'name': 'Pre-Merge Exploration', 'start': '2026-05-10', 'end': '2026-05-24'},
    {'name': 'Ramp-Up', 'start': '2026-05-25', 'end': '2026-05-31'},
    {'name': 'Feature Velocity', 'start': '2026-06-01', 'end': '2026-06-14'},
    {'name': 'Efficiency Gains', 'start': '2026-06-15', 'end': '2026-06-29'}
]
for p in phases:
    phase_daily = [r for r in merged_daily if p['start'] <= r['date'] <= p['end']]
    p['tokens'] = sum(r['total_tokens'] for r in phase_daily)
    p['sessions'] = sum(r['sessions'] for r in phase_daily)
    p['commits'] = sum(r['commits'] for r in phase_daily)
    p['swift_adds'] = sum(r['adds'] for r in phase_daily)
    p['test_adds'] = sum(r['test_adds'] for r in phase_daily)
    p['tok_per_commit'] = round(p['tokens'] / p['commits']) if p['commits'] > 0 else 0
    p['tok_per_swift'] = round(p['tokens'] / p['swift_adds']) if p['swift_adds'] > 0 else 0
    p['test_pct'] = round(100.0 * p['test_adds'] / p['swift_adds'], 1) if p['swift_adds'] > 0 else 0

# Cost estimation (input only, output excluded due to local caching uncertainty)
# Cheap tier: 0.05/M input, 0.15/M output
# Expensive tier: 0.50/M input, 1.50/M output
CHEAP_INPUT = 0.05 / 1e6
CHEAP_OUTPUT = 0.15 / 1e6
EXP_INPUT = 0.50 / 1e6
EXP_OUTPUT = 1.50 / 1e6

cum_cheap = 0.0
cum_exp = 0.0
for r in merged_daily:
    inp = r.get('input_tokens', 0)
    out = r.get('output_tokens', 0)
    day_cheap = inp * CHEAP_INPUT + out * CHEAP_OUTPUT
    day_exp = inp * EXP_INPUT + out * EXP_OUTPUT
    cum_cheap += day_cheap
    cum_exp += day_exp
    r['cost_cheap'] = round(cum_cheap, 2)
    r['cost_expensive'] = round(cum_exp, 2)
    r['daily_cost_cheap'] = round(day_cheap, 2)
    r['daily_cost_expensive'] = round(day_exp, 2)

total_input = summary.get('total_input', 0) or 0
total_output = summary.get('total_output', 0) or 0
cost_summary = {
    'total_cheap': round(total_input * CHEAP_INPUT + total_output * CHEAP_OUTPUT, 2),
    'total_expensive': round(total_input * EXP_INPUT + total_output * EXP_OUTPUT, 2),
    'input_tokens': total_input,
    'output_tokens': total_output,
    'cheap_input_per_m': 0.05,
    'cheap_output_per_m': 0.15,
    'expensive_input_per_m': 0.50,
    'expensive_output_per_m': 1.50,
    'note': 'Input-only pricing recommended (output excluded) due to unknown local LM Studio caching.'
}

for p in phases:
    phase_inp = sum(r.get('input_tokens', 0) for r in merged_daily if p['start'] <= r['date'] <= p['end'])
    phase_out = sum(r.get('output_tokens', 0) for r in merged_daily if p['start'] <= r['date'] <= p['end'])
    p['cost_cheap'] = round(phase_inp * CHEAP_INPUT + phase_out * CHEAP_OUTPUT, 2)
    p['cost_expensive'] = round(phase_inp * EXP_INPUT + phase_out * EXP_OUTPUT, 2)

output = {
    'summary': summary,
    'cost_summary': cost_summary,
    'productivity': productivity,
    'build_productivity': build_prod,
    'phases': phases,
    'merged_daily': merged_daily,
    'weekly': weekly,
    'agent_context': agent_context,
    'most_efficient_commits': most_efficient,
    'least_efficient_commits': least_efficient,
    'generated': __import__('datetime').datetime.now().strftime('%Y-%m-%d %H:%M %Z')
}

print(json.dumps(output, indent=2))
" "$DAILY_AGENT_JSON" \
  "$AGENT_CONTEXT_JSON" \
  "$WEEKLY_JSON" \
  "$SUMMARY_JSON" \
  "$SWIFT_GIT_JSON" \
  "$DAILY_GIT_JSON" \
  "$PRODUCTIVITY_JSON" \
  "$BUILD_PRODUCTIVITY_JSON" > "$OUTPUT"

echo "Data written: ${OUTPUT} ($(wc -c < "$OUTPUT") bytes)" >&2
