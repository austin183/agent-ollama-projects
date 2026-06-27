#!/usr/bin/env bash
set -uo pipefail

PROJECT="CollageMaker.xcodeproj"
SCHEME="CollageMaker"
TEST_TARGET="CollageMakerTests"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$SCRIPT_DIR/CollageMaker"

DESTINATION='platform=macOS,arch=arm64'
RESULT_BUNDLE="/tmp/CollageMakerTestResults.xcresult"
rm -rf "$RESULT_BUNDLE" 2>/dev/null

echo "Running tests..."

xcodebuild test \
    -project "$PROJECT_DIR/$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -only-testing:"$TEST_TARGET" \
    -resultBundlePath "$RESULT_BUNDLE" \
    -quiet \
    > /dev/null 2>&1

# Parse results from xcresult bundle
if [ ! -d "$RESULT_BUNDLE" ]; then
  echo ""
  echo "=== Test Results ==="
  echo ""
  echo "Build failed — no test results available."
  echo ""
  exit 1
fi

xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" --format json 2>/dev/null | python3 -c "
import sys, json

d = json.load(sys.stdin)
pt = d.get('passedTests', 0)
ft = d.get('failedTests', 0)
st = d.get('skippedTests', 0)
total = pt + ft + st
failures = d.get('testFailures', [])

skip_note = f' ({st} skipped)' if st else ''
print(f'')
print('=== Test Results ===')

if ft > 0:
    print(f'')
    print(f'\u274c {ft} of {total} tests failed{skip_note}:')
    print(f'')
    for f in failures:
        ident = f.get('testIdentifierString', f.get('testName', 'unknown'))
        desc = f.get('failureText', 'no description')
        print(f'  {ident}')
        print(f'    {desc}')
    print(f'')
    sys.exit(1)
else:
    print(f'\u2705 All {total} tests passed.{skip_note}')
    sys.exit(0)
"
