# Shape-Aware Crop Overlay — Remaining Bugs

**Date:** 2026-06-10
**Plan:** `_agent_docs/plans/2026-06-10-shape-aware-crop-overlay.md`
**Status:** Incomplete — two bugs remain

## What Was Done

Step 1 (store geometry in CropInfo), Step 2 (quad overlay rendering), Step 3 (hit testing verification) were implemented. Three additional `CropInfo` creation sites in pan/pinch/overlay paths were fixed to preserve `destination` geometry. Build succeeds, all tests pass.

## Remaining Bugs

### Bug 1: Crop Overlay Does Not Track Canvas Gestures

**Repro:** Select a panel in diagonal slices layout. Open the Panel Editor in the right sidebar. Pan or zoom the image using canvas gestures (scroll-wheel pan or pinch-to-zoom on the preview).

**Expected:** The crop overlay in the Panel Editor updates to reflect the new `sourceRect`.

**Actual:** The overlay remains frozen at its initial position — canvas gesture updates to `cropMap` are not reflected in the Panel Editor.

**Likely cause:** `PanelCropEditor` reads `cropMap` through a computed property `currentCrop` (`viewModel.cropMap[panel.id]`). The `cropMap` getter reads `cropMapVersion` to establish `@Observable` dependency, but the computed property chain `currentCrop` → `cropMap` → `cropManager.cropMap` may break SwiftUI's observation tracking. The `CropPreviewView` receives `crop` as a `let` parameter, so if `PanelCropEditor.body` doesn't re-evaluate, the crop view never sees the updated value.

**Files:** `Views/PanelCropEditor.swift:19-21, 33-39`

### Bug 2: Crop Overlay Does Not Align with Panel Content on Select

**Repro:** Add three images. Select the leftmost panel (trapezoid shape in diagonal slices). Observe the crop overlay in the Panel Editor.

**Expected:** The visible region overlay in the crop editor should highlight the same portion of the image that is visible in the canvas panel.

**Actual:** The overlay appears as a trapezoid shape (correct), but the highlighted region does not match the portion of the image visible in the canvas.

**Likely cause:** The `computeQuadInContainer` function maps panel corners through the image fit transform, but the mapping may not correctly account for how the assembler draws the image. The assembler does:
1. `cropped = cgImage.cropping(to: sourceRect)` — crops the full image to the source rectangle
2. `context.draw(cropped, in: destRect)` — draws the cropped image into the panel's bounding rect

The crop editor displays the full image (not cropped) and overlays a visible region. The quad computation maps panel corners → relative position in bounding rect → source pixel in full image → container coords. This should be correct, but the Y-flip between canvas coords (bottom-left) and image coords (top-left) may be applied incorrectly, or the relative-position mapping may not account for the fact that the cropped image is stretched to fill the bounding rect (not the full image).

**Files:** `Views/PanelCropEditor.swift:346-395`, `Services/CollageAssembler.swift:330-348`

## Files Changed

| File | Changes |
|------|---------|
| `Models/PanelGeometry.swift` | Added `isRect` computed property |
| `Models/ImagePanel.swift` | Already had `destination: PanelGeometry` in `CropInfo` |
| `ViewModel/CropManager.swift` | 7 `CropInfo` init sites use `destination: panel.geometry` / `crop.destination` |
| `ViewModel/CollageViewModel.swift` | Swap and overlay paths use `destination: crop.destination` |
| `Views/PanelCropEditor.swift` | Added `VisibleRegion` enum, quad rendering, `computeQuadInContainer`, `extractPathPoints`, updated `detectDragMode` |

## Next Steps

1. Fix Bug 1: Ensure `PanelCropEditor` observes `cropMap` changes — may need to read `cropMap` directly in `body` or use a version counter
2. Fix Bug 2: Trace the quad computation against the assembler's draw path to find the coordinate mismatch
3. Consider adding a test that verifies quad vertex positions match what the assembler renders
