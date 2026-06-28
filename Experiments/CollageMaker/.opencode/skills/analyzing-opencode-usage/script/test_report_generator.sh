#!/usr/bin/env bash
# test_report_generator.sh — Validate the CollageMaker LLM report generator output.
# Usage: ./test_report_generator.sh [--output PATH]
# Runs the generator with a known date range and checks that the HTML output is well-formed,
# contains all expected sections, has valid SVG charts, and token totals are consistent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GENERATOR="${SCRIPT_DIR}/generate_llm_report.sh"
REPORT_DIR="$HOME/workspace/agent-ollama-projects/Experiments/CollageMaker/_agent_docs/project-timeline/llm-usage"
OUTPUT_TEST=""
PASS=0
FAIL=0

# ── Helpers ──────────────────────────────────────────────────────────────────

pass() {
  PASS=$((PASS + 1))
  echo "  PASS: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL: $1"
}

check() {
  local desc="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

# ── Argument Parsing ────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT_TEST="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ── Pre-flight Checks ───────────────────────────────────────────────────────

echo ""
echo "=== CollageMaker LLM Report Generator — Tests ==="
echo ""

if [[ ! -x "$GENERATOR" ]]; then
  echo "ERROR: Generator script not found or not executable: $GENERATOR" >&2
  exit 1
fi

# ── Test 1: Generate report and verify file exists ──────────────────────────

TEST_OUTPUT="${OUTPUT_TEST:-${REPORT_DIR}/test-report-$$-collagemaker-llm-report.html}"

echo "Test 1: Report generation"
bash "$GENERATOR" --days 7 --output "$TEST_OUTPUT" 2>/dev/null

check "Report file created" test -f "$TEST_OUTPUT"
check "Report file is non-empty (>1KB)" test "$(wc -c < "$TEST_OUTPUT")" -gt 1024

HTML="$TEST_OUTPUT"

# ── Test 2: HTML structure validity ────────────────────────────────────────

echo ""
echo "Test 2: HTML structure"

check "Contains DOCTYPE html" grep -q '<!DOCTYPE html>' "$HTML"
check "Contains closing </html>" grep -q '</html>' "$HTML"
check "Contains <title> with report name" grep -q 'CollageMaker.*LLM Usage Report' "$HTML"
check "Contains dark theme CSS variables" grep -q -- '--bg: #1a1a2e' "$HTML"

# ── Test 3: Required sections present ──────────────────────────────────────

echo ""
echo "Test 3: Section IDs"

REQUIRED_SECTIONS=("summary" "models" "agents" "cross-tab" "timeseries" "top-sessions" "code-impact")
for section in "${REQUIRED_SECTIONS[@]}"; do
  check "Section #${section} exists" grep -q "id=\"${section}\"" "$HTML"
done

# ── Test 4: SVG chart validation ───────────────────────────────────────────

echo ""
echo "Test 4: SVG chart"

check "SVG element present with id=daily-chart" grep -q 'id="daily-chart"' "$HTML"
check "SVG has valid viewBox attribute" grep -qE 'viewBox="0 0 [0-9]+ [0-9]+"' "$HTML"
check "Polyline has points attribute (non-empty)" grep -qE '<polyline[^>]*points="[^"]{10,}"' "$HTML"
check "Chart has data point circles" grep -c 'class="chart-point"' "$HTML" | awk '{exit ($1 > 5) ? 0 : 1}'

# ── Test 5: Tooltip JS present ─────────────────────────────────────────────

echo ""
echo "Test 5: Tooltips"

check "Inline <script> tag with tooltip logic" grep -q 'svg-tooltip' "$HTML"
check "Tooltip follows mousemove event" grep -q 'mousemove' "$HTML"

# ── Test 6: Token totals consistency ───────────────────────────────────────

echo ""
echo "Test 6: Data consistency"

# Get the total tokens from the summary card in HTML (first metric-value)
HTML_TOTAL=$(python3 -c "
import re, sys
html = open('$HTML').read()
m = re.search(r'<div class=\"metric-value\" data-raw-tokens=\"([0-9]+)\">', html)
print(m.group(1) if m else '0')
")

# Compute expected total from SQLite directly
EXPECTED_JSON=$(opencode db "SELECT SUM(tokens_input + tokens_output + tokens_reasoning) as total FROM session WHERE directory LIKE '%CollageMaker%' AND strftime('%Y-%m-%d', time_created / 1000, 'unixepoch') >= date('now', '-7 days')" --format json 2>/dev/null)
EXPECTED_TOTAL=$(echo "$EXPECTED_JSON" | jq -r '.[0].total // 0' 2>/dev/null || echo "0")

# Strip commas from HTML value for comparison
HTML_TOTAL_CLEAN="${HTML_TOTAL//,}"

if (( HTML_TOTAL_CLEAN > 0 && EXPECTED_TOTAL > 0 )); then
  python3 -c "
h = int('${HTML_TOTAL_CLEAN}')
e = int('${EXPECTED_TOTAL}')
ratio = min(h, e) / max(h, e)
exit(0 if ratio > 0.85 else 1)
" && pass "Summary token total consistent with SQL (~${HTML_TOTAL} vs ~${EXPECTED_TOTAL})" || fail "Token mismatch: HTML ${HTML_TOTAL} vs SQL ${EXPECTED_TOTAL}"
else
  fail "Could not parse token values for comparison (HTML=${HTML_TOTAL_CLEAN}, SQL=${EXPECTED_TOTAL})"
fi

# ── Test 7: Model bars rendered with segments ──────────────────────────────

echo ""
echo "Test 7: Model breakdown bars"

check "At least one stacked bar row exists" grep -q 'class="bar-row"' "$HTML"
check "Input color segment present (#4fc3f7)" grep -q '#4fc3f7' "$HTML"
check "Output color segment present (#4db6ac)" grep -q '#4db6ac' "$HTML"
check "Reasoning color segment present (#ba68c8)" grep -q '#ba68c8' "$HTML"

# ── Test 8: Agent bars rendered ────────────────────────────────────────────

echo ""
echo "Test 8: Agent usage bars"

check "At least one horizontal bar row exists" grep -q 'class="h-bar-row"' "$HTML"
check "Build agent listed in output" grep -q 'build' "$HTML"

# ── Test 9: Code impact section has data ───────────────────────────────────

echo ""
echo "Test 9: Code impact (git correlation)"

check "Impact grid cards present" grep -q 'class="impact-grid"' "$HTML"
check "Total commits values rendered (4 cards)" python3 -c "import re; html=open('$HTML').read(); vals=re.findall(r'<div class=\"impact-value\">([^<]+)</div>', html); exit(0 if len(vals)>=4 else 1)"
check "Daily detail table has rows" grep -q '<tr><td>[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]</td>' "$HTML"

# ── Test 10: Top sessions table rendered ───────────────────────────────────

echo ""
echo "Test 10: Top sessions"

check "Top sessions heading present" grep -q 'id="top-sessions"' "$HTML"
check "Table has at least one data row" python3 -c "import re; html=open('$HTML').read(); exit(0 if re.search(r'<tr><td>[0-9]</td>', html) else 1)"

# ── Cleanup & Summary ──────────────────────────────────────────────────────

rm -f "$TEST_OUTPUT" 2>/dev/null

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((PASS + FAIL))
if (( FAIL == 0 )); then
  echo "✅ All ${TOTAL} tests passed."
else
  echo "❌ ${FAIL} of ${TOTAL} tests failed."
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

exit "$FAIL"
