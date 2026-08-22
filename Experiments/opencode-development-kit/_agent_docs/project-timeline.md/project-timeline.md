# Project Timeline

## 2026-08-15 — CollageMaker Report Regeneration + Session-Timeline Enrichment

**Purpose:** Regenerate the CollageMaker LLM usage report (`BlogPosts/references/CollageMaker-LLM-Report.html`) and add context on how tokens were used over time, using the session summaries in `CollageMaker/_agent_docs/project-timeline/sessions/`.

**Work completed:**
- Regenerated `CollageMaker-LLM-Report.html` + `-data.json` for the full project history (Jul 1 – Aug 4, 2026, 517 sessions, 717.7M raw → 48.1M effective tokens, 94.2% cache hit rate) — data matches the Aug 5 report exactly (no sessions recorded after Aug 4)
- Updated renderer fixes surfaced in the regenerated file: project name now substituted ("CollageMaker" instead of the old `[ProjectName]` placeholder), improved cost cards (single raw vs. with-cache pair) and metric tooltips
- Added a new collapsible section **"Session Timeline — How Tokens Were Used Over Time"** between *Charts & Visualizations* and *Cost Analysis*:
  - 5 phase cards with token share + highlights — Greenfield Build 33.3%, Stabilization & Change Requests 23.1%, Title & UX Refinement 16.7%, Undo/Redo & Mobile Redesign 14.4%, Mobile Polish & Multi-Touch 12.5%
  - 35-day day-by-day table: effective tokens, DB sessions, summaries, commits, +lines, agent mix, and a one-line narrative per day derived from the 233 session summaries
  - 5 observed usage patterns (build-docs ran every day; plan-bdd specs preceded multi-phase features; token intensity decayed 5.3M/day → ~0.6–0.9M/day; zero-commit days were plan/debug days; 233 of 517 sessions summarized)
- Appended a `session_timeline` payload (phases, daily rows, patterns) to the JSON data file

**Key findings:**
- Phase 1 (Greenfield, Jun 30 – Jul 5) consumed 33.3% of all effective tokens in 6 days, peaking at 5.3M effective tokens/day on Jul 5
- The DB contains three directories matching "CollageMaker" (206 + 741 + 517 sessions) — report generation must use the full path filter to isolate the austin183.github.io workspace
- Two summaries dated 2026-08-02 have no DB sessions under that date (matching work is timestamped Aug 3) — the daily table includes the day with 0 tokens and explains the gap
- One session summary file is malformed JSON (`2026-07-13-009`, leading-zero `session_number: 009`) — enrichment parsing needs a regex fallback

**Files:**
- Report: `austin183.github.io/BlogPosts/references/CollageMaker-LLM-Report.html`
- Data: `austin183.github.io/BlogPosts/references/CollageMaker-LLM-Report-data.json`
- Session: `_agent_docs/sessions/2026-08-15-003-build-docs-collagemaker-report-timeline.json`
- Skill: `.opencode/skills/analyzing-opencode-usage/` (used, not modified)

## 2026-08-08 — CollageMaker All-Time LLM Usage Report (Full History) & World-Review

**Purpose:** Generate comprehensive all-time LLM usage report for CollageMaker (May 10 - August 4, 2026, 1464 sessions) and prepare for world-review of the analytics skill.

**Work completed:**
- Generated consolidated HTML report (`CollageMaker-LLM-Usage-Report.html`) covering full project history (May 10 - August 4, 2026)
- Generated JSON data file (`CollageMaker-LLM-Usage-Report-data.json`) for programmatic access
- Reports written to `austin183.github.io/BlogPosts/references/`
- Session summary captured to `_agent_docs/sessions/`

**Key findings:**
- **517 sessions** (non-legacy) across 10 models and 18 agents (July 1 - August 4, 2026 subset; 1464 total sessions including legacy)
- **717M raw tokens** → **48M effective tokens** (94.2% cache hit rate)
- Cloud-equivalent cost: $375 raw → $67 cache-adjusted ($308 saved via caching)
- 58% productivity (296/505 sessions resulted in git commits)

**Top models:** qwen/qwen3.6-27b (277 sessions, $292 raw / $49 cache-adjusted), agents-a1 (33 sessions, $44 raw / $6.9 cache-adjusted), ornith-1.0-35b (34 sessions, $15 raw / $2.9 cache-adjusted)

**Top agents:** build-tdd (67 sessions, 288M raw), build-docs (121 sessions, 170M raw), build (32 sessions, 83M raw)

**Next steps:** Launch world-review subagent to review report quality and identify bugs/data anomalies in the analyzing-opencode-usage skill.

**World-Review Findings (2026-08-08):**
- **Overall trustworthiness: 75-80%** — core token counts and cost calculations are accurate, but derived metrics need context
- **8 known issues verified:**
  1. ✅ FIXED: `_resolve_date()` vulnerability to `'None'` string — properly handled now
  2. ✅ EXPECTED: `productive_sessions` token-ratio formula — documented limitation
  3. ✅ EXPECTED: Cache hit rate is simulated estimate — properly disclaimed
  4. ✅ EXPECTED: Cost calculation inconsistency (flat vs per-model) — intentional design
  5. ❌ FALSE POSITIVE: `references/` directory exists with both required files (activity-template.md, session-summary.json)
  6. ⚠️ MEDIUM: Two rendering paths key mismatch risk
  7. ⚠️ MEDIUM: Date range discrepancy in report vs prompt
  8. ℹ️ LOW: Zero-token sessions properly detected and logged
- **3 new findings:**
  1. Potential SQL injection risk in `build_where()` function (low-medium)
  2. UX issue: missing context for "Effective Tokens" in report headers (low-medium)
  3. Performance concern: N+1 query pattern in cache estimation (low)

**Recommended immediate actions:**
1. Create `references/` directory with required templates
2. Add input sanitization to `estimate_cache.py`'s `build_where()` function
3. Enhance UX with clearer metric explanations for raw vs effective tokens
4. Verify date range parameters match expected periods

**Files:**
- Report: `austin183.github.io/BlogPosts/references/CollageMaker-LLM-Usage-Report.html`
- Data: `austin183.github.io/BlogPosts/references/CollageMaker-LLM-Usage-Report-data.json`
- Session: `_agent_docs/sessions/` (TBD)
- Skill: `.opencode/skills/analyzing-opencode-usage/`

## 2026-08-06 — CollageMaker All-Time LLM Usage Report & World-Review Prep

**Purpose:** Generate fresh all-time LLM usage report for CollageMaker and prepare for world-review of the analytics skill.

**Work completed:**
- Generated consolidated HTML report (`CollageMaker-LLM-Usage-Report.html`) covering all-time data
- Generated JSON data file (`CollageMaker-LLM-Usage-Report-data.json`) for programmatic access
- Reports written to `austin183.github.io/BlogPosts/references/`
- Session summary captured to `_agent_docs/sessions/`

**Key findings:**
- **517 sessions** across 10 models and 18 agents (July 1 - August 4, 2026)
- **717M raw tokens** → **48M effective tokens** (94.2% cache hit rate)
- Cloud-equivalent cost: $375 raw → $67 cache-adjusted ($308 saved via caching)
- 58% productivity (296/505 sessions resulted in git commits)
- Models using fallback pricing: `laguna-s-2.1`, `qwen/qwen3.6-27b-q4`, `qwen/qwen3.6-27b-lite`, `qwen/qwen3.5-9b`

**Top models:** qwen/qwen3.6-27b (277 sessions, $292 raw / $49 cache-adjusted), agents-a1 (33 sessions, $44 raw / $6.9 cache-adjusted), ornith-1.0-35b (34 sessions, $15 raw / $2.9 cache-adjusted)

**Top agents:** build-tdd (67 sessions, 288M raw), build-docs (121 sessions, 170M raw), build (32 sessions, 83M raw)

**Next steps:** Launch world-review subagent to review report quality and identify bugs/data anomalies in the analyzing-opencode-usage skill.

**World-Review Findings:**
- **Overall trustworthiness: 75-80%** — core token counts and cost calculations are accurate, but derived metrics need context
- **3 Critical issues identified:**
  1. Flawed `productive_sessions` calculation in `merge.py:86-92` — uses token-ratio formula instead of actual build session counting
  2. `_resolve_date()` in `utils.py:30-35` vulnerable to `'None'` string being passed as a valid date
  3. Zero-token sessions for `qwen/qwen3.5-9b` — 2 sessions with 0 tokens across all categories
- **3 Warnings:** cache hit rate misinterpretation risk, cost calculation inconsistency (flat vs per-model), fallback pricing for 4 unknown models
- **4 Suggestions:** fix empty `created` fields in top sessions, add zero-token validation, improve productive sessions calculation, add Qwen variant pricing
- **Data anomalies:** zero-token sessions, empty created fields, weekly data gaps, commit vs sessions metric discrepancy

**Recommended actions:**
1. Immediate: add validation warning for zero-token sessions in `merge.py`
2. Short-term: fix empty `created` fields in `top_sessions.py` query
3. Medium-term: replace token-ratio formula with proper build-agent session counting
4. Documentation: add prominent disclaimer that cache hit rates are simulated estimates

**Files:**
- Report: `austin183.github.io/BlogPosts/references/CollageMaker-LLM-Usage-Report.html`
- Data: `austin183.github.io/BlogPosts/references/CollageMaker-LLM-Usage-Report-data.json`
- Session: `_agent_docs/sessions/2026-08-06-002-build-docs-collagemaker-alltime-report.json`
- Skill: `.opencode/skills/analyzing-opencode-usage/`

## 2026-08-05 — CollageMaker LLM Usage Analysis (Updated All-Time Report)

**Purpose:** Generate updated all-time LLM usage report for CollageMaker and prepare for world-review of the analytics skill.

**Work completed:**
- Generated updated consolidated HTML report (`CollageMaker-LLM-Report.html`, 190KB) covering 517 sessions from July 1 - August 4, 2026
- Generated updated JSON data file (`CollageMaker-LLM-Report-data.json`, 120KB) for programmatic access
- Reports written to `austin183.github.io/BlogPosts/references/`

**Key findings:**
- **517 sessions** across 10 models and 18 agents
- **717M raw tokens** → **48M effective tokens** (94.2% cache hit rate)
- Cloud-equivalent cost: $375 raw → $67 cache-adjusted ($308 saved via caching)
- Models using fallback pricing: `laguna-s-2.1`, `qwen/qwen3.6-27b-q4`, `qwen/qwen3.6-27b-lite`, `qwen/qwen3.5-9b`

**Top models:** qwen/qwen3.6-27b (277 sessions, $292 raw / $49 cache-adjusted), agents-a1 (33 sessions, $44 raw / $6.9 cache-adjusted), ornith-1.0-35b (34 sessions, $15 raw / $2.9 cache-adjusted)

**Next steps:** Launch world-review subagent to review report quality and identify bugs/data anomalies in the analyzing-opencode-usage skill.

**Files:**
- Report: `austin183.github.io/BlogPosts/references/CollageMaker-LLM-Report.html`
- Data: `austin183.github.io/BlogPosts/references/CollageMaker-LLM-Report-data.json`
- Skill: `.opencode/skills/analyzing-opencode-usage/`

## 2026-08-01 — CollageMaker LLM Usage Analysis

**Purpose:** Generate comprehensive LLM usage report for CollageMaker project and review analytics skill for bugs.

**Work completed:**
- Generated consolidated HTML report (`CollageMaker-LLM-Report.html`, 188KB) covering 509 sessions from July 1 - August 1, 2026
- Generated JSON data file (`CollageMaker-LLM-Report-data.json`, 117KB) for programmatic access
- Reports written to `austin183.github.io/BlogPosts/references/`
- Conducted comprehensive code review of `analyzing-opencode-usage` skill

**Key findings:**
- **509 sessions** across 10 models and 18 agents
- **709M raw tokens** → **47M effective tokens** (94.2% cache hit rate)
- **58% productivity** (295/509 sessions resulted in git commits)
- Cloud-equivalent cost: $361 raw → $63 cache-adjusted ($298 saved via caching)

**Bugs discovered:**
1. **`_resolve_date()` returns `'None'` string** — `str(None)` used as SQL parameter; works by accident via ASCII ordering
2. **`productive_sessions` > `total_build_sessions`** — counts ALL sessions on commit dates, not just build sessions
3. **Hardcoded phase dates** — May-June 2026 ranges produce empty phases for July-August report
4. **Cost calculation inconsistency** — flat rates vs per-model rates produce different totals
5. **Missing `references/` directory** — SKILL.md references templates that don't exist

**Top models:** qwen3.6-27b (567M raw), agents-a1 (86M), ornith-1.0-35b (20M)
**Top agents:** build-tdd (282M), build-docs (169M), build (83M)

**Files:**
- Report: `austin183.github.io/BlogPosts/references/CollageMaker-LLM-Report.html`
- Data: `austin183.github.io/BlogPosts/references/CollageMaker-LLM-Report-data.json`
- Session: `_agent_docs/sessions/2026-08-01-001-build-docs-collagemaker-report.json`
- Template: `.opencode/skills/analyzing-opencode-usage/references/session-summary.json`
