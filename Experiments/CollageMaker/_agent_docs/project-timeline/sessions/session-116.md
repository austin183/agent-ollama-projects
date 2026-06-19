# Session 116 — Round 100: Diagonal Slices Edge Panel Pan Boundaries (Polygon-Aware Visible Bounds)

**Date:** 2026-06-18
**Change Request:** `_agent_docs/change-requests/round-100.md`

## Summary

Fixed a bug where diagonal slices edge panels (leftmost, rightmost) computed pan boundaries from the parallelogram's axis-aligned bounding rectangle instead of the actual clipped polygon. This prevented users from panning images to their true top/bottom edges within the visible triangle.

First pass implemented the polygon-aware computation but missed a Y-axis flip between canvas coordinates (bottom-left origin) and source image coordinates (top-left origin). Second pass corrected `offCanvasTop` to measure the canvas top clip (`boundingRect.maxY - clippedMaxY`) instead of the canvas bottom clip (`clippedMinY - boundingRect.minY`), since the clamping logic treats `offsetY` as "pixels to skip at the source top."

## Changes

### New helper — `computeVisibleSourceBounds(destination:sourceW:sourceH:)` (CropManager.swift)
Added a polygon-aware overload that:
- For `.rect`: delegates to existing rect-based logic (no change)
- For `.path`: extracts polygon vertices via `extractPathPoints`, clips to canvas via `PolygonClipper.clip()`, computes visible extents from the clipped polygon, and accounts for the canvas-to-source Y-axis flip in the `offCanvasTop` calculation

### Updated callers (3 sites)
- `CropManager.applyPan` (line 169) — canvas scroll pan
- `CropManager.applyPinch` (lines 228-229) — zoom anchor computation
- `PanelCropEditor` overlay drag setup (line 95) — detail panel drag gesture

### New tests (7 tests, CropManagerTests.swift)
- `computeVisibleSourceBoundsRectDelegatesToRectLogic` — `.rect` panels unchanged
- `computeVisibleSourceBoundsFullyOnCanvasRect` — fully on-canvas rect
- `computeVisibleSourceBoundsDiagonalSlicesLeftmostPanel` — leftmost edge panel triangle
- `computeVisibleSourceBoundsDiagonalSlicesRightmostPanel` — rightmost edge panel triangle
- `computeVisibleSourceBoundsDiagonalSlicesMiddlePanel` — middle panel (full height, clipped X)
- `computeVisibleSourceBoundsPathPanelFullyOnCanvas` — `.path` panel fully within canvas
- `computeVisibleSourceBoundsPathPanelFullyOffCanvas` — `.path` panel entirely off-canvas

## Bug: Y-Axis Flip in offCanvasTop

The first implementation used `clippedMinY - boundingRect.minY` to compute `offCanvasTop`, measuring the canvas bottom clip. But canvas Y is bottom-left origin while source image Y is top-left origin. The rendering pipeline flips Y: canvas bottom maps to source top, canvas top maps to source bottom. The clamping logic treats `offsetY` as "pixels to skip at the source top." A clip at the canvas bottom (source top) must be expressed as a clip at the canvas top to produce the correct source-top offset after the flip.

**Fix:** `offCanvasTop = max(0, boundingRect.maxY - clippedMaxY)`

## Verification

- `xcodebuild build` — Succeeded
- `xcodebuild test -only-testing:CollageMakerTests` — All tests pass (0 failures)
- diff-review-g31 — Clean (no issues)
- Manual verification — User confirmed leftmost panel can now pan to both top and bottom edges

## Files Changed

| File | Changes |
|------|---------|
| `ViewModel/CropManager.swift` | New polygon-aware `computeVisibleSourceBounds`, updated 3 callers |
| `Views/PanelCropEditor.swift` | Updated overlay drag setup caller |
| `CollageMakerTests/CropManagerTests.swift` | 7 new tests for polygon-aware bounds |

## New Learnings

Created `_agent_docs/learnings/polygon-clip-y-axis-flip-visible-bounds.md` — documents the Y-axis flip interaction between canvas coordinates, source image coordinates, and the `offCanvasTop` formula when computing visible bounds from a clipped polygon.

---
**Status:** Complete
**Follow-up:** None. Round 100 complete.
