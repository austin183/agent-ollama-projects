#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CollageMaker"
PROJECT="CollageMaker.xcodeproj"
SCHEME="CollageMaker"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$SCRIPT_DIR/CollageMaker"

# Kill existing instance
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
sleep 0.5

# Build
xcodebuild -project "$PROJECT_DIR/$PROJECT" -scheme "$SCHEME" \
    -configuration Debug -destination 'platform=macOS,arch=arm64' build

APP_PATH=$(find "$HOME/Library/Developer/Xcode/DerivedData/$APP_NAME-"*/Build/Products/Debug -name "$APP_NAME.app" -type d | head -1)

if [ -z "$APP_PATH" ]; then
  echo "Error: Could not find $APP_NAME.app in DerivedData" >&2
  exit 1
fi

case "$MODE" in
  run)
    open "$APP_PATH"
    ;;
  --logs|logs)
    open "$APP_PATH"
    sleep 1
    /usr/bin/log stream --predicate "process == \"$APP_NAME\"" --style compact
    ;;
  --telemetry|telemetry)
    open "$APP_PATH"
    sleep 1
    /usr/bin/log stream --predicate 'process == "CollageMaker" or subsystem == "austin183.indie.CollageMaker"' --style compact
    ;;
  --test|test)
    TEST_IMAGES_DIR="$(cd "$SCRIPT_DIR/TestImages" && pwd)"
    COLLAGEMAKER_TEST_IMAGES_DIR="$TEST_IMAGES_DIR" open "$APP_PATH"
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --verify|verify)
    open "$APP_PATH"
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--logs|--telemetry|--test|--verify]" >&2
    exit 2
    ;;
esac
