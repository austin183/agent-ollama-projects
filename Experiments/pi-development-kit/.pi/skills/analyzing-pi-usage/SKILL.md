---
name: analyzing-pi-usage
description: Analyze pi agent token usage, cost, cache behavior, and git productivity from pi's JSONL session files. WIP — analysis scripts not yet ported (Phase 4 of _agent_docs/plans/2026-08-15-opencode-kit-port-to-pi.md). Do not run analysis until the script/ directory exists.
disable-model-invocation: true
---

# Analyzing pi Usage

**Status: WIP.** This skill is being reworked from the opencode kit's
`analyzing-opencode-usage` for pi's JSONL session format. The analysis
pipeline (JSONL parser, role attribution, cache estimation, cost analysis,
HTML/JSON report) lands in `script/` during Phase 4 of the port plan:

`_agent_docs/plans/2026-08-15-opencode-kit-port-to-pi.md`

Until then, this skill only provides the workflow reference templates used
by the rest of the kit:

- `references/session-summary.json` — session summary template. Every agent
  writes one of these to `[docs directory]/sessions/` after each session
  (purpose, outcome, decisions, role, pi session ID).
- `references/activity-template.md` — daily activity summary template used
  by the report workflow.

Do not attempt to run analysis until `script/` and `tests/` are populated.
