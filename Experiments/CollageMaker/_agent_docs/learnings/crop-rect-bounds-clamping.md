# Crop Rect Bounds Clamping with CGRect.intersection

**Date:** 2026-06-20
**Session:** 121

## What Happened

After removing the portrait swap from `SaliencyResult.cropOrigin`, the crop overlay in the Panel Editor appeared to expand outside the image bounds. The issue only manifested with small test images (268x338) where the panel size exceeded the image dimensions.

## Root Cause

`CropManager.computeCropsFromSaliency` creates a source rect using `CGRect(origin: origin, size: panelSize)`. When `panelSize > imageSize`, the rect extends beyond the image. The `cropOrigin` clamping (`max(0, min(origin, imageSize - cropSize))`) only constrains the origin to `0` when `cropSize > imageSize`, leaving the rect oversized.

## Fix

```swift
var rect = CGRect(origin: origin, size: panelSize)
rect = rect.intersection(CGRect(origin: .zero, size: image.size))
sourceRect = rect
```

`CGRect.intersection` clamps the rect to image bounds. If the rect is fully within bounds, it's unchanged. If it extends beyond, the intersection shrinks it to fit.

## Learning

**When constructing a crop/source rect from a panel size, always clamp to image bounds.** Panel sizes are determined by layout math and canvas dimensions, not by the image. A large panel on a small image will produce an oversized source rect.

**Use `CGRect.intersection` for simple bounds clamping.** It handles all four edges in one call and is more concise than manual `max`/`min` clamping on origin and size.

**Small images expose edge cases that larger images mask.** When testing crop logic, use images smaller than the panel size to verify bounds clamping. The default test image size (100x100) is small enough to catch this.

## When to Apply

Any code path that creates a `sourceRect` from a panel size:
1. `computeCropsFromSaliency` — saliency-based crop initialization
2. `computeInitialCrops` — default centered crop (uses `FitMath.sourceRect` which already clamps)
3. `resetCrop` — restores initial crop (uses `computeBestFitSource` which already clamps)

## Related

- `off-canvas-panel-drag-clamping.md` — clamping for panels that extend beyond the canvas
- `verify-data-flow-before-coordinate-conversion.md` — trace values to their producer
