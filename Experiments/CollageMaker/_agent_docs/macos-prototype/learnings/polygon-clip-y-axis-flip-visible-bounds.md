# Polygon Clip Y-Axis Flip in Visible Bounds — Learnings 2026-06-18

**Purpose:** Document the Y-axis flip interaction between canvas coordinates, source image coordinates, and the `offCanvasTop` formula when computing visible bounds from a clipped polygon.

## What Worked

- **Polygon-aware visible bounds** — For `.path` panels whose parallelogram extends beyond the canvas, computing visible source bounds from the clipped polygon (via `PolygonClipper`) produces accurate pan boundaries. The clipped polygon's AABB gives the correct visible extent, unlike the bounding rectangle intersection which overestimates.

- **Canvas-to-source Y-axis flip in `offCanvasTop`** — Canvas coordinates are bottom-left origin; source image coordinates are top-left origin. The rendering pipeline flips Y: canvas bottom maps to source top, canvas top maps to source bottom. The clamping logic treats `offsetY` as "pixels to skip at the source top." Therefore, `offCanvasTop` must measure the **canvas top clip** (`boundingRect.maxY - clippedMaxY`), not the canvas bottom clip (`clippedMinY - boundingRect.minY`).

  ```swift
  // WRONG — measures canvas bottom clip, which maps to source top after Y-flip,
  // but the clamping logic already handles source-top clamping via maxEffY.
  // This produces offsetY that allows the source origin to go negative,
  // exposing pixels that should remain hidden.
  let offCanvasTop = Swift.max(0, clippedMinY - boundingRect.minY)

  // RIGHT — measures canvas top clip, which maps to source bottom.
  // The clamping logic treats offsetY as "source-top offset," and the
  // canvas-to-source Y-flip means canvas top = source bottom.
  let offCanvasTop = Swift.max(0, boundingRect.maxY - clippedMaxY)
  ```

## What Didn't Work / Gaps

- **Bottom-clip formula for `offCanvasTop`** — The initial implementation used `clippedMinY - boundingRect.minY` (canvas bottom clip), which is intuitive for a bottom-left coordinate system. But the clamping logic expects `offsetY` to represent the source-top offset. After the Y-flip, the canvas bottom clip corresponds to source-top pixels that are already handled by the `maxEffY` bound. Using the bottom clip produced an `offsetY` that allowed the source origin to go negative, exposing the image top through the crop overlay. **Lesson:** When bridging two coordinate systems with opposite Y directions, trace the value through the flip to find which direction the consumer expects.

## Key Pattern: Y-Flip-Aware Off-Canvas Measurement

When computing visible bounds from a polygon clipped to canvas bounds:

1. Extract polygon vertices in canvas coordinates (bottom-left origin)
2. Clip to canvas rectangle via `PolygonClipper`
3. Compute AABB of clipped polygon: `clippedMinX/Y`, `clippedMaxX/Y`
4. Measure off-canvas portions:
   - X: `offCanvasLeft = max(0, clippedMinX - boundingRect.minX)` — no flip needed
   - Y: `offCanvasTop = max(0, boundingRect.maxY - clippedMaxY)` — **canvas top, not bottom**
5. Scale by bounding rect dimensions to get source-space offsets

**When to use:** Any time you compute visible source bounds from a polygon that may extend beyond canvas bounds, where the source image uses top-left coordinates and the canvas uses bottom-left coordinates.

**Coordinate space matters:** The polygon vertices must be in canvas coordinates (same space as the canvas clip rect). The `boundingRect` is also in canvas coordinates. The resulting `offsetX/Y` and `visibleW/H` are in source image coordinates (top-left origin).

## Related Learnings

- `off-canvas-panel-drag-clamping.md` — Documents the effective-origin clamping pattern and rect-based visible bounds. This learning extends it to polygon clipping with Y-axis awareness.
- `polygon-clip-and-vertex-guard-propagation.md` — Documents Sutherland-Hodgman clipping and vertex guard propagation. This learning addresses the coordinate space interaction when using clip results for boundary computation.

---
**Status:** Closed
**Follow-up:** None
