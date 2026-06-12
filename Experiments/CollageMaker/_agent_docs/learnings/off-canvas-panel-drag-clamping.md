# Off-Canvas Panel Drag Clamping — Learnings 2026-06-11

**Purpose:** Document the visible bounds clamping pattern for panels whose bounding boxes extend beyond the canvas (diagonal slices, hexagonal edge panels).

## What Worked

- **Effective-origin clamping** — When a panel's bounding box extends beyond the canvas, the `sourceRect` maps to the full bounding box. Clamping `sourceRect.origin` to `[0, image.size - sourceRect.size]` prevents the visible portion from reaching image edges. The fix operates on the "effective origin" (`sourceRect.origin + visibleOffset`), clamped to `[0, image.size - visibleSize]`, then translates back. This pattern applies uniformly across drag gestures, pan gestures, and rendering.

- **Visible bounds from bounding box vs canvas** — The visible portion of the sourceRect is proportional to the visible portion of the panel's bounding box:
  ```
  offCanvasLeft = max(0, -destRect.minX)
  visWidth = min(canvasW, destRect.maxX) - max(0, destRect.minX)
  visOffsetX = offCanvasLeft / destRect.width * sourceW
  visSizeX = visWidth / destRect.width * sourceW
  ```

- **Polygon vertex classification by bounding box center** — For hit-testing polygon vertices as resize handles, classify each vertex by its position relative to the bounding box center rather than assuming a fixed vertex order. Works for parallelograms, hexagons, and clipped triangles.

## What Didn't Work / Gaps

- **sourceRectProj corners for handles** — Using `computeVisibleRect` corners for handle positions produces handles that extend beyond the parallelogram overlay for diagonal slices. The source rect projection is a rectangle, but the visible region is a parallelogram. Handles connected to the wrong shape feel disconnected from the overlay. **Lesson:** Handle positions should match the rendered overlay shape, not the underlying data model.

- **sourceRect beyond image bounds crashes rendering** — `CGImage.cropping(to:)` returns `nil` when the rect extends beyond image bounds (negative origin or size larger than image). The rendering pipeline silently drew nothing. **Fix:** Clamp to the overlapping portion and draw in the corresponding sub-rectangle of `destRect`.

## Key Pattern: Visible Bounds Clamping

```swift
// Compute visible portion of sourceRect (in image coordinates)
let offCanvasLeft = Swift.max(0, -destRect.minX)
let offCanvasTop = Swift.max(0, -destRect.minY)
let visMinX = Swift.max(0, destRect.minX)
let visMaxX = Swift.min(canvasSize.width, destRect.maxX)
let visOffsetX = offCanvasLeft / destRect.width * sourceW
let visSizeX = (visMaxX - visMinX) / destRect.width * sourceW

// Clamp effective origin, translate back
let effectiveBaseX = sourceRect.origin.x + visOffsetX
let maxEffX = image.size.width - visSizeX
let newEffX = clamp(effectiveBaseX + translation, min: 0, max: maxEffX)
let newOX = newEffX - visOffsetX  // can be negative!
```

**When to use:** Whenever a panel's destination bounding box extends beyond the canvas (negative `origin.x` or `origin.y`, or `maxX`/`maxY` exceeding canvas bounds). Affects diagonal slices (shear transform), hexagonal edge panels, and any future layout that overhangs the canvas.

**Apply in all three places:**
1. **Drag gestures** — Panel Editor overlay drag
2. **Pan gestures** — Canvas scroll pan (`CropManager.applyPan`)
3. **Rendering** — `CGImage.cropping(to:)` clamping in `CollageAssembler`

## Key Pattern: SourceRect Beyond Image Bounds

```swift
if let cropped = cg.cropping(to: sourceRect) {
    context.draw(cropped, in: destRect)
} else {
    let imageBounds = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
    let clamped = sourceRect.intersection(imageBounds)
    if clamped.width > 0, clamped.height > 0,
       let clippedCrop = cg.cropping(to: clamped) {
        let drawX = destRect.origin.x + (clamped.origin.x - sourceRect.origin.x) / sourceRect.width * destRect.width
        let drawY = destRect.origin.y + (clamped.origin.y - sourceRect.origin.y) / sourceRect.height * destRect.height
        let drawW = clamped.width / sourceRect.width * destRect.width
        let drawH = clamped.height / sourceRect.height * destRect.height
        context.draw(clippedCrop, in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
    }
}
```

**When to use:** Whenever `sourceRect` can extend beyond image bounds — which happens when off-canvas panels allow their sourceRect origin to go negative during drag/pan.

---
**Status:** Closed
**Follow-up:** None
