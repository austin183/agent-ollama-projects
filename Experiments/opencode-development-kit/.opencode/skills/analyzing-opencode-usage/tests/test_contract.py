#!/usr/bin/env python3
"""Phase 2: Contract test — key alignment between merge.py output and consumers.

This test prevents silent failures where a key rename in merge.py
causes render_consolidated_report.py or charts.py to read wrong values.

Scenarios from plan 2026-08-08:
  2.1.1  merge.py output has total_tokens_raw in models → contract test passes
  2.1.2  merge.py output is missing total_tokens_raw in models → contract test fails
  2.1.3  merge.py output has total_effective in timeseries → contract test passes
  2.1.4  renderer expects 'total' but merge.py produces 'total_tokens_raw' → contract test fails
"""

import re
import sys
from pathlib import Path

# Add script directory to path so we can import modules
sys.path.insert(0, str(Path(__file__).parent.parent / "script"))

from aggregator.merge import merge_datasets


# ── Shared helpers ───────────────────────────────────────────────────────────

def _extract_get_keys(source: str) -> set[str]:
    """Extract all string keys from .get('key') and .get("key") calls in source.

    Used by both renderer and charts contract validation to find dictionary
    key accesses in Python source code.
    """
    pattern = r"\.get\(\s*['\"]([^'\"]+)['\"]"
    return set(re.findall(pattern, source))


# ── Expected keys by section (the contract) ──────────────────────────────────

# Top-level keys that merge_datasets() must produce
TOP_LEVEL_KEYS = frozenset({
    'meta', 'summary', 'cost_summary', 'cache_cost_summary',
    'model_pricing', 'models_with_cost', 'productivity', 'build_productivity',
    'models', 'agents', 'cross_tab', 'top_sessions', 'weekly',
    'agents_detailed', 'timeseries', 'daily_agent_stacked',
    'cache_estimate', 'phases', 'most_efficient_commits',
    'least_efficient_commits', 'warnings',
})

# Keys in the meta section
META_KEYS = frozenset({
    'title', 'since', 'until', 'generated',
    # True all-time project range (query-filter-independent), Phase 3
    'project_since', 'project_until', 'total_sessions_all_time',
})

# Keys in the summary section (from _build_summary_output)
SUMMARY_KEYS = frozenset({
    'total_sessions', 'total_tokens_raw', 'total_tokens_effective',
    'total_input_raw', 'total_input_uncached', 'total_output',
    'total_reasoning', 'cache_hit_pct', 'earliest', 'latest',
    'model_count', 'agent_count',
})

# Keys in each model row (ModelRow + enrichment from enrich_models_with_cost)
# merge.py passes models_data directly to 'models' key
MODELS_ROW_KEYS = frozenset({
    'model', 'sessions', 'total_tokens_raw', 'input_tokens_raw',
    'output_tokens_raw', 'reasoning_tokens_raw',
})

# Keys in each agent row (AgentRow)
AGENTS_ROW_KEYS = frozenset({
    'agent', 'sessions', 'total_tokens_raw', 'input_tokens_raw',
    'output_tokens_raw', 'reasoning_tokens_raw',
})

# Keys in each cross-tab row (CrossTabRow)
CROSSTAB_ROW_KEYS = frozenset({
    'model', 'agent', 'sessions', 'total_tokens_raw',
})

# Keys in each timeseries row (DailyTokenRowWithCache + computed fields)
TIMESERIES_ROW_KEYS = frozenset({
    'date', 'sessions', 'total_tokens_raw', 'input_tokens_raw',
    'input_tokens', 'output_tokens', 'reasoning_tokens',
    'build_tok', 'review_tok', 'plan_tok', 'explore_tok', 'other_tok',
    'total_effective', 'input_uncached',
    'commits', 'adds', 'dels', 'test_adds', 'test_dels',
    'tok_per_commit', 'tok_per_line', 'cache_hit_pct',
    'cost_cheap', 'cost_expensive', 'daily_cost_cheap', 'daily_cost_expensive',
    'cum_tokens', 'cum_all', 'cum_test',
    'rolling_tok_per_commit', 'test_ratio',
})

# Keys in each top session row (TopSessionRow)
TOP_SESSIONS_ROW_KEYS = frozenset({
    'session_id', 'title', 'model', 'agent', 'created',
    'tokens', 'input_tokens', 'output_tokens', 'reasoning_tokens',
})

# Keys in each agent detailed row (AgentContextRow)
AGENTS_DETAILED_ROW_KEYS = frozenset({
    'context_type', 'sessions', 'total_tokens_raw', 'input_tokens_raw',
    'output_tokens_raw', 'reasoning_tokens_raw',
})

# Keys in each weekly row (WeeklyRow)
WEEKLY_ROW_KEYS = frozenset({
    'week_start', 'week_end', 'sessions', 'total_tokens_raw',
    'build_tokens', 'review_tokens', 'planner_tokens',
})

# Keys in each commit efficiency row
COMMIT_EFFICIENCY_ROW_KEYS = frozenset({
    'sha', 'date', 'message', 'adds', 'dels', 'lines_changed',
    'tok_per_commit', 'tok_per_line', 'is_test',
})

# Keys in the cache_estimate section
CACHE_ESTIMATE_KEYS = frozenset({
    'sessions', 'total_turns', 'total_input_raw',
    'estimated_uncached_input', 'estimated_cached_input',
    'cache_hit_pct', 'total_output', 'total_reasoning',
    'effective_total', 'raw_total',
    'by_model', 'by_agent', 'by_day',
})


# ── Helper: generate a representative merge output ──────────────────────────

def _make_sample_report() -> dict:
    """Generate a representative merge output using merge_datasets().

    This produces a realistic report structure with all sections populated,
    used as the canonical fixture for contract validation.
    """
    return merge_datasets(
        daily_agent=[
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
        agents_detailed=[
            {'context_type': 'build', 'sessions': 5, 'total_tokens_raw': 12000,
             'input_tokens_raw': 8000, 'output_tokens_raw': 3000,
             'reasoning_tokens_raw': 1000},
            {'context_type': 'explore', 'sessions': 3, 'total_tokens_raw': 6000,
             'input_tokens_raw': 3000, 'output_tokens_raw': 2000,
             'reasoning_tokens_raw': 1000},
        ],
        weekly=[
            {'week_start': '2026-08-01', 'week_end': '2026-08-07', 'sessions': 8,
             'total_tokens_raw': 18000, 'build_tokens': 7000,
             'review_tokens': 5000, 'planner_tokens': 3000},
        ],
        summary_raw=[
            {'total_sessions': 8, 'total_input_raw': 11000,
             'total_output': 5000, 'total_reasoning': 2000,
             'earliest': '2026-08-01', 'latest': '2026-08-02',
             'total_tokens_raw': 18000, 'model_count': 1, 'agent_count': 2},
        ],
        models_data=[
            {'model': 'qwen/qwen3.6-27b', 'sessions': 8,
             'total_tokens_raw': 18000, 'input_tokens_raw': 11000,
             'output_tokens_raw': 5000, 'reasoning_tokens_raw': 2000},
        ],
        agents_data=[
            {'agent': 'build', 'sessions': 5, 'total_tokens_raw': 12000,
             'input_tokens_raw': 8000, 'output_tokens_raw': 3000,
             'reasoning_tokens_raw': 1000},
            {'agent': 'explore', 'sessions': 3, 'total_tokens_raw': 6000,
             'input_tokens_raw': 3000, 'output_tokens_raw': 2000,
             'reasoning_tokens_raw': 1000},
        ],
        cross_tab=[
            {'model': 'qwen/qwen3.6-27b', 'agent': 'build', 'sessions': 5,
             'total_tokens_raw': 12000},
            {'model': 'qwen/qwen3.6-27b', 'agent': 'explore', 'sessions': 3,
             'total_tokens_raw': 6000},
        ],
        top_sessions=[
            {'session_id': 'sess-1', 'title': 'Build feature', 'model': 'qwen/qwen3.6-27b',
             'agent': 'build', 'created': '2026-08-01', 'tokens': 12000,
             'input_tokens': 8000, 'output_tokens': 3000, 'reasoning_tokens': 1000},
        ],
        productivity_raw=[
            {'total_sessions': 8, 'daily_sessions': {'2026-08-01': 5}},
        ],
        build_prod_raw=[
            {'total_build_sessions': 5, 'total_tokens': 12000},
        ],
        git_commits=[
            {'sha': 'abc123', 'date': '2026-08-01', 'message': 'feat: add feature',
             'adds': 100, 'dels': 50, 'is_test': False},
        ],
        daily_git=[
            {'date': '2026-08-01', 'commits': 1, 'adds': 100, 'dels': 50,
             'test_adds': 20, 'test_dels': 10},
            {'date': '2026-08-02', 'commits': 0, 'adds': 0, 'dels': 0,
             'test_adds': 0, 'test_dels': 0},
        ],
        cache_estimate={
            'aggregate': {
                'sessions': 8, 'total_turns': 20,
                'total_input_raw': 11000, 'estimated_uncached_input': 3000,
                'estimated_cached_input': 8000, 'cache_hit_pct': 72.7,
                'total_output': 5000, 'total_reasoning': 2000,
                'effective_total': 10000, 'raw_total': 18000,
            },
            'by_model': [
                {'key': 'qwen/qwen3.6-27b', 'model': 'qwen/qwen3.6-27b',
                 'sessions': 8, 'total_input_raw': 11000,
                 'estimated_uncached_input': 3000, 'estimated_cached_input': 8000,
                 'cache_hit_pct': 72.7, 'total_output': 5000, 'total_reasoning': 2000},
            ],
            'by_agent': [
                {'key': 'build', 'agent': 'build', 'sessions': 5,
                 'total_input_raw': 8000, 'estimated_uncached_input': 2000,
                 'estimated_cached_input': 6000, 'cache_hit_pct': 75.0,
                 'total_output': 3000, 'total_reasoning': 1000},
            ],
            'by_day': [
                {'day': '2026-08-01', 'sessions': 5, 'total_input_raw': 6000,
                 'estimated_uncached_input': 2000, 'estimated_cached_input': 4000,
                 'cache_hit_pct': 66.7, 'total_output': 3000, 'total_reasoning': 1000},
            ],
        },
        project_name='TestProject',
    )


# ── 2.1: Merge output structural completeness ───────────────────────────────

class TestMergeOutputCompleteness:
    """2.1: merge_datasets() must produce all expected top-level and section keys.

    If any key is missing, consumers (renderer, charts) will silently read
    wrong values or raise KeyError.
    """

    def test_merge_output_has_all_top_level_keys(self):
        """2.1.1 — All top-level keys must be present in merge output."""
        report = _make_sample_report()
        actual_keys = set(report.keys())
        missing = TOP_LEVEL_KEYS - actual_keys
        assert not missing, f"Missing top-level keys: {sorted(missing)}"

    def test_merge_meta_has_all_required_keys(self):
        """2.1.2 — Meta section must have all required keys."""
        report = _make_sample_report()
        meta = report.get('meta', {})
        actual_keys = set(meta.keys())
        missing = META_KEYS - actual_keys
        assert not missing, f"Missing meta keys: {sorted(missing)}"

    def test_merge_summary_has_all_required_keys(self):
        """2.1.3 — Summary section must have all required keys."""
        report = _make_sample_report()
        summary = report.get('summary', {})
        actual_keys = set(summary.keys())
        missing = SUMMARY_KEYS - actual_keys
        assert not missing, f"Missing summary keys: {sorted(missing)}"

    def test_merge_models_rows_have_all_required_keys(self):
        """2.1.4 — Each model row must have all ModelRow keys."""
        report = _make_sample_report()
        models = report.get('models', [])
        assert len(models) > 0, "No model rows to validate"
        for m in models:
            actual_keys = set(m.keys())
            missing = MODELS_ROW_KEYS - actual_keys
            assert not missing, \
                f"Missing model keys in {m.get('model', 'unknown')}: {sorted(missing)}"

    def test_merge_agents_rows_have_all_required_keys(self):
        """2.1.5 — Each agent row must have all AgentRow keys."""
        report = _make_sample_report()
        agents = report.get('agents', [])
        assert len(agents) > 0, "No agent rows to validate"
        for a in agents:
            actual_keys = set(a.keys())
            missing = AGENTS_ROW_KEYS - actual_keys
            assert not missing, \
                f"Missing agent keys in {a.get('agent', 'unknown')}: {sorted(missing)}"

    def test_merge_cross_tab_rows_have_all_required_keys(self):
        """2.1.6 — Each cross-tab row must have all CrossTabRow keys."""
        report = _make_sample_report()
        cross_tab = report.get('cross_tab', [])
        assert len(cross_tab) > 0, "No cross-tab rows to validate"
        for ct in cross_tab:
            actual_keys = set(ct.keys())
            missing = CROSSTAB_ROW_KEYS - actual_keys
            assert not missing, \
                f"Missing cross-tab keys: {sorted(missing)}"

    def test_merge_timeseries_rows_have_all_required_keys(self):
        """2.1.7 — Each timeseries row must have all required keys."""
        report = _make_sample_report()
        timeseries = report.get('timeseries', [])
        assert len(timeseries) > 0, "No timeseries rows to validate"
        for ts in timeseries:
            actual_keys = set(ts.keys())
            missing = TIMESERIES_ROW_KEYS - actual_keys
            assert not missing, \
                f"Missing timeseries keys in {ts.get('date', 'unknown')}: {sorted(missing)}"

    def test_merge_top_sessions_rows_have_all_required_keys(self):
        """2.1.8 — Each top session row must have all required keys."""
        report = _make_sample_report()
        top_sessions = report.get('top_sessions', [])
        assert len(top_sessions) > 0, "No top session rows to validate"
        for ts in top_sessions:
            actual_keys = set(ts.keys())
            missing = TOP_SESSIONS_ROW_KEYS - actual_keys
            assert not missing, \
                f"Missing top session keys: {sorted(missing)}"

    def test_merge_agents_detailed_rows_have_all_required_keys(self):
        """2.1.9 — Each agent detailed row must have all required keys."""
        report = _make_sample_report()
        detailed = report.get('agents_detailed', [])
        assert len(detailed) > 0, "No agent detailed rows to validate"
        for a in detailed:
            actual_keys = set(a.keys())
            missing = AGENTS_DETAILED_ROW_KEYS - actual_keys
            assert not missing, \
                f"Missing agent detailed keys: {sorted(missing)}"

    def test_merge_weekly_rows_have_all_required_keys(self):
        """2.1.10 — Each weekly row must have all required keys."""
        report = _make_sample_report()
        weekly = report.get('weekly', [])
        assert len(weekly) > 0, "No weekly rows to validate"
        for w in weekly:
            actual_keys = set(w.keys())
            missing = WEEKLY_ROW_KEYS - actual_keys
            assert not missing, \
                f"Missing weekly keys: {sorted(missing)}"

    def test_merge_commit_efficiency_rows_have_all_required_keys(self):
        """2.1.11 — Each commit efficiency row must have all required keys."""
        report = _make_sample_report()
        commits = report.get('most_efficient_commits', [])
        assert len(commits) > 0, "No commit efficiency rows to validate"
        for c in commits:
            actual_keys = set(c.keys())
            missing = COMMIT_EFFICIENCY_ROW_KEYS - actual_keys
            assert not missing, \
                f"Missing commit efficiency keys: {sorted(missing)}"

    def test_merge_cache_estimate_has_all_required_keys(self):
        """2.1.12 — Cache estimate section must have all required keys."""
        report = _make_sample_report()
        cache = report.get('cache_estimate', {})
        actual_keys = set(cache.keys())
        missing = CACHE_ESTIMATE_KEYS - actual_keys
        assert not missing, f"Missing cache estimate keys: {sorted(missing)}"


# ── 2.2: Renderer key consumption validation ────────────────────────────────

class TestRendererKeyConsumption:
    """2.2: render_consolidated_report.py must only read keys that merge.py produces.

    This test statically analyzes the renderer source code for .get('key') calls
    and verifies each key exists in the corresponding merge output section.
    """

    def test_renderer_models_section_only_reads_model_row_keys(self):
        """2.2.1 — build_models_section must only read keys present in ModelRow."""
        source = (Path(__file__).parent.parent / "script" / "render_consolidated_report.py").read_text()

        # Extract the build_models_section function
        func_match = re.search(
            r'def build_models_section\(.*?\n(?=\ndef |\Z)',
            source, re.DOTALL
        )
        assert func_match, "Could not find build_models_section function"
        func_source = func_match.group(0)

        get_keys = _extract_get_keys(func_source)
        # Keys the function reads from model row dicts (d.get(...))
        # Filter to only keys that look like they come from model data
        model_keys = {
            'model', 'sessions', 'total_tokens_raw', 'input_tokens_raw',
            'output_tokens_raw', 'reasoning_tokens_raw',
        }
        # Also allow cache lookup keys
        cache_keys = {'key', 'model', 'estimated_uncached_input', 'total_output', 'total_reasoning'}
        allowed = model_keys | cache_keys | {'by_model', 'by_agent', 'by_day'}

        disallowed = get_keys - allowed
        assert not disallowed, \
            f"build_models_section reads keys not in ModelRow: {sorted(disallowed)}"

    def test_renderer_agents_section_only_reads_agent_row_keys(self):
        """2.2.2 — build_agents_section must only read keys present in AgentRow."""
        source = (Path(__file__).parent.parent / "script" / "render_consolidated_report.py").read_text()

        func_match = re.search(
            r'def build_agents_section\(.*?\n(?=\ndef |\Z)',
            source, re.DOTALL
        )
        assert func_match, "Could not find build_agents_section function"
        func_source = func_match.group(0)

        get_keys = _extract_get_keys(func_source)
        agent_keys = {
            'agent', 'sessions', 'total_tokens_raw', 'input_tokens_raw',
            'output_tokens_raw', 'reasoning_tokens_raw',
        }
        cache_keys = {'key', 'agent', 'estimated_uncached_input', 'total_output', 'total_reasoning'}
        allowed = agent_keys | cache_keys | {'by_model', 'by_agent', 'by_day'}

        disallowed = get_keys - allowed
        assert not disallowed, \
            f"build_agents_section reads keys not in AgentRow: {sorted(disallowed)}"

    def test_renderer_cross_tab_only_reads_cross_tab_keys(self):
        """2.2.3 — build_cross_tab must only read keys present in CrossTabRow."""
        source = (Path(__file__).parent.parent / "script" / "render_consolidated_report.py").read_text()

        func_match = re.search(
            r'def build_cross_tab\(.*?\n(?=\ndef |\Z)',
            source, re.DOTALL
        )
        assert func_match, "Could not find build_cross_tab function"
        func_source = func_match.group(0)

        get_keys = _extract_get_keys(func_source)
        allowed = CROSSTAB_ROW_KEYS

        disallowed = get_keys - allowed
        assert not disallowed, \
            f"build_cross_tab reads keys not in CrossTabRow: {sorted(disallowed)}"

    def test_renderer_summary_cards_only_reads_summary_keys(self):
        """2.2.4 — build_summary_cards must only read keys present in merge output sections."""
        source = (Path(__file__).parent.parent / "script" / "render_consolidated_report.py").read_text()

        func_match = re.search(
            r'def build_summary_cards\(.*?\n(?=\ndef |\Z)',
            source, re.DOTALL
        )
        assert func_match, "Could not find build_summary_cards function"
        func_source = func_match.group(0)

        get_keys = _extract_get_keys(func_source)
        # Summary cards reads from summary, cost_summary, cache_cost_summary, timeseries, meta
        allowed = SUMMARY_KEYS | {
            'total_cheap', 'total_expensive', 'total_per_model',
            'uncached_input', 'cached_input',
            'commits', 'adds', 'earliest', 'latest', 'model_count', 'agent_count',
            'cache_hit_pct', 'generated', 'summary', 'cost_summary',
            'cache_cost_summary', 'timeseries', 'meta',
            # Project range annotation in subtitle (Phase 3)
            'project_since', 'since', 'total_sessions_all_time',
        }

        disallowed = get_keys - allowed
        assert not disallowed, \
            f"build_summary_cards reads keys not in expected sections: {sorted(disallowed)}"

    def test_renderer_no_short_key_aliases(self):
        """2.2.5 — Renderer must NOT use short key aliases like 'total', 'input', 'output'.

        This is the critical regression test: if someone renames a key in merge.py
        but forgets to update the renderer, this test catches it.
        """
        source = (Path(__file__).parent.parent / "script" / "render_consolidated_report.py").read_text()

        # Keys that were the OLD broken aliases (should NOT appear in .get() calls
        # for model/agent/cross-tab data)
        broken_aliases = {'total', 'input', 'output', 'reasoning'}

        # Check build_models_section
        func_match = re.search(
            r'def build_models_section\(.*?\n(?=\ndef |\Z)',
            source, re.DOTALL
        )
        if func_match:
            get_keys = _extract_get_keys(func_match.group(0))
            bad = get_keys & broken_aliases
            assert not bad, \
                f"build_models_section uses broken key aliases: {sorted(bad)}"

        # Check build_agents_section
        func_match = re.search(
            r'def build_agents_section\(.*?\n(?=\ndef |\Z)',
            source, re.DOTALL
        )
        if func_match:
            get_keys = _extract_get_keys(func_match.group(0))
            bad = get_keys & broken_aliases
            assert not bad, \
                f"build_agents_section uses broken key aliases: {sorted(bad)}"

        # Check build_cross_tab
        func_match = re.search(
            r'def build_cross_tab\(.*?\n(?=\ndef |\Z)',
            source, re.DOTALL
        )
        if func_match:
            get_keys = _extract_get_keys(func_match.group(0))
            bad = get_keys & broken_aliases
            assert not bad, \
                f"build_cross_tab uses broken key aliases: {sorted(bad)}"


# ── 2.3: Charts key consumption validation ──────────────────────────────────

class TestChartsKeyConsumption:
    """2.3: charts.py must only read keys that merge.py produces.

    This test validates that chart functions read keys from the correct
    data structures (tuple indices for tuple rows, dict keys for dict rows).
    """

    def test_daily_agent_stacked_reads_timeseries_keys(self):
        """2.3.1 — render_daily_agent_stacked must read keys present in timeseries rows."""
        source = (Path(__file__).parent.parent / "script" / "charts.py").read_text()

        func_match = re.search(
            r'def render_daily_agent_stacked\(.*?\n(?=\ndef |\Z)',
            source, re.DOTALL
        )
        assert func_match, "Could not find render_daily_agent_stacked function"
        func_source = func_match.group(0)

        get_keys = _extract_get_keys(func_source)
        # This function reads from dict rows (timeseries/daily_agent_stacked)
        allowed = TIMESERIES_ROW_KEYS | {'date'}

        disallowed = get_keys - allowed
        assert not disallowed, \
            f"render_daily_agent_stacked reads keys not in timeseries: {sorted(disallowed)}"

    def test_cumulative_efficiency_reads_timeseries_keys(self):
        """2.3.2 — render_cumulative_efficiency must read keys present in timeseries rows."""
        source = (Path(__file__).parent.parent / "script" / "charts.py").read_text()

        func_match = re.search(
            r'def render_cumulative_efficiency\(.*?\n(?=\ndef |\Z)',
            source, re.DOTALL
        )
        assert func_match, "Could not find render_cumulative_efficiency function"
        func_source = func_match.group(0)

        get_keys = _extract_get_keys(func_source)
        allowed = TIMESERIES_ROW_KEYS | {'date', 'cum_tokens', 'cum_all', 'cum_test'}

        disallowed = get_keys - allowed
        assert not disallowed, \
            f"render_cumulative_efficiency reads keys not in timeseries: {sorted(disallowed)}"

    def test_rolling_tok_per_commit_reads_timeseries_keys(self):
        """2.3.3 — render_rolling_tok_per_commit must read keys present in timeseries rows."""
        source = (Path(__file__).parent.parent / "script" / "charts.py").read_text()

        func_match = re.search(
            r'def render_rolling_tok_per_commit\(.*?\n(?=\ndef |\Z)',
            source, re.DOTALL
        )
        assert func_match, "Could not find render_rolling_tok_per_commit function"
        func_source = func_match.group(0)

        get_keys = _extract_get_keys(func_source)
        allowed = TIMESERIES_ROW_KEYS | {'date', 'rolling_tok_per_commit', 'commits'}

        disallowed = get_keys - allowed
        assert not disallowed, \
            f"render_rolling_tok_per_commit reads keys not in timeseries: {sorted(disallowed)}"

    def test_cumulative_cost_reads_timeseries_keys(self):
        """2.3.4 — render_cumulative_cost must read keys present in timeseries rows."""
        source = (Path(__file__).parent.parent / "script" / "charts.py").read_text()

        func_match = re.search(
            r'def render_cumulative_cost\(.*?\n(?=\ndef |\Z)',
            source, re.DOTALL
        )
        assert func_match, "Could not find render_cumulative_cost function"
        func_source = func_match.group(0)

        get_keys = _extract_get_keys(func_source)
        allowed = TIMESERIES_ROW_KEYS | {
            'date', 'cost_cheap', 'cost_expensive',
            'daily_cost_cheap', 'daily_cost_expensive',
        }

        disallowed = get_keys - allowed
        assert not disallowed, \
            f"render_cumulative_cost reads keys not in timeseries: {sorted(disallowed)}"

    def test_context_efficiency_table_reads_agent_keys(self):
        """2.3.5 — render_context_efficiency_table must read keys present in AgentContextRow."""
        source = (Path(__file__).parent.parent / "script" / "charts.py").read_text()

        func_match = re.search(
            r'def render_context_efficiency_table\(.*?\n(?=\ndef |\Z)',
            source, re.DOTALL
        )
        assert func_match, "Could not find render_context_efficiency_table function"
        func_source = func_match.group(0)

        get_keys = _extract_get_keys(func_source)
        allowed = AGENTS_DETAILED_ROW_KEYS | {'agent', 'context_type'}

        disallowed = get_keys - allowed
        assert not disallowed, \
            f"render_context_efficiency_table reads keys not in AgentContextRow: {sorted(disallowed)}"

# ── 2.4: Negative tests — verify contract catches mismatches ────────────────

class TestContractDetectsMismatches:
    """2.4: Contract test must fail when keys are intentionally broken.

    These tests verify that the contract test itself is effective by
    intentionally introducing mismatches and confirming they are caught.
    """

    def test_contract_catches_missing_model_key(self):
        """2.4.1 — If a model row is missing total_tokens_raw, contract must detect it."""
        # Simulate a model row missing total_tokens_raw
        broken_models = [
            {'model': 'qwen/qwen3.6-27b', 'sessions': 8,
             'input_tokens_raw': 11000, 'output_tokens_raw': 5000,
             'reasoning_tokens_raw': 2000},  # missing total_tokens_raw
        ]
        for m in broken_models:
            actual_keys = set(m.keys())
            missing = MODELS_ROW_KEYS - actual_keys
            # This assertion should FAIL if the contract is working
            assert missing, "Contract should have detected missing total_tokens_raw"

    def test_contract_catches_missing_timeseries_key(self):
        """2.4.2 — If a timeseries row is missing total_effective, contract must detect it."""
        broken_ts = {
            'date': '2026-08-01', 'sessions': 5, 'total_tokens_raw': 10000,
            'input_tokens_raw': 6000, 'output_tokens_raw': 3000,
            # missing total_effective
        }
        actual_keys = set(broken_ts.keys())
        missing = TIMESERIES_ROW_KEYS - actual_keys
        assert 'total_effective' in missing, \
            "Contract should have detected missing total_effective"
