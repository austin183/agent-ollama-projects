# Pinch Zoom Anchor — Old vs New Visible Bounds — Learnings 2026-06-12

**Purpose:** Document the zoom anchor computation pattern for pinch gestures on panels with off-canvas geometry (diagonal slices, hexagonal edge panels).

## What Worked

- **Old/new bounds split** — When computing the zoom anchor for `applyPinch`, the anchor's effective source coordinate must be extracted from the **old** crop (pre-zoom), while the offset subtracted is the anchor's position within the **new** visible region (post-zoom). Using the new bounds for both creates a feedback loop where the anchor itself moves as zoom changes, causing drift.

- **Corner-based anchors for `.path` panels** — For diagonal slices, center-based zoom on fully on-canvas panels drifts when the parallelogram is sheared (drift proportional to `tan(angle)/2`). Using a fixed corner (top-left for left-clipped, bottom-right for right-clipped, top-left for middle) eliminates drift entirely.

- **`VisibleSourceBounds` as static method** — Making `computeVisibleSourceBounds` a `static func` on `CropManager` enables reuse from `PanelCropEditor` (overlay drag initialization) and from `CropManager` itself (pan and pinch). Eliminates 18 lines of duplicated math.

## What Didn't Work / Gaps

- **Center-based zoom for sheared parallelograms** — Using `boundingBox.width/2` as the zoom anchor for a sheared parallelogram causes drift proportional to `shear/2`. At 25° this is barely visible. At 43° (`tan(43°) ≈ 0.93`) the drift is obvious. The visual center (average of all path corners) differs from the bounding box center, but computing it per-zoom was expensive and still didn't match user expectations. **Lesson:** For irregular shapes, a fixed corner anchor is more predictable than any kind of "center."

- **`applyPinch` using `crop.sourceRect.midX`** — The original code preserved the center of the *full* source rect (`crop.sourceRect.midX`). For off-canvas panels, the visible center is `origin + offsetX + visibleW/2`, which differs from `midX + offsetX` by `(scaledW - visibleW)/2`. This was always positive, causing rightward drift on every zoom. **Lesson:** Always anchor to a point the user can see, not to a point that may be off-screen.

## Key Pattern: Zoom Anchor from Old Bounds

```swift
// Compute NEW visible bounds (post-zoom)
let visBounds = Self.computeVisibleSourceBounds(
    destRect: crop.destinationRect, sourceW: scaledW, sourceH: scaledH
)

// Compute OLD visible bounds (pre-zoom, from current crop)
let oldVisBounds = Self.computeVisibleSourceBounds(
    destRect: crop.destinationRect, sourceW: crop.sourceRect.width, sourceH: crop.sourceRect.height
)

// Anchor effective coordinate from OLD crop
let anchorEffX = crop.sourceRect.origin.x + oldVisBounds.offsetX + oldVisBounds.visibleW / 2

// Anchor offset within NEW visible region
let anchorOffsetX = visBounds.visibleW / 2

// New effective origin = anchor - offset
let maxEffX = max(0, image.size.width - visBounds.visibleW)
let newEffX = clamp(anchorEffX - anchorOffsetX, min: 0, max: maxEffX)
let newOX = newEffX - visBounds.offsetX
```

**Why old bounds for the anchor:** The anchor represents a point in the image that should stay fixed during zoom. That point is defined by the current (pre-zoom) crop. Using new bounds shifts the anchor as zoom changes — the anchor is no longer fixed.

**Why new bounds for the offset:** The offset is "how far from the anchor to the new source rect origin." It must use the new visible region dimensions because that's what the source rect will be after zoom.

## Key Pattern: Corner Anchor for Irregular Shapes

For `.path` panels (parallelograms, triangles, hexagons), use a fixed corner instead of the center:

```swift
if dest.minX < 0 {
    // Left edge clipped — anchor at top-left
    anchorEffX = baseEffX; anchorOffsetX = 0
    anchorEffY = baseEffY; anchorOffsetY = 0
} else if dest.maxX > canvasWidth {
    // Right edge clipped — anchor at bottom-right
    anchorEffX = baseEffX + oldVisBounds.visibleW; anchorOffsetX = visBounds.visibleW
    anchorEffY = baseEffY + oldVisBounds.visibleH; anchorOffsetY = visBounds.visibleH
} else {
    // Fully on-canvas — anchor at top-left
    anchorEffX = baseEffX; anchorOffsetX = 0
    anchorEffY = baseEffY; anchorOffsetY = 0
}
```

**When to use:** For any `.path` panel where the shape is not a rectangle. The user expects the visible region to expand/contract from a fixed corner, not from a computed center.

---
**Status:** Closed
**Follow-up:** None
