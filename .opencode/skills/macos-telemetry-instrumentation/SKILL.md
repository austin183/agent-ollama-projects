---
name: macos-telemetry-instrumentation
description: Add lightweight runtime telemetry and debug instrumentation to macOS apps, then verify those events after building and running. Use when wiring Logger/os.Logger, adding log points for window/sidebar/menu-bar actions, reading runtime logs from log stream, or confirming that expected events fire after a local run.
---
# Telemetry

Add lightweight app instrumentation for debugging behavior without turning the codebase into a logging landfill. Prefer Apple's unified logging APIs.

## Core Guidelines

- Prefer `Logger` from the `OSLog` framework for structured app logs
- Give each feature a clear subsystem/category pair for easy filtering
- Log meaningful lifecycle events: window opening, selection changes, menu commands, sync milestones, error paths
- Keep info logs concise and stable; use debug logs for noisy state details
- Do not log secrets, auth tokens, personal data, or raw document contents
- Add signposts only when measuring timing or performance spans

## Minimal Logger Pattern

```swift
import OSLog

private let logger = Logger(
  subsystem: Bundle.main.bundleIdentifier ?? "com.example.AppName",
  category: "Sidebar"
)

@MainActor
func selectItem(_ item: SidebarItem) {
  logger.info("Selected sidebar item: \(item.id, privacy: .public)")
  selection = item.id
}
```

Use feature-specific categories: `Windowing`, `Commands`, `MenuBar`, `Sidebar`, `Sync`, `Import`, `Analysis`, `Export`.

## Workflow

1. Identify the behavior needing observability:
   - Window open/close
   - Sidebar or inspector selection changes
   - Menu or keyboard command actions
   - Background load/sync/import events
   - Error and recovery paths

2. Add the smallest useful instrumentation:
   - One `Logger` per feature area or type
   - Log action boundaries and key state transitions
   - One high-signal line per user action over noisy value dumps

3. Build and run the app

4. Read runtime logs and verify:
   ```bash
   # By process
   log stream --style compact --predicate 'process == "AppName"'

   # By subsystem and category (tighter)
   log stream --style compact --predicate 'subsystem == "com.example.app" && category == "Sidebar"'
   ```

5. Tighten or remove instrumentation:
   - If the event fires, keep only logs useful for future debugging
   - If it does not fire, move the log closer to the suspected control path and rerun

## Verification Checklist

- [ ] The app builds after telemetry changes
- [ ] The relevant action emits exactly one clear log line or small bounded sequence
- [ ] The log can be filtered by process, subsystem, or category
- [ ] No sensitive payloads are written to unified logs
- [ ] Noisy temporary debug logs are removed or demoted before finishing

## Reading Logs

### `log stream` vs `log show`

- **`log stream`** — Captures entries in real-time. Use during active testing for immediate feedback
- **`log show`** — Queries the persistent unified log store, which has a flush delay. Recent entries may not appear, making it unreliable for live debugging
- **Prefer `log stream`** during active development and testing. Use `log show` only for historical log review after a flush window

### `Logger` in `@MainActor` Classes

When calling `logger.info("\(someProperty)")` inside an `@MainActor` class, Swift closure capture rules require explicit `self`:

```swift
// Correct — explicit self in @MainActor class
logger.info("Image count: \(self.images.count)")

// Will produce: "reference to property 'images' in closure requires explicit use of self"
logger.info("Image count: \(images.count)")
```

## Guardrails

- Do not use `print` as the primary telemetry mechanism for macOS app code
- Do not leave a dense trail of permanent debug logs around every state mutation
- Do not claim an event is wired correctly until verified through `log stream` or Console
- If the debugging task is about crash/backtrace analysis rather than action telemetry, use build/debug workflows instead
