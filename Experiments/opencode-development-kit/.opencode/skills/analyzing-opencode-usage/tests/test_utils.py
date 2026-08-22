#!/usr/bin/env python3
"""Tests for queries/utils.py — _resolve_date() function.

Behavior spec from plan B1/B10/R1:
  1.1.1.1  since='2026-08-01', until=None, days=None  → ('2026-08-01', today)
  1.1.1.2  since=None, until='2026-08-01', days=None  → ('2000-01-01', '2026-08-01')
  1.1.1.3  since='2026-08-01', until='2026-08-07', days=None  → ('2026-08-01', '2026-08-07')
  1.1.1.4  since=None, until=None, days=7  → (today-7, today)
  1.1.1.5  since=None, until=None, days=None  → ('2000-01-01', today)
  1.1.1.6  Return value is (str, str), neither is the literal string 'None'
"""

import logging
import sys
from datetime import date, timedelta
from pathlib import Path
from unittest.mock import patch

# Add script directory to path so we can import modules
sys.path.insert(0, str(Path(__file__).parent.parent / "script"))

from queries.utils import _resolve_date


class TestResolveDate:
    """Tests for _resolve_date() — the single canonical date resolver."""

    def test_since_only_defaults_until_to_today(self):
        """1.1.1.1 — since provided, until is None → until defaults to today."""
        today = date.today().isoformat()
        start, end = _resolve_date(since='2026-08-01', until=None, days=None)
        assert start == '2026-08-01'
        assert end == today

    def test_until_only_defaults_since_to_epoch(self):
        """1.1.1.2 — until provided, since is None → since defaults to epoch."""
        start, end = _resolve_date(since=None, until='2026-08-01', days=None)
        assert start == '2000-01-01'
        assert end == '2026-08-01'

    def test_both_provided_preserves_both(self):
        """1.1.1.3 — both since and until provided → both preserved."""
        start, end = _resolve_date(since='2026-08-01', until='2026-08-07', days=None)
        assert start == '2026-08-01'
        assert end == '2026-08-07'

    def test_days_overrides_since_and_until(self):
        """1.1.1.4 — days provided → overrides since/until entirely."""
        today = date.today()
        expected_start = (today - timedelta(days=7)).isoformat()
        expected_end = today.isoformat()
        start, end = _resolve_date(since=None, until=None, days=7)
        assert start == expected_start
        assert end == expected_end

    def test_all_none_defaults_to_full_range(self):
        """1.1.1.5 — all arguments None → epoch to today."""
        today = date.today().isoformat()
        start, end = _resolve_date(since=None, until=None, days=None)
        assert start == '2000-01-01'
        assert end == today

    def test_neither_element_is_literal_none_string(self):
        """1.1.1.6 — return value is (str, str), neither is the string 'None'.

        This is the regression guard for the original str(None) bug that
        produced ('2026-08-01', 'None') when only since was provided.
        """
        # Test all partial combinations that previously produced 'None'
        cases = [
            {'since': '2026-08-01', 'until': None, 'days': None},
            {'since': None, 'until': '2026-08-01', 'days': None},
            {'since': None, 'until': None, 'days': None},
        ]
        for kwargs in cases:
            start, end = _resolve_date(**kwargs)
            assert start != 'None', f"start_date is literal 'None' for {kwargs}"
            assert end != 'None', f"end_date is literal 'None' for {kwargs}"

    def test_returns_tuple_of_strings(self):
        """Return type is always Tuple[str, str]."""
        result = _resolve_date(since='2026-01-01', until='2026-01-07', days=None)
        assert isinstance(result, tuple)
        assert len(result) == 2
        assert isinstance(result[0], str)
        assert isinstance(result[1], str)

    def test_days_with_explicit_since_and_until(self):
        """days takes priority even when since/until are also provided."""
        today = date.today()
        expected_start = (today - timedelta(days=30)).isoformat()
        expected_end = today.isoformat()
        # days should override since/until
        start, end = _resolve_date(
            since='2026-01-01', until='2026-12-31', days=30
        )
        assert start == expected_start
        assert end == expected_end


class TestResolveDateTruthiness:
    """WR-5: _resolve_date() truthiness behavior for falsy values.

    The function uses truthiness checks (`if since`, `if until`) rather
    than explicit `is not None` checks. This means both None and ""
    (empty string) fall through to defaults. This is intentional:
    callers should pass None for missing values, and empty strings
    should be treated the same way.

    These tests characterize and guard the truthiness behavior so that
    a future refactor to `is not None` checks wouldn't silently break
    empty-string handling.
    """

    def test_empty_string_since_defaults_to_epoch(self):
        """WR-5 2.1.1.2 — since="" treated as missing, defaults to epoch."""
        today = date.today().isoformat()
        start, end = _resolve_date(since='', until=None, days=None)
        assert start == '2000-01-01', \
            f"Empty string since should default to epoch, got {start!r}"
        assert end == today

    def test_empty_string_until_defaults_to_today(self):
        """WR-5 — until="" treated as missing, defaults to today."""
        today = date.today().isoformat()
        start, end = _resolve_date(since='2026-08-01', until='', days=None)
        assert start == '2026-08-01'
        assert end == today, \
            f"Empty string until should default to today, got {end!r}"

    def test_both_empty_strings_defaults_to_full_range(self):
        """WR-5 — since="" and until="" both treated as missing."""
        today = date.today().isoformat()
        start, end = _resolve_date(since='', until='', days=None)
        assert start == '2000-01-01'
        assert end == today

    def test_empty_string_with_days_ignored(self):
        """WR-5 — days overrides everything, including empty strings."""
        today = date.today()
        expected_start = (today - timedelta(days=7)).isoformat()
        expected_end = today.isoformat()
        start, end = _resolve_date(since='', until='', days=7)
        assert start == expected_start
        assert end == expected_end

    def test_truthiness_check_documented_in_source(self):
        """WR-5 — the truthiness behavior must be documented in the source.

        This test reads the source file to verify that the truthiness
        pattern is documented with a comment, so future maintainers
        understand why `if since` is used instead of `if since is not None`.
        """
        source_file = Path(__file__).parent.parent / "script" / "queries" / "utils.py"
        source = source_file.read_text()

        # Look for a comment (line starting with #) that documents the
        # truthiness/falsy behavior near the since/until checks
        lines = source.splitlines()
        has_documented_comment = False
        for line in lines:
            stripped = line.strip()
            if not stripped.startswith('#'):
                continue
            # Check if any comment line explains the truthiness behavior
            lower = stripped.lower()
            if any(
                keyword in lower
                for keyword in ['truthiness', 'falsy', 'empty string', 'fall through']
            ):
                has_documented_comment = True
                break

        assert has_documented_comment, \
            "queries/utils.py should contain a comment (starting with #) " \
            "documenting the truthiness behavior of the since/until checks"


class TestResolveDateInputValidation:
    """Phase 2: _resolve_date() hardening — reject 'None' string and invalid dates.

    The original truthiness check (`since if since else default`) passes the
    literal string "None" as a valid date. This class tests that the hardened
    version rejects it, along with other invalid date strings.
    """

    def test_since_literal_none_string_defaults_to_epoch(self):
        """P2 2.1.1 — since='None' treated as missing, defaults to epoch."""
        today = date.today().isoformat()
        start, end = _resolve_date(since='None', until=None, days=None)
        assert start == '2000-01-01', \
            f"Literal 'None' string for since should default to epoch, got {start!r}"
        assert end == today

    def test_until_literal_none_string_defaults_to_today(self):
        """P2 — until='None' treated as missing, defaults to today."""
        today = date.today().isoformat()
        start, end = _resolve_date(since='2026-08-01', until='None', days=None)
        assert start == '2026-08-01'
        assert end == today, \
            f"Literal 'None' string for until should default to today, got {end!r}"

    def test_since_whitespace_padded_none_defaults_to_epoch(self):
        """P2 — since='  None  ' (whitespace-padded) treated as missing."""
        today = date.today().isoformat()
        start, end = _resolve_date(since='  None  ', until=None, days=None)
        assert start == '2000-01-01', \
            f"Whitespace-padded 'None' should default to epoch, got {start!r}"
        assert end == today

    def test_since_lowercase_none_defaults_to_epoch(self):
        """P2 — since='none' (lowercase) treated as missing."""
        today = date.today().isoformat()
        start, end = _resolve_date(since='none', until=None, days=None)
        assert start == '2000-01-01', \
            f"Lowercase 'none' should default to epoch, got {start!r}"
        assert end == today

    def test_since_invalid_date_defaults_to_epoch_with_warning(self):
        """P2 2.1.2 — since='not-a-date' falls back to default, logs warning."""
        today = date.today().isoformat()
        with patch('queries.utils.logger') as mock_logger:
            start, end = _resolve_date(since='not-a-date', until=None, days=None)
        assert start == '2000-01-01', \
            f"Invalid date should default to epoch, got {start!r}"
        assert end == today
        mock_logger.warning.assert_called_once()
        call_args = mock_logger.warning.call_args[0]
        # call_args is (format_string, 'not-a-date', '2000-01-01')
        assert 'not-a-date' in call_args, \
            f"Warning call args should include the invalid date, got {call_args}"

    def test_until_invalid_date_defaults_to_today_with_warning(self):
        """P2 — until='not-a-date' falls back to default, logs warning."""
        with patch('queries.utils.logger') as mock_logger:
            start, end = _resolve_date(since='2026-08-01', until='not-a-date', days=None)
        assert start == '2026-08-01'
        assert end == date.today().isoformat()
        mock_logger.warning.assert_called_once()

    def test_since_impossible_date_defaults_with_warning(self):
        """P2 — since='2026-13-01' (month 13) is invalid, falls back."""
        today = date.today().isoformat()
        with patch('queries.utils.logger') as mock_logger:
            start, end = _resolve_date(since='2026-13-01', until=None, days=None)
        assert start == '2000-01-01', \
            f"Impossible date should default to epoch, got {start!r}"
        assert end == today
        mock_logger.warning.assert_called_once()

    def test_both_invalid_dates_both_fallback_with_two_warnings(self):
        """P2 — both since and until invalid → both fallback, two warnings."""
        today = date.today().isoformat()
        with patch('queries.utils.logger') as mock_logger:
            start, end = _resolve_date(since='bad', until='also-bad', days=None)
        assert start == '2000-01-01'
        assert end == today
        assert mock_logger.warning.call_count == 2

    def test_valid_date_still_accepted(self):
        """P2 2.1.3 — valid date '2026-01-15' is preserved as-is."""
        today = date.today().isoformat()
        start, end = _resolve_date(since='2026-01-15', until=None, days=None)
        assert start == '2026-01-15', \
            f"Valid date should be preserved, got {start!r}"
        assert end == today

    def test_valid_date_no_warning_logged(self):
        """P2 — valid date does NOT trigger a warning."""
        with patch('queries.utils.logger') as mock_logger:
            _resolve_date(since='2026-01-15', until='2026-02-28', days=None)
        mock_logger.warning.assert_not_called()

    def test_parse_or_default_is_importable(self):
        """P2 — _parse_or_default helper function must exist and be importable."""
        from queries.utils import _parse_or_default
        assert callable(_parse_or_default), \
            "_parse_or_default should be a callable function"

    def test_parse_or_default_with_none_returns_default(self):
        """P2 — _parse_or_default(None, 'default') returns 'default'."""
        from queries.utils import _parse_or_default
        result = _parse_or_default(None, '2000-01-01')
        assert result == '2000-01-01'

    def test_parse_or_default_with_empty_string_returns_default(self):
        """P2 — _parse_or_default('', 'default') returns 'default'."""
        from queries.utils import _parse_or_default
        result = _parse_or_default('', '2000-01-01')
        assert result == '2000-01-01'

    def test_parse_or_default_with_literal_none_string_returns_default(self):
        """P2 — _parse_or_default('None', 'default') returns 'default'."""
        from queries.utils import _parse_or_default
        result = _parse_or_default('None', '2000-01-01')
        assert result == '2000-01-01', \
            f"Literal 'None' string should return default, got {result!r}"

    def test_parse_or_default_with_invalid_date_returns_default(self):
        """P2 — _parse_or_default('not-a-date', 'default') returns 'default'."""
        from queries.utils import _parse_or_default
        with patch('queries.utils.logger') as mock_logger:
            result = _parse_or_default('not-a-date', '2000-01-01')
        assert result == '2000-01-01', \
            f"Invalid date should return default, got {result!r}"
        mock_logger.warning.assert_called_once()

    def test_parse_or_default_with_valid_date_returns_it(self):
        """P2 — _parse_or_default('2026-01-15', 'default') returns '2026-01-15'."""
        from queries.utils import _parse_or_default
        result = _parse_or_default('2026-01-15', '2000-01-01')
        assert result == '2026-01-15', \
            f"Valid date should be returned as-is, got {result!r}"
