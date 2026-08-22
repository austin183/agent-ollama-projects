# Round 100 — Diagonal Slices Edge Panel Pan Boundaries Ignore Clipped Shape

**Date:** 2026-06-18
**Type:** Bug fix

## Overview

In the Diagonal Slices layout, when panning edge panels (far left or far right), the user cannot pan the image to the top-most or bottom-most edges. The crop overlay renders as the correct clipped triangle shape, but the pan boundary constraints are computed from the **uncropped parallelogram bounding rectangle** instead of the **clipped polygon**. This creates a mismatch between what the user sees (a triangle) and what they can pan to (constrained as if it were a full-height rectangle).

## Reproduction

1. Open CollageMaker, add 3+ images
2. Switch to **Diagonal Slices** layout (any angle, default 45°)
3. Select the **leftmost** or **rightmost** panel
4. Scroll-pan the image up and down
5. Observe: the image cannot be panned to show its top-most or bottom-most edge within the visible triangle, even though there is visual room

The same issue affects the overlay drag gesture in the Panel Crop Editor detail panel.

## Root Cause

`CropManager.computeVisibleSourceBounds` (`CropManager.swift:496-512`) computes visible bounds by intersecting the panel's **bounding rectangle** with the canvas rect. For `.path` panels whose parallelogram extends beyond the canvas, this produces an axis-aligned rectangular intersection that does not match the actual clipped polygon.

**Concrete example — leftmost panel, 3 images, 45° angle, canvas 1920×1080:**

The leftmost parallelogram corners (canvas coords):
- Bottom-left: `(-1080, 0)` — off-canvas
- Bottom-right: `(-80, 0)` — off-canvas
- Top-right: `(1000, 1080)` — on-canvas
- Top-left: `(0, 1080)` — on-canvas

Bounding rect: `(-1080, 0, 2080, 1080)`

`computeVisibleSourceBounds` computes:
- `visMinY = max(0, 0) = 0`
- `visMaxY = min(1080, 1080) = 1080`
- `visibleH = 1080/1080 * sourceH = sourceH` ← **wrong**
- `offsetY = 0/1080 * sourceH = 0` ← **wrong**

But the **actual clipped triangle** (via `PolygonClipper.clip`) has vertices at approximately `(0, 80)`, `(0, 1080)`, `(1000, 1080)`. The triangle's Y extent is **80 to 1080**, not 0 to 1080.

Correct values should be:
- `visibleH = (1080 - 80) / 1080 * sourceH = 1000/1080 * sourceH`
- `offsetY = 80/1080 * sourceH`

Because `visibleH` is overestimated, `maxEffY = image.size.height - visibleH` is too small. Because `offsetY` is underestimated (0 instead of the actual off-canvas proportion), the effective origin is wrong. Combined, the user cannot pan far enough to reach the image's true top and bottom edges.

## Affected Code Paths

All three call `computeVisibleSourceBounds(destRect: crop.destinationRect, ...)` which only receives the bounding `CGRect`:

| # | Location | File:Line | Impact |
|---|----------|-----------|--------|
| 1 | `applyPan` | `CropManager.swift:169` | Canvas scroll-pan for selected panel |
| 2 | `applyPinch` | `CropManager.swift:228-229` | Zoom anchor point computation for `.path` panels |
| 3 | Overlay drag setup | `PanelCropEditor.swift:95-101` | Detail panel drag gesture clamping |

## The Mismatch

| Component | Shape Used | Result |
|---|---|---|
| Visual overlay (`computeQuadInContainer`) | Clipped polygon via `PolygonClipper` | Correct — shows triangle |
| Rendering (`CollageAssembler.drawPanels`) | `CGPath` clip | Correct — clips to parallelogram |
| Pan boundaries (`computeVisibleSourceBounds`) | Bounding rect ∩ canvas | **Wrong — treats as rectangle** |

## Proposed Fix

For `.path` panels, compute the visible source bounds from the **clipped polygon** rather than the bounding rectangle intersection.

### Approach

1. **New helper** — Add `computeVisibleSourceBounds(destination: PanelGeometry, sourceW: CGFloat, sourceH: CGFloat) -> VisibleSourceBounds` that:
   - For `.rect`: delegates to existing logic (no change)
   - For `.path`: extracts polygon vertices via `PanelGeometry.extractPathPoints(cgPath)`, clips to canvas via `PolygonClipper.clip()`, computes minY/maxX/minY/maxY from the clipped polygon, and derives `offsetX/Y` and `visibleW/H` from the clipped extent

2. **Update callers** — Replace all three call sites to pass `crop.destination` (the `PanelGeometry`) instead of `crop.destinationRect` (the bounding `CGRect`):
   - `CropManager.swift:169` — `applyPan`
   - `CropManager.swift:228-229` — `applyPinch`
   - `PanelCropEditor.swift:95-99` — overlay drag setup

3. **Keep the existing function** — Retain `computeVisibleSourceBounds(destRect:sourceW:sourceH:)` for any code paths that only have a bounding rect, or deprecate it if all callers can be migrated.

### Key Considerations

- **Coordinate space:** `extractPathPoints` returns points in canvas coordinates (same space as the canvas clip rect). The `PolygonClipper` is already used correctly in `PanelCropEditor.computeQuadInContainer` (line 382) with `CGRect(origin: .zero, size: canvasSize)`.
- **Empty clip result:** If `PolygonClipper.clip()` returns an empty array (panel fully off-canvas), fall back to zero visible bounds.
- **Performance:** The clipping is a lightweight Sutherland-Hodgman pass over ≤8 vertices. Called on the main thread during gesture handling — negligible cost.
- **Hexagonal layout:** Edge hexagonal panels may also benefit from this fix, since their bounding rects similarly extend beyond canvas bounds.

## Related Learnings

- `_agent_docs/learnings/off-canvas-panel-drag-clamping.md` — Documents the effective-origin clamping pattern, but assumes rectangular visible bounds. Does not address the polygon-vs-rectangle mismatch.
- `_agent_docs/learnings/polygon-clip-and-vertex-guard-propagation.md` — Documents that "vertex-count assumptions propagate across rendering, hit-testing, overlay, and gesture code." This is the same propagation issue: polygon clipping was applied to rendering and overlay but not to boundary computation.

## Files to Modify

| File | Changes |
|------|---------|
| `CropManager.swift` | Add polygon-aware `computeVisibleSourceBounds`; update `applyPan` and `applyPinch` callers |
| `PanelCropEditor.swift` | Update overlay drag setup to use polygon-aware bounds |
| `CollageMakerTests/` | Add tests for visible bounds computation on diagonal slice edge panels |

## Acceptance Criteria

1. On a Diagonal Slices layout with 3+ images, the leftmost panel can be panned to show the full vertical extent of the assigned image within the visible triangle
2. The rightmost panel behaves symmetrically
3. Middle panels (fully on-canvas) are unaffected — no behavioral regression
4. Rectangular layouts (Grid, Single, etc.) are unaffected
5. Pinch-to-zoom on `.path` panels anchors correctly
6. Overlay drag in the detail panel clamps consistently with canvas scroll-pan

---

**Status:** Open
**Priority:** Medium — functional bug affecting core editing workflow
**Risk:** Low — localized change to one helper function with 3 call sites
