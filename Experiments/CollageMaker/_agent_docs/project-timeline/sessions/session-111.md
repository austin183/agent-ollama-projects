# Session 111 — SRP Remediation Phase 7.1: ImageCoordinatorTests

**Date:** 2026-06-18
**Plan:** `_agent_docs/plans/2026-06-15-srp-remediation-plan.md` § Phase 7.1

## Summary

Created `ImageCoordinatorTests.swift` with 20 tests covering all public methods of `ImageCoordinator`. Added `MockCoordinationTarget` to `TestHelpers.swift` as a call-tracking mock for the `ImageCoordinationTarget` protocol. Ran diff-review-g31 — no bugs found, one coverage gap noted (`addImages(from:)` is hard to unit-test in isolation due to filesystem dependency).

## MockCoordinationTarget

Added to `TestHelpers.swift` (53 lines). Conforms to `ImageCoordinationTarget` and tracks:
- Call counts: `beginProcessingCalls`, `endProcessingCalls`, `updatePreviewCalls`, `updateAllPanelPreviewsCalls`, `regenerateLayoutCalls`
- Call arguments: `updatePanelPreviewCalls: [UUID]`, `resetCropCalls: [UUID]`, `cancelDebouncerCalls: [String]`
- State: `isProcessing`, `selectedPanelId`, `errorMessage`, `customImageOrder`

## Test Coverage (20 tests)

| Category | Tests |
|----------|-------|
| `removeImage` | Returns item+index, out of bounds, middle removal |
| `moveImages` | Returns old order, updates custom order, clears panel assignments |
| `clearDomain` | Clears images+saliency, empty state no-op |
| `assignImage` | Updates panel assignments, triggers resetCrop + updatePanelPreview |
| `getEffectiveImageIndex` | Explicit assignment, fallback to panel index, nil for unknown |
| `selectPanelForImage` | Matching panel, explicit assignment, out of bounds |
| `swapPanelImages` | Same ID no-op, swaps assignments+crops, single crop no-swap |
| `analyzeSaliency` | Updates results+crops, error handling, early return on empty |
| `browseImages` | Delegates to image library |

## Bugs Fixed During Development

- `swapPanelImagesDoesNotSwapCropsWhenOnlyOneExists` — initially asserted that a single crop would be copied to the other panel. The implementation uses `if let cropA = state.sourceCrop, let cropB = state.targetCrop` which requires BOTH crops to exist. Fixed assertion to expect `nil` for the panel without a crop.
- `#expect(throws: Never.self, calledThroughCoordinator)` — Swift Testing requires the expression as a trailing closure, not a separate argument. Fixed to `#expect(throws: Never.self) { coord.browseImages() }`.

## Verification

- `xcodebuild build` — Succeeded, zero errors
- `xcodebuild test` — All 20 ImageCoordinatorTests passed, full suite (300+ tests) passed
- diff-review-g31 — No bugs, noted `addImages(from:)` as coverage gap (filesystem-dependent, already covered by ImageLibraryManagerTests)

## Files Changed

| File | Changes |
|------|---------|
| `TestHelpers.swift` | Added `MockCoordinationTarget` class (53 lines) |
| `ImageCoordinatorTests.swift` | New file, 20 tests |

## New Learnings

None. The mock protocol pattern, `@MainActor @Suite(.serialized)` test struct, fixture helpers, and `#expect` assertions are all documented in existing skills and learnings.

---
**Status:** Complete
**Follow-up:** Phase 7.2 (LayoutManagerTests) or Phase 7.3 (TitleManagerTests extension) from the same plan.
