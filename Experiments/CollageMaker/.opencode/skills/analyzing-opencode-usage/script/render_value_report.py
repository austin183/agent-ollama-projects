#!/usr/bin/env python3
"""Render Token Value Analysis report from JSON data.

Usage: python3 render_value_report.py < value-report-data.json > token-value-report.html

Reads merged JSON from stdin (DB queries + git stats), builds HTML sections,
and outputs a self-contained HTML report.
"""

import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
sys.path.insert(0, str(SCRIPT_DIR))
from charts import (
    fmt, fmt_short,
    render_cumulative_efficiency,
    render_cumulative_cost,
    render_daily_agent_stacked,
    render_rolling_tok_per_commit,
    render_test_ratio,
    render_context_efficiency_table,
)


def build_summary_metrics(data):
    """Render top metric cards."""
    s = data.get('summary', {})
    total = s.get('total_tokens', 0) or 0
    sessions = s.get('total_sessions', 0) or 0
    earliest = s.get('earliest', '')
    latest = s.get('latest', '')
    model_count = s.get('model_count', 0)
    agent_count = s.get('agent_count', 0)
    avg_tok = total // sessions if sessions > 0 else 0

    merged = data.get('merged_daily', [])
    total_commits = sum(r.get('commits', 0) for r in merged)
    total_adds = sum(r.get('adds', 0) for r in merged)
    total_test_adds = sum(r.get('test_adds', 0) for r in merged)

    cs = data.get('cost_summary', {})
    cheap = cs.get('total_cheap', 0) or 0
    expensive = cs.get('total_expensive', 0) or 0

    return f'''<div class="metrics-grid" id="summary">
  <div class="metric-card"><div class="metric-value">{fmt(total)}</div><div class="metric-label">Total Tokens</div></div>
  <div class="metric-card"><div class="metric-value">{sessions}</div><div class="metric-label">Sessions</div></div>
  <div class="metric-card"><div class="metric-value">{fmt(avg_tok)}</div><div class="metric-label">Avg / Session</div></div>
  <div class="metric-card"><div class="metric-value">{total_commits}</div><div class="metric-label">Commits</div></div>
  <div class="metric-card"><div class="metric-value">{fmt(total_adds)}</div><div class="metric-label">Swift Lines Added</div></div>
  <div class="metric-card"><div class="metric-value">{fmt(total_test_adds)}</div><div class="metric-label">Test Lines Added</div></div>
  <div class="metric-card cost"><div class="metric-value">${cheap:,.2f}</div><div class="metric-label">Est. Cost (Low)</div></div>
  <div class="metric-card cost"><div class="metric-value">${expensive:,.2f}</div><div class="metric-label">Est. Cost (High)</div></div>
</div>
<p class="subtitle">Period: {earliest} to {latest} &middot; {model_count} models &middot; {agent_count} agent roles &middot; Generated: {data.get('generated', '')}</p>
<p class="subtitle" style="margin-top:0.3rem;">Cost estimates: ${cs.get('cheap_input_per_m', 0)}/M input + ${cs.get('cheap_output_per_m', 0)}/M output (low) vs ${cs.get('expensive_input_per_m', 0)}/M + ${cs.get('expensive_output_per_m', 1.50)}/M (high). {cs.get('note', '')}</p>'''


def build_phase_table(phases):
    """Render phase summary table."""
    if not phases:
        return '<p style="color:#8892a4">No phase data.</p>'

    html = '<table><thead><tr><th>Phase</th><th>Dates</th><th class="num">Tokens</th><th class="num">Sessions</th><th class="num">Commits</th><th class="num">Swift+</th><th class="num">Test+</th><th class="num">Tok/Commit</th><th class="num">Tok/Swift</th><th class="num">Test%</th><th class="num">Cost (Low)</th><th class="num">Cost (High)</th></tr></thead><tbody>'
    for p in phases:
        date_range = f"{p.get('start', '')}–{p.get('end', '')}"
        html += (
            f'<tr><td>{p["name"]}</td><td>{date_range}</td>'
            f'<td class="num">{fmt(p.get("tokens", 0))}</td>'
            f'<td class="num">{p.get("sessions", 0)}</td>'
            f'<td class="num">{p.get("commits", 0)}</td>'
            f'<td class="num">{fmt(p.get("swift_adds", 0))}</td>'
            f'<td class="num">{fmt(p.get("test_adds", 0))}</td>'
            f'<td class="num">{fmt(p.get("tok_per_commit", 0))}</td>'
            f'<td class="num">{fmt(p.get("tok_per_swift", 0))}</td>'
            f'<td class="num">{p.get("test_pct", 0)}%</td>'
            f'<td class="num">${p.get("cost_cheap", 0):,.2f}</td>'
            f'<td class="num">${p.get("cost_expensive", 0):,.2f}</td></tr>'
        )
    html += '</tbody></table>'
    return html


def build_efficiency_commits_table(commits, title):
    """Render top N efficient/inefficient commits table."""
    if not commits:
        return '<p style="color:#8892a4">No commit efficiency data.</p>'

    html = f'<h3 class="chart-title">{title}</h3>'
    html += '<table><thead><tr><th>#</th><th>Date</th><th>Message</th><th class="num">Lines</th><th class="num">Adds</th><th class="num">Dels</th><th class="num">Tok/Commit</th><th class="num">Tok/Line</th></tr></thead><tbody>'
    for i, c in enumerate(commits, 1):
        msg = str(c.get('message', ''))[:80]
        html += (
            f'<tr><td>{i}</td><td>{c.get("date", "")}</td><td>{msg}</td>'
            f'<td class="num">{c.get("lines_changed", 0)}</td>'
            f'<td class="num">{c.get("adds", 0)}</td>'
            f'<td class="num">{c.get("dels", 0)}</td>'
            f'<td class="num">{fmt(c.get("tok_per_commit", 0))}</td>'
            f'<td class="num">{fmt(c.get("tok_per_line", 0))}</td></tr>'
        )
    html += '</tbody></table>'
    return html


def build_weekly_table(weekly):
    """Render weekly agent breakdown table."""
    if not weekly:
        return '<p style="color:#8892a4">No weekly data.</p>'

    html = '<table><thead><tr><th>Week</th><th>Dates</th><th class="num">Sessions</th><th class="num">Total</th><th class="num">Build</th><th class="num">Review</th><th class="num">Plan</th><th class="num">Explore</th></tr></thead><tbody>'
    for w in weekly:
        html += (
            f'<tr><td>{w.get("week", "")}</td><td>{w.get("week_start", "")}–{w.get("week_end", "")}</td>'
            f'<td class="num">{w.get("sessions", 0)}</td>'
            f'<td class="num">{fmt(w.get("total_tokens", 0))}</td>'
            f'<td class="num">{fmt(w.get("build_tok", 0))}</td>'
            f'<td class="num">{fmt(w.get("review_tok", 0))}</td>'
            f'<td class="num">{fmt(w.get("plan_tok", 0))}</td>'
            f'<td class="num">{fmt(w.get("explore_tok", 0))}</td></tr>'
        )
    html += '</tbody></table>'
    return html


def build_productivity_section(data):
    """Render productivity stats."""
    prod = data.get('productivity', {})
    build_prod = data.get('build_productivity', {})

    total_sessions = prod.get('total_sessions', 0) or 0
    with_changes = prod.get('sessions_with_changes', 0) or 0
    pct = prod.get('pct_with_changes', 0) or 0

    build_total = build_prod.get('total_build_sessions', 0) or 0
    build_productive = build_prod.get('productive_sessions', 0) or 0
    build_pct = build_prod.get('pct_productive', 0) or 0
    build_tokens = build_prod.get('total_tokens', 0) or 0
    zero_change_tokens = build_prod.get('zero_change_tokens', 0) or 0
    zero_pct = round(100.0 * zero_change_tokens / build_tokens, 1) if build_tokens > 0 else 0

    s = data.get('summary', {})
    null_agent_sessions = sum(1 for r in data.get('merged_daily', []) if False)  # computed below
    null_agent_tokens = 0
    for r in data.get('agent_context', []):
        if r.get('agent') is None:
            null_agent_tokens += r.get('total_tokens', 0)

    # Count zero-commit days with high token usage
    merged = data.get('merged_daily', [])
    zero_commit_high_tok = [r for r in merged if r.get('commits', 0) == 0 and r.get('total_tokens', 0) > 1000000]
    zero_commit_tok_total = sum(r['total_tokens'] for r in zero_commit_high_tok)

    html = '<div class="impact-grid">'
    html += f'<div class="impact-card"><div class="impact-value">{pct}%</div><div class="impact-label">Sessions w/ File Changes</div></div>'
    html += f'<div class="impact-card"><div class="impact-value">{with_changes}/{total_sessions}</div><div class="impact-label">Productive Sessions</div></div>'
    html += f'<div class="impact-card ratio"><div class="impact-value">{build_pct}%</div><div class="impact-label">Build Agent Productive</div></div>'
    html += f'<div class="impact-card"><div class="impact-value">{zero_pct}%</div><div class="impact-label">Build Tokens w/ Zero Changes</div></div>'
    html += '</div>'
    html += '<p style="color:#8892a4; font-size:0.82rem; margin-bottom:1rem;">'
    html += '<strong>Notes:</strong> '
    html += '<code>summary_files</code> is only populated for sessions where opencode recorded file changes. '
    html += 'Most sessions are exploratory, research, or cross-session coordination. '
    html += 'Input token counts may be overstated for sessions where LM Studio caching occurred invisibly (cache columns not yet populated). '
    if zero_commit_high_tok:
        html += f'{len(zero_commit_high_tok)} days had {fmt(zero_commit_tok_total)} tokens with zero commits '
        html += '(e.g., research, debugging, cross-session coordination). '
    if null_agent_tokens > 0:
        html += f'19 legacy sessions have no agent assigned ({fmt(null_agent_tokens)} tokens). '
    html += '</p>'
    return html


def main():
    """Read JSON from stdin, render HTML report."""
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON input: {e}", file=sys.stderr)
        sys.exit(1)

    merged_daily = data.get('merged_daily', [])
    phases = data.get('phases', [])
    weekly = data.get('weekly', [])
    agent_context = data.get('agent_context', [])
    most_efficient = data.get('most_efficient_commits', [])
    least_efficient = data.get('least_efficient_commits', [])

    # Build HTML
    html_parts = []
    html_parts.append('''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>CollageMaker — Token Value Analysis</title>
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

  .metrics-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 1rem; margin-bottom: 2rem; }
  .metric-card { background: var(--card-bg); border: 1px solid var(--border); border-radius: 8px; padding: 1.2rem; text-align: center; }
  .metric-value { font-size: 1.6rem; font-weight: 700; color: var(--accent); letter-spacing: -1px; }
  .metric-label { font-size: 0.75rem; color: var(--muted); text-transform: uppercase; margin-top: 0.3rem; letter-spacing: 0.5px; }
  .metric-card.cost { border-color: #f5a623; background: rgba(245,166,35,0.06); }
  .metric-card.cost .metric-value { color: #f5a623; }

  .impact-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 1.5rem; }
  .impact-card { background: var(--card-bg); border: 1px solid var(--border); border-radius: 8px; padding: 1.2rem; text-align: center; }
  .impact-value { font-size: 1.8rem; font-weight: 700; color: #4db6ac; letter-spacing: -1px; }
  .impact-label { font-size: 0.72rem; color: var(--muted); text-transform: uppercase; margin-top: 0.3rem; letter-spacing: 0.5px; }
  .impact-card.ratio { border-color: #4db6ac; background: rgba(77, 182, 172, 0.06); }
  .impact-card.ratio .impact-value { color: #4db6ac; font-size: 2rem; }

  table { width: 100%; border-collapse: collapse; margin-bottom: 1.5rem; font-size: 0.82rem; }
  th { text-align: left; color: var(--muted); padding: 0.6rem 0.8rem; border-bottom: 1px solid var(--border); font-weight: 500; text-transform: uppercase; font-size: 0.7rem; letter-spacing: 0.5px; }
  td { padding: 0.5rem 0.8rem; border-bottom: 1px solid rgba(255,255,255,0.04); }
  tr:nth-child(even) td { background: rgba(255,255,255,0.02); }
  tr:hover td { background: rgba(79,195,247,0.06); }
  .num { text-align: right; font-variant-numeric: tabular-nums; }

  .chart-svg { width: 100%; height: auto; margin-bottom: 1rem; }
  .chart-point { cursor: crosshair; transition: r 0.15s; }
  .chart-point:hover { r: 6; }
  .chart-title { font-size: 0.95rem; color: var(--muted); margin-top: 2rem; margin-bottom: 0.8rem; padding-bottom: 0.3rem; border-bottom: 1px solid rgba(15,52,96,0.5); }

  #svg-tooltip { position: fixed; display: none; background: #16213e; border: 1px solid #4fc3f7; border-radius: 6px; padding: 8px 12px; font-size: 12px; color: #e0e0e0; pointer-events: none; z-index: 9999; box-shadow: 0 4px 12px rgba(0,0,0,0.3); line-height: 1.6; }

  footer { margin-top: 3rem; padding-top: 1rem; border-top: 1px solid var(--border); font-size: 0.72rem; color: var(--muted); text-align: center; }
  code { background: rgba(79,195,247,0.1); padding: 0.1rem 0.3rem; border-radius: 3px; font-size: 0.8rem; }
</style>
</head>
<body>

<h1>CollageMaker — Token Value Analysis</h1>''')

    # Summary metrics
    html_parts.append(build_summary_metrics(data))

    # Phase summary
    html_parts.append('<h2 id="phases">Phase Breakdown</h2>')
    html_parts.append(build_phase_table(phases))

    # Productivity
    html_parts.append('<h2 id="productivity">Productivity Overview</h2>')
    html_parts.append(build_productivity_section(data))

    # Chart 1: Cumulative tokens vs. cumulative Swift lines
    html_parts.append('<h2 id="charts">Efficiency Curves</h2>')
    html_parts.append('<h3 class="chart-title">Cumulative Tokens vs. Cumulative Swift Lines</h3>')
    html_parts.append(render_cumulative_efficiency(merged_daily, 'cum_swift', 'Swift Lines'))

    # Chart 2: Cumulative tokens vs. cumulative test lines
    html_parts.append('<h3 class="chart-title">Cumulative Tokens vs. Cumulative Test Lines</h3>')
    html_parts.append(render_cumulative_efficiency(merged_daily, 'cum_test', 'Test Lines'))

    # Chart 3: Cumulative cost over time
    html_parts.append('<h2 id="cost">Cumulative Estimated Cost</h2>')
    html_parts.append(render_cumulative_cost(merged_daily))

    # Chart 4: Daily tokens stacked by agent
    html_parts.append('<h2 id="agent-breakdown">Daily Token Breakdown by Agent</h2>')
    html_parts.append(render_daily_agent_stacked(merged_daily))

    # Chart 4: 7-day rolling tokens per commit
    html_parts.append('<h2 id="rolling-efficiency">7-Day Rolling Tokens per Commit</h2>')
    html_parts.append(render_rolling_tok_per_commit(merged_daily))

    # Chart 5: Test ratio over time
    html_parts.append('<h2 id="test-ratio">Test Ratio Over Time</h2>')
    html_parts.append(render_test_ratio(merged_daily))

    # Commit efficiency tables
    html_parts.append('<h2 id="commit-efficiency">Commit Efficiency</h2>')
    html_parts.append(build_efficiency_commits_table(most_efficient, 'Top 10 Most Efficient Commits'))
    html_parts.append(build_efficiency_commits_table(least_efficient, 'Top 10 Least Efficient Commits'))

    # Weekly breakdown
    html_parts.append('<h2 id="weekly">Weekly Agent Breakdown</h2>')
    html_parts.append(build_weekly_table(weekly))

    # Context efficiency
    html_parts.append('<h2 id="context-efficiency">Agent Context Efficiency</h2>')
    html_parts.append('<p style="color:#8892a4; font-size:0.85rem; margin-bottom:1rem;">Turns = user messages per session. Input tokens grow as conversation history accumulates — each turn re-sends prior context. Avg Input/Turn shows effective context size per exchange.</p>')
    html_parts.append(render_context_efficiency_table(agent_context))

    # Footer
    html_parts.append('''
<footer>
  <p>Data sources: opencode SQLite DB (<code>session</code> + <code>message</code> tables) + git log (skipping SHAs: <code>a877b47</code>, <code>2f5d923</code>, <code>4c13f15</code>, <code>f43f886</code>)</p>
  <p>LM Studio cache columns (<code>tokens_cache_read</code>/<code>tokens_cache_write</code>) exist but are all 0 — input token counts may be overstated for cached sessions.</p>
  <p>Phase "tok/swift" for Efficiency Gains is elevated due to high test code ratio (65.7%) and days with zero commits but high token usage.</p>
</footer>

<div id="svg-tooltip"></div>

<script>
// Tooltip for chart points
const tooltip = document.getElementById('svg-tooltip');
document.querySelectorAll('.chart-point').forEach(pt => {
  pt.addEventListener('mouseenter', e => {
    if (!tooltip) return;
    tooltip.style.display = 'block';
    let html = '';
    const date = pt.getAttribute('data-date');
    if (date) html += `<strong>${date}</strong><br>`;
    const attrs = pt.attributes;
    for (let i = 0; i < attrs.length; i++) {
      const attr = attrs[i];
      if (attr.name.startsWith('data-') && attr.name !== 'data-date' && attr.name !== 'data-chart-type') {
        const label = attr.name.replace('data-', '').replace(/-([a-z])/g, g => g[1].toUpperCase());
        const num = parseFloat(attr.value);
        html += `${label}: ${isNaN(num) ? attr.value : num.toLocaleString()}<br>`;
      }
    }
    tooltip.innerHTML = html;
  });
  pt.addEventListener('mousemove', e => {
    if (!tooltip) return;
    tooltip.style.left = (e.clientX + 15) + 'px';
    tooltip.style.top = (e.clientY + 15) + 'px';
  });
  pt.addEventListener('mouseleave', () => { if (tooltip) tooltip.style.display = 'none'; });
});
</script>
</body>
</html>''')

    print('\n'.join(html_parts))


if __name__ == '__main__':
    main()
