#!/usr/bin/env python3
"""Tests for Phase 3: Maintainability & Documentation.

B7:  Duplicated CTE in cache_estimate.py — extract shared _cache_cte() function
B11: Missing references/activity-template.md file
B12: SKILL.md cost example has wrong numbers
"""

import sys
from pathlib import Path

# Add script directory to path so we can import modules
sys.path.insert(0, str(Path(__file__).parent.parent / "script"))

import model_pricing

# Resolve project paths
SKILL_ROOT = Path(__file__).parent.parent
SCRIPT_DIR = SKILL_ROOT / "script"
REFERENCES_DIR = SKILL_ROOT / "references"


class TestB7_CTEDeduplication:
    """B7: cache_estimate.py should have a single shared CTE builder function.

    Before: 5 identical 4-level CTE chains (~200 lines of duplication).
    After:  1 _cache_cte() function + 5 thin SELECT clauses.
    """

    def test_cache_cte_function_exists(self):
        """_cache_cte function must exist in cache_estimate module."""
        from queries import cache_estimate
        assert hasattr(cache_estimate, '_cache_cte'), \
            "cache_estimate module missing _cache_cte() function"
        assert callable(cache_estimate._cache_cte), \
            "_cache_cte must be callable"

    def test_cache_cte_is_pure_function(self):
        """_cache_cte must be a pure function — same input yields same output."""
        from queries import cache_estimate
        where1 = "1=1"
        result_a = cache_estimate._cache_cte(where1)
        result_b = cache_estimate._cache_cte(where1)
        assert result_a == result_b, "_cache_cte is not deterministic"

    def test_cache_cte_contains_all_four_cte_levels(self):
        """_cache_cte output must contain all 4 CTE levels: collages, msg_tokens,
        with_prev, per_turn."""
        from queries import cache_estimate
        cte = cache_estimate._cache_cte("1=1")

        assert "collages AS" in cte, "Missing collages CTE"
        assert "msg_tokens AS" in cte, "Missing msg_tokens CTE"
        assert "with_prev AS" in cte, "Missing with_prev CTE"
        assert "per_turn AS" in cte, "Missing per_turn CTE"

    def test_cache_cte_includes_cache_logic(self):
        """_cache_cte must include the cache estimation CASE logic."""
        from queries import cache_estimate
        cte = cache_estimate._cache_cte("1=1")

        assert "new_uncached_input" in cte, "Missing new_uncached_input calculation"
        assert "cached_input" in cte, "Missing cached_input calculation"
        assert "LAG" in cte, "Missing LAG window function"

    def test_cache_cte_includes_where_clause(self):
        """_cache_cte must incorporate the where clause parameter."""
        from queries import cache_estimate
        cte = cache_estimate._cache_cte("directory LIKE '%test%'")
        assert "directory LIKE '%test%'" in cte, \
            "where clause not passed through to CTE"

    def test_no_duplicate_cte_blocks_in_source(self):
        """The source file should contain 'WITH collages AS' exactly once
        (inside _cache_cte), not duplicated across 5 fetch functions."""
        source_path = SCRIPT_DIR / "queries" / "cache_estimate.py"
        source = source_path.read_text()

        # Count occurrences of the CTE anchor — should be exactly 1 (in _cache_cte)
        count = source.count("WITH collages AS")
        assert count == 1, \
            f"Expected 1 occurrence of 'WITH collages AS', found {count} " \
            f"(CTE is still duplicated across fetch functions)"

    def test_line_count_reduced_by_at_least_100(self):
        """cache_estimate.py should be at least 100 lines shorter after deduplication.

        Original: ~513 lines. After dedup: should be <= ~413 lines.
        """
        source_path = SCRIPT_DIR / "queries" / "cache_estimate.py"
        source = source_path.read_text()
        line_count = len(source.splitlines())

        assert line_count <= 413, \
            f"Expected <= 413 lines after dedup, got {line_count} " \
            f"(need to reduce by at least 100 lines from original ~513)"

    def test_all_fetch_functions_still_exist(self):
        """All 5 fetch_* functions must still exist after refactoring."""
        from queries import cache_estimate
        expected = ['fetch_aggregate', 'fetch_by_model', 'fetch_by_agent',
                     'fetch_by_day', 'fetch_sessions']
        for name in expected:
            assert hasattr(cache_estimate, name), \
                f"cache_estimate missing {name}() after CTE extraction"
            assert callable(getattr(cache_estimate, name)), \
                f"{name} must be callable"


class TestB11_ActivityTemplate:
    """B11: references/activity-template.md must exist and contain required structure."""

    def test_activity_template_file_exists(self):
        """The file referenced by SKILL.md line 417 must exist."""
        template_path = REFERENCES_DIR / "activity-template.md"
        assert template_path.exists(), \
            f"activity-template.md not found at {template_path}. " \
            "Referenced by SKILL.md but does not exist."

    def test_activity_template_is_non_empty(self):
        """The template file must have content (not an empty file)."""
        template_path = REFERENCES_DIR / "activity-template.md"
        content = template_path.read_text()
        assert len(content.strip()) > 50, \
            "activity-template.md is too short to be a useful template"

    def test_activity_template_has_overview_section(self):
        """Template must include an overview section."""
        template_path = REFERENCES_DIR / "activity-template.md"
        content = template_path.read_text()
        assert "Overview" in content or "overview" in content, \
            "activity-template.md missing overview section"

    def test_activity_template_has_daily_breakdown(self):
        """Template must include a daily breakdown structure."""
        template_path = REFERENCES_DIR / "activity-template.md"
        content = template_path.read_text()
        assert "Daily" in content or "daily" in content or "Date" in content, \
            "activity-template.md missing daily breakdown structure"

    def test_activity_template_has_token_fields(self):
        """Template must include token breakdown placeholders."""
        template_path = REFERENCES_DIR / "activity-template.md"
        content = template_path.read_text()
        assert "token" in content.lower(), \
            "activity-template.md missing token breakdown fields"

    def test_activity_template_has_session_fields(self):
        """Template must include session count placeholders."""
        template_path = REFERENCES_DIR / "activity-template.md"
        content = template_path.read_text()
        assert "session" in content.lower(), \
            "activity-template.md missing session count fields"

    def test_activity_template_has_commit_fields(self):
        """Template must include commit SHA placeholders."""
        template_path = REFERENCES_DIR / "activity-template.md"
        content = template_path.read_text()
        assert "commit" in content.lower() or "sha" in content.lower(), \
            "activity-template.md missing commit SHA fields"


class TestB12_SKILLCostExample:
    """B12: SKILL.md cost example must match actual compute_cost() output.

    The documented example at SKILL.md lines 193-194 shows:
        cost = compute_cost('qwen/qwen3.6-27b', 1000000, 500000, 800000)
        # {'raw_cost': 0.80, 'cache_adjusted_cost': 0.79, 'cache_savings': 0.01}

    Actual computation:
        raw_cost = 1000000 * 0.50/1M + 500000 * 1.50/1M = 0.50 + 0.75 = 1.25
        uncached = 1000000 - 800000 = 200000
        cache_adjusted = 200000 * 0.50/1M + 800000 * 0.05/1M + 500000 * 1.50/1M
                      = 0.10 + 0.04 + 0.75 = 0.89
        cache_savings = 1.25 - 0.89 = 0.36
    """

    def test_compute_cost_returns_correct_values(self):
        """compute_cost('qwen/qwen3.6-27b', 1000000, 500000, 800000) must
        return the mathematically correct values."""
        result = model_pricing.compute_cost(
            'qwen/qwen3.6-27b', 1000000, 500000, 800000
        )

        # raw_cost = 1M * $0.50/M + 500K * $1.50/M = $0.50 + $0.75 = $1.25
        assert result['raw_cost'] == 1.25, \
            f"raw_cost should be 1.25, got {result['raw_cost']}"

        # cache_adjusted = 200K * $0.50/M + 800K * $0.05/M + 500K * $1.50/M
        #               = $0.10 + $0.04 + $0.75 = $0.89
        assert result['cache_adjusted_cost'] == 0.89, \
            f"cache_adjusted_cost should be 0.89, got {result['cache_adjusted_cost']}"

        # cache_savings = 1.25 - 0.89 = 0.36
        assert result['cache_savings'] == 0.36, \
            f"cache_savings should be 0.36, got {result['cache_savings']}"

    def test_skill_md_cost_example_matches_actual_output(self):
        """The cost example in SKILL.md must match compute_cost() actual output."""
        result = model_pricing.compute_cost(
            'qwen/qwen3.6-27b', 1000000, 500000, 800000
        )

        skill_md = (SKILL_ROOT / "SKILL.md").read_text()

        # Check that the documented values appear in SKILL.md
        raw_str = f"'raw_cost': {result['raw_cost']}"
        adjusted_str = f"'cache_adjusted_cost': {result['cache_adjusted_cost']}"
        savings_str = f"'cache_savings': {result['cache_savings']}"

        assert raw_str in skill_md, \
            f"SKILL.md missing correct raw_cost value: {raw_str}"
        assert adjusted_str in skill_md, \
            f"SKILL.md missing correct cache_adjusted_cost value: {adjusted_str}"
        assert savings_str in skill_md, \
            f"SKILL.md missing correct cache_savings value: {savings_str}"
