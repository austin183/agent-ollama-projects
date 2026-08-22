# 2026-06-10 Shape-Aware Crop Overlay

**Date:** 2026-06-10
**Goal:** Make the crop overlay and canvas hit testing match the actual panel geometry (trapezoid) for diagonal slices and other non-rectangular layouts.
**Rendering approach:** Keep current clip-to-path. Do NOT shear the image.

---

## Execution Order

### Step 1 — Store Geometry in CropInfo

**What:** `CropManager` currently creates `CropInfo` with `destinationRect: panel.frame` (bounding rect), losing the actual `PanelGeometry`. Store the real geometry so downstream code can access it.

**Files:** `CropManager.swift`, `CollageViewModel.swift`

**Changes:**

1. `CropManager.computeInitialCrops` (line 72-76):
   - Change `destinationRect: panel.frame` → `destination: panel.geometry`

2. `CropManager.computeCropsFromSaliency` (line 100-104):
   - Change `destinationRect: panel.frame` → `destination: panel.geometry`

3. `CropManager.applyCropsBySlot` (line 119):
   - Change `destinationRect: panel.frame` → `destination: panel.geometry`

4. `CollageViewModel` swap logic (line 624-625):
   - Change `destinationRect: cropA.destinationRect` → `destination: cropA.destination`
   - Change `destinationRect: cropB.destinationRect` → `destination: cropB.destination`

**Verification:** Build succeeds, no visual change. Existing tests pass.

---

### Step 2 — Quad Crop Overlay in Panel Editor

**What:** The crop preview overlay shows a rectangular visible region. For non-rectangular panels (trapezoid from diagonal slices, hexagon from hex layout), show the actual visible region shape.

**Files:** `PanelCropEditor.swift`

**Changes:**

1. **Pass `panel.geometry` to `CropPreviewView`** (line 32-37):
   - Add `panelGeometry: panel.geometry` parameter

2. **`CropPreviewView` — accept geometry** (line 289-307):
   - Add `let panelGeometry: PanelGeometry` property
   - For `.rect`: keep existing behavior
   - For `.path`: compute visible quad and render quad-based overlay

3. **Compute visible quad in container coordinates:**
   - Extract the 4 corner points from the panel's `CGPath`
   - The panel corners are in canvas coordinates (CGContext, origin=bottom-left)
   - Map them through the image fit transform: for each corner, compute what source-image pixel it corresponds to, then map that pixel to the container's fitted-image display coordinates
   - The fit transform is: `(fittedSize, fitOffset) = FitMath.fit(imageSize, into: container)`, then `displayX = fitOffset.x + sourceX / imageW * fittedW`, `displayY = fitOffset.y + sourceY / imageH * fittedH`

4. **Replace rectangular eoFill cutout with quad cutout** (line 312-317):
   - Instead of `path.addRect(visible)`, build a `Path` from the 4 quad vertices
   - The eoFill pattern still works: outer container rect + inner quad

5. **Replace corner handles with quad-vertex handles** (line 329-339):
   - Position the 4 orange resize handles at the quad vertices instead of rect corners

6. **Update `detectDragMode`** (line 348-391):
   - For quad: hit-test against quad vertices (distance threshold) and quad interior (`Path(quad).contains()`)
   - For rect: keep existing logic

**Verification:** Crop preview for diagonal slice panels shows trapezoid-shaped visible region with handles at the 4 trapezoid vertices. Rectangular panels are unchanged.

---

### Step 3 — Canvas Hit Testing for Trapezoid Extents

**What:** Verify that canvas hit testing correctly handles the trapezoid panel shapes. The `panelFrames` are bounding rects, and `hitTestPanel` refines with `cgPath.contains()`. Need to verify coordinate conversion is correct.

**Files:** `CollageEditorView.swift`, `CropManager.swift`

**Changes (if needed):**

1. **Verify `panelFrames` bounding rect coverage:** For diagonal slices, `panel.frame` is `geometry.boundingRect`, which is the min/max of all 4 trapezoid corners. This bounding rect already encompasses the full trapezoid extent, so `frame.contains(location)` is a correct first filter.

2. **Verify `screenToCanvasPoint`** (`CropManager.swift:299-307`):
   - This converts SwiftUI tap coordinates (origin=top-left) to CGContext coordinates (origin=bottom-left)
   - The Y-flip is done on line 304: `canvasY = canvasSize.height - (screenPoint.y - offset.y) / fittedH * canvasH`
   - Verify this matches the coordinate system used by the panel's `CGPath` (which is built in canvas coords, origin=bottom-left)

3. **Verify `hitTestPanel`** (`CropManager.swift:265-291`):
   - The `cgPath.contains(canvasPoint)` call tests against the path in canvas coordinates
   - The path was built with corners in canvas coordinates (origin=bottom-left)
   - If the coordinate conversion is correct, this should work

4. **If there are gaps:** The ZStack clipping to `canvasPreviewFrame` means taps outside the canvas preview frame don't reach gesture handlers. This is intentional. But if trapezoid corners extend beyond the canvas bounds (they shouldn't with the coverage fix), those corners would be unclickable.

**Verification:** Click and scroll-pan on trapezoid panel regions near the sheared edges. All regions within the canvas should respond.

---

## Summary of Touch Points

| File | Step | Lines |
|------|------|-------|
| `CropManager.swift` | 1 | 72-76, 100-104, 119 |
| `CollageViewModel.swift` | 1 | 624-625 |
| `PanelCropEditor.swift` | 2 | 32-37, 289-391 |
| `CollageEditorView.swift` | 3 | 336-343, 35-41 |
| `CropManager.swift` | 3 | 265-307 |

## Risks

| Risk | Mitigation |
|------|-----------|
| Coordinate system mismatch in quad computation | Reference existing coordinate docs, add debug logging |
| `detectDragMode` quad hit-testing edge cases | Use `Path.contains()` for interior test, distance threshold for vertices |
| Backward compatibility with rect panels | All changes are behind `switch geometry { case .rect: ... case .path: ... }` |
