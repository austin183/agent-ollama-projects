# Resize Handles — Edge-Based and Corner-Based Resize Patterns

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
- The threshold extends beyond the visual handle width (`+ 2`) for a comfortable grab area
- Y bounds check (`tf.minY ... tf.maxY`) ensures the drag started vertically within the box, not just horizontally near the edge
- A single `@State` enum (e.g., `TitleResizeEdge`) tracks which mode is active, avoiding multiple boolean flags
- All three modes share the same `DragGesture` — no additional gesture modifiers needed

### Right vs Left Edge Resize Semantics

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

### Minimum Width from Natural Text Bounds

To prevent a text box from shrinking below its content, compute the unbounded natural width:

```swift
let naturalBounds = attributedString.boundingRect(
    with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
    options: [.usesLineFragmentOrigin, .usesFontLeading]
)
let minWidth = naturalBounds.width
```

**Swift type ambiguity:** `.greatestFiniteMagnitude` is ambiguous without explicit type — both `Float` and `Double` have the property. Must use `CGFloat.greatestFiniteMagnitude`.

### ZStack Overlay Frame Sizing

A `Rectangle()` in a ZStack overlay with `.frame(width: 8)` stretches vertically to fill the full ZStack height. To vertically bound the rectangle, specify both dimensions: `.frame(width: 8, height: boxHeight)`. Without explicit height, the overlay fills available vertical space rather than matching the target element.

## Corner-Based Resize with Aspect Ratio Constraint

When a panel or overlay needs to be resizable from all four corners while maintaining its aspect ratio, use the **dominant-dimension pattern** with a **uniform bounding box**.

### Dominant-Dimension Pattern

Compare the drag ratio to the target aspect ratio to determine which dimension drives the resize:

```swift
let targetAspect = panel.frame.width / panel.frame.height

let rawW = abs(value.location.x - anchor.x)
let rawH = abs(value.location.y - anchor.y)

var newW: CGFloat
var newH: CGFloat
if rawW / rawH > targetAspect {
    newW = max(1, rawW)
    newH = newW / targetAspect
} else {
    newH = max(1, rawH)
    newW = newH * targetAspect
}
```

**Why it works:** The `rawW / rawH` comparison determines which drag dimension the user is moving more strongly. That dimension becomes the driver; the other is derived from the target aspect ratio. Dragging mostly horizontally expands width primarily, dragging mostly vertically expands height primarily — always preserving proportions.

### Uniform Bounding Box for All Corners

Use `min`/`abs` to compute the bounding box origin and dimensions. This works uniformly for all four corners without branching on corner type or drag direction:

```swift
let originX = min(anchor.x, value.location.x)
let originY = min(anchor.y, value.location.y)
let newRect = CGRect(x: originX, y: originY, width: newW, height: newH)
```

### Anti-Pattern: Contraction/Expansion Branching

**Do NOT** branch on whether `delta.width <= 0 && delta.height <= 0` to handle "shrinking" vs "expanding" differently. For bottom-left and top-right corners, one delta component is positive and the other negative during a valid resize, causing the branch to take the wrong path. The `min`/`abs` approach eliminates the need for this branch entirely.

### Corner Hit Detection

Combine with the edge-based resize handle pattern, but extend the threshold check to detect corners where the horizontal and vertical edge thresholds overlap:

```swift
let threshold: CGFloat = 8

// Corner detection (check corners first, then edges, then body)
if startLocation.x >= tf.maxX - threshold, startLocation.y >= tf.maxY - threshold {
    // Bottom-right corner
} else if startLocation.x <= tf.minX + threshold, startLocation.y >= tf.maxY - threshold {
    // Bottom-left corner
} else if startLocation.x >= tf.maxX - threshold, startLocation.y <= tf.minY + threshold {
    // Top-right corner
} else if startLocation.x <= tf.minX + threshold, startLocation.y <= tf.minY + threshold {
    // Top-left corner
} else if /* edge checks */ {
    // Edge resize
} else if tf.contains(startLocation) {
    // Drag to move
}
```

Track active mode with a single `@State` enum (e.g., `enum ResizeMode { case move, corner(Corner), edge(Edge) }`).

## Key Findings

1. **Edge resize with single DragGesture** — Distinguish drag-to-move vs drag-to-resize by checking `startLocation` proximity to element edges on first `onChanged`. Use a single `@State` enum to track mode. Right edge anchors left position; left edge adjusts position by half the width delta for symmetric resize.
2. **ZStack overlay rectangles need explicit height** — `.frame(width: 8)` on a `Rectangle()` in a ZStack overlay stretches vertically to fill the full ZStack height. Must specify both dimensions: `.frame(width: 8, height: boxHeight)`.
3. **`CGFloat.greatestFiniteMagnitude` requires explicit type** — `.greatestFiniteMagnitude` alone is ambiguous between `Float` and `Double`. Always prefix with `CGFloat.`
4. **Inverse coordinate transform with letterboxing** — When a gesture modifies a rect in container coordinates from a `.aspectRatio(.fit)` image, converting back to source requires subtracting the letterboxing offset before scaling: `sourceX = (containerX - offsetX) / fittedW * imageW`. Using `containerX * scaleX` double-applies the offset, causing the visual element to jump away from the cursor. See `../graphics/coordinate-systems.md` "Inverse Transform Pitfall".
5. **Aspect-ratio-constrained corner resize** — Use the dominant-dimension pattern: compare `rawW / rawH` to `targetAspect` to pick the driving axis, derive the other from the aspect ratio. Use `min(anchor, cursor)` + `abs(cursor - anchor)` for a uniform bounding box that works for all four corners without branching.
6. **Contraction/expansion branching is broken for corner resize** — Branching on `delta.width <= 0 && delta.height <= 0` fails for bottom-left and top-right corners where one delta is positive and the other negative. Use `min`/`abs` instead.

## Pitfalls

- **`CGFloat.greatestFiniteMagnitude` requires explicit type** — `.greatestFiniteMagnitude` alone is ambiguous between `Float` and `Double`. Always use `CGFloat.greatestFiniteMagnitude`.
- **Contraction/expansion branch breaks corner resize** — Branching on `delta.width <= 0 && delta.height <= 0` to distinguish shrinking from expanding doesn't work for bottom-left and top-right corners, where one delta is positive and the other negative. Use `min(anchor, cursor)` + `abs(cursor - anchor)` for a uniform bounding box across all four corners.
- **`.cursor()` modifier unavailable in macOS** — macOS SwiftUI has no `.cursor()` modifier. Use `NSCursor.push()` / `NSCursor.pop()` in `onHover` instead: `.onHover { hovering in if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }`
