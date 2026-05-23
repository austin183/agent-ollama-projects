# Build, Run, and Debug

Shell-first workflows for building, launching, and debugging macOS apps.

## CLI Build and Launch

```bash
# Build
xcodebuild -project "App.xcodeproj" -scheme AppName \
    -configuration Debug -destination 'platform=macOS,arch=arm64' build

# Launch
open "$HOME/Library/Developer/Xcode/DerivedData/AppName-*/Build/Products/Debug/AppName.app"

# Build and test
xcodebuild -project "App.xcodeproj" -scheme AppName \
    -destination 'platform=macOS,arch=arm64' test

# Run specific test target (Swift Testing framework)
xcodebuild -project "App.xcodeproj" -scheme AppName \
    -destination 'platform=macOS,arch=arm64' \
    -only-testing:TargetName test
```

## Build Script Pattern

Create `script/build_and_run.sh` as the single kill + build + run entrypoint:

```bash
#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CollageMaker"
PROJECT="CollageMaker.xcodeproj"
SCHEME="CollageMaker"

# Kill existing instance
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

# Build
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -configuration Debug -destination 'platform=macOS,arch=arm64' build

APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/$APP_NAME-*/Build/Products/Debug/$APP_NAME.app"

case "$MODE" in
  run)
    open "$APP_PATH"
    ;;
  --logs|logs)
    open "$APP_PATH"
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open "$APP_PATH"
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.example.CollageMaker"'
    ;;
  --verify|verify)
    open "$APP_PATH"
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
```

## Debugging

- `NSUnbufferedIO=YES open ...` does not produce useful stdout for SwiftUI apps
- Use `os_log` (`Logger` from OSLog) for unified log output
- Use `log stream --predicate 'process == "AppName"'` for runtime logs
- When debugging GUI behavior without app visibility, write ViewModel integration tests
- For SwiftPM GUI apps: if window doesn't come forward, check `NSApp.setActivationPolicy(.regular)` + `NSApp.activate(ignoringOtherApps: true)`

## Classifying Build Failures

| Category | Signs |
|---|---|
| Compiler | Type errors, missing imports, unresolved identifiers |
| Linker | Undefined symbols, duplicate symbols |
| Signing | Code signing errors, entitlement issues |
| Build settings | Missing SDK, wrong deployment target |
| Script bug | Shell errors, wrong paths |
| Runtime launch | App crashes on startup, no window appears |
