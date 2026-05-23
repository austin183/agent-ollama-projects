# Title Drag-to-Position — Canvas Gesture & Coordinate Mapping — Learnings

**Date:** 2026-05-14
**Session:** 14
**Purpose:** Document learnings from implementing Phase 2 of Round 3: free-form title positioning via canvas drag gesture.

---

## What Worked

- **Normalized 0–1 position coordinates** — `positionX/Y` as normalized values (0–1) in `TitleStyle` make title placement resolution-independent. The assembler multiplies by canvas dimensions to get anchor points. Same approach works for any canvas size.
- **Top-left origin convention for position** — `positionX/Y` use top-left origin (SwiftUI convention) internally. The assembler converts to bottom-left (CoreGraphics) at draw time, and the editor view converts at hit-area time. One convention, convert at the boundary.
- **`decodeIfPresent` for backward-compatible Codable** — New `positionX/Y` fields use `try container.decodeIfPresent(CGFloat.self, forKey:)` with `?? TitleStyle.default.positionX` fallback. Existing saved `TitleStyle` JSON without these keys decodes to defaults instead of crashing.
- **Parent-level `DragGesture` with hit-test locking** — Following the skill guidance (Approach 1 from `swiftui-gestures.md`), a single `DragGesture(minimumDistance: 5)` at the ZStack level hit-tests `startLocation` against `scaledTitleFrame` on first `onChanged`. A `@State` flag (`dragTitleLocked`) prevents re-locking mid-drag.
- **Reusing `canvasToPreviewFrame` for title** — The existing coordinate conversion function handles Y-flip and aspect-ratio fit scaling. By computing `titleCanvasFrame` in canvas coordinates (bottom-left origin), the same function produces correct preview hit areas.

## What Didn't Work / Gaps

- **Title overlay appeared above text** — Initial `titleCanvasFrame` computed the rect's origin at `anchorYcg` (the top of the text in CG coords), but `canvasToPreviewFrame` flips Y: `flippedY = canvasHeight - origin.y - height`. With origin at the text top, the flipped rect placed the overlay above the actual text. Fixed by computing the origin at the text baseline (`anchorYcg - boundingBox.height`), matching `drawTitle()`'s `y` coordinate. The overlay rect now exactly covers the rendered text region.

- **DragGesture coordinate conversion needed careful handling** — Converting `DragGesture.Value.location` (SwiftUI top-left preview coords) to normalized canvas position requires:
  1. Compute fitted canvas size within preview geometry (same `.aspectRatio(contentMode: .fit)` math)
  2. Subtract centering offset to get position within the fitted canvas area
  3. Scale to canvas dimensions
  4. Flip Y from top-left to bottom-left (CoreGraphics)
  5. Convert back to top-left normalized for `positionY`

  The formula in the gesture `onChanged`:
  ```swift
  let canvasX = (location.x - offsetX) / fittedSize.width * canvasSize.width
  let canvasY = canvasSize.height - (location.y - offsetY) / fittedSize.height * canvasSize.height
  style.positionX = canvasX / canvasSize.width
  style.positionY = 1.0 - canvasY / canvasSize.height
  ```

- **`@Observable` property assignment triggers live preview** — Setting `viewModel.titleStyle = style` during `onChanged` fires `didSet`, which calls `updatePreview()`. Since `updatePreview()` already uses `Task.detached` with stale task cancellation, live drag updates are naturally debounced — no additional throttling needed.

## Key Patterns

### Normalized Position with Codable Backward Compatibility

```swift
struct TitleStyle: Codable, Equatable {
    var positionX: CGFloat
    var positionY: CGFloat

    static let `default` = TitleStyle(
        // ...
        positionX: 0.5,
        positionY: 0.88
    )
}

// In init(from:):
positionX = try container.decodeIfPresent(CGFloat.self, forKey: .positionX)
    ?? TitleStyle.default.positionX
positionY = try container.decodeIfPresent(CGFloat.self, forKey: .positionY)
    ?? TitleStyle.default.positionY
```

### Canvas-to-Preview Coordinate Conversion for Arbitrary Rects

When overlaying SwiftUI hit areas on a CoreGraphics-rendered image with `.aspectRatio(contentMode: .fit)`:

```swift
func canvasToPreviewFrame(_ canvasRect: CGRect, in previewSize: CGSize) -> CGRect {
    let canvasSize = CanvasConfig.defaultCanvasSize
    // ... compute fittedSize (see existing implementation) ...

    // Y-flip: CoreGraphics bottom-left -> SwiftUI top-left
    let flippedY = canvasSize.height - canvasRect.origin.y - canvasRect.height

    return CGRect(
        x: offsetX + canvasRect.origin.x / canvasSize.width * fittedSize.width,
        y: offsetY + flippedY / canvasSize.height * fittedSize.height,
        width: canvasRect.width / canvasSize.width * fittedSize.width,
        height: canvasRect.height / canvasSize.height * fittedSize.height
    )
}
```

### DragGesture Preview-to-Canvas Inverse Conversion

```swift
// In DragGesture onChanged:
let canvasX = (value.location.x - offsetX) / fittedSize.width * canvasSize.width
let canvasY = canvasSize.height - (value.location.y - offsetY) / fittedSize.height * canvasSize.height

// Store as normalized top-left:
style.positionX = canvasX / canvasSize.width
style.positionY = 1.0 - canvasY / canvasSize.height
```

### Title Frame Estimation in Editor View

To compute the title's canvas frame for hit-area overlay, estimate the bounding box using the same font/paragraph attributes as `drawTitle()`:

```swift
var titleCanvasFrame: CGRect? {
    guard !title.isEmpty else { return nil }
    // ... compute font, attributedString, boundingBox ...

    let anchorX = positionX * canvasWidth
    let originX: CGFloat
    switch alignment {
    case .left: originX = anchorX
    case .right: originX = anchorX - boundingBox.width
    default: originX = anchorX - boundingBox.width / 2
    }
    // Convert to bottom-left origin for canvasToPreviewFrame:
    let anchorYcg = canvasHeight - positionY * canvasHeight
    let originY = anchorYcg - boundingBox.height
    return CGRect(x: originX, y: originY, width: boundingBox.width, height: boundingBox.height)
}
```

## Alignment-Aware Anchor Points

The assembler's `drawTitle()` uses the anchor point differently per alignment:
- **Left**: anchor is the left edge of text (`x = anchorX`)
- **Center**: anchor is the center of text (`x = anchorX - width/2`)
- **Right**: anchor is the right edge of text (`x = anchorX - width`)

This means dragging the title moves the anchor point, and the text re-aligns relative to it. The visual effect is that the title stays anchored to the cursor at the alignment-appropriate edge.

## Next Steps

- Phase 3: Panel drag-to-reorder (canvas `DragGesture` that swaps images between panels)
- Consider: hide title overlay stroke when not dragging (cleaner canvas appearance)
- Consider: snap-to-grid or snap-to-edge for title positioning

---
**Status:** Closed
**Follow-up:** Round 3 Phase 3 (panel drag reorder)
