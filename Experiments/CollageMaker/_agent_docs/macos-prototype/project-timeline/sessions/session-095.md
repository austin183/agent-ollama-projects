# Session 95 — Post-Round-99 Review Phase B Fixes

**Date:** 2026-06-08
**Plan:** `_agent_docs/plans/2026-06-08-post-round-99-review-fixes.md`, Phase B

## Changes

### B1: Batch Error Handling (ERR-01)

**File:** `Services/SaliencyAnalyzer.swift`

Replaced `withThrowingTaskGroup` with `withTaskGroup` + `Result<SaliencyResult, Error>` pattern. Previously, one corrupt image would cancel all concurrent tasks and return zero results. Now each image is analyzed independently — failures are logged per-image, and partial results are returned so the collage renders with center-based fallback crops for failed images.

### B2: Double Exposure Overlay in Layered Mode

**Files:** `Services/CollageAssembler.swift`, `Services/PreviewManager.swift`, `ViewModel/CollageViewModel.swift`, `Views/CollageEditorView.swift`, `CollageMakerTests/TestHelpers.swift`

The overlay was correctly rendered into `previewImage` (full composite), but invisible in layered mode because the ZStack had no overlay layer.

- Added `OverlayRenderer` protocol (`renderOverlay(_:canvasSize:)`) to `CollageAssembly`
- Added `overlayImage` / `overlayBlendMode` properties and `updateOverlay(_:canvasSize:)` to `PreviewManager`
- Added proxy properties to `CollageViewModel`, wired `updatePreview()` and `updateAllPanelPreviews()` to trigger overlay rendering in layered mode
- Added overlay `Image` with `.blendMode()` modifier to the layered ZStack between panels and title
- Added `renderOverlay` stub to `TestAssembler` mock

**diff-review bugs fixed:**
1. `renderOverlay` was applying `CGContext.setBlendMode(.multiply)` on an empty context, producing black pixels. Moved blend mode from CoreGraphics to SwiftUI's `.blendMode()` modifier.
2. `updateAllPanelPreviews()` was missing overlay update — overlay absent after layout regeneration.
3. `buildAssemblyConfig()` called twice in `updatePreview()` — reused existing `config` variable.

### B3: Debouncer Utility (SRP-02)

**Files:** New `ViewModel/Debouncer.swift`, `ViewModel/CollageViewModel.swift`

Extracted `@MainActor final class Debouncer` with `debounce(id:delay:work:)`, `cancel(id:)`, and `cancelAll()`. Replaced 8 identical debounce task variables (`saveDebounceTask`, `previewDebounceTask`, `previewRenderDebounceTask`, `panelPreviewTask`, `titleDebounceTask`, `fontSizeDebounceTask`, `gutterDebounceTask`, `backgroundColorDebounceTask`) with a single `Debouncer` instance. Eliminated ~70 lines of cancel-sleep-execute boilerplate.

## Results

- Build: passed
- Tests: all passing

## New Learnings

- `cgblendmode-empty-context-learnings.md` — CGBlendMode on transparent CGContext produces black
