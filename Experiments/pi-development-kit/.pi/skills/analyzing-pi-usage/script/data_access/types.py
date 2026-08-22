#!/usr/bin/env python3
"""Type definitions for pi LLM usage analytics.

All data structures use TypedDict with explicit fields for IDE support and
early error detection. Raw query results contain parsed-JSONL values; enriched
results include computed/cached fields. The summary carries
cache_read/cache_write (provider-reported) and actual cost, plus
subagent-run and session-summary datasets.
"""

from typing import TypedDict


# ── Raw query result types (from parsed session JSONL) ────────────────────────

class SummaryRow(TypedDict):
    """Raw summary from session aggregation."""
    total_sessions: int
    total_tokens_raw: int
    total_input_raw: int
    total_output: int
    total_reasoning: int
    cache_read: int
    cache_write: int
    actual_cost: float
    earliest: str
    latest: str
    model_count: int
    role_count: int


class DailyTokenRow(TypedDict):
    """Raw daily token counts by role category."""
    date: str
    sessions: int
    # Raw values
    total_tokens_raw: int
    input_tokens_raw: int
    output_tokens_raw: int
    reasoning_tokens_raw: int
    build_tok_raw: int
    review_tok_raw: int
    plan_tok_raw: int
    explore_tok_raw: int
    other_tok_raw: int


class ModelRow(TypedDict):
    """Raw model usage data."""
    model: str
    sessions: int
    total_tokens_raw: int
    input_tokens_raw: int
    output_tokens_raw: int
    reasoning_tokens_raw: int


class RoleRow(TypedDict):
    """Raw role usage data."""
    role: str
    sessions: int
    total_tokens_raw: int
    input_tokens_raw: int
    output_tokens_raw: int
    reasoning_tokens_raw: int


class CrossTabRow(TypedDict):
    """Model-role cross-tabulation."""
    model: str
    role: str
    sessions: int
    total_tokens_raw: int


class TopSessionRow(TypedDict):
    """Top sessions by token usage."""
    session_id: str
    title: str
    model: str
    role: str
    created: str
    tokens: int
    input_tokens: int
    output_tokens: int
    reasoning_tokens: int


class WeeklyRow(TypedDict):
    """Weekly aggregation by role category."""
    week: str
    week_start: str
    week_end: str
    sessions: int
    total_tokens_raw: int
    build_tokens: int
    review_tokens: int
    planner_tokens: int


class ProductivityRow(TypedDict):
    """Aggregated productivity metrics (sessions matched to git commit dates)."""
    total_sessions: int
    sessions_with_changes: int
    pct_with_changes: float


class BuildProductivityRow(TypedDict):
    """Build-role token efficiency."""
    date: str
    build_tokens: int
    commits: int
    tokens_per_commit: float
    total_build_sessions: int
    productive_sessions: int
    total_tokens: int
    zero_change_tokens: int
    pct_productive: float


class GitCommitRow(TypedDict):
    """Per-commit git statistics."""
    date: str
    commits: int
    lines_added: int
    lines_deleted: int
    authors: dict[str, int]


class DailyGitRow(TypedDict):
    """Daily git stats with test-file breakdown."""
    date: str
    total_commits: int
    total_adds: int
    total_deletes: int


class CacheEstimateRow(TypedDict):
    """Cache estimate by dimension (measured when the provider reports
    cacheRead/cacheWrite; LAG-delta simulated otherwise)."""
    key: str  # model, role, day, or None for aggregate
    value: str  # actual value (e.g., model name, or 'aggregate')
    sessions: int
    total_turns: int
    total_input_raw: int
    estimated_uncached_input: int
    estimated_cached_input: int
    cache_hit_pct: float
    total_output: int
    total_reasoning: int
    effective_total: int
    raw_total: int
    simulated: bool  # True when the LAG-delta fallback was used


class SubagentRunRow(TypedDict):
    """One subagent run (from a parent session's subagent tool result)."""
    agent: str
    model: str
    day: str
    session_id: str
    turns: int
    context_tokens: int
    input: int
    output: int
    cost: float
    depth: int
    stop_reason: str


class SubagentAgentRow(TypedDict):
    """Subagent usage aggregated by agent."""
    agent: str
    runs: int
    turns: int
    total_input: int
    total_output: int
    total_cost: float
    models: list[str]


class SessionSummaryStats(TypedDict):
    """Join with [docs directory]/sessions/*.json summaries."""
    total: int
    by_purpose: dict[str, int]
    by_outcome: dict[str, int]
    by_role: dict[str, int]


# ── Enriched types (after aggregation) ───────────────────────────────────────

class Summary(SummaryRow):
    """Enriched summary with computed fields."""
    # Cache-adjusted fields (added by aggregator)
    input_tokens_uncached: int
    output_tokens_cached: int
    reasoning_tokens_cached: int
    total_tokens_effective: int
    cache_hit_pct: float
    # Cost fields
    cost_cheap_raw: float
    cost_expensive_raw: float
    cost_cheap_cached: float
    cost_expensive_cached: float


class DailyTokenRowWithCache(DailyTokenRow):
    """Daily token row with cache-adjusted fields."""
    input_tokens_uncached: int
    output_tokens_cached: int
    reasoning_tokens_cached: int
    total_effective: int
    # Cost fields (by day)
    cost_cheap: float
    cost_expensive: float


class ModelRowWithCost(ModelRow):
    """Model row with cost and cache data."""
    # Cache-adjusted
    input_tokens_uncached: int
    output_tokens_cached: int
    reasoning_tokens_cached: int
    total_effective: int
    # Cost fields
    raw_cost: float
    cache_adjusted_cost: float
    cache_savings: float


class RoleRowEnriched(RoleRow):
    """Enriched role row."""
    input_tokens_uncached: int
    output_tokens_cached: int
    reasoning_tokens_cached: int
    total_effective: int


class CacheEstimateAggregated(TypedDict):
    """Aggregated cache estimate data."""
    sessions: int
    total_turns: int
    total_input_raw: int
    estimated_uncached_input: int
    estimated_cached_input: int
    cache_hit_pct: float
    total_output: int
    total_reasoning: int
    effective_total: int
    raw_total: int
    simulated: bool


class CostSummary(TypedDict):
    """Cost summary for raw and cached tokens."""
    total_cheap: float
    total_expensive: float
    # May include breakdown fields


class ModelPricing(TypedDict):
    """Pricing per model (cloud-equivalent)."""
    model: str
    input_cost_per_million: float
    output_cost_per_million: float
    reasoning_cost_per_million: float


class Meta(TypedDict):
    """Report metadata."""
    title: str
    since: str
    until: str
    generated: str
    # True all-time project range (query-filter-independent)
    project_since: str
    project_until: str
    total_sessions_all_time: int


# ── Full report structure ────────────────────────────────────────────────────

class ReportData(TypedDict):
    """Complete report JSON structure."""
    meta: Meta
    summary: Summary
    cost_summary: CostSummary
    cache_cost_summary: CostSummary
    model_pricing: dict[str, ModelPricing]
    models_with_cost: list[ModelRowWithCost]
    productivity: list[ProductivityRow]
    build_productivity: list[BuildProductivityRow]
    models: list[ModelRow]
    roles: list[RoleRowEnriched]
    cross_tab: list[CrossTabRow]
    top_sessions: list[TopSessionRow]
    timeseries: list[DailyTokenRowWithCache]
    cache_estimate: CacheEstimateAggregated
    subagent_runs: dict
    session_summaries: SessionSummaryStats
    most_efficient_commits: list[dict]
    least_efficient_commits: list[dict]
    warnings: list[str]
