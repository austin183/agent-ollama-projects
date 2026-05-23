# Title Resizable Text Box — Edge Resize Gesture Pattern — Learnings

**Date:** 2026-05-16
**Session:** 22
**Purpose:** Document learnings from implementing Round 4.3: resizable title text box with edge drag handles.

---

## Edge-Based Resize Handle Pattern

When an overlay element needs both drag-to-move and drag-to-resize, distinguish the two by checking whether `startLocation` falls within a threshold of the element's edge on first `onChanged`:

```swift
let handleThreshold = resizeHandleWidth + 2  // visual handle + comfortable grab area

if tf.minX - handleThreshold <= startLocation.x,
   startLocation.x <= tf.minX + handleThreshold,
   tf.minY <= startLocation.y, startLocation.y <= tf.maxY {
    // Left edge resize
} else if tf.maxX - handleThreshold <= startLocation.x,
          startLocation.x <= tf.maxX + handleThreshold,
          tf.minY <= startLocation.y, startLocation.y <= tf.maxY {
    // Right edge resize
} else if tf.contains(startLocation) {
    // Drag to move
}
```

**Key points:**
- The threshold extends beyond the visual handle width (`+ 2`) for comfortable grab area
- Y bounds check (`tf.minY ... tf.maxY`) ensures the drag started vertically within the box, not just horizontally near the edge
- A single `@State` enum (`TitleResizeEdge`) tracks which mode is active, avoiding multiple boolean flags
- All three modes share the same `DragGesture` — no additional gesture modifiers needed

## Right vs Left Edge Resize Semantics

- **Right edge resize** anchors the left edge of the box — width grows/shrinks rightward, position stays fixed
- **Left edge resize** adjusts `positionX` by half the width delta — the box appears to grow/shrink from the center, which matches user expectation for symmetric resizing

```swift
if titleResizeEdge == .right {
    let newWidth = max(minX, canvasX - tf.minX)
    style.width = newWidth
} else {
    let newWidth = max(minX, tf.maxX - canvasX)
    let dx = (tf.width - newWidth) / 2
    style.width = newWidth
    style.positionX = style.positionX + dx / canvasSize.width
}
```

## Minimum Width from Natural Text Bounds

To prevent the text box from shrinking below the text content, compute the unbounded natural width:

```swift
let naturalBounds = attributedString.boundingRect(
    with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
    options: [.usesLineFragmentOrigin, .usesFontLeading]
)
let minWidth = naturalBounds.width
```

**Swift type ambiguity:** `.greatestFiniteMagnitude` is ambiguous without explicit type — both `Float` and `Double` have the property. Must use `CGFloat.greatestFiniteMagnitude`.

## Effective Width Helper for Backward Compatibility

When adding a custom width property to a model where "use default" is the zero value, a helper method centralizes the fallback logic:

```swift
func effectiveWidth(canvasWidth: CGFloat) -> CGFloat {
    if width > 0 { return width }
    return canvasWidth - 40  // default: full canvas minus padding
}
```

This avoids duplicating the `width > 0 ? width : canvasWidth - 40` check at every call site (assembler, editor view, etc.).

## ZStack Overlay Frame Sizing

A `Rectangle()` in a ZStack overlay with `.frame(width: 8)` stretches vertically to fill the full ZStack height. To vertically bound the rectangle, specify both dimensions: `.frame(width: 8, height: boxHeight)`. Without explicit height, the overlay fills available vertical space rather than matching the target element.

---
**Status:** Closed
**Follow-up:** None
