# Fix Intermittent Test Failures

**Date:** 2026-06-15
**Status:** Proposed

## Problem

Running the full unit test suite (`CollageMakerTests`) produces 8-10 failures across multiple runs. Tests pass in isolation but fail when run together. Two categories were identified across 10+ test runs.

## Category 1: Deterministic Crash — `swapPanelImages` (2 tests)

**Failing tests:**
- `ExportFlowTests/swapPanelImagesUpdatesAssignments()`
- `ExportFlowTests/swapPanelImagesUpdatesCropMap()`

**Root cause:** `ImageCoordinator.swapPanelImages()` at `ImageCoordinator.swift:150` calls `imageLibrary.customImageOrder.swapAt(sourceSlot, targetSlot)` using panel slot indices (e.g. 0, 1). But `customImageOrder` is `[]` (empty) after `regenerateLayout()`. The `LayoutManager.regenerateLayout()` builds a local `order = Array(0..<images.count)` when `customImageOrder` is empty, but never writes it back to `imageLibrary.customImageOrder`. Result: `swapAt(0, 1)` on an empty array crashes with index out of bounds.

**Fix:** In `CollageViewModel.regenerateLayout()`, after `layoutManager.regenerateLayout()` returns, sync `customImageOrder` from the resulting `panelAssignments` so the array is always populated when images exist.

## Category 2: Async Task Interference (6 tests)

**Failing tests (only when full suite runs):**
- `PreviewManagerTests/updateBackgroundRendersImage()`
- `PreviewManagerTests/updatePanelPreviewRendersImage()`
- `CollageViewModelTests/titleColorChangeUpdatesPreview()`
- `CollageViewModelTests/titleBackgroundColorChangeUpdatesPreview()`
- `CollagePerformanceTests/scrollPreviewUpdatesAssembler()`
- `CollagePerformanceTests/scrollPanMultipleIterations()`

**Root cause:** All 6 are `async` tests that fail in 0.000s only during full-suite execution. They pass when their suite runs alone. `@Suite(.serialized)` serializes within each suite, but xcodebuild runs suites across parallel processes. Leftover async `Task`s from earlier-running suites (or the shared `TestAssembler` in `PreviewManagerTests`) bleed into subsequent tests, poisoning the `@MainActor` context.

**Fix:** Explicitly cancel pending tasks at test boundaries:
- `PreviewManagerTests`: `mgr.clearAll()` in the `manager` factory to cancel stale tasks from the shared assembler
- `CollageViewModelTests` + `CollagePerformanceTests`: `vm.previewManager.cancelAll()` at the end of each async test

## Implementation Plan

### Change 1: `CollageViewModel.swift`

**File:** `CollageMaker/CollageMaker/ViewModel/CollageViewModel.swift` (~line 508)

After the `layoutManager.regenerateLayout(...)` call and before `updatePreview()`, add:

```swift
// Sync customImageOrder from panelAssignments so swapPanelImages has a valid array.
if imageLibrary.customImageOrder.isEmpty || imageLibrary.customImageOrder.count != images.count {
    imageLibrary.customImageOrder = layoutManager.panels.enumerated()
        .compactMap { (idx, panel) in
            layoutManager.panelAssignments[panel.id].map { (idx, $0) }
        }
        .sorted { $0.0 < $1.0 }
        .map { $0.1 }
}
```

### Change 2: `PreviewManagerTests.swift`

**File:** `CollageMaker/CollageMakerTests/PreviewManagerTests.swift` (~line 9-11)

Change the `manager` computed property:

```swift
private var manager: PreviewManager {
    let mgr = PreviewManager(assembler: assembler)
    mgr.clearAll()
    return mgr
}
```

### Change 3: `CollageViewModelTests.swift`

**File:** `CollageMaker/CollageMakerTests/CollageViewModelTests.swift`

In `titleColorChangeUpdatesPreview()` (~line 195) and `titleBackgroundColorChangeUpdatesPreview()` (~line 213), add `vm.previewManager.cancelAll()` after the final assertion.

### Change 4: `CollagePerformanceTests.swift`

**File:** `CollageMaker/CollageMakerTests/CollagePerformanceTests.swift`

In `scrollPreviewUpdatesAssembler()` (~line 38) and `scrollPanMultipleIterations()` (~line 59), add `vm.previewManager.cancelAll()` after the final assertion.

## Verification

Run the full test suite 5 times:

```bash
for i in 1 2 3 4 5; do
    echo "Run $i:"
    xcodebuild test -project CollageMaker/CollageMaker.xcodeproj -scheme CollageMaker \
        -destination 'platform=macOS,arch=arm64' -only-testing:CollageMakerTests 2>&1 | \
        grep -E '(TEST FAILED|TEST SUCCEEDED)'
done
```

Expected: All 5 runs report `TEST SUCCEEDED`.

## Notes

- FontMergerTests (`nilExistingWithEmptyFamily`, `emptyFamilyReturnsBoldSystemFont`) showed 1 intermittent failure in early runs but were clean in later runs. Will monitor but not fix unless it recurs.
- The `customImageOrder` sync is a production fix — it corrects an invariant that `swapPanelImages` depends on, not just a test workaround.
