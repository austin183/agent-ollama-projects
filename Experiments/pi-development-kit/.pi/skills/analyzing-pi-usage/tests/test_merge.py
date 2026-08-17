"""Aggregator merge: key alignment, enrichment, capping, passthrough.

Token magnitudes are in the millions so the cent-rounded cost assertions
are meaningful.
"""

from aggregator.merge import merge_datasets


def _cache_row(key, total_input, uncached, cached, output=150_000, reasoning=50_000):
    return {
        'key': key, 'value': key, 'sessions': 1, 'total_turns': 4,
        'total_input_raw': total_input,
        'estimated_uncached_input': uncached,
        'estimated_cached_input': cached,
        'cache_hit_pct': round(100.0 * cached / total_input, 1) if total_input else 0.0,
        'total_output': output, 'total_reasoning': reasoning,
        'effective_total': uncached + output + reasoning,
        'raw_total': total_input + output + reasoning,
        'simulated': True,
    }


def _base_inputs(**overrides):
    inputs = {
        'daily_agent': [{
            'date': '2026-01-05', 'sessions': 1,
            'total_tokens_raw': 1_000_000, 'input_tokens_raw': 800_000,
            'output_tokens_raw': 150_000, 'reasoning_tokens_raw': 50_000,
            'build_tok_raw': 600_000, 'review_tok_raw': 100_000,
            'plan_tok_raw': 300_000, 'explore_tok_raw': 0, 'other_tok_raw': 0,
        }],
        'weekly': [{'week': '2026-W01', 'total_sessions': 1,
                    'total_tokens_raw': 1_000_000}],
        'summary_raw': [{
            'total_sessions': 3, 'total_tokens_raw': 1_000_000,
            'total_input_raw': 800_000, 'total_output': 150_000,
            'total_reasoning': 50_000, 'cache_read': 0, 'cache_write': 0,
            'actual_cost': 0.5, 'earliest': '2026-01-05',
            'latest': '2026-01-05', 'model_count': 1, 'role_count': 2,
        }],
        'models_data': [{
            'model': 'anthropic/claude-sonnet-4', 'sessions': 3,
            'input_tokens_raw': 800_000, 'output_tokens_raw': 150_000,
            'reasoning_tokens_raw': 50_000, 'total_tokens_raw': 1_000_000,
        }],
        'roles_data': [{'role': 'main', 'sessions': 3, 'total_tokens_raw': 1_000_000,
                        'input_tokens_raw': 800_000, 'output_tokens_raw': 150_000,
                        'reasoning_tokens_raw': 50_000}],
        'cross_tab': [{'model': 'anthropic/claude-sonnet-4', 'role': 'main',
                       'sessions': 3, 'total_tokens_raw': 1_000_000}],
        'top_sessions': [],
        'productivity_raw': [{
            'total_sessions': 3,
            'daily_sessions': {'2026-01-05': 2},
        }],
        'build_prod_raw': [{
            'date': '', 'build_tokens': 600_000, 'commits': 0,
            'tokens_per_commit': 0.0, 'total_build_sessions': 2,
            'productive_sessions': 0, 'total_tokens': 600_000,
            'zero_change_tokens': 600_000, 'pct_productive': 0.0,
        }],
        'git_commits': [],
        'daily_git': [{'date': '2026-01-05', 'commits': 2, 'adds': 100,
                       'dels': 10, 'test_adds': 20, 'test_dels': 2}],
        'cache_estimate': {
            'aggregate': _cache_row('aggregate', 800_000, 100_000, 700_000),
            'by_day': [_cache_row('2026-01-05', 800_000, 100_000, 700_000)],
            'by_model': [_cache_row('anthropic/claude-sonnet-4', 800_000,
                                    100_000, 700_000)],
            'by_role': [_cache_row('main', 800_000, 100_000, 700_000)],
        },
        'project_range': {'project_since': '2025-12-01',
                          'project_until': '2026-01-05',
                          'total_sessions_all_time': 7},
        'project_name': 'DemoProject',
        'subagent_runs': {'total_runs': 2, 'by_agent': [], 'runs': []},
        'session_summaries': {'total': 1, 'by_purpose': {'dev': 1},
                              'by_outcome': {'complete': 1},
                              'by_role': {'main': 1}},
    }
    inputs.update(overrides)
    return inputs


def _merge(**overrides):
    i = _base_inputs(**overrides)
    return merge_datasets(**i)


def test_all_report_keys_present():
    r = _merge()
    for key in ('meta', 'summary', 'cost_summary', 'cache_cost_summary',
                'model_pricing', 'models_with_cost', 'productivity',
                'build_productivity', 'models', 'roles', 'cross_tab',
                'top_sessions', 'weekly', 'timeseries', 'cache_estimate',
                'subagent_runs', 'session_summaries',
                'most_efficient_commits', 'least_efficient_commits',
                'warnings'):
        assert key in r, f'missing report key: {key}'


def test_meta():
    r = _merge()
    assert r['meta']['title'] == 'DemoProject — LLM Usage & Value Report'
    assert r['meta']['since'] == '2026-01-05'
    assert r['meta']['project_since'] == '2025-12-01'
    assert r['meta']['total_sessions_all_time'] == 7
    assert r['meta']['generated'] == ''  # filled by caller


def test_summary_enriched_with_cache_adjusted_total():
    r = _merge()
    s = r['summary']
    # effective = uncached(100K) + output(150K) + reasoning(50K)
    assert s['total_tokens_effective'] == 300_000
    assert s['total_input_uncached'] == 100_000
    assert s['cache_hit_pct'] == 87.5
    assert s['actual_cost'] == 0.5


def test_sessions_with_changes_capped_at_session_total():
    r = _merge()
    prod = r['productivity'][0]
    assert prod['sessions_with_changes'] == 2
    assert prod['pct_with_changes'] == round(100.0 * 2 / 3, 1)

    # date-join estimate must never exceed the session total
    r = _merge(productivity_raw=[{'total_sessions': 3,
                                  'daily_sessions': {'2026-01-05': 50}}])
    assert r['productivity'][0]['sessions_with_changes'] == 3


def test_productivity_includes_session_summaries():
    r = _merge()
    assert r['productivity'][0]['session_summaries']['total'] == 1
    assert r['session_summaries']['by_purpose'] == {'dev': 1}


def test_build_productivity_computed_from_daily():
    r = _merge()
    bp = r['build_productivity'][0]
    # all build tokens fell on a commit day -> 100% productive; the
    # token-ratio session estimate (0.6 -> 1) is capped by total_build_sessions
    assert bp['productive_sessions'] == 1
    assert bp['zero_change_tokens'] == 0
    assert bp['pct_productive'] == 100.0


def test_cost_summary_uses_pricing_table():
    r = _merge()
    cs = r['cost_summary']
    # claude-sonnet-4 raw: 800K in @3.00/M + (150K+50K) out @15.00/M = 2.40+3.00
    assert cs['total_per_model'] == 5.40
    assert cs['actual_cost'] == 0.5
    ccs = r['cache_cost_summary']
    # cache-adjusted: 100K @3.00/M + 700K @0.30/M + 200K out @15.00/M
    assert ccs['total_per_model'] == round(0.30 + 0.21 + 3.00, 2)
    assert ccs['uncached_input'] == 100_000
    assert ccs['cached_input'] == 700_000


def test_timeseries_rows_cache_adjusted_and_costed():
    r = _merge()
    row = r['timeseries'][0]
    assert row['date'] == '2026-01-05'
    assert row['input_tokens'] == 100_000  # uncached from cache estimate
    assert row['total_effective'] == 300_000
    assert row['cache_hit_pct'] == 87.5
    assert row['build_tok'] == 180_000  # 600K raw * 0.3 cache ratio
    assert row['daily_cost_cheap'] > 0
    assert row['rolling_tok_per_commit'] > 0


def test_subagent_runs_passthrough():
    sub = {'total_runs': 4, 'by_agent': [{'agent': 'planner', 'runs': 4}],
           'runs': [{'agent': 'planner'}]}
    r = _merge(subagent_runs=sub)
    assert r['subagent_runs'] == sub


def test_model_warning_for_zero_token_sessions():
    r = _merge(models_data=[{'model': 'broken/model', 'sessions': 2,
                             'input_tokens_raw': 0, 'output_tokens_raw': 0,
                             'reasoning_tokens_raw': 0,
                             'total_tokens_raw': 0}])
    assert any('broken/model' in w for w in r['warnings'])
