#!/usr/bin/env python3
"""Tests for aggregator/merge.py — structural correctness bugs B8 and B4.

B8: daily_agent_stacked shares mutable reference with timeseries
  2.1.1.1  merge_datasets() returns output → sort(timeseries) does NOT affect daily_agent_stacked
  2.1.1.2  merge_datasets() returns output → append(daily_agent_stacked) does NOT affect timeseries length

B4: Hardcoded phase dates produce all-zero phases for any report outside May-June 2026
  2.3.2.1  _build_phases() called with July-August 2026 data → returns []
  2.3.2.2  _build_phases() called with May-June 2026 data → returns [] (hardcoded dates removed)
"""

import sys
from pathlib import Path

# Add script directory to path so we can import modules
sys.path.insert(0, str(Path(__file__).parent.parent / "script"))

from aggregator.merge import merge_datasets, _build_phases


class TestB8_MutableReference:
    """B8: daily_agent_stacked must be an independent copy of timeseries."""

    def _make_minimal_datasets(self):
        """Return minimal datasets that produce a valid merge output."""
        return {
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
                 'output_tokens_raw': 5000, 'reasoning_tokens_raw': 2000},
            ],
            'agents_data': [],
            'cross_tab': [],
            'top_sessions': [],
            'productivity_raw': [{'total_sessions': 8, 'daily_sessions': {}}],
            'build_prod_raw': [{}],
            'git_commits': [],
            'daily_git': [
                {'date': '2026-08-01', 'commits': 2, 'adds': 100, 'dels': 50,
                 'test_adds': 20, 'test_dels': 10},
                {'date': '2026-08-02', 'commits': 1, 'adds': 50, 'dels': 20,
                 'test_adds': 10, 'test_dels': 5},
            ],
            'cache_estimate': {'aggregate': {}, 'by_model': [], 'by_agent': [], 'by_day': []},
        }

    def test_timeseries_and_stacked_are_different_objects(self):
        """2.1.1.1 — daily_agent_stacked must not be the same list object as timeseries."""
        datasets = self._make_minimal_datasets()
        output = merge_datasets(**datasets)

        assert output['timeseries'] is not output['daily_agent_stacked'], \
            "timeseries and daily_agent_stacked share the same list reference"

    def test_sorting_timeseries_does_not_affect_stacked(self):
        """2.1.1.1 — mutating timeseries via sort() must not affect daily_agent_stacked."""
        datasets = self._make_minimal_datasets()
        output = merge_datasets(**datasets)

        stacked_before = [dict(row) for row in output['daily_agent_stacked']]
        output['timeseries'].sort(key=lambda r: r['date'], reverse=True)

        stacked_after = list(output['daily_agent_stacked'])
        assert [row['date'] for row in stacked_after] == [row['date'] for row in stacked_before], \
            "Sorting timeseries mutated daily_agent_stacked order"

    def test_appending_to_stacked_does_not_affect_timeseries(self):
        """2.1.1.2 — mutating daily_agent_stacked via append() must not affect timeseries length."""
        datasets = self._make_minimal_datasets()
        output = merge_datasets(**datasets)

        ts_len = len(output['timeseries'])
        output['daily_agent_stacked'].append({'date': '2026-08-99', 'sessions': 0})

        assert len(output['timeseries']) == ts_len, \
            f"Appending to daily_agent_stacked mutated timeseries length: {ts_len} -> {len(output['timeseries'])}"

    def test_appending_to_timeseries_does_not_affect_stacked(self):
        """Symmetric: mutating timeseries via append() must not affect daily_agent_stacked length."""
        datasets = self._make_minimal_datasets()
        output = merge_datasets(**datasets)

        stacked_len = len(output['daily_agent_stacked'])
        output['timeseries'].append({'date': '2026-08-99', 'sessions': 0})

        assert len(output['daily_agent_stacked']) == stacked_len, \
            f"Appending to timeseries mutated daily_agent_stacked length: {stacked_len} -> {len(output['daily_agent_stacked'])}"


class TestB4_HardcodedPhases:
    """B4: _build_phases() must return empty list — no hardcoded phase dates."""

    def test_phases_returns_empty_list(self):
        """2.3.2.1 — _build_phases() returns [] regardless of data provided."""
        result = _build_phases([])
        assert result == [], f"Expected empty list, got {result}"

    def test_phases_returns_empty_with_july_august_data(self):
        """2.3.2.1 — July-August 2026 data should not produce hardcoded phases."""
        merged_daily = [
            {'date': '2026-07-15', 'total_effective': 10000, 'sessions': 5,
             'commits': 2, 'adds': 100, 'test_adds': 20},
            {'date': '2026-08-01', 'total_effective': 15000, 'sessions': 8,
             'commits': 3, 'adds': 150, 'test_adds': 30},
        ]
        result = _build_phases(merged_daily)
        assert result == [], f"Expected empty list for July-Aug data, got {len(result)} phases"

    def test_phases_returns_empty_with_may_june_data(self):
        """2.3.2.2 — Even May-June 2026 data should return [] (hardcoded dates removed)."""
        merged_daily = [
            {'date': '2026-05-15', 'total_effective': 10000, 'sessions': 5,
             'commits': 2, 'adds': 100, 'test_adds': 20},
            {'date': '2026-06-01', 'total_effective': 15000, 'sessions': 8,
             'commits': 3, 'adds': 150, 'test_adds': 30},
        ]
        result = _build_phases(merged_daily)
        assert result == [], f"Expected empty list even for May-June data, got {len(result)} phases"

    def test_phases_is_a_list_type(self):
        """Return type is always list."""
        result = _build_phases([])
        assert isinstance(result, list)
