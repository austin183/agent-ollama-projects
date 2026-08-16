# Phase 1 Probe Fixtures

Real pi session JSONL files captured during Phase 1 verification
(2026-08-16) in a scratch project (`/tmp/pi-kit-phase1-test`). Each file
is one parent session that invoked the `subagent` tool. They are the
reference shapes for the Phase 4 parser, especially:

| File (prefix) | Contents |
|---|---|
| `2026-08-16T02-16-57` | `world-review` run that **failed at model load** (LM Studio 400, memory guardrail). Shows `stopReason: "error"`, `exitCode: 0`, intended `model` still recorded, zero usage. |
| `2026-08-16T02-21-04` | Successful single `planner` run on the inherited model. Shows full `usage` (input/output/contextTokens/turns) in `toolResult.details.results[0]`. |
| `2026-08-16T02-24-02` | **Nested** run: main → `plan-bdd` → `planner`. Top-level `results[0]` is `plan-bdd` (its own turns only); the nested `planner` result lives inside `results[0].messages[].details.results[]`. The Phase 4 parser must recurse into `messages` to attribute nested subagents. |

Parser notes (from these fixtures):

- Subagent attribution entries are `type: "message"` entries whose
  `message.role` is `"toolResult"` and whose `message.details.results` is
  a non-empty array; each result has `agent`, `agentSource`, `task`,
  `exitCode`, `messages`, `stderr`, `usage`, `model`, `stopReason`.
- `results[i].usage` counts only that agent's **own** LLM turns.
- Nested subagent results are found by walking `results[i].messages[]`
  for toolResult messages carrying their own `details.results`.
- `model` is the full `provider/model-id` string (e.g.
  `lmstudio/qwen/qwen3.8-27b`); for inherited models it is filled from
  the dispatching session's active model.
