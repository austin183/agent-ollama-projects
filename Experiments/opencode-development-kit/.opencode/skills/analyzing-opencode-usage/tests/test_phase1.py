#!/usr/bin/env python3
"""Tests for Phase 1 data accuracy fixes: productive_sessions, zero-token validation, top_sessions dates.

P1.1: productive_sessions max(1) inflation — commit dates with zero build tokens
  1.1.1  A commit date with 0 build_tok contributes 0 (not 1) to productive_build_sessions
  1.1.2  productive_build_sessions capped at total_build_sessions (safety net)

P1.2: Zero-token session validation
  1.2.1  _validate_models returns warning for model with sessions > 0 and tokens = 0
  1.2.2  _validate_models returns empty list when all models have tokens
  1.2.3  merge_datasets output includes 'warnings' key

P1.3: Top sessions created field
  1.3.1  top_sessions SQL includes time_created column
  1.3.2  TopSessionRow created field is populated from query (not hardcoded '')
"""

import sys
from pathlib import Path

# Add script directory to path so we can import modules
sys.path.insert(0, str(Path(__file__).parent.parent / "script"))

from aggregator.merge import merge_datasets, _validate_models


def _make_minimal_datasets(overrides: dict | None = None) -> dict:
    """Return minimal datasets that produce a valid merge output.

    Args:
        overrides: Optional dict of dataset-level overrides.

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
            if key in defaults and isinstance(defaults[key], list) and isinstance(value, list):
                defaults[key] = value
            elif key in defaults and isinstance(defaults[key], dict) and isinstance(value, dict):
                defaults[key] = {**defaults[key], **value}
            else:
                defaults[key] = value
    return defaults


class TestP1_ProductiveSessionsNoInflation:
    """P1.1: productive_sessions must not inflate via max(1, ...) floor."""

    def test_productive_sessions_uses_max_zero_not_max_one(self):
        """1.1.1 — The productive_sessions formula must use max(0, ...), not max(1, ...).

        The bug: max(1, round(sessions * build_tok / total_effective)) forces at least 1
        session per commit date. With very small build ratios, this inflates counts.
        The fix: use max(0, ...) so days with negligible build contribution yield 0.

        This test verifies the source code uses max(0, ...) not max(1, ...).
        """
        source_path = Path(__file__).parent.parent / "script" / "aggregator" / "merge.py"
        source = source_path.read_text()

        # Find the productive_build_sessions computation
        assert 'max(0,' in source or 'max( 0,' in source, \
            "merge.py productive_sessions should use max(0, ...) not max(1, ...)"

        # The old buggy pattern
        lines = source.split('\n')
        for i, line in enumerate(lines):
            if 'productive_build_sessions' in line and 'sum(' in line:
                # Check the next few lines for the max(1, ...) pattern
                context = '\n'.join(lines[i:i+5])
                assert 'max(1,' not in context and 'max( 1,' not in context, \
                    f"merge.py still uses max(1, ...) in productive_sessions calculation:\n{context}"

    def test_productive_sessions_safety_net_caps_at_total_build(self):
        """1.1.2 — productive_build_sessions never exceeds total_build_sessions.

        Even if the token-ratio estimate produces a large number, the safety net
        must cap it at total_build_sessions.
        """
        datasets = _make_minimal_datasets({
            'daily_agent': [
                {'day': '2026-08-01', 'sessions': 100, 'total_tokens_raw': 100000,
                 'input_tokens_raw': 60000, 'output_tokens_raw': 30000,
                 'reasoning_tokens_raw': 10000, 'build_tok_raw': 100000,
                 'review_tok_raw': 0, 'plan_tok_raw': 0,
                 'explore_tok_raw': 0, 'other_tok_raw': 0},
            ],
            'daily_git': [
                {'date': '2026-08-01', 'commits': 5, 'adds': 500, 'dels': 200,
                 'test_adds': 100, 'test_dels': 50},
            ],
            'build_prod_raw': [{'total_build_sessions': 2, 'total_tokens': 100000}],
        })
        output = merge_datasets(**datasets)

        bp = output['build_productivity'][0]
        prod = bp.get('productive_sessions', 0)
        total = bp.get('total_build_sessions', 0)

        # With 100 sessions and 100% build tokens, the ratio would estimate 100.
        # But total_build_sessions is only 2, so it must be capped.
        assert prod <= total, \
            f"productive_sessions ({prod}) exceeds total_build_sessions ({total})"
        assert prod == 2, \
            f"Expected capped at 2, got {prod}"


class TestP1_ZeroTokenValidation:
    """P1.2: _validate_models() identifies zero-token session anomalies."""

    def test_validate_models_returns_warning_for_zero_tokens(self):
        """1.2.1 — Model with sessions > 0 and total_tokens_raw = 0 produces a warning."""
        models_data = [
            {'model': 'qwen/qwen3.5-9b', 'sessions': 2, 'total_tokens_raw': 0,
             'input_tokens_raw': 0, 'output_tokens_raw': 0, 'reasoning_tokens_raw': 0},
        ]
        warnings = _validate_models(models_data)

        assert len(warnings) == 1, f"Expected 1 warning, got {len(warnings)}"
        assert 'qwen/qwen3.5-9b' in warnings[0]
        assert '0 tokens' in warnings[0] or 'zero' in warnings[0].lower()

    def test_validate_models_returns_empty_for_normal_models(self):
        """1.2.2 — Models with sessions and tokens produce no warnings."""
        models_data = [
            {'model': 'qwen/qwen3.6-27b', 'sessions': 5, 'total_tokens_raw': 100000,
             'input_tokens_raw': 60000, 'output_tokens_raw': 30000, 'reasoning_tokens_raw': 10000},
            {'model': 'claude-3-haiku', 'sessions': 3, 'total_tokens_raw': 50000,
             'input_tokens_raw': 30000, 'output_tokens_raw': 20000, 'reasoning_tokens_raw': 0},
        ]
        warnings = _validate_models(models_data)

        assert len(warnings) == 0, f"Expected no warnings for normal models, got {warnings}"

    def test_validate_models_ignores_model_with_no_sessions(self):
        """A model with 0 sessions and 0 tokens is not a warning (no activity to validate)."""
        models_data = [
            {'model': 'unused-model', 'sessions': 0, 'total_tokens_raw': 0,
             'input_tokens_raw': 0, 'output_tokens_raw': 0, 'reasoning_tokens_raw': 0},
        ]
        warnings = _validate_models(models_data)

        assert len(warnings) == 0, \
            f"Model with 0 sessions should not produce a warning: {warnings}"

    def test_validate_models_mixed_data_warns_only_anomalous(self):
        """Only models with sessions > 0 AND tokens = 0 produce warnings."""
        models_data = [
            {'model': 'good-model', 'sessions': 5, 'total_tokens_raw': 10000,
             'input_tokens_raw': 6000, 'output_tokens_raw': 4000, 'reasoning_tokens_raw': 0},
            {'model': 'bad-model', 'sessions': 3, 'total_tokens_raw': 0,
             'input_tokens_raw': 0, 'output_tokens_raw': 0, 'reasoning_tokens_raw': 0},
            {'model': 'unused-model', 'sessions': 0, 'total_tokens_raw': 0,
             'input_tokens_raw': 0, 'output_tokens_raw': 0, 'reasoning_tokens_raw': 0},
        ]
        warnings = _validate_models(models_data)

        assert len(warnings) == 1, f"Expected 1 warning (bad-model only), got {len(warnings)}"
        assert 'bad-model' in warnings[0]

    def test_merge_datasets_includes_warnings_key(self):
        """1.2.3 — merge_datasets output includes 'warnings' key in the report."""
        datasets = _make_minimal_datasets({
            'models_data': [
                {'model': 'qwen/qwen3.6-27b', 'input_tokens_raw': 11000,
                 'output_tokens_raw': 5000, 'reasoning_tokens_raw': 2000,
                 'sessions': 8, 'total_tokens_raw': 18000},
                {'model': 'qwen/qwen3.5-9b', 'input_tokens_raw': 0,
                 'output_tokens_raw': 0, 'reasoning_tokens_raw': 0,
                 'sessions': 2, 'total_tokens_raw': 0},
            ],
        })
        output = merge_datasets(**datasets)

        assert 'warnings' in output, \
            f"merge_datasets output missing 'warnings' key. Keys: {list(output.keys())}"
        assert isinstance(output['warnings'], list), \
            f"warnings should be a list, got {type(output['warnings'])}"

    def test_merge_datasets_warnings_includes_zero_token_model(self):
        """When a model has zero tokens, the warnings list includes it."""
        datasets = _make_minimal_datasets({
            'models_data': [
                {'model': 'qwen/qwen3.5-9b', 'input_tokens_raw': 0,
                 'output_tokens_raw': 0, 'reasoning_tokens_raw': 0,
                 'sessions': 2, 'total_tokens_raw': 0},
            ],
        })
        output = merge_datasets(**datasets)

        warnings = output.get('warnings', [])
        assert len(warnings) >= 1, \
            f"Expected at least 1 warning for zero-token model, got {warnings}"
        assert any('qwen/qwen3.5-9b' in w for w in warnings), \
            f"Warning should mention qwen/qwen3.5-9b: {warnings}"


class TestP1_TopSessionsCreatedField:
    """P1.3: top_sessions SQL must include time_created column."""

    def test_top_sessions_sql_selects_time_created(self):
        """1.3.1 — The SQL query in top_sessions.py must SELECT time_created (not just filter on it).

        The WHERE clause already references time_created for date filtering.
        The fix adds time_created to the SELECT list so the 'created' field is populated.
        """
        source_path = Path(__file__).parent.parent / "script" / "queries" / "top_sessions.py"
        source = source_path.read_text()

        # Find the SQL string and check it has time_created in SELECT (before FROM)
        import re
        sql_match = re.search(r'sql\s*=\s*f?"""(.*?)"""', source, re.DOTALL)
        if sql_match:
            sql_body = sql_match.group(1)
            select_section = sql_body.split('FROM')[0] if 'FROM' in sql_body else sql_body
            assert 'time_created' in select_section or 'strftime' in select_section, \
                "top_sessions.py SQL SELECT clause does not include time_created"
        else:
            # Fallback: check that strftime appears in SELECT context
            assert "strftime('%Y-%m-%d', time_created" in source.split('FROM')[0] if 'FROM' in source else source, \
                "top_sessions.py SQL does not format time_created in SELECT"

    def test_top_sessions_row_created_not_hardcoded_empty(self):
        """1.3.2 — TopSessionRow created field must not be hardcoded to empty string."""
        source_path = Path(__file__).parent.parent / "script" / "queries" / "top_sessions.py"
        source = source_path.read_text()

        # The old code had: created='',  # Not in query
        # The fix should use: created=r.get('created', '') or ''
        assert "created='',  # Not in query" not in source, \
            "top_sessions.py still has hardcoded empty string for created field"

        # Verify created is populated from the row data
        assert "r.get('created'" in source, \
            "top_sessions.py should populate created from query result"
