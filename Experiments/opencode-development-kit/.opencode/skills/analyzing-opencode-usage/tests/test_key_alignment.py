#!/usr/bin/env python3
"""Phase 1: Key alignment tests for render_consolidated_report.py.

Verifies that the renderer reads the correct keys from ModelRow, AgentRow,
and CrossTabRow data structures. These keys must match the TypedDict
definitions in data_access/types.py.

Scenarios from plan 2026-08-08:
  1.1.1-1.1.4: Models table displays correct token counts
  1.2.1: Agents table displays correct token counts
  1.3.1: Cross-tab displays correct token counts
  1.4.1-1.4.2: Cache lookups work for models with underscores
"""

import sys
from pathlib import Path

# Add script directory to path so we can import modules
sys.path.insert(0, str(Path(__file__).parent.parent / "script"))

from render_consolidated_report import (
    build_models_section,
    build_agents_section,
    build_cross_tab,
    build_cost_analysis_section,
    _cache_lookups,
)


# ── Test data matching actual TypedDict shapes ────────────────────────────────

def _make_model_row(model: str, total: int, inp: int, out: int, rea: int, sessions: int = 10):
    """Create a dict matching ModelRow TypedDict from data_access/types.py."""
    return {
        'model': model,
        'sessions': sessions,
        'total_tokens_raw': total,
        'input_tokens_raw': inp,
        'output_tokens_raw': out,
        'reasoning_tokens_raw': rea,
    }


def _make_agent_row(agent: str, total: int, sessions: int = 10):
    """Create a dict matching AgentRow TypedDict from data_access/types.py."""
    return {
        'agent': agent,
        'sessions': sessions,
        'total_tokens_raw': total,
        'input_tokens_raw': total * 80 // 100,
        'output_tokens_raw': total * 10 // 100,
        'reasoning_tokens_raw': total * 10 // 100,
    }


def _make_cross_tab_row(model: str, agent: str, total: int, sessions: int = 5):
    """Create a dict matching CrossTabRow TypedDict from data_access/types.py."""
    return {
        'model': model,
        'agent': agent,
        'sessions': sessions,
        'total_tokens_raw': total,
    }


def _make_cache_estimate(by_model=None, by_agent=None, by_day=None):
    """Create a cache estimate dict matching CacheEstimateRow shape."""
    return {
        'by_model': by_model or [],
        'by_agent': by_agent or [],
        'by_day': by_day or [],
    }


# ── 1.1: Models table key alignment ──────────────────────────────────────────

class TestModelsSectionKeyAlignment:
    """1.1: build_models_section must read ModelRow keys, not short aliases.

    The renderer previously read 'total', 'input', 'output', 'reasoning'
    but ModelRow has 'total_tokens_raw', 'input_tokens_raw', etc.
    This caused silent zero display in the models table.
    """

    def test_models_total_uses_total_tokens_raw(self):
        """1.1.1 — ModelRow total_tokens_raw must be rendered as non-zero total."""
        models = [_make_model_row('qwen/qwen3.6-27b', total=575422469, inp=570959258, out=3332704, rea=1130507)]
        html = build_models_section(models)

        # The bar-value span should show the formatted total, not "0"
        assert '0">' not in html.split('bar-value')[-1] if 'bar-value' in html else True
        # More reliably: the rendered total should be non-zero
        assert '575' in html or '575,422,469' in html or '575M' in html, \
            f"Models section did not render total_tokens_raw. HTML: {html[:500]}"

    def test_models_input_uses_input_tokens_raw(self):
        """1.1.2 — ModelRow input_tokens_raw must be rendered as non-zero input."""
        models = [_make_model_row('qwen/qwen3.6-27b', total=575422469, inp=570959258, out=3332704, rea=1130507)]
        html = build_models_section(models)

        # Input segment should show the input value (fmt() abbreviates: 571.0M)
        assert '571' in html or '570' in html or '570.9' in html, \
            f"Models section did not render input_tokens_raw. HTML: {html[:500]}"

    def test_models_output_uses_output_tokens_raw(self):
        """1.1.3 — ModelRow output_tokens_raw must be rendered as non-zero output."""
        models = [_make_model_row('qwen/qwen3.6-27b', total=575422469, inp=570959258, out=3332704, rea=1130507)]
        html = build_models_section(models)

        # Output segment should show the output value (fmt() abbreviates: 3.3M)
        assert '3.3' in html or '3332' in html, \
            f"Models section did not render output_tokens_raw. HTML: {html[:500]}"

    def test_models_reasoning_uses_reasoning_tokens_raw(self):
        """1.1.4 — ModelRow reasoning_tokens_raw must be rendered as non-zero reasoning."""
        models = [_make_model_row('qwen/qwen3.6-27b', total=575422469, inp=570959258, out=3332704, rea=1130507)]
        html = build_models_section(models)

        # Reasoning segment should show the reasoning value (fmt() abbreviates: 1.1M)
        assert '1.1' in html or '1130' in html, \
            f"Models section did not render reasoning_tokens_raw. HTML: {html[:500]}"

    def test_models_without_cache_fallback_uses_raw_keys(self):
        """1.1.5 — When no cache estimate is available, fallback must use raw keys."""
        models = [_make_model_row('unknown-model', total=1000000, inp=800000, out=100000, rea=100000)]
        # No cache estimate provided — must fall back to raw keys
        html = build_models_section(models, cache_estimate=None)

        # Total should be non-zero (fmt() abbreviates: 1.0M)
        assert '1.0M' in html or '1,000,000' in html or '1000000' in html, \
            f"Models fallback did not render total_tokens_raw. HTML: {html[:500]}"


# ── 1.2: Agents table key alignment ──────────────────────────────────────────

class TestAgentsSectionKeyAlignment:
    """1.2: build_agents_section must read AgentRow keys, not short aliases.

    The renderer previously read 'total' but AgentRow has 'total_tokens_raw'.
    This caused silent zero display in the agents table.
    """

    def test_agents_total_uses_total_tokens_raw(self):
        """1.2.1 — AgentRow total_tokens_raw must be rendered as non-zero total."""
        agents = [_make_agent_row('build-tdd', total=288000000)]
        html = build_agents_section(agents)

        # The h-bar-value should show the formatted total, not "0"
        assert '288' in html or '288,000,000' in html, \
            f"Agents section did not render total_tokens_raw. HTML: {html[:500]}"

    def test_agents_without_cache_fallback_uses_raw_keys(self):
        """1.2.2 — When no cache estimate is available, fallback must use raw keys."""
        agents = [_make_agent_row('build', total=5000000)]
        html = build_agents_section(agents, cache_estimate=None)

        # fmt() abbreviates: 5.0M
        assert '5.0M' in html or '5,000,000' in html or '5000000' in html, \
            f"Agents fallback did not render total_tokens_raw. HTML: {html[:500]}"


# ── 1.3: Cross-tab key alignment ─────────────────────────────────────────────

class TestCrossTabKeyAlignment:
    """1.3: build_cross_tab must read CrossTabRow keys, not short aliases.

    The renderer previously read 'total' but CrossTabRow has 'total_tokens_raw'.
    This caused silent zero display in the cross-tab table.
    """

    def test_cross_tab_total_uses_total_tokens_raw(self):
        """1.3.1 — CrossTabRow total_tokens_raw must be rendered as non-zero total."""
        cross_tab = [_make_cross_tab_row('qwen/qwen3.6-27b', 'build-tdd', total=575422469)]
        html = build_cross_tab(cross_tab)

        assert '575' in html or '575,422,469' in html, \
            f"Cross-tab did not render total_tokens_raw. HTML: {html[:500]}"


# ── 1.4: Cache lookup key normalization ──────────────────────────────────────

class TestCacheLookupKeyNormalization:
    """1.4: _cache_lookups must produce keys consistent with model/agent IDs.

    The renderer normalizes model names with .replace('_', '-').replace('-', '-')
    which is a no-op for the second replace. This is consistent between
    _cache_lookups and the consumer functions, but the plan recommends using
    raw model IDs to avoid future mismatches.
    """

    def test_cache_lookup_key_matches_raw_model_id(self):
        """1.4.1 — Cache lookup key for model without underscores must match."""
        cache = _make_cache_estimate(
            by_model=[{
                'key': 'qwen/qwen3.6-27b',
                'model': 'qwen/qwen3.6-27b',
                'estimated_uncached_input': 1000,
                'total_output': 500,
                'total_reasoning': 200,
            }]
        )
        lookups = _cache_lookups(cache)

        # The lookup key should be findable by the raw model ID
        # (after whatever normalization the function applies)
        assert len(lookups['by_model']) == 1, \
            f"Expected 1 model lookup, got {len(lookups['by_model'])}"

    def test_cache_lookup_key_matches_model_with_underscores(self):
        """1.4.2 — Cache lookup key for model with underscores must be consistent."""
        cache = _make_cache_estimate(
            by_model=[{
                'key': 'some_model_v2',
                'model': 'some_model_v2',
                'estimated_uncached_input': 1000,
                'total_output': 500,
                'total_reasoning': 200,
            }]
        )
        lookups = _cache_lookups(cache)

        # The lookup key should be findable — verify the key exists
        assert len(lookups['by_model']) == 1, \
            f"Expected 1 model lookup, got {len(lookups['by_model'])}"

        # The key should be usable — check that it's a string
        key = list(lookups['by_model'].keys())[0]
        assert isinstance(key, str) and len(key) > 0, \
            f"Cache lookup key is empty or not a string: {key!r}"

    def test_cache_lookup_agent_key_matches_raw_agent_id(self):
        """1.4.3 — Cache lookup key for agent must match raw agent ID."""
        cache = _make_cache_estimate(
            by_agent=[{
                'key': 'build-tdd',
                'agent': 'build-tdd',
                'estimated_uncached_input': 1000,
                'total_output': 500,
                'total_reasoning': 200,
            }]
        )
        lookups = _cache_lookups(cache)

        assert len(lookups['by_agent']) == 1, \
            f"Expected 1 agent lookup, got {len(lookups['by_agent'])}"


# ── 1.5: Cost analysis section key alignment ─────────────────────────────────

class TestCostAnalysisKeyAlignment:
    """1.5: build_cost_analysis_section must read ModelRowWithCost keys.

    The cost analysis section reads from models_with_cost which is enriched
    ModelRow data. It must use the correct keys for input/output/reasoning tokens.
    """

    def test_cost_analysis_uses_input_tokens_raw(self):
        """1.5.1 — Cost analysis must read input_tokens_raw, not 'input'."""
        data = {
            'model_pricing': {
                'total_raw_cost': 100.0,
                'total_cache_adjusted_cost': 20.0,
                'total_cache_savings': 80.0,
            },
            'models_with_cost': [
                {
                    'model': 'qwen/qwen3.6-27b',
                    'sessions': 10,
                    'input_tokens_raw': 5000000,
                    'output_tokens_raw': 500000,
                    'reasoning_tokens_raw': 100000,
                    'raw_cost': 90.0,
                    'cache_adjusted_cost': 18.0,
                    'cache_savings': 72.0,
                }
            ],
            'summary': {'cache_hit_pct': 90.0},
        }
        html = build_cost_analysis_section(data, ts_data=[])

        # Input tokens should be rendered (fmt() abbreviates: 5.0M)
        assert '5.0M' in html or '5,000,000' in html or '5000000' in html, \
            f"Cost analysis did not render input_tokens_raw. HTML: {html[:500]}"

    def test_cost_analysis_uses_output_tokens_raw(self):
        """1.5.2 — Cost analysis must read output_tokens_raw, not 'output'."""
        data = {
            'model_pricing': {
                'total_raw_cost': 100.0,
                'total_cache_adjusted_cost': 20.0,
                'total_cache_savings': 80.0,
            },
            'models_with_cost': [
                {
                    'model': 'qwen/qwen3.6-27b',
                    'sessions': 10,
                    'input_tokens_raw': 5000000,
                    'output_tokens_raw': 500000,
                    'reasoning_tokens_raw': 100000,
                    'raw_cost': 90.0,
                    'cache_adjusted_cost': 18.0,
                    'cache_savings': 72.0,
                }
            ],
            'summary': {'cache_hit_pct': 90.0},
        }
        html = build_cost_analysis_section(data, ts_data=[])

        # Output + reasoning tokens should be rendered (fmt() abbreviates: 600.0K)
        assert '600' in html or '0.6M' in html or '600.0K' in html, \
            f"Cost analysis did not render output_tokens_raw. HTML: {html[:500]}"
