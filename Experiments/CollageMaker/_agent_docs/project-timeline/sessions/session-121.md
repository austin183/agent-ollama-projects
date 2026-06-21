# Session 121 — Round 103: Saliency Diagnostics Phase 3 + Crop Bounds Fix

**Date:** 2026-06-20
**Change Request:** round-103.md
**Plan:** 2026-06-20-round-103-saliency-diagnostics.md

## Summary

Implemented Phase 3 of the saliency diagnostics plan: removed the portrait swap from `SaliencyResult.cropOrigin`, consolidated coordinate conversion in `SaliencyAnalyzer` using `CoordinateConverter.visionToCG`, and removed unused `CropManager` methods. Additionally discovered and fixed a pre-existing edge case where the crop overlay expands beyond image bounds for small images.

## Phase 3 Changes

### Removed Portrait Swap — `Models/SaliencyResult.swift`

Removed the x/y axis swap for portrait images (lines 22-29). The diagnostic overlay from Phase 1 confirmed the saliency center is correct, and the swap was the root cause of face misalignment on portrait images. The `VNImageRequestHandler` with `orientation: .up` already handles orientation correctly.

### Consolidated Coordinate Conversion — `Services/SaliencyAnalyzer.swift`

Replaced inline Vision-to-CG math (`box.midX * width`, `(1.0 - box.midY) * height`) with `CoordinateConverter.visionToCG()` calls for face and salient object bounding boxes. This establishes a single source of truth for coordinate conversions.

### Removed Unused Methods — `ViewModel/CropManager.swift`

Removed `applyPortraitSwap` and `visionToCGWithPortrait` from `CoordinateConverter`. These were created to address the portrait swap problem but were never used in production code (only referenced in tests and the plan).

### Updated Tests

- `SaliencyResultTests.swift`: Updated `cropOriginPortraitSwap` → `cropOriginPortraitNoSwap` with correct expected values
- `CoordinateConverterTests.swift`: Removed 7 tests for deleted portrait swap methods

## Crop Bounds Fix — `ViewModel/CropManager.swift`

**Problem:** User reported the crop overlay expands outside image bounds in the Panel Editor. The issue only appeared with small test images (268x338) where `panelSize > imageSize`.

**Root cause:** `computeCropsFromSaliency` creates a source rect with `CGRect(origin: origin, size: panelSize)`. When `panelSize` exceeds `imageSize`, the rect extends beyond the image. The `cropOrigin` clamping only constrains the origin to `[0, imageSize - cropSize]`, but when `cropSize > imageSize`, the clamped origin is `0` and the rect still exceeds bounds.

**Fix:** Added `CGRect.intersection` after constructing the rect:
```swift
var rect = CGRect(origin: origin, size: panelSize)
rect = rect.intersection(CGRect(origin: .zero, size: image.size))
sourceRect = rect
```

This ensures the source rect is always within image bounds, regardless of panel size.

## Verification

- Build: zero errors, zero warnings
- All 250+ unit tests pass (SaliencyResultTests, CoordinateConverterTests, CropManagerTests)
- User confirmed crop overlay stays within image boundaries with both small and large images

## Files Changed

| File | Change |
|------|--------|
| `Models/SaliencyResult.swift` | Removed portrait swap (9 lines → 0) |
| `Services/SaliencyAnalyzer.swift` | Consolidated coordinate conversion using `CoordinateConverter.visionToCG` |
| `ViewModel/CropManager.swift` | Removed unused methods, added `CGRect.intersection` clamping |
| `Tests/SaliencyResultTests.swift` | Updated portrait test |
| `Tests/CoordinateConverterTests.swift` | Removed 7 portrait swap tests |

## Next Steps

Phase 2 (test with real images) deferred — the diagnostic confirmed the fix without fixture-based tests.
