#!/usr/bin/env python3
"""Aggregator module for merging analytics datasets into unified report structure.

This module contains the core logic for combining raw query results from multiple
sources (token usage, git commits, cache estimates) into a single coherent JSON
report structure with cache-adjusted values and cost estimations.
"""

import logging
from typing import Any

# Import from top-level after script is added to sys.path
from model_pricing import enrich_models_with_cost, compute_total_cost, get_pricing, compute_total_flat_cost

logger = logging.getLogger(__name__)


def merge_datasets(
    daily_agent: list[dict],
    agents_detailed: list[dict],
    weekly: list[dict],
    summary_raw: list[dict],
    models_data: list[dict],
    agents_data: list[dict],
    cross_tab: list[dict],
    top_sessions: list[dict],
    productivity_raw: list[dict],
    build_prod_raw: list[dict],
    git_commits: list[dict],
    daily_git: list[dict],
    cache_estimate: dict,
    project_range: dict | None = None,
    project_name: str = '',
) -> dict:
    """Merge all raw datasets into the final report structure.

    Args:
        daily_agent: Daily token counts by agent category from daily_tokens query.
        agents_detailed: Agent context efficiency metrics from agents_detailed query.
        weekly: Weekly aggregation from weekly query.
        summary_raw: Summary metrics from summary query (single-element list).
        models_data: Model usage statistics from models query.
        agents_data: Agent breakdown from agents query.
        cross_tab: Model-agent cross-tabulation from cross_tab query.
        top_sessions: Top sessions by token usage from top_sessions query.
        productivity_raw: Productivity metrics from productivity query (single-element list).
        build_prod_raw: Build productivity metrics from build_productivity query (single-element list).
        git_commits: Per-commit git statistics from git_commits query.
        daily_git: Daily git aggregates from daily_git query.
        cache_estimate: Cache estimation data with by_day, by_model, aggregate keys.
        project_range: True all-time project range from summary.fetch_project_range
            (keys: project_since, project_until, total_sessions_all_time,
            legacy_sessions). Injected by the caller to keep this function a
            pure in-memory merge. Defaults to None (backward compatible).
        project_name: Project name for the report title.

    Returns:
        dict: Complete report structure matching the expected JSON output format.
    """
    # Extract single-row queries
    summary = summary_raw[0] if summary_raw else {}
    productivity = productivity_raw[0] if productivity_raw else {}
    build_prod = build_prod_raw[0] if build_prod_raw else {}

    # Compute sessions_with_changes from git data (summary_files is always 0 in opencode DB)
    daily_sessions = productivity.pop('daily_sessions', {})
    git_dates_with_commits = {r.get('date', '') for r in daily_git if r.get('commits', 0) > 0}
    sessions_with_changes = sum(daily_sessions.get(d, 0) for d in git_dates_with_commits)
    productivity['sessions_with_changes'] = sessions_with_changes
    productivity['pct_with_changes'] = round(
        100.0 * sessions_with_changes / max(productivity.get('total_sessions', 0), 1), 1
    )

    # Build cache-adjusted daily rows
    merged_daily = _build_merged_daily(daily_agent, daily_git, cache_estimate)

    # Compute cumulative values
    _compute_cumulative(merged_daily)

    # Compute rolling averages and test ratios
    _compute_rolling_and_ratios(merged_daily)

    # Enrich summary with cache-adjusted values
    _enrich_summary(summary, cache_estimate)

    # Compute git-based build productivity from merged daily data
    build_total_tokens_adj = sum(r.get('build_tok', 0) for r in merged_daily)
    productive_build_tokens = sum(
        r.get('build_tok', 0) for r in merged_daily if r.get('date', '') in git_dates_with_commits
    )
    zero_change_build_tokens = build_total_tokens_adj - productive_build_tokens
    productive_build_sessions = sum(
        max(0, round(r.get('sessions', 0) * r.get('build_tok', 0) / max(r.get('total_effective', 1), 1)))
        for r in merged_daily
        if r.get('date', '') in git_dates_with_commits and r.get('build_tok', 0) > 0
    )
    # Safety net: productive sessions can never exceed total build sessions
    productive_build_sessions = min(productive_build_sessions, build_prod.get('total_build_sessions', 0))
    build_pct = round(100.0 * productive_build_tokens / max(build_total_tokens_adj, 1), 1)
    build_prod['productive_sessions'] = productive_build_sessions
    build_prod['zero_change_tokens'] = zero_change_build_tokens
    build_prod['pct_productive'] = build_pct
    build_prod['date'] = 'all'  # Aggregate across all dates in range

    # Cost estimation
    warnings = _validate_models(models_data) + _legacy_sessions_warning(project_range)
    cache_by_model = _build_cache_by_model(cache_estimate)
    models_with_cost = enrich_models_with_cost(models_data, cache_by_model)
    pricing_totals = compute_total_cost(models_data, cache_by_model)
    flat_totals = compute_total_flat_cost(models_data, cache_by_model)

    # Add cost data to daily rows
    _add_costs_to_daily(merged_daily, models_data, cache_by_model)

    # Build commit efficiency
    commit_efficiency = _build_commit_efficiency(merged_daily, git_commits, daily_git)

    # Phase breakdown
    phases = _build_phases(merged_daily)

    # Assemble final output
    pr = project_range or {}
    return {
        'meta': {
            'title': f'{project_name} — LLM Usage & Value Report' if project_name else 'LLM Usage & Value Report',
            'since': summary.get('earliest', ''),
            'until': summary.get('latest', ''),
            'generated': '',  # Will be filled by caller
            # True all-time project range (query-filter-independent), from fetch_project_range
            'project_since': pr.get('project_since', '') or '',
            'project_until': pr.get('project_until', '') or '',
            'total_sessions_all_time': pr.get('total_sessions_all_time', 0) or 0,
        },
        'summary': _build_summary_output(summary),
        'cost_summary': {
            'total_cheap': flat_totals['cheap_raw'],
            'total_expensive': flat_totals['expensive_raw'],
            'total_per_model': pricing_totals['total_raw_cost'],
            'input_tokens': summary.get('total_input_raw', 0),
            'output_tokens': summary.get('total_output', 0),
            'reasoning_tokens': summary.get('total_reasoning', 0),
        },
        'cache_cost_summary': {
            'uncached_input': cache_estimate.get('aggregate', {}).get('estimated_uncached_input', 0),
            'cached_input': cache_estimate.get('aggregate', {}).get('estimated_cached_input', 0),
            'total_cheap': flat_totals['cheap_cache'],
            'total_expensive': flat_totals['expensive_cache'],
            'total_per_model': pricing_totals['total_cache_adjusted_cost'],
        },
        'model_pricing': pricing_totals,
        'models_with_cost': models_with_cost,
        'productivity': [productivity] if productivity else [],
        'build_productivity': [build_prod] if build_prod else [],
        'models': models_data,
        'agents': agents_data,
        'cross_tab': cross_tab,
        'top_sessions': top_sessions,
        'weekly': weekly,
        'agents_detailed': agents_detailed,
        'timeseries': merged_daily,
        'daily_agent_stacked': list(merged_daily),  # Independent copy to prevent mutation bleed
        'cache_estimate': {
            **cache_estimate.get('aggregate', {}),
            'by_model': cache_estimate.get('by_model', []),
            'by_agent': cache_estimate.get('by_agent', []),
            'by_day': cache_estimate.get('by_day', []),
        },
        'phases': phases,
        'most_efficient_commits': commit_efficiency['most_efficient'],
        'least_efficient_commits': commit_efficiency['least_efficient'],
        'warnings': warnings,
    }


def _build_merged_daily(
    daily_agent: list[dict],
    daily_git: list[dict],
    cache_estimate: dict,
) -> list[dict]:
    """Build merged daily rows with cache-adjusted values.

    Merges token data with git data by date, applying cache adjustment to input tokens.
    """
    # Build lookup maps
    token_map = {}
    for r in daily_agent:
        day = r.get('day', '') or r.get('date', '')
        if day:
            token_map[day] = {
                'total_tokens_raw': r.get('total_tokens_raw', 0) or 0,
                'sessions': r.get('sessions', 0) or 0,
                'input_tokens_raw': r.get('input_tokens_raw', 0) or 0,
                'output_tokens_raw': r.get('output_tokens_raw', 0) or 0,
                'reasoning_tokens_raw': r.get('reasoning_tokens_raw', 0) or 0,
                'build_tok': r.get('build_tok_raw', 0) or 0,
                'review_tok': r.get('review_tok_raw', 0) or 0,
                'plan_tok': r.get('plan_tok_raw', 0) or 0,
                'explore_tok': r.get('explore_tok_raw', 0) or 0,
                'other_tok': r.get('other_tok_raw', 0) or 0,
            }

    git_map = {}
    for r in daily_git:
        date = r.get('date', '')
        if date:
            git_map[date] = {
                'commits': r.get('commits', 0),
                'adds': r.get('adds', 0),
                'dels': r.get('dels', 0),
                'test_adds': r.get('test_adds', 0),
                'test_dels': r.get('test_dels', 0),
            }

    # Build cache-adjusted lookups for input tokens
    cache_by_day = {}
    for entry in cache_estimate.get('by_day', []):
        day = entry.get('key', '') or entry.get('day', '')
        if day:
            cache_by_day[day] = {
                'uncached_input': entry.get('estimated_uncached_input', 0) or 0,
                'output': entry.get('total_output', 0) or 0,
                'reasoning': entry.get('total_reasoning', 0) or 0,
            }

    def effective_total(uncached_in: int, output: int, reasoning: int) -> int:
        return uncached_in + output + reasoning

    # Build merged rows
    merged_daily = []
    # Use set union for efficiency; both are already dicts so we can use them directly
    all_dates = sorted(set(token_map) | set(git_map))

    for date in all_dates:
        t = token_map.get(date, {})
        g = git_map.get(date, {})
        cl = cache_by_day.get(date)

        # Use cache-adjusted input if available, otherwise raw
        if cl and cl['uncached_input'] > 0:
            inp_uncached = cl['uncached_input']
            out_cached = cl['output'] or t.get('output_tokens_raw', 0) or 0
            rea_cached = cl['reasoning'] or t.get('reasoning_tokens_raw', 0) or 0
            eff_total = effective_total(inp_uncached, out_cached, rea_cached)
        else:
            inp_uncached = t.get('input_tokens_raw', 0) or 0
            out_cached = t.get('output_tokens_raw', 0) or 0
            rea_cached = t.get('reasoning_tokens_raw', 0) or 0
            eff_total = t.get('total_tokens_raw', 0) or 0

        commits = g.get('commits', 0)
        adds = g.get('adds', 0)
        dels = g.get('dels', 0)
        test_adds = g.get('test_adds', 0)
        test_dels = g.get('test_dels', 0)

        raw_input = t.get('input_tokens_raw', 0) or 0

        # Compute cache ratio for agent category adjustment
        raw_total = t.get('total_tokens_raw', 0) or 0
        cache_ratio = eff_total / raw_total if raw_total > 0 else 1.0

        row = {
            'date': date,
            'sessions': t.get('sessions', 0),
            # Raw values (for reference/comparison)
            'total_tokens_raw': t.get('total_tokens_raw', 0) or 0,
            'input_tokens_raw': raw_input,
            'input_tokens': inp_uncached,
            'output_tokens': out_cached,
            'reasoning_tokens': rea_cached,
            # Agent category breakdown (cache-adjusted)
            'build_tok': round(t.get('build_tok', 0) * cache_ratio),
            'review_tok': round(t.get('review_tok', 0) * cache_ratio),
            'plan_tok': round(t.get('plan_tok', 0) * cache_ratio),
            'explore_tok': round(t.get('explore_tok', 0) * cache_ratio),
            'other_tok': round(t.get('other_tok', 0) * cache_ratio),
            # Cache-adjusted effective total
            'total_effective': eff_total,
            'input_uncached': inp_uncached,
            # Git/impact data
            'commits': commits,
            'adds': adds,
            'dels': dels,
            'test_adds': test_adds,
            'test_dels': test_dels,
            # Derived metrics
            'tok_per_commit': round(eff_total / commits) if commits > 0 else 0,
            'tok_per_line': round(eff_total / adds) if adds > 0 else 0,
            'cache_hit_pct': 0,
            'cost_cheap': 0.0,
            'cost_expensive': 0.0,
            'daily_cost_cheap': 0.0,
            'daily_cost_expensive': 0.0,
        }

        # Compute cache hit percentage for this day
        if raw_input > 0 and cl:
            row['cache_hit_pct'] = round(100.0 * (raw_input - inp_uncached) / raw_input, 1)

        merged_daily.append(row)

    return merged_daily


def _compute_cumulative(merged_daily: list[dict]) -> None:
    """Compute cumulative values for efficiency curves."""
    cum_tokens = 0
    cum_all = 0
    cum_test = 0

    for r in merged_daily:
        cum_tokens += r['total_effective']
        cum_all += r['adds'] - r['dels']
        cum_test += r['test_adds'] - r['test_dels']
        r['cum_tokens'] = cum_tokens
        r['cum_all'] = cum_all
        r['cum_test'] = cum_test


def _compute_rolling_and_ratios(merged_daily: list[dict]) -> None:
    """Compute 7-day rolling tokens per commit and test ratios."""
    # Compute 7-day rolling tokens per commit using sliding window for O(n) performance
    window_tokens = 0
    window_commits = 0

    for i, r in enumerate(merged_daily):
        # Add current row to window
        window_tokens += r['total_effective']
        window_commits += r['commits']

        # Remove row that falls out of 7-day window (keep last 7 days including current)
        if i >= 7:
            prev = merged_daily[i - 7]
            window_tokens -= prev['total_effective']
            window_commits -= prev['commits']

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


def _enrich_summary(summary: dict, cache_estimate: dict) -> None:
    """Enrich summary with cache-adjusted values."""
    cache_agg = cache_estimate.get('aggregate', {}) if cache_estimate else {}
    uncached_input_total = cache_agg.get('estimated_uncached_input', 0) or 0
    cached_input_total = cache_agg.get('estimated_cached_input', 0) or 0

    summary['total_tokens_effective'] = uncached_input_total + (summary.get('total_output', 0) or 0) + (summary.get('total_reasoning', 0) or 0)
    summary['total_input_uncached'] = uncached_input_total
    summary['cache_hit_pct'] = cache_agg.get('cache_hit_pct', 0) or 0


def _build_cache_by_model(cache_estimate: dict) -> dict:
    """Build cache lookup by model name."""
    cache_by_model = {}
    for entry in cache_estimate.get('by_model', []):
        model_name = entry.get('key', 'unknown')
        cache_by_model[model_name] = entry
    return cache_by_model


def _add_costs_to_daily(
    merged_daily: list[dict],
    models_data: list[dict],
    cache_by_model: dict,
) -> None:
    """Add cost data to daily rows using average per-token rates."""
    # Compute totals from models (using correct key names with _raw suffixes)
    _total_input_all = sum(m.get('input_tokens_raw', 0) or 0 for m in models_data)
    _total_output_all = sum(m.get('output_tokens_raw', 0) or 0 for m in models_data)

    # Compute pricing totals
    pricing_totals = compute_total_cost(models_data, cache_by_model)

    # Derive average rates - first compute input cost total
    _input_cost_total = sum(
        (m.get('input_tokens_raw', 0) or 0) * get_pricing(m.get('model', 'unknown'))['input'] / 1_000_000
        for m in models_data
    )
    # Output cost is total raw minus input cost
    _output_cost_total = pricing_totals['total_raw_cost'] - _input_cost_total

    # Average rates per million tokens
    _avg_rate_input = _input_cost_total / _total_input_all if _total_input_all > 0 else 0.0005
    _avg_rate_output = _output_cost_total / _total_output_all if _total_output_all > 0 else 0.0015

    # Cache-adjusted average rates
    _input_cost_cache = sum(
        max(0, (m.get('input_tokens_raw', 0) or 0) - (cache_by_model.get(m.get('model', ''), {}).get('estimated_cached_input', 0) or 0))
        * get_pricing(m.get('model', 'unknown'))['input'] / 1_000_000
        + (cache_by_model.get(m.get('model', ''), {}).get('estimated_cached_input', 0) or 0)
        * get_pricing(m.get('model', 'unknown'))['cached_input'] / 1_000_000
        for m in models_data
    )
    _output_cost_cache = _output_cost_total
    _total_cache_cost = _input_cost_cache + _output_cost_cache
    _avg_rate_input_cache = _input_cost_cache / _total_input_all if _total_input_all > 0 else 0.00005

    # Add costs to daily rows
    cum_cheap = 0.0
    cum_exp = 0.0
    for r in merged_daily:
        inp = r.get('input_tokens', 0)
        out_ = r.get('output_tokens', 0)
        day_cheap = inp * _avg_rate_input_cache + out_ * _avg_rate_output
        day_exp = inp * _avg_rate_input + out_ * _avg_rate_output
        cum_cheap += day_cheap
        cum_exp += day_exp
        r['cost_cheap'] = round(cum_cheap, 2)
        r['cost_expensive'] = round(cum_exp, 2)
        r['daily_cost_cheap'] = round(day_cheap, 2)
        r['daily_cost_expensive'] = round(day_exp, 2)


def _build_commit_efficiency(
    merged_daily: list[dict],
    git_commits: list[dict],
    daily_git: list[dict],
) -> dict:
    """Build commit efficiency metrics."""
    token_map_eff = {}
    for r in merged_daily:
        token_map_eff[r['date']] = r.get('total_effective', 0)

    git_map_commits = {}
    for r in daily_git:
        git_map_commits[r['date']] = r.get('commits', 0)

    commit_efficiency = []
    for c in git_commits:
        date = c['date']
        daily_tokens = token_map_eff.get(date, 0)
        daily_commits_count = git_map_commits.get(date, 0)
        tok_per_commit = round(daily_tokens / daily_commits_count) if daily_commits_count > 0 else 0
        lines_changed = c['adds'] + c['dels']
        tok_per_line = round(tok_per_commit / lines_changed) if lines_changed > 0 else 0
        commit_efficiency.append({
            'sha': c['sha'],
            'date': date,
            'message': c['message'],
            'adds': c['adds'],
            'dels': c['dels'],
            'lines_changed': lines_changed,
            'tok_per_commit': tok_per_commit,
            'tok_per_line': tok_per_line,
            'is_test': c.get('is_test', False),
        })

    most_efficient = sorted(
        [c for c in commit_efficiency if c['lines_changed'] > 0],
        key=lambda c: c['tok_per_line']
    )[:10]

    least_efficient = sorted(
        [c for c in commit_efficiency if c['lines_changed'] > 0],
        key=lambda c: c['tok_per_line'],
        reverse=True
    )[:10]

    return {
        'most_efficient': most_efficient,
        'least_efficient': least_efficient,
    }


def _build_phases(merged_daily: list[dict]) -> list[dict]:
    """Build phase breakdowns.

    Returns empty list. Phase definitions are project-specific and should be
    configured externally via a phases file. Hardcoded dates were removed as
    they produced all-zero results for any report outside the original window.
    """
    return []


def _build_summary_output(summary: dict) -> dict:
    """Build final summary output structure."""
    return {
        'total_sessions': summary.get('total_sessions', 0) or 0,
        'total_tokens_raw': summary.get('total_tokens_raw', 0) or 0,
        'total_tokens_effective': summary.get('total_tokens_effective', 0) or 0,
        'total_input_raw': summary.get('total_input_raw', 0) or 0,
        'total_input_uncached': summary.get('total_input_uncached', 0) or 0,
        'total_output': summary.get('total_output', 0) or 0,
        'total_reasoning': summary.get('total_reasoning', 0) or 0,
        'cache_hit_pct': summary.get('cache_hit_pct', 0) or 0,
        'earliest': summary.get('earliest', ''),
        'latest': summary.get('latest', ''),
        'model_count': summary.get('model_count', 0) or 0,
        'agent_count': summary.get('agent_count', 0) or 0,
    }


def _validate_models(models_data: list[dict]) -> list[str]:
    """Validate model data for anomalies. Returns list of warning messages.

    Checks for models that have sessions recorded but zero tokens, which
    indicates incomplete or corrupted session data.

    Args:
        models_data: List of model dicts with 'model', 'sessions', 'total_tokens_raw' keys.

    Returns:
        List of warning message strings. Empty list if no anomalies found.
    """
    warnings: list[str] = []
    for m in models_data:
        model_id = m.get('model', 'unknown')
        sessions = m.get('sessions', 0) or 0
        total = m.get('total_tokens_raw', 0) or 0
        if sessions > 0 and total == 0:
            msg = f"Model '{model_id}' has {sessions} session(s) with 0 tokens"
            warnings.append(msg)
            logger.warning(msg)
    return warnings


def _legacy_sessions_warning(project_range: dict | None) -> list[str]:
    """Flag legacy (NULL model/agent) sessions in the warnings array.

    Legacy sessions predate opencode's model/agent tracking. They are counted
    in session totals but carry no model/agent attribution and zero tokens.

    Args:
        project_range: Fetched project range dict (may be None).

    Returns:
        A single warning message when legacy sessions exist, else an empty list.
    """
    legacy = (project_range or {}).get('legacy_sessions', 0) or 0
    if legacy > 0:
        msg = f"{legacy} legacy sessions with NULL model/agent are included in counts"
        logger.warning(msg)
        return [msg]
    return []
