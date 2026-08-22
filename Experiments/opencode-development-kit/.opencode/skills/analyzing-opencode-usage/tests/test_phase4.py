#!/usr/bin/env python3
"""Tests for Phase 4: Documentation and Disclaimer additions.

P4-1: Cache hit rate must have inline tooltip explaining it is simulated
P4-2: Productive sessions must note it is estimated from token ratios
P4-3: SKILL.md must document simulated estimates in gotchas
"""

import sys
from pathlib import Path

# Add script directory to path so we can import modules
sys.path.insert(0, str(Path(__file__).parent.parent / "script"))

from render_consolidated_report import (
    build_summary_cards,
    build_cache_cards,
    build_productivity_notes,
)


def _make_minimal_data(overrides: dict | None = None) -> dict:
    """Return minimal data dict for renderer functions.

    Args:
        overrides: Optional dict of top-level key overrides.

    Returns:
        Dict with minimal structure for render functions.
    """
    defaults: dict = {
        'summary': {
            'total_tokens_effective': 50000,
            'total_tokens_raw': 500000,
            'total_sessions': 10,
            'earliest': '2026-08-01',
            'latest': '2026-08-08',
            'model_count': 3,
            'agent_count': 5,
            'cache_hit_pct': 94.2,
        },
        'cost_summary': {
            'total_cheap': 0.01,
            'total_expensive': 0.05,
            'total_per_model': 0.04,
        },
        'cache_cost_summary': {
            'total_cheap': 0.005,
            'total_expensive': 0.02,
            'total_per_model': 0.015,
        },
        'meta': {
            'title': 'TestProject — LLM Usage & Value Report',
            'generated': '2026-08-08',
        },
        'timeseries': [
            {'date': '2026-08-01', 'total_effective': 25000, 'input_uncached': 15000,
             'output_tokens': 8000, 'reasoning_tokens': 2000, 'sessions': 5,
             'commits': 2, 'adds': 100, 'dels': 50, 'tok_per_commit': 12500,
             'tok_per_line': 250, 'input_tokens_raw': 150000},
            {'date': '2026-08-02', 'total_effective': 25000, 'input_uncached': 15000,
             'output_tokens': 8000, 'reasoning_tokens': 2000, 'sessions': 5,
             'commits': 1, 'adds': 50, 'dels': 20, 'tok_per_commit': 25000,
             'tok_per_line': 500, 'input_tokens_raw': 150000},
        ],
        'models': [],
        'agents': [],
        'cross_tab': [],
        'cache_estimate': {
            'aggregate': {
                'raw_total': 500000,
                'effective_total': 50000,
                'estimated_cached_input': 450000,
                'estimated_uncached_input': 50000,
                'cache_hit_pct': 94.2,
                'sessions': 10,
                'total_turns': 85,
            },
            'by_model': [],
            'by_agent': [],
            'by_day': [],
        },
        'productivity': {
            'total_sessions': 10,
            'sessions_with_changes': 4,
            'pct_with_changes': 40.0,
        },
        'build_productivity': {
            'total_build_sessions': 5,
            'productive_sessions': 2,
            'pct_productive': 40.0,
            'total_tokens': 30000,
            'zero_change_tokens': 10000,
        },
        'agents_detailed': [],
        'weekly': [],
        'phases': [],
        'most_efficient_commits': [],
        'least_efficient_commits': [],
        'top_sessions': [],
    }
    if overrides:
        for key, value in overrides.items():
            if key in defaults and isinstance(defaults[key], dict) and isinstance(value, dict):
                defaults[key] = {**defaults[key], **value}
            else:
                defaults[key] = value
    return defaults


class TestP41_CacheHitRateTooltip:
    """P4-1: Cache hit rate card must include a tooltip explaining it is simulated.

    The cache hit rate is a simulated estimate based on per-message token deltas,
    not actual provider cache performance. This must be communicated to the reader.
    """

    def test_summary_cards_cache_hit_has_tooltip(self):
        """4.1.1 — Summary cards cache hit rate must have a title attribute with explanation."""
        data = _make_minimal_data()
        html = build_summary_cards(data)

        assert 'title=' in html or 'title =' in html, \
            "Cache hit rate card missing title attribute for tooltip"
        # The tooltip should mention that this is simulated/estimated
        assert any(phrase in html.lower() for phrase in [
            'simulated', 'estimated', 'estimate', 'approximation',
            'not actual', 'not real',
        ]), \
            "Cache hit rate tooltip does not explain it is a simulated estimate"

    def test_summary_cards_cache_hit_tooltip_mentions_per_message(self):
        """4.1.2 — Tooltip should explain the methodology (per-message token deltas)."""
        data = _make_minimal_data()
        html = build_summary_cards(data)

        assert any(phrase in html.lower() for phrase in [
            'per-message', 'per message', 'token delta', 'delta',
            'prefix cach', 'prior context',
        ]), \
            "Cache hit rate tooltip does not explain the estimation methodology"

    def test_cache_cards_hit_rate_has_disclaimer(self):
        """4.1.3 — Cache section cards must include a disclaimer about simulated estimates."""
        cache_estimate = _make_minimal_data()['cache_estimate']
        html = build_cache_cards(cache_estimate)

        # The cache cards already have a paragraph disclaimer. Verify it's present.
        assert any(phrase in html.lower() for phrase in [
            'simulated', 'estimated', 'estimate', 'approximation',
            'if the llm provider', 'prefix caching',
        ]), \
            "Cache cards section missing disclaimer about simulated estimates"


class TestP42_ProductiveSessionsEstimationNote:
    """P4-2: Productive sessions metric must note it is estimated from token ratios.

    When per-agent daily session counts are not available, productive_sessions
    is estimated from token ratios. This estimation method must be documented
    in the report.
    """

    def test_productivity_notes_mentions_estimated(self):
        """4.2.1 — Productivity notes must mention that productive sessions is estimated."""
        data = _make_minimal_data()
        html = build_productivity_notes(data)

        assert any(phrase in html.lower() for phrase in [
            'estimated', 'estimate', 'approximation', 'token ratio',
            'token-ratio', 'proportional',
        ]), \
            "Productivity notes do not mention that productive sessions is estimated"

    def test_productivity_notes_explains_token_ratio_method(self):
        """4.2.2 — Notes should explain the token-ratio estimation method."""
        data = _make_minimal_data()
        html = build_productivity_notes(data)

        # Should explain how the estimate is derived
        assert any(phrase in html.lower() for phrase in [
            'token ratio', 'token-ratio', 'proportional', 'build fraction',
            'build token', 'build share',
        ]), \
            "Productivity notes do not explain the token-ratio estimation method"


class TestP43_SKILLMDGotcha:
    """P4-3: SKILL.md gotchas must document simulated estimates.

    The SKILL.md gotchas section should warn users that cache hit rate
    and productive sessions are simulated estimates, not ground truth.
    """

    def test_skill_md_has_simulated_estimates_gotcha(self):
        """4.3.1 — SKILL.md gotchas section must mention simulated/estimated metrics."""
        skill_path = Path(__file__).parent.parent / "SKILL.md"
        content = skill_path.read_text()

        gotchas_section = content[content.index('## Gotchas'):] if '## Gotchas' in content else ''
        assert gotchas_section, "SKILL.md missing Gotchas section"

        assert any(phrase in gotchas_section.lower() for phrase in [
            'simulated', 'estimated', 'estimate', 'cache hit rate',
        ]), \
            "SKILL.md Gotchas section does not document that cache hit rate is simulated"

    def test_skill_md_gotcha_mentions_cache_is_simulated(self):
        """4.3.2 — Gotcha should specifically call out cache hit rate as simulated."""
        skill_path = Path(__file__).parent.parent / "SKILL.md"
        content = skill_path.read_text()

        gotchas_section = content[content.index('## Gotchas'):] if '## Gotchas' in content else ''

        # Should mention cache hit rate specifically
        assert 'cache hit rate' in gotchas_section.lower() or 'cache' in gotchas_section.lower(), \
            "SKILL.md Gotchas section does not mention cache metrics"
        # Should indicate it's an estimate/simulation
        assert any(phrase in gotchas_section.lower() for phrase in [
            'simulated', 'estimate', 'approximation', 'not actual',
        ]), \
            "SKILL.md Gotchas section does not indicate cache metrics are simulated"
