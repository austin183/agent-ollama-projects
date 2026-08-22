# Fix Saliency Face Centering — Phase 1: Diagnostics

**Date:** 2026-06-20
**Change Request:** round-103
**Status:** pending

## Problem

Faces are misaligned in cropped panels. The `SaliencyResult.cropOrigin` method swaps x/y for portrait images as a workaround for a perceived `VNImageRequestHandler` buffer rotation. Two contributing factors:

1. **Portrait swap** (`Models/SaliencyResult.swift:26-29`) — swaps coordinates when `imageSize.width < imageSize.height`, likely an over-correction
2. **Hardcoded orientation** (`Services/SaliencyAnalyzer.swift:43`) — passes `orientation: .up` instead of `cgImage.imageOrientation`, so Vision ignores EXIF rotation tags

The test images in `TestImages/SaliencyFaces/` have no EXIF tags (all orientation=1), so for those images the bug is purely the portrait swap. Real-world phone photos with EXIF tags compound the problem.

## Root Cause Theory

The portrait swap mirrors the crop center across the diagonal for all portrait images. Since `SaliencyAnalyzer` already converts Vision normalized coordinates to CG pixel space using the image's natural dimensions, the swap displaces the center — it was likely a workaround for some earlier coordinate confusion.

## Phase 1: Diagnostic Tooling (Verify Before Fixing)

### Task 1: Enhanced Logging in `SaliencyAnalyzer.swift`

Add `logger.debug` at 4 points in `analyze()`:

| Point | Line | Content |
|-------|------|---------|
| Entry | ~36 | Image dimensions + EXIF orientation tag |
| Faces | ~50 | Per-face: Vision `boundingBox`, converted CG pixel point, confidence |
| Saliency | ~58 | Salient object count |
| Result | ~93 | Final centroid, radius, confidence |

Example log output:
```
Analyzing image: 4032x3024 orientation=left
  Face #0: box=(0.32, 0.25, 0.18, 0.22) cg=(1537, 758) conf=0.95
  Salient objects: 2
  Result: center=(1537, 758) radius=412 conf=0.95
```

### Task 2: Debug Overlay in `CropPreviewView`

**Goal:** Visualize the saliency center and source rect on the crop preview so we can see if they align with the face.

**A. `PanelCropEditor.swift`** — add computed property to fetch saliency result:
```swift
private var currentSaliency: SaliencyResult? {
    guard let idx = viewModel.getEffectiveImageIndex(for: panel.id) else { return nil }
    return viewModel.imageCoordinator.saliencyResults[idx]
}
```

Pass `currentSaliency` into `CropPreviewView`.

**B. `CropPreviewView`** — add optional `saliency: SaliencyResult?` parameter. Inside `body`, after the existing dim overlay:

```swift
#if DEBUG
if let saliency {
    saliencyDebugOverlay(saliency: saliency)
}
#endif
```

The overlay maps `SaliencyResult.center` (CG pixel space, top-left origin) to the SwiftUI preview container using the same `FitMath.fit()` logic already used by `computeQuadInContainer` (line 361):

```swift
let (fittedSize, fitOffset) = FitMath.fit(imageSize, into: containerSize)
let previewCenter = CGPoint(
    x: fitOffset.x + center.x / imageSize.width * fittedSize.width,
    y: fitOffset.y + center.y / imageSize.height * fittedSize.height
)
```

Draw:
- Red circle (radius 6) at `previewCenter` — the saliency center
- Green dashed circle at `previewCenter` with `saliency.radius` scaled to preview — the saliency radius

**C. `CollageViewModel`** — verify `imageCoordinator` is accessible. It's already wired at line 401 (`saliencyAnalyzer: SaliencyAnalyzer()`), and `saliencyResults` is stored on `ImageCoordinator` (line 39). The VM references it at line 529.

### Task 3: Test Image Fixtures

Copy images from `TestImages/SaliencyFaces/` into `CollageMaker/CollageMakerTests/Resources/`:

| File | Dimensions | Notes |
|------|-----------|-------|
| `20200813_094739.jpg` | 2640x1980 | Landscape, no EXIF |
| `20211125_100710.jpg` | 2640x1980 | Landscape, no EXIF |
| `20220808_145050.jpg` | 2640x1980 | Landscape, no EXIF |
| `20230109_104134.jpg` | 1164x1959 | **Portrait**, no EXIF — key test case |
| `20250604_172706.jpg` | 3264x1836 | Landscape, no EXIF |

Ensure the Xcode project includes the new `Resources` folder in `CollageMakerTests`.

### Task 4: Build, Run, Inspect

```bash
bash script/build_and_run.sh --logs
```

1. Load the test images via the app
2. Select each panel in the crop editor to see the debug overlay
3. Observe the log output for face detection results and computed centroids
4. Check if the red dot aligns with the face on each image

### Expected Observations

**Portrait image** (`20230109_104134.jpg`):
- If the portrait swap is the bug, the red dot will appear in the wrong quadrant (mirrored across the diagonal)
- Logs will show face detection succeeded (faces found with good confidence)
- The `cropOrigin` will be based on swapped coordinates

**Landscape images**:
- The swap won't trigger (`width > height`), so the red dot should align with the face
- If it doesn't, the bug is elsewhere (coordinate conversion or rendering)

## Phase 2: Tests (After Diagnostics Confirm the Bug)

### Task 5: Fixture-Based Accuracy Tests

In `SaliencyAnalyzerTests.swift`, add a `@Suite(.serialized)` that:
- Loads each fixture image from `Bundle.module.url(forResource:withExtension:)`
- Calls `analyze(_:)` on the CGImage
- Asserts face detection returned at least 1 result for face images
- Asserts `center` falls within a 10% tolerance region of the known face location

### Task 6: Portrait Swap Unit Test

In `SaliencyResultTests.swift`, add a test that:
- Creates a `SaliencyResult` with a known center (e.g., top-right quadrant)
- Calls `cropOrigin` with a portrait `imageSize`
- Verifies the origin is NOT swapped (after fix) vs IS swapped (before fix)

## Phase 3: Fix (After Diagnostics Confirm Root Cause)

### Task 7: Remove Portrait Swap

Delete lines 26-29 from `Models/SaliencyResult.swift`:
```swift
// DELETE
if imageSize.width < imageSize.height {
    originX = center.y - halfW
    originY = center.x - halfH
}
```

### Task 8: Fix EXIF Orientation

Change line 43 in `Services/SaliencyAnalyzer.swift`:
```swift
// Before
orientation: CGImagePropertyOrientation.up
// After
orientation: cgImage.imageOrientation
```

### Task 9: Consolidate Coordinate Conversion

Either:
- Use `CropManager.visionToCG` in `SaliencyAnalyzer` (single source of truth), OR
- Document the inline approach in `SaliencyAnalyzer` and remove the unused `CropManager.applyPortraitSwap` / `CropManager.visionToCGWithPortrait` methods

## Files Modified

| File | Change |
|------|--------|
| `Services/SaliencyAnalyzer.swift` | Enhanced logging |
| `Views/PanelCropEditor.swift` | Pass saliency to preview |
| `Views/PanelCropEditor.swift` | `CropPreviewView` debug overlay |
| `CollageMakerTests/Resources/` | New directory with test images |
| `CollageMakerTests/SaliencyAnalyzerTests.swift` | Fixture-based tests (Phase 2) |
| `CollageMakerTests/SaliencyResultTests.swift` | Portrait swap test (Phase 2) |
| `Models/SaliencyResult.swift` | Remove swap (Phase 3) |
| `Services/SaliencyAnalyzer.swift` | Fix orientation (Phase 3) |
| `ViewModel/CropManager.swift` | Remove unused methods (Phase 3) |

## Success Criteria

- Debug overlay confirms saliency center position visually
- Logs show face detection results and coordinate chain
- We can identify whether the portrait swap is the root cause
- Portrait images show misalignment; landscape images work correctly
