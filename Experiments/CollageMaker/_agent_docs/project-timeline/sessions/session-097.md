# Session 97 — Diagonal Slices Canvas Coverage

**Date:** 2026-06-10
**Plan:** `_agent_docs/plans/2026-06-09-diagonal-slices-canvas-coverage.md`

## Changes

### L1: Slider Range Adjustment

**File:** `ContentView.swift:206`

Changed diagonal slice angle slider from `5...85` to `0...75` — allows zero-angle vertical strips and caps at 75° to prevent extreme shear offsets.

### L2: Shear-Aware Panel Layout Math

**File:** `Services/LayoutGenerator.swift:240-249`

Replaced fixed-width column layout with shear-aware calculation:

```
shearOffset     = H × tan(θ)
effectiveGutter = gutter × cos²(θ)
totalGutter     = (N - 1) × effectiveGutter
colWidth        = (W + shearOffset - totalGutter) / N
centerOffset    = -shearOffset
panel[i].x      = centerOffset + i × (colWidth + effectiveGutter)
```

**Critical correction:** The plan specified `centerOffset = -shearOffset / 2`, claiming both top and bottom edges would be covered. Visual testing revealed an uncovered triangle at the top-left. The error: at y=H (bottom in CGContext), the sheared left edge of panel 0 is at `centerOffset + H×tan(θ) = -shearOffset/2 + shearOffset = +shearOffset/2` — positive, leaving the bottom-left corner uncovered. Corrected to `centerOffset = -shearOffset`, which places the bottom-left at exactly x=0. The plan's "Review Notes" section actually identified this concern but incorrectly dismissed it by confusing top-left with bottom-left sheared corners.

### L3: Preview Canvas Clipping

**File:** `Views/CollageEditorView.swift:41, 137-139`

Added `canvasPreviewFrame` computation and `.clipShape()` + `.frame()` + `.position()` on the ZStack so that panel overflow is clipped to the canvas preview bounds. Previously, the non-layered preview mode (single CGContext render) implicitly clipped via bitmap size, but layered mode (individual panel NSImages placed in ZStack) had no clipping — panels extending beyond canvas were visible.

### L4: Updated and New Tests

**File:** `CollageMakerTests/LayoutGeneratorTests.swift:237-295`

- `diagonalSlicesPanelsWithinReasonableBounds` — Replaced overlap-ratio check (which failed with centered panels) with simple intersection check
- `diagonalSlicesFullCanvasCoverage` — Verifies panel span covers canvas at 0°, 30°, 45°, 60°, 75° (gutter: 0, checks minX ≤ 0 and maxX ≥ W)
- `diagonalSlicesCornersCovered` — Verifies x/y extent at 45° covers full canvas
- `diagonalSlicesZeroAngleVerticalStrips` — Verifies 0° produces strips from x=0 to x=canvasWidth
- `diagonalSlices75DegreesCoversCanvas` — Verifies coverage at max angle with 2, 3, 4 panels

## Files Changed

| File | Changes |
|------|---------|
| `ContentView.swift` | Slider range `5...85` → `0...75` |
| `Services/LayoutGenerator.swift` | Shear-aware width, cos² gutter, `centerOffset = -shearOffset` |
| `Views/CollageEditorView.swift` | Canvas preview frame clipping on ZStack |
| `CollageMakerTests/LayoutGeneratorTests.swift` | Updated bounds test, added 4 coverage tests |

## Verification

- `xcodebuild test ... -only-testing:CollageMakerTests` — All tests passed
- Visual check: 2-4 images, diagonal slices, slider 0°→75°, panels cover full preview, overflow clipped at edges
- Build and launch successful

## Key Decisions

- **`centerOffset = -shearOffset`** — Full shear displacement as offset ensures bottom-left corner (y=H in CGContext) of panel 0 starts at x=0. Top-left (y=0, no shear) starts at `-shearOffset`, providing symmetric overflow on the left. Right side overflows by `shearOffset` at the top.
- **Canvas clipping on ZStack** — Rather than constraining panel bounding rects, clip at the display boundary. This matches the non-layered mode behavior (CGContext bitmap edge) and the export behavior (CGContext at canvas size).
- **cos² gutter scaling** — Adopted from plan without change. Compresses gutters faster than linear cos: 50% at 45°, 7% at 75°. Visually appropriate for steep angles where diagonal gaps would otherwise dominate.

## New Learnings

- **Shear transform coverage math** — For a rightward shear (`x' = x + y·tan(θ)`), the bottom edge (y=H) shifts right by `H·tan(θ)`. To cover the bottom-left corner (x=0), the unsheared left edge must start at `-H·tan(θ)`, not `-H·tan(θ)/2`. The `/2` formula only works if you want symmetric overflow at both top and bottom, but shear displacement is zero at top and maximum at bottom, so symmetric overflow is impossible.
- **CGContext implicit clipping** — A CGContext created at size `S` silently discards drawing outside `[0, S]`. This means the non-layered preview (rendered into a scaled CGContext) clips to canvas bounds automatically. Layered mode (individual per-panel NSImages placed in SwiftUI ZStack) has no such clipping — overflow panels render visibly.
- **SwiftUI ZStack canvas clipping** — Adding `.clipShape(Rectangle())` + `.frame()` + `.position()` to a ZStack inside a GeometryReader clips content to the fitted canvas area (accounting for letterboxing).

---
**Status:** Complete
**Follow-up:** None
