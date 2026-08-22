#!/usr/bin/env python3
"""Tests for queries/productivity.py — dead SQL bug B9.

B9: summary_files column never populated, producing always-zero results
  2.2.1.1  productivity.fetch() SQL must NOT reference summary_files
  2.2.1.2  productivity fetch result must contain total_sessions and daily_sessions keys
"""

import sys
from pathlib import Path

# Add script directory to path so we can import modules
sys.path.insert(0, str(Path(__file__).parent.parent / "script"))


class TestB9_DeadSQL:
    """B9: productivity.py must not reference summary_files in SQL."""

    def test_no_summary_files_in_source(self):
        """2.2.1.1 — The SQL in productivity.py must not reference summary_files."""
        source_path = Path(__file__).parent.parent / "script" / "queries" / "productivity.py"
        source = source_path.read_text()

        assert 'summary_files' not in source, \
            "productivity.py still references summary_files column (dead SQL)"

    def test_no_sessions_with_changes_in_return(self):
        """The return dict must not include sessions_with_changes (computed in merge.py)."""
        source_path = Path(__file__).parent.parent / "script" / "queries" / "productivity.py"
        source = source_path.read_text()

        assert 'sessions_with_changes' not in source, \
            "productivity.py still returns sessions_with_changes (should be computed in merge.py)"

    def test_no_pct_with_changes_in_return(self):
        """The return dict must not include pct_with_changes (computed in merge.py)."""
        source_path = Path(__file__).parent.parent / "script" / "queries" / "productivity.py"
        source = source_path.read_text()

        assert 'pct_with_changes' not in source, \
            "productivity.py still returns pct_with_changes (should be computed in merge.py)"

    def test_has_zero_token_filter_in_main_query(self):
        """The main query must filter zero-token sessions (from B5)."""
        source_path = Path(__file__).parent.parent / "script" / "queries" / "productivity.py"
        source = source_path.read_text()

        assert 'tokens_input + tokens_output + tokens_reasoning' in source, \
            "productivity.py main query missing zero-token filter"

    def test_has_zero_token_filter_in_daily_query(self):
        """The daily sub-query must also filter zero-token sessions (from B5)."""
        source_path = Path(__file__).parent.parent / "script" / "queries" / "productivity.py"
        source = source_path.read_text()

        # Count occurrences — should appear in both the main query and daily sub-query
        count = source.count('tokens_input + tokens_output + tokens_reasoning')
        assert count >= 2, \
            f"Expected zero-token filter in both queries, found {count} occurrence(s)"
