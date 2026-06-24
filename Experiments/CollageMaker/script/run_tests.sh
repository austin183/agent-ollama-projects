#!/usr/bin/env bash
set -uo pipefail

PROJECT="CollageMaker.xcodeproj"
SCHEME="CollageMaker"
TEST_TARGET="CollageMakerTests"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$SCRIPT_DIR/CollageMaker"

DESTINATION='platform=macOS,arch=arm64'

# Capture raw output to a temp file so we can parse results
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

echo "Running tests..."

xcodebuild test \
    -project "$PROJECT_DIR/$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -only-testing:"$TEST_TARGET" \
    -quiet \
    2>&1 | tee "$TMPFILE" || true

echo ""
echo "=== Test Results ==="

PASSED=$(grep -ci 'Test case .* passed' "$TMPFILE" || true)
FAILED=$(grep -ci 'Test case .* failed' "$TMPFILE" || true)
TOTAL=$((PASSED + FAILED))

if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "❌ $FAILED of $TOTAL tests failed:"
  echo ""
  grep -i 'Test case .* failed' "$TMPFILE" || true
  echo ""
  exit 1
else
  echo "✅ All $TOTAL tests passed."
  exit 0
fi
