# UI Automation — CLI Image Loading & Title Regression Tests

**Date:** 2026-06-19
**Status:** Draft — pending review

## Motivation

Title-related regressions are the most frequent breaking changes across 116 sessions. Common failure modes:
- Preview not updating on title text/color/font/position changes (sessions 11, 63, 74, 75, 76)
- Title invisible in layered mode during panel editing (sessions 56, 57)
- Stale render caches after clear-restore (session 80)
- Gesture conflicts between title and panel interactions (sessions 17, 27)
- Coordinate transform mismatches (sessions 14, 21, 26)

Unit tests cover `TitleManager` interaction math and `CollageViewModel` setter side effects (render call counts). What's missing is **integration-level verification** that the UI is wired correctly — controls exist, canvas renders, buttons are enabled.

The blocker: the app launches empty, requiring manual File Picker interaction. No automated test can proceed past the blank canvas.

## Plan

### Phase 1 — CLI Image Loading

Enable launching the app with pre-loaded images so tests can start from a known state.

#### 1a. `TestBootstrap.swift` (new file, ~30 lines)

Location: `CollageMaker/CollageMaker/TestBootstrap.swift`

Reads `COLLAGEMAKER_TEST_IMAGES_DIR` environment variable. When set, scans the directory for image files (`.jpg`, `.jpeg`, `.png`, `.tiff`, `.heic`, `.heif`) and returns sorted `[URL]`. Returns `nil` when the env var is not set — zero impact on normal usage.

```swift
enum TestBootstrap {
    static func loadTestImageURLs() -> [URL]?
}
```

No new dependencies. Uses `FileManager.default.contentsOfDirectory` with `isDirectory` check and extension filtering.

#### 1b. `CollageMakerApp.swift` — launch task (~8 lines)

Add a `.task` modifier on `ContentView` that:
1. Checks `TestBootstrap.loadTestImageURLs()`
2. If URLs exist, clears persisted state (new method on `UserDefaultsPersistence` or just `viewModel.clearAll()` before loading)
3. Calls `await viewModel.addImages(from: urls)`

The task runs once at launch (`.task` lifecycle). Normal usage is unaffected because the env var won't be set.

```swift
ContentView(viewModel: viewModel)
    .task {
        if let urls = TestBootstrap.loadTestImageURLs() {
            viewModel.clearAll()
            await viewModel.addImages(from: urls)
        }
    }
```

#### 1c. `build_and_run.sh` — `--test` mode (~8 lines)

New mode that builds, launches with the env var, and waits for the process to start:

```bash
--test|test)
    COLLAGEMAKER_TEST_IMAGES_DIR="../TestImages" open "$APP_PATH"
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
```

#### 1d. Clean state for tests

`XCUIApplication.launch()` calls `terminate()` first, but `UserDefaults` persist across launches. Two options:

**Option A:** `TestBootstrap` calls `viewModel.clearAll()` before loading images. This clears images, panels, crops, and resets background/title to defaults. The `.task` modifier ensures this runs before images load.

**Option B:** Use `COLLAGEMAKER_CLEAR_STATE=1` as a separate env var that clears all UserDefaults keys. More thorough but more complex.

**Decision:** Option A is sufficient. `clearAll()` resets title, background, panels, and images. Layout-specific settings (gutter, style) persist but don't affect test assertions.

### Phase 2 — UI Tests

#### 2a. `CollageMakerTitleTests.swift` (new file)

Location: `CollageMaker/CollageMakerUITests/CollageMakerTitleTests.swift`

Each test launches with `setEnvironment("../TestImages", forVariable: "COLLAGEMAKER_TEST_IMAGES_DIR")`, waits for images to load (poll sidebar element count), then asserts UI structure.

| # | Test | Verifies | Regression it catches |
|---|------|----------|----------------------|
| 1 | `testAppLaunchesWithTestImages` | Sidebar shows 5 image entries, canvas is not `ContentUnavailableView` | Images load at all, sidebar populates |
| 2 | `testExportButtonEnabled` | Export button exists and is enabled | Export wiring intact |
| 3 | `testTitleEditorExists` | "Title text editor" accessibility element exists | Title editor not removed from view |
| 4 | `testTitleFontSizeSliderExists` | "Title font size" slider exists | Font size control present |
| 5 | `testTitleColorWellExists` | "Title text color" color well exists | Color picker present |
| 6 | `testTitleAlignmentPickerExists` | "Title alignment" segmented control exists | Alignment picker present |
| 7 | `testBackgroundStylePickerExists` | "Background style" segmented control exists | Background controls present |
| 8 | `testLayoutMenuItemsPresent` | Menu bar has Layout > Uniform/Hero/Mosaic | Menu structure intact |
| 9 | `testAddImagesButtonPresent` | Toolbar "Add Images" button exists | Toolbar wiring intact |
| 10 | `testSidebarImageCount` | Sidebar shows exactly 5 image entries | Correct image count |

#### 2b. `CollageMakerSnapshotTests.swift` (new file)

Location: `CollageMaker/CollageMakerUITests/CollageMakerSnapshotTests.swift`

| # | Test | Verifies |
|---|------|----------|
| 1 | `testCanvasRendersScreenshot` | Takes screenshot attachment, verifies non-zero pixel count | Canvas renders something |
| 2 | `testCanvasRendersWithTitle` | (If feasible) Sets title text via AX, takes screenshot | Title appears in output |

These are lower-fidelity — they produce screenshot attachments for manual review or basic pixel checks, not pixel-perfect assertions. The value is catching "the canvas is blank" or "the title text editor is missing" before a human notices.

#### Timing strategy

Tests poll for conditions rather than sleeping:

```swift
// Wait for images to load (up to 30s)
let imagesPredicate = NSPredicate { _, _ in
    app.images.count > 0
}
expectation(for: imagesPredicate, evaluatedWith: app, handler: nil)
wait(for: [imagesExpectation], timeout: 30)
```

For saliency analysis completion (which runs after images load), wait for the processing indicator to disappear or the export button to become enabled.

### Phase 3 — Unit Test Gap (Optional)

One gap in existing unit tests: verify that `titleAttrString` changes in layered mode call `updateTitleImage()` (not `updatePreview()`). Session 75 regression. The existing test `titleAttrStringSetterCallsUpdatePreview` checks the non-layered path. Add:

```swift
@Test func titleAttrStringSetterInLayeredModeCallsUpdateTitleImage() async {
    // Set isLayeredMode = true, change title, verify titleRenderCalls increments
    // but previewCalls does NOT increment (only title layer re-renders)
}
```

This is a small addition to `CollageViewModelTests.swift`, ~15 lines.

## Files Changed

| File | Change | Lines |
|------|--------|-------|
| `CollageMaker/TestBootstrap.swift` | **New** — env var reader | ~30 |
| `CollageMaker/CollageMakerApp.swift` | `.task` modifier | +8 |
| `script/build_and_run.sh` | `--test` mode | +8 |
| `CollageMakerUITests/CollageMakerTitleTests.swift` | **New** — 10 UI tests | ~120 |
| `CollageMakerUITests/CollageMakerSnapshotTests.swift` | **New** — 2 snapshot tests | ~40 |
| `CollageMakerTests/CollageViewModelTests.swift` | 1 layered-mode test | +15 |

**Total:** ~220 lines of new/changed code.

## What We're NOT Testing

- Export dialog flow (system save panel — per user request)
- Gesture interactions (drag, resize, pinch — XCUIAutomation unreliable for these)
- Saliency analysis results (already mocked in unit tests)
- Performance regression (unit tests already measure render call counts)
- Pixel-perfect title rendering (screenshot attachments only)

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| XCUIAutomation timing flakiness | Poll for conditions, not fixed sleeps. 30s timeout. |
| Title editor is `NSTextView` wrapper | Use AX element existence checks, not text input. |
| Canvas is `NSImage`, not AX-inspectable | Screenshot attachments for verification. |
| Tests slow due to saliency analysis | Wait for export button enabled (proxy for "processing done"). |
| `TestBootstrap` affects production builds | Guarded by env var — never set in production. |

## Rollout

1. Write plan → review → approve
2. Implement Phase 1 (CLI loading) → build → verify manual launch works
3. Implement Phase 2 (UI tests) → run via `xcodebuild test` → verify green
4. Implement Phase 3 (unit test gap) → run full test suite
