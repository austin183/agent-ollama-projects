# Polygon Clipping & Vertex Guard Propagation — Learnings 2026-06-11

**Purpose:** Document learnings from fixing crop overlay bugs in non-rectangular panel layouts (diagonal slices, hexagonal).

## What Worked

- **Sutherland-Hodgman polygon clipping** — A general-purpose algorithm for clipping an arbitrary polygon to a rectangular clip region. Each edge of the clip rectangle is processed sequentially, producing a new polygon that is the intersection of the input polygon and the half-plane defined by that edge. Works for any convex or concave input polygon with 3+ vertices.

- **Vertex-agnostic coordinate mapping** — The `corners.map { corner in ... }` loop in `computeQuadInContainer` already handled any number of vertices. The `guard corners.count == 4` was an unnecessary constraint inherited from when only parallelograms were expected.

- **Path-based containment for N vertices** — `Path` + `p.addLine(to:)` in a loop + `p.contains(point)` works for any polygon. No need for special-case quad vs hex logic.

## What Didn't Work / Gaps

- **Vertex-count guard propagation** — The `guard corners.count == 4` guard appeared in **3 places**: two `computeQuadInContainer` methods (rendering) and one `detectDragMode` (gesture hit-testing). When the rendering guards were removed in round 99.3, the gesture guard was missed, causing hexagonal panels to render correctly but reject all click/drag gestures. **Lesson:** vertex-count assumptions propagate across rendering, hit-testing, overlay, and gesture code. Search for the pattern across all files, not just the one mentioned in the plan.

- **Container clip ≠ canvas clip** — Adding `.clipped()` to the overlay ZStack clips to the SwiftUI view's frame (the GeometryReader container), but the parallelogram extends beyond the **canvas** within the container. When the canvas is letterboxed inside the container, the clipping rectangles differ. The fix requires clipping polygon vertices to canvas bounds **before** the coordinate transform, not clipping the rendered view.

- **Canvas bounds in panel coordinates** — To clip a parallelogram to canvas bounds, the clip rectangle must be expressed in the same coordinate space as the polygon vertices (panel coordinates). The canvas bounds in panel coordinates are:
  ```
  left = -panelFrame.origin.x
  top = -panelFrame.origin.y
  right = canvasWidth - panelFrame.origin.x
  bottom = canvasHeight - panelFrame.origin.y
  ```
  This is non-intuitive: panels whose frames start at negative offsets (outside the canvas) have positive clip bounds.

## Key Pattern: Sutherland-Hodgman Polygon Clipping

```swift
static func clipPolygon(_ subject: [CGPoint], to clipRect: CGRect) -> [CGPoint] {
    // Process each clip edge in order: left, right, top, bottom
    var result = subject
    result = clipEdgeCorrect(result, with: .left(clipRect.minX))
    result = clipEdgeCorrect(result, with: .right(clipRect.maxX))
    result = clipEdgeCorrect(result, with: .top(clipRect.minY))
    result = clipEdgeCorrect(result, with: .bottom(clipRect.maxY))
    return result
}

// Each edge clips the polygon to the "inside" half-plane
func clipEdgeCorrect(_ input: [CGPoint], with respectTo: ClipEdge) -> [CGPoint] {
    var prev = input[input.count - 1]  // wrap around
    var prevInside = respectTo.isInside(prev)
    for curr in input {
        let currInside = respectTo.isInside(curr)
        if currInside {
            if !prevInside {
                output.append(respectTo.intersection(from: prev, to: curr))
            }
            output.append(curr)
        } else if prevInside {
            output.append(respectTo.intersection(from: prev, to: curr))
        }
        prev = curr
        prevInside = currInside
    }
    return output
}
```

**When to use:** When a polygon (parallelogram, hexagon, arbitrary shape) needs to be clipped to a rectangular boundary before rendering or coordinate transformation. This is the right tool when SwiftUI's `.clipped()` clips to the wrong rectangle (container vs canvas).

**Coordinate space matters:** The polygon vertices and clip rectangle must be in the **same coordinate space**. If the polygon is in panel coordinates (relative to panel bounding box origin), the clip rectangle must also be in panel coordinates — not canvas or container coordinates.

## Key Pattern: Vertex-Count Guard Audit

When a guard like `guard vertices.count == N` exists in one place, search for the same pattern across:
1. **Rendering code** — `computeQuadInContainer`, `dimOverlay`, `strokeVisibleRegion`
2. **Hit-testing code** — `detectDragMode`, `hitTestPanel`
3. **Handle/gesture code** — `visibleRegionHandles`, corner distance checks
4. **Serialization** — Codable encode/decode for vertex arrays

A vertex-count guard in rendering does not imply the same constraint applies to hit-testing. A hex panel should render as a hexagon AND accept drags inside the hexagon, even if corner resize handles are only meaningful for quads.

## Skill Improvements

### `building-macos-apps/references/graphics/coordinate-systems.md`

Add a section on "Polygon Clipping to Canvas Bounds" documenting:
- The Sutherland-Hodgman algorithm for arbitrary polygon clipping
- The coordinate space requirement (polygon vertices and clip rect must match)
- The canvas-in-panel-coordinates formula: `-panelFrame.origin` offset

### `building-macos-apps/SKILL.md` — Debugging Strategy

Add item: "When fixing a vertex-count guard in rendering code, search for the same guard pattern in hit-testing, gesture handling, and overlay code. A `guard vertices.count == 4` that breaks rendering will also break gesture hit-testing for non-quad polygons."

---
**Status:** Closed
**Follow-up:** Round 99.4 — remaining diagonal left panel hourglass and hexagonal corner resize
