#!/usr/bin/env bash
# pi-analytics.sh — Query pi's session JSONL files for usage analytics.
# Thin wrapper over analytics.py (the opencode kit's analytics.sh was a full
# bash/SQLite driver; pi's data lives in JSONL, so the logic is in Python).
#
# Usage: ./script/analytics.sh [OPTIONS]
#
# Options (see `analytics.py --help` for details):
#   --project <pattern>   Filter by project directory (substring match)
#   --since <YYYY-MM-DD>  Start date (inclusive)
#   --until <YYYY-MM-DD>  End date (inclusive, defaults to today)
#   --days <N>            Last N days (overrides --since)
#   --week                Last 7 days
#   --month               Last 30 days
#   --all                 All-time (no date filter)
#   --models              Token usage by model
#   --roles               Token usage by role (--agents alias)
#   --model-roles         Model × role cross-tab (--model-agents alias)
#   --timeseries          Daily token trend
#   --weekly              Weekly token trend
#   --monthly             Monthly token trend
#   --projects            Token usage by project/directory
#   --top-sessions [N]    Top N sessions by token count (default 20)
#   --impact              File change impact (git-based)
#   --cache               Prefix cache approximation
#   --subagents           Subagent run attribution (pi-only)
#   --summary             High-level overview (default if no flags given)
#   --json                Output raw JSON instead of formatted text
#   --help                Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$SCRIPT_DIR/analytics.py" "$@"
