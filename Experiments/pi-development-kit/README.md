# pi-development-kit

A reusable set of agents, prompt templates, skills, and an extension for the
[pi coding agent](https://pi.dev), built around a **plan → build → review**
multi-agent workflow plus **LLM-usage analytics** driven by pi's native JSONL
session files.

Ported from `opencode-development-kit` — see
`_agent_docs/plans/2026-08-15-opencode-kit-port-to-pi.md` for the full plan
and per-phase results.

## What's inside

| Resource | Location | Notes |
|---|---|---|
| 9 agent definitions | `.pi/agents/*.md` | Single source of truth for each role |
| 8 prompt templates | `.pi/prompts/*.md` | Thin role launchers (`Role:` marker + pointer to the agent definition) |
| 9 skills | `.pi/skills/` | 8 ported from the opencode kit + the new `analyzing-pi-usage` |
| Subagent extension | `.pi/extensions/subagent/` | Vendored from pi's `examples/extensions/subagent/`; provides the `subagent` tool |

### Roles

| Role | Launcher | Kind | Model | Purpose |
|---|---|---|---|---|
| `plan-bdd` | `/plan-bdd` | persona (main session) | default | BDD behavior spec + phased technical plan; delegates to `world-review` + `planner` |
| `build-tdd` | `/build-tdd` | persona | default | TDD Red-Green-Refactor implementation of a plan |
| `build-quick-work` | `/build-quick-work` | persona | default | Commits, cleanup, housekeeping |
| `build-debug` | `/build-debug` | persona | default | Bug investigation, root cause, fixes |
| `build-docs` | `/build-docs` | persona | default | Learnings, plans, skills, review docs |
| `diff-review` | `/diff-review` | subagent | default | High-signal review of the uncommitted git diff |
| `solid-review` | `/solid-review` | subagent | default | SOLID / best-practices review |
| `world-review` | `/world-review` | subagent | `lmstudio/qwen-agentworld-35b-a3b` | Real-world UX / systems-perspective review |
| `planner` | — (no launcher) | subagent | default | Codebase exploration + BDD implementation design (invoked by `plan-bdd`) |

Personas work **in the main session** (the template's first line,
`Role: <name>`, is what the analytics skill uses to attribute those turns).
Subagents run as isolated `pi -p --no-session` child processes with
enforced read-only tools; their usage is attributed from the parent session's
tool results.

## Install

One-time, from the kit repo:

```bash
cd /path/to/pi-development-kit
pi -a                 # or /trust in an interactive session — the repo must be trusted
bash setup.sh         # --dry-run to preview
```

`setup.sh`:

1. Symlinks `.pi/agents/*.md` into `~/.pi/agent/agents/` (the subagent
   extension discovers agents there; it does not support settings-array
   agent references).
2. Symlinks the vendored extension into `~/.pi/agent/extensions/subagent/`.
3. Prints the `~/.pi/agent/settings.json` snippet — **merge it yourself**
   (your global settings stay yours):

   ```json
   {
     "skills":  ["/path/to/pi-development-kit/.pi/skills"],
     "prompts": ["/path/to/pi-development-kit/.pi/prompts"],
     "enableSkillCommands": true
   }
   ```

In a running pi session, `/reload` picks up extensions, skills, prompts, and
context files. **Trust changes are not hot-reloaded** — restart pi for those.

## Per-project usage

Nothing to install per project. In each project's `AGENTS.md`, define:

- The **docs directory** convention (e.g. `_agent_docs`) — roles read
  learnings/plans/timeline from `[docs directory]/` and write plans and
  session summaries there.
- Project conventions the roles should inherit (language, test runner,
  commit style). The commit trailer convention (e.g.
  `Co-Authored-By: …`) belongs here too — `build-quick-work` follows it.

Typical feature workflow:

```
/plan-bdd <feature>          # BDD spec + plan in [docs directory]/plans/ (delegates to subagents)
/build-tdd <plan reference>  # implements per plan; writes session summary
/diff-review                 # subagent review of the uncommitted diff
/build-quick-work commit …   # commits per the project's convention; writes session summary
```

Every role agent ends by writing a session summary to
`[docs directory]/sessions/` (`YYYY-MM-DD-XXX-<role>-<description>.json`,
all fields from `analyzing-pi-usage/references/session-summary.json`).
Validate them with:

```bash
bash .pi/skills/analyzing-pi-usage/script/validate_summaries.sh --root <project>   # add --strict in CI
```

## Analyzing LLM usage

The `analyzing-pi-usage` skill parses `~/.pi/agent/sessions/` JSONL directly
(no database). Quick start:

```bash
cd .pi/skills/analyzing-pi-usage/script
./analytics.sh --summary --project <path>                 # token summary for a project
./analytics.sh --project <path> --roles --subagents       # per-role + subagent attribution
./analytics.sh --project <path> --impact                  # git-commit productivity (add --since/--until/--days)
python3 generate_report.py --project <path> --output /tmp/report.html   # consolidated HTML report
```

The full flag/section table and the "Direct JSONL queries" cookbook are in
`.pi/skills/analyzing-pi-usage/SKILL.md`.

Known data caveats (also in SKILL.md gotchas):

- Providers that don't report cache tokens (e.g. LM Studio) record zero
  `cacheRead`/`cacheWrite`; the skill falls back to a delta-based
  effective-token estimate, flagged as *simulated* in reports.
- Abandoned branch entries are counted by design (they consumed tokens).
- "Sessions with changes" is a git-date-join **estimate** — pi does not
  record per-session file changes.
- Subagent runs are attributed from the parent session's tool results
  (`details.results[]`), including nested delegation.

## Development

- Parser/query/report tests:
  `python3 -m pytest .pi/skills/analyzing-pi-usage/tests/` (80 tests;
  fixtures in `tests/fixtures/` are real pi session files from the kit's
  own verification runs).
- `charts.py` and `model_pricing.py` are pure copies from the opencode kit —
  re-sync manually if opencode-side rates change.
- The vendored extension may lag pi's bundled example after pi updates —
  re-sync per the header comment (check `ExtensionAPI` usage for drift).
