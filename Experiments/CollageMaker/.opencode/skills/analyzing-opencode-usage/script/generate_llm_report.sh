#!/usr/bin/env bash
# generate_llm_report.sh — Generate an HTML LLM usage report for CollageMaker.
# Queries opencode's SQLite DB + git log, merges by date, emits a self-contained HTML file.
#
# Usage: ./generate_llm_report.sh [OPTIONS]
#   --since YYYY-MM-DD    Start date (inclusive)
#   --until YYYY-MM-DD    End date (inclusive, defaults to today)
#   --days N              Last N days (overrides --since; default 30)
#   --output PATH         Output file path (default: auto-generated in llm-usage/)
#   --activity            Also generate daily-data.json for agent-driven activity summaries

set -euo pipefail

# ── Defaults & Argument Parsing ──────────────────────────────────────────────

REPORT_DIR="$(cd "$(dirname "$0")/../../../../_agent_docs/project-timeline" && pwd)/llm-usage"
OUTPUT=""
SINCE=""
UNTIL=$(date +%Y-%m-%d)
DAYS=30
ACTIVITY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)   SINCE="$2"; shift 2 ;;
    --until)   UNTIL="$2"; shift 2 ;;
    --days)    DAYS="$2"; shift 2 ;;
    --output)  OUTPUT="$2"; shift 2 ;;
    --activity) ACTIVITY=true; shift ;;
    *)         echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$SINCE" ]]; then
  SINCE=$(date -v-${DAYS}d +%Y-%m-%d)
fi

if [[ -z "$OUTPUT" ]]; then
  OUTPUT="${REPORT_DIR}/$(date +%Y-%m-%d)-collagemaker-llm-report.html"
fi

mkdir -p "$(dirname "$OUTPUT")"

# ── Helpers ──────────────────────────────────────────────────────────────────

DB_CMD="opencode db"
FORMAT_FLAG="--format json"

query() {
  $DB_CMD "$1" $FORMAT_FLAG
}

fmt_tokens() {
  local n="$1"
  if (( n >= 1000000000 )); then
    printf "%.1fB" "$(echo "scale=1; $n / 1000000000" | bc)"
  elif (( n >= 1000000 )); then
    printf "%.1fM" "$(echo "scale=1; $n / 1000000" | bc)"
  elif (( n >= 1000 )); then
    printf "%.1fK" "$(echo "scale=1; $n / 1000" | bc)"
  else
    echo "$n"
  fi
}

# ── Data Gathering ───────────────────────────────────────────────────────────

read_summary() {
  local json
  json=$(query "
    SELECT
      COUNT(*) as sessions,
      SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens,
      MIN(strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')) as earliest,
      MAX(strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')) as latest,
      COUNT(DISTINCT json_extract(model, '$.id')) as model_count,
      COUNT(DISTINCT agent) as agent_count
    FROM session
    WHERE directory LIKE '%CollageMaker%'
      AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= '${SINCE}'
      AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= '${UNTIL}'
  " | python3 -c "import sys,json; d=json.load(sys.stdin)[0]; print(d.get('sessions',0), d.get('total_tokens',0), d.get('earliest',''), d.get('latest',''), d.get('model_count',0), d.get('agent_count',0))")
  echo "$json"
}

query_models() {
  query "
    SELECT
      COALESCE(json_extract(model, '$.id'), 'unknown') as model,
      COUNT(*) as sessions,
      SUM(tokens_input) as input,
      SUM(tokens_output) as output,
      SUM(tokens_reasoning) as reasoning,
      SUM(tokens_input + tokens_output + tokens_reasoning) as total
    FROM session
    WHERE directory LIKE '%CollageMaker%'
      AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= '${SINCE}'
      AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= '${UNTIL}'
    GROUP BY model
    ORDER BY total DESC
    LIMIT 15
  "
}

query_agents() {
  query "
    SELECT
      COALESCE(agent, 'unknown') as agent,
      COUNT(*) as sessions,
      SUM(tokens_input + tokens_output + tokens_reasoning) as total
    FROM session
    WHERE directory LIKE '%CollageMaker%'
      AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= '${SINCE}'
      AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= '${UNTIL}'
    GROUP BY agent
    ORDER BY total DESC
    LIMIT 15
  "
}

query_timeseries() {
  query "
    SELECT
      strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') as day,
      SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens,
      COUNT(*) as sessions,
      COALESCE(SUM(tokens_input), 0) as input_tokens,
      COALESCE(SUM(tokens_output), 0) as output_tokens,
      COALESCE(SUM(tokens_reasoning), 0) as reasoning_tokens
    FROM session
    WHERE directory LIKE '%CollageMaker%'
      AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= '${SINCE}'
      AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= '${UNTIL}'
    GROUP BY day
    ORDER BY day
  "
}

query_top_sessions() {
  query "
    SELECT
      title,
      agent,
      json_extract(model, '$.id') as model,
      tokens_input + tokens_output + tokens_reasoning as total_tokens
    FROM session
    WHERE directory LIKE '%CollageMaker%'
      AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= '${SINCE}'
      AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= '${UNTIL}'
    ORDER BY total_tokens DESC
    LIMIT 15
  "
}

query_model_agent() {
  query "
    SELECT
      COALESCE(json_extract(model, '$.id'), 'unknown') as model,
      COALESCE(agent, 'unknown') as agent,
      COUNT(*) as sessions,
      SUM(tokens_input + tokens_output + tokens_reasoning) as total
    FROM session
    WHERE directory LIKE '%CollageMaker%'
      AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= '${SINCE}'
      AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= '${UNTIL}'
    GROUP BY model, agent
    ORDER BY total DESC
    LIMIT 30
  "
}

extract_git_stats() {
  # Extract per-day commit counts and line changes from git log.
  # Output format: DATE COMMITS ADDITIONS DELETIONS (one line per day, sorted ascending)
  git log --reverse --date=short --pretty=format:'%ad' --numstat 2>/dev/null | awk '
    /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/ {
      date = $0
      if (!(date in commits)) order[++n] = date
      commits[date]++
      next
    }
    /^[0-9]+\t[0-9]+/ && date != "" {
      additions[date] += $1
      deletions[date] += $2
    }
    END {
      for (i = 1; i <= n; i++) {
        d = order[i]
        printf "%s %d %d %d\n", d, commits[d], additions[d]+0, deletions[d]+0
      }
    }
  ' || true
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
  echo "Generating CollageMaker LLM usage report..." >&2
  echo "  Period: ${SINCE} to ${UNTIL}" >&2
  echo "  Output: ${OUTPUT}" >&2
  
  # Gather all data as JSON strings
  local summary_line models_json agents_json timeseries_json top_sessions_json cross_tab_json git_stats_json
  local gen_ts
  
  summary_line=$(read_summary)
  models_json=$(query_models)
  agents_json=$(query_agents)
  timeseries_json=$(query_timeseries)
  top_sessions_json=$(query_top_sessions)
  cross_tab_json=$(query_model_agent)
  git_stats_json=$(extract_git_stats || echo "")
  
  gen_ts=$(date '+%Y-%m-%d %H:%M %Z')
  
  # Build combined JSON to temp file (reused for initial render and --activity re-render)
  local TEMP_DATA="${OUTPUT%.html}.tmp.json"
  python3 -c "
import sys, json

# Parse summary line: sessions total_tokens earliest latest model_count agent_count
summary_parts = sys.argv[1].split()
sessions = int(summary_parts[0]) if len(summary_parts) > 0 else 0
total_tokens = int(summary_parts[1]) if len(summary_parts) > 1 else 0
earliest = summary_parts[2] if len(summary_parts) > 2 else ''
latest = summary_parts[3] if len(summary_parts) > 3 else ''
model_count = int(summary_parts[4]) if len(summary_parts) > 4 else 0
agent_count = int(summary_parts[5]) if len(summary_parts) > 5 else 0

# Parse JSON arrays from stdin (passed as separate args for safety)
models_data = json.loads(sys.argv[2]) if sys.argv[2] else []
agents_data = json.loads(sys.argv[3]) if sys.argv[3] else []
timeseries_data = json.loads(sys.argv[4]) if sys.argv[4] else []
top_sessions_data = json.loads(sys.argv[5]) if sys.argv[5] else []
cross_tab_data = json.loads(sys.argv[6]) if sys.argv[6] else []

# Parse git stats (space-delimited: DATE COMMITS ADDS DELS per line)
git_map = {}
if sys.argv[7]:
    for line in sys.argv[7].strip().split('\n'):
        parts = line.split()
        if len(parts) >= 4 and parts[0].count('-') == 2:
            date, commits, adds, dels = parts[0], int(parts[1]), int(parts[2]), int(parts[3])
            # Filter by report period
            if earliest <= date <= latest:
                git_map[date] = (commits, adds, dels)

# Build token_map from timeseries data
token_map = {}
for row in timeseries_data:
    token_map[row['day']] = {
        'total_tokens': row.get('total_tokens', 0) or 0,
        'sessions': row.get('sessions', 0) or 0,
        'input_tokens': row.get('input_tokens', 0) or 0,
        'output_tokens': row.get('output_tokens', 0) or 0,
        'reasoning_tokens': row.get('reasoning_tokens', 0) or 0
    }

# Build output structure for render_report.py
output = {
    'title': 'CollageMaker — LLM Usage Report',
    'since': earliest,
    'until': latest,
    'generated': sys.argv[8],
    'totals': {
        'tokens': {
            'total': total_tokens,
            'input': sum(d.get('input_tokens', 0) for d in token_map.values()),
            'output': sum(d.get('output_tokens', 0) for d in token_map.values()),
            'reasoning': sum(d.get('reasoning_tokens', 0) for d in token_map.values())
        },
        'sessions': sessions,
        'model_count': model_count,
        'agent_count': agent_count
    },
    'models': models_data,
    'agents': agents_data,
    'timeseries': timeseries_data,
    'top_sessions': top_sessions_data,
    'cross_tab': cross_tab_data,
    'token_map': token_map,
    'git_map': git_map,
    'daily_activity_link': ''  # Will be filled by caller if --activity is used
}

print(json.dumps(output))
" "$summary_line" \
  "${models_json:-[]}" \
  "${agents_json:-[]}" \
  "${timeseries_json:-[]}" \
  "${top_sessions_json:-[]}" \
  "${cross_tab_json:-[]}" \
  "${git_stats_json:-}" \
  "$gen_ts" > "$TEMP_DATA"
  
  # Render HTML from combined JSON
  python3 "$(dirname "$0")/render_report.py" < "$TEMP_DATA" > "$OUTPUT"
  
  echo "Report generated: ${OUTPUT} ($(wc -c < "$OUTPUT") bytes)" >&2
  
  # Optional: Generate daily data and re-render HTML with activity link
  if [[ "$ACTIVITY" == true ]]; then
    local session_dir="${REPORT_DIR}/../sessions"
    
    # Extract token-only JSON for collect_daily_data.py (filter out non-daily fields)
    python3 -c "
import sys, json

data = json.load(sys.stdin)
# Keep only fields needed by collect_daily_data.py
output = {k: v for k, v in data.items() if k in ('token_map', 'git_map', 'since', 'until')}
print(json.dumps(output))
" < "$TEMP_DATA" | python3 "$(dirname "$0")/collect_daily_data.py" --session-dir "$session_dir" > "${OUTPUT%.html}-daily-data.json"
    
    echo "Daily data generated: ${OUTPUT%.html}-daily-data.json" >&2
    
    # Re-render HTML with link to daily-data.json (activity summary is generated separately by agent)
    local activity_link="<a href=\"$(basename "${OUTPUT%.html}-daily-data.json")\">View Daily Activity Data</a>"
    
    python3 -c "
import sys, json

data = json.load(sys.stdin)
data['daily_activity_link'] = '''$activity_link'''
print(json.dumps(data))
" < "$TEMP_DATA" | python3 "$(dirname "$0")/render_report.py" > "${OUTPUT}.tmp" && mv "${OUTPUT}.tmp" "$OUTPUT"
    
    echo "Report re-rendered with daily activity link: ${OUTPUT}" >&2
  fi
  
  # Cleanup temp file
  rm -f "$TEMP_DATA" "${OUTPUT%.html}.tmp.json"
}

main "$@"
