# Port opencode-development-kit Agents and Skills to pi

**Date:** 2026-08-15
**Status:** Phase 1 complete (2026-08-16) — proceeding phase by phase
**Source project:** `/Users/austin/workspace/agent-ollama-projects/Experiments/opencode-development-kit`
**Target project:** `/Users/austin/workspace/agent-ollama-projects/Experiments/pi-development-kit`

---

## Overview

Rewrite the agents and skills from `opencode-development-kit` for use with the pi coding agent. The opencode kit provides a plan→build→review multi-agent workflow plus LLM-usage analytics built on opencode's SQLite database. The pi port uses pi's native equivalents:

- **Agents** → pi agent definitions (`.pi/agents/*.md`) consumed by the **subagent extension** (isolated `pi -p` subprocesses with enforced tool restrictions and per-agent model override), plus **prompt templates** (`.pi/prompts/*.md`) that make the "primary" roles work as the main-session persona.
- **Skills** → pi skills (`.pi/skills/`). Both harnesses implement the Agent Skills standard, so most skills are near drop-in; path and tool-name fixes are the bulk of the work.
- **Usage analytics** → new `analyzing-pi-usage` skill that parses pi's JSONL session files (`~/.pi/agent/sessions/`) instead of opencode's SQLite DB. Pi's data is strictly richer: per-message usage with real `cacheRead`/`cacheWrite`, per-turn cost, reasoning tokens, and (via subagent tool results) full per-subagent usage attribution.

**Agents in scope (9, per user):** `build-debug`, `build-docs`, `build-quick-work`, `build-tdd`, `diff-review`, `plan-bdd`, `planner`, `solid-review`, `world-review`.
**Skills in scope (9):** `analyzing-opencode-usage` (reworked as `analyzing-pi-usage`), `capturing-learnings`, `code-review`, `playwright-cli`, `reviewing-agents-md`, `running-diff-review`, `skill-extraction`, `skills-best-practice`, `writing-plans`.

---

## Current State Analysis

### opencode kit inventory

**Agents** (`.opencode/agents/`):

| Agent | mode | permission | model | Role |
|---|---|---|---|---|
| `build-tdd` | primary | edit: allow | — | TDD Red-Green-Refactor with SOLID guidance; owns tests + production code |
| `plan-bdd` | primary | edit: allow | — | BDD planning; delegates to `@world-review` + `@planner` subagents |
| `build-debug` | primary | edit: allow | — | Bug investigation, root cause, minimal fixes |
| `build-docs` | primary | edit: allow | — | Learnings, plans, skills, reviews |
| `build-quick-work` | primary | edit: allow | — | Commits, cleanup, housekeeping |
| `planner` | subagent | edit: deny | — | Read-only codebase exploration + implementation plans |
| `diff-review` | subagent | edit: deny | — | High-signal diff review (bugs + AGENTS.md violations) |
| `solid-review` | subagent | edit: deny | — | SOLID/separation-of-concerns review |
| `world-review` | subagent | edit: deny | `lmstudio/qwen-agentworld-35b-a3b` | Real-world UX/performance perspective |

Not ported (unused by user): `build-code`, `build-test`, `planner-g31`, `diff-review-g31`, `solid-review-g31`.

**Skills** (`.opencode/skills/`): `analyzing-opencode-usage` (large Python/SQL pipeline + pytest suite), `capturing-learnings`, `code-review`, `playwright-cli`, `reviewing-agents-md`, `running-diff-review`, `skill-extraction`, `skills-best-practice`, `writing-plans`.

**Conventions:** every agent writes a session-summary JSON to `[docs directory]/sessions/` from the template at `analyzing-opencode-usage/references/session-summary.json`; plans live in `[docs directory]/plans/` following the `writing-plans` template; learnings in `[docs directory]/learnings/`.

### pi equivalents (verified against installed pi docs and examples)

| opencode concept | pi mechanism | Evidence |
|---|---|---|
| Subagent (isolated context, read-only, own model) | **subagent extension**: agent defs in `~/.pi/agent/agents/*.md` or `.pi/agents/*.md`; `subagent` tool spawns `pi --mode json -p --no-session [--model X] [--tools ...]` | `examples/extensions/subagent/` (index.ts:300 builds the child args; agents.ts parses frontmatter `name`, `description`, `tools`, `model`) |
| `permission: edit: deny` | `tools: read, grep, find, ls` frontmatter → `--tools` on child process (real enforcement, unlike opencode's prompt-only deny) | subagent index.ts:307 |
| `model:` frontmatter | `model:` frontmatter → `--model` on child process | subagent index.ts:303 |
| `mode: primary` (session persona) | No equivalent; use **prompt templates** (`.pi/prompts/*.md`) that inject the role into the main session | docs/prompt-templates.md |
| Skills | `.pi/skills/` (project) or `~/.pi/agent/skills/` (global); Agent Skills standard — same `SKILL.md` frontmatter shape | docs/skills.md |
| Distribution to other projects | `skills` / `prompts` arrays in settings.json accept **files or directories** — reference the kit's paths, no per-project copying | docs/skills.md, docs/prompt-templates.md |
| Usage data source | JSONL per session under `~/.pi/agent/sessions/--<cwd>--/<ts>_<uuid>.jsonl`; assistant messages carry `usage: {input, output, cacheRead, cacheWrite, reasoning, totalTokens, cost{...}}` | docs/session-format.md; verified in live session files |
| Subagent usage attribution | Subagent runs use `--no-session` (no own session file), but the parent session's `toolResult.details.results[]` stores `agent`, full `usage` (input/output/cacheRead/cacheWrite/cost/contextTokens/turns), and `model` per subagent run | subagent index.ts:148–160 |

### Key Discoveries

- **Subagent runs are ephemeral but fully attributable.** `pi --mode json -p --no-session` (index.ts:300) means no per-subagent session file — but `SingleResult {agent, usage, model}` in the persisted tool result (index.ts:148–160) gives per-role, per-model token/cost attribution from the parent session's JSONL. The analytics skill gets role-level subagent usage for free.
- **Pi session usage is richer than opencode's.** Per-message `cacheRead`/`cacheWrite` are real values when the provider reports them (Anthropic/OpenAI/Google). With LM Studio they are 0 (verified in this repo's live sessions: `lmstudio/qwen/qwen3.8-27b`, all cache fields 0, input growing 1.9K→42K across turns) — so the opencode kit's LAG-delta cache estimation is still needed as a *fallback*, not the primary path.
- **`pi` has no built-in subagents** by design (docs/usage.md, Design Principles) — the bundled example extension is the intended mechanism, and it is production-shaped (streaming, parallel, chains, abort, usage display).
- **`reasoning` tokens are a first-class usage field** in pi sessions (observed in live JSONL) — a metric opencode's skill tracked as `tokens_reasoning`; keep it.
- **Role attribution for main-session work needs a convention.** pi sessions do not record which prompt template expanded a user message. Convention: every ported role template begins its body with a plain `Role: <agent-name>` marker line; the analytics skill attributes a main-session assistant turn to the most recent preceding `Role:` marker (default `main`).
- **`model_pricing.py` from the opencode kit is provider-agnostic** (per-model cloud-equivalent rates + `compute_cost`/`enrich_models_with_cost`) — copy it into the new skill unchanged.
- **The opencode kit drifts via per-project copies** (e.g. CollageMaker's `.opencode` has diverged from the kit's). The pi kit should use settings-array references as the primary distribution so there is one source of truth.
- **Pi project trust:** project-local `.pi/` resources (skills, prompts, extensions) load only after the project is trusted (`/trust`, `pi -a`, or `defaultProjectTrust`). The kit repo needs a one-time trust decision.
- **Session JSONL is a tree** (`id`/`parentId`), with compaction checkpoints and `parentSession` forks. For usage accounting, count **all** assistant/compaction/toolResult entries in a file (every entry executed and consumed tokens, even abandoned branches); document this choice.

Verified during Phase 0 (2026-08-15):

- **`/reload` is a built-in hot-reload command** — reloads keybindings, extensions, skills, prompts, themes, and context files in a running session; no restart needed. The one exception: trust decisions (`/trust` → `~/.pi/agent/trust.json`) are *not* hot-reloaded — restart pi for those. Non-interactive `pi -p` runs always start fresh, so `/reload` only matters for interactive iteration. `setup.sh` messages users accordingly.
- **`--no-tools` makes pi omit the skills section of the system prompt entirely** (verified: a known-good skill's sentinel was absent with `--no-tools`, present with tools enabled). Any model-context probe of skill loading must run with tools enabled.
- **Non-interactive skill-load probe (sentinel technique)**: create a temporary skill whose `description` contains a unique sentinel string, run `pi -p "Search your entire context for '<sentinel>'…" --no-session` (tools enabled), expect the model to quote it. Use a phrase unique to the skill *description*, not the skill *name* — `AGENTS.md` and other context files may also mention the name, which produces false positives (hit this with the `analyzing-pi-usage` stub, whose path is named in the kit's AGENTS.md).
- **`disable-model-invocation: true` verified working** — a skill with this field loads without warnings but its description is absent from the model's context (user can still use `/skill:name`). This is why the Phase 0 stub uses it: the WIP skill stays out of the model's toolset until Phase 4 lands.

Verified during Phase 1 (2026-08-16):

- **Subagents can nest.** Child `pi` processes load global extensions too, so a subagent with the default toolset (no `tools:` frontmatter) also gets the `subagent` tool and can delegate further (verified: main → `plan-bdd` → `planner`). Consequence for Phase 4: the parser must **recurse** into `details.results[i].messages[]` to find nested subagent `toolResult` entries — nested usage is NOT included in the parent result's `usage` (that counts only the intermediate agent's own LLM turns).
- **Session dir encoding uses the real path**: `/tmp/…` sessions land in `~/.pi/agent/sessions/--private-tmp-…--/` on macOS (`/tmp` → `/private/tmp`). The Phase 4 parser should resolve symlinks when mapping a cwd to its session dir.
- **Child LLM errors propagate cleanly**: if the child's model fails (e.g., LM Studio 400 "insufficient resources"), the tool returns `isError` with the error text, and the parent JSONL still records `results[i]` with `stopReason: "error"`, `exitCode: 0`, and the *intended* `model` — useful for attribution of failed runs.
- **world-review model override verified end-to-end** (2026-08-16, after the user loaded the model in LM Studio): `lmstudio/qwen-agentworld-35b-a3b` runs successfully and is recorded in the parent JSONL with full usage. Note: the model is large (~34.94 GB); if LM Studio's memory guardrail blocks it (400 error), the run fails cleanly but the intended `model` is still recorded (see fixture `2026-08-16T02-16-57`).

### Target layout

```
pi-development-kit/
├── AGENTS.md                          # kit conventions (Phase 0)
├── AGENTS.md.template                 # project bootstrap template, .pi/ paths (Phase 0)
├── .gitignore                         # ported from opencode kit (Phase 0)
├── setup.sh                           # global install: agent symlinks + extension + settings snippet (Phase 0)
├── .pi/
│   ├── settings.json                  # { "enableSkillCommands": true } (Phase 0)
│   ├── agents/                        # 9 agent definitions — single source of truth for role content (Phase 1)
│   │   ├── build-debug.md
│   │   ├── build-docs.md
│   │   ├── build-quick-work.md
│   │   ├── build-tdd.md
│   │   ├── diff-review.md
│   │   ├── plan-bdd.md
│   │   ├── planner.md
│   │   ├── solid-review.md
│   │   └── world-review.md
│   ├── prompts/                       # 8 thin launcher templates (Phase 2)
│   │   ├── build-debug.md             # persona launchers for the 5 primary roles
│   │   ├── build-docs.md
│   │   ├── build-quick-work.md
│   │   ├── build-tdd.md
│   │   ├── plan-bdd.md
│   │   ├── diff-review.md             # delegation launchers for the 4 subagent roles
│   │   ├── solid-review.md
│   │   └── world-review.md
│   ├── extensions/
│   │   └── subagent/                  # vendored subagent extension (index.ts + agents.ts) (Phase 1)
│   └── skills/
│       ├── analyzing-pi-usage/        # reworked analytics skill (skeleton in Phase 0, full in Phase 4)
│       │   ├── SKILL.md
│       │   ├── references/            # session-summary.json, activity-template.md (Phase 0), pi-session-format.md (Phase 4)
│       │   ├── script/                # python pipeline (Phase 4)
│       │   └── tests/                 # pytest (Phase 4)
│       ├── capturing-learnings/       # Phase 3
│       ├── code-review/               # Phase 3
│       ├── playwright-cli/            # Phase 3
│       ├── reviewing-agents-md/       # Phase 3
│       ├── running-diff-review/       # Phase 3 (rewritten for the subagent tool)
│       ├── skill-extraction/          # Phase 3
│       ├── skills-best-practice/      # Phase 3
│       └── writing-plans/             # Phase 3
└── _agent_docs/
    ├── plans/                         # this plan
    ├── sessions/                      # session summary JSONs
    └── learnings/
```

**Distribution model (recommended):** global, reference-based.
- Skills + prompts: `~/.pi/agent/settings.json` → `"skills": ["<kit>/.pi/skills"]`, `"prompts": ["<kit>/.pi/prompts"]` — every project gets them, single source of truth, zero copy drift.
- Agents: the subagent extension only discovers `~/.pi/agent/agents/` and the project's `.pi/agents/` — so `setup.sh` symlinks the kit's agent files into `~/.pi/agent/agents/`.
- Extension: `setup.sh` symlinks (or copies) the subagent extension into `~/.pi/agent/extensions/subagent/`.
- Alternative (not default): copy `.pi/` into a consumer project — rejected as primary because of the drift observed in the opencode kit.

---

## Desired End State

1. In any trusted project, pi exposes:
   - 9 skills (descriptions in the system prompt; `/skill:name` works via `enableSkillCommands`).
   - 8 prompt templates in `/` autocomplete: the 5 primary roles act as the main-session persona; the 4 review/planning roles delegate to isolated subagents.
   - A `subagent` tool that can run any of the 9 agent definitions, with enforced read-only tool sets where specified and `world-review` pinned to its model.
2. `/plan-bdd <feature>` runs the BDD planning workflow in-session, delegating to `world-review` and `planner` via the subagent tool (chain or sequential calls).
3. `/diff-review` (and the `running-diff-review` skill) delegates to the `diff-review` subagent with learnings enrichment, returns high-signal findings.
4. `analyzing-pi-usage` produces the same consolidated HTML/JSON report the opencode kit produces (summary cards, by-model, by-role, cross-tab, daily trend, cache estimate, cost analysis, git-based productivity, top sessions), sourced from pi's JSONL sessions, with per-role attribution for both main-session work and subagent runs.
5. `python3 -m pytest tests/` in `analyzing-pi-usage` passes, including contract tests for key alignment and fixtures of synthetic pi session JSONL.
6. A report generated for a real project (validation target: this repo's own `austin183.github.io` sessions or the first real pi project used) matches independent sums of the JSONL `usage` fields.

## What We're NOT Doing

- **Not porting** `build-code`, `build-test`, or the `-g31` model-variant agents (unused).
- **Not forking pi** or adding built-in subagent support — we use the bundled example extension as-is (vendored copy).
- **Not keeping opencode compatibility** in the analytics skill — `analyzing-pi-usage` is a fresh skill; the opencode kit keeps working for opencode sessions.
- **Not persisting subagent sessions** — the extension's `--no-session` behavior stays; attribution comes from parent-session tool results.
- **Not adding runtime schema validation** (pydantic etc.) to the analytics pipeline — contract tests are the pragmatic safeguard (same decision as the opencode kit's 2026-08-08 plan).
- **Not rewriting the two rendering paths into one** (JSON output vs HTML render) — alignment via contract tests only.
- **Not porting the opencode kit's `_agent_docs` history** (plans/sessions/timeline) into the pi kit — only the templates and conventions.
- **Not changing the session-summary JSON workflow** — it remains the human-curated companion to pi's raw JSONL (purpose, outcome, decisions, role), and is unchanged in shape so `validate_summaries.sh` logic carries over.

---

## Implementation Approach

Ordering principle: scaffolding first, then the subagent mechanism (agents + extension), then role templates, then skills, then the analytics skill (largest piece, depends on the `Role:` marker convention from Phase 2 being settled). Each phase is independently shippable.

Frontmatter mapping used throughout Phases 1–2:

| opencode frontmatter | pi agent frontmatter | Notes |
|---|---|---|
| `description: ...` | `description: ...` | keep |
| `name:` (implicit = filename) | `name: <agent>` | set explicitly |
| `mode: primary` / `mode: subagent` | *(removed)* | no equivalent; persona vs delegation is expressed via templates + tool |
| `permission: edit: allow` | *(no `tools` field)* | child process gets full tools |
| `permission: edit: deny` | `tools: read, grep, find, ls` | + `bash` for agents that need `git diff`/`git log` (planner, diff-review, solid-review, world-review), keeping the read-only-bash instruction in the body (pattern: subagent example `reviewer.md`) |
| `model: lmstudio/qwen-agentworld-35b-a3b` | `model: <verified id>` | verify exact id via `pi --list-models` before Phase 1 (LM Studio ids appear as `provider/model` in pi sessions) |

Body adaptations applied to all 9 agent files:

- `.opencode/...` path references → `.pi/...` (session-summary template path becomes `.pi/skills/analyzing-pi-usage/references/session-summary.json`).
- `@world-review` / `@planner` call sites → "use the `subagent` tool with agent `world-review` / `planner`".
- "What You Do NOT Do" lines referencing unported agents (`build-code`, `build-test`) → generalized (e.g. "do not implement new features beyond the requested fix").
- Session-summary section: keep the filename convention and template; add one line — "Record the pi session ID (from `/session`) in the summary for cross-reference with the raw JSONL."
- `[test command]` / `[e2e test command]` placeholders stay (resolved per project by AGENTS.md).

---

## Phase 0: Kit Scaffolding

### Overview

Stand up the repo skeleton so later phases have somewhere to land, and de-risk the `analyzing-pi-usage` forward references (agents reference the session-summary template path).

### Changes Required

1. **`AGENTS.md`** — modeled on `opencode-development-kit/AGENTS.md`: goal statement (reusable agents/skills for working on and measuring LLM usage with pi), pointer to `analyzing-pi-usage` skill, and the pi-specific deltas (session JSONL location, `/session` command, trust note).
2. **`AGENTS.md.template`** — rewrite from the opencode template: directory structure shows `.pi/` (agents, prompts, skills, extensions) and `[docs directory]`; session-summary path → `.pi/skills/analyzing-pi-usage/references/session-summary.json`; note pi reads `AGENTS.md`/`CLAUDE.md` natively and supports `APPEND_SYSTEM.md`/`SYSTEM.md`.
3. **`.gitignore`** — port from opencode kit; drop opencode-specific entries; keep Python/Node/OS/IDE/report patterns; add `.playwright-cli/`.
4. **`.pi/settings.json`** — `{ "enableSkillCommands": true }`.
5. **`_agent_docs/`** — `plans/`, `sessions/`, `learnings/` (this plan lands in `plans/`).
6. **`.pi/skills/analyzing-pi-usage/references/`** — create skeleton now with the two workflow templates (content unchanged from the opencode kit): `session-summary.json`, `activity-template.md`. `SKILL.md` stub with a "WIP — see plan 2026-08-15" note so skill discovery doesn't warn about a missing description. *(Implemented with `disable-model-invocation: true` — the WIP skill is hidden from the model and user-invocable only; see Key Discoveries.)*
7. **`setup.sh`** — global install script (see Phase 1 for the agent/extension steps; the script itself is written here so it can be exercised incrementally): symlink `.pi/agents/*.md` → `~/.pi/agent/agents/`; symlink or copy `.pi/extensions/subagent/` → `~/.pi/agent/extensions/subagent/`; print the `~/.pi/agent/settings.json` snippet (`skills`, `prompts` arrays pointing at the kit). *(Implements `--dry-run`; tells users to run `/reload` in a live session, with the trust-restart caveat.)*

### Success Criteria

- `pi` starts in this repo (after trust) and lists the stub skill without warnings.
- `bash setup.sh --dry-run` (prints intended actions) succeeds; actual run idempotent (re-run does not duplicate or fail).
- `validate_summaries.sh`-style structural check passes for the template file (fields match the opencode kit's template exactly).

---

## Phase 1: Subagent Extension + Agent Definitions *(complete 2026-08-16)*

### Overview

Vendor the subagent extension and port all 9 agent definitions to `.pi/agents/`, so the `subagent` tool can delegate to any role with enforced tool restrictions and model override.

### Changes Required

1. **Vendor the extension** — copy `index.ts` + `agents.ts` from `<pi-package>/examples/extensions/subagent/` into `.pi/extensions/subagent/`. Add a header comment to each file: "Vendored from pi examples/extensions/subagent (pi vX.Y.Z) — re-sync when pi updates."
2. **Port the 9 agent files** per the frontmatter mapping and body adaptations above. Per-agent specifics:
   - `build-tdd`, `build-debug`, `build-docs`, `build-quick-work`, `plan-bdd`: no `tools` field (full tools).
   - `planner`: `tools: read, grep, find, ls, bash` — keep the CRITICAL READ-ONLY block (it now has teeth via `--tools`, but bash is still allowed for `git status/log/diff`).
   - `diff-review`, `solid-review`: `tools: read, grep, find, ls, bash` (bash for `git diff`); add the read-only-bash instruction line (they currently rely on opencode's edit-deny alone).
   - `world-review`: `tools: read, grep, find, ls, bash`; `model:` set to the verified agentworld model id.
   - `plan-bdd` workflow: steps 2–3 ("Call `@world-review`… Call `@planner`…") → "Use the `subagent` tool with agent `world-review` (task: user-experience perspective on these requirements) … then with agent `planner` (task: BDD scenarios + technical approach, including the world-review output)".
3. **`setup.sh`** — wire in the agent + extension symlink steps.

### Verification

| # | Check | Method |
|---|---|---|
| 1.1 | Extension loads | start pi in kit → `subagent` tool present in system prompt/tools (during iterative development, `/reload` in a running session picks up extension changes without a restart; trust changes still need a restart) |
| 1.2 | All 9 agents discovered | ask the model to list available subagents, or inspect the tool's agent enumeration; all 9 names present with descriptions |
| 1.3 | Read-only enforcement | in a scratch dir with a junk file: run `subagent` with `diff-review` on an empty diff and instruct it (via task text) to create a file → child lacks `write`/`edit` tools; file not created |
| 1.4 | Model override | run `world-review` → tool output shows the agentworld model (and `pi --list-models` id matched in frontmatter) |
| 1.5 | Frontmatter validity | no parse warnings from agents.ts (bad frontmatter silently drops tools/model — verify `tools`/`model` fields by running 1.3/1.4) |

---

## Phase 2: Prompt Templates (Role Launchers)

### Overview

Give the 5 primary roles their opencode-style "session persona" via thin prompt templates, and give the 4 subagent roles one-command delegation launchers. Agent definitions remain the single source of truth for role content; templates are ~10-line launchers (no content duplication).

### Template Conventions

- Filename = command name (`/build-tdd`, `/plan-bdd`, `/diff-review`, …).
- Frontmatter: `description` (from the agent's), `argument-hint` where a target is expected (e.g. `"<feature or plan reference>"`).
- **First line of every primary-role template body is the analytics marker** `Role: <agent-name>` (plain text; the analytics skill greps user messages for `^Role: ([a-z-]+)` and attributes subsequent assistant turns to that role until the next marker; default role is `main`).
- Primary-role launcher body (pattern, using build-tdd):

  ```
  Role: build-tdd
  Work in the current session AS the build-tdd agent. First read the full role
  definition at <kit>/.pi/agents/build-tdd.md and follow it for this task.
  Do not commit files (build-quick-work's job). Task: ${@:-no explicit target — ask me}
  ```

  `<kit>` is the absolute kit path — resolve it at port time (the templates are global via settings, so they must not rely on a project-relative `.pi/`).
- Subagent-role launcher body (pattern, using diff-review):

  ```
  Delegate a high-signal review of the current uncommitted git diff to the
  diff-review subagent: use the `subagent` tool with agent `diff-review` and a
  task containing the user's request (${@:-review the current git diff}) plus any
  relevant learnings from [docs directory]/learnings/ (see the running-diff-review
  skill for the enrichment workflow). Discuss findings with me before changes.
  ```

### Changes Required

1. Create the 8 template files in `.pi/prompts/` (5 persona + 3 delegation; `planner` gets no template — it is invoked by `plan-bdd`'s workflow, and a standalone `/planner` launcher is added only if wanted later).
2. Update `setup.sh` settings snippet if not already present (prompts array).

### Verification

| # | Check | Method |
|---|---|---|
| 2.1 | All 8 templates appear in `/` autocomplete with descriptions | interactive check |
| 2.2 | `/build-tdd` expands with the `Role: build-tdd` first line and the task argument | type it, inspect expansion |
| 2.3 | Persona works: `/build-tdd add a trivial failing test + implementation` in a scratch repo completes a Red-Green-Refactor cycle and writes the session summary JSON with `agent_role: build-tdd` | scratch project |
| 2.4 | Delegation works: `/diff-review` on a scratch diff spawns a subagent run (streaming output shows agent name + model) and returns findings to the main session | scratch project |
| 2.5 | `/plan-bdd <small feature>` in a scratch project: main session runs the BDD workflow; subagent runs for `world-review` and `planner` visible; plan file lands in `[docs directory]/plans/` | scratch project |
| 2.6 | Session JSONL of 2.3 contains a user message starting with `Role: build-tdd` (marker convention holds for analytics) | grep the session file |

---

## Phase 3: Skills Port

### Overview

Port the 7 straightforward skills (near drop-in) and rewrite `running-diff-review` for the subagent tool.

### Per-Skill Changes

| Skill | Action | Specific changes |
|---|---|---|
| `capturing-learnings` | Copy | None (no harness-specific paths) |
| `code-review` | Copy | Optional wording: "run a subagent" → "use the `subagent` tool"; otherwise unchanged |
| `playwright-cli` | Copy | None |
| `reviewing-agents-md` | Copy | "opencode uses AGENTS.md" → "pi uses AGENTS.md (also CLAUDE.md; `.pi/SYSTEM.md` replaces the system prompt)" |
| `skill-extraction` | Copy | None (script + preamble workflow is harness-agnostic) |
| `skills-best-practice` | Copy | Frontmatter `allowed-tools: Bash, Read, Write, Edit, Glob, Grep` → `bash read write edit grep find ls` (pi tool names; field is experimental — mapped, not removed); body "Skills that Claude can discover" → "Skills the agent can discover" |
| `writing-plans` | Copy | None |
| `running-diff-review` | **Rewrite** | Step 4: "Call the `diff-review` or `diff-review-g31` subagent" → "Use the `subagent` tool with agent `diff-review` … include the learnings block in the task text"; drop all g31 references (not ported); keyword map + enrichment format unchanged |

All copies: verify no `.opencode/` path references remain (`rg '\.opencode' .pi/skills/` must return nothing).

### Verification

| # | Check | Method |
|---|---|---|
| 3.1 | All 8 ported skills + `analyzing-pi-usage` stub discoverable | pi startup header / `/skill:` autocomplete; no missing-description warnings. Non-interactive alternative: sentinel probe (Key Discoveries) — temporarily add a probe skill per skill-under-test, or spot-check one skill's unique description phrase; run with tools enabled (`--no-tools` omits the skills section) |
| 3.2 | Skill content loads via `/skill:writing-plans` etc. | invoke 2–3 spot checks |
| 3.3 | `running-diff-review` end-to-end | in a scratch repo with 1 learning file + a diff: `/skill:running-diff-review` → enriched task reaches the `diff-review` subagent (inspect the subagent's task text) |
| 3.4 | No opencode references | `rg -n "opencode|g31" .pi/skills/ .pi/prompts/` returns nothing (except intentional prose in `analyzing-pi-usage`'s plan references) |

---

## Phase 4: `analyzing-pi-usage` Skill

### Overview

Rework `analyzing-opencode-usage` into `analyzing-pi-usage`: same questions answered (tokens by model/role/day, cost, cache, productivity, top sessions), same report architecture (typed queries → merge → JSON/HTML), new data layer (JSONL parser instead of `opencode db` SQL).

### Architecture

```
.pi/skills/analyzing-pi-usage/
├── SKILL.md                          # rewritten: JSONL data source, workflows, gotchas
├── references/
│   ├── session-summary.json          # (Phase 0)
│   ├── activity-template.md          # (Phase 0)
│   └── pi-session-format.md          # NEW: entry types, tree/compaction/branch gotchas
├── script/
│   ├── analytics.sh                  # same CLI surface; python3 JSONL queries instead of opencode db
│   ├── generate_report.py            # consolidated report entry (port)
│   ├── render_consolidated_report.py # HTML renderer (port, mostly unchanged)
│   ├── charts.py                     # (port, mostly unchanged)
│   ├── model_pricing.py              # COPY unchanged from opencode kit (provider-agnostic)
│   ├── pi_sessions.py                # NEW: JSONL parser — header, entries, tree walk, message extraction
│   ├── queries/                      # rewritten over parsed session data (same module names where 1:1)
│   │   ├── summary.py  models.py  roles.py  cross_tab.py
│   │   ├── timeseries.py  top_sessions.py  cache_estimate.py
│   │   ├── git_commits.py            # port unchanged (git-based)
│   │   └── session_summaries.py      # join with _agent_docs/sessions/*.json (purpose/outcome)
│   ├── aggregator/merge.py           # port (TypedDicts; role rows instead of agent rows)
│   └── data_access/types.py          # port (SessionUsage, ModelRow, RoleRow, …)
└── tests/                            # pytest: parser, attribution, cache, pricing, contract, merge
```

### Data Layer Design (`pi_sessions.py`)

- **Parse:** one JSON object per line; index entries by `id`; keep `parentId` links.
- **Project filter:** header `cwd` substring match (opencode used directory substring; same UX via `--project`).
- **Date filter:** entry `timestamp` (ISO) → day; inclusive `--since`/`--until`.
- **Token sources (summed, each counted once):**
  1. `message` entries, role `assistant` → `usage` (input/output/cacheRead/cacheWrite/reasoning/cost).
  2. `compaction` entries → their `usage` (summary generation) when present.
  3. `message` entries, role `toolResult` → subagent nested work from `details.results[]` (each result's `usage`), attributed to that result's `agent`. Also read a top-level `usage` field on toolResult if pi populates it (verify against live sessions during implementation; prefer `details.results[]` as the source of truth).
- **Count all entries, including abandoned branches** — every entry executed and consumed tokens. Document in SKILL.md gotchas (mirrors the opencode kit's raw-vs-effective discipline).
- **Model attribution:** per-message `provider`/`model` (assistant) or `results[].model` (subagent).
- **Role attribution:**
  - Subagent runs → `details.results[].agent` (exact).
  - Main-session assistant turns → most recent preceding user-message `Role: <name>` marker (walk `parentId` chain from the assistant entry to find its immediately preceding user message; if none, or no marker, role = `main`).
- **Session metadata:** header `id`/`cwd`/`timestamp`; `session_info` name; `model_change` entries for the adoption timeline.

### Cache Estimation (ported logic, new data path)

- **Primary:** real `cacheRead`/`cacheWrite` when nonzero (providers that report caching — no estimation needed; report shows measured hit rate).
- **Fallback (per session file, when all cache fields are 0 — e.g. LM Studio):** port the LAG-delta method from `estimate_cache.py`: sort assistant turns by timestamp within the file; `effective_input[n] = max(input[n] − input[n−1], 0)`, first turn keeps full input. Disclaim as simulated (same wording as the opencode kit).
- **Effective tokens** = uncached input + output + reasoning (primary metric, unchanged).

### Cost Analysis

- Actual cost: sum of `usage.cost` (real for cloud providers; $0 for local models — annotate "actual cost: $0 (local via LM Studio)" as needed).
- Cloud-equivalent: reuse `model_pricing.py` `enrich_models_with_cost` on raw and cache-adjusted token counts (identical presentation to the opencode report).

### Productivity

Unchanged approach: match session dates to git commit dates (`git_commits.py` port); join `_agent_docs/sessions/*.json` summaries for purpose/outcome breakdowns.

### Report

Same consolidated HTML sections as the opencode kit (summary cards, by-model, by-role, cross-tab model×role, daily trend, cache, cost analysis, productivity, top sessions), plus one new collapsible section: **Subagent Runs** (count, by agent, tokens, cost — from tool results). JSON output shape mirrors the opencode report's keys where 1:1 so `render_consolidated_report.py`/`charts.py` port with minimal diff; `agent`-named keys become `role`.

### SKILL.md Rewrite

- Data source section: `~/.pi/agent/sessions/` layout, JSONL entry types, `Role:` marker convention, subagent `--no-session` + `details.results[]` attribution.
- Gotchas (ported + new): `cacheRead/cacheWrite` are 0 under LM Studio (use fallback estimator); branches double-count by design; `parentSession` forks share history (dedupe by entry `id` when a session is forked); `compaction` `retainedTail` duplicates post-compaction context (do not sum retainedTail usage — it's context, not new work); legacy `firstKeptEntryId` sessions still parse; session names from `session_info` entries.
- Keep: Quick Start, section/flag tables (same CLI surface), Direct-query section becomes "Direct JSONL queries" (python one-liners instead of SQL), Data Validation Checklist, Shell/JQ gotchas (keep; JSONL makes some jq patterns obsolete — update examples).

### Tests

- **Fixtures:** synthetic pi session JSONL files (hand-written: header, `Role:` user message, assistant turns with usage incl. cacheRead, model_change, toolResult with subagent `details`, compaction) — simpler than the opencode kit's SQLite seeding.
- **Ported:** model pricing tests, key-alignment contract test (merge output ↔ renderer/charts keys), project/date-range filtering, merge validation.
- **New:** parser tests (each entry type; malformed line tolerance), role attribution tests (marker found/absent/switched; subagent results), cache fallback tests (delta computation; real-cache path bypasses estimator), subagent usage extraction tests.

### Verification

| # | Check | Method |
|---|---|---|
| 4.1 | `python3 -m pytest tests/` green | in skill dir |
| 4.2 | `analytics.sh --summary` for a real project matches independent sum | `jq`/python one-liner over the same JSONL files, compared field-by-field |
| 4.3 | Report for a real project (e.g. `--project austin183.github.io`, the live sessions from this work) renders all sections with non-zero tables | open HTML |
| 4.4 | Subagent Runs section shows this repo's Phase 1–2 verification runs with correct agents/models | open HTML |
| 4.5 | Cache fallback fires under LM Studio data; real-cache path used when a provider-reported session is present | fixture test + live check |
| 4.6 | Cost section: local models show $0 actual + cloud-equivalent with cache savings | open HTML |
| 4.7 | `validate_summaries.sh` port validates existing `_agent_docs/sessions/` JSONs | run in kit |

---

## Phase 5: Integration Validation + Documentation

### Overview

End-to-end proof that the kit works as a unit, plus operator docs.

### Changes Required

1. **End-to-end scratch-project exercise** (fresh temp repo, trusted):
   - `/plan-bdd <tiny feature>` → plan with subagent delegation.
   - `/build-tdd <feature>` → implemented per plan; session summary written.
   - `/diff-review` → subagent findings.
   - `/build-quick-work` → commit with Co-Authored-By convention.
   - `analyzing-pi-usage` report over the scratch project → all metrics non-zero, role attribution correct (plan-bdd main turns, world-review/planner/diff-review subagent turns, build-tdd/build-quick-work main turns).
2. **Kit README** (or AGENTS.md section): install (trust + `setup.sh`), per-project usage, template/skill inventory, pointer to the analytics skill.
3. **`_agent_docs/project-timeline.md`** entry for the port (first entry in the pi kit's timeline).

### Success Criteria

- The scratch-project exercise completes without manual intervention beyond the initial prompts.
- Report role table matches the known sequence of operations in the exercise.
- A second user session in a *different* project picks up all skills/templates/agents with zero per-project setup (global distribution works).

---

## Testing Strategy

| Layer | Coverage | Where |
|---|---|---|
| Unit | JSONL parser, role attribution, cache estimator, pricing, merge | `analyzing-pi-usage/tests/` |
| Contract | key alignment merge ↔ renderer ↔ charts (ported pattern) | `tests/test_key_alignment.py` |
| Component | subagent discovery, tool enforcement, model override (Phase 1 checks 1.1–1.5) | manual/scripted |
| Integration | template launchers (Phase 2 checks), running-diff-review enrichment (3.3), full report vs independent sum (4.2–4.4) | scratch projects |
| End-to-end | Phase 5 exercise | scratch repo |

Priority: P0 = parser/attribution/cache correctness (4.1–4.2, 4.5) and subagent enforcement (1.3–1.4); P1 = contract tests + template launchers (2.2–2.6, 3.3); P2 = report polish sections.

## Performance Considerations

- JSONL parsing is O(lines); session files for this repo's projects are tens of KB to low MB — trivial. No DB, no subprocess-per-query (the opencode kit shelled out to `opencode db` per query; the pi port parses once per run and serves all query modules from the in-memory structure — strictly faster).
- Vendored extension adds one extension load at startup (negligible).
- Global skills/prompts add name+description lines to the system prompt (8 skills + 8 templates ≈ modest tokens; unchanged in kind from the opencode kit).

## Migration Notes

- The opencode kit remains untouched and continues to serve opencode work; the two kits coexist.
- No consumer-project migration is required for the first version — distribution is opt-in via `setup.sh`.
- `model_pricing.py` rates are copied as-is; if opencode-side rates are later updated, re-sync manually (note in the file header).
- The `Role:` marker convention is additive: sessions without markers simply attribute to `main`.
- Vendored subagent extension may lag pi's bundled example after pi updates — re-sync via the header comment's instruction (check for API drift in `ExtensionAPI` usage on re-sync).

## References

- Source kit: `agent-ollama-projects/Experiments/opencode-development-kit/` (AGENTS.md, `.opencode/agents/*.md`, `.opencode/skills/*`, `_agent_docs/plans/2026-08-08-analytics-skill-remaining-fixes.md` for the contract-test pattern)
- pi docs (installed package `docs/`): `skills.md` (locations, frontmatter, settings arrays), `prompt-templates.md` (format, args, `$@`), `extensions.md` (locations, `pi.registerTool`), `session-format.md` (JSONL entry types, Usage shape, SessionManager API), `sessions.md`, `usage.md` (design principles: no built-in subagents)
- pi examples: `examples/extensions/subagent/` (README.md — install + security model; agents.ts:34–80 — frontmatter parsing; index.ts:148–160 — `SingleResult {agent, usage, model}`; index.ts:300–307 — child process args `--no-session --model --tools`)
- Live pi session data (verified during planning): `~/.pi/agent/sessions/--Users-austin-workspace-austin183.github.io--/*.jsonl` — per-message `usage` incl. `cacheRead`/`cacheWrite`/`reasoning`/`cost`; all-zero cache under `lmstudio/qwen/qwen3.8-27b`
- Kit conventions for this plan's own format: `writing-plans` skill template (as used by the opencode kit's plans)
