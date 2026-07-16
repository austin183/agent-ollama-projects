# Plan: Interactive LLM Usage Visualization

Replace static SVG charts in the analyzing-opencode-usage skill with interactive 2D/3D charts using Chart.js + Plotly.js, modeled after the TaxBracketVisualizer.

## Motivation

The current consolidated report generates static inline SVG charts via `charts.py`. This limits interactivity — no zoom, no hover detail, no toggle layers, no 3D exploration. The TaxBracketVisualizer demonstrates a better pattern: a single HTML file that ships data as JSON and renders interactive charts client-side via CDN libraries (Vue + Chart.js + Plotly.js).

## Architecture

```
generate_consolidated_report.sh (unchanged pipeline orchestration)
  → sqlite3 queries (summary, models, agents, timeseries, git stats)
  → estimate_cache.py (cache-adjusted per-message analysis)
  → NEW: model_pricing.py (per-model cost lookup)
  → REWRITE: render_consolidated_report.py
      │
      └── Emits single self-contained HTML file with:
          ├─ <script id="report-data" type="application/json">...</script>
          ├─ Vue 3 from CDN (reactive controls, tabbed panels)
          ├─ Chart.js from CDN (2D interactive charts)
          ├─ Plotly.js from CDN (3D interactive charts)
          └─ Client-side JS renders all charts from embedded JSON
```

## Files Changed

| File | Action | Est. Lines | Notes |
|---|---|---|---|
| `model_pricing.py` | **Create** | ~60 | Pricing lookup dict + `compute_cost(model, tokens, cache_hit)` |
| `render_consolidated_report.py` | **Rewrite** | ~600→500 | Emit interactive HTML skeleton instead of static SVG content |
| `charts.py` | **Delete** | ~1160 | SVG rendering entirely replaced by browser-side charts |
| `estimate_cache.py` | **Minor patch** | +20 | Optionally output per-model pricing data |
| `generate_consolidated_report.sh` | **Minor patch** | +10 | Wire up pricing flag |
| `SKILL.md` | **Modify** | 2 sections | Update examples, remove SVG references |

## Tabbed Interface Layout

| Tab | Content | Library |
|---|---|---|
| **Overview** | Summary metric cards, date range selector, key numbers, productivity stats (sessions/day, commits/week, avg tok/session) | Vue reactive cards |
| **3D Agent Topology** | Surface plot: Time × Cognitive Load × Effective Tokens | Plotly.js surface trace |
| **3D Efficiency Scatter** | Bubble scatter: tok/commit × lines/commit × time | Plotly.js scatter3d |
| **Token Trends** | Stacked area (input/output/reasoning) + Waterfall (cache savings) + Cumulative curves | Chart.js |
| **Model Breakdown** | Pareto + Model adoption timeline + Sunburst hierarchy | Chart.js + Plotly.js |
| **Cost Analysis** | Dual-axis: Actual ($0, flat) vs Cloud-Equivalent cost over time | Chart.js |
| **Efficiency** | Rolling tok/commit + scatter (tokens vs lines) + Agent donut | Chart.js |
| **Details** | Commit efficiency rankings, agent context efficiency, top sessions table, cache approximation breakdown | Vue reactive tables |

## Work Categories (Agent-Based with Cognitive Load Ordering)

| Y | Category | Agents | Description |
|---|---|---|---|
| 0 | **Explore** | `explore` | Light research, codebase reading |
| 1 | **Review** | `diff-review`, `diff-review-g31`, `solid-review`, `world-review`, `diff-review-q35`, `diff-review-o32` | Code evaluation, PR review |
| 2 | **Plan** | `planner`, `planner-g31`, `plan` | Architecture, design |
| 3 | **Build** | `build` | Implementation, coding |
| 4 | **Other** | everything else (skill-extraction, debugging, config, etc.) | Debugging, docs, troubleshooting |

## 3D Charts

### 1. Agent Activity Topology (Primary)

- **Trace type**: `Plotly surface` or `mesh3d`
- **X axis**: Time (weeks since project start, sorted ascending)
- **Y axis**: Cognitive load category (0=Explore → 4=Other)
- **Z axis**: Effective (cache-adjusted) token volume
- **Controls**: Date range slider, model filter dropdown
- **Visual**: Colored surface where peaks show heavy-effort periods by work type

### 2. Efficiency 3D Scatter

- **Trace type**: `Plotly scatter3d`
- **X axis**: Tokens per commit (log scale)
- **Y axis**: Lines changed per commit (log scale)
- **Z axis**: Time (days)
- **Color**: Agent category
- **Size**: Cache savings magnitude
- **Visual**: Clusters show agent behavior patterns; outliers are inefficiency hotspots

## 2D Charts (Chart.js)

### Must-Have
1. **Stacked Area** — Daily tokens by type (input/output/reasoning), cache-adjusted
2. **Waterfall** — Raw Input → Cached Savings → Uncached Input → Reasoning → Output
3. **Cumulative Curves** — Running total of effective tokens over time (mirrors current collapsible section)
4. **Pareto Model Contribution** — Bar + cumulative line by model
5. **Agent Donut** — % of effective tokens by work category (range-selectable)
6. **Model Adoption Timeline** — Stacked bar: which models used each week
7. **Tokens vs Lines Scatter** — Colored by agent, sized by effective tokens
8. **Rolling 7-Day Efficiency** — Smoothed tok/commit with range selector

### Nice-to-Have
8. **Sunburst** — Hierarchy: Directory → Agent → Model → Tokens
9. **Phase Breakdown** — Grouped bar across project phases (if phase data present)
10. **Session Duration Distribution** — Histogram of session lengths

## Details Tab (Tabular Data)

Tabular sections that complement the chart-heavy tabs. All tables are sortable and filterable by date range.

### 1. Commit Efficiency Rankings

- **Columns**: Commit SHA, Date, Agent, Model, Tokens (effective), Lines Changed, Tok/Commit, Lines/Commit
- **Sort**: Default by tok/commit ascending (most efficient first)
- **Purpose**: Identify which sessions delivered the most code per token; outliers flag inefficiency

### 2. Agent Context Efficiency

- **Columns**: Agent, Sessions, Avg Input Tokens/Turn, Avg Turns/Session, Context Growth Rate (tokens added per turn)
- **Purpose**: Show how efficiently each agent role uses context windows; high context growth = more wasted prefix re-sends

### 3. Top Sessions Table

- **Columns**: Title, Date, Agent, Model, Input Tokens (raw/uncached), Output Tokens, Reasoning Tokens, Total, Files Changed, Lines Added/Deleted
- **Sort**: Default by total tokens descending
- **Pagination**: Show top 20, load more on demand
- **Purpose**: Quick reference for highest-cost sessions with raw and cache-adjusted values side by side

### 4. Cache Approximation Breakdown

- **Columns**: Date, Sessions, Raw Input, Estimated Cached, Estimated Uncached, Cache Hit %, Effective Total
- **Groupable by**: Model, Agent (toggle)
- **Purpose**: Detailed view of prefix caching impact, mirroring the current collapsible cache approximation section

## Pricing Model

### Single Pricing Lookup Module (`model_pricing.py`)

```python
MODEL_PRICING = {
    # Cloud providers (real public pricing)
    'openai/gpt-4o':              {'input': 2.50,  'output': 10.00, 'cached_input': 1.25},
    'anthropic/claude-sonnet-4':  {'input': 3.00,  'output': 15.00, 'cached_input': 0.30},
    'google/gemma-4-31b-qat':     {'input': 0.25,  'output': 1.00,  'cached_input': 0.025},
    # Local models (cloud-equivalent estimates for "what-if" cost)
    'qwen/qwen3.6-27b':           {'input': 0.50,  'output': 1.50,  'cached_input': 0.05},
    'qwen/qwen3.6-35b-a3b':       {'input': 0.80,  'output': 2.40,  'cached_input': 0.08},
    'qwen/qwq-32b':               {'input': 0.60,  'output': 1.80,  'cached_input': 0.06},
    'ornith-1.0-35b':             {'input': 0.70,  'output': 2.10,  'cached_input': 0.07},
    'qwen/qwen3-coder-next':      {'input': 0.75,  'output': 2.25,  'cached_input': 0.075},
    'qwen-agentworld-35b-a3b':    {'input': 0.80,  'output': 2.40,  'cached_input': 0.08},
    'gemini/gemini-2.5-flash':    {'input': 0.15,  'output': 0.60,  'cached_input': 0.015},
    'fallback':                   {'input': 0.50,  'output': 1.50,  'cached_input': 0.05},
}
```

### Dual Cost Display

All cost charts show:
- **Primary Y-axis** (left): Cloud-equivalent cost computed from per-model pricing × token counts
- **Secondary display**: Cache-adjusted cost using `estimated_uncached_input` instead of raw input
- **Annotation**: "Actual cost: $0 (all models run on local LM Studio)"
- **Cache savings**: **"$X.XX saved thanks to prefix caching"** shown in dollar amounts alongside percentage

## Data Flow (render_consolidated_report.py rewrite)

1. Read enriched JSON payload from stdin (unchanged — produced by shell pipeline)
2. Call `model_pricing.compute_pricing(data)` to attach per-model cost data
3. Call `estimate_cache` enrichments (already in payload from shell)
4. Build HTML skeleton with embedded JSON in `<script>` tag
5. Inline chart rendering JS reads `window.REPORT_DATA` and calls Chart.js/Plotly.js APIs
6. Write complete HTML to stdout

## Implementation Steps (in order)

### Phase 0: Foundation
- Create `model_pricing.py` with pricing dict, `get_pricing()`, `compute_cost()`, `enrich_data()`
- Patch `generate_consolidated_report.sh` to wire `model_pricing.py` into merge step
- Patch `estimate_cache.py` with `--pricing` flag passthrough
- Verify enriched JSON payload includes cost data

### Phase 1: HTML Skeleton + Overview Tab (P0)
- Rewrite `render_consolidated_report.py` to emit HTML with embedded JSON, Vue 3/Chart.js/Plotly.js from CDN
- Overview tab: summary metric cards, productivity stats, cache savings in $ amounts
- Tab navigation shell (8 tabs, Overview functional first)

### Phase 2: 2D Charts (P0 MVP)
- Token Trends: stacked area, cumulative curves
- Model Breakdown: Pareto chart
- Cost Analysis: dual-axis with "$0 actual + cloud-equivalent" + "$ saved thanks to prefix caching"
- Efficiency: rolling tok/commit, agent donut
- Details: commit efficiency table, top sessions table

### Phase 3: 3D Charts + Polish (P1)
- 3D Agent Topology surface plot
- 3D Efficiency Scatter bubble chart
- Waterfall chart, model adoption timeline, sunburst (nice-to-have)
- Reactive date range filter across all tabs
- Sortable/filterable tables in Details tab

### Phase 4: Cleanup
- Delete `charts.py` (~1160 lines of dead SVG code)
- Update `SKILL.md` to reflect interactive charts

## Verification

```bash
# Generate interactive report
bash .opencode/skills/analyzing-opencode-usage/script/generate_consolidated_report.sh \
  --days 30 --pricing

# Verify in browser
open _agent_docs/project-timeline/llm-usage/*.html
```

**Manual checklist**:
- [ ] All 8 tabs switch correctly
- [ ] 3D topology renders with meaningful surface
- [ ] 3D scatter shows agent-colored points
- [ ] Cost dual-axis shows "$0 actual" + cloud-equivalent + "$ saved thanks to prefix caching"
- [ ] Waterfall chart shows cache savings visually
- [ ] Stacked area toggles layers on click
- [ ] Cumulative curves render in Token Trends tab
- [ ] Details tab: tables are sortable and filterable
- [ ] Overview: productivity stats cards display correctly
- [ ] Date range slider updates charts and tables

## Resolved Questions

- **Historical pricing**: Static pricing based on today's rates is sufficient. No need to track price changes over time.
- **Cache cost savings**: In addition to percentage, all cost displays will show **"$ saved thanks to prefix caching"** in dollar amounts.
- **Session categories**: Subagent and model name are sufficient categories. No keyword matching on session/git titles.
- **Cloud API pricing**: Not needed. All models run locally via LM Studio. Occasional free cloud models may be added but won't require pricing integration.

## Scope Prioritization

### P0 — MVP (Deliver first)

| Feature | Tab | Effort |
|---------|-----|--------|
| Summary metric cards (effective tokens, sessions, cost, cache hit rate) | Overview | Low |
| Tab navigation (8 tabs) | All | Low |
| Stacked area chart (input/output/reasoning, cache-adjusted) | Token Trends | Medium |
| Cumulative efficiency curves | Token Trends | Medium |
| Model Pareto chart | Model Breakdown | Medium |
| Cost analysis with "$0 actual + cloud-equivalent" | Cost Analysis | Medium |
| "$ saved thanks to prefix caching" display | Cost Analysis | Low |
| Rolling tok/commit trend | Efficiency | Medium |
| Agent donut chart | Efficiency | Low |
| Commit efficiency table | Details | Medium |
| Top sessions table | Details | Low |

### P1 — Nice-to-Have (Add after MVP)

| Feature | Tab | Effort |
|---------|-----|--------|
| 3D Agent Topology surface plot | 3D Agent Topology | High |
| 3D Efficiency Scatter | 3D Efficiency Scatter | High |
| Waterfall chart (cache savings breakdown) | Token Trends | Medium |
| Model adoption timeline | Model Breakdown | Medium |
| Sunburst hierarchy | Model Breakdown | High |
| Date range filter (reactive) | All | Medium |
| Sortable/filterable tables | Details | Medium |
| Phase breakdown chart | Efficiency | Low |

## Edge Cases

| Edge Case | Handling |
|-----------|----------|
| **Empty database** (no sessions) | Show "No data for this period" message. Metric cards show zeros. |
| **Single session** | Charts render with single data point. |
| **Missing model in pricing dict** | Fall back to `_fallback` pricing. Log warning to stderr. |
| **Model with NULL agent** | Already handled by `COALESCE` in SQL queries. Shows as "unknown". |
| **Date range with no data** (e.g. weekend gaps) | Chart.js `spanGaps: true` handles gaps. |
| **Very large token counts** (> 1B) | `fmtTokens()` handles B suffix. Chart.js auto-scales axes. |
| **Cache estimate fails** | Cache-adjusted values fall back to raw values. |
| **Git log fails** (no repo) | Efficiency metrics are 0, charts show flat lines. |
| **CDN failure** (Chart.js or Plotly.js) | Graceful degradation: affected tabs show error message, other tabs still work. |

---

*Plan written 2026-07-04 for the CollageMaker project's analyzing-opencode-usage skill.*
