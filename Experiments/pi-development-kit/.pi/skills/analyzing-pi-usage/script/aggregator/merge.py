#!/usr/bin/env python3
"""Aggregator for merging pi analytics datasets into the unified report structure.

Ported from the opencode kit's aggregator/merge.py (agent rows became role
rows; pi adds subagent-run and session-summary datasets). Combines raw query
results from the parsed-JSONL query modules with git and cache-estimate data
into a single coherent JSON report structure with cache-adjusted values and
cost estimations.
"""

import logging

from model_pricing import (
    enrich_models_with_cost,
    compute_total_cost,
    compute_total_flat_cost,
    get_pricing,
)
from queries.utils import pricing_model_id

logger = logging.getLogger(__name__)


def merge_datasets(
    daily_agent: list[dict],
    weekly: list[dict],
    summary_raw: list[dict],
    models_data: list[dict],
    roles_data: list[dict],
    cross_tab: list[dict],
    top_sessions: list[dict],
    productivity_raw: list[dict],
    build_prod_raw: list[dict],
    git_commits: list[dict],
    daily_git: list[dict],
    cache_estimate: dict,
    project_range: dict | None = None,
    project_name: str = '',
    subagent_runs: dict | None = None,
    session_summaries: dict | None = None,
    change_attribution: dict | None = None,
) -> dict:
    """Merge all raw datasets into the final report structure."""
    # Extract single-row queries
    summary = summary_raw[0] if summary_raw else {}
    productivity = dict(productivity_raw[0]) if productivity_raw else {}
    build_prod = dict(build_prod_raw[0]) if build_prod_raw else {}

    # Compute sessions_with_changes (pi does not record per-session file
    # changes). With `Pi-Session:` commit trailers present, the attributed
    # sessions are measured and only unattributed commits fall back to the
    # date-join estimate; without trailers this is the legacy pure estimate.
    daily_sessions = productivity.pop('daily_sessions', {})
    total_sessions = productivity.get('total_sessions', 0) or 0
    attribution = change_attribution or {}
    git_dates_with_commits = {r.get('date', '') for r in daily_git if r.get('commits', 0) > 0}
    if attribution.get('attributed_commits', 0) > 0:
        unattr_dates = {c.get('date', '') for c in git_commits if not c.get('session_id')}
        est_remainder = sum(daily_sessions.get(d, 0) for d in unattr_dates)
        # Cap: the estimate portion can never exceed the session total.
        sessions_with_changes = min(
            attribution.get('sessions_measured', 0) + est_remainder, total_sessions)
        productivity['sessions_with_changes_measured'] = attribution.get('sessions_measured', 0)
    else:
        sessions_with_changes = sum(
            daily_sessions.get(d, 0) for d in git_dates_with_commits)
        sessions_with_changes = min(sessions_with_changes, total_sessions)
        productivity['sessions_with_changes_measured'] = 0
    productivity['sessions_with_changes'] = sessions_with_changes
    productivity['pct_with_changes'] = round(
        100.0 * sessions_with_changes / max(total_sessions, 1), 1
    )
    productivity['session_summaries'] = session_summaries or {
        'total': 0, 'by_purpose': {}, 'by_outcome': {}, 'by_role': {}}

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

    # Cost estimation (pi model ids adapted to the provider-agnostic pricing table)
    warnings = _validate_models(models_data)
    cache_by_model = _build_cache_by_model(cache_estimate)
    models_with_cost = enrich_models_with_cost(_adapt_pricing(models_data), cache_by_model)
    pricing_totals = compute_total_cost(_adapt_pricing(models_data), cache_by_model)
    flat_totals = compute_total_flat_cost(_adapt_pricing(models_data), cache_by_model)

    # Add cost data to daily rows
    _add_costs_to_daily(merged_daily, models_data, cache_by_model)

    # Build commit efficiency
    commit_efficiency = _build_commit_efficiency(merged_daily, git_commits, daily_git)

    # Assemble final output
    pr = project_range or {}
    return {
        'meta': {
            'title': f'{project_name} — LLM Usage & Value Report' if project_name else 'LLM Usage & Value Report',
            'since': summary.get('earliest', ''),
            'until': summary.get('latest', ''),
            'generated': '',  # Will be filled by caller
            # True all-time project range (query-filter-independent)
            'project_since': pr.get('project_since', '') or '',
            'project_until': pr.get('project_until', '') or '',
            'total_sessions_all_time': pr.get('total_sessions_all_time', 0) or 0,
        },
        'summary': _build_summary_output(summary),
        'cost_summary': {
            'total_cheap': flat_totals['cheap_raw'],
            'total_expensive': flat_totals['expensive_raw'],
            'total_per_model': pricing_totals['total_raw_cost'],
            'actual_cost': summary.get('actual_cost', 0.0),
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
        'roles': roles_data,
        'cross_tab': cross_tab,
        'top_sessions': top_sessions,
        'weekly': weekly,
        'timeseries': merged_daily,
        'cache_estimate': {
            **cache_estimate.get('aggregate', {}),
            'by_model': cache_estimate.get('by_model', []),
            'by_role': cache_estimate.get('by_role', []),
            'by_day': cache_estimate.get('by_day', []),
        },
        'subagent_runs': subagent_runs or {},
        'session_summaries': session_summaries or {
            'total': 0, 'by_purpose': {}, 'by_outcome': {}, 'by_role': {}},
        'most_efficient_commits': commit_efficiency['most_efficient'],
        'least_efficient_commits': commit_efficiency['least_efficient'],
        'change_attribution': change_attribution or {},
        'warnings': warnings,
    }


def _adapt_pricing(models_data: list[dict]) -> list[dict]:
    """Copy model rows with pi provider-prefixed ids mapped to pricing keys."""
    out = []
    for m in models_data:
        m2 = dict(m)
        m2['model'] = pricing_model_id(m.get('model', ''))
        out.append(m2)
    return out


def _build_merged_daily(
    daily_agent: list[dict],
    daily_git: list[dict],
    cache_estimate: dict,
) -> list[dict]:
    """Build merged daily rows with cache-adjusted values."""
    token_map = {}
    for r in daily_agent:
        day = r.get('date', '')
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

    merged_daily = []
    all_dates = sorted(set(token_map) | set(git_map))

    for date in all_dates:
        t = token_map.get(date, {})
        g = git_map.get(date, {})
        cl = cache_by_day.get(date)

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
        raw_total = t.get('total_tokens_raw', 0) or 0
        cache_ratio = eff_total / raw_total if raw_total > 0 else 1.0

        row = {
            'date': date,
            'sessions': t.get('sessions', 0),
            'total_tokens_raw': t.get('total_tokens_raw', 0) or 0,
            'input_tokens_raw': raw_input,
            'input_tokens': inp_uncached,
            'output_tokens': out_cached,
            'reasoning_tokens': rea_cached,
            # Role category breakdown (cache-adjusted)
            'build_tok': round(t.get('build_tok', 0) * cache_ratio),
            'review_tok': round(t.get('review_tok', 0) * cache_ratio),
            'plan_tok': round(t.get('plan_tok', 0) * cache_ratio),
            'explore_tok': round(t.get('explore_tok', 0) * cache_ratio),
            'other_tok': round(t.get('other_tok', 0) * cache_ratio),
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
    window_tokens = 0
    window_commits = 0

    for i, r in enumerate(merged_daily):
        window_tokens += r['total_effective']
        window_commits += r['commits']

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

    for r in merged_daily:
        total_adds = r['adds']
        r['test_ratio'] = round(100.0 * r['test_adds'] / total_adds, 1) if total_adds > 0 else 0


def _enrich_summary(summary: dict, cache_estimate: dict) -> None:
    """Enrich summary with cache-adjusted values."""
    cache_agg = cache_estimate.get('aggregate', {}) if cache_estimate else {}
    uncached_input_total = cache_agg.get('estimated_uncached_input', 0) or 0

    summary['total_tokens_effective'] = (
        uncached_input_total + (summary.get('total_output', 0) or 0)
        + (summary.get('total_reasoning', 0) or 0)
    )
    summary['total_input_uncached'] = uncached_input_total
    summary['cache_hit_pct'] = cache_agg.get('cache_hit_pct', 0) or 0


def _build_cache_by_model(cache_estimate: dict) -> dict:
    """Build cache lookup by (pricing-adapted) model name."""
    cache_by_model = {}
    for entry in cache_estimate.get('by_model', []):
        model_name = entry.get('key', 'unknown')
        cache_by_model[pricing_model_id(model_name)] = entry
    return cache_by_model


def _add_costs_to_daily(
    merged_daily: list[dict],
    models_data: list[dict],
    cache_by_model: dict,
) -> None:
    """Add cost data to daily rows using average per-token rates."""
    adapted = _adapt_pricing(models_data)
    _total_input_all = sum(m.get('input_tokens_raw', 0) or 0 for m in adapted)
    _total_output_all = sum(m.get('output_tokens_raw', 0) or 0 for m in adapted)

    pricing_totals = compute_total_cost(adapted, cache_by_model)

    _input_cost_total = sum(
        (m.get('input_tokens_raw', 0) or 0) * get_pricing(m.get('model', 'unknown'))['input'] / 1_000_000
        for m in adapted
    )
    _output_cost_total = pricing_totals['total_raw_cost'] - _input_cost_total

    _avg_rate_input = _input_cost_total / _total_input_all if _total_input_all > 0 else 0.0005
    _avg_rate_output = _output_cost_total / _total_output_all if _total_output_all > 0 else 0.0015

    _input_cost_cache = sum(
        max(0, (m.get('input_tokens_raw', 0) or 0) - (cache_by_model.get(m.get('model', ''), {}).get('estimated_cached_input', 0) or 0))
        * get_pricing(m.get('model', 'unknown'))['input'] / 1_000_000
        + (cache_by_model.get(m.get('model', ''), {}).get('estimated_cached_input', 0) or 0)
        * get_pricing(m.get('model', 'unknown'))['cached_input'] / 1_000_000
        for m in adapted
    )
    _output_cost_cache = _output_cost_total
    _total_cache_cost = _input_cost_cache + _output_cost_cache
    _avg_rate_input_cache = _input_cost_cache / _total_input_all if _total_input_all > 0 else 0.00005

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
        'cache_read': summary.get('cache_read', 0) or 0,
        'cache_write': summary.get('cache_write', 0) or 0,
        'actual_cost': summary.get('actual_cost', 0.0) or 0.0,
        'cache_hit_pct': summary.get('cache_hit_pct', 0) or 0,
        'earliest': summary.get('earliest', ''),
        'latest': summary.get('latest', ''),
        'model_count': summary.get('model_count', 0) or 0,
        'role_count': summary.get('role_count', 0) or 0,
    }


def _validate_models(models_data: list[dict]) -> list[str]:
    """Validate model data for anomalies. Returns list of warning messages."""
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
