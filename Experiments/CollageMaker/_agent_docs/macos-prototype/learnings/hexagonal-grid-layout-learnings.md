# Hexagonal Grid Layout — Learnings 2026-06-06

**Purpose:** Document pitfalls discovered while implementing `HexagonalLayoutStrategy` for a honeycomb collage layout.

## What Worked

- **Axial coordinate ring traversal** — Proper hex grid placement uses 6 direction vectors walked in perimeter order, not polar angles. For pointy-top hexagons: `(0,-1) → (-1,0) → (-1,+1) → (0,+1) → (+1,0) → (+1,-1)`. Starting position for ring N is `(q=N, r=0)`, walk N steps per direction.

- **`createHexagonPath` returning `(path, boundingRect)` tuple** — Avoids computing bounding rect separately. The 6 vertices are known, so `minX`/`maxX`/`minY`/`maxY` across them is O(1).

## What Didn't Work

- **Polar coordinate ring placement** — The "simpler concentric ring" approach from the plan (`angle += 2π/hexesInRing`, `x = center + radius * cos(angle)`) produces elliptical rings, not a hexagonal grid. At diagonal angles, hexagon centers were ~57px closer than the non-overlap minimum. The hex grid spacing math (`hSpacing = √3·R + S`, `vSpacing = 1.5·R + S·0.5`) is correct for axial coordinates but meaningless when applied to polar angles.

- **Integer division in x-coordinate formula** — `CGFloat(q + r / 2)` truncates odd `r` values. For `r = -1`, `r / 2 = 0` (not `-0.5`), placing hexagons at wrong x-positions. Fix: `(CGFloat(q) + CGFloat(r) / 2.0)`.

- **`R_eff` sizing too aggressive** — Dividing canvas by `3√3·rings` for both axes produced hexagons that were too small. Y-axis is the limiting dimension (`max Δy = 3·rings·R_eff`), X-axis has a different factor (`max Δx = 2√3·rings·R_eff`). Must compute both and take the minimum.

- **`R_eff` only ensures centers fit, not hex extents** — The formula `W / (2√3·rings)` places outermost centers at the canvas edge, but hexagons extend `√3·R` horizontally and `R` vertically beyond their centers. For 7 images, all 6 ring-1 hexagons were partially off-canvas. Correct: `W / (√3·(2·rings+1))`, `H / (3·rings+√3)`.

- **Visual radius formula assumed `2·R_eff` minimum distance** — The formula `R = R_eff - S/2` assumed minimum center-to-center distance is `2·R_eff`, but on an axial pointy-top grid the minimum is `√3·R_eff`. Correct: `R = √3/2 · R_eff - S/2`.

- **Ring traversal nested loop order** — `for step { for direction { ... } }` cycles through all 6 directions `step` times, producing duplicate positions. Correct: `for direction { for step { ... } }` — follow each direction for `step` positions before switching. The outer loop iterates directions, the inner loop walks `ring` steps along that direction.

- **Per-panel rendering clips to rect, not path** — `CollageAssembler.renderPanel()` clips to `destRect` (rectangle only), producing rectangular images for hexagonal panels. SwiftUI `.clipShape(PanelShape(...))` doesn't help because `PanelShape.path(in:)` translates the path to origin-local coordinates, but the view is positioned elsewhere in the parent ZStack via `.position()`, so the clip region misses the image content entirely. **Fix:** Pass `PanelGeometry` to `renderPanel()` and clip at CGContext level using the path translated by `boundingRect.origin`.

## Key Formulas (Pointy-Top Hexagons)

```
// Grid spacing — accounts for hex extent beyond outermost centers
R_eff = min(canvasW / (√3·(2·rings+1)), canvasH / (3·rings+√3))

// Visual hexagon radius (center to vertex)
R = max(√3/2 · R_eff - spacing/2, spacing)  // guard against negative R

// Axial (q, r) → pixel (x, y)
x = centerX + (q + r/2) · √3 · R_eff
y = centerY + r · 1.5 · R_eff

// Bounding rect of hexagon (pointy-top)
frame.width  = √3 · R
frame.height = 2 · R
```

## Test Gotchas

- **Non-overlap threshold** — Minimum center-to-center distance for non-overlapping pointy-top hexagons is `2·R`. Since `frame.width = √3·R`, the threshold is `2·frame.width/√3`, not `frame.width` or `2·frame.width/2`.

- **Spacing affects visual size, not center positions** — In axial grid, center positions depend on `R_eff` (which is computed from canvas size and ring count, independent of `spacing`). The `spacing` parameter only affects the visual hexagon radius `R`. Tests comparing layout spread across different spacing values will fail.

## When This Matters

Any time you need to place regular hexagons in a honeycomb pattern — not just collage layouts, but also UI grids, game boards, or any tiling application. The axial coordinate system is the standard approach; polar coordinates produce visual artifacts.

## Per-Panel Rendering with Path Geometry

When rendering individual panels that have non-rectangular shapes (hexagons, diagonal slices, etc.):

- **Clip at CGContext level, not SwiftUI level** — `renderPanel()` should accept `PanelGeometry` and clip using `context.addPath()` + `context.clip()`. The path must be translated by `-boundingRect.origin` since the rendering context is origin-local.
- **`.clipShape` in SwiftUI has coordinate space issues** — `PanelShape.path(in:)` returns a path translated to origin-local, but `.position()` places the view elsewhere in the parent coordinate space. The clip region won't match the image content.
- **Protocol signature changes cascade** — Adding `geometry` to `renderPanel()` requires updating `PanelRenderer`, `PreviewManager`, `CollageViewModel`, all test mocks, and all test call sites.

## Skill Improvements

### `building-macos-apps/references/graphics/coordinate-systems.md`

Consider adding a "Hexagonal Grid" section with:
1. Axial coordinate system basics (q, r, s where q+r+s=0)
2. Pointy-top vs flat-top orientation differences
3. Ring traversal algorithm with 6 direction vectors
4. Pixel conversion formulas for both orientations

---
**Status:** Complete — hexagonal panels render correctly in layered mode
**Follow-up:** Address remaining visual bugs; Panel Editor hexagonal overlay; continue Round-99 Phase 4+5
