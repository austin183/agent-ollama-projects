#!/usr/bin/env bash
# setup.sh — install pi-development-kit resources into pi globally.
#
# What it does:
#   1. Symlinks .pi/agents/*.md into ~/.pi/agent/agents/
#      (the subagent extension discovers agents from there; the extension
#      does not support settings-array references for agents)
#   2. Installs the vendored subagent extension into ~/.pi/agent/extensions/subagent/
#      (one symlink per file, so re-syncing the kit picks up changes)
#   3. Prints the ~/.pi/agent/settings.json snippet for skills + prompts
#      (printed, not merged — your global settings stay yours to edit)
#
# A running pi session picks up the new resources with /reload
# (extensions, skills, prompts, themes, context files). Trust changes
# are the exception: /trust is not hot-reloaded — restart pi for those.
#
# Usage:
#   bash setup.sh --dry-run   # print intended actions without executing
#   bash setup.sh             # execute (idempotent: safe to re-run)
#
# Notes:
#   - Requires project trust for this kit repo before pi loads local .pi/
#     resources in this repo itself (/trust or `pi -a`).
#   - Existing symlinks are replaced; existing *files* at the destination
#     are overwritten by the symlink — back up anything you put there by hand.
#   - Set PI_AGENT_DIR to install into a non-default agent directory.

set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_AGENT_DIR="${PI_AGENT_DIR:-$HOME/.pi/agent}"
DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

log() { printf '%s\n' "$*"; }
run() {
  if (( DRY_RUN )); then
    log "  [dry-run] $*"
  else
    log "  $*"
    "$@"
  fi
}

log "pi-development-kit setup"
log "  kit:        $KIT_DIR"
log "  agent dir:  $PI_AGENT_DIR"
(( DRY_RUN )) && log "  mode:       dry-run"
log ""

# 1. Agent definitions (Phase 1) -----------------------------------------
AGENTS_SRC="$KIT_DIR/.pi/agents"
AGENTS_DST="$PI_AGENT_DIR/agents"
if [[ -d "$AGENTS_SRC" ]]; then
  log "Agent definitions:"
  run mkdir -p "$AGENTS_DST"
  for f in "$AGENTS_SRC"/*.md; do
    [[ -e "$f" ]] || continue
    run ln -sf "$f" "$AGENTS_DST/$(basename "$f")"
  done
else
  log "  (skip) agent definitions not present yet (Phase 1): $AGENTS_SRC"
fi

# 2. Subagent extension (Phase 1) -----------------------------------------
EXT_SRC="$KIT_DIR/.pi/extensions/subagent"
EXT_DST="$PI_AGENT_DIR/extensions/subagent"
if [[ -d "$EXT_SRC" ]]; then
  log "Subagent extension:"
  run mkdir -p "$EXT_DST"
  for f in "$EXT_SRC"/*.ts; do
    [[ -e "$f" ]] || continue
    run ln -sf "$f" "$EXT_DST/$(basename "$f")"
  done
else
  log "  (skip) subagent extension not vendored yet (Phase 1): $EXT_SRC"
fi

# 3. Settings snippet -------------------------------------------------------
log ""
log "Add to $PI_AGENT_DIR/settings.json (merge with existing settings):"
log ""
cat <<EOF
{
  "skills":  ["$KIT_DIR/.pi/skills"],
  "prompts": ["$KIT_DIR/.pi/prompts"],
  "enableSkillCommands": true
}
EOF

log ""
if (( DRY_RUN )); then
  log "Dry run complete — no changes made."
else
  log "Done. In a running pi session run /reload (or restart pi) to pick up new agents/extensions/skills/prompts."
  log "Note: project *trust* decisions are not picked up by /reload — trust this repo once with /trust or use --approve."
fi
