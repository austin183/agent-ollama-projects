# Diagonal Slices Canvas Coverage Plan

**Date:** 2026-06-09
**Source Request:** `_agent_docs/change-requests/round-99.1.md`

## Overview

When the diagonal slice angle is greater than 0°, the sheared parallelogram panels shift rightward and overflow off the canvas. The user wants panels to always fully cover the preview image area, with overflow clipped at canvas edges.

**Core idea:** Make each panel wider to absorb the shear displacement, center the group, and let the existing rendering pipeline clip to canvas bounds.

---

## Problem

In `DiagonalSlicesLayoutStrategy.generate` (LayoutGenerator.swift:229-274), columns are laid out within `[0, canvasWidth]`, then sheared by `x' = x + y * tan(angle)`. At 45° on a 1920×1080 canvas, the top of each panel shifts right by 1080px. The rightmost panels overflow completely off-canvas, and the left side of the canvas is partially uncovered.

---

## Solution

### Math

For `N` panels, canvas `W×H`, angle `θ`, shear `s = tan(θ)`:

```
shearOffset     = H × s
effectiveGutter = gutter × cos²(θ)
totalGutter     = (N - 1) × effectiveGutter
colWidth        = (W + shearOffset - totalGutter) / N
centerOffset    = -shearOffset / 2

panel[i].x = centerOffset + i × (colWidth + effectiveGutter)
```

**Behavior at boundaries:**
- **θ = 0°:** `s=0`, `shearOffset=0`, `effectiveGutter=gutter`, `centerOffset=0` — identical to current behavior.
- **θ = 45°:** `s=1.0`, `shearOffset=1080`, `effectiveGutter≈0.5×gutter`, panels are wider, centered.
- **θ = 75°:** `s≈3.73`, `shearOffset≈4030`, `effectiveGutter≈0.07×gutter`, very wide panels, minimal gutters.

### Why `cos²` for gutter scaling

Squared cosine compresses faster than linear: at 45° the gutter is 50% (vs 70% linear), at 75° it's 7% (vs 26%). At steep angles the diagonal gutter gaps would otherwise dominate the visual, so the squared scaling keeps them subtle.

---

## Changes

### 1. `ContentView.swift` — Slider range (line 206)

```swift
// Before:
Slider(value: $viewModel.diagonalSliceAngle, in: 5...85, step: 1)

// After:
Slider(value: $viewModel.diagonalSliceAngle, in: 0...75, step: 1)
```

### 2. `LayoutGenerator.swift` — `DiagonalSlicesLayoutStrategy.generate` (lines 240-246)

Replace the column width and x-position calculation:

```swift
// Current (lines 240-246):
let totalGutter = CGFloat(numImages - 1) * gutter
let colWidth = (canvasSize.width - totalGutter) / CGFloat(numImages)

for i in 0..<numImages {
    let unshearedX = CGFloat(i) * (colWidth + gutter)
    // ...
}

// New:
let shearOffset = canvasSize.height * shear
let effectiveGutter = gutter * cos(radians) * cos(radians)
let totalGutter = CGFloat(numImages - 1) * effectiveGutter
let colWidth = (canvasSize.width + shearOffset - totalGutter) / CGFloat(numImages)
let centerOffset = -shearOffset / 2.0

for i in 0..<numImages {
    let unshearedX = centerOffset + CGFloat(i) * (colWidth + effectiveGutter)
    // ... rest of shearing logic (lines 248-270) unchanged
}
```

The single-image case (lines 232-235) returns a full-canvas rect — no change needed.

### 3. `LayoutGeneratorTests.swift` — Tests

**Update existing:**
- `diagonalSlicesPanelsWithinReasonableBounds` (line 237): Currently checks bounding rect overlap ratio > 0.5, which edge panels may not satisfy after centering. Replace with point-in-path canvas coverage check.

**Add new:**
- `diagonalSlicesFullCanvasCoverage` — sample a 10×10 grid of points across the canvas, assert each point is contained by at least one panel's CGPath. Test at angles 0°, 30°, 45°, 60°, 75°.
- `diagonalSlicesCornersCovered` — verify all 4 canvas corners fall inside some panel's path at 45°.
- `diagonalSlicesZeroAngleVerticalStrips` — 0° produces panels where minX=0 and maxX=canvasWidth (extends existing `diagonalSlicesZeroAngleProducesVerticalStrips`).
- `diagonalSlices75DegreesCoversCanvas` — point-in-path coverage at max angle with 2, 3, and 4 panels.

**Keep unchanged** (no bounding rect position assumptions):
- `diagonalSlicesSingleImage`, `diagonalSlicesAllImageIndicesUnique`, `diagonalSlicesWithCustomOrder`, `diagonalSlicesProducesPathGeometry`, `diagonalSlicesTwoImages`, `diagonalSlicesNegativeAngle`, `diagonalSlicesLargeAngle`

### 4. No other changes needed

The rendering pipeline (`CollageAssembler.drawPanels`) draws into a CGContext sized to `canvasSize` — content outside `[0, canvasSize]` is silently clipped. The SwiftUI preview (`CollageEditorView`) displays the preview image with `.frame(width: geometry.size.width, height: geometry.size.height)` which clips to the GeometryReader. Panel hit testing uses `path.contains()` against tap locations (always inside the canvas), so extended bounding rects don't cause false positives.

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Very high angles produce extremely wide panels | 75° max, `cos²(75°) ≈ 0.07` keeps gutters minimal. Panels are wide but visually this is the desired "almost horizontal" look. |
| `colWidth` goes negative at extreme angles | At 75° with 2 panels: `colWidth = (1920 + 4030 - 0.14) / 2 ≈ 2975px` — positive and fine. Would only go negative if angle > ~86° on 16:9 canvas. |
| Layered mode panel overlays overflow | Clipped by GeometryReader container. No visual issue. |
| Negative angle support | The slider is 0–75, but the layout strategy still accepts negative angles. `cos²(-θ) = cos²(θ)` and `tan(-θ) = -tan(θ)`, so panels shift left instead of right, and centering still works. The existing `diagonalSlicesNegativeAngle` test should still pass. |

---

## Review Notes

An external review flagged a concern with `centerOffset = -shearOffset/2`, claiming the bottom-left canvas corner would be uncovered. The concern was traced to confusing the **top-left** sheared corner (`centerOffset + H*s`) with the **bottom-left** (`centerOffset`, y=0, no shear applied). Verified: at every y-level, the panel span `[-shearOffset/2 + y*s, canvasWidth + shearOffset/2 + y*s]` fully contains `[0, canvasWidth]`. The proposed correction (`centerOffset = -shearOffset`) would produce asymmetric overflow (left: `-shearOffset`, right: `canvasWidth + 2*shearOffset`). Original calculation stands.

---

## Verification

1. **Unit tests pass** — run `xcodebuild test ... -only-testing:CollageMakerTests`
2. **Visual check** — launch app, add 2-4 images, set diagonal slices, sweep slider 0°→75°:
   - Panels always cover the full preview area
   - No background visible between panels (except in gutter gaps)
   - No panels spill over the preview window edges
3. **Export check** — export a collage at 45°, verify output image has no empty edges

---

**Status:** Planned
**Follow-up:** Implement after plan review
