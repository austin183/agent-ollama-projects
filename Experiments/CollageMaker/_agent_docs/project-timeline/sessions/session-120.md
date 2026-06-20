# Session 120 — Round 103: Saliency Face Centering Diagnostics (Phase 1)

**Date:** 2026-06-20
**Change Request:** round-103.md
**Plan:** 2026-06-20-round-103-saliency-diagnostics.md

## Summary

Implemented Phase 1 diagnostic tooling to investigate why faces are misaligned in cropped panels. Visual diagnostics confirmed the bug: the saliency center is computed correctly, but `SaliencyResult.cropOrigin` applies a portrait swap that displaces the crop for portrait images.

## Diagnostic Results

**Observation:** User loaded a portrait image with a face. The red debug dot (saliency center) aligned perfectly with the face in the crop preview. But the actual cropped area was above the face — the face did not appear in the panel.

**Conclusion:** The `SaliencyAnalyzer` computes the correct center point. The bug is in `SaliencyResult.cropOrigin` (lines 26-29) which swaps x/y for portrait images. This swap mirrors the crop origin across the diagonal, displacing it from the correct center.

**EXIF note:** `CGImage` extracted from `NSImage` has no EXIF orientation tag. The `SaliencyAnalyzer` hardcodes `orientation: .up` — there is no better value available. For our test images (no EXIF), this is correct. For real-world phone photos with EXIF rotation, the EXIF is already baked into the `CGImage` pixel dimensions by `NSImage`, so `.up` is the right choice.

## Changes

### Enhanced Logging — `Services/SaliencyAnalyzer.swift`

Added 4 `logger.debug` points in `analyze()`:
- Image dimensions + orientation note (line 38)
- Face count + per-face bounding boxes with CG pixel conversion (lines 54-62)
- Salient object count (line 64)
- Final centroid, radius, confidence (lines 107-110)

### Debug Overlay — `Views/PanelCropEditor.swift`

- `currentSaliency` computed property on `PanelCropEditor` (lines 24-27)
- `saliency: SaliencyResult?` parameter added to `CropPreviewView` (line 260)
- `#if DEBUG` overlay method `saliencyDebugOverlay` (lines 370-392):
  - Red dot (8px) at saliency center mapped to preview space
  - Green circle at saliency radius scaled to preview
  - Uses `FitMath.fit()` for coordinate mapping

### Test Image Fixtures

Copied 5 images from `TestImages/SaliencyFaces/` to `CollageMakerTests/Resources/`:
- 3 landscape (2640x1980), 1 portrait (1164x1959), 1 landscape (3264x1836)
- No EXIF orientation tags on any image

## Verification

- Build: zero errors, zero warnings
- App launches, debug overlay renders correctly on crop preview

## Next Steps

Phase 3: Remove the portrait swap from `SaliencyResult.cropOrigin` (lines 26-29). The diagnostic confirmed this is the root cause.
