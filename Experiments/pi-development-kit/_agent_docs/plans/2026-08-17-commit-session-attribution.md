# Commit→Session Change Attribution Plan

## Overview

Turn the report's "sessions with changes" metric from a **date-join estimate** into a **measurement**. pi does not record per-session file changes, so today the report guesses: any session active on a day that has commits counts. This plan adds a commit-trailer convention (`Pi-Session: <uuid>`) that agents include when committing, so each commit is attributed to the session that made its changes. The parser reads the trailer, the report joins commits to real sessions, and the estimate survives only as a clearly-labeled fallback for unattributed commits.

## Current State Analysis

- `script/queries/git_commits.py` runs `git log --numstat --pretty=format:COMMIT:%h|%ad|%s` and parses only subject + numstat. No message body, no trailers (`_run_git_log`, `_parse_commits`).
- `script/aggregator/merge.py` computes `sessions_with_changes` by joining session days to commit days (`merge_datasets`, "Compute sessions_with_changes" block) — the estimate.
- `script/generate_report.py` loads sessions and git data separately; nothing joins them.
- `PI_SESSION_ID` / `PI_SESSION_FILE` are **exposed to agents as env vars** (verified in a live pi process) — an agent knows its own session UUID, and `dirname $PI_SESSION_FILE` is the project's session directory (filename = `<timestamp>_<uuid>.jsonl`).
- Session header `id` (UUID) is the parser's session key (`pi_sessions.py:92`).
- Commits in the wild already carry a trailer (`Co-Authored-By: LittleLight <noreply@traveler.dstny>`) per the workspace CLAUDE.md convention — the trailer format is already native here.
- `build-quick-work` is the designated committer; `build-tdd` explicitly does not commit — so in the kit's flagship flow the **work session and committing session differ**.

### Key Discoveries

- The keystone is `PI_SESSION_ID`: agent-side convention is one line, no discovery of session files needed for the self-commit case.
- `%B` in `git log --pretty` always ends with a newline, so a `%x1e` record separator appended to the format lands on its own line — a clean, unambiguous message terminator that cannot appear in a commit message.
- A body line could theoretically start with `COMMIT:` — the new marker check must validate the sha|date shape, not just the prefix.

## Desired End State

1. **Convention**: agent commits end with a `Pi-Session: <session-uuid>` trailer identifying the session that made the changes in that commit (work session; discovery rule for handoff commits documented in `build-quick-work.md` and the AGENTS.md files).
2. **Parser**: `git_commits.fetch()` returns each commit with `session_id` (UUID from trailer, validated, last occurrence wins) or `None`.
3. **Report**:
   - `change_attribution` block: per-session commits/+adds/−dels joined to session role/title; `attributed_commits` / `unattributed_commits` / `sessions_measured`.
   - `sessions_with_changes` = measured (distinct attributed sessions) + date-join estimate over *unattributed* commits only, capped at total sessions; labeled measured-vs-estimated in output and HTML.
   - `analytics.py --impact` prints the same split.
4. **Backward compatible**: repos without trailers behave exactly as today (pure estimate, no new UI beyond "0 of N attributed").
5. **Verified**: unit + integration (real temp git repo) + e2e report tests; full suite green; real-data report run shows attribution for trailer-bearing commits.

### Key Discoveries (cont.)

- `merge.py` already receives `git_commits` (now trailer-enriched) — the measured count can be computed there; only the role/title join needs the session objects, which live in `generate_report.py`.

## What We're NOT Doing

- No backfilling of historical commits (trailers are forward-only; old commits stay estimated).
- No commit-time role inference (a session's *dominant* role is the display label; per-commit role-at-time would need commit timestamps + event-time lookups — later).
- No subagent commit attribution (subagents are read-only-enforced and don't commit).
- No changes to pi itself or the vendored subagent extension.
- Not editing the workspace-level `CLAUDE.md` (user file) — the convention goes in the kit's `AGENTS.md`, the template, and the committer agent; the user can mirror it into CLAUDE.md if wanted.

## Implementation Approach

Single trailer, minimal parse surface: one regex over the commit message, one new field on the commit dict, one aggregation function, one new key in the merged report. Every layer degrades to today's behavior when the trailer is absent.

## Phase 1: Trailer parsing in `git_commits.py`

### Changes Required:

#### 1. Git log format + parser
**File**: `.pi/skills/analyzing-pi-usage/script/queries/git_commits.py`
**Changes**:
- `--pretty=format:COMMIT:%h|%ad|%s%nMSG:%B%x1e` (full message block, `\x1e` terminator on its own line).
- `_parse_commits`: small state machine — `COMMIT:` (validated as `sha|date|` shape) starts a commit; `MSG:` opens the message buffer; lines until the `\x1e`-terminated line are message; then numstat as today. Message lines containing tabs are safe (consumed while in-message).
- `_PI_SESSION_RE = ^Pi-Session:\s*<uuid-shape>\s*$` (MULTILINE); last match wins; stored lowercase in `commit['session_id']`, else `None`.

### Success Criteria:

#### Automated Verification:
- [ ] `_parse_commits` unit tests: trailer present / absent / malformed (non-UUID) / multiple (last wins) / tab in message / binary numstat after message / body line starting with `COMMIT:` not misparsed.
- [ ] Integration test: real temp git repo, commits with and without trailer, `fetch(project=tmp)` returns correct `session_id`s.
- [ ] `fetch_daily` output unchanged in shape (regression).

## Phase 2: Aggregation + report wiring

### Changes Required:

#### 1. `summarize_attribution(commits)`
**File**: `script/queries/git_commits.py`
**Changes**: pure function → `{'attributed_commits', 'unattributed_commits', 'sessions_measured', 'by_session': {sid: {commits, adds, dels, test_adds, test_dels}}}`.

#### 2. Session join
**File**: `script/generate_report.py`
**Changes**: index loaded sessions by `session_id`; for each attributed session add `role` (dominant event role) and `title` (`name` or `first_user_text` or short id, same rule as `top_sessions.py:44`); pass `change_attribution` into `merge_datasets`.

#### 3. Merge
**File**: `script/aggregator/merge.py`
**Changes**: accept `change_attribution`; when `attributed_commits > 0`, recompute `sessions_with_changes` = `sessions_measured` + date-join estimate over unattributed-commit days only (capped at `total_sessions`); expose `sessions_with_changes_measured`; emit top-level `change_attribution` in the merged output.

#### 4. `--impact` CLI
**File**: `script/analytics.py`
**Changes**: `show_impact` prints attributed/unattributed commit counts and the measured sessions figure alongside the existing estimate.

#### 5. HTML report
**File**: `script/render_consolidated_report.py`
**Changes**: "Change Attribution" block in the code-impact area — per-session table (role, title, commits, +adds, −dels) plus coverage line ("N of M commits attributed"); productivity card label notes measured vs estimated; footer states the convention.

### Success Criteria:

#### Automated Verification:
- [ ] `summarize_attribution` unit tests (empty, all-attributed, mixed, duplicate sessions).
- [ ] E2E: report JSON on a temp project (fixture session IDs + trailer commits) carries `change_attribution` with the right join (role/title present for known IDs, absent for unknown).
- [ ] No-trailer project: report JSON byte-identical to pre-change output for the affected keys (pure-estimate path unchanged).
- [ ] Full pytest suite green.

## Phase 3: Agent-side convention

### Changes Required:

#### 1. `build-quick-work.md`
**File**: `.pi/agents/build-quick-work.md`
**Changes**: new "Commit Attribution" convention — every commit includes `Pi-Session: <uuid>` = the session that made the changes: `$PI_SESSION_ID` when this session made them; for handoff commits, newest other file in `$(dirname "$PI_SESSION_FILE")` (uuid = filename after last `_`). Trailer as a final `Key: value` paragraph.

#### 2. AGENTS.md files
**Files**: `AGENTS.md`, `AGENTS.md.template`
**Changes**: one-line convention next to the commit-signing rule: agent commits carry a `Pi-Session: <session-uuid>` trailer (details in the committer agent).

### Success Criteria:

#### Automated Verification:
- [ ] `grep -c "Pi-Session" .pi/agents/build-quick-work.md AGENTS.md AGENTS.md.template` ≥ 1 each.

#### Manual Verification:
- [ ] A `build-quick-work` run in a scratch repo produces a commit whose trailer names the work session (next kit exercise; not blocking).

## Phase 4: Documentation

### Changes Required:
- `SKILL.md`: "Change attribution" subsection under Key Concepts (convention + measured/estimated semantics); `--impact` flag note.
- `references/`: convention documented in SKILL.md (no new reference file — one concept, one home).
- `_agent_docs/project-timeline.md`: new entry for this work.

### Success Criteria:

#### Automated Verification:
- [ ] `grep -q "Pi-Session" SKILL.md`.

## Testing Strategy

### Unit Tests (new `tests/test_commit_attribution.py`):
- `_parse_commits` scenarios above (P0).
- `summarize_attribution` scenarios (P1).

### Integration:
- Temp git repo fixture (P0): `git init`, committer identity, 3 commits (trailer / no trailer / trailer with unknown UUID), assert `fetch()` results.

### E2E:
- Extend the report e2e pattern: temp project with sessions root containing a synthetic session whose ID matches a trailer → `generate_report.py --json` → `change_attribution` correct, `sessions_with_changes` measured.

### Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | parser + temp-repo integration + e2e attribution | Core — without these the feature doesn't work |
| **P1** | summarize unit, no-trailer regression, full suite | Correctness of the mixed measured/estimated path |
| **P2** | real-data report run | Confidence on live `~/.pi` data |

## Migration Notes

- Forward-only: existing commits remain unattributed; reports on old projects are unchanged (0 attributed → legacy estimate path).
- `change_attribution` is a new report key; older report consumers ignore it.

## References

- `references/pi-session-format.md` (session IDs, file layout)
- `_agent_docs/project-timeline.md` 2026-08-17 entry (Phase 5 exercise: build→commit handoff)
- `queries/utils.py::sessions_by_day` (the estimate being replaced)
