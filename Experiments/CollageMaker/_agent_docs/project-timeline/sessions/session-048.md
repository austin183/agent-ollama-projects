# Session 48 — 2026-05-25

### Round 15.1 CR: Dynamic Zoom Limits for Pinch-to-Zoom

**Goal:** Allow pinch-to-zoom (2-finger gesture) to zoom out far enough to show the full image when the image is much larger than the panel, and cap max zoom-in at 2x.

**Source:** Round 15.1 change request — user could not zoom out to edges with 2-finger zoom gesture; panel snapped back before reaching the full image extent.

**Investigation:**

The `applyPinch` method in `CropManager.swift` used hardcoded zoom limits (`clamp(min: 0.5, max: 3.0)`) that were independent of the actual image and panel sizes. This meant:
- When the image (e.g., 4000x4000) was much larger than the panel (e.g., 960x540), the max zoom-out was clamped at 3.0, preventing the user from seeing the full image.
- The max zoom-in was 3x instead of the desired 2x.

The `translateZoom` static helper had the same hardcoded limits, and `PanelCropEditor.handleResize` had no clamping on the source rect size during corner-drag zoom.

**Changes Implemented:**

#### `CropManager.swift:142-155` — Dynamic zoom-out limit in `applyPinch`

Replaced hardcoded `clamp(min: 0.5, max: 3.0)` with:
- **Min zoom:** `0.5` (source rect = half panel size → 2x zoom-in)
- **Max zoom-out:** `min(imageW/panelW, imageH/panelH)` — the largest zoom where the source rect still fits within the image on both dimensions

```swift
let maxZoomOut = Swift.min(image.size.width / panelSize.width, image.size.height / panelSize.height)
let newZoom = clamp(baseZoom / zoomDelta, min: 0.5, max: maxZoomOut)
```

#### `CropManager.swift:205-210` — Updated `translateZoom` signature

Added `imageSize` and `panelSize` parameters, applying the same dynamic clamping:

```swift
static func translateZoom(magnification: CGFloat, baseZoom: CGFloat, imageSize: CGSize, panelSize: CGSize) -> CGFloat
```

#### `PanelCropEditor.swift:259-291` — Source size clamping in `handleResize`

Added clamping for corner-drag zoom:
- **Max source size:** largest rect fitting within the image at the panel's aspect ratio (full image visible)
- **Min source size:** half the panel size (2x zoom-in)
- Origin clamped to `[0, image.size - sourceSize]` after size clamping

#### `CropManagerTests.swift` — Updated test suite

- Renamed `pinchZoomClampsMin` → `pinchZoomClampsToFullImage` with 8000x4000 image, verifies source stays within image bounds
- Renamed `pinchZoomClampsMax` → `pinchZoomClampsTo2xZoomIn`, verifies zoom floor at 0.5
- Replaced `pinchZoomChangesCropSize` with `pinchZoomInReducesCropSize` and `pinchZoomOutIncreasesCropSize`
- Updated `translateZoom` tests for new signature and dynamic limits

**Build and Test Status:**
- **Build:** Succeeded — zero errors, zero warnings
- **Tests:** 108 tests passing (including updated zoom limit tests)

**Session Status:** Complete — dynamic zoom limits applied to pinch gesture and corner-drag resize, tests passing.
