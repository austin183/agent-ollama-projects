# Goal
Have a reusable set of agents and skills to work on and measure LLM usage on software projects, built for the pi coding agent.

## LLM Usage Measuring Goals
To work the `.pi/skills/analyzing-pi-usage` skill and its scripts into a reliable and meaningful way to analyze LLM usage from pi's JSONL session files.

## pi-Specific Notes

- **Session data**: pi stores sessions as JSONL under `~/.pi/agent/sessions/--<cwd>--/<timestamp>_<id>.jsonl`. Every assistant message carries a `usage` object (input, output, cacheRead, cacheWrite, reasoning, cost). There is no database — the analytics skill parses these files directly.
- **Local-model cache**: providers that do not report cache tokens (e.g. LM Studio) record zero `cacheRead`/`cacheWrite`; the analytics skill falls back to delta-based effective-token estimation in that case.
- **Subagent runs**: the `subagent` tool (`.pi/extensions/subagent/`, vendored from pi's examples) runs isolated `pi -p` processes with `--no-session`; their usage is attributed from the parent session's tool results (`details.results[]`).
- **Project trust**: pi loads project-local `.pi/` resources (skills, prompts, extensions) only after the project is trusted (`/trust`, `pi -a`, or `defaultProjectTrust`).
- **Role markers**: prompt templates from this kit begin with a `Role: <agent>` line so the analytics skill can attribute main-session turns to roles.
- **Commit attribution**: agent commits end with a `Pi-Session: <session-uuid>` trailer naming the session that made the changes (convention in `build-quick-work`), so the analytics skill measures change attribution instead of estimating it by date.
