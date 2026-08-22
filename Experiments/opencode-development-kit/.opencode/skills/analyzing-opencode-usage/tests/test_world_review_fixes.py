#!/usr/bin/env python3
"""Tests for world-review Phase 1 bug fixes: WR-1 through WR-4.

WR-1: [ProjectName] placeholder not replaced in report title
WR-2: productive_sessions > total_build_sessions (impossible subset)
WR-3: cost_summary missing per-model pricing and reasoning_tokens
WR-4: build_productivity.date is empty string
"""

import sys
from pathlib import Path

# Add script directory to path so we can import modules
sys.path.insert(0, str(Path(__file__).parent.parent / "script"))

from aggregator.merge import merge_datasets


def _make_minimal_datasets(overrides: dict | None = None) -> dict:
    """Return minimal datasets that produce a valid merge output.

    Args:
        overrides: Optional dict of dataset overrides to merge into defaults.

    Returns:
        Dict with all required datasets for merge_datasets().
    """
    defaults: dict = {
        'daily_agent': [
            {'day': '2026-08-01', 'sessions': 5, 'total_tokens_raw': 10000,
             'input_tokens_raw': 6000, 'output_tokens_raw': 3000,
             'reasoning_tokens_raw': 1000, 'build_tok_raw': 4000,
             'review_tok_raw': 3000, 'plan_tok_raw': 2000,
             'explore_tok_raw': 500, 'other_tok_raw': 500},
            {'day': '2026-08-02', 'sessions': 3, 'total_tokens_raw': 8000,
             'input_tokens_raw': 5000, 'output_tokens_raw': 2000,
             'reasoning_tokens_raw': 1000, 'build_tok_raw': 3000,
             'review_tok_raw': 2000, 'plan_tok_raw': 1500,
             'explore_tok_raw': 1000, 'other_tok_raw': 500},
        ],
        'agents_detailed': [],
        'weekly': [],
        'summary_raw': [{'total_sessions': 8, 'total_input_raw': 11000,
                         'total_output': 5000, 'total_reasoning': 2000,
                         'earliest': '2026-08-01', 'latest': '2026-08-02',
                         'total_tokens_raw': 18000}],
        'models_data': [
            {'model': 'qwen/qwen3.6-27b', 'input_tokens_raw': 11000,
             'output_tokens_raw': 5000, 'reasoning_tokens_raw': 2000,
             'sessions': 8},
        ],
        'agents_data': [],
        'cross_tab': [],
        'top_sessions': [],
        'productivity_raw': [{'total_sessions': 8, 'daily_sessions': {}}],
        'build_prod_raw': [{'total_build_sessions': 5, 'total_tokens': 7000}],
        'git_commits': [],
        'daily_git': [
            {'date': '2026-08-01', 'commits': 2, 'adds': 100, 'dels': 50,
             'test_adds': 20, 'test_dels': 10},
            {'date': '2026-08-02', 'commits': 1, 'adds': 50, 'dels': 20,
             'test_adds': 10, 'test_dels': 5},
        ],
        'cache_estimate': {'aggregate': {}, 'by_model': [], 'by_agent': [], 'by_day': []},
    }
    if overrides:
        for key, value in overrides.items():
            if key in defaults and isinstance(defaults[key], dict):
                defaults[key] = {**defaults[key], **value}
            elif key in defaults and isinstance(defaults[key], list):
                # For lists, replace entirely unless it's a nested override
                defaults[key] = value
            else:
                defaults[key] = value
    return defaults


class TestWR1_TitlePlaceholder:
    """WR-1: meta.title must not contain the [ProjectName] placeholder.

    The merge_datasets() function produces the meta dict. The caller
    (generate_report.py) is responsible for injecting the project name.
    We test that merge_datasets sets a title that does NOT contain the
    placeholder, and that the title format is correct once project_name
    is provided.
    """

    def test_title_does_not_contain_placeholder(self):
        """1.1.1.3 — meta.title must not contain [ProjectName] after merge."""
        datasets = _make_minimal_datasets()
        output = merge_datasets(**datasets)

        title = output['meta']['title']
        assert '[ProjectName]' not in title, \
            f"meta.title still contains placeholder: {title!r}"

    def test_title_contains_project_name_when_provided(self):
        """1.1.2.1 — When project_name is passed, title includes it."""
        datasets = _make_minimal_datasets()
        output = merge_datasets(**datasets, project_name='CollageMaker')

        title = output['meta']['title']
        assert 'CollageMaker' in title, \
            f"meta.title missing project name: {title!r}"
        assert '[ProjectName]' not in title, \
            f"meta.title still contains placeholder: {title!r}"

    def test_title_format_with_project_name(self):
        """Title format is '{project_name} — LLM Usage & Value Report'."""
        datasets = _make_minimal_datasets()
        output = merge_datasets(**datasets, project_name='MyProject')

        title = output['meta']['title']
        assert title == 'MyProject — LLM Usage & Value Report', \
            f"Unexpected title format: {title!r}"


class TestWR2_ProductiveSessionsExceedTotal:
    """WR-2: productive_build_sessions must never exceed total_build_sessions.

    The bug: productive_build_sessions summed ALL sessions on commit dates
    (including non-build sessions), which could exceed total_build_sessions.
    Fix: use token-ratio approximation to estimate build sessions per day.
    """

    def test_productive_sessions_never_exceed_total_build(self):
        """1.2.1.1 — productive_sessions must be <= total_build_sessions."""
        datasets = _make_minimal_datasets()
        output = merge_datasets(**datasets)

        bp = output['build_productivity'][0]
        prod = bp.get('productive_sessions', 0)
        total = bp.get('total_build_sessions', 0)
        assert prod <= total, \
            f"productive_sessions ({prod}) exceeds total_build_sessions ({total})"

    def test_productive_sessions_uses_token_ratio_not_all_sessions(self):
        """1.2.2.1 — productive sessions should approximate build fraction, not all sessions.

        With 5 sessions on day 1, build_tok=4000, total_effective=10000:
        build fraction = 4000/10000 = 0.4, so ~2 build sessions, not 5.
        """
        datasets = _make_minimal_datasets()
        # Day 1: 5 sessions, build_tok=4000, total_effective=10000 (40% build)
        # Day 2: 3 sessions, build_tok=3000, total_effective=8000 (37.5% build)
        # Both days have commits. Total build sessions = 5.
        # Expected productive: ~2 + ~1 = ~3, definitely not 8 (all sessions).
        output = merge_datasets(**datasets)

        bp = output['build_productivity'][0]
        prod = bp.get('productive_sessions', 0)
        total_build = bp.get('total_build_sessions', 0)
        total_all_sessions = 8  # 5 + 3 from daily_agent

        # The bug was that productive = 8 (all sessions on commit dates)
        # The fix should produce something much lower, using build token ratio
        assert prod < total_all_sessions, \
            f"productive_sessions ({prod}) equals all sessions ({total_all_sessions}), " \
            "not using token-ratio approximation"
        assert prod <= total_build, \
            f"productive_sessions ({prod}) exceeds total_build_sessions ({total_build})"

    def test_productive_sessions_at_least_one_per_commit_date_with_build(self):
        """1.2.2.2 — Each commit date with build activity contributes at least 1."""
        datasets = _make_minimal_datasets()
        output = merge_datasets(**datasets)

        bp = output['build_productivity'][0]
        prod = bp.get('productive_sessions', 0)
        # Both days have commits AND build tokens, so at least 2 productive sessions
        assert prod >= 2, \
            f"Expected at least 2 productive sessions (2 commit dates with build), got {prod}"


class TestWR3_CostCalculationInconsistency:
    """WR-3: cost_summary must include per-model pricing and reasoning_tokens.

    The bug: cost_summary used flat-rate tiers while model_pricing used
    per-model rates, producing two different totals with no reconciliation.
    Fix: add total_per_model and reasoning_tokens to cost_summary.
    """

    def test_cost_summary_has_total_per_model(self):
        """1.3.2.1 — cost_summary must include total_per_model key."""
        datasets = _make_minimal_datasets()
        output = merge_datasets(**datasets)

        cs = output['cost_summary']
        assert 'total_per_model' in cs, \
            f"cost_summary missing 'total_per_model' key. Keys: {list(cs.keys())}"

    def test_cost_summary_total_per_model_matches_model_pricing(self):
        """1.3.2.1 — cost_summary.total_per_model equals model_pricing.total_raw_cost."""
        datasets = _make_minimal_datasets()
        output = merge_datasets(**datasets)

        cs = output['cost_summary']
        mp = output['model_pricing']
        assert cs['total_per_model'] == mp['total_raw_cost'], \
            f"cost_summary.total_per_model ({cs['total_per_model']}) != " \
            f"model_pricing.total_raw_cost ({mp['total_raw_cost']})"

    def test_cost_summary_has_reasoning_tokens(self):
        """1.3.2.3 — cost_summary must include reasoning_tokens field."""
        datasets = _make_minimal_datasets()
        output = merge_datasets(**datasets)

        cs = output['cost_summary']
        assert 'reasoning_tokens' in cs, \
            f"cost_summary missing 'reasoning_tokens' key. Keys: {list(cs.keys())}"

    def test_cost_summary_reasoning_tokens_value(self):
        """1.3.2.3 — reasoning_tokens matches summary total_reasoning."""
        datasets = _make_minimal_datasets()
        output = merge_datasets(**datasets)

        cs = output['cost_summary']
        summary = output['summary']
        assert cs['reasoning_tokens'] == summary['total_reasoning'], \
            f"cost_summary.reasoning_tokens ({cs['reasoning_tokens']}) != " \
            f"summary.total_reasoning ({summary['total_reasoning']})"

    def test_cache_cost_summary_has_total_per_model(self):
        """1.3.2.2 — cache_cost_summary must include total_per_model key."""
        datasets = _make_minimal_datasets()
        output = merge_datasets(**datasets)

        ccs = output['cache_cost_summary']
        assert 'total_per_model' in ccs, \
            f"cache_cost_summary missing 'total_per_model' key. Keys: {list(ccs.keys())}"

    def test_cache_cost_summary_total_per_model_matches_model_pricing(self):
        """1.3.2.2 — cache_cost_summary.total_per_model equals model_pricing.total_cache_adjusted_cost."""
        datasets = _make_minimal_datasets()
        output = merge_datasets(**datasets)

        ccs = output['cache_cost_summary']
        mp = output['model_pricing']
        assert ccs['total_per_model'] == mp['total_cache_adjusted_cost'], \
            f"cache_cost_summary.total_per_model ({ccs['total_per_model']}) != " \
            f"model_pricing.total_cache_adjusted_cost ({mp['total_cache_adjusted_cost']})"


class TestWR4_EmptyBuildProductivityDate:
    """WR-4: build_productivity.date must not be an empty string.

    The bug: build_productivity.fetch() hardcodes date='' and merge.py
    never populates it. Fix: merge.py sets date='all' for the aggregate.
    """

    def test_build_productivity_date_not_empty(self):
        """1.4.1.1 — build_productivity[0].date must not be empty string."""
        datasets = _make_minimal_datasets()
        output = merge_datasets(**datasets)

        bp = output['build_productivity'][0]
        date_val = bp.get('date', '')
        assert date_val != '', \
            f"build_productivity.date is empty string. Full record: {bp}"

    def test_build_productivity_date_is_all(self):
        """1.4.2.1 — build_productivity.date should be 'all' for aggregate."""
        datasets = _make_minimal_datasets()
        output = merge_datasets(**datasets)

        bp = output['build_productivity'][0]
        assert bp.get('date') == 'all', \
            f"build_productivity.date is {bp.get('date')!r}, expected 'all'"
