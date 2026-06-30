#!/usr/bin/env bash
# validate_summaries.sh — Scan session summaries, validate structure, report statistics
# Usage: bash validate_summaries.sh [--strict] [--root PATH] [--sessions-dir PATH] [--template PATH]
#   --strict              Exit with code 1 if any summary has missing required fields
#   --root PATH           Project root directory (default: computed from script location)
#   --sessions-dir PATH   Directory containing session summaries (default: $ROOT/_agent_docs/project-timeline/sessions)
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
  SESSIONS_DIR="$ROOT/_agent_docs/project-timeline/sessions"
fi

if [[ -z "$TEMPLATE_FILE" ]]; then
  TEMPLATE_FILE="$ROOT/.opencode/skills/analyzing-opencode-usage/references/session-summary.json"
fi

REQUIRED_FIELDS=(
  "session_id"
  "session_number"
  "date"
  "purpose"
  "agent_role"
  "files_changed"
  "test_files_added"
  "tests_added"
  "assertions_added"
  "bugs_fixed"
  "learnings_written"
  "plans_written"
  "commits"
  "outcome"
  "notes"
)

VALID_PURPOSES=("code" "test" "docs" "debug" "refactor" "research")
VALID_OUTCOMES=("success" "partial" "failed")

if [ ! -d "$SESSIONS_DIR" ]; then
  echo "ERROR: Sessions directory not found: $SESSIONS_DIR"
  exit 1
fi

SUMMARY_FILES=("$SESSIONS_DIR"/*-summary.json)
if [ ! -e "${SUMMARY_FILES[0]}" ]; then
  echo "No session summary files found in $SESSIONS_DIR"
  echo "Summaries should be named: session-NNN-summary.json"
  exit 0
fi

TOTAL=${#SUMMARY_FILES[@]}
VALID=0
INVALID=0
MISSING_FIELDS_TOTAL=0

declare -A PURPOSE_COUNTS
declare -A OUTCOME_COUNTS
declare -A AGENT_COUNTS

for f in "${SUMMARY_FILES[@]}"; do
  FILE_VALID=true
  MISSING=()

  for field in "${REQUIRED_FIELDS[@]}"; do
    VALUE=$(python3 -c "
import json, sys
try:
    with open('$f') as fp:
        data = json.load(fp)
    if '$field' in data:
        print('PRESENT')
    else:
        print('MISSING')
except:
    print('PARSE_ERROR')
" 2>/dev/null)

    if [ "$VALUE" = "MISSING" ]; then
      MISSING+=("$field")
      MISSING_FIELDS_TOTAL=$((MISSING_FIELDS_TOTAL + 1))
    elif [ "$VALUE" = "PARSE_ERROR" ]; then
      echo "  PARSE ERROR: $(basename "$f")"
      FILE_VALID=false
      MISSING+=("ALL (parse error)")
      break
    fi
  done

  if [ "$FILE_VALID" = false ]; then
    INVALID=$((INVALID + 1))
    continue
  fi

  if [ ${#MISSING[@]} -gt 0 ]; then
    echo "  MISSING FIELDS in $(basename "$f"): ${MISSING[*]}"
    FILE_VALID=false
  fi

  if [ "$FILE_VALID" = true ]; then
    VALID=$((VALID + 1))

    PURPOSE=$(python3 -c "
import json
with open('$f') as fp:
    data = json.load(fp)
print(data.get('purpose', 'unknown'))
" 2>/dev/null)

    OUTCOME=$(python3 -c "
import json
with open('$f') as fp:
    data = json.load(fp)
print(data.get('outcome', 'unknown'))
" 2>/dev/null)

    AGENT=$(python3 -c "
import json
with open('$f') as fp:
    data = json.load(fp)
print(data.get('agent_role', 'unknown'))
" 2>/dev/null)

    PURPOSE_COUNTS["$PURPOSE"]=$(( ${PURPOSE_COUNTS["$PURPOSE"]:-0} + 1 ))
    OUTCOME_COUNTS["$OUTCOME"]=$(( ${OUTCOME_COUNTS["$OUTCOME"]:-0} + 1 ))
    AGENT_COUNTS["$AGENT"]=$(( ${AGENT_COUNTS["$AGENT"]:-0} + 1 ))
  else
    INVALID=$((INVALID + 1))
  fi
done

echo "=== Session Summary Validation ==="
echo ""
echo "Total summary files: $TOTAL"
echo "Valid: $VALID"
echo "Invalid: $INVALID"
if [ $MISSING_FIELDS_TOTAL -gt 0 ]; then
  echo "Total missing fields: $MISSING_FIELDS_TOTAL"
fi
echo ""

echo "--- By Purpose ---"
for purpose in $(echo "${!PURPOSE_COUNTS[@]}" | tr ' ' '\n' | sort); do
  echo "  $purpose: ${PURPOSE_COUNTS[$purpose]}"
done
echo ""

echo "--- By Outcome ---"
for outcome in $(echo "${!OUTCOME_COUNTS[@]}" | tr ' ' '\n' | sort); do
  echo "  $outcome: ${OUTCOME_COUNTS[$outcome]}"
done
echo ""

echo "--- By Agent Role ---"
for agent in $(echo "${!AGENT_COUNTS[@]}" | tr ' ' '\n' | sort); do
  echo "  $agent: ${AGENT_COUNTS[$agent]}"
done
echo ""

if [ "$STRICT" = true ] && [ $INVALID -gt 0 ]; then
  echo "STRICT MODE: $INVALID summaries have missing fields"
  exit 1
fi

exit 0
