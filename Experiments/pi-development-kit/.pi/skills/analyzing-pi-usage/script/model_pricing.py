#!/usr/bin/env python3
"""Per-model pricing lookup and cost computation for LLM usage reports.

Provides cloud-equivalent cost estimates for locally-run models. All models
run locally via LM Studio (actual cost: $0), but this module computes what
they would cost if run through cloud APIs, enabling cost comparison and
cache savings analysis.

Pricing rates are per 1M tokens.

Usage as module:
    from model_pricing import MODEL_PRICING, get_pricing, compute_cost, enrich_models_with_cost

Usage standalone:
    python3 model_pricing.py < models.json > models-with-cost.json
"""

import json
import logging
import sys


# Flat-rate tiers for quick cost estimation (per 1M tokens)
FLAT_RATES = {
    'cheap':     {'input': 0.05, 'output': 0.15, 'cached_input': 0.01},
    'expensive': {'input': 0.50, 'output': 1.50, 'cached_input': 0.05},
}

logger = logging.getLogger(__name__)

# Track which models have triggered fallback warnings (avoid repeated logging)
_FALLBACK_WARNED: set = set()

MODEL_PRICING = {
    # Cloud providers (real public pricing, per 1M tokens)
    'openai/gpt-4o':              {'input': 2.50,  'output': 10.00, 'cached_input': 1.25},
    'anthropic/claude-sonnet-4':  {'input': 3.00,  'output': 15.00, 'cached_input': 0.30},
    'google/gemma-4-31b-qat':     {'input': 0.25,  'output': 1.00,  'cached_input': 0.025},
    # Local models (cloud-equivalent estimates for "what-if" cost, per 1M tokens)
    'qwen/qwen3.6-27b':           {'input': 0.50,  'output': 1.50,  'cached_input': 0.05},
    'qwen/qwen3.6-35b-a3b':       {'input': 0.80,  'output': 2.40,  'cached_input': 0.08},
    'qwen/qwq-32b':               {'input': 0.60,  'output': 1.80,  'cached_input': 0.06},
    'ornith-1.0-35b':             {'input': 0.70,  'output': 2.10,  'cached_input': 0.07},
    'qwen/qwen3-coder-next':      {'input': 0.75,  'output': 2.25,  'cached_input': 0.075},
    'qwen-agentworld-35b-a3b':    {'input': 0.80,  'output': 2.40,  'cached_input': 0.08},
    'gemini/gemini-2.5-flash':    {'input': 0.15,  'output': 0.60,  'cached_input': 0.015},
    # Additional local models (cloud-equivalent estimates)
    'laguna-s-2.1':               {'input': 0.50,  'output': 1.50,  'cached_input': 0.05},
    'qwen/qwen3.6-27b-q4':        {'input': 0.50,  'output': 1.50,  'cached_input': 0.05},
    'qwen/qwen3.6-27b-lite':      {'input': 0.40,  'output': 1.20,  'cached_input': 0.04},
    'qwen/qwen3.5-9b':            {'input': 0.30,  'output': 0.60,  'cached_input': 0.03},
    # Custom/local models
    'agents-a1':                  {'input': 0.50,  'output': 1.50,  'cached_input': 0.05},
    'big-pickle':                 {'input': 0.50,  'output': 1.50,  'cached_input': 0.05},
    # Fallback for unknown models
    'fallback':                   {'input': 0.50,  'output': 1.50,  'cached_input': 0.05},
}


def get_pricing(model_id):
    """Get pricing dict for a model. Falls back to generic pricing if unknown.

    Args:
        model_id: Model identifier string (e.g., 'qwen/qwen3.6-27b')

    Returns:
        dict with 'input', 'output', 'cached_input' rates (per 1M tokens)
    """
    if not model_id:
        return MODEL_PRICING['fallback']
    if model_id in MODEL_PRICING:
        return MODEL_PRICING[model_id]
    # Unknown model — warn once per model ID
    if model_id not in _FALLBACK_WARNED:
        logger.warning(
            "Model '%s' not found in pricing table. Using fallback rates "
            "(input: $0.50/M, output: $1.50/M). Add to MODEL_PRICING for accuracy.",
            model_id
        )
        _FALLBACK_WARNED.add(model_id)
    return MODEL_PRICING['fallback']


def compute_cost(model_id, input_tokens, output_tokens, cached_input_tokens=0):
    """Compute cloud-equivalent cost for a set of tokens.

    Args:
        model_id: Model identifier string
        input_tokens: Total input tokens
        output_tokens: Total output tokens
        cached_input_tokens: Number of input tokens served from cache

    Returns:
        dict with 'raw_cost', 'cache_adjusted_cost', 'cache_savings' in USD
    """
    pricing = get_pricing(model_id)
    uncached = max(0, input_tokens - cached_input_tokens)

    raw_cost = (
        input_tokens * pricing['input'] / 1_000_000
        + output_tokens * pricing['output'] / 1_000_000
    )
    cache_adjusted_cost = (
        uncached * pricing['input'] / 1_000_000
        + cached_input_tokens * pricing['cached_input'] / 1_000_000
        + output_tokens * pricing['output'] / 1_000_000
    )
    cache_savings = round(raw_cost - cache_adjusted_cost, 4)

    return {
        'raw_cost': round(raw_cost, 4),
        'cache_adjusted_cost': round(cache_adjusted_cost, 4),
        'cache_savings': round(cache_savings, 4),
    }


def enrich_models_with_cost(models_data, cache_by_model=None):
    """Add per-model cost data to models list.

    Args:
        models_data: List of model dicts with 'model', 'input_tokens_raw', 'output_tokens_raw', 'reasoning_tokens_raw' keys
        cache_by_model: Optional dict mapping model name to cache estimate dict

    Returns:
        List of model dicts with additional cost fields:
            - raw_cost: cloud-equivalent cost without caching
            - cache_adjusted_cost: cost with prefix caching
            - cache_savings: dollars saved by caching
    """
    if not cache_by_model:
        cache_by_model = {}

    enriched = []
    for m in models_data:
        model_id = m.get('model', 'unknown')
        input_tok = m.get('input_tokens_raw', 0) or 0
        output_tok = m.get('output_tokens_raw', 0) or 0
        reasoning_tok = m.get('reasoning_tokens_raw', 0) or 0

        cache_info = cache_by_model.get(model_id, {})
        cached_input = cache_info.get('estimated_cached_input', 0) or 0

        cost = compute_cost(model_id, input_tok, output_tok + reasoning_tok, cached_input)

        entry = {**m, **cost}
        enriched.append(entry)

    return enriched


def compute_total_cost(models_data, cache_by_model=None):
    """Compute aggregate cloud-equivalent costs across all models.

    Args:
        models_data: List of model dicts with 'model', 'input_tokens_raw', 'output_tokens_raw', 'reasoning_tokens_raw' keys
        cache_by_model: Optional dict mapping model name to cache estimate dict

    Returns:
        dict with 'total_raw_cost', 'total_cache_adjusted_cost', 'total_cache_savings' in USD
    """
    if not cache_by_model:
        cache_by_model = {}

    total_raw = 0.0
    total_adjusted = 0.0

    for m in models_data:
        model_id = m.get('model', 'unknown')
        input_tok = m.get('input_tokens_raw', 0) or 0
        output_tok = m.get('output_tokens_raw', 0) or 0
        reasoning_tok = m.get('reasoning_tokens_raw', 0) or 0

        cache_info = cache_by_model.get(model_id, {})
        cached_input = cache_info.get('estimated_cached_input', 0) or 0

        cost = compute_cost(model_id, input_tok, output_tok + reasoning_tok, cached_input)
        total_raw += cost['raw_cost']
        total_adjusted += cost['cache_adjusted_cost']

    return {
        'total_raw_cost': round(total_raw, 2),
        'total_cache_adjusted_cost': round(total_adjusted, 2),
        'total_cache_savings': round(total_raw - total_adjusted, 2),
    }


def compute_flat_cost(input_tokens, output_tokens, cached_input_tokens, tier='cheap'):
    """Compute cost using flat-rate pricing tier.

    Args:
        input_tokens: Total input tokens.
        output_tokens: Total output tokens.
        cached_input_tokens: Number of input tokens served from cache.
        tier: 'cheap' or 'expensive'.

    Returns:
        dict with 'raw_cost', 'cache_adjusted_cost' in USD.
    """
    rates = FLAT_RATES[tier]
    uncached = max(0, input_tokens - cached_input_tokens)

    raw_cost = (
        input_tokens * rates['input'] / 1_000_000
        + output_tokens * rates['output'] / 1_000_000
    )
    cache_adjusted_cost = (
        uncached * rates['input'] / 1_000_000
        + cached_input_tokens * rates['cached_input'] / 1_000_000
        + output_tokens * rates['output'] / 1_000_000
    )

    return {
        'raw_cost': round(raw_cost, 4),
        'cache_adjusted_cost': round(cache_adjusted_cost, 4),
    }


def compute_total_flat_cost(models_data, cache_by_model=None):
    """Compute aggregate costs using flat-rate pricing tiers.

    Args:
        models_data: List of model dicts with token counts.
        cache_by_model: Optional dict mapping model name to cache estimate dict.

    Returns:
        dict with 'cheap_raw', 'cheap_cache', 'expensive_raw', 'expensive_cache' in USD.
    """
    if not cache_by_model:
        cache_by_model = {}

    totals = {tier: {'raw': 0.0, 'cache': 0.0} for tier in ('cheap', 'expensive')}

    for m in models_data:
        model_id = m.get('model', 'unknown')
        input_tok = m.get('input_tokens_raw', 0) or 0
        output_tok = m.get('output_tokens_raw', 0) or 0
        reasoning_tok = m.get('reasoning_tokens_raw', 0) or 0
        total_out = output_tok + reasoning_tok

        cache_info = cache_by_model.get(model_id, {})
        cached_input = cache_info.get('estimated_cached_input', 0) or 0

        for tier in ('cheap', 'expensive'):
            cost = compute_flat_cost(input_tok, total_out, cached_input, tier)
            totals[tier]['raw'] += cost['raw_cost']
            totals[tier]['cache'] += cost['cache_adjusted_cost']

    return {
        'cheap_raw': round(totals['cheap']['raw'], 2),
        'cheap_cache': round(totals['cheap']['cache'], 2),
        'expensive_raw': round(totals['expensive']['raw'], 2),
        'expensive_cache': round(totals['expensive']['cache'], 2),
    }


def main():
    """Standalone mode: read models JSON from stdin, output enriched JSON."""
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON input: {e}", file=sys.stderr)
        sys.exit(1)

    models = data if isinstance(data, list) else data.get('models', [])
    cache_by_model = {}
    if isinstance(data, dict) and 'cache_estimate' in data:
        for entry in data['cache_estimate'].get('by_model', []):
            model_name = entry.get('model', 'unknown')
            cache_by_model[model_name] = entry

    enriched = enrich_models_with_cost(models, cache_by_model)
    totals = compute_total_cost(models, cache_by_model)

    output = {
        'models': enriched,
        'totals': totals,
    }
    print(json.dumps(output, indent=2))


if __name__ == '__main__':
    main()
