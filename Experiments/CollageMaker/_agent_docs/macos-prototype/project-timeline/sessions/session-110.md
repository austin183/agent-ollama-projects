# Session 110 — SRP Remediation Phase 6.4: Cache panelFrames in VM + TitleManagerTests Fix

**Date:** 2026-06-18
**Plan:** `_agent_docs/plans/2026-06-15-srp-remediation-plan.md` § Phase 6.4

## Summary

Implemented Phase 6.4 (R4) — moved the O(N) `panelFrames` computation out of the SwiftUI `body` evaluation path into a cached method on `CollageViewModel`. Also fixed pre-existing compilation errors in `TitleManagerTests.swift` that referenced the deleted `TitleDragHandler` type.

## Phase 6.4 Changes

### LayoutManager: layoutVersion Counter

Added `layoutVersion: Int` (starts at 0), incremented in `regenerateLayout()` and `reset()`. This gives the VM a cheap way to detect panel layout changes without comparing arrays or exposing `LayoutManager` internals to views.

### CollageViewModel: Cached panelFrames

Added `computePanelFrames(previewSize: CGSize) -> [UUID: CGRect]` with a three-field cache:
- `cachedPanelFramesVersion` — mirrors `layoutManager.layoutVersion`
- `cachedPanelFramesSize` — last `previewSize` argument
- `cachedPanelFramesResult` — cached `[UUID: CGRect]`

Cache invalidates when either `layoutVersion` or `previewSize` changes.

### CollageEditorView: Body Simplification

Replaced the inline `panels.reduce(into:)` + `canvasToPreviewFrame` call in the `GeometryReader` closure with `viewModel.computePanelFrames(previewSize: geometry.size)`. The body still computes frames on-the-fly (avoiding the `@State` staleness gap from session 54), but the O(N) work is now cached behind a version counter instead of running on every body evaluation.

### TitleManager: Test Override Properties

Added two `internal` test-only properties:
- `testCanvasFrameOverride: CGRect?` — bypasses CoreText bounds computation
- `testMinWidthOverride: CGFloat?` — bypasses CoreText min-width computation

These allow tests to inject deterministic frames without needing real attributed strings and font metrics.

### TitleManagerTests: Complete Rewrite

Rewrote all 28 tests to use `TitleManager` instead of the non-existent `TitleDragHandler` type. Changes:
- `makeHandler(titleCanvasFrame:)` → `makeManager(titleCanvasFrame:minWidth:previewSize:)`
- All method calls updated to `TitleManager` API: `hitTestTitle(location:previewSize:)`, `computeTitleDragOffset(startLocation:previewSize:)`, `computeTitleResize(screenLocation:edge:previewSize:)`, `computeTitleDragPosition(screenLocation:offset:previewSize:)`
- Fixed unqualified enum cases (`.left` → `TitleResizeEdge.left`, `.none` → `TitleHitResult.none`, `.zero` → `CGPoint.zero`)

## Verification

- `xcodebuild build` — Succeeded, zero errors
- `xcodebuild test` — All tests passed (28 TitleManagerTests + full suite)

## Files Changed

| File | Changes |
|------|---------|
| `ViewModel/LayoutManager.swift` | Added `layoutVersion` counter, incremented in `regenerateLayout()` and `reset()` |
| `ViewModel/CollageViewModel.swift` | Added `computePanelFrames(previewSize:)` with 3-field cache |
| `ViewModel/TitleManager.swift` | Added `testCanvasFrameOverride` and `testMinWidthOverride` |
| `Views/CollageEditorView.swift` | Replaced inline `reduce` with `viewModel.computePanelFrames()` |
| `TitleManagerTests.swift` | Rewrote 28 tests for `TitleManager` API |

## New Learnings

None. The version counter pattern, on-the-fly GeometryReader computation, and `@State` staleness gap are all documented in existing learnings and skill references.

---
**Status:** Complete
**Follow-up:** Phase 6.2 (Title logic extraction) or Phase 6.3 (NSOpenPanel flows) from the same plan.
