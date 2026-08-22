# Analytics Script Debugging — Learnings 2026-07-10

**Purpose**: Document hard-won insights from debugging the LLM usage analytics pipeline, fixing data inconsistencies, and interpreting project usage patterns.

## What Worked

- **Git-based productivity as ground truth**: Since `summary_files` is always 0 in the opencode DB, computing "sessions with changes" by matching session dates to git commit dates is a pragmatic workaround that produces meaningful numbers (41.9% sessions with changes).
- **`LIKE 'build%'` over exact match**: The DB stores agent names like `build-docs`, `build-test`, `build-tdd`, `build-debug`, `build-quick-work` — not just `build`. Using `agent LIKE 'build%' OR agent = 'general'` captures all build-related sessions. This pattern applies to any agent that has variants.
- **Cache-adjusted tokens are the right metric**: Raw tokens (310M) are misleading due to 93.7% cache hit rate. Effective tokens (22M) — uncached input + output + reasoning — tell the real story of LLM work done.
- **Cross-referencing DB data with session summaries**: Combining LLM token data with session summary files (`_agent_docs/project-timeline/sessions/`) reveals the narrative behind the numbers — e.g., Jul 4-5's zero-commit days were test/docs sessions, not wasted effort.

## What Didn't Work / Gaps

- **`summary_files > 0` check is dead code**: This column is never populated in the opencode DB. Any query relying on it will always return 0. The `build_productivity` query used it for `productive_sessions` and `pct_productive`, producing 0% for both cards.
- **`BuildProductivityRow` type was incomplete**: The TypedDict only had `build_tokens`, `commits`, `tokens_per_commit` — but the renderer expected `pct_productive`, `zero_change_tokens`, `total_build_sessions`, `productive_sessions`. The query computed these fields but the return mapping didn't pass them through.
- **Agent category `Total` column showed 0**: The chart table read `total_tokens` key, but the merged data uses `total_effective`. One-character key mismatch, silent failure.
- **`productive_sessions` in build_productivity is misleading**: It counts ALL sessions on commit days, not just build sessions. Not displayed in any card, but the field name implies it's build-only.
- **Raw vs cache-adjusted comparison bug**: Initially compared raw build tokens (289M) from DB against cache-adjusted daily build tokens (~20M) — apples to oranges. Must compare like with like.
- **`cached_vals` line in Tokens vs Commits chart**: Cached input values (6M–92M) are 10–20× larger than effective tokens (1M–5M), making them unreadable on the same scale. Removed from chart, kept in data table.

## What Was Confusing

- **Two rendering paths**: `generate_report.py` produces JSON, then `render_consolidated_report.py` renders HTML from the same JSON. But the HTML chart functions in `charts.py` read from the JSON data directly. A key mismatch in one place doesn't show in the other.
- **`models` vs `models_with_cost`**: The `models` query returns raw data correctly. The `models_with_cost` enrichment adds cost fields. The initial inspection showed 0s because I looked at the wrong field names in the HTML bar charts (which use `total_effective`, not `total_tokens_raw`).
- **Session summaries vs DB sessions**: 74 session summary files vs 215 DB sessions. Not every LLM session gets a summary file — only the ones the agent deemed worth documenting.

## Skill Improvements

### For `analyzing-opencode-usage` skill
- Add a data validation step that checks: (1) all expected keys exist in merged output, (2) agent category sums match `total_effective`, (3) no key mismatches between query output and renderer expectations
- Document that `summary_files` is always 0 — use git dates instead
- Add `agent LIKE 'build%'` pattern to the skill as a known DB convention

### For `capturing-learnings` skill
- The debrief template works well for technical debugging sessions
- Consider adding a "Data Anomalies Found" section for analytics work

### For `building-web-apps` skill (N/A here, but noted)
- N/A — this session was about analytics, not web app development

## Bugs Fixed in This Session

| Bug | File | Fix |
|---|---|---|
| Agent category "Other" catching `build-*` variants | `daily_tokens.py:45-49` | `agent LIKE 'build%' OR agent = 'general'` |
| Same agent matching in weekly query | `weekly.py:43-45` | Same pattern |
| `build_productivity` using exact `agent = 'build'` | `build_productivity.py:45` | Same pattern |
| `BuildProductivityRow` missing fields | `types.py` | Added `total_build_sessions`, `productive_sessions`, `total_tokens`, `zero_change_tokens`, `pct_productive` |
| `build_productivity` return mapping incomplete | `build_productivity.py:63-70` | Return all fields |
| Git-based productivity not computed | `merge.py` | Added computation from merged daily data + git dates |
| Chart `Total` column showing 0 | `charts.py:753` | `total_tokens` → `total_effective` |
| Chart cached input line off-screen | `charts.py` | Removed polyline and legend, kept in data table |
| Missing `solid-review-g31` in review category | `daily_tokens.py:46` | Added to IN list |
| Missing `planner-g4` in plan category | `daily_tokens.py:47` | Added to IN list |

## Key Data Insights

- **93.7% cache hit rate** means raw tokens are 14× effective tokens — always use effective for comparisons
- **Jul 5 spike** (97M raw, 5.3M effective) was `agents-a1` model usage (32 sessions, 79M raw) — high raw cost but contained effective cost due to caching
- **46% of documented sessions are `docs` purpose** (34/74) — meta-work that compounds value but doesn't ship code
- **Review agents are most token-efficient** (39–42% effective ratio) — consider using them more as pre-commit gates
- **Greenfield is cheapest** (96 tok/line) vs iteration (618–902 tok/line) — context accumulation is the real cost driver

## Next Steps

- [ ] Add automated data validation to report generation pipeline
- [ ] Fix `productive_sessions` field to count only build sessions on commit days (or rename to clarify it's all sessions)
- [ ] Consider adding a "sessions without summary file" metric to track undocumented LLM work
- [ ] Document the `LIKE 'build%'` pattern in the analytics skill

---
**Status**: Closed
**Follow-up**: Analytics script validation improvements
