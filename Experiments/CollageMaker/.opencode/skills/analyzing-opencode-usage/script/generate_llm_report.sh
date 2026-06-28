#!/usr/bin/env bash
# generate_llm_report.sh — Generate an HTML LLM usage report for CollageMaker.
# Queries opencode's SQLite DB + git log, merges by date, emits a self-contained HTML file.
#
# Usage: ./generate_llm_report.sh [OPTIONS]
#   --since YYYY-MM-DD    Start date (inclusive)
#   --until YYYY-MM-DD    End date (inclusive, defaults to today)
#   --days N              Last N days (overrides --since; default 30)
#   --output PATH         Output file path (default: auto-generated in llm-usage/)

set -euo pipefail

# ── Defaults & Argument Parsing ──────────────────────────────────────────────

REPORT_DIR="$(cd "$(dirname "$0")/../../../../_agent_docs/project-timeline" && pwd)/llm-usage"
OUTPUT=""
SINCE=""
UNTIL=$(date +%Y-%m-%d)
DAYS=30

while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)  SINCE="$2"; shift 2 ;;
    --until)  UNTIL="$2"; shift 2 ;;
    --days)   DAYS="$2";  shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    *)        echo "Unknown option: $1" >&2; exit 1 ;;
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

# Summary: total tokens, sessions, date range, model/agent counts
read_summary() {
  local json
  json=$(query "
    SELECT
      COUNT(*) as sessions,
      SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens,
      MIN(strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')) as earliest,
      MAX(strftime('%Y-%m-%d', time_created / 1000, 'unixepoch')) as latest,
      COUNT(DISTINCT json_extract(model, '$.id')),
      COUNT(DISTINCT agent)
    FROM session
    WHERE directory LIKE '%CollageMaker%'
      AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= '${SINCE}'
      AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= '${UNTIL}'
  " | python3 -c "import sys,json; d=json.load(sys.stdin)[0]; print(d.get('sessions',0), d.get('total_tokens',0), d.get('earliest',''), d.get('latest',''), d.get('COUNT(DISTINCT json_extract(model, \\'$.id\\'))',0), d.get('COUNT(DISTINCT agent)',0))")
  echo "$json"
}

# Token usage by model (top N)
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

# Token usage by agent (top N)
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

# Daily token trend for timeseries chart
query_timeseries() {
  query "
    SELECT
      strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') as day,
      SUM(tokens_input + tokens_output + tokens_reasoning) as total_tokens,
      COUNT(*) as sessions
    FROM session
    WHERE directory LIKE '%CollageMaker%'
      AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= '${SINCE}'
      AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') <= '${UNTIL}'
    GROUP BY day
    ORDER BY day
  "
}

# Top sessions by token count
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

# Model × Agent cross-tabulation
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

# ── Git Stats Extraction ─────────────────────────────────────────────────────

extract_git_stats() {
  # Extract per-day commit counts and line changes from git log.
  # Output format: DATE COMMITS ADDITIONS DELETIONS (one line per day, sorted ascending)
  # Uses --reverse so dates come chronologically; no sort needed in awk.
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
  '
}

# ── SVG Chart Generation ─────────────────────────────────────────────────────

generate_svg_chart() {
  # Reads "DATE TOKENS" lines from stdin, outputs an inline <svg> element.
  local width="${1:-800}"
  local height="${2:-300}"
  local padding="${3:-50}"
  local chart_id="${4:-chart}"

  awk -v w="$width" -v h="$height" -v pad="$padding" -v cid="$chart_id" '
    BEGIN { n = 0; max_val = 1 }
    NF >= 2 {
      dates[n] = $1
      vals[n] = $2 + 0
      if (vals[n] > max_val) max_val = vals[n]
      n++
    }
    END {
      plot_w = w - 2 * pad
      plot_h = h - 2 * pad
      
      # Compute points string and tooltip data
      points = ""
      for (i = 0; i < n; i++) {
        x = pad + (n > 1 ? int(i * plot_w / (n - 1)) : plot_w / 2)
        y = h - pad - int(vals[i] * plot_h / max_val)
        points = points (i > 0 ? " " : "") x "," y
        
        # Store tooltip data
        tx[i] = x; ty[i] = y; td[i] = dates[i]; tv[i] = vals[i]
      }
      
      printf "<svg id=\"%s\" viewBox=\"0 0 %d %d\" xmlns=\"http://www.w3.org/2000/svg\" class=\"chart-svg\">\n", cid, w, h
      printf "  <defs>\n"
      printf "    <linearGradient id=\"grad-%s\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\">\n", cid
      printf "      <stop offset=\"0%%\" stop-color=\"#4fc3f7\" stop-opacity=\"0.3\"/>\n"
      printf "      <stop offset=\"100%%\" stop-color=\"#4fc3f7\" stop-opacity=\"0.02\"/>\n"
      printf "    </linearGradient>\n"
      printf "  </defs>\n"
      
      # Area fill under line
      if (n > 1) {
        printf "  <polygon points=\"%s %d,%d\" fill=\"url(#grad-%s)\"/>\n", points, pad, h - pad, cid
      }
      
      # Line
      printf "  <polyline points=\"%s\" fill=\"none\" stroke=\"#4fc3f7\" stroke-width=\"2\" stroke-linejoin=\"round\"/>\n", points
      
      # Data points (invisible hit targets + visible dots)
      for (i = 0; i < n; i++) {
        printf "  <circle cx=\"%d\" cy=\"%d\" r=\"4\" fill=\"#1a1a2e\" stroke=\"#4fc3f7\" stroke-width=\"2\" class=\"chart-point\" data-date=\"%s\" data-tokens=\"%d\"/>\n", tx[i], ty[i], td[i], tv[i]
      }
      
      # X-axis labels (show every Nth label to avoid crowding)
      step = int(n / 8)
      if (step < 1) step = 1
      for (i = 0; i < n; i += step) {
        x = pad + (n > 1 ? int(i * plot_w / (n - 1)) : plot_w / 2)
        printf "  <text x=\"%d\" y=\"%d\" text-anchor=\"middle\" fill=\"#8892a4\" font-size=\"10\" class=\"chart-label\">%s</text>\n", x, h - 10, td[i]
      }
      
      # Y-axis labels (min, max, midpoint)
      printf "  <text x=\"%d\" y=\"%d\" text-anchor=\"end\" fill=\"#8892a4\" font-size=\"10\">%s</text>\n", pad - 5, pad + 4, fmt_tokens_h(max_val)
      mid = int(max_val / 2)
      if (mid > 0) printf "  <text x=\"%d\" y=\"%d\" text-anchor=\"end\" fill=\"#8892a4\" font-size=\"10\">%s</text>\n", pad - 5, h - pad - int(plot_h / 2), fmt_tokens_h(mid)
      
      # Hover tooltip div (positioned via JS)
      printf "  <rect id=\"tooltip-%s\" x=\"0\" y=\"0\" width=\"160\" height=\"30\" rx=\"4\" fill=\"#16213e\" stroke=\"#4fc3f7\" stroke-width=\"1\" opacity=\"0\" pointer-events=\"none\"/>\n", cid
      printf "  <text id=\"tooltip-text-%s\" x=\"8\" y=\"19\" fill=\"#e0e0e0\" font-size=\"11\" opacity=\"0\" pointer-events=\"none\"></text>\n", cid
      
      printf "</svg>\n"
    }
    
    function fmt_tokens_h(v) {
      if (v >= 1000000000) return sprintf("%.1fB", v / 1000000000)
      if (v >= 1000000) return sprintf("%.1fM", v / 1000000)
      if (v >= 1000) return sprintf("%.1fK", v / 1000)
      return sprintf("%d", v)
    }
  '
}

# ── HTML Generation ──────────────────────────────────────────────────────────

generate_html() {
  local summary_line="$1"     # "sessions total_tokens earliest latest model_count agent_count"
  
  read -r sess tot_tok ear lat mod_cnt agt_cnt <<< "$summary_line"
  local avg_tok=0
  if (( sess > 0 )); then
    avg_tok=$((tot_tok / sess))
  fi
  
  local tot_tok_human avg_tok_human
  tot_tok_human=$(fmt_tokens "$tot_tok")
  avg_tok_human=$(fmt_tokens "$avg_tok")
  
  local gen_ts
  gen_ts=$(date '+%Y-%m-%d %H:%M %Z')
  
  cat <<'HTMLHEAD'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>CollageMaker — LLM Usage Report</title>
<style>
  :root {
    --bg: #1a1a2e; --card-bg: #16213e; --border: #0f3460;
    --text: #e0e0e0; --muted: #8892a4; --accent: #4fc3f7;
    --input-color: #4fc3f7; --output-color: #4db6ac; --reasoning-color: #ba68c8;
    --bar-bg: rgba(255,255,255,0.06);
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { background: var(--bg); color: var(--text); font-family: -apple-system, BlinkMacSystemFont, 'SF Mono', Menlo, monospace; line-height: 1.5; padding: 2rem; max-width: 1200px; margin: 0 auto; }
  
  h1 { font-size: 1.8rem; color: var(--accent); margin-bottom: 0.3rem; letter-spacing: -0.5px; }
  h2 { font-size: 1.2rem; color: var(--muted); margin-top: 2rem; margin-bottom: 1rem; padding-bottom: 0.4rem; border-bottom: 1px solid var(--border); }
  .subtitle { color: var(--muted); font-size: 0.85rem; margin-bottom: 2rem; }
  
  /* Metric cards */
  .metrics-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 1rem; margin-bottom: 2rem; }
  .metric-card { background: var(--card-bg); border: 1px solid var(--border); border-radius: 8px; padding: 1.2rem; text-align: center; }
  .metric-value { font-size: 1.6rem; font-weight: 700; color: var(--accent); letter-spacing: -1px; }
  .metric-label { font-size: 0.75rem; color: var(--muted); text-transform: uppercase; margin-top: 0.3rem; letter-spacing: 0.5px; }
  
  /* Stacked bars (model breakdown) */
  .bar-row { display: flex; align-items: center; margin-bottom: 0.6rem; gap: 0.8rem; }
  .bar-label { width: 220px; font-size: 0.8rem; color: var(--muted); text-align: right; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; flex-shrink: 0; }
  .bar-track { flex: 1; height: 24px; background: var(--bar-bg); border-radius: 4px; overflow: hidden; display: flex; position: relative; }
  .bar-segment { height: 100%; transition: opacity 0.2s; cursor: pointer; }
  .bar-segment:hover { opacity: 0.8; }
  .bar-value { font-size: 0.75rem; color: var(--muted); width: 90px; text-align: right; flex-shrink: 0; }
  
  /* Horizontal bars (agent usage) */
  .h-bar-row { display: flex; align-items: center; margin-bottom: 0.5rem; gap: 1rem; }
  .h-bar-label { width: 160px; font-size: 0.8rem; color: var(--muted); text-align: right; flex-shrink: 0; }
  .h-bar-track { flex: 1; height: 20px; background: var(--bar-bg); border-radius: 3px; overflow: hidden; position: relative; }
  .h-bar-fill { height: 100%; background: linear-gradient(90deg, #4fc3f7, #4db6ac); border-radius: 3px; transition: width 0.3s; }
  .h-bar-value { font-size: 0.75rem; color: var(--muted); width: 90px; text-align: right; flex-shrink: 0; }
  
  /* Tables */
  table { width: 100%; border-collapse: collapse; margin-bottom: 1.5rem; font-size: 0.82rem; }
  th { text-align: left; color: var(--muted); padding: 0.6rem 0.8rem; border-bottom: 1px solid var(--border); font-weight: 500; text-transform: uppercase; font-size: 0.7rem; letter-spacing: 0.5px; }
  td { padding: 0.5rem 0.8rem; border-bottom: 1px solid rgba(255,255,255,0.04); }
  tr:nth-child(even) td { background: rgba(255,255,255,0.02); }
  tr:hover td { background: rgba(79,195,247,0.06); }
  .num { text-align: right; font-variant-numeric: tabular-nums; }
  
  /* Chart */
  .chart-svg { width: 100%; height: auto; margin-bottom: 1rem; }
  .chart-point { cursor: crosshair; transition: r 0.15s; }
  .chart-point:hover { r: 6; }
  
  /* Legend */
  .legend { display: flex; gap: 1.5rem; margin-bottom: 1rem; flex-wrap: wrap; }
  .legend-item { display: flex; align-items: center; gap: 0.4rem; font-size: 0.78rem; color: var(--muted); }
  .legend-swatch { width: 12px; height: 12px; border-radius: 2px; }
  
  /* Code impact cards */
  .impact-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 1.5rem; }
  .impact-card { background: var(--card-bg); border: 1px solid var(--border); border-radius: 8px; padding: 1.2rem; text-align: center; }
  .impact-value { font-size: 1.8rem; font-weight: 700; color: #4db6ac; letter-spacing: -1px; }
  .impact-label { font-size: 0.72rem; color: var(--muted); text-transform: uppercase; margin-top: 0.3rem; letter-spacing: 0.5px; }
  .impact-card.ratio { border-color: #4db6ac; background: rgba(77, 182, 172, 0.06); }
  .impact-card.ratio .impact-value { color: #4db6ac; font-size: 2rem; }
  
  /* Footer */
  footer { margin-top: 3rem; padding-top: 1rem; border-top: 1px solid var(--border); font-size: 0.72rem; color: var(--muted); text-align: center; }
</style>
</head>
<body>

<h1>CollageMaker — LLM Usage Report</h1>
<p class="subtitle">Period: ${ear} to ${lat} &middot; Generated: ${gen_ts}</p>

HTMLHEAD

  # ── Summary Metrics ──────────────────────────────────────────────────────
  cat <<METRICSCARD
<div class="metrics-grid" id="summary">
  <div class="metric-card"><div class="metric-value" data-raw-tokens="${tot_tok}">${tot_tok_human}</div><div class="metric-label">Total Tokens</div></div>
  <div class="metric-card"><div class="metric-value">${sess}</div><div class="metric-label">Sessions</div></div>
  <div class="metric-card"><div class="metric-value">${avg_tok_human}</div><div class="metric-label">Avg / Session</div></div>
  <div class="metric-card"><div class="metric-value">${mod_cnt}</div><div class="metric-label">Models Used</div></div>
  <div class="metric-card"><div class="metric-value">${agt_cnt}</div><div class="metric-label">Agent Roles</div></div>
</div>
METRICSCARD

  # ── Token Usage by Model ────────────────────────────────────────────────
  echo '<h2 id="models">Token Usage by Model</h2>'
  
  cat <<LEGEND
<div class="legend">
  <div class="legend-item"><div class="legend-swatch" style="background:#4fc3f7"></div>Input</div>
  <div class="legend-item"><div class="legend-swatch" style="background:#4db6ac"></div>Output</div>
  <div class="legend-item"><div class="legend-swatch" style="background:#ba68c8"></div>Reasoning</div>
</div>
LEGEND

  # Parse models JSON and render stacked bars
  local models_json
  models_json=$(query_models)
  
  python3 -c "
import json, sys

def fmt(v):
    if v >= 1e9: return f'{v/1e9:.1f}B'
    if v >= 1e6: return f'{v/1e6:.1f}M'
    if v >= 1e3: return f'{v/1e3:.1f}K'
    return f'{v:,}'

data = json.load(sys.stdin)
if not data:
    print('<p style=\"color:#8892a4\">No model data in this period.</p>')
    sys.exit(0)

total_all = sum(d['total'] for d in data)
max_model_total = max(d['total'] for d in data) if data else 1

for d in data:
    name = d.get('model', 'unknown') or 'unknown'
    inp = d.get('input', 0) or 0
    out = d.get('output', 0) or 0
    rea = d.get('reasoning', 0) or 0
    tot = d.get('total', 0) or 0
    
    inp_pct = (inp / total_all * 100) if total_all else 0
    out_pct = (out / total_all * 100) if total_all else 0
    rea_pct = (rea / total_all * 100) if total_all else 0
    
    bar_width = (tot / max_model_total * 100) if max_model_total else 0
    
    print(f'<div class=\"bar-row\">')
    print(f'  <span class=\"bar-label\" title=\"{name}\">{name}</span>')
    print(f'  <div class=\"bar-track\" style=\"width:{max(bar_width, 5)}%\">')
    if inp > 0: print(f'    <div class=\"bar-segment\" style=\"width:{inp_pct}%;background:#4fc3f7;\" title=\"Input: {fmt(inp)}\"></div>')
    if out > 0: print(f'    <div class=\"bar-segment\" style=\"width:{out_pct}%;background:#4db6ac;\" title=\"Output: {fmt(out)}\"></div>')
    if rea > 0: print(f'    <div class=\"bar-segment\" style=\"width:{rea_pct}%;background:#ba68c8;\" title=\"Reasoning: {fmt(rea)}\"></div>')
    print(f'  </div>')
    print(f'  <span class=\"bar-value\">{fmt(tot)}</span>')
    print(f'</div>')
" <<< "$models_json"

  # ── Token Usage by Agent ────────────────────────────────────────────────
  echo '<h2 id="agents">Token Usage by Agent</h2>'
  
  local agents_json
  agents_json=$(query_agents)
  
  python3 -c "
import json, sys

def fmt(v):
    if v >= 1e9: return f'{v/1e9:.1f}B'
    if v >= 1e6: return f'{v/1e6:.1f}M'
    if v >= 1e3: return f'{v/1e3:.1f}K'
    return f'{v:,}'

data = json.load(sys.stdin)
if not data:
    print('<p style=\"color:#8892a4\">No agent data in this period.</p>')
    sys.exit(0)

max_total = max(d['total'] for d in data) if data else 1

for d in data:
    name = (d.get('agent') or 'unknown').replace('_', '-').replace('-', '-')
    tot = d.get('total', 0) or 0
    sess = d.get('sessions', 0) or 0
    width_pct = (tot / max_total * 100) if max_total else 0
    
    print(f'<div class=\"h-bar-row\">')
    print(f'  <span class=\"h-bar-label\" title=\"{name}\">{name}</span>')
    print(f'  <div class=\"h-bar-track\"><div class=\"h-bar-fill\" style=\"width:{max(width_pct, 2)}%\"></div></div>')
    print(f'  <span class=\"h-bar-value\">{fmt(tot)} ({sess})</span>')
    print(f'</div>')
" <<< "$agents_json"

  # ── Model × Agent Cross-tab ─────────────────────────────────────────────
  echo '<h2 id="cross-tab">Model &times; Agent Breakdown</h2>'
  
  local ma_json
  ma_json=$(query_model_agent)
  
  python3 -c "
import json, sys

def fmt(v):
    if v >= 1e9: return f'{v/1e9:.1f}B'
    if v >= 1e6: return f'{v/1e6:.1f}M'
    if v >= 1e3: return f'{v/1e3:.1f}K'
    return f'{v:,}'

data = json.load(sys.stdin)
if not data:
    print('<p style=\"color:#8892a4\">No cross-tab data in this period.</p>')
    sys.exit(0)

print('<table><thead><tr><th>Model</th><th>Agent</th><th class=\"num\">Sessions</th><th class=\"num\">Tokens</th></tr></thead><tbody>')
for d in data:
    model = (d.get('model') or 'unknown').replace('_', '-').replace('-', '-')[:30]
    agent = (d.get('agent') or 'unknown').replace('_', '-').replace('-', '-')[:20]
    sess = d.get('sessions', 0) or 0
    tot = d.get('total', 0) or 0
    print(f'<tr><td>{model}</td><td>{agent}</td><td class=\"num\">{sess}</td><td class=\"num\">{fmt(tot)}</td></tr>')
print('</tbody></table>')
" <<< "$ma_json"

  # ── Daily Token Trend (Timeseries) ──────────────────────────────────────
  echo '<h2 id="timeseries">Daily Token Trend</h2>'
  
  local ts_json
  ts_json=$(query_timeseries)
  
  # Extract date+tokens pairs for the SVG chart
  local chart_data
  chart_data=$(echo "$ts_json" | jq -r '.[] | "\(.day) \(.total_tokens)"')
  
  if [[ -n "$chart_data" ]]; then
    generate_svg_chart 800 300 50 "daily-chart" <<< "$chart_data"
    
    # Tooltip JS
    cat <<'TOOLTIPJS'
<script>
(function() {
  const tooltip = document.createElement('div');
  tooltip.id = 'svg-tooltip';
  Object.assign(tooltip.style, {
    position: 'fixed', display: 'none', background: '#16213e', border: '1px solid #4fc3f7',
    borderRadius: '6px', padding: '8px 12px', fontSize: '12px', color: '#e0e0e0',
    pointerEvents: 'none', zIndex: '9999', boxShadow: '0 4px 12px rgba(0,0,0,0.3)',
    lineHeight: '1.6'
  });
  document.body.appendChild(tooltip);

  function fmtTokens(v) {
    if (v >= 1e9) return (v/1e9).toFixed(1) + 'B';
    if (v >= 1e6) return (v/1e6).toFixed(1) + 'M';
    if (v >= 1e3) return (v/1e3).toFixed(1) + 'K';
    return v.toLocaleString();
  }

  document.querySelectorAll('.chart-point').forEach(pt => {
    pt.addEventListener('mouseenter', e => {
      const date = pt.dataset.date;
      const tokens = parseInt(pt.dataset.tokens);
      tooltip.innerHTML = '<strong>' + date + '</strong><br>Tokens: ' + fmtTokens(tokens);
      tooltip.style.display = 'block';
    });
    pt.addEventListener('mousemove', e => {
      tooltip.style.left = (e.clientX + 14) + 'px';
      tooltip.style.top = (e.clientY - 50) + 'px';
    });
    pt.addEventListener('mouseleave', () => {
      tooltip.style.display = 'none';
    });
  });
})();
</script>
TOOLTIPJS
    
    # Data table below chart
    echo '<table><thead><tr><th>Date</th><th>Sessions</th><th class="num">Tokens</th></tr></thead><tbody>'
    echo "$ts_json" | python3 -c "
import json, sys
def fmt(v):
    if v >= 1e9: return f'{v/1e9:.1f}B'
    if v >= 1e6: return f'{v/1e6:.1f}M'
    if v >= 1e3: return f'{v/1e3:.1f}K'
    return f'{v:,}'
for r in json.load(sys.stdin):
    print(f'<tr><td>{r[\"day\"]}</td><td class=\"num\">{r[\"sessions\"]}</td><td class=\"num\">{fmt(r[\"total_tokens\"])}</td></tr>')
"
    echo '</tbody></table>'
  else
    echo '<p style="color:#8892a4">No daily data in this period.</p>'
  fi

  # ── Top Sessions ────────────────────────────────────────────────────────
  echo '<h2 id="top-sessions">Top Sessions by Token Usage</h2>'
  
  local top_json
  top_json=$(query_top_sessions)
  
  python3 -c "
import json, sys

def fmt(v):
    if v >= 1e9: return f'{v/1e9:.1f}B'
    if v >= 1e6: return f'{v/1e6:.1f}M'
    if v >= 1e3: return f'{v/1e3:.1f}K'
    return f'{v:,}'

data = json.load(sys.stdin)
if not data:
    print('<p style=\"color:#8892a4\">No sessions in this period.</p>')
    sys.exit(0)

print('<table><thead><tr><th>#</th><th>Agent</th><th>Model</th><th>Title</th><th class=\"num\">Tokens</th></tr></thead><tbody>')
for i, d in enumerate(data, 1):
    agent = (d.get('agent') or 'unknown').replace('_', '-').replace('-', '-')[:20]
    model = (d.get('model') or 'unknown').replace('_', '-').replace('-', '-')[:35]
    title = str(d.get('title', ''))[:60]
    tot = d.get('total_tokens', 0) or 0
    print(f'<tr><td>{i}</td><td>{agent}</td><td style=\"font-size:0.75rem\">{model}</td><td>{title}</td><td class=\"num\">{fmt(tot)}</td></tr>')
print('</tbody></table>')
" <<< "$top_json"

  # ── Code Impact (Git-derived) ───────────────────────────────────────────
  echo '<h2 id="code-impact">Code Impact — Tokens vs. Commits</h2>'
  
  local git_stats ts_json_for_impact
  git_stats=$(extract_git_stats || true)
  ts_json_for_impact=$(query_timeseries)
  
  if [[ -z "$git_stats" && -z "$ts_json_for_impact" ]]; then
    echo '<p style="color:#8892a4">No code impact data available.</p>'
  else
    # Filter git stats to same date window as token data, pass via env var; timeseries JSON via stdin
    local filtered_git
    filtered_git=$(echo "$git_stats" | awk -v since="$SINCE" -v until="$UNTIL" '$1 >= since && $1 <= until')
    GIT_STATS="$filtered_git" TS_JSON="$ts_json_for_impact" python3 << 'PYEOF'
import json, os

def fmt(v):
    if v >= 1e9: return f'{v/1e9:.1f}B'
    if v >= 1e6: return f'{v/1e6:.1f}M'
    if v >= 1e3: return f'{v/1e3:.1f}K'
    return f'{v:,}'

token_map = {}
ts_raw = os.environ.get('TS_JSON', '').strip()
if ts_raw:
    try:
        for row in json.loads(ts_raw):
            token_map[row['day']] = row.get('total_tokens', 0) or 0
    except (json.JSONDecodeError, KeyError):
        pass

git_lines = os.environ.get('GIT_STATS', '').strip().split('\n') if os.environ.get('GIT_STATS') else []
git_map = {}
for line in git_lines:
    parts = line.split()
    if len(parts) >= 4 and parts[0].count('-') == 2:
        d, c, a, de = parts[0], int(parts[1]), int(parts[2]), int(parts[3])
        git_map[d] = (c, a, de)

if not git_map and not token_map:
    print('<p style="color:#8892a4">No code impact data available.</p>')
else:
    total_commits = sum(v[0] for v in git_map.values())
    total_adds = sum(v[1] for v in git_map.values())
    total_dels = sum(v[2] for v in git_map.values())
    total_tokens = sum(token_map.values())

    all_dates = sorted(set(list(token_map.keys()) + list(git_map.keys())))

    rows = []
    for date in all_dates:
        tokens = token_map.get(date, 0)
        commits, adds, dels = git_map.get(date, (0, 0, 0))
        tpc = round(tokens / commits) if commits > 0 else 0
        tpl = round(tokens / adds) if adds > 0 else 0
        rows.append((date, tokens, commits, adds, dels, tpc, tpl))

    avg_tok_per_commit = round(total_tokens / total_commits) if total_commits else 0
    avg_tok_per_line = round(total_tokens / total_adds) if total_adds else 0

    print(f'<p style="color:#8892a4; margin-bottom:1rem; font-size:0.9rem;">{fmt(total_tokens)} tokens consumed across {total_commits:,} commits producing {total_adds:,} lines of code.</p>')
    print('<div class="impact-grid">')
    print(f'  <div class="impact-card"><div class="impact-value">{fmt(total_commits)}</div><div class="impact-label">Total Commits</div></div>')
    print(f'  <div class="impact-card"><div class="impact-value">{fmt(total_adds)}</div><div class="impact-label">Lines Added</div></div>')
    print(f'  <div class="impact-card ratio"><div class="impact-value">{fmt(avg_tok_per_commit)}</div><div class="impact-label">Avg Tokens / Commit</div></div>')
    print(f'  <div class="impact-card ratio"><div class="impact-value">{fmt(avg_tok_per_line)}</div><div class="impact-label">Avg Tokens / Line Added</div></div>')
    print('</div>')

    print('<table><thead><tr><th>Date</th><th>Tokens</th><th>Commits</th><th>Adds</th><th>Dels</th><th class="num">Tok/Commit</th><th class="num">Tok/Line</th></tr></thead><tbody>')
    for r in rows:
        print(f'<tr><td>{r[0]}</td><td class="num">{fmt(r[1])}</td><td class="num">{r[2]}</td><td class="num">{fmt(r[3])}</td><td class="num">{fmt(r[4])}</td><td class="num">{fmt(r[5])}</td><td class="num">{fmt(r[6])}</td></tr>')
    print('</tbody></table>')

PYEOF
  fi

  # ── Footer ──────────────────────────────────────────────────────────────
  cat <<'HTMLFOOT'
<footer>Generated by generate_llm_report.sh &middot; Data source: opencode SQLite DB + git log</footer>
</body>
</html>
HTMLFOOT
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
  echo "Generating CollageMaker LLM usage report..." >&2
  echo "  Period: ${SINCE} to ${UNTIL}" >&2
  echo "  Output: ${OUTPUT}" >&2
  
  # Gather summary data
  local summary_line
  summary_line=$(read_summary)
  
  # Generate HTML
  generate_html "$summary_line" > "$OUTPUT"
  
  echo "Report generated: ${OUTPUT} ($(wc -c < "$OUTPUT") bytes)" >&2
}

main
