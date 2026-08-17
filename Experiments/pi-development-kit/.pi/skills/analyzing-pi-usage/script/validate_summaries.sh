#!/usr/bin/env bash
# validate_summaries.sh — Scan session summaries, validate structure, report statistics
# Ported from the opencode kit; paths default to the pi kit's _agent_docs/sessions.
# Usage: bash validate_summaries.sh [--strict] [--root PATH] [--sessions-dir PATH] [--template PATH]
#   --strict              Exit with code 1 if any summary has missing required fields
#   --root PATH           Project root directory (default: computed from script location)
#   --sessions-dir PATH   Directory containing session summaries (default: $ROOT/_agent_docs/sessions)
#   --template PATH       Path to the session-summary.json template

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Default: compute root from skill directory structure
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
ROOT="$DEFAULT_ROOT"
SESSIONS_DIR=""
TEMPLATE_FILE=""
STRICT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)          ROOT="$2"; shift 2 ;;
    --sessions-dir)  SESSIONS_DIR="$2"; shift 2 ;;
    --template)      TEMPLATE_FILE="$2"; shift 2 ;;
    --strict)        STRICT=true; shift ;;
    *)               echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Compute defaults if not provided via flags
if [[ -z "$SESSIONS_DIR" ]]; then
  for candidate in "$ROOT/_agent_docs/sessions" "$ROOT/docs/sessions"; do
    if [ -d "$candidate" ]; then
      SESSIONS_DIR="$candidate"
      break
    fi
  done
  SESSIONS_DIR="${SESSIONS_DIR:-$ROOT/_agent_docs/sessions}"
fi

if [[ -z "$TEMPLATE_FILE" ]]; then
  TEMPLATE_FILE="$ROOT/.pi/skills/analyzing-pi-usage/references/session-summary.json"
fi

if [ ! -d "$SESSIONS_DIR" ]; then
  echo "ERROR: Sessions directory not found: $SESSIONS_DIR"
  exit 1
fi

# Delegate all validation logic to Python (avoids bash 4+ associative array requirement)
python3 - "$SESSIONS_DIR" "$TEMPLATE_FILE" "$STRICT" <<'PYEOF'
import json, sys, os, glob
from collections import defaultdict

sessions_dir, template_file, strict = sys.argv[1], sys.argv[2], sys.argv[3] == 'true'

REQUIRED_FIELDS = [
    'session_id', 'session_number', 'date', 'purpose', 'agent_role',
    'files_changed', 'test_files_added', 'tests_added', 'assertions_added',
    'bugs_fixed', 'learnings_written', 'plans_written', 'commits',
    'outcome', 'notes',
]

summary_files = sorted(glob.glob(os.path.join(sessions_dir, '*-summary.json')))

if not summary_files:
    print('No session summary files found in ' + sessions_dir)
    print('Summaries should be named: session-NNN-summary.json')
    sys.exit(0)

total = len(summary_files)
valid = 0
invalid = 0
missing_fields_total = 0
purpose_counts = defaultdict(int)
outcome_counts = defaultdict(int)
agent_counts = defaultdict(int)

for f in summary_files:
    fname = os.path.basename(f)
    try:
        with open(f) as fp:
            data = json.load(fp)
    except (json.JSONDecodeError, IOError) as e:
        print(f'  PARSE ERROR: {fname}: {e}')
        invalid += 1
        continue

    missing = [field for field in REQUIRED_FIELDS if field not in data]

    if missing:
        missing_fields_total += len(missing)
        print(f'  MISSING FIELDS in {fname}: {" ".join(missing)}')
        invalid += 1
        continue

    valid += 1
    purpose = data.get('purpose', 'unknown')
    outcome = data.get('outcome', 'unknown')
    agent = data.get('agent_role', 'unknown')
    purpose_counts[purpose] += 1
    outcome_counts[outcome] += 1
    agent_counts[agent] += 1

print('=== Session Summary Validation ===')
print()
print(f'Total summary files: {total}')
print(f'Valid: {valid}')
print(f'Invalid: {invalid}')
if missing_fields_total > 0:
    print(f'Total missing fields: {missing_fields_total}')
print()

print('--- By Purpose ---')
for purpose in sorted(purpose_counts):
    print(f'  {purpose}: {purpose_counts[purpose]}')
print()
print('--- By Outcome ---')
for outcome in sorted(outcome_counts):
    print(f'  {outcome}: {outcome_counts[outcome]}')
print()
print('--- By Agent Role ---')
for agent in sorted(agent_counts):
    print(f'  {agent}: {agent_counts[agent]}')
print()

if strict and invalid > 0:
    print(f'STRICT MODE: {invalid} summaries have missing fields')
    sys.exit(1)
PYEOF

exit $?
