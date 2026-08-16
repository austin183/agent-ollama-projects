# Subagent Extension (vendored)

Vendored from `@earendil-works/pi-coding-agent` **v0.84.2**,
`examples/extensions/subagent/` (files: `index.ts`, `agents.ts`).

The code is unmodified apart from the provenance header comment at the top
of each file. If a local change is ever strictly necessary, record why in
`_agent_docs/learnings/` and prefer an upstream fix.

## Re-sync on pi updates

```bash
PKG=$(npm root -g)/@earendil-works/pi-coding-agent
cp "$PKG/examples/extensions/subagent/index.ts" .pi/extensions/subagent/index.ts
cp "$PKG/examples/extensions/subagent/agents.ts" .pi/extensions/subagent/agents.ts
# then restore the provenance header comment at the top of each file
```

`setup.sh` symlinks these `.ts` files into `~/.pi/agent/extensions/subagent/`,
so a re-sync is picked up by an existing pi session with `/reload`.

## What it provides

A `subagent` tool (single / parallel / chain modes) that spawns isolated
`pi --mode json -p --no-session` child processes. Agent definitions are
markdown files with YAML frontmatter (`name`, `description` required;
`tools`, `model` optional):

- **User-level**: `~/.pi/agent/agents/*.md` — always loaded (default scope)
- **Project-level**: nearest `.pi/agents/` at or above cwd — only with
  `agentScope: "project"` or `"both"` (interactive sessions confirm before
  running project-local agents; non-interactive runs do not prompt)

Each run's `agent`, full `usage` (input/output/cacheRead/cacheWrite/cost/
contextTokens/turns), and `model` are recorded in the parent session's
`toolResult.details.results[]` — the source of truth for subagent
attribution in the `analyzing-pi-usage` skill.
