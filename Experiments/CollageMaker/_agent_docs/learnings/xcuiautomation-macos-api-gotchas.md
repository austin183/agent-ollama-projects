# XCUIAutomation macOS API Gotchas

**Date:** 2026-06-19
**Context:** UI automation Phase 2 — writing XCUIAutomation tests for CollageMaker on macOS 26.4+

## Problem

Several XCUIAutomation APIs commonly referenced in Apple documentation and online examples do not exist or behave differently in the macOS 26.5 SDK. Writing tests against assumed APIs results in compile-time errors that are easy to fix but time-consuming to discover.

## Gotchas

### `XCUIApplication.setEnvironment(_:forVariable:)` — Does Not Exist

This method does not exist on `XCUIApplication` in the macOS 26.5 SDK. It cannot be used to inject environment variables into the test target.

**Fix:** Use `launchArguments` with a convention the app understands:

```swift
app.launchArguments = ["COLLAGEMAKER_TEST_IMAGES_DIR=/path/to/TestImages"]
```

Then read from `CommandLine.arguments` in the app (in addition to `ProcessInfo.processInfo.environment`):

```swift
let dirPath = ProcessInfo.processInfo.environment["COLLAGEMAKER_TEST_IMAGES_DIR"]
    ?? CommandLine.arguments.first(where: { $0.hasPrefix("COLLAGEMAKER_TEST_IMAGES_DIR=") })?
    .components(separatedBy: "=").last
```

### `XCUIElementQuery.menuItem` — Does Not Exist

`app.menus.menuItem["Item Name"]` is a compile error. The `menuItem` subscript is not available on `XCUIElementQuery`.

**Fix:** Use `app.menuItems["Item Name"]` directly:

```swift
let uniformItem = app.menuItems["Uniform"]
XCTAssertTrue(uniformItem.exists)
```

### `XCUIElement.typeKeyword(_:)` — Does Not Exist

`element.typeKeyword(.a)` is not available. The `typeKeyword` method does not exist on `XCUIElement`.

**Fix:** Use `typeText(_:)` for arbitrary strings:

```swift
element.typeText("Test Title")
```

### `XCUIElement.focus()` — Does Not Exist

`element.focus()` is not available on `XCUIElement`.

**Fix:** `typeText(_:)` works without an explicit focus call — XCUIAutomation handles focus automatically.

### `XCTNSPredicateExpectation` + `wait(for:timeout:)` — Return Type Issues

The `wait(for:timeout:)` method on `XCTestCase` returns `Void` in some SDK versions, not `DispatchTimeoutResult`. Comparing against `.timedOut` is a compile error.

**Fix:** Use a polling loop with `RunLoop`:

```swift
private func waitForImagesLoaded(timeout: TimeInterval = 60) {
    let deadline = Date().addingTimeInterval(timeout)
    let exportButton = app.buttons["Export collage as JPEG"]

    while Date() < deadline {
        if exportButton.exists && exportButton.isEnabled {
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    XCTFail("Timed out waiting for images to load")
}
```

## Debugging Clues

- Compiler error "value of type 'XCUIApplication' has no member 'setEnvironment'" — the method simply doesn't exist, not a missing import
- "value of type 'XCUIElementQuery' has no member 'menuItem'" — use `app.menuItems[]` instead
- "cannot convert value of type 'Void' to expected argument type 'DispatchTimeoutResult'" — `wait(for:)` return type differs from documentation

## Prevention

- When writing XCUIAutomation tests, verify API availability against the actual SDK, not documentation or examples from other platforms (iOS APIs differ)
- Prefer `typeText(_:)` over character-by-keyword input — simpler and more reliable
- Use polling loops instead of `XCTNSPredicateExpectation` for condition waiting — more portable across SDK versions
- Test infrastructure that needs to pass configuration to the app should support both environment variables AND command line arguments

## Related

- `sandbox-file-access-test-bootstrap.md` — Debug builds need sandbox disabled for test file access
- `building-macos-apps` skill → `references/testing/testing-patterns.md` — unit testing patterns
