#!/usr/bin/env bash
# generate_daily_activity.sh — Generate daily-data.json for agent-driven activity summaries.
#
# Usage: ./generate_daily_activity.sh [SESSION_DIR] < data.json > daily-data.json
#
# SESSION_DIR defaults to _agent_docs/project-timeline/sessions/ relative to project root.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../../../.." && pwd)/Experiments/CollageMaker"
SESSION_DIR="${1:-${PROJECT_ROOT}/_agent_docs/project-timeline/sessions}"

# Validate session directory exists
if [[ ! -d "$SESSION_DIR" ]]; then
  echo "Error: Session directory not found: $SESSION_DIR" >&2
  exit 1
fi

# Run collect_daily_data.py with session dir and piped JSON data
python3 "$SCRIPT_DIR/collect_daily_data.py" --session-dir "$SESSION_DIR"
