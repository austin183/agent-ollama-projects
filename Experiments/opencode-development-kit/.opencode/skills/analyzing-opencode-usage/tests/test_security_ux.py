#!/usr/bin/env python3
"""Tests for Phase 4: Security Hardening and UX Polish.

Plan: _agent_docs/plans/2026-08-08-analytics-skill-remaining-fixes.md (Phase 4)

Phase 4.1 — SQL injection hardening in legacy estimate_cache.py:
  4.1.1  project with quote-injection payload is neutralized (inert in SQLite)
  4.1.2  since with injection payload is rejected (ValueError)
  4.1.3  until with injection payload is rejected (ValueError)
  4.1.4  normal project name + dates still produce a working WHERE clause
  % and _ in project names are treated as literals, not LIKE wildcards
  CLI surfaces invalid dates as a clean error (no traceback)

Phase 4.2 — Raw vs effective token UX in HTML report:
  4.2.1  "Raw Tokens" metric card carries an explanatory title tooltip
  4.2.2  "Effective Tokens" metric card carries an explanatory title tooltip
  4.2.3  A visible legend below the metric cards explains the distinction
  Cards still render their values normally (no regression)
"""

import re
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest

# Add script directory to path so we can import modules
sys.path.insert(0, str(Path(__file__).parent.parent / "script"))

import estimate_cache
from render_consolidated_report import build_summary_cards


# ── Phase 4.1: build_where() SQL injection hardening ────────────────────────

# 2026-07-15T00:00:00Z in epoch milliseconds — inside the test date window
TEST_CREATED_MS = int(datetime(2026, 7, 15, tzinfo=timezone.utc).timestamp() * 1000)


def _run_where(where: str, directories: list[str]):
    """Execute `SELECT id FROM session WHERE <where>` against in-memory SQLite.

    Creates a session table with one row per directory (all created
    2026-07-15 UTC) and runs the candidate WHERE clause for real, so tests
    verify actual SQL behavior rather than string shapes.

    Returns:
        Tuple (row_ids, table_exists): the ids of matched rows and whether
        the session table survived the query.
    """
    conn = sqlite3.connect(':memory:')
    try:
        conn.execute(
            "CREATE TABLE session (id TEXT, directory TEXT, time_created INTEGER)"
        )
        for i, d in enumerate(directories):
            conn.execute(
                "INSERT INTO session VALUES (?, ?, ?)", (f"s{i}", d, TEST_CREATED_MS)
            )
        rows = conn.execute(f"SELECT id FROM session WHERE {where}").fetchall()
        table_exists = conn.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name='session'"
        ).fetchone() is not None
    finally:
        conn.close()
    return [r[0] for r in rows], table_exists


class TestBuildWhereSecurity:
    """4.1: build_where() must neutralize or reject malicious filter input.

    The legacy script passes its WHERE clause to `opencode db` as a single
    SQL statement string, so every interpolated value must be validated
    (dates) or escaped (LIKE pattern) before it reaches the query.
    """

    def test_quote_injection_project_is_inert_in_sqlite(self):
        """4.1.1 — A quote-injection payload in --project must not execute extra
        SQL: the session table must survive and the payload must be treated
        as an inert literal substring (matching nothing)."""
        where = estimate_cache.build_where(project="'; DROP TABLE session; --")

        rows, table_exists = _run_where(
            where, ['/Users/austin/projects/CollageMaker']
        )

        assert table_exists, \
            "session table was dropped or altered — SQL injection succeeded"
        assert rows == [], \
            "Injection payload should be treated as a literal substring, matching nothing"

    def test_percent_and_underscore_treated_as_literals(self):
        """% and _ in a project name must be escaped so they match literally,
        not as LIKE wildcards."""
        # '/tmp/100XXYoff' matches the WILDCARD pattern 100%_off
        # (100 + any + one char + off) but not the literal string.
        # '/tmp/100%_off' contains the literal characters.
        wildcard_only = '/tmp/100XXYoff'
        literal_only = '/tmp/100%_off'

        where = estimate_cache.build_where(project='100%_off')
        rows, _ = _run_where(where, [wildcard_only, literal_only])

        assert rows == ['s1'], \
            "LIKE wildcards in project name were not escaped — " \
            f"expected only the literal directory to match, got {rows}"

    def test_backslash_project_name_still_matches(self):
        """Regression guard: a project name containing a backslash must still
        match its literal directory (backslash escaping must not break it)."""
        where = estimate_cache.build_where(project=r'a\b')
        rows, _ = _run_where(where, [r'/tmp/a\b', '/tmp/axb'])

        assert rows == ['s0'], \
            f"Backslash project name should match only its literal directory, got {rows}"

    def test_invalid_since_date_raises_value_error(self):
        """4.1.2 — A since value that is not a date must be rejected."""
        with pytest.raises(ValueError):
            estimate_cache.build_where(since='not-a-date')

    def test_injection_since_raises_value_error(self):
        """4.1.2 — A since value containing a quote-injection payload must be
        rejected before any SQL is built."""
        with pytest.raises(ValueError):
            estimate_cache.build_where(since="2026-01-01' OR '1'='1")

    def test_injection_until_raises_value_error(self):
        """4.1.3 — An until value containing a quote-injection payload must be
        rejected before any SQL is built."""
        with pytest.raises(ValueError):
            estimate_cache.build_where(until="2026-12-31' UNION SELECT * FROM session --")

    def test_impossible_calendar_date_raises_value_error(self):
        """A date that matches YYYY-MM-DD but is not a real calendar date
        (2026-13-45) must also be rejected — it would silently produce an
        empty report with no error."""
        with pytest.raises(ValueError):
            estimate_cache.build_where(since='2026-13-45')

    def test_valid_project_and_dates_accepted(self):
        """4.1.4 — Normal input must still produce a working WHERE clause."""
        where = estimate_cache.build_where(
            project='CollageMaker', since='2026-07-01', until='2026-08-08'
        )

        assert "directory LIKE '%CollageMaker%'" in where, \
            f"Project filter missing or malformed: {where}"
        assert ">= '2026-07-01'" in where, f"Since filter malformed: {where}"
        assert "<= '2026-08-08'" in where, f"Until filter malformed: {where}"

        # The clause must also actually work against a real SQLite table
        rows, table_exists = _run_where(
            where, ['/Users/austin/projects/CollageMaker', '/tmp/other-project']
        )
        assert table_exists
        assert rows == ['s0'], f"Expected only CollageMaker row to match, got {rows}"

    def test_no_filters_returns_1eq1(self):
        """Regression guard: no filters still yields the tautology 1=1."""
        assert estimate_cache.build_where() == '1=1'

    def test_cli_rejects_invalid_since_with_clean_error(self, monkeypatch, capsys):
        """The CLI must surface an invalid --since as a clean error message
        with a non-zero exit code — not a raw ValueError traceback."""
        monkeypatch.setattr(sys, 'argv', ['estimate_cache.py', '--since', 'not-a-date'])

        with pytest.raises(SystemExit) as exc_info:
            estimate_cache.main()

        assert exc_info.value.code == 2, \
            f"Expected exit code 2 for invalid input, got {exc_info.value.code}"
        err = capsys.readouterr().err
        assert 'not-a-date' in err, \
            f"Error message should name the offending value, got: {err!r}"
        assert 'Traceback' not in err, \
            f"CLI printed a raw traceback instead of a clean error: {err!r}"


# ── Phase 4.2: raw vs effective tokens tooltips + legend ────────────────────

def _summary_data() -> dict:
    """Minimal data dict exercising build_summary_cards token/cost cards."""
    return {
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
        'cost_summary': {'total_per_model': 0.04},
        'cache_cost_summary': {'total_per_model': 0.015},
        'meta': {'title': 'TestProject', 'generated': '2026-08-08'},
        'timeseries': [],
    }


def _metric_card(html: str, label: str) -> dict:
    """Extract the opening-tag attributes and displayed value of the metric
    card whose label matches exactly. Raises AssertionError if absent."""
    pattern = (
        r'<div class="metric-card(?P<attrs>[^>]*)>'
        r'<div class="metric-value">(?P<value>[^<]*)</div>'
        r'<div class="metric-label">' + re.escape(label) + r'</div></div>'
    )
    m = re.search(pattern, html)
    assert m, f"No metric card with label {label!r} in rendered HTML"
    return {'attrs': m.group('attrs'), 'value': m.group('value')}


class TestRawVsEffectiveTooltips:
    """4.2: The report must explain what Raw vs Effective tokens mean.

    Readers see both metrics side by side with no definition; the difference
    (estimated prefix-caching savings) is only meaningful once the terms are
    defined. Tooltips on the cards plus a visible legend below the grid.
    """

    def test_raw_tokens_card_has_explanatory_tooltip(self):
        """4.2.1 — The Raw Tokens card must carry a title tooltip explaining
        that it includes redundant context re-sent each turn."""
        html = build_summary_cards(_summary_data())
        card = _metric_card(html, 'Raw Tokens')

        assert 'title="' in card['attrs'], \
            "Raw Tokens card is missing a title tooltip"
        tooltip = card['attrs'].lower()
        assert any(p in tooltip for p in ('redundant', 're-sent', 'each turn')), \
            "Raw Tokens tooltip does not explain that redundant context is included"

    def test_effective_tokens_card_has_explanatory_tooltip(self):
        """4.2.2 — The Effective Tokens card must carry a title tooltip
        explaining the caching adjustment."""
        html = build_summary_cards(_summary_data())
        card = _metric_card(html, 'Effective Tokens')

        assert 'title="' in card['attrs'], \
            "Effective Tokens card is missing a title tooltip"
        tooltip = card['attrs'].lower()
        assert any(p in tooltip for p in ('prefix caching', 'prompt caching', 'uncached')), \
            "Effective Tokens tooltip does not explain the caching adjustment"

    def test_legend_explains_raw_vs_effective(self):
        """4.2.3 — A visible legend below the metric cards must define both
        terms and connect their difference to caching savings."""
        html = build_summary_cards(_summary_data())

        m = re.search(r'metrics-legend[^>]*>(.*?)</p>', html, re.DOTALL)
        assert m, "Missing legend (metrics-legend) explaining raw vs effective tokens"
        text = m.group(1).lower()

        assert 'effective tokens' in text, "Legend does not define Effective Tokens"
        assert 'raw tokens' in text, "Legend does not define Raw Tokens"
        assert 'cach' in text, \
            "Legend does not connect the difference to caching savings"

    def test_cards_still_render_values(self):
        """Regression guard: adding tooltips/legend must not alter the values
        rendered on the Raw/Effective cards."""
        html = build_summary_cards(_summary_data())

        assert _metric_card(html, 'Effective Tokens')['value'] == '50.0K'
        assert _metric_card(html, 'Raw Tokens')['value'] == '500.0K'
