#!/usr/bin/env bash
# plan-integrity-check.sh — mechanical integrity check for a decomposed plan directory.
#
# Usage: plan-integrity-check.sh <plan-dir> [options]
#   --ids '<regex>'      ERE of ID prefixes to verify (default: 'R-[A-Za-z0-9]+(\.[0-9]+)?|RD-[0-9]+')
#   --canonical f [f…]   Files that define canonical IDs (default: behavior-specs.md context.md index.md)
#
# Checks:
#   1. every ID referenced in phase-*.md resolves in a canonical file
#   2. phase-file count == phase-map row count in index.md
#   3. every phase file named in the index.md phase map exists
# Exits 0 on success, 1 on any failure.

set -u

die() { echo "error: $*" >&2; exit 2; }

[ $# -ge 1 ] || die "usage: plan-integrity-check.sh <plan-dir> [--ids <regex>] [--canonical f [f…]]"
plan_dir="$1"; shift
id_re='R-[A-Za-z0-9]+(\.[0-9]+)?|RD-[0-9]+'
canonical=(behavior-specs.md context.md index.md)

while [ $# -gt 0 ]; do
  case "$1" in
    --ids) [ $# -ge 2 ] || die "--ids needs a value"; id_re="$2"; shift 2 ;;
    --canonical)
      [ $# -ge 2 ] || die "--canonical needs at least one file"
      canonical=(); while [ $# -gt 0 ] && [ "$1" != --* ]; do canonical+=("$1"); shift; done
      [ ${#canonical[@]} -gt 0 ] || die "--canonical needs at least one file"
      ;;
    *) die "unknown option: $1" ;;
  esac
done

[ -d "$plan_dir" ] || die "not a directory: $plan_dir"
cd "$plan_dir" || die "cannot cd to $plan_dir"
[ -f index.md ] || die "index.md not found in $plan_dir"

fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

# --- 1. IDs referenced in phase files must resolve in a canonical file ---
phase_files=(phase-*.md)
[ -e "${phase_files[0]}" ] || { echo "FAIL: no phase-*.md files found" >&2; exit 1; }

ids=$(grep -ohE "$id_re" phase-*.md 2>/dev/null | sort -u)
if [ -n "$ids" ]; then
  missing=""
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    found=0
    for f in "${canonical[@]}"; do
      [ -f "$f" ] && grep -qF -- "$id" "$f" && { found=1; break; }
    done
    [ "$found" -eq 1 ] || missing="$missing  $id (referenced in phase files, not in any canonical file)\n"
  done <<< "$ids"
  if [ -n "$missing" ]; then
    echo "FAIL: unresolved IDs:" >&2; printf '%b' "$missing" >&2
    fail=1
  fi
fi

# --- 2. phase count: index.md phase map vs files ---
map_rows=$(awk '/^## Phase Map/{f=1;next} f&&/^\|[[:space:]]*[0-9]+/{c++} END{print c+0}' index.md) # numbered rows only
file_count=${#phase_files[@]}
[ "$map_rows" -eq "$file_count" ] || \
  err "phase-map rows in index.md ($map_rows) != phase file count ($file_count)"

# --- 3. every phase file named in the phase map exists ---
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || err "phase map references missing file: $f"
done < <(grep -oE 'phase-[0-9]+-[A-Za-z0-9._-]+\.md' index.md | sort -u)

if [ "$fail" -eq 0 ]; then
  echo "OK: ${#phase_files[@]} phase file(s); ID check covered: $(grep -ohE "$id_re" phase-*.md 2>/dev/null | sort -u | wc -l | tr -d ' ') distinct ID(s) across ${canonical[*]:-none}"
  exit 0
fi
exit 1
