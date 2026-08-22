#!/usr/bin/env python3
"""Type definitions for [ProjectName] LLM usage analytics.

All data structures use TypedDict with explicit fields for IDE support and early error detection.
Raw query results contain database values; enriched results include computed/cached fields.
"""

from typing import TypedDict


# ── Raw query result types (from database) ────────────────────────────────────

class SummaryRow(TypedDict):
    """Raw summary from session aggregation."""
    total_sessions: int
    total_tokens_raw: int
    total_input_raw: int
    total_output: int
    total_reasoning: int
    cache_hit_pct: float
    earliest: str
    latest: str
    model_count: int
    agent_count: int


class DailyTokenRow(TypedDict):
    """Raw daily token counts by phase."""
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


class AgentRow(TypedDict):
    """Raw agent role usage data."""
    agent: str
    sessions: int
    total_tokens_raw: int
    input_tokens_raw: int
    output_tokens_raw: int
    reasoning_tokens_raw: int


class CrossTabRow(TypedDict):
    """Model-agent cross-tabulation."""
    model: str
    agent: str
    sessions: int
    total_tokens_raw: int


class TopSessionRow(TypedDict):
    """Top sessions by token usage."""
    session_id: str
    title: str
    model: str
    agent: str
    created: str
    tokens: int
    input_tokens: int
    output_tokens: int
    reasoning_tokens: int


class AgentContextRow(TypedDict):
    """Agent context type aggregation."""
    context_type: str
    sessions: int
    total_tokens_raw: int
    input_tokens_raw: int
    output_tokens_raw: int
    reasoning_tokens_raw: int


class WeeklyRow(TypedDict):
    """Weekly aggregation by agent category."""
    week_start: str
    week_end: str
    sessions: int
    total_tokens_raw: int
    build_tokens: int
    review_tokens: int
    planner_tokens: int


class ProductivityRow(TypedDict):
    """Aggregated productivity metrics (sessions with file changes)."""
    total_sessions: int
    sessions_with_changes: int
    pct_with_changes: float


class BuildProductivityRow(TypedDict):
    """Build-phase token efficiency."""
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
    """Git commit statistics."""
    date: str
    commits: int
    lines_added: int
    lines_deleted: int
    authors: dict[str, int]


class DailyGitRow(TypedDict):
    """Daily git stats with author breakdown."""
    date: str
    total_commits: int
    total_adds: int
    total_deletes: int


class CacheEstimateRow(TypedDict):
    """Cache estimation by dimension."""
    # For aggregate or breakdown rows
    key: str  # model, agent, day, or None for aggregate
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


class PerSessionCacheRow(TypedDict):
    """Per-session cache estimates."""
    session_id: str
    agent: str
    model: str
    title: str
    created: str
    turns: int
    total_input_raw: int
    estimated_uncached_input: int
    estimated_cached_input: int
    cache_hit_pct: float
    total_output: int
    total_reasoning: int
    min_input: int
    max_input: int


# ── Enriched types (after aggregation) ───────────────────────────────────────

class Summary(SummaryRow):
    """Enriched summary with computed fields."""
    # Cache-adjusted fields (added by aggregator)
    input_tokens_uncached: int
    output_tokens_cached: int
    reasoning_tokens_cached: int
    total_tokens_effective: int
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
    cost_cheap_raw: float
    cost_expensive_raw: float
    cost_cheap_cached: float
    cost_expensive_cached: float


class AgentRowEnriched(AgentRow):
    """Enriched agent row."""
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


class CacheEstimateByModel(TypedDict):
    """Cache estimate breakdown by model."""
    model: str
    sessions: int
    total_input_raw: int
    estimated_uncached_input: int
    estimated_cached_input: int
    cache_hit_pct: float
    total_output: int
    total_reasoning: int


class CacheEstimateByAgent(TypedDict):
    """Cache estimate breakdown by agent."""
    agent: str
    sessions: int
    total_input_raw: int
    estimated_uncached_input: int
    estimated_cached_input: int
    cache_hit_pct: float
    total_output: int
    total_reasoning: int


class CacheEstimateByDay(TypedDict):
    """Cache estimate breakdown by day."""
    day: str
    sessions: int
    total_input_raw: int
    estimated_uncached_input: int
    estimated_cached_input: int
    cache_hit_pct: float
    total_output: int
    total_reasoning: int


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
    # True all-time project range (query-filter-independent), from fetch_project_range
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
    agents: list[AgentRowEnriched]
    cross_tab: list[CrossTabRow]
    top_sessions: list[TopSessionRow]
    weekly: list[WeeklyRow]
    agents_detailed: list[AgentContextRow]
    timeseries: list[DailyTokenRowWithCache]
    daily_agent_stacked: list[DailyTokenRowWithCache]
    cache_estimate: CacheEstimateAggregated
    phases: dict[str, int]
    most_efficient_commits: list[dict]
    least_efficient_commits: list[dict]

