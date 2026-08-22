# Session 105 — SRP Decomposition Phase 2 (Round 2): ImageCoordinator

**Date:** 2026-06-15
**Plan:** `_agent_docs/plans/2026-06-14-vm-decomposition-round2.md` § Phase 2

## Summary

Implemented Phase 2 of the Round 2 VM decomposition plan — extracted `ImageCoordinator` (image loading, reordering, removal, panel assignment, saliency analysis) from `CollageViewModel`. The coordinator holds direct references to all managers it needs and the ViewModel for callbacks. Thin wrapper methods on the ViewModel delegate to the coordinator, preserving the existing API surface for tests and views.

## New File

### `ViewModel/ImageCoordinator.swift` (193 lines)

`@MainActor final class` holding:
- Dependencies: `viewModel`, `imageLibrary`, `layoutManager`, `cropManager`, `previewManager`, `undoManager`, `saliencyAnalyzer`
- State: `saliencyResults: [Int: SaliencyResult]` (moved from CollageViewModel)
- Image operations: `browseImages()`, `addImages(from:)`, `removeImage(at:)`, `moveImages(from:to:)`, `clearAll()`
- Panel assignment: `assignImage(_:to:)`, `getEffectiveImageIndex(for:)`, `selectPanelForImage(at:)`, `swapPanelImages(sourceId:targetId:)`
- Saliency: `analyzeSaliency()` (moved from CollageViewModel, triggers crop recomputation and preview updates)

Key design: `ImageCoordinator` holds a strong reference to `CollageViewModel` for callbacks (`beginProcessing`, `endProcessing`, `errorMessage`, `selectedPanelId`, etc.). This is safe because the coordinator is owned by the ViewModel — no circular strong reference. Undo registration targets the ViewModel directly.

## CollageViewModel Changes

- Added `imageCoordinator: ImageCoordinator!` stored property (implicitly unwrapped, initialized in `init` after all managers exist)
- Removed `private var saliencyResults: [Int: SaliencyResult]` — now on `imageCoordinator`
- Removed method bodies for 9 methods (~104 lines): `browseImages`, `addImages`, `removeImage`, `moveImages`, `clearAll`, `assignImage`, `getEffectiveImageIndex`, `selectPanelForImage`, `swapPanelImages`, `analyzeSaliency`
- Added thin wrapper methods that delegate to `imageCoordinator.*`
- Updated `regenerateLayout()` — reads `imageCoordinator.saliencyResults` instead of `self.saliencyResults`

## View & Caller Updates

| File | Changes |
|------|---------|
| `ContentView.swift` | 3 calls: `browseImages()`, `addImages(from:)` (drop handler) → `imageCoordinator.*` |
| `ImageLibrarySidebar.swift` | 5 calls: `removeImage`, `selectPanelForImage`, `moveImages`, `browseImages` → `imageCoordinator.*` |
| `CollageEditorView.swift` | 4 calls: `getEffectiveImageIndex`, `swapPanelImages`, `removeImage` → `imageCoordinator.*` |
| `PanelCropEditor.swift` | 1 call: `getEffectiveImageIndex` → `imageCoordinator.*` |
| `CollageCommands.swift` | 1 call: `browseImages` → `imageCoordinator.*` |

## Test Updates

None required — thin wrapper methods on `CollageViewModel` preserve the existing API. All test calls to `vm.removeImage(at:)`, `vm.swapPanelImages(...)`, `vm.analyzeSaliency()`, etc. continue to work through the wrappers.

## Verification

- `xcodebuild build` — Succeeded, zero errors
- `xcodebuild test` — Zero new failures. All 8 failing tests (`PreviewManagerTests.updateBackgroundRendersImage`, `PreviewManagerTests.updatePanelPreviewRendersImage`, `ExportFlowTests.swapPanelImages*`, `CollageViewModelTests.titleColor/BackgroundColorChangeUpdatesPreview`, `CollagePerformanceTests.scroll*`) are **pre-existing** — confirmed by running tests on stashed original code.

## Line Counts

| File | Before | After | Net |
|------|--------|-------|-----|
| `CollageViewModel.swift` | 1,067 | 963 | -104 |
| `ImageCoordinator.swift` | — | 193 | +193 (new) |
| **Total** | 1,067 | 1,156 | +89 |

## Files Changed

| File | Changes |
|------|---------|
| `ViewModel/ImageCoordinator.swift` | New — image ops, panel assignment, saliency |
| `ViewModel/CollageViewModel.swift` | Removed 9 method bodies, added coordinator + wrappers, `saliencyResults` moved |
| `ContentView.swift` | 3 calls routed to `imageCoordinator.*` |
| `Views/ImageLibrarySidebar.swift` | 5 calls routed to `imageCoordinator.*` |
| `Views/CollageEditorView.swift` | 4 calls routed to `imageCoordinator.*` |
| `Views/PanelCropEditor.swift` | 1 call routed to `imageCoordinator.*` |
| `Views/CollageCommands.swift` | 1 call routed to `imageCoordinator.*` |

## New Learnings

None — all patterns (coordinator dependency injection, thin wrapper delegation, `@MainActor` isolation, undo registration across boundaries, pre-existing flaky test verification) are covered by existing learnings and skills.

---
**Status:** Complete
**Follow-up:** Phase 3 (Thin Down VM) and Phase 4 (Persistence & View Updates) from the same plan.
