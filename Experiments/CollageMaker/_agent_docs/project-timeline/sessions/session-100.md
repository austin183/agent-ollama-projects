# Session 100 — Round 99.4 Crop Overlay Fixes & Off-Canvas Drag Clamping

**Date:** 2026-06-11
**Plan:** `_agent_docs/plans/2026-06-11-round-99.4-crop-overlay-fixes.md`
**CR:** `_agent_docs/change-requests/round-99.4.md`

## Summary

Fixed 4 remaining crop overlay bugs from Round 99.4 plan. User then reported that diagonal slice triangle panels couldn't pan/drag the image to canvas edges — the off-canvas parallelogram portion was consuming drag range. Extended the fix to both the Panel Editor drag gesture and the canvas pan gesture, plus the CollageAssembler rendering pipeline. Build succeeds.

## Changes Made

### Issue #3 — canvasClipInPanel Math (`PanelCropEditor.swift:444-455`)

`extractPathPoints(cgPath)` returns points in **canvas coordinates** (verified against `LayoutGenerator.swift`). The old code incorrectly assumed panel-local coordinates and applied a wrong transform (`-panelFrame.origin.x` offsets), shrinking the clip rect for leftmost panels. Fixed to `CGRect(origin: .zero, size: canvasSize)`. This also resolved Issue #1 (diagonal slices hourglass) as a direct consequence.

### Issue #4 — Dead clipEdge Function (`PanelCropEditor.swift:481-508`)

Removed 28 lines of dead code — `clipEdge` was defined but never called (only `clipEdgeCorrect` was used). The dead function also had a bug: `prev` was `let` and never updated in the loop.

### Issue #2 — Hexagonal Corner Resize (`PanelCropEditor.swift`)

Three changes across the gesture pipeline:
- **Gesture handler**: Always computes `sourceRectProj` via `computeVisibleRect` for both `.rect` and `.path` geometries. Sets `dragBaseOrigin`/`dragBaseSize` from `sourceRectProj` for all panel types. Removed dead `dragBaseQuad` state.
- **detectDragMode**: Added `sourceRectProj` parameter, removed `vertices.count == 4` guard, used `sourceRectProj` corners for resize handle detection.
- **visibleRegionHandles**: For `.quad`, computed handle positions from `computeVisibleRect` corners instead of polygon vertices.

### User Feedback — Revert Handles to Polygon Vertices

The `sourceRectProj` corners extended past the parallelogram overlay for diagonal slices, making handles visually disconnected from the overlay. Reverted:
- **Handles**: Back to polygon vertices (`visibleRegionHandles` uses `.quad(let v)` directly)
- **Hit-testing**: Back to polygon vertices, classified by bounding box center position (top-left vs bottom-right)
- **Resize math**: `dragBaseOrigin`/`dragBaseSize` derived from polygon bounding box

### User Feedback — Off-Canvas Drag Range (`PanelCropEditor.swift`, `CropManager.swift`, `CollageAssembler.swift`)

For diagonal slice panels, the parallelogram extends beyond the canvas. The `sourceRect` maps to the full parallelogram bounding box. When panning/dragging, the off-canvas portion "eats" drag range — the visible triangle hits the image edge limit before the triangle itself reaches the canvas edge.

**Fix in Panel Editor drag** (`PanelCropEditor.swift`):
- Added `dragVisibleOffset` and `dragVisibleSize` state — computed from the parallelogram bounding box vs canvas bounds
- Drag operates on "effective origin" (`sourceRect.origin + visibleOffset`), clamped to `[0, image.size - visibleSize]`
- Translates back to actual `sourceRect.origin` (which can go negative)

**Fix in canvas pan** (`CropManager.swift`):
- Added `VisibleSourceBounds` struct and `computeVisibleSourceBounds(destRect:sourceW:sourceH:)` helper
- `applyPan` uses the same effective-origin clamping pattern
- `applyPinch` uses the visible bounds for zoom limits

**Fix in rendering** (`CollageAssembler.swift`):
- Both `drawPanels` and `renderPanel` now handle `sourceRect` extending beyond image bounds
- When `cg.cropping(to:)` fails, clamps to the overlapping portion and draws in the corresponding sub-rectangle of `destRect`

## Verification

- `xcodebuild build` — Succeeded
- User verified: diagonal slices can pan/drag to both left and right edges, hexagonal corner resize works, handles match overlay shape

## Files Changed

| File | Changes |
|------|---------|
| `Views/PanelCropEditor.swift` | Fixed canvasClipInPanel, removed dead clipEdge, gesture handler visible bounds, vertex-based handles/hit-testing, drag clamping with visible offset |
| `ViewModel/CropManager.swift` | `VisibleSourceBounds` struct, `computeVisibleSourceBounds`, `applyPan` effective-origin clamping |
| `Services/CollageAssembler.swift` | `drawPanels` and `renderPanel` sourceRect clamping for off-image rects |

## New Learnings

Created `off-canvas-panel-drag-clamping.md` — visible bounds clamping pattern for panels extending beyond canvas.

---
**Status:** Complete
**Follow-up:** None
