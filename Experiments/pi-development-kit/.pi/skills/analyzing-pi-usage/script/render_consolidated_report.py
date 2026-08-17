#!/usr/bin/env python3
"""Render consolidated LLM Usage & Value report from unified JSON payload.

This module provides the render_html() function used by generate_report.py
to produce a self-contained HTML report with collapsible sections, charts, and tables.
All token counts use cache-adjusted (uncached) input by default.

Ported from the opencode kit's renderer: agent-named keys became role-named
keys, the agent context-efficiency section was dropped (no pi counterpart),
and a Subagent Runs section was added (pi's subagent tool results carry
per-run attribution the opencode kit could not get).

Standalone usage:
    python3 render_consolidated_report.py < consolidated-data.json > report.html
"""

import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
sys.path.insert(0, str(SCRIPT_DIR))
from charts import (
    fmt, fmt_short,
    render_stacked_area,
    render_tokens_vs_commits,
    render_efficiency,
    render_cumulative_efficiency,
    render_cumulative_cost,
    render_daily_agent_stacked,
    render_rolling_tok_per_commit,
    render_test_ratio,
    render_context_efficiency_table,
)
from model_pricing import MODEL_PRICING, FLAT_RATES

# ── CSS for collapsible sections & report layout ─────────────────────────────

COLLAPSIBLE_CSS = """
  /* Collapsible sections */
  .collapsible-section { margin-bottom: 1rem; border: 1px solid var(--border); border-radius: 8px; overflow: hidden; }
  .collapsible-section > summary {
    background: var(--card-bg); padding: 0.8rem 1.2rem; cursor: pointer;
    font-size: 1rem; color: var(--accent); user-select: none;
    list-style: none; display: flex; align-items: center; justify-content: space-between;
    transition: background 0.15s;
  }
  .collapsible-section > summary:hover { background: rgba(79,195,247,0.08); }
  .collapsible-section > summary::-webkit-details-marker { display: none; }
  .collapsible-section > summary::after {
    content: '\u25BE'; font-size: 0.8rem; transition: transform 0.2s; color: var(--muted);
  }
  .collapsible-section[open] > summary::after { transform: rotate(180deg); }
  .collapsible-content { padding: 1rem 1.2rem; background: rgba(26,26,46,0.5); }

  /* Always-visible sections get no border/shadow for visual consistency */
  .always-visible { margin-bottom: 1.5rem; }
"""


def build_summary_cards(data):
    """Render top metric cards (always visible).

    Shows effective tokens, raw tokens, sessions, avg/session, commits, lines added,
    cost estimates, and cache hit rate in a responsive grid.
    """
    s = data.get('summary', {})
    cs = data.get('cost_summary', {})
    ccs = data.get('cache_cost_summary', {})

    effective = s.get('total_tokens_effective', 0) or 0
    raw_total = s.get('total_tokens_raw', 0) or 0
    sessions = s.get('total_sessions', 0) or 0
    avg_tok = effective // sessions if sessions > 0 else 0

    ts = data.get('timeseries', [])
    total_commits = sum(r.get('commits', 0) for r in ts)
    total_adds = sum(r.get('adds', 0) for r in ts)

    cheap_raw = cs.get('total_cheap', 0) or 0
    exp_raw = cs.get('total_expensive', 0) or 0
    cheap_cache = ccs.get('total_cheap', 0) or 0
    exp_cache = ccs.get('total_expensive', 0) or 0
    # Use per-model pricing as primary cost display (canonical source of truth)
    per_model_raw = cs.get('total_per_model', 0) or 0
    per_model_cache = ccs.get('total_per_model', 0) or 0
    cache_hit = s.get('cache_hit_pct', 0) or 0

    meta = data.get('meta', {})
    earliest = s.get('earliest', '')
    latest = s.get('latest', '')
    model_count = s.get('model_count', 0)
    agent_count = s.get('role_count', 0) or s.get('agent_count', 0)

    cards = f'''<div class="metrics-grid" id="summary">
  <div class="metric-card" title="Estimated tokens after prefix caching: only truly new input tokens + output + reasoning. Shows what you would pay if the provider supported prompt caching."><div class="metric-value">{fmt(effective)}</div><div class="metric-label">Effective Tokens</div></div>
  <div class="metric-card" title="Total tokens as recorded by pi: input + output + reasoning. Includes redundant context re-sent each turn in multi-turn sessions."><div class="metric-value">{fmt(raw_total)}</div><div class="metric-label">Raw Tokens</div></div>
  <div class="metric-card"><div class="metric-value">{sessions}</div><div class="metric-label">Sessions</div></div>
  <div class="metric-card"><div class="metric-value">{fmt(avg_tok)}</div><div class="metric-label">Avg / Session</div></div>
  <div class="metric-card"><div class="metric-value">{total_commits}</div><div class="metric-label">Commits</div></div>
  <div class="metric-card"><div class="metric-value">{fmt(total_adds)}</div><div class="metric-label">Lines Added</div></div>
  <div class="metric-card cost"><div class="metric-value">${per_model_raw:,.2f}</div><div class="metric-label">Est. Cost (raw)</div></div>'''

    if cache_hit > 0:
        cards += f'''
  <div class="metric-card cost" style="border-color:#4db6ac;background:rgba(77,182,172,0.06);"><div class="metric-value" style="color:#4db6ac;">${per_model_cache:,.2f}</div><div class="metric-label">Est. Cost (w/cache)</div></div>
  <div class="metric-card" title="Simulated prefix-caching estimate, not actual provider cache performance. Computed from per-message token deltas: each turn re-sends prior context, but only the delta vs the previous turn is considered truly new."><div class="metric-value">{cache_hit}%</div><div class="metric-label">Cache Hit Rate</div></div>'''

    cards += '</div>'

    # Legend explaining raw vs effective tokens (see card tooltips above)
    cards += (
        '<p class="subtitle metrics-legend">'
        '<strong>Effective Tokens</strong> = uncached input + output + reasoning (truly new work). '
        '<strong>Raw Tokens</strong> = all tokens as recorded by pi, '
        'including redundant context re-sent each turn in multi-turn sessions. '
        'The difference is the estimated prefix-caching savings.'
        '</p>'
    )

    # Subtitle line — annotate the true project start when the query range
    # is narrower than the project's full history
    period = f'Period: {earliest} to {latest}'
    project_since = meta.get('project_since', '')
    if project_since and project_since != meta.get('since', ''):
        period += f' (project started {project_since}, {meta.get("total_sessions_all_time", 0)} all-time sessions)'
    subtitle = f'{period} &middot; {model_count} models &middot; {agent_count} roles &middot; Generated: {meta.get("generated", "")}'
    cards += f'<p class="subtitle">{subtitle}</p>'

    # Cost estimate note
    note = 'Cost estimates: cloud-equivalent per-model pricing (actual cost: $0, all models run locally via LM Studio).'
    cards += f'<p class="subtitle" style="margin-top:0.3rem;">{note}</p>'

    if cache_hit > 0:
        cache_savings = per_model_raw - per_model_cache
        savings_dollar = round(cache_savings, 2) if per_model_raw else 0
        pct_savings = round(100.0 * savings_dollar / per_model_raw, 1) if per_model_raw > 0 else 0
        cards += f'<p class="subtitle" style="margin-top:0.3rem; color:#4db6ac;">${savings_dollar:,.2f} saved via prompt context caching ({pct_savings}% reduction, {cache_hit}% cache hit rate).</p>'

    return cards


def build_models_section(models_data, cache_estimate=None):
    """Render stacked bar chart for token usage by model (always visible).

    Uses cache-adjusted effective totals when available.
    """
    if not models_data:
        return '<p style="color:#8892a4">No model data in this period.</p>'

    lookups = _cache_lookups(cache_estimate or {})
    max_total = 0
    for d in models_data:
        name = (d.get('model') or 'unknown')[:30]
        lookup = lookups['by_model'].get(name)
        if lookup:
            eff = _effective_total(lookup['uncached_input'], lookup['output'], lookup['reasoning'])
            max_total = max(max_total, eff)
        else:
            tot = d.get('total_tokens_raw', 0) or 0
            max_total = max(max_total, tot)

    html_parts = []
    for d in models_data:
        name = (d.get('model') or 'unknown')[:30]
        lookup = lookups['by_model'].get(name)

        if lookup:
            inp = lookup['uncached_input']
            out_ = lookup['output']
            rea = lookup['reasoning']
        else:
            inp = d.get('input_tokens_raw', 0) or 0
            out_ = d.get('output_tokens_raw', 0) or 0
            rea = d.get('reasoning_tokens_raw', 0) or 0

        model_total = _effective_total(inp, out_, rea)
        inp_pct = (inp / model_total * 100) if model_total else 0
        out_pct = (out_ / model_total * 100) if model_total else 0
        rea_pct = (rea / model_total * 100) if model_total else 0

        bar_width = (model_total / max_total * 100) if max_total else 0

        html_parts.append(f'<div class="bar-row">')
        html_parts.append(f'  <span class="bar-label" title="{name}">{name}</span>')
        html_parts.append(f'  <div class="bar-track" style="width:{max(bar_width, 5)}%">')
        if inp > 0:
            label = "Uncached Input" if lookup else "Input"
            html_parts.append(f'    <div class="bar-segment" style="width:{inp_pct}%;background:#4fc3f7;" title="{label}: {fmt(inp)}"></div>')
        if out_ > 0:
            html_parts.append(f'    <div class="bar-segment" style="width:{out_pct}%;background:#4db6ac;" title="Output: {fmt(out_)}"></div>')
        if rea > 0:
            html_parts.append(f'    <div class="bar-segment" style="width:{rea_pct}%;background:#ba68c8;" title="Reasoning: {fmt(rea)}"></div>')
        html_parts.append(f'  </div>')
        html_parts.append(f'  <span class="bar-value">{fmt(model_total)}</span>')
        html_parts.append(f'</div>')

    return '\n'.join(html_parts)


def build_roles_section(roles_data, cache_estimate=None):
    """Render horizontal bars for token usage by role (always visible)."""
    if not roles_data:
        return '<p style="color:#8892a4">No role data in this period.</p>'

    lookups = _cache_lookups(cache_estimate or {})
    max_total = 0
    for d in roles_data:
        name = (d.get('role') or 'unknown')[:20]
        lookup = lookups['by_role'].get(name)
        if lookup:
            eff = _effective_total(lookup['uncached_input'], lookup['output'], lookup['reasoning'])
            max_total = max(max_total, eff)
        else:
            tot = d.get('total_tokens_raw', 0) or 0
            max_total = max(max_total, tot)

    html_parts = []
    for d in roles_data:
        name = (d.get('role') or 'unknown')[:20]
        lookup = lookups['by_role'].get(name)

        if lookup:
            eff = _effective_total(lookup['uncached_input'], lookup['output'], lookup['reasoning'])
        else:
            eff = d.get('total_tokens_raw', 0) or 0

        sess = d.get('sessions', 0) or 0
        width_pct = (eff / max_total * 100) if max_total else 0

        html_parts.append(f'<div class="h-bar-row">')
        html_parts.append(f'  <span class="h-bar-label" title="{name}">{name}</span>')
        html_parts.append(f'  <div class="h-bar-track"><div class="h-bar-fill" style="width:{max(width_pct, 2)}%"></div></div>')
        html_parts.append(f'  <span class="h-bar-value">{fmt(eff)} ({sess})</span>')
        html_parts.append(f'</div>')

    return '\n'.join(html_parts)


def build_cross_tab(cross_tab_data):
    """Render model x role breakdown table (collapsible)."""
    if not cross_tab_data:
        return '<p style="color:#8892a4">No cross-tab data in this period.</p>'

    html = '<table><thead><tr><th>Model</th><th>Role</th><th class="num">Sessions</th><th class="num">Effective Tokens</th></tr></thead><tbody>'
    for d in cross_tab_data:
        model = (d.get('model') or 'unknown')[:30]
        role = (d.get('role') or 'unknown')[:20]
        sess = d.get('sessions', 0) or 0
        tot = d.get('total_tokens_raw', 0) or 0
        html += f'<tr><td>{model}</td><td>{role}</td><td class="num">{sess}</td><td class="num">{fmt(tot)}</td></tr>'
    html += '</tbody></table>'
    return html


def build_daily_trend_section(ts_data):
    """Render daily token trend chart.

    Stacked area chart showing input/output/reasoning over time using cache-adjusted values.
    """
    if not ts_data:
        return '<p style="color:#8892a4">No daily token data in this period.</p>'

    rows = _build_ts_rows(ts_data)
    return render_stacked_area(rows)



def build_code_impact_cards(ts_data):
    """Render code impact cards only (no charts)."""
    if not ts_data:
        return ''

    rows = _build_ts_rows(ts_data)
    total_commits = sum(r[7] for r in rows)
    total_adds = sum(r[8] for r in rows)
    total_tokens = sum(r[1] for r in rows)
    total_reasoning = sum(r[4] for r in rows)

    avg_tok_per_commit = round(total_tokens / total_commits) if total_commits else 0
    avg_tok_per_line = round(total_tokens / total_adds) if total_adds else 0
    reasoning_pct_total = f'{total_reasoning/total_tokens*100:.1f}%' if total_tokens > 0 else '\u2014'
    peak_tpc = max((r[10] for r in rows), default=0)

    html_parts = []
    cache_note = " (est. effective)" if any(r.get('cache_hit_pct', 0) > 0 for r in ts_data) else ""
    html_parts.append(f'<p style="color:#8892a4; margin-bottom:1rem; font-size:0.9rem;">{fmt(total_tokens)} tokens consumed across {total_commits:,} commits producing {total_adds:,} lines of code.{cache_note}</p>')

    html_parts.append('<div class="impact-grid">')
    html_parts.append(f'  <div class="impact-card"><div class="impact-value">{total_commits}</div><div class="impact-label">Total Commits</div></div>')
    html_parts.append(f'  <div class="impact-card"><div class="impact-value">{fmt(total_adds)}</div><div class="impact-label">Lines Added</div></div>')
    html_parts.append(f'  <div class="impact-card ratio"><div class="impact-value">{fmt(avg_tok_per_commit)}</div><div class="impact-label">Avg Tokens / Commit</div></div>')
    html_parts.append(f'  <div class="impact-card ratio"><div class="impact-value">{fmt(avg_tok_per_line)}</div><div class="impact-label">Avg Tokens / Line Added</div></div>')
    html_parts.append(f'  <div class="impact-card"><div class="impact-value">{reasoning_pct_total}</div><div class="impact-label">Reasoning %</div></div>')
    html_parts.append(f'  <div class="impact-card"><div class="impact-value">{fmt(peak_tpc)}</div><div class="impact-label">Peak Tok / Commit</div></div>')
    html_parts.append('</div>')

    return '\n'.join(html_parts)


def build_code_impact_charts(ts_data):
    """Render code impact charts only (no cards)."""
    if not ts_data:
        return ''

    rows = _build_ts_rows(ts_data)
    html_parts = []

    html_parts.append('<h3 id="chart-tokens-vs-commits" class="chart-title">Tokens vs. Commits</h3>')
    if rows:
        html_parts.append(render_tokens_vs_commits(rows))

    html_parts.append('<h3 id="chart-efficiency" class="chart-title">Tokens per Commit vs. per Line Added</h3>')
    if rows:
        html_parts.append(render_efficiency(rows))

    return '\n'.join(html_parts)


def build_cumulative_sections(ts_data):
    """Render cumulative efficiency curves (collapsible)."""
    if not ts_data:
        return '<p style="color:#8892a4">No data for efficiency curves.</p>'

    html_parts = []

    # Cumulative tokens vs. cumulative lines added (all files)
    html_parts.append('<h3 class="chart-title">Cumulative Tokens vs. Cumulative Lines Added</h3>')
    html_parts.append(render_cumulative_efficiency(ts_data, 'cum_all', 'Lines Added'))

    # Cumulative cost over time
    has_cost = any(r.get('cost_cheap', 0) > 0 for r in ts_data)
    if has_cost:
        html_parts.append('<h3 class="chart-title">Cumulative Estimated Cost</h3>')
        html_parts.append(render_cumulative_cost(ts_data))

    # Rolling 7-day tokens per commit trend
    html_parts.append('<h3 class="chart-title">Rolling 7-Day Tokens per Commit Trend</h3>')
    html_parts.append(render_rolling_tok_per_commit(ts_data))

    return '\n'.join(html_parts)


def build_agent_category_section(ts_data):
    """Render agent category breakdown (collapsible).

    Daily stacked bar chart: build / review / plan / explore / other tokens.
    Weekly agent breakdown table.
    """
    if not ts_data:
        return '<p style="color:#8892a4">No daily agent data.</p>'

    html_parts = []

    # Stacked bar chart by agent category
    html_parts.append('<h3 class="chart-title">Daily Token Breakdown by Role Category</h3>')
    html_parts.append(render_daily_agent_stacked(ts_data))

    return '\n'.join(html_parts)


def build_cache_section(cache_estimate):
    """Render cache approximation section (collapsible)."""
    if not cache_estimate:
        return ''

    agg = cache_estimate.get('aggregate', {})
    if not agg:
        return ''

    raw_total = agg.get('raw_total', 0) or 0
    effective_total = agg.get('effective_total', 0) or 0
    cached = agg.get('estimated_cached_input', 0) or 0
    uncached = agg.get('estimated_uncached_input', 0) or 0
    hit_pct = agg.get('cache_hit_pct', 0) or 0
    sessions_count = agg.get('sessions', 0) or 0
    turns = agg.get('total_turns', 0) or 0
    savings = raw_total - effective_total
    savings_pct = round(100.0 * savings / raw_total, 1) if raw_total > 0 else 0

    html_parts = []
    html_parts.append('<p style="color:#8892a4; font-size:0.85rem; margin-bottom:1rem;">')
    html_parts.append('Estimated impact if the LLM provider supported prefix caching. ')
    html_parts.append('Computed from per-message token data: each turn re-sends prior context, ')
    html_parts.append('but only the delta vs. the previous turn is truly new. ')
    html_parts.append(f'Analyzed {sessions_count} sessions across {turns} turns.')
    html_parts.append('</p>')

    # Metric cards
    html_parts.append('<div class="impact-grid">')
    html_parts.append(f'  <div class="impact-card"><div class="impact-value">{fmt(uncached)}</div><div class="impact-label">Est. Uncached Input</div></div>')
    html_parts.append(f'  <div class="impact-card"><div class="impact-value">{fmt(cached)}</div><div class="impact-label">Est. Cached Input</div></div>')
    html_parts.append(f'  <div class="impact-card ratio"><div class="impact-value">{hit_pct}%</div><div class="impact-label">Cache Hit Rate</div></div>')
    html_parts.append(f'  <div class="impact-card"><div class="impact-value">{fmt(effective_total)}</div><div class="impact-label">Effective Total (w/cache)</div></div>')
    html_parts.append(f'  <div class="impact-card"><div class="impact-value">{savings_pct}%</div><div class="impact-label">Tokens Saved</div></div>')
    html_parts.append('</div>')

    # By model table
    by_model = cache_estimate.get('by_model', [])
    if by_model:
        html_parts.append('<h3 class="chart-title">Cache Impact by Model</h3>')
        html_parts.append('<table><thead><tr><th>Model</th><th class="num">Sessions</th><th class="num">Raw Input</th><th class="num">Uncached</th><th class="num">Cached</th><th class="num">Hit %</th></tr></thead><tbody>')
        for r in by_model:
            model = (r.get('model') or 'unknown').replace('_', '-').replace('-', '-')[:30]
            html_parts.append(
                f'<tr><td>{model}</td>'
                f'<td class="num">{r.get("sessions", 0)}</td>'
                f'<td class="num">{fmt(r.get("total_input_raw", 0))}</td>'
                f'<td class="num">{fmt(r.get("estimated_uncached_input", 0))}</td>'
                f'<td class="num">{fmt(r.get("estimated_cached_input", 0))}</td>'
                f'<td class="num">{r.get("cache_hit_pct", 0)}%</td></tr>'
            )
        html_parts.append('</tbody></table>')

    # By role table
    by_role = cache_estimate.get('by_role', [])
    if by_role:
        html_parts.append('<h3 class="chart-title">Cache Impact by Role</h3>')
        html_parts.append('<table><thead><tr><th>Role</th><th class="num">Sessions</th><th class="num">Raw Input</th><th class="num">Uncached</th><th class="num">Cached</th><th class="num">Hit %</th></tr></thead><tbody>')
        for r in by_role:
            role = (r.get('value') or 'unknown')[:20]
            html_parts.append(
                f'<tr><td>{role}</td>'
                f'<td class="num">{r.get("sessions", 0)}</td>'
                f'<td class="num">{fmt(r.get("total_input_raw", 0))}</td>'
                f'<td class="num">{fmt(r.get("estimated_uncached_input", 0))}</td>'
                f'<td class="num">{fmt(r.get("estimated_cached_input", 0))}</td>'
                f'<td class="num">{r.get("cache_hit_pct", 0)}%</td></tr>'
            )
        html_parts.append('</tbody></table>')

    # By day table
    by_day = cache_estimate.get('by_day', [])
    if by_day:
        html_parts.append('<h3 class="chart-title">Cache Impact by Day</h3>')
        html_parts.append('<table><thead><tr><th>Date</th><th class="num">Sessions</th><th class="num">Raw Input</th><th class="num">Uncached</th><th class="num">Cached</th><th class="num">Hit %</th></tr></thead><tbody>')
        for r in by_day:
            html_parts.append(
                f'<tr><td>{r.get("key", "") or r.get("day", "")}</td>'
                f'<td class="num">{r.get("sessions", 0)}</td>'
                f'<td class="num">{fmt(r.get("total_input_raw", 0))}</td>'
                f'<td class="num">{fmt(r.get("estimated_uncached_input", 0))}</td>'
                f'<td class="num">{fmt(r.get("estimated_cached_input", 0))}</td>'
                f'<td class="num">{r.get("cache_hit_pct", 0)}%</td></tr>'
            )
        html_parts.append('</tbody></table>')

    return '\n'.join(html_parts)


def build_cache_cards(cache_estimate):
    """Render cache impact cards only (no tables)."""
    if not cache_estimate:
        return ''

    agg = cache_estimate.get('aggregate', {})
    if not agg:
        return ''

    raw_total = agg.get('raw_total', 0) or 0
    effective_total = agg.get('effective_total', 0) or 0
    cached = agg.get('estimated_cached_input', 0) or 0
    uncached = agg.get('estimated_uncached_input', 0) or 0
    hit_pct = agg.get('cache_hit_pct', 0) or 0
    sessions_count = agg.get('sessions', 0) or 0
    turns = agg.get('total_turns', 0) or 0
    savings = raw_total - effective_total
    savings_pct = round(100.0 * savings / raw_total, 1) if raw_total > 0 else 0

    html_parts = []
    html_parts.append('<p style="color:#8892a4; font-size:0.85rem; margin-bottom:1rem;">')
    html_parts.append('Estimated impact if the LLM provider supported prefix caching. ')
    html_parts.append('Computed from per-message token data: each turn re-sends prior context, ')
    html_parts.append('but only the delta vs. the previous turn is truly new. ')
    html_parts.append(f'Analyzed {sessions_count} sessions across {turns} turns.')
    html_parts.append('</p>')

    html_parts.append('<div class="impact-grid">')
    html_parts.append(f'  <div class="impact-card"><div class="impact-value">{fmt(uncached)}</div><div class="impact-label">Est. Uncached Input</div></div>')
    html_parts.append(f'  <div class="impact-card"><div class="impact-value">{fmt(cached)}</div><div class="impact-label">Est. Cached Input</div></div>')
    html_parts.append(f'  <div class="impact-card ratio"><div class="impact-value">{hit_pct}%</div><div class="impact-label">Cache Hit Rate</div></div>')
    html_parts.append(f'  <div class="impact-card"><div class="impact-value">{fmt(effective_total)}</div><div class="impact-label">Effective Total (w/cache)</div></div>')
    html_parts.append(f'  <div class="impact-card"><div class="impact-value">{savings_pct}%</div><div class="impact-label">Tokens Saved</div></div>')
    html_parts.append('</div>')

    return '\n'.join(html_parts)


def build_cache_tables(cache_estimate):
    """Render cache approximation tables only (no cards)."""
    if not cache_estimate:
        return ''

    html_parts = []

    by_model = cache_estimate.get('by_model', [])
    if by_model:
        html_parts.append('<h3 class="chart-title">Cache Impact by Model</h3>')
        html_parts.append('<table><thead><tr><th>Model</th><th class="num">Sessions</th><th class="num">Raw Input</th><th class="num">Uncached</th><th class="num">Cached</th><th class="num">Hit %</th></tr></thead><tbody>')
        for r in by_model:
            model = (r.get('model') or 'unknown').replace('_', '-').replace('-', '-')[:30]
            html_parts.append(
                f'<tr><td>{model}</td>'
                f'<td class="num">{r.get("sessions", 0)}</td>'
                f'<td class="num">{fmt(r.get("total_input_raw", 0))}</td>'
                f'<td class="num">{fmt(r.get("estimated_uncached_input", 0))}</td>'
                f'<td class="num">{fmt(r.get("estimated_cached_input", 0))}</td>'
                f'<td class="num">{r.get("cache_hit_pct", 0)}%</td></tr>'
            )
        html_parts.append('</tbody></table>')

    by_role = cache_estimate.get('by_role', [])
    if by_role:
        html_parts.append('<h3 class="chart-title">Cache Impact by Role</h3>')
        html_parts.append('<table><thead><tr><th>Role</th><th class="num">Sessions</th><th class="num">Raw Input</th><th class="num">Uncached</th><th class="num">Cached</th><th class="num">Hit %</th></tr></thead><tbody>')
        for r in by_role:
            role = (r.get('value') or 'unknown')[:20]
            html_parts.append(
                f'<tr><td>{role}</td>'
                f'<td class="num">{r.get("sessions", 0)}</td>'
                f'<td class="num">{fmt(r.get("total_input_raw", 0))}</td>'
                f'<td class="num">{fmt(r.get("estimated_uncached_input", 0))}</td>'
                f'<td class="num">{fmt(r.get("estimated_cached_input", 0))}</td>'
                f'<td class="num">{r.get("cache_hit_pct", 0)}%</td></tr>'
            )
        html_parts.append('</tbody></table>')

    by_day = cache_estimate.get('by_day', [])
    if by_day:
        html_parts.append('<h3 class="chart-title">Cache Impact by Day</h3>')
        html_parts.append('<table><thead><tr><th>Date</th><th class="num">Sessions</th><th class="num">Raw Input</th><th class="num">Uncached</th><th class="num">Cached</th><th class="num">Hit %</th></tr></thead><tbody>')
        for r in by_day:
            html_parts.append(
                f'<tr><td>{r.get("key", "") or r.get("day", "")}</td>'
                f'<td class="num">{r.get("sessions", 0)}</td>'
                f'<td class="num">{fmt(r.get("total_input_raw", 0))}</td>'
                f'<td class="num">{fmt(r.get("estimated_uncached_input", 0))}</td>'
                f'<td class="num">{fmt(r.get("estimated_cached_input", 0))}</td>'
                f'<td class="num">{r.get("cache_hit_pct", 0)}%</td></tr>'
            )
        html_parts.append('</tbody></table>')

    return '\n'.join(html_parts)


def build_cost_analysis_section(data, ts_data):
    """Render cost analysis section with per-model pricing (collapsible).

    Shows actual cost ($0, all local) vs cloud-equivalent cost, cache savings
    in dollar amounts, and per-model cost breakdown.
    """
    mp = data.get('model_pricing', {})
    models_with_cost = data.get('models_with_cost', [])
    cache_hit = data.get('summary', {}).get('cache_hit_pct', 0) or 0

    if not mp and not models_with_cost:
        return ''

    total_raw = mp.get('total_raw_cost', 0) or 0
    total_adj = mp.get('total_cache_adjusted_cost', 0) or 0
    total_savings = mp.get('total_cache_savings', 0) or 0

    html_parts = []

    # Actual cost annotation
    html_parts.append('<p style="color:#8892a4; font-size:0.85rem; margin-bottom:1rem;">')
    html_parts.append('All models run locally via LM Studio — actual API cost is $0. ')
    html_parts.append('Cloud-equivalent costs below show what these sessions would cost ')
    html_parts.append('if run through commercial APIs at current per-model pricing.')
    html_parts.append('</p>')

    # Cost metric cards
    html_parts.append('<div class="impact-grid">')
    html_parts.append(f'  <div class="impact-card" style="border-color:#8892a4;background:rgba(136,146,164,0.06);"><div class="impact-value" style="color:#8892a4;">$0.00</div><div class="impact-label">Actual Cost</div><div style="font-size:0.65rem;color:#8892a4;margin-top:0.2rem;">Local execution only &middot; no API fees</div></div>')
    html_parts.append(f'  <div class="impact-card cost"><div class="impact-value">${total_raw:,.2f}</div><div class="impact-label">Cloud-Equivalent (Raw)</div></div>')
    html_parts.append(f'  <div class="impact-card" style="border-color:#4db6ac;background:rgba(77,182,172,0.06);"><div class="impact-value" style="color:#4db6ac;">${total_adj:,.2f}</div><div class="impact-label">Cloud-Equivalent (w/Cache)</div></div>')
    html_parts.append(f'  <div class="impact-card ratio"><div class="impact-value">${total_savings:,.2f}</div><div class="impact-label">Saved by Context Caching</div></div>')
    html_parts.append('</div>')

    # Cache savings note
    if total_savings > 0 and total_raw > 0:
        savings_pct = round(100.0 * total_savings / total_raw, 1)
        html_parts.append(f'<p style="color:#4db6ac; font-size:0.85rem; margin-bottom:1.5rem;">${total_savings:,.2f} saved via prompt context caching ({savings_pct}% reduction, {cache_hit}% cache hit rate).</p>')

    # Per-model cost table
    if models_with_cost:
        html_parts.append('<h3 class="chart-title">Cloud-Equivalent Cost by Model</h3>')
        html_parts.append('<table><thead><tr><th>Model</th><th class="num">Sessions</th><th class="num">Input Tokens</th><th class="num">Output Tokens</th><th class="num">Raw Cost</th><th class="num">w/Cache Cost</th><th class="num">Cache Savings</th></tr></thead><tbody>')
        for m in sorted(models_with_cost, key=lambda x: x.get('raw_cost', 0), reverse=True):
            model = (m.get('model') or 'unknown')[:30]
            sess = m.get('sessions', 0) or 0
            inp = m.get('input_tokens_raw', 0) or 0
            out_ = m.get('output_tokens_raw', 0) or 0
            rea = m.get('reasoning_tokens_raw', 0) or 0
            raw_c = m.get('raw_cost', 0) or 0
            adj_c = m.get('cache_adjusted_cost', 0) or 0
            sav = m.get('cache_savings', 0) or 0
            html_parts.append(
                f'<tr><td style="font-size:0.75rem">{model}</td>'
                f'<td class="num">{sess}</td>'
                f'<td class="num">{fmt(inp)}</td>'
                f'<td class="num">{fmt(out_ + rea)}</td>'
                f'<td class="num">${raw_c:,.2f}</td>'
                f'<td class="num" style="color:#4db6ac;">${adj_c:,.2f}</td>'
                f'<td class="num" style="color:#4db6ac;">${sav:,.2f}</td></tr>'
            )
        html_parts.append('</tbody></table>')

        # Assumed rates table
        html_parts.append('<h3 class="chart-title">Assumed Pricing Rates</h3>')
        html_parts.append('<table><thead><tr><th>Model</th><th class="num">Input ($/M)</th><th class="num">Output ($/M)</th><th class="num">Cached Input ($/M)</th></tr></thead><tbody>')
        for model_name, rates in MODEL_PRICING.items():
            html_parts.append(
                f'<tr><td style="font-size:0.75rem">{model_name}</td>'
                f'<td class="num">${rates["input"]:.3f}</td>'
                f'<td class="num">${rates["output"]:.3f}</td>'
                f'<td class="num">${rates["cached_input"]:.3f}</td></tr>'
            )
        html_parts.append('</tbody></table>')
        html_parts.append('<p style="color:#8892a4; font-size:0.7rem; margin-top:0.5rem;">Per-model rates above are used for detailed cost calculations. Flat-rate tiers below are used for summary estimates.</p>')
        html_parts.append('<table><thead><tr><th>Tier</th><th class="num">Input ($/M)</th><th class="num">Output ($/M)</th><th class="num">Cached Input ($/M)</th></tr></thead><tbody>')
        for tier_name, rates in FLAT_RATES.items():
            html_parts.append(
                f'<tr><td>{tier_name.title()}</td>'
                f'<td class="num">${rates["input"]:.2f}</td>'
                f'<td class="num">${rates["output"]:.2f}</td>'
                f'<td class="num">${rates["cached_input"]:.2f}</td></tr>'
            )
        html_parts.append('</tbody></table>')

    # Cumulative cost chart (dual-axis: actual $0 flat line vs cloud-equivalent)
    if ts_data:
        html_parts.append('<h3 class="chart-title">Estimated Cloud Cost Over Time (Hypothetical)</h3>')
        html_parts.append(render_cumulative_cost(ts_data))

    return '\n'.join(html_parts)


def build_productivity_cards(data):
    """Render productivity overview cards only."""
    prod = data.get('productivity', {})
    if isinstance(prod, list) and len(prod) > 0:
        prod = prod[0]
    elif not prod:
        prod = {}

    build_prod = data.get('build_productivity', {})
    if isinstance(build_prod, list) and len(build_prod) > 0:
        build_prod = build_prod[0]
    elif not build_prod:
        build_prod = {}

    total_sessions = prod.get('total_sessions', 0) or 0
    with_changes = prod.get('sessions_with_changes', 0) or 0
    pct = prod.get('pct_with_changes', 0) or 0

    build_total = build_prod.get('total_build_sessions', 0) or 0
    build_productive = build_prod.get('productive_sessions', 0) or 0
    build_pct = build_prod.get('pct_productive', 0) or 0
    build_tokens = build_prod.get('total_tokens', 0) or 0
    zero_change_tokens = build_prod.get('zero_change_tokens', 0) or 0
    zero_pct = round(100.0 * zero_change_tokens / build_tokens, 1) if build_tokens > 0 else 0

    html_parts = []
    html_parts.append('<div class="impact-grid">')
    html_parts.append(f'<div class="impact-card"><div class="impact-value">{pct}%</div><div class="impact-label">Sessions w/ File Changes</div></div>')
    html_parts.append(f'<div class="impact-card"><div class="impact-value">{with_changes}/{total_sessions}</div><div class="impact-label">Productive Sessions</div></div>')
    html_parts.append(f'<div class="impact-card ratio"><div class="impact-value">{build_pct}%</div><div class="impact-label">Build Agent Productive</div></div>')
    html_parts.append(f'<div class="impact-card"><div class="impact-value">{zero_pct}%</div><div class="impact-label">Build Tokens w/ Zero Changes</div></div>')
    html_parts.append('</div>')

    return '\n'.join(html_parts)


def build_productivity_notes(data):
    """Render productivity overview notes paragraph."""
    merged = data.get('timeseries', [])
    zero_commit_high_tok = [r for r in merged if r.get('commits', 0) == 0 and r.get('total_effective', 0) > 1_000_000]
    zero_commit_tok_total = sum(r['total_effective'] for r in zero_commit_high_tok)

    notes = '<p style="color:#8892a4; font-size:0.82rem; margin-bottom:1rem;"><strong>Notes:</strong> '
    notes += 'Pi does not record per-session file changes, so "sessions w/ file changes" '
    notes += 'counts sessions on days that have git commits (date-matched, an estimate). '
    notes += 'Most sessions are exploratory, research, or cross-session coordination. '
    notes += 'Build-role productive sessions are estimated from token-ratio approximation '
    notes += '(build tokens / total effective tokens per day). '
    if zero_commit_high_tok:
        notes += f'{len(zero_commit_high_tok)} days had {fmt(zero_commit_tok_total)} tokens with zero commits '
        notes += '(e.g., research, debugging, cross-session coordination). '
    notes += '</p>'
    return notes


def build_session_summaries_section(data):
    """Render the [docs directory]/sessions summary join (purpose/outcome/role)."""
    prod = data.get('productivity', [])
    if isinstance(prod, list) and prod:
        summaries = prod[0].get('session_summaries', {})
    else:
        summaries = data.get('session_summaries', {})
    if not summaries or not summaries.get('total'):
        return ''

    def _table(title, mapping):
        if not mapping:
            return ''
        parts = [f'<h3 class="chart-title">{title}</h3>',
                 '<table><thead><tr><th>Category</th><th class="num">Sessions</th></tr></thead><tbody>']
        for k, v in sorted(mapping.items(), key=lambda kv: -kv[1]):
            parts.append(f'<tr><td>{k}</td><td class="num">{v}</td></tr>')
        parts.append('</tbody></table>')
        return '\n'.join(parts)

    html_parts = [f'<p style="color:#8892a4; font-size:0.85rem; margin-bottom:1rem;">'
                  f'{summaries["total"]} human-curated session summaries in [docs directory]/sessions 'f'(date-filtered).</p>']
    for title, key in (('Summaries by Purpose', 'by_purpose'),
                       ('Summaries by Outcome', 'by_outcome'),
                       ('Summaries by Role', 'by_role')):
        t = _table(title, summaries.get(key, {}))
        if t:
            html_parts.append(t)
    return '\n'.join(html_parts)


def build_subagent_runs_section(subagent_runs):
    """Render subagent run attribution (collapsible).

    Pi's subagent tool persists per-run usage in the parent session's tool
    results, so every delegated run is attributable to its agent and model.
    """
    if not subagent_runs or not subagent_runs.get('total_runs'):
        return ''

    total_runs = subagent_runs.get('total_runs', 0)
    total_turns = subagent_runs.get('total_turns', 0)
    total_input = subagent_runs.get('total_input', 0)
    total_output = subagent_runs.get('total_output', 0)
    total_cost = subagent_runs.get('actual_cost', 0.0)

    html_parts = []
    html_parts.append('<p style="color:#8892a4; font-size:0.85rem; margin-bottom:1rem;">'
                      f'{total_runs} subagent run(s) across {total_turns} LLM turns, '
                      f'attributed from parent-session <code>subagent</code> tool results '
                      f'({fmt(total_input + total_output)} tokens, actual cost ${total_cost:,.2f}).</p>')

    by_agent = subagent_runs.get('by_agent', [])
    if by_agent:
        html_parts.append('<table><thead><tr><th>Agent</th><th class="num">Runs</th><th class="num">Turns</th><th class="num">Input</th><th class="num">Output</th><th class="num">Cost</th><th>Models</th></tr></thead><tbody>')
        for a in by_agent:
            models = ', '.join(a.get('models', []))
            if len(models) > 48:
                models = models[:45] + '...'
            html_parts.append(
                f'<tr><td>{a.get("agent", "")}</td>'
                f'<td class="num">{a.get("runs", 0)}</td>'
                f'<td class="num">{a.get("turns", 0)}</td>'
                f'<td class="num">{fmt(a.get("total_input", 0))}</td>'
                f'<td class="num">{fmt(a.get("total_output", 0))}</td>'
                f'<td class="num">${a.get("total_cost", 0.0):,.2f}</td>'
                f'<td style="font-size:0.72rem">{models}</td></tr>'
            )
        html_parts.append('</tbody></table>')

    runs = subagent_runs.get('runs', [])[-25:]
    if runs:
        html_parts.append('<h3 class="chart-title">Most Recent Runs</h3>')
        html_parts.append('<table><thead><tr><th>Date</th><th>Agent</th><th>Model</th><th class="num">Turns</th><th class="num">Context</th><th class="num">Input</th><th class="num">Output</th><th>Status</th></tr></thead><tbody>')
        for r in runs:
            status = r.get('stop_reason', '') or 'ok'
            status_cell = status if status == 'ok' else f'<span style="color:#f5a623">{status}</span>'
            model = (r.get('model') or '')[:40]
            html_parts.append(
                f'<tr><td>{r.get("day", "")}</td><td>{r.get("agent", "")}</td>'
                f'<td style="font-size:0.72rem">{model}</td>'
                f'<td class="num">{r.get("turns", 0)}</td>'
                f'<td class="num">{fmt(r.get("context_tokens", 0))}</td>'
                f'<td class="num">{fmt(r.get("input", 0))}</td>'
                f'<td class="num">{fmt(r.get("output", 0))}</td>'
                f'<td>{status_cell}</td></tr>'
            )
        html_parts.append('</tbody></table>')

    return '\n'.join(html_parts)


def build_phase_table(phases):
    """Render phase summary table."""
    if not phases:
        return '<p style="color:#8892a4">No phase data.</p>'

    html = '<table><thead><tr><th>Phase</th><th>Dates</th><th class="num">Effective Tokens</th><th class="num">Sessions</th><th class="num">Commits</th><th class="num">Lines Added</th><th class="num">Test+</th><th class="num">Tok/Commit</th><th class="num">Tok/Line</th><th class="num">Test%</th></tr></thead><tbody>'
    for p in phases:
        date_range = f"{p.get('start', '')}\u2013{p.get('end', '')}"
        html += (
            f'<tr><td>{p["name"]}</td><td>{date_range}</td>'
            f'<td class="num">{fmt(p.get("tokens", 0))}</td>'
            f'<td class="num">{p.get("sessions", 0)}</td>'
            f'<td class="num">{p.get("commits", 0)}</td>'
            f'<td class="num">{fmt(p.get("adds", 0))}</td>'
            f'<td class="num">{fmt(p.get("test_adds", 0))}</td>'
            f'<td class="num">{fmt(p.get("tok_per_commit", 0))}</td>'
            f'<td class="num">{fmt(p.get("tok_per_line", 0))}</td>'
            f'<td class="num">{p.get("test_pct", 0)}%</td></tr>'
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


def build_top_sessions_section(top_sessions_data, cache_estimate=None):
    """Render top sessions table (collapsible)."""
    if not top_sessions_data:
        return '<p style="color:#8892a4">No sessions in this period.</p>'

    lookups = _cache_lookups(cache_estimate or {})
    model_ratios = {}
    for m_name, m_cache in lookups['by_model'].items():
        eff = _effective_total(m_cache['uncached_input'], m_cache['output'], m_cache['reasoning'])
        model_ratios[m_name] = eff

    html = '<table><thead><tr><th>#</th><th>Role</th><th>Model</th><th>Title</th><th class="num">Tokens (raw)</th></tr></thead><tbody>'
    for i, d in enumerate(top_sessions_data, 1):
        role = (d.get('role') or 'main')[:20]
        model_raw = d.get('model') or 'unknown'
        title = str(d.get('title', ''))[:60]
        raw_tot = d.get('tokens', 0) or d.get('total_tokens', 0) or 0

        html += f'<tr><td>{i}</td><td>{role}</td><td style="font-size:0.75rem">{model_raw}</td><td>{title}</td><td class="num">{fmt(raw_tot)}</td></tr>'
    html += '</tbody></table>'
    return html


# ── Shared helpers ───────────────────────────────────────────────────────────

def _cache_lookups(cache_estimate):
    """Build lookup maps from cache estimate data for quick access by section."""
    lookups = {'by_model': {}, 'by_role': {}, 'by_day': {}}
    if not cache_estimate:
        return lookups

    for entry in cache_estimate.get('by_model', []):
        name = (entry.get('key') or entry.get('model') or 'unknown')[:30]
        lookups['by_model'][name] = {
            'uncached_input': entry.get('estimated_uncached_input', 0) or 0,
            'output':         entry.get('total_output', 0) or 0,
            'reasoning':      entry.get('total_reasoning', 0) or 0,
        }

    for entry in cache_estimate.get('by_role', []):
        name = (entry.get('key') or entry.get('role') or 'unknown')[:20]
        lookups['by_role'][name] = {
            'uncached_input': entry.get('estimated_uncached_input', 0) or 0,
            'output':         entry.get('total_output', 0) or 0,
            'reasoning':      entry.get('total_reasoning', 0) or 0,
        }

    for entry in cache_estimate.get('by_day', []):
        day = entry.get('day', '') or entry.get('key', '')
        lookups['by_day'][day] = {
            'uncached_input': entry.get('estimated_uncached_input', 0) or 0,
            'output':         entry.get('total_output', 0) or 0,
            'reasoning':      entry.get('total_reasoning', 0) or 0,
        }

    return lookups


def _effective_total(uncached_in, output, reasoning):
    """Compute effective total from cache-adjusted input plus output and reasoning."""
    return (uncached_in or 0) + (output or 0) + (reasoning or 0)


def _build_ts_rows(ts_data):
    """Convert timeseries dict rows to tuple format for chart rendering."""
    rows = []
    for r in ts_data:
        eff_total = r.get('total_effective', 0) or 0
        inp = r.get('input_uncached', r.get('input_tokens', 0)) or 0
        out_ = r.get('output_tokens', 0) or 0
        rea = r.get('reasoning_tokens', 0) or 0
        sess = r.get('sessions', 0) or 0
        commits = r.get('commits', 0)
        adds = r.get('adds', 0)
        dels = r.get('dels', 0)
        tpc = r.get('tok_per_commit', 0) or 0
        tpl = r.get('tok_per_line', 0) or 0
        rea_pct = f'{rea/eff_total*100:.1f}%' if eff_total > 0 else '\u2014'
        inp_raw = r.get('input_tokens_raw', 0) or 0
        rows.append((r['date'], eff_total, inp, out_, rea, sess, commits, commits, adds, dels, tpc, tpl, rea_pct, inp_raw))
    return rows


# ── HTML template helpers ────────────────────────────────────────────────────

def collapsible_section(title, content_html, open=True):
    """Wrap content in a collapsible <details> section with smooth styling."""
    open_attr = ' open' if open else ''
    return f'''<details class="collapsible-section"{open_attr}>
  <summary onclick="toggleDetails(this)">{title} \u25BE</summary>
  <div class="collapsible-content">
    {content_html}
  </div>
</details>'''


def always_visible(title, content_html):
    """Render a section that is always visible (not collapsible)."""
    return f'''<div class="always-visible">
  <h2 id="{title.lower().replace(' ', '-')}">{title}</h2>
  {content_html}
</div>'''


def subsection(title, content_html):
    """Render a subsection with h3 heading inside a collapsible section."""
    slug = title.lower().replace(' ', '-').replace('\u00d7', '-').replace('&', '')
    return f'''<div class="always-visible">
  <h3 id="{slug}" class="chart-title">{title}</h3>
  {content_html}
</div>'''


def render_html(data: dict) -> str:
    """Render consolidated HTML report from data dictionary.

    Args:
        data: Merged report data structure.

    Returns:
        HTML string.
    """
    meta = data.get('meta', {})
    ts_data = data.get('timeseries', [])
    cache_estimate = data.get('cache_estimate', {})
    weekly = data.get('weekly', [])
    agents_detailed = data.get('agents_detailed', [])

    # ── Build HTML parts ────────────────────────────────────────────────
    html_parts = []

    # Header
    html_parts.append(f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{meta.get('title', '[ProjectName] — LLM Usage & Value Report')}</title>
<style>
  :root {{
    --bg: #1a1a2e; --card-bg: #16213e; --border: #0f3460;
    --text: #e0e0e0; --muted: #8892a4; --accent: #4fc3f7;
    --input-color: #4fc3f7; --output-color: #4db6ac; --reasoning-color: #ba68c8;
    --bar-bg: rgba(255,255,255,0.06);
  }}
  * {{ margin: 0; padding: 0; box-sizing: border-box; }}
  body {{ background: var(--bg); color: var(--text); font-family: -apple-system, BlinkMacSystemFont, 'SF Mono', Menlo, monospace; line-height: 1.5; padding: 2rem; max-width: 1200px; margin: 0 auto; }}

  h1 {{ font-size: 1.8rem; color: var(--accent); margin-bottom: 0.3rem; letter-spacing: -0.5px; }}
  h2 {{ font-size: 1.2rem; color: var(--muted); margin-top: 2rem; margin-bottom: 1rem; padding-bottom: 0.4rem; border-bottom: 1px solid var(--border); }}
  .subtitle {{ color: var(--muted); font-size: 0.85rem; margin-bottom: 2rem; }}

  .metrics-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 1rem; margin-bottom: 2rem; }}
  .metric-card {{ background: var(--card-bg); border: 1px solid var(--border); border-radius: 8px; padding: 1.2rem; text-align: center; }}
  .metric-value {{ font-size: 1.6rem; font-weight: 700; color: var(--accent); letter-spacing: -1px; }}
  .metric-label {{ font-size: 0.75rem; color: var(--muted); text-transform: uppercase; margin-top: 0.3rem; letter-spacing: 0.5px; }}
  .metric-card.cost {{ border-color: #f5a623; background: rgba(245,166,35,0.06); }}
  .metric-card.cost .metric-value {{ color: #f5a623; }}

  .impact-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 1.5rem; }}
  .impact-card {{ background: var(--card-bg); border: 1px solid var(--border); border-radius: 8px; padding: 1.2rem; text-align: center; }}
  .impact-value {{ font-size: 1.8rem; font-weight: 700; color: #4db6ac; letter-spacing: -1px; }}
  .impact-label {{ font-size: 0.72rem; color: var(--muted); text-transform: uppercase; margin-top: 0.3rem; letter-spacing: 0.5px; }}
  .impact-card.ratio {{ border-color: #4db6ac; background: rgba(77, 182, 172, 0.06); }}
  .impact-card.ratio .impact-value {{ color: #4db6ac; font-size: 2rem; }}

  table {{ width: 100%; border-collapse: collapse; margin-bottom: 1.5rem; font-size: 0.82rem; }}
  th {{ text-align: left; color: var(--muted); padding: 0.6rem 0.8rem; border-bottom: 1px solid var(--border); font-weight: 500; text-transform: uppercase; font-size: 0.7rem; letter-spacing: 0.5px; }}
  td {{ padding: 0.5rem 0.8rem; border-bottom: 1px solid rgba(255,255,255,0.04); }}
  tr:nth-child(even) td {{ background: rgba(255,255,255,0.02); }}
  tr:hover td {{ background: rgba(79,195,247,0.06); }}
  .num {{ text-align: right; font-variant-numeric: tabular-nums; }}

  /* Stacked bar chart (models) */
  .bar-row {{ display: flex; align-items: center; margin-bottom: 0.5rem; }}
  .bar-label {{ width: 180px; font-size: 0.8rem; color: var(--text); text-align: right; padding-right: 1rem; flex-shrink: 0; }}
  .bar-track {{ flex: 1; height: 28px; background: var(--bar-bg); border-radius: 4px; overflow: hidden; display: flex; min-width: 40px; }}
  .bar-segment {{ height: 100%; transition: opacity 0.15s; }}
  .bar-segment:hover {{ opacity: 0.8; }}
  .bar-value {{ width: 80px; font-size: 0.8rem; color: var(--muted); text-align: right; padding-left: 0.8rem; flex-shrink: 0; }}

  /* Horizontal bar (agents) */
  .h-bar-row {{ display: flex; align-items: center; margin-bottom: 0.4rem; }}
  .h-bar-label {{ width: 140px; font-size: 0.8rem; color: var(--text); text-align: right; padding-right: 1rem; flex-shrink: 0; }}
  .h-bar-track {{ flex: 1; height: 20px; background: var(--bar-bg); border-radius: 4px; overflow: hidden; min-width: 40px; }}
  .h-bar-fill {{ height: 100%; background: var(--accent); border-radius: 4px; }}
  .h-bar-value {{ width: 100px; font-size: 0.78rem; color: var(--muted); text-align: right; padding-left: 0.8rem; flex-shrink: 0; }}

  .chart-title {{ font-size: 0.95rem; color: var(--muted); margin-top: 2rem; margin-bottom: 0.8rem; padding-bottom: 0.3rem; border-bottom: 1px solid rgba(15,52,96,0.5); }}

  .chart-svg {{ width: 100%; height: auto; margin-bottom: 1rem; }}
  .chart-point {{ cursor: crosshair; transition: r 0.15s; }}
  .chart-point:hover {{ r: 6; }}

  #svg-tooltip {{ position: fixed; display: none; background: #16213e; border: 1px solid #4fc3f7; border-radius: 6px; padding: 8px 12px; font-size: 12px; color: #e0e0e0; pointer-events: none; z-index: 9999; box-shadow: 0 4px 12px rgba(0,0,0,0.3); line-height: 1.6; }}

  footer {{ margin-top: 3rem; padding-top: 1rem; border-top: 1px solid var(--border); font-size: 0.72rem; color: var(--muted); text-align: center; }}
  code {{ background: rgba(79,195,247,0.1); padding: 0.1rem 0.3rem; border-radius: 3px; font-size: 0.8rem; }}
  a {{ color: var(--accent); text-decoration: none; }}
  a:hover {{ text-decoration: underline; }}

  {COLLAPSIBLE_CSS}
</style>
</head>
<body>

<h1>{meta.get('title', '[ProjectName] — LLM Usage & Value Report')}</h1>''')

    # ── Section 1: Summary Metrics (collapsible, open) ──────────────────
    _cards_parts = [build_summary_cards(data)]
    _ic = build_code_impact_cards(ts_data)
    if _ic:
        _cards_parts.append(_ic)
    _cc = build_cache_cards(cache_estimate)
    if _cc:
        _cards_parts.append(_cc)
    _pc = build_productivity_cards(data)
    if _pc:
        _cards_parts.append(_pc)
    _pn = build_productivity_notes(data)
    if _pn:
        _cards_parts.append(_pn)
    html_parts.append(collapsible_section(
        'Summary Metrics',
        '\n'.join(_cards_parts),
        open=True
    ))

    # ── Section 2: Charts & Visualizations (collapsible, open) ──────────
    _charts_parts = []
    _charts_parts.append(subsection(
        'Token Usage by Model',
        build_models_section(data.get('models', []), cache_estimate)
    ))
    _charts_parts.append(subsection(
        'Token Usage by Role',
        build_roles_section(data.get('roles', []), cache_estimate)
    ))
    _charts_parts.append(subsection(
        'Daily Token Trend',
        build_daily_trend_section(ts_data)
    ))
    _ic_charts = build_code_impact_charts(ts_data)
    if _ic_charts:
        _charts_parts.append(_ic_charts)
    _cum = build_cumulative_sections(ts_data)
    if _cum:
        _charts_parts.append(_cum)
    _agent_cat = build_agent_category_section(ts_data)
    if _agent_cat:
        _charts_parts.append(_agent_cat)
    html_parts.append(collapsible_section(
        'Charts & Visualizations',
        '\n'.join(_charts_parts),
        open=True
    ))

    # ── Section 2b: Cost Analysis (collapsible, open) ────────────────────
    _cost_html = build_cost_analysis_section(data, ts_data)
    if _cost_html:
        html_parts.append(collapsible_section(
            'Cost Analysis',
            _cost_html,
            open=True
        ))

    # ── Section 3: Detailed Data Tables (collapsible, closed) ───────────
    _tables_parts = []
    _ct = build_cross_tab(data.get('cross_tab', []))
    if _ct:
        _tables_parts.append(subsection(
            'Model × Role Breakdown',
            _ct
        ))
    _cache_tables = build_cache_tables(cache_estimate)
    if _cache_tables:
        _tables_parts.append('<h3 class="chart-title">Cache Approximation</h3>' + _cache_tables)
    phases = data.get('phases', [])
    if phases:
        _tables_parts.append(subsection(
            'Phase Breakdown',
            build_phase_table(phases)
        ))
    most_eff = data.get('most_efficient_commits', [])
    least_eff = data.get('least_efficient_commits', [])
    if most_eff or least_eff:
        commit_html = ''
        if most_eff:
            commit_html += build_efficiency_commits_table(most_eff, 'Top 10 Most Efficient Commits') + '<br>'
        if least_eff:
            commit_html += build_efficiency_commits_table(least_eff, 'Top 10 Least Efficient Commits')
        _tables_parts.append(subsection('Commit Efficiency', commit_html))
    if agents_detailed:
        _tables_parts.append(subsection(
            'Agent Context Efficiency',
            render_context_efficiency_table(agents_detailed)
        ))
    _sess_summaries = build_session_summaries_section(data)
    if _sess_summaries:
        _tables_parts.append(subsection('Session Summaries', _sess_summaries))
    _subagent = build_subagent_runs_section(data.get('subagent_runs', {}))
    if _subagent:
        _tables_parts.append(subsection('Subagent Runs', _subagent))
    top_sess = data.get('top_sessions', [])
    if top_sess:
        _tables_parts.append(subsection(
            'Top Sessions by Token Count',
            build_top_sessions_section(top_sess, cache_estimate)
        ))
    html_parts.append(collapsible_section(
        'Detailed Data Tables',
        '\n'.join(_tables_parts) if _tables_parts else '<p style="color:#8892a4">No detailed data available.</p>',
        open=False
    ))

    # ── Footer ──────────────────────────────────────────────────────────
    html_parts.append('''
<footer>
  <p>Data sources: pi session JSONL files (<code>~/.pi/agent/sessions/**/*.jsonl</code>) + git log (all tracked files)</p>
  <p>Subagent usage is attributed from <code>subagent</code> tool results persisted in parent sessions (nested runs included).</p>
  <p>Where pi reports real cache reads they are used; otherwise a per-session delta model estimates uncached input. Token counts use cache-adjusted (uncached) input by default; raw values shown for comparison in summary cards and top sessions table.</p>
</footer>

<div id="svg-tooltip"></div>

<script>
// Collapsible section toggle handler
function toggleDetails(summaryEl) {
  const details = summaryEl.parentElement;
  // Toggle is handled natively by <details>, this just provides smooth transition feedback
}

// Tooltip for chart points
const tooltip = document.getElementById('svg-tooltip');
document.querySelectorAll('.chart-point').forEach(pt => {
  pt.addEventListener('mouseenter', e => {
    if (!tooltip) return;
    tooltip.style.display = 'block';
    let html = '';
    const date = pt.getAttribute('data-date');
    if (date) html += '<strong>' + date + '</strong><br>';
    const attrs = pt.attributes;
    for (let i = 0; i < attrs.length; i++) {
      const attr = attrs[i];
      if (attr.name.startsWith('data-') && attr.name !== 'data-date' && attr.name !== 'data-chart-type') {
        const label = attr.name.replace('data-', '').replace(/-([a-z])/g, g => g[1].toUpperCase());
        const num = parseFloat(attr.value);
        html += label + ': ' + (isNaN(num) ? attr.value : num.toLocaleString()) + '<br>';
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

    return '\n'.join(html_parts)


def main():
    """Read JSON from stdin, render consolidated HTML report."""
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON input: {e}", file=sys.stderr)
        sys.exit(1)

    html = render_html(data)
    print(html)


if __name__ == '__main__':
    main()
