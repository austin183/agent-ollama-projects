"""Model pricing: the lmstudio/ prefix adapter and cost computation."""

import logging

from model_pricing import MODEL_PRICING, compute_cost, get_pricing
from queries.utils import pricing_model_id


def test_pricing_model_id_strips_lmstudio_when_known():
    # 'qwen-agentworld-35b-a3b' is a known table key (local model row)
    assert 'qwen-agentworld-35b-a3b' in MODEL_PRICING
    assert pricing_model_id('lmstudio/qwen-agentworld-35b-a3b') == 'qwen-agentworld-35b-a3b'
    # unknown lmstudio models keep their full id (falls back downstream)
    assert pricing_model_id('lmstudio/qwen/qwen3.8-27b') == 'lmstudio/qwen/qwen3.8-27b'


def test_pricing_model_id_passthrough_for_cloud_ids():
    assert pricing_model_id('anthropic/claude-sonnet-4') == 'anthropic/claude-sonnet-4'
    assert pricing_model_id('') == ''


def test_known_model_prices():
    p = get_pricing('anthropic/claude-sonnet-4')
    assert p['input'] == 3.00
    assert p['output'] == 15.00
    assert p['cached_input'] == 0.30


def test_unknown_model_falls_back_with_warning(caplog):
    # Fresh id: get_pricing warns only once per id (module-level memo)
    with caplog.at_level(logging.WARNING, logger='model_pricing'):
        p = get_pricing('totally/unknown-model-xyz')
    assert p == MODEL_PRICING['fallback']
    assert 'totally/unknown-model-xyz' in caplog.text


def test_compute_cost_with_cache_savings():
    raw = compute_cost('anthropic/claude-sonnet-4', 1_000_000, 100_000)
    cached = compute_cost('anthropic/claude-sonnet-4', 1_000_000, 100_000,
                          cached_input_tokens=900_000)
    # 100K uncached @ 3.00/M + 900K cached @ 0.30/M + 100K output @ 15.00/M
    expected_adj = (100_000 * 3.00 + 900_000 * 0.30 + 100_000 * 15.00) / 1e6
    assert cached['cache_adjusted_cost'] == round(expected_adj, 4)
    assert cached['raw_cost'] == (1_000_000 * 3.00 + 100_000 * 15.00) / 1e6
    assert cached['cache_savings'] > 0
    assert cached['cache_adjusted_cost'] < raw['raw_cost']
