#!/usr/bin/env bash
# opencode-analytics.sh — Query opencode's SQLite database for usage analytics.
# Usage: ./script/opencode-analytics.sh [OPTIONS]
#
# Options:
#   --project <pattern>   Filter by directory (substring match, may use %)
#   --since <YYYY-MM-DD>  Start date (inclusive)
#   --until <YYYY-MM-DD>  End date (inclusive, defaults to today)
#   --days <N>            Last N days (overrides --since)
#   --week                Last 7 days
#   --month               Last 30 days
#   --all                 All-time (no date filter)
#   --models              Token usage by model
#   --agents              Token usage by agent
#   --model-agents        Token usage by model + agent cross-tab
#   --timeseries          Daily token trend
#   --weekly              Weekly token trend
#   --monthly             Monthly token trend
#   --projects            Token usage by project/directory
#   --top-sessions <N>    Top N sessions by token count (default 20)
#   --impact              Sessions with file changes
#   --summary             High-level overview (default if no flags given)
#   --json                Output raw JSON instead of formatted text
#   --help                Show this help

set -euo pipefail

# ── Helpers ──────────────────────────────────────────────────────────────────

DB_CMD="opencode db"
FORMAT_FLAG="--format json"

# Run a query and return JSON
query() {
  $DB_CMD "$1" $FORMAT_FLAG
}

# Format a number with commas
fmt_num() {
  local n="$1"
  local result=""
  local digits="${n#-}"
  local sign=""
  if [[ "$n" == -* ]]; then sign="-"; fi
  while (( ${#digits} > 3 )); do
    local len=${#digits}
    result=",${digits:$((len-3))}$result"
    digits="${digits:0:$((len-3))}"
  done
  echo "${sign}${digits}${result}"
}

# Format tokens in human-readable form
fmt_tokens() {
  local n="$1"
  if (( n >= 1000000000 )); then
    echo "$(echo "scale=1; $n / 1000000000" | bc)B"
  elif (( n >= 1000000 )); then
    echo "$(echo "scale=1; $n / 1000000" | bc)M"
  elif (( n >= 1000 )); then
    echo "$(echo "scale=1; $n / 1000" | bc)K"
  else
    echo "$n"
  fi
}

# Print a section header
section() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $1"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ── Argument Parsing ─────────────────────────────────────────────────────────

PROJECT_FILTER=""
SINCE=""
UNTIL=""
SHOW_MODELS=false
SHOW_AGENTS=false
SHOW_MODEL_AGENTS=false
SHOW_TIMESERIES=false
SHOW_WEEKLY=false
SHOW_MONTHLY=false
SHOW_PROJECTS=false
SHOW_TOP_SESSIONS=false
TOP_N=20
SHOW_IMPACT=false
JSON_OUTPUT=false

# Track if any section flag was explicitly set
ANY_SECTION=false
EXPLICIT_SUMMARY=false

while (( $# > 0 )); do
  case "$1" in
    --project)
      PROJECT_FILTER="$2"
      shift 2
      ;;
    --since)
      SINCE="$2"
      shift 2
      ;;
    --until)
      UNTIL="$2"
      shift 2
      ;;
    --days)
      DAYS="$2"
      SINCE=$(date -v-${DAYS}d +%Y-%m-%d 2>/dev/null || date -d "-${DAYS} days" +%Y-%m-%d)
      shift 2
      ;;
    --week)
      SINCE=$(date -v-7d +%Y-%m-%d 2>/dev/null || date -d "-7 days" +%Y-%m-%d)
      shift
      ;;
    --month)
      SINCE=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d "-30 days" +%Y-%m-%d)
      shift
      ;;
    --all)
      shift
      ;;
    --models)
      SHOW_MODELS=true
      ANY_SECTION=true
      shift
      ;;
    --agents)
      SHOW_AGENTS=true
      ANY_SECTION=true
      shift
      ;;
    --model-agents)
      SHOW_MODEL_AGENTS=true
      ANY_SECTION=true
      shift
      ;;
    --timeseries)
      SHOW_TIMESERIES=true
      ANY_SECTION=true
      shift
      ;;
    --weekly)
      SHOW_WEEKLY=true
      ANY_SECTION=true
      shift
      ;;
    --monthly)
      SHOW_MONTHLY=true
      ANY_SECTION=true
      shift
      ;;
    --projects)
      SHOW_PROJECTS=true
      ANY_SECTION=true
      shift
      ;;
    --top-sessions)
      SHOW_TOP_SESSIONS=true
      ANY_SECTION=true
      if [[ -n "${2:-}" && "${2:-}" != --* ]]; then
        TOP_N="$2"
        shift 2
      else
        shift
      fi
      ;;
    --impact)
      SHOW_IMPACT=true
      ANY_SECTION=true
      shift
      ;;
    --summary)
      EXPLICIT_SUMMARY=true
      shift
      ;;
    --json)
      JSON_OUTPUT=true
      shift
      ;;
    --help)
      echo "opencode-analytics.sh — Query opencode's SQLite database for usage analytics."
      echo ""
      echo "Usage: ./script/opencode-analytics.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --project <pattern>   Filter by directory (substring match, may use %)"
      echo "  --since <YYYY-MM-DD>  Start date (inclusive)"
      echo "  --until <YYYY-MM-DD>  End date (inclusive, defaults to today)"
      echo "  --days <N>            Last N days (overrides --since)"
      echo "  --week                Last 7 days"
      echo "  --month               Last 30 days"
      echo "  --all                 All-time (no date filter)"
      echo "  --models              Token usage by model"
      echo "  --agents              Token usage by agent"
      echo "  --model-agents        Token usage by model + agent cross-tab"
      echo "  --timeseries          Daily token trend"
      echo "  --weekly              Weekly token trend"
      echo "  --monthly             Monthly token trend"
      echo "  --projects            Token usage by project/directory"
      echo "  --top-sessions <N>    Top N sessions by token count (default 20)"
      echo "  --impact              Sessions with file changes"
      echo "  --summary             High-level overview (default if no flags given)"
      echo "  --json                Output raw JSON instead of formatted text"
      echo "  --help                Show this help"
      echo ""
      echo "Examples:"
      echo "  ./script/opencode-analytics.sh                           # all-time summary"
      echo "  ./script/opencode-analytics.sh --week --models           # last 7 days by model"
      echo "  ./script/opencode-analytics.sh --project CollageMaker    # CollageMaker only"
      echo "  ./script/opencode-analytics.sh --summary --models --json # JSON output"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# Default: show summary if no section flags were given
SHOW_SUMMARY=$EXPLICIT_SUMMARY
if ! $ANY_SECTION && ! $EXPLICIT_SUMMARY; then
  SHOW_SUMMARY=true
fi

# ── Build WHERE clause ───────────────────────────────────────────────────────

# Base WHERE conditions from filters
BASE_WHERE=""
if [[ -n "$PROJECT_FILTER" ]]; then
  BASE_WHERE="directory LIKE '%$PROJECT_FILTER%'"
fi
if [[ -n "$SINCE" ]]; then
  BASE_WHERE="${BASE_WHERE:+$BASE_WHERE AND }strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= '$SINCE'"
fi
if [[ -n "$UNTIL" ]]; then
  BASE_WHERE="${BASE_WHERE:+$BASE_WHERE AND }strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= '$UNTIL'"
fi

# Build a WHERE clause, optionally adding an extra condition
build_where() {
  local extra="${1:-}"
  local parts=()
  if [[ -n "$BASE_WHERE" ]]; then
    parts+=("$BASE_WHERE")
  fi
  if [[ -n "$extra" ]]; then
    parts+=("$extra")
  fi
  if (( ${#parts[@]} > 0 )); then
    local joined="${parts[0]}"
    for (( i=1; i<${#parts[@]}; i++ )); do
      joined="$joined AND ${parts[$i]}"
    done
    echo "WHERE $joined"
  fi
}

WHERE=$(build_where "")

WHERE=$(build_where)

# ── JSON Output Mode ─────────────────────────────────────────────────────────

if $JSON_OUTPUT; then
  # Collect all requested data into a single JSON object
  collect_json() {
    local result="{"

    if $SHOW_SUMMARY; then
      local summary
      summary=$(query "
        SELECT
          COUNT(*) as sessions,
          SUM(tokens_input) as total_input,
          SUM(tokens_output) as total_output,
          SUM(tokens_reasoning) as total_reasoning,
          SUM(tokens_cache_read) as cache_read,
          SUM(tokens_cache_write) as cache_write,
          SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens,
          ROUND(AVG(tokens_input + tokens_output + tokens_reasoning)) as avg_per_session,
          COUNT(DISTINCT directory) as projects,
          COUNT(DISTINCT json_extract(model, '\$.id')) as models,
          COUNT(DISTINCT agent) as agents,
          MIN(strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')) as earliest,
          MAX(strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')) as latest
        FROM session $WHERE
      ")
      result="$result \"summary\": $summary,"
    fi

    if $SHOW_MODELS; then
      local models
      models=$(query "
        SELECT
          json_extract(model, '\$.id') as model,
          COUNT(*) as sessions,
          SUM(tokens_input) as input,
          SUM(tokens_output) as output,
          SUM(tokens_reasoning) as reasoning,
          SUM(tokens_input + tokens_output + tokens_reasoning) as total,
          ROUND(AVG(tokens_input + tokens_output + tokens_reasoning)) as avg_per_session
        FROM session $WHERE
        GROUP BY json_extract(model, '\$.id')
        ORDER BY total DESC
      ")
      result="$result \"models\": $models,"
    fi

    if $SHOW_AGENTS; then
      local agents
      agents=$(query "
        SELECT
          agent,
          COUNT(*) as sessions,
          SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens,
          ROUND(AVG(tokens_input + tokens_output + tokens_reasoning)) as avg_per_session
        FROM session $WHERE
        GROUP BY agent
        ORDER BY total_tokens DESC
      ")
      result="$result \"agents\": $agents,"
    fi

    if $SHOW_MODEL_AGENTS; then
      local model_agents
      model_agents=$(query "
        SELECT
          json_extract(model, '\$.id') as model,
          agent,
          COUNT(*) as sessions,
          SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens,
          ROUND(AVG(tokens_input + tokens_output + tokens_reasoning)) as avg_per_session
        FROM session $WHERE
        GROUP BY json_extract(model, '\$.id'), agent
        ORDER BY total_tokens DESC
      ")
      result="$result \"model_agents\": $model_agents,"
    fi

    if $SHOW_TIMESERIES; then
      local ts
      ts=$(query "
        SELECT
          strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') as day,
          COUNT(*) as sessions,
          SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens
        FROM session $WHERE
        GROUP BY day
        ORDER BY day
      ")
      result="$result \"timeseries\": $ts,"
    fi

    if $SHOW_WEEKLY; then
      local weekly
      weekly=$(query "
        SELECT
          strftime('%Y-W%W', time_created / 1000, 'unixepoch') as week,
          COUNT(*) as sessions,
          SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens
        FROM session $WHERE
        GROUP BY week
        ORDER BY week
      ")
      result="$result \"weekly\": $weekly,"
    fi

    if $SHOW_MONTHLY; then
      local monthly
      monthly=$(query "
        SELECT
          strftime('%Y-%m', time_created / 1000, 'unixepoch') as month,
          COUNT(*) as sessions,
          SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens
        FROM session $WHERE
        GROUP BY month
        ORDER BY month
      ")
      result="$result \"monthly\": $monthly,"
    fi

    if $SHOW_PROJECTS; then
      local projects
      projects=$(query "
        SELECT
          directory,
          COUNT(*) as sessions,
          SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens,
          ROUND(AVG(tokens_input + tokens_output + tokens_reasoning)) as avg_tokens,
          COUNT(DISTINCT json_extract(model, '\$.id')) as models_used
        FROM session $WHERE
        GROUP BY directory
        ORDER BY total_tokens DESC
      ")
      result="$result \"projects\": $projects,"
    fi

    if $SHOW_TOP_SESSIONS; then
      local top
      top=$(query "
        SELECT
          id,
          title,
          directory,
          agent,
          json_extract(model, '\$.id') as model,
          tokens_input,
          tokens_output,
          tokens_reasoning,
          tokens_input + tokens_output + tokens_reasoning as total,
          summary_files,
          summary_additions,
          summary_deletions,
          strftime('%Y-%m-%d %H:%M', time_created / 1000, 'unixepoch') as created
        FROM session $WHERE
        ORDER BY total DESC
        LIMIT $TOP_N
      ")
      result="$result \"top_sessions\": $top,"
    fi

    if $SHOW_IMPACT; then
      local impact
      impact=$(query "
        SELECT
          directory,
          agent,
          COUNT(*) as sessions_with_changes,
          SUM(summary_files) as total_files,
          SUM(summary_additions) as total_additions,
          SUM(summary_deletions) as total_deletions
        FROM session $(build_where "summary_files > 0")
        GROUP BY directory, agent
        ORDER BY total_files DESC
      ")
      result="$result \"impact\": $impact,"
    fi

    # Remove trailing comma and close
    result="${result%,}}"
    echo "$result" | jq .
  }

  collect_json
  exit 0
fi

# ── Formatted Text Output ────────────────────────────────────────────────────

print_filter() {
  local filters=()
  [[ -n "$PROJECT_FILTER" ]] && filters+=("project: $PROJECT_FILTER")
  [[ -n "$SINCE" ]] && filters+=("since: $SINCE")
  [[ -n "$UNTIL" ]] && filters+=("until: $UNTIL")
  if (( ${#filters[@]} > 0 )); then
    echo "  Filter: $(IFS=', '; echo "${filters[*]}")"
  fi
}

# ── Summary ──────────────────────────────────────────────────────────────────

if $SHOW_SUMMARY; then
  section "opencode Usage Summary"
  print_filter

  local_data=$(query "
    SELECT
      COUNT(*) as sessions,
      COALESCE(SUM(tokens_input), 0) as total_input,
      COALESCE(SUM(tokens_output), 0) as total_output,
      COALESCE(SUM(tokens_reasoning), 0) as total_reasoning,
      COALESCE(SUM(tokens_cache_read), 0) as cache_read,
      COALESCE(SUM(tokens_cache_write), 0) as cache_write,
      COALESCE(SUM(tokens_input + tokens_output + tokens_reasoning), 0) as total_tokens,
      COALESCE(ROUND(AVG(tokens_input + tokens_output + tokens_reasoning)), 0) as avg_per_session,
      COUNT(DISTINCT directory) as projects,
      COUNT(DISTINCT json_extract(model, '\$.id')) as models,
      COUNT(DISTINCT agent) as agents,
      MIN(strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')) as earliest,
      MAX(strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')) as latest
    FROM session $WHERE
  ")

  echo ""
  echo "  Sessions:          $(fmt_num "$(echo "$local_data" | jq -r '.[0].sessions')")"
  echo "  Projects:          $(echo "$local_data" | jq -r '.[0].projects')"
  echo "  Models:            $(echo "$local_data" | jq -r '.[0].models')"
  echo "  Agents:            $(echo "$local_data" | jq -r '.[0].agents')"
  echo "  Date range:        $(echo "$local_data" | jq -r '.[0].earliest') → $(echo "$local_data" | jq -r '.[0].latest')"
  echo ""
  echo "  Tokens:"
  echo "    Input:           $(fmt_num "$(echo "$local_data" | jq -r '.[0].total_input')") ($(fmt_tokens "$(echo "$local_data" | jq -r '.[0].total_input')"))"
  echo "    Output:          $(fmt_num "$(echo "$local_data" | jq -r '.[0].total_output')") ($(fmt_tokens "$(echo "$local_data" | jq -r '.[0].total_output')"))"
  echo "    Reasoning:       $(fmt_num "$(echo "$local_data" | jq -r '.[0].total_reasoning')") ($(fmt_tokens "$(echo "$local_data" | jq -r '.[0].total_reasoning')"))"
  echo "    Cache read:      $(fmt_num "$(echo "$local_data" | jq -r '.[0].cache_read')") ($(fmt_tokens "$(echo "$local_data" | jq -r '.[0].cache_read')"))"
  echo "    Cache write:     $(fmt_num "$(echo "$local_data" | jq -r '.[0].cache_write')") ($(fmt_tokens "$(echo "$local_data" | jq -r '.[0].cache_write')"))"
  echo "    Total:           $(fmt_num "$(echo "$local_data" | jq -r '.[0].total_tokens')") ($(fmt_tokens "$(echo "$local_data" | jq -r '.[0].total_tokens')"))"
  echo "  Avg per session:   $(fmt_num "$(echo "$local_data" | jq -r '.[0].avg_per_session')") ($(fmt_tokens "$(echo "$local_data" | jq -r '.[0].avg_per_session')"))"
fi

# ── Models ───────────────────────────────────────────────────────────────────

if $SHOW_MODELS; then
  section "Token Usage by Model"
  print_filter

  local_data=$(query "
    SELECT
      json_extract(model, '\$.id') as model,
      COUNT(*) as sessions,
      SUM(tokens_input) as input,
      SUM(tokens_output) as output,
      SUM(tokens_reasoning) as reasoning,
      SUM(tokens_input + tokens_output + tokens_reasoning) as total,
      ROUND(AVG(tokens_input + tokens_output + tokens_reasoning)) as avg_per_session
    FROM session $WHERE
    GROUP BY json_extract(model, '\$.id')
    ORDER BY total DESC
  ")

  echo ""
  printf "  %-35s %6s %12s %12s %12s %12s\n" "Model" "Sess" "Input" "Output" "Reason" "Total"
  echo "  ─────────────────────────────────────────────────────────────────────────────────────────────────────"

  echo "$local_data" | jq -c '.[]' | while read -r row; do
    model=$(echo "$row" | jq -r '.model')
    sessions=$(echo "$row" | jq -r '.sessions')
    input=$(echo "$row" | jq -r '.input')
    output=$(echo "$row" | jq -r '.output')
    reasoning=$(echo "$row" | jq -r '.reasoning')
    total=$(echo "$row" | jq -r '.total')
    printf "  %-35s %6s %12s %12s %12s %12s\n" \
      "$model" "$sessions" \
      "$(fmt_tokens "$input")" "$(fmt_tokens "$output")" "$(fmt_tokens "$reasoning")" "$(fmt_tokens "$total")"
  done
fi

# ── Agents ───────────────────────────────────────────────────────────────────

if $SHOW_AGENTS; then
  section "Token Usage by Agent"
  print_filter

  local_data=$(query "
    SELECT
      COALESCE(agent, '(none)') as agent,
      COUNT(*) as sessions,
      SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens,
      ROUND(AVG(tokens_input + tokens_output + tokens_reasoning)) as avg_per_session
    FROM session $WHERE
    GROUP BY agent
    ORDER BY total_tokens DESC
  ")

  echo ""
  printf "  %-25s %6s %14s %14s\n" "Agent" "Sess" "Total" "Avg/Session"
  echo "  ───────────────────────────────────────────────────────────────"

  echo "$local_data" | jq -c '.[]' | while read -r row; do
    agent=$(echo "$row" | jq -r '.agent')
    sessions=$(echo "$row" | jq -r '.sessions')
    total=$(echo "$row" | jq -r '.total_tokens')
    avg=$(echo "$row" | jq -r '.avg_per_session')
    printf "  %-25s %6s %14s %14s\n" \
      "$agent" "$sessions" "$(fmt_tokens "$total")" "$(fmt_tokens "$avg")"
  done
fi

# ── Model × Agent Cross-Tab ──────────────────────────────────────────────────

if $SHOW_MODEL_AGENTS; then
  section "Model × Agent Breakdown"
  print_filter

  local_data=$(query "
    SELECT
      json_extract(model, '\$.id') as model,
      COALESCE(agent, '(none)') as agent,
      COUNT(*) as sessions,
      SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens,
      ROUND(AVG(tokens_input + tokens_output + tokens_reasoning)) as avg_per_session
    FROM session $WHERE
    GROUP BY json_extract(model, '\$.id'), agent
    ORDER BY total_tokens DESC
    LIMIT 30
  ")

  echo ""
  printf "  %-30s %-20s %5s %14s %14s\n" "Model" "Agent" "Sess" "Total" "Avg/Session"
  echo "  ───────────────────────────────────────────────────────────────────────────────"

  echo "$local_data" | jq -c '.[]' | while read -r row; do
    model=$(echo "$row" | jq -r '.model')
    agent=$(echo "$row" | jq -r '.agent')
    sessions=$(echo "$row" | jq -r '.sessions')
    total=$(echo "$row" | jq -r '.total_tokens')
    avg=$(echo "$row" | jq -r '.avg_per_session')
    printf "  %-30s %-20s %5s %14s %14s\n" \
      "$model" "$agent" "$sessions" "$(fmt_tokens "$total")" "$(fmt_tokens "$avg")"
  done
fi

# ── Timeseries ───────────────────────────────────────────────────────────────

if $SHOW_TIMESERIES; then
  section "Daily Token Trend"
  print_filter

  local_data=$(query "
    SELECT
      strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') as day,
      COUNT(*) as sessions,
      SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens
    FROM session $WHERE
    GROUP BY day
    ORDER BY day
  ")

  echo ""
  printf "  %-12s %6s %14s\n" "Date" "Sess" "Tokens"
  echo "  ─────────────────────────────────────"

  echo "$local_data" | jq -c '.[]' | while read -r row; do
    day=$(echo "$row" | jq -r '.day')
    sessions=$(echo "$row" | jq -r '.sessions')
    total=$(echo "$row" | jq -r '.total_tokens')
    printf "  %-12s %6s %14s\n" "$day" "$sessions" "$(fmt_tokens "$total")"
  done
fi

# ── Weekly Trend ─────────────────────────────────────────────────────────────

if $SHOW_WEEKLY; then
  section "Weekly Token Trend"
  print_filter

  local_data=$(query "
    SELECT
      strftime('%Y-W%W', time_created / 1000, 'unixepoch') as week,
      COUNT(*) as sessions,
      SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens
    FROM session $WHERE
    GROUP BY week
    ORDER BY week
  ")

  echo ""
  printf "  %-10s %6s %14s\n" "Week" "Sess" "Tokens"
  echo "  ─────────────────────────────────"

  echo "$local_data" | jq -c '.[]' | while read -r row; do
    week=$(echo "$row" | jq -r '.week')
    sessions=$(echo "$row" | jq -r '.sessions')
    total=$(echo "$row" | jq -r '.total_tokens')
    printf "  %-10s %6s %14s\n" "$week" "$sessions" "$(fmt_tokens "$total")"
  done
fi

# ── Monthly Trend ────────────────────────────────────────────────────────────

if $SHOW_MONTHLY; then
  section "Monthly Token Trend"
  print_filter

  local_data=$(query "
    SELECT
      strftime('%Y-%m', time_created / 1000, 'unixepoch') as month,
      COUNT(*) as sessions,
      SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens
    FROM session $WHERE
    GROUP BY month
    ORDER BY month
  ")

  echo ""
  printf "  %-8s %6s %14s\n" "Month" "Sess" "Tokens"
  echo "  ────────────────────────────────"

  echo "$local_data" | jq -c '.[]' | while read -r row; do
    month=$(echo "$row" | jq -r '.month')
    sessions=$(echo "$row" | jq -r '.sessions')
    total=$(echo "$row" | jq -r '.total_tokens')
    printf "  %-8s %6s %14s\n" "$month" "$sessions" "$(fmt_tokens "$total")"
  done
fi

# ── Projects ─────────────────────────────────────────────────────────────────

if $SHOW_PROJECTS; then
  section "Token Usage by Project"
  print_filter

  local_data=$(query "
    SELECT
      directory,
      COUNT(*) as sessions,
      SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens,
      ROUND(AVG(tokens_input + tokens_output + tokens_reasoning)) as avg_tokens,
      COUNT(DISTINCT json_extract(model, '\$.id')) as models_used
    FROM session $WHERE
    GROUP BY directory
    ORDER BY total_tokens DESC
  ")

  echo ""
  printf "  %-60s %5s %14s %14s %s\n" "Directory" "Sess" "Total" "Avg" "Models"
  echo "  ─────────────────────────────────────────────────────────────────────────────────────────"

  echo "$local_data" | jq -c '.[]' | while read -r row; do
    dir=$(echo "$row" | jq -r '.directory')
    sessions=$(echo "$row" | jq -r '.sessions')
    total=$(echo "$row" | jq -r '.total_tokens')
    avg=$(echo "$row" | jq -r '.avg_tokens')
    models=$(echo "$row" | jq -r '.models_used')
    # Truncate long directory paths
    if (( ${#dir} > 60 )); then
      dir="...${dir: -57}"
    fi
    printf "  %-60s %5s %14s %14s %s\n" \
      "$dir" "$sessions" "$(fmt_tokens "$total")" "$(fmt_tokens "$avg")" "$models"
  done
fi

# ── Top Sessions ─────────────────────────────────────────────────────────────

if $SHOW_TOP_SESSIONS; then
  section "Top $TOP_N Sessions by Token Usage"
  print_filter

  local_data=$(query "
    SELECT
      id,
      title,
      directory,
      COALESCE(agent, '(none)') as agent,
      json_extract(model, '\$.id') as model,
      tokens_input,
      tokens_output,
      tokens_reasoning,
      tokens_input + tokens_output + tokens_reasoning as total,
      COALESCE(summary_files, 0) as files,
      COALESCE(summary_additions, 0) as additions,
      COALESCE(summary_deletions, 0) as deletions,
      strftime('%Y-%m-%d %H:%M', time_created / 1000, 'unixepoch') as created
    FROM session $WHERE
    ORDER BY total DESC
    LIMIT $TOP_N
  ")

  echo ""
  printf "  %-12s %-30s %-15s %-35s %10s\n" "Date" "Agent" "Model" "Title" "Tokens"
  echo "  ───────────────────────────────────────────────────────────────────────────────────────────────────────"

  echo "$local_data" | jq -c '.[]' | while read -r row; do
    created=$(echo "$row" | jq -r '.created')
    agent=$(echo "$row" | jq -r '.agent')
    model=$(echo "$row" | jq -r '.model')
    title=$(echo "$row" | jq -r '.title')
    total=$(echo "$row" | jq -r '.total')
    # Truncate title
    if (( ${#title} > 30 )); then
      title="${title:0:27}..."
    fi
    # Truncate model
    if (( ${#model} > 35 )); then
      model="${model:0:32}..."
    fi
    printf "  %-12s %-30s %-15s %-35s %10s\n" \
      "$created" "$agent" "$model" "$title" "$(fmt_tokens "$total")"
  done
fi

# ── Impact ───────────────────────────────────────────────────────────────────

if $SHOW_IMPACT; then
  section "File Change Impact"
  print_filter

  local_data=$(query "
    SELECT
      directory,
      COALESCE(agent, '(none)') as agent,
      COUNT(*) as sessions_with_changes,
      SUM(summary_files) as total_files,
      SUM(summary_additions) as total_additions,
      SUM(summary_deletions) as total_deletions
    FROM session $(build_where "summary_files > 0")
    GROUP BY directory, agent
    ORDER BY total_files DESC
    LIMIT 20
  ")

  echo ""
  printf "  %-50s %-18s %5s %8s %10s %10s\n" "Directory" "Agent" "Sess" "Files" "Additions" "Deletions"
  echo "  ─────────────────────────────────────────────────────────────────────────────────────────────────"

  echo "$local_data" | jq -c '.[]' | while read -r row; do
    dir=$(echo "$row" | jq -r '.directory')
    agent=$(echo "$row" | jq -r '.agent')
    sessions=$(echo "$row" | jq -r '.sessions_with_changes')
    files=$(echo "$row" | jq -r '.total_files')
    additions=$(echo "$row" | jq -r '.total_additions')
    deletions=$(echo "$row" | jq -r '.total_deletions')
    if (( ${#dir} > 50 )); then
      dir="...${dir: -47}"
    fi
    printf "  %-50s %-18s %5s %8s %10s %10s\n" \
      "$dir" "$agent" "$sessions" "$(fmt_num "$files")" "$(fmt_num "$additions")" "$(fmt_num "$deletions")"
  done
fi

echo ""
