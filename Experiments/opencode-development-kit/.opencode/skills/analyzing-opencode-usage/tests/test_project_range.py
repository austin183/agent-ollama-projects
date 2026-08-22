#!/usr/bin/env python3
"""Tests for Phase 3 (2026-08-08 plan): Date Range and Legacy Sessions.

P3.1: meta.project_since/project_until reflect true project history
  3.1.1  Sessions 2026-05-10..2026-08-04, report --since 2026-07-01
         → meta.project_since = 2026-05-10 (true start, not filter start)
  3.1.2  Same → meta.project_until = 2026-08-04 (true end)
  3.1.3  Report with no date filter → meta.project_since = 2026-05-10
  3.1.4  Report --until 2026-07-15 → meta.project_until = 2026-08-04
         (true end, not filter end)

P3.2: Legacy sessions are counted but flagged
  3.2.1  Legacy (NULL model) sessions included in session counts
  3.2.2  Warnings array notes legacy session count
  3.2.3  Legacy sessions counted but not inflating token totals

Design notes:
  - The project range query lives in queries/summary.py (DB layer) and takes
    NO date parameters — by construction it ignores the query filter.
  - merge_datasets() stays a pure in-memory merge: the fetched project range
    is injected as a parameter (same pattern as all other datasets).
"""

import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

import pytest

# Add script directory to path so we can import modules
sys.path.insert(0, str(Path(__file__).parent.parent / "script"))

from aggregator.merge import merge_datasets
from queries import summary
from render_consolidated_report import build_summary_cards


# ── DB fixture: deterministic session rows ───────────────────────────────────

def _ts(date_tuple: tuple) -> int:
    """Millisecond timestamp for a UTC date.

    Matches strftime('%Y-%m-%d', time_created / 1000, 'unixepoch'),
    which is UTC-based.
    """
    return int(datetime(*date_tuple, tzinfo=timezone.utc).timestamp() * 1000)


# (id, directory, date, model, agent)
# CollageMaker: 3 legacy (NULL model) + 2 normal, spanning 2026-05-10..2026-08-04
# other-project: 2 normal on 2026-07-01
SEED_ROWS = [
    ("s1", "/path/to/CollageMaker", (2026, 5, 10), None, None),
    ("s2", "/path/to/CollageMaker", (2026, 5, 10), None, None),
    ("s3", "/path/to/CollageMaker", (2026, 5, 11), None, None),
    ("s4", "/path/to/CollageMaker", (2026, 6, 15), '{"id": "qwen/qwen3.6-27b"}', "build"),
    ("s5", "/path/to/CollageMaker", (2026, 8, 4), '{"id": "gpt-4o"}', "explore"),
    ("s6", "/path/to/other-project", (2026, 7, 1), '{"id": "qwen/qwen3.6-27b"}', "build"),
    ("s7", "/path/to/other-project", (2026, 7, 1), '{"id": "qwen/qwen3.6-27b"}', "explore"),
]


@pytest.fixture
def db_path(tmp_path):
    """Temp SQLite DB with the opencode session schema and deterministic rows."""
    path = str(tmp_path / "opencode_test.db")
    conn = sqlite3.connect(path)
    conn.execute("""
        CREATE TABLE session (
            id TEXT PRIMARY KEY,
            directory TEXT,
            time_created INTEGER,
            model TEXT,
            agent TEXT,
            title TEXT
        )
    """)
    for sid, directory, date_tuple, model, agent in SEED_ROWS:
        conn.execute(
            "INSERT INTO session (id, directory, time_created, model, agent, title) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (sid, directory, _ts(date_tuple), model, agent, f"session {sid}"),
        )
    conn.commit()
    conn.close()
    return path


@pytest.fixture
def empty_db_path(tmp_path):
    """Temp SQLite DB with the session schema but no rows."""
    path = str(tmp_path / "opencode_empty.db")
    conn = sqlite3.connect(path)
    conn.execute("""
        CREATE TABLE session (
            id TEXT PRIMARY KEY,
            directory TEXT,
            time_created INTEGER,
            model TEXT,
            agent TEXT,
            title TEXT
        )
    """)
    conn.commit()
    conn.close()
    return path


# ── P3.1a: fetch_project_range query (DB layer) ─────────────────────────────

class TestFetchProjectRange:
    """queries.summary.fetch_project_range must return the true project
    date range and all-time session stats, ignoring any date filter."""

    def test_true_range_for_project(self, db_path):
        """3.1.1/3.1.2 — Range spans the project's full history."""
        r = summary.fetch_project_range(db_path=db_path, project="/path/to/CollageMaker")
        assert r['project_since'] == '2026-05-10', \
            f"project_since should be 2026-05-10 (true start), got {r['project_since']!r}"
        assert r['project_until'] == '2026-08-04', \
            f"project_until should be 2026-08-04 (true end), got {r['project_until']!r}"

    def test_all_time_session_count_for_project(self, db_path):
        """3.1.3 — Count covers all sessions for the project, unfiltered."""
        r = summary.fetch_project_range(db_path=db_path, project="/path/to/CollageMaker")
        assert r['total_sessions_all_time'] == 5, \
            f"Expected 5 all-time sessions for CollageMaker, got {r['total_sessions_all_time']}"

    def test_respects_project_filter(self, db_path):
        """Filtering by another project must exclude other projects' sessions."""
        r = summary.fetch_project_range(db_path=db_path, project="/path/to/other-project")
        assert r['project_since'] == '2026-07-01'
        assert r['project_until'] == '2026-07-01'
        assert r['total_sessions_all_time'] == 2
        assert r['legacy_sessions'] == 0

    def test_no_project_filter_covers_all_projects(self, db_path):
        """With no project filter, the range covers the entire database."""
        r = summary.fetch_project_range(db_path=db_path)
        assert r['project_since'] == '2026-05-10'
        assert r['project_until'] == '2026-08-04'
        assert r['total_sessions_all_time'] == 7
        assert r['legacy_sessions'] == 3

    def test_counts_legacy_null_model_sessions(self, db_path):
        """3.2.1 — Legacy (NULL model) sessions are counted, including
        in the all-time session total."""
        r = summary.fetch_project_range(db_path=db_path, project="/path/to/CollageMaker")
        assert r['legacy_sessions'] == 3, \
            f"Expected 3 legacy sessions, got {r['legacy_sessions']}"
        # 3 legacy + 2 normal = 5 total: legacy sessions are included
        assert r['total_sessions_all_time'] == 5

    def test_empty_database_returns_empty_defaults(self, empty_db_path):
        """A project with no sessions yields empty dates and zero counts."""
        r = summary.fetch_project_range(db_path=empty_db_path)
        assert r['project_since'] == ''
        assert r['project_until'] == ''
        assert r['total_sessions_all_time'] == 0
        assert r['legacy_sessions'] == 0

    def test_signature_has_no_date_parameters(self):
        """The query ignores date filters by construction: it accepts no
        since/until/days arguments."""
        import inspect
        params = inspect.signature(summary.fetch_project_range).parameters
        for name in ('since', 'until', 'days'):
            assert name not in params, \
                f"fetch_project_range must not accept a {name!r} parameter"


# ── P3.1b: merge_datasets meta (aggregator layer) ───────────────────────────

def _make_minimal_datasets(overrides: dict | None = None) -> dict:
    """Return minimal datasets that produce a valid merge output.

    The summary_raw range (2026-08-01..2026-08-02) simulates a report
    generated with a --since 2026-08-01 filter.
    """
    defaults: dict = {
        'daily_agent': [
            {'day': '2026-08-01', 'sessions': 5, 'total_tokens_raw': 10000,
             'input_tokens_raw': 6000, 'output_tokens_raw': 3000,
             'reasoning_tokens_raw': 1000, 'build_tok_raw': 4000,
             'review_tok_raw': 3000, 'plan_tok_raw': 2000,
             'explore_tok_raw': 500, 'other_tok_raw': 500},
        ],
        'agents_detailed': [],
        'weekly': [],
        'summary_raw': [{'total_sessions': 5, 'total_input_raw': 6000,
                         'total_output': 3000, 'total_reasoning': 1000,
                         'earliest': '2026-08-01', 'latest': '2026-08-02',
                         'total_tokens_raw': 10000}],
        'models_data': [
            {'model': 'qwen/qwen3.6-27b', 'input_tokens_raw': 6000,
             'output_tokens_raw': 3000, 'reasoning_tokens_raw': 1000,
             'sessions': 5},
        ],
        'agents_data': [],
        'cross_tab': [],
        'top_sessions': [],
        'productivity_raw': [{'total_sessions': 5, 'daily_sessions': {}}],
        'build_prod_raw': [{'total_build_sessions': 3, 'total_tokens': 4000}],
        'git_commits': [],
        'daily_git': [
            {'date': '2026-08-01', 'commits': 2, 'adds': 100, 'dels': 50,
             'test_adds': 20, 'test_dels': 10},
        ],
        'cache_estimate': {'aggregate': {}, 'by_model': [], 'by_agent': [], 'by_day': []},
    }
    if overrides:
        for key, value in overrides.items():
            defaults[key] = value
    return defaults


PROJECT_RANGE = {
    'project_since': '2026-05-10',
    'project_until': '2026-08-04',
    'total_sessions_all_time': 1464,
    'legacy_sessions': 19,
}


class TestMergeProjectRangeMeta:
    """merge_datasets must inject the true project range into meta while
    keeping since/until as the query-filtered range."""

    def test_meta_includes_project_range(self):
        """3.1.1/3.1.2 — meta.project_since/project_until come from the
        fetched project range, not the query filter."""
        output = merge_datasets(**_make_minimal_datasets(), project_range=PROJECT_RANGE)
        meta = output['meta']
        assert meta['project_since'] == '2026-05-10', \
            f"meta.project_since should be 2026-05-10, got {meta.get('project_since')!r}"
        assert meta['project_until'] == '2026-08-04', \
            f"meta.project_until should be 2026-08-04, got {meta.get('project_until')!r}"
        assert meta['total_sessions_all_time'] == 1464

    def test_meta_since_until_remain_query_range(self):
        """3.1.4 — since/until keep the query-filtered range so data
        consumers know the actual window the report data covers."""
        output = merge_datasets(**_make_minimal_datasets(), project_range=PROJECT_RANGE)
        meta = output['meta']
        assert meta['since'] == '2026-08-01', \
            f"meta.since must stay the query range, got {meta['since']!r}"
        assert meta['until'] == '2026-08-02', \
            f"meta.until must stay the query range, got {meta['until']!r}"

    def test_meta_project_range_defaults_when_not_provided(self):
        """Backward compatibility: reports generated without a project range
        get empty defaults, never missing keys."""
        output = merge_datasets(**_make_minimal_datasets())
        meta = output['meta']
        assert meta['project_since'] == ''
        assert meta['project_until'] == ''
        assert meta['total_sessions_all_time'] == 0


# ── P3.2: Legacy session warning ────────────────────────────────────────────

class TestLegacySessionWarning:
    """merge_datasets must flag legacy (NULL model/agent) sessions in the
    warnings array so report readers know those sessions have no
    model/agent attribution."""

    def test_warning_includes_legacy_count(self):
        """3.2.2 — A warning mentions the legacy session count."""
        output = merge_datasets(**_make_minimal_datasets(), project_range=PROJECT_RANGE)
        legacy_warnings = [w for w in output['warnings'] if 'legacy' in w.lower()]
        assert len(legacy_warnings) == 1, \
            f"Expected exactly 1 legacy warning, got: {output['warnings']}"
        assert '19' in legacy_warnings[0], \
            f"Legacy warning must include the count (19): {legacy_warnings[0]!r}"

    def test_warning_uses_real_count_values(self):
        """The documented CollageMaker-style case: 307 legacy sessions."""
        range_307 = dict(PROJECT_RANGE, legacy_sessions=307)
        output = merge_datasets(**_make_minimal_datasets(), project_range=range_307)
        legacy_warnings = [w for w in output['warnings'] if 'legacy' in w.lower()]
        assert len(legacy_warnings) == 1
        assert '307' in legacy_warnings[0]

    def test_no_warning_when_no_legacy_sessions(self):
        """A project with zero legacy sessions gets no legacy warning."""
        range_none = dict(PROJECT_RANGE, legacy_sessions=0)
        output = merge_datasets(**_make_minimal_datasets(), project_range=range_none)
        legacy_warnings = [w for w in output['warnings'] if 'legacy' in w.lower()]
        assert legacy_warnings == [], \
            f"No legacy warning expected, got: {legacy_warnings}"

    def test_no_warning_when_project_range_missing(self):
        """Backward compatibility: no project_range → no legacy warning."""
        output = merge_datasets(**_make_minimal_datasets())
        legacy_warnings = [w for w in output['warnings'] if 'legacy' in w.lower()]
        assert legacy_warnings == []


# ── P3.3: Renderer subtitle shows project start ─────────────────────────────

def _make_minimal_render_data(overrides: dict | None = None) -> dict:
    """Return minimal data for build_summary_cards.

    summary.earliest/latest simulate a report generated with --since 2026-07-01.
    """
    defaults: dict = {
        'summary': {
            'total_tokens_effective': 50000,
            'total_tokens_raw': 500000,
            'total_sessions': 10,
            'earliest': '2026-07-01',
            'latest': '2026-08-04',
            'model_count': 3,
            'agent_count': 5,
            'cache_hit_pct': 0,
        },
        'cost_summary': {'total_per_model': 100.0},
        'cache_cost_summary': {'total_per_model': 90.0},
        'meta': {
            'title': 'TestProject — LLM Usage & Value Report',
            'generated': '2026-08-08',
        },
        'timeseries': [],
    }
    if overrides:
        for key, value in overrides.items():
            if key in defaults and isinstance(defaults[key], dict) and isinstance(value, dict):
                defaults[key] = {**defaults[key], **value}
            else:
                defaults[key] = value
    return defaults


class TestSubtitleProjectRange:
    """build_summary_cards must annotate the Period subtitle with the true
    project start when the query range is narrower than the project's
    full history."""

    def test_subtitle_shows_project_start_when_range_differs(self):
        """3.1.1 — Filtered report (since 2026-07-01) shows project start
        2026-05-10 in the subtitle."""
        data = _make_minimal_render_data(overrides={
            'meta': {
                'since': '2026-07-01',
                'until': '2026-08-04',
                'project_since': '2026-05-10',
                'project_until': '2026-08-04',
                'total_sessions_all_time': 1464,
            },
        })
        html = build_summary_cards(data)
        assert 'project started 2026-05-10' in html, \
            "Subtitle must mention the true project start date"
        assert '1464 all-time sessions' in html, \
            "Subtitle must mention the all-time session count"

    def test_subtitle_keeps_period_dates(self):
        """The subtitle still shows the query-filtered period dates."""
        data = _make_minimal_render_data(overrides={
            'meta': {
                'since': '2026-07-01',
                'until': '2026-08-04',
                'project_since': '2026-05-10',
                'project_until': '2026-08-04',
                'total_sessions_all_time': 1464,
            },
        })
        html = build_summary_cards(data)
        assert 'Period: 2026-07-01 to 2026-08-04' in html

    def test_subtitle_unchanged_when_project_range_matches(self):
        """Unfiltered report (project start == query start): no annotation."""
        data = _make_minimal_render_data(overrides={
            'meta': {
                'since': '2026-05-10',
                'until': '2026-08-04',
                'project_since': '2026-05-10',
                'project_until': '2026-08-04',
                'total_sessions_all_time': 1464,
            },
        })
        html = build_summary_cards(data)
        assert 'project started' not in html

    def test_subtitle_unchanged_for_reports_without_project_range(self):
        """Backward compatibility: JSON reports generated before this change
        (no project_since in meta) render as before."""
        data = _make_minimal_render_data()
        html = build_summary_cards(data)
        assert 'project started' not in html
        assert 'Period: 2026-07-01 to 2026-08-04' in html
