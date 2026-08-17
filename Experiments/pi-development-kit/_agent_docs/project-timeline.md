# Project Timeline

## 2026-08-17 — Port opencode-development-kit Agents and Skills to pi (Phases 0–5)

**Purpose:** Make the opencode kit's plan→build→review multi-agent workflow and its LLM-usage analytics work natively in the pi coding agent: pi agent definitions + subagent extension instead of `.opencode/agents`, prompt templates as role launchers, and a new `analyzing-pi-usage` skill that parses pi's JSONL session files instead of opencode's SQLite DB. Plan: `_agent_docs/plans/2026-08-15-opencode-kit-port-to-pi.md`.

**Work completed (2026-08-15 → 2026-08-17):**

- **Phase 0 — Scaffolding:** kit layout (`.pi/agents`, `.pi/prompts`, `.pi/skills`, `.pi/extensions`), `setup.sh` (agent/extension symlinks + settings snippet), `AGENTS.md`, session-summary template reference, `.gitignore`.
- **Phase 1 — Subagent extension + 9 agent definitions:** vendored pi's `subagent` example extension (isolated `pi -p --no-session` child runs, enforced read-only tools, per-agent `model:` override); ported all 9 agents. Verified: discovery, tool enforcement (write attempts rejected), model override (world-review on the agentworld model).
- **Phase 2 — Prompt templates (role launchers):** 8 thin templates in `.pi/prompts/` — 5 personas (`/plan-bdd`, `/build-tdd`, `/build-quick-work`, `/build-debug`, `/build-docs`) whose first line is the analytics `Role: <name>` marker, 3 delegation launchers (`/diff-review`, `/solid-review`, `/world-review`). Verified end-to-end in a scratch repo; the four probe sessions were kept as parser fixtures (`tests/fixtures/phase2-*.jsonl`).
- **Phase 3 — Skills port:** 7 near-drop-in skills + `running-diff-review` rewritten for the `subagent` tool. Found and fixed a source bug: `reviewing-agents-md`'s description contained an unquoted `: `, making its YAML frontmatter unparseable (pi silently skips such skills); also normalized CRLF in 12 copied files.
- **Phase 4 — `analyzing-pi-usage` skill:** new JSONL data layer (`pi_sessions.py`: entry tree, `Role:` marker attribution, fork dedup by first entry-ID, compaction usage, recursive subagent `details.results[]` extraction) over the opencode kit's report architecture (typed queries → merge → JSON/HTML; `charts.py`/`model_pricing.py` pure copies). New **Subagent Runs** report section. 80 pytest tests green; report verified on real data (420 KB HTML; subagent runs with correct agents/models/costs; LM Studio cache fallback + measured-cache paths). Bugs found/fixed along the way: `fmt_num` infinite loop, "Lines Added" card summing deletions, "sessions with changes" counting events, unbounded git ancestor walk + CWD-repo leakage, and an entry-point path-validation inconsistency.
- **Phase 5 — Integration validation + documentation:** end-to-end scratch-project exercise in `/tmp/pi-kit-phase5-test` (fresh repo, trusted via `-a`, zero local `.pi/`): `/plan-bdd` (54 min; world-review + planner subagent delegations; plan + summary), `/build-tdd` (62 min; 36 passing tests; summary), `/diff-review` (30 min; subagent found a real test-coverage gap — the 8 MiB streaming fixture aligns every chunk boundary to whitespace, so the word-carry branch never runs end-to-end), `/build-quick-work` (commit `aac42ad` with the `Co-Authored-By: LittleLight` trailer + summary). The report's role table matched the known operation sequence exactly: plan-bdd 2 sess / 411.6K, build-tdd 1 / 651.5K, build-quick-work 1 / 155.6K, main 3 / 60.3K (probes + diff-review launcher), diff-review 1 run / 47.1K, planner 2 runs / 33.1K, world-review 2 runs / 17.1K; 7 sessions, 1.38M tokens, all metrics non-zero. Global distribution verified (fresh project: all 9 skills + `subagent` tool discovered via `setup.sh` + global settings). This README; this timeline entry.

**Key findings:**

- Pi's session data is strictly richer than opencode's for this workflow: per-message `usage` with real `cacheRead`/`cacheWrite`/`reasoning`/`cost`, and subagent usage fully attributable from parent-session tool results (subagents run with `--no-session`, so the parent's `details.results[]` is the only record — the parser reads it recursively for nested delegation).
- LM Studio records zero cache tokens; the ported LAG-delta effective-token estimator covers that (flagged *simulated* in reports). Local models report `$0` actual cost with cloud-equivalent shown alongside.
- pi does not record per-session file changes, so "sessions with changes" is a git-date-join estimate — documented in SKILL.md and the report footer.
- Global distribution works with zero per-project setup: agents via `~/.pi/agent/agents` symlinks, extension via `~/.pi/agent/extensions`, skills/prompts via the global settings `skills`/`prompts` arrays. Gaps found and fixed during the exercise: (1) role agents referenced the session-summary template by project-relative path, which only resolves inside the kit repo — fixed to absolute kit paths; (2) `validate_summaries.sh` still validated the opencode-era summary schema (`session-NNN-summary.json`, quantitative fields) while the agents and template use `YYYY-MM-DD-XXX-<role>-<description>.json` with the richer token-centric template — validator now derives required fields from the template and globs `*.json`; (3) `analytics.py --impact` counted token events, not distinct sessions, for "sessions on commit days" (69 instead of 7) — same bug class as a Phase 4 fix in `merge.py`; counting is now a single shared `sessions_by_day()` helper with a regression test.
- Local-model runs are the pacing constraint: the four exercise steps took ~3.5 h total on qwen3.8-27b via LM Studio (plan-bdd 54 min incl. both subagent delegations, build-tdd 62 min, diff-review 30 min, build-quick-work ~15 min).
- Model IDs are recorded verbatim and the spelling varies by context (main sessions: settings-form `qwen/qwen3.8-27b`; subagent results: provider-qualified `lmstudio/qwen/qwen3.8-27b`) — the same physical model can appear as two rows in by-model tables; pricing normalizes via `pricing_model_id()`, display stays verbatim (documented in `references/pi-session-format.md`).

**Files:**

- Kit: `.pi/` (agents, prompts, skills, extensions), `setup.sh`, `README.md`, `AGENTS.md`
- Plan + per-phase results: `_agent_docs/plans/2026-08-15-opencode-kit-port-to-pi.md`
- Scratch exercise repo: `/tmp/pi-kit-phase5-test` (sessions under `~/.pi/agent/sessions/--private-tmp-pi-kit-phase5-test--/`)

**Next steps:** none — port complete. Ongoing maintenance notes: re-sync `charts.py`/`model_pricing.py` if opencode-side rates change; re-sync the vendored extension after pi updates (check `ExtensionAPI` drift).

---

## 2026-08-17 — Commit→Session Change Attribution (`Pi-Session` trailers)

**Purpose:** Replace the report's date-matched "sessions with changes" estimate with a measurement: agent commits carry a `Pi-Session: <uuid>` trailer naming the session that made the changes, and the analytics skill joins trailers to real sessions. Plan: `_agent_docs/plans/2026-08-17-commit-session-attribution.md`.

**Work completed:**

- **Convention** — `build-quick-work` (the kit's only committer; every other role is explicitly commit-free) now requires the trailer: `$PI_SESSION_ID` when the committing session made the changes, or — for the usual build→handoff flow — the newest *other* session in `$(dirname "$PI_SESSION_FILE")` (UUID = filename after the last `_`). One-line conventions added to the kit `AGENTS.md` and `AGENTS.md.template`. Trailer semantics: **work session**, not committing session — that keeps the tokens→code join honest in the flagship handoff flow.
- **Parser** — `git_commits.py` log format extended to `COMMIT:%h|%ad|%s%nMSG:%B%x1e` (full message, `\x1e` terminator on its own line); `\_parse_commits` gained a small state machine (message buffer until the terminator, then numstat) and a UUID-shaped `Pi-Session:` regex (last match wins, lowercased) → `commit['session_id']`. Marker lines are shape-validated (`sha|date|`) so a body line starting with `COMMIT:` cannot split a commit.
- **Report** — new `summarize_attribution()` (per-session commits/+adds/−dels) and `generate_report.join_change_attribution()` (joins to loaded sessions: dominant role + top-sessions-style title; unknown IDs still count, just unlabelled). `merge_datasets` gains `change_attribution`: "sessions with changes" = measured attributed sessions + date-join estimate over *unattributed* commits only (capped at total sessions); `sessions_with_changes_measured` exposed. HTML: new **Change Attribution** table in Detailed Data Tables, productivity card labelled `N measured` vs `estimate`, notes + footer explain the convention. `analytics.py --impact` prints attributed/unattributed split.
- **Tests** — 18 new (99 total, green): parser units (trailer present/absent/malformed/multiple/tab-in-message/binary numstat/marker-lookalike body line), `summarize_attribution` units, real temp-git-repo integration (`fetch` reads trailers; `fetch_daily` shape unchanged; date range), and e2e fetch→join→merge→render (known + unknown session IDs; no-trailer legacy path unchanged incl. HTML).
- **Docs** — SKILL.md Key Concepts + `--impact` flag line; this timeline entry.

**Key findings:**

- **`PI_SESSION_ID` / `PI_SESSION_FILE` are exposed to agents as env vars** (verified in a live process) — the keystone: an agent knows its own session UUID, and the session filename layout (`<timestamp>_<uuid>.jsonl` under the encoded-cwd dir) makes the handoff discovery rule deterministic.
- **Apple Git 2.50.1 parses date-only `--since` as an unreliable ~18:00–18:45Z instant of that date** (bisected: e.g. bare `--since=2026-03-03` excludes a 12:00Z commit on the same day; identical behavior under `TZ=UTC`, so it's a date-parsing quirk, not local-time). Explicit `…T00:00:00Z` bounds parse consistently. `\_run_git_log` now uses explicit UTC bounds **and** runs git with `TZ=UTC` so `--date=short` buckets commits by UTC day — which also fixes a latent mis-join: sessions are bucketed by UTC day, but commit dates were previously displayed/filtered in local time.
- **`str.splitlines()` splits on `\x1e`** (record separator is a Unicode line boundary) — the message terminator must be found by splitting on `\n` only, or the in-message state swallows the numstat block. Caught by the first test run.
- The estimate survives deliberately: repos without trailers (all existing history, non-kit projects) render exactly as before; the measured figure only appears when trailers exist.

**Files:**

- `script/queries/git_commits.py` (format, parser, `summarize_attribution`), `script/aggregator/merge.py`, `script/generate_report.py` (`join_change_attribution`), `script/analytics.py` (`--impact`), `script/render_consolidated_report.py` (table + labels + footer)
- `.pi/agents/build-quick-work.md`, `AGENTS.md`, `AGENTS.md.template`
- `tests/test_commit_attribution.py`, `SKILL.md`, plan + timeline entries

**Next steps:** (1) first real exercise — a `build-quick-work` handoff commit in a scratch repo, then confirm the report shows the measured attribution end-to-end; (2) optionally mirror the trailer convention into the workspace `CLAUDE.md` next to the `Co-Authored-By` rule; (3) if handoff discovery ever proves ambiguous (multiple interleaved sessions), consider an explicit `Pi-Work-Session:` override.
