#!/usr/bin/env python3
"""Render LLM usage report from JSON data using references/report.html.

Usage: python3 render_report.py < data.json > report.html

Reads merged JSON from stdin (all query results + git stats), builds HTML sections,
and fills placeholders in the template to produce a self-contained HTML report.
"""

import json
import sys
from pathlib import Path
from string import Template

SCRIPT_DIR = Path(__file__).parent
sys.path.insert(0, str(SCRIPT_DIR))
from charts import render_stacked_area, render_tokens_vs_commits, render_efficiency


def fmt(v):
    """Format token count for display."""
    if v >= 1e9:
        return f'{v/1e9:.1f}B'
    if v >= 1e6:
        return f'{v/1e6:.1f}M'
    if v >= 1e3:
        return f'{v/1e3:.1f}K'
    return f'{v:,}'


def build_summary_metrics(data):
    """Render metric cards HTML from summary data."""
    tokens = data['totals']['tokens']
    total = tokens.get('total', 0)
    sessions = data['totals'].get('sessions', 0)
    model_count = data['totals'].get('model_count', 0)
    agent_count = data['totals'].get('agent_count', 0)
    
    avg_tok = total // sessions if sessions > 0 else 0
    
    return f'''<div class="metrics-grid" id="summary">
  <div class="metric-card"><div class="metric-value">{fmt(total)}</div><div class="metric-label">Total Tokens</div></div>
  <div class="metric-card"><div class="metric-value">{sessions}</div><div class="metric-label">Sessions</div></div>
  <div class="metric-card"><div class="metric-value">{fmt(avg_tok)}</div><div class="metric-label">Avg / Session</div></div>
  <div class="metric-card"><div class="metric-value">{model_count}</div><div class="metric-label">Models Used</div></div>
  <div class="metric-card"><div class="metric-value">{agent_count}</div><div class="metric-label">Agent Roles</div></div>
</div>'''


def build_models_section(models_data):
    """Render stacked bar chart for token usage by model."""
    if not models_data:
        return '<p style="color:#8892a4">No model data in this period.</p>'
    
    max_total = max(d.get('total', 0) for d in models_data) if models_data else 1
    
    html_parts = []
    for d in models_data:
        name = (d.get('model') or 'unknown').replace('_', '-').replace('-', '-')[:30]
        inp = d.get('input', 0) or 0
        out_ = d.get('output', 0) or 0
        rea = d.get('reasoning', 0) or 0
        tot = d.get('total', 0) or 0
        
        model_total = inp + out_ + rea
        inp_pct = (inp / model_total * 100) if model_total else 0
        out_pct = (out_ / model_total * 100) if model_total else 0
        rea_pct = (rea / model_total * 100) if model_total else 0
        
        bar_width = (tot / max_total * 100) if max_total else 0
        
        html_parts.append(f'<div class="bar-row">')
        html_parts.append(f'  <span class="bar-label" title="{name}">{name}</span>')
        html_parts.append(f'  <div class="bar-track" style="width:{max(bar_width, 5)}%">')
        if inp > 0:
            html_parts.append(f'    <div class="bar-segment" style="width:{inp_pct}%;background:#4fc3f7;" title="Input: {fmt(inp)}"></div>')
        if out_ > 0:
            html_parts.append(f'    <div class="bar-segment" style="width:{out_pct}%;background:#4db6ac;" title="Output: {fmt(out_)}"></div>')
        if rea > 0:
            html_parts.append(f'    <div class="bar-segment" style="width:{rea_pct}%;background:#ba68c8;" title="Reasoning: {fmt(rea)}"></div>')
        html_parts.append(f'  </div>')
        html_parts.append(f'  <span class="bar-value">{fmt(tot)}</span>')
        html_parts.append(f'</div>')
    
    return '\n'.join(html_parts)


def build_agents_section(agents_data):
    """Render horizontal bars for token usage by agent."""
    if not agents_data:
        return '<p style="color:#8892a4">No agent data in this period.</p>'
    
    max_total = max(d.get('total', 0) for d in agents_data) if agents_data else 1
    
    html_parts = []
    for d in agents_data:
        name = (d.get('agent') or 'unknown').replace('_', '-').replace('-', '-')[:20]
        tot = d.get('total', 0) or 0
        sess = d.get('sessions', 0) or 0
        width_pct = (tot / max_total * 100) if max_total else 0
        
        html_parts.append(f'<div class="h-bar-row">')
        html_parts.append(f'  <span class="h-bar-label" title="{name}">{name}</span>')
        html_parts.append(f'  <div class="h-bar-track"><div class="h-bar-fill" style="width:{max(width_pct, 2)}%"></div></div>')
        html_parts.append(f'  <span class="h-bar-value">{fmt(tot)} ({sess})</span>')
        html_parts.append(f'</div>')
    
    return '\n'.join(html_parts)


def build_cross_tab(cross_tab_data):
    """Render model × agent breakdown table."""
    if not cross_tab_data:
        return '<p style="color:#8892a4">No cross-tab data in this period.</p>'
    
    html = '<table><thead><tr><th>Model</th><th>Agent</th><th class="num">Sessions</th><th class="num">Tokens</th></tr></thead><tbody>'
    for d in cross_tab_data:
        model = (d.get('model') or 'unknown').replace('_', '-').replace('-', '-')[:30]
        agent = (d.get('agent') or 'unknown').replace('_', '-').replace('-', '-')[:20]
        sess = d.get('sessions', 0) or 0
        tot = d.get('total', 0) or 0
        html += f'<tr><td>{model}</td><td>{agent}</td><td class="num">{sess}</td><td class="num">{fmt(tot)}</td></tr>'
    html += '</tbody></table>'
    return html


def build_timeseries(timeseries_data):
    """Render daily token trend table with input/output/reasoning breakdown."""
    if not timeseries_data:
        return '<p style="color:#8892a4">No daily data in this period.</p>'
    
    html = '<table><thead><tr><th>Date</th><th>Sessions</th><th class="num">Total Tokens</th><th class="num">Input</th><th class="num">Output</th><th class="num">Reasoning</th><th class="num">Reasoning %</th></tr></thead><tbody>'
    for r in timeseries_data:
        inp = r.get('input_tokens', 0) or 0
        out_ = r.get('output_tokens', 0) or 0
        rea = r.get('reasoning_tokens', 0) or 0
        tot = r.get('total_tokens', 0) or 0
        sess = r.get('sessions', 0) or 0
        rea_pct = f'{rea/tot*100:.1f}%' if tot > 0 else '—'
        html += f'<tr><td>{r["day"]}</td><td class="num">{sess}</td><td class="num">{fmt(tot)}</td><td class="num">{fmt(inp)}</td><td class="num">{fmt(out_)}</td><td class="num">{fmt(rea)}</td><td class="num">{rea_pct}</td></tr>'
    html += '</tbody></table>'
    return html


def build_top_sessions(top_sessions_data):
    """Render top sessions table ranked by token count."""
    if not top_sessions_data:
        return '<p style="color:#8892a4">No sessions in this period.</p>'
    
    html = '<table><thead><tr><th>#</th><th>Agent</th><th>Model</th><th>Title</th><th class="num">Tokens</th></tr></thead><tbody>'
    for i, d in enumerate(top_sessions_data, 1):
        agent = (d.get('agent') or 'unknown').replace('_', '-').replace('-', '-')[:20]
        model = (d.get('model') or 'unknown').replace('_', '-').replace('-', '-')[:35]
        title = str(d.get('title', ''))[:60]
        tot = d.get('total_tokens', 0) or 0
        html += f'<tr><td>{i}</td><td>{agent}</td><td style="font-size:0.75rem">{model}</td><td>{title}</td><td class="num">{fmt(tot)}</td></tr>'
    html += '</tbody></table>'
    return html


def build_code_impact(token_map, git_map):
    """Render code impact section with charts and tables.
    
    Merges token timeseries with git stats by date.
    Handles edge cases: sessions w/o commits → effective_commits=1, commits w/o sessions → 0 tokens.
    Returns full HTML section including SVG charts via charts.py functions.
    """
    if not git_map and not token_map:
        return '<p style="color:#8892a4">No code impact data available.</p>'
    
    # Build merged rows with effective_commits edge-case logic
    all_dates = sorted(set(list(token_map.keys()) + list(git_map.keys())))
    
    rows = []
    for date in all_dates:
        d = token_map.get(date, None)
        commits, adds, dels = git_map.get(date, (0, 0, 0))
        
        if d is not None:
            tokens = d['total_tokens']
            inp = d['input_tokens']
            out_ = d['output_tokens']
            rea = d['reasoning_tokens']
            sess = d['sessions']
            eff_commits = max(commits, 1) if commits == 0 else commits
        else:
            tokens = inp = out_ = rea = sess = 0
            eff_commits = commits
        
        tpc = round(tokens / eff_commits) if eff_commits > 0 else 0
        tpl = round(tokens / adds) if adds > 0 else 0
        rea_pct = f'{rea/tokens*100:.1f}%' if tokens > 0 else '—'
        rows.append((date, tokens, inp, out_, rea, sess, eff_commits, commits, adds, dels, tpc, tpl, rea_pct))
    
    total_commits = sum(v[0] for v in git_map.values())
    total_adds = sum(v[1] for v in git_map.values())
    total_dels = sum(v[2] for v in git_map.values())
    total_tokens = sum(d['total_tokens'] for d in token_map.values())
    total_reasoning = sum(d['reasoning_tokens'] for d in token_map.values())
    
    avg_tok_per_commit = round(total_tokens / total_commits) if total_commits else 0
    avg_tok_per_line = round(total_tokens / total_adds) if total_adds else 0
    reasoning_pct_total = f'{total_reasoning/total_tokens*100:.1f}%' if total_tokens > 0 else '—'
    
    # Subtitle & Metric Cards
    html_parts = []
    html_parts.append(f'<p style="color:#8892a4; margin-bottom:1rem; font-size:0.9rem;">{fmt(total_tokens)} tokens consumed across {total_commits:,} commits producing {total_adds:,} lines of code.</p>')
    html_parts.append('<div class="impact-grid">')
    html_parts.append(f'  <div class="impact-card"><div class="impact-value">{fmt(total_commits)}</div><div class="impact-label">Total Commits</div></div>')
    html_parts.append(f'  <div class="impact-card"><div class="impact-value">{fmt(total_adds)}</div><div class="impact-label">Lines Added</div></div>')
    html_parts.append(f'  <div class="impact-card ratio"><div class="impact-value">{fmt(avg_tok_per_commit)}</div><div class="impact-label">Avg Tokens / Commit</div></div>')
    html_parts.append(f'  <div class="impact-card ratio"><div class="impact-value">{fmt(avg_tok_per_line)}</div><div class="impact-label">Avg Tokens / Line Added</div></div>')
    html_parts.append(f'  <div class="impact-card"><div class="impact-value">{reasoning_pct_total}</div><div class="impact-label">Reasoning %</div></div>')
    peak_tpc = max((r[10] for r in rows if r[6] > 0), default=0)
    html_parts.append(f'  <div class="impact-card"><div class="impact-value">{fmt(peak_tpc)}</div><div class="impact-label">Peak Tok / Commit</div></div>')
    html_parts.append('</div>')
    
    # Chart 1: Daily Token Breakdown (Stacked Area)
    html_parts.append('<h3 id="chart-token-breakdown" class="chart-title">Daily Token Breakdown</h3>')
    if rows:
        html_parts.append(render_stacked_area(rows))
    else:
        html_parts.append('<p style="color:#8892a4">No daily token data in this period.</p>')
    
    # Chart 2: Tokens vs. Commits (Dual-Axis)
    html_parts.append('<h3 id="chart-tokens-vs-commits" class="chart-title">Tokens vs. Commits</h3>')
    if rows:
        html_parts.append(render_tokens_vs_commits(rows))
    else:
        html_parts.append('<p style="color:#8892a4">No daily data in this period.</p>')
    
    # Chart 3: Tokens per Commit vs. per Line (Dual-Axis)
    html_parts.append('<h3 id="chart-efficiency" class="chart-title">Tokens per Commit vs. per Line Added</h3>')
    if rows:
        html_parts.append(render_efficiency(rows))
    else:
        html_parts.append('<p style="color:#8892a4">No daily data in this period.</p>')
    
    # Summary Table (all merged metrics)
    html_parts.append('<h3 id="summary-table" class="chart-title">Daily Summary</h3>')
    html_parts.append('<table><thead><tr><th>Date</th><th>Sessions</th><th class="num">Total Tokens</th><th class="num">Input</th><th class="num">Output</th><th class="num">Reasoning</th><th class="num">Reasoning %</th><th class="num">Commits</th><th class="num">Adds</th><th class="num">Dels</th><th class="num">Tok/Commit</th><th class="num">Tok/Line</th></tr></thead><tbody>')
    for r in rows:
        html_parts.append(f'<tr><td>{r[0]}</td><td class="num">{r[5]}</td><td class="num">{fmt(r[1])}</td><td class="num">{fmt(r[2])}</td><td class="num">{fmt(r[3])}</td><td class="num">{fmt(r[4])}</td><td class="num">{r[12]}</td><td class="num">{r[7]}</td><td class="num">{fmt(r[8])}</td><td class="num">{fmt(r[9])}</td><td class="num">{fmt(r[10])}</td><td class="num">{fmt(r[11])}</td></tr>')
    html_parts.append('</tbody></table>')
    
    return '\n'.join(html_parts)


def main():
    """Read JSON from stdin, render HTML report."""
    # Read all data from stdin
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON input: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Load template
    template_path = SCRIPT_DIR.parent / 'templates' / 'report.html'
    if not template_path.exists():
        print(f"Error: Template not found at {template_path}", file=sys.stderr)
        sys.exit(1)
    
    with open(template_path, 'r') as f:
        template_str = f.read()
    
    try:
        template = Template(template_str)
    except ValueError as e:
        print(f"Error: Invalid template syntax: {e}", file=sys.stderr)
        sys.exit(1)
    
    # Build substitutions
    tokens = data.get('totals', {}).get('tokens', {})
    substitutions = {
        'TITLE': data.get('title', 'CollageMaker — LLM Usage Report'),
        'PERIOD': f"{data.get('since', '')} to {data.get('until', '')}",
        'GENERATED': data.get('generated', ''),
        'SUMMARY_METRICS': build_summary_metrics(data),
        'MODELS_SECTION': build_models_section(data.get('models', [])),
        'AGENTS_SECTION': build_agents_section(data.get('agents', [])),
        'CROSSTAB_SECTION': build_cross_tab(data.get('cross_tab', [])),
        'TIMESERIES_SECTION': build_timeseries(data.get('timeseries', [])),
        'TOP_SESSIONS_SECTION': build_top_sessions(data.get('top_sessions', [])),
        'CODE_IMPACT_SECTION': build_code_impact(
            data.get('token_map', {}),
            data.get('git_map', {})
        ),
        'DAILY_ACTIVITY_LINK': data.get('daily_activity_link', '')
    }
    
    # Render and output
    try:
        html = template.substitute(**substitutions)
        print(html)
    except KeyError as e:
        print(f"Error: Missing placeholder in template: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
