# Coordinate System Traps

Vision, CoreGraphics, and NSImage use different origins:

| Framework | Origin | Notes |
|---|---|---|
| Vision | bottom-left (0,0) | Normalized 0-1, flip Y for top-left |
| CoreGraphics CGContext | bottom-left (0,0) | Flip with `translateBy` + `scaleBy` |
| NSImage / SwiftUI | top-left (0,0) | Standard screen coordinates |

## Vision to NSImage Y flip

```swift
let flippedY = imageHeight - visionRect.origin.y - visionRect.height
```

## CGContext top-left flip

```swift
context.translateBy(x: 0, y: canvasHeight)
context.scaleBy(x: 1, y: -1)
```

## EXIF Coordinate Mismatch

`Image(nsImage:)` applies EXIF orientation corrections (rotation, flip) before display, but `sourceRect` coordinates from CGImage operations live in raw pixel space. The overlay will appear shifted or rotated. Fix: strip EXIF metadata so the displayed image matches CGImage coordinates:

```swift
// WRONG — applies EXIF rotation/flip, shifting coordinates
Image(nsImage: imageItem.nsImage)

// RIGHT — strips EXIF, display matches CGImage pixel coords
let displayImage = NSImage(cgImage: imageItem.cgImage, size: .zero)
Image(nsImage: displayImage)
```

## Canvas-to-Preview Coordinate Conversion

When overlaying SwiftUI hit areas on a CoreGraphics-rendered image with `.aspectRatio(contentMode: .fit)`, you must account for both Y-axis inversion and aspect-ratio fit scaling:

```swift
func canvasToPreviewFrame(_ canvasRect: CGRect, in previewSize: CGSize) -> CGRect {
    let canvasSize = canvasSize  // e.g., CGSize(width: 1920, height: 1080)
    let canvasAspect = canvasSize.width / canvasSize.height
    let previewAspect = previewSize.width / previewSize.height

    // Compute fitted canvas size within preview
    let (fittedWidth, fittedHeight) = canvasAspect > previewAspect
        ? (previewSize.width, previewSize.width / canvasAspect)
        : (previewSize.height * canvasAspect, previewSize.height)

    // Centering offsets
    let offsetX = (previewSize.width - fittedWidth) / 2
    let offsetY = (previewSize.height - fittedHeight) / 2

    // Y-flip: CoreGraphics bottom-left -> SwiftUI top-left
    let flippedY = canvasSize.height - canvasRect.origin.y - canvasRect.height

    return CGRect(
        x: offsetX + canvasRect.origin.x / canvasSize.width * fittedWidth,
        y: offsetY + flippedY / canvasSize.height * fittedHeight,
        width: canvasRect.width / canvasSize.width * fittedWidth,
        height: canvasRect.height / canvasSize.height * fittedHeight
    )
}
```

## Preview-to-Canvas Inverse Conversion

For converting `DragGesture.Value.location` (SwiftUI top-left preview coords) back to normalized canvas position:

```swift
// In DragGesture onChanged:
let canvasX = (value.location.x - offsetX) / fittedWidth * canvasSize.width
let canvasY = canvasSize.height - (value.location.y - offsetY) / fittedHeight * canvasSize.height

// Store as normalized top-left (0-1):
style.positionX = canvasX / canvasSize.width
style.positionY = 1.0 - canvasY / canvasSize.height
```

Conversion steps:
1. Compute fitted canvas size within preview geometry (same `.aspectRatio(contentMode: .fit)` math)
2. Subtract centering offset to get position within the fitted canvas area
3. Scale to canvas dimensions
4. Flip Y from top-left to bottom-left (CoreGraphics)
5. Convert back to top-left normalized for storage

## Fit Math Branch Direction Gotcha

When implementing "fit source into container," the branch that triggers on `sourceAspect > containerAspect` (source is **wider**) should fill the container's **width** — not the height. The wider source hits the width wall first.

```swift
// CORRECT: wider source (higher aspect) → fill width
if sourceAspect >= containerAspect {
    fittedSize = CGSize(width: containerWidth, height: containerWidth / sourceAspect)
} else {
    fittedSize = CGSize(width: containerHeight * sourceAspect, height: containerHeight)
}
```

**Mnemonic:** The `>` branch fills the constraining dimension. Source is wider → width constrains → fill width. Getting this backwards produces a fitted size too small in one dimension and too large in the other, breaking hit-testing.

## Source Rect to Fitted Container Mapping

When mapping a rect from image pixel space to a SwiftUI container using `.aspectRatio(contentMode: .fit)` without Y-flip (e.g., sourceRect from CGImage crop, where coordinates are already top-left):

```swift
let (fittedW, fittedH): (CGFloat, CGFloat)
if imageAspect > containerAspect {
    fittedW = containerWidth
    fittedH = containerWidth / imageAspect
} else {
    fittedH = containerHeight
    fittedW = containerHeight * imageAspect
}

let offsetX = (containerWidth - fittedW) / 2
let offsetY = (containerHeight - fittedH) / 2

let mappedRect = CGRect(
    x: offsetX + sourceOriginX / imageWidth * fittedW,
    y: offsetY + sourceOriginY / imageHeight * fittedH,
    width: sourceWidth / imageWidth * fittedW,
    height: sourceHeight / imageHeight * fittedH
)
```

## Inverse Transform Pitfall: Never Use `* scaleX` with Letterboxing

When the forward transform is `containerX = offsetX + sourceX / imageW * fittedW`, the
**incorrect** inverse is `sourceX = containerX * scaleX` (where `scaleX = imageW / fittedW`).
This double-applies the offset:

```
containerX * scaleX
= (offsetX + sourceX/imageW * fittedW) * imageW/fittedW
= offsetX * imageW/fittedW + sourceX    ← offset leaks through
```

The **correct** inverse subtracts the offset first:

```swift
let offsetX = (containerWidth - fittedW) / 2
let offsetY = (containerHeight - fittedH) / 2

let sourceX = (containerX - offsetX) / fittedW * imageWidth
let sourceY = (containerY - offsetY) / fittedH * imageHeight
let sourceW = containerW / fittedW * imageWidth
let sourceH = containerH / fittedH * imageHeight
```

When image and container aspect ratios match, `offsetX == 0` and both formulas are equivalent.
The bug only manifests with letterboxed/pillarboxed images — the common case for arbitrary
images in a fixed-size container.

## Normalized Position Coordinates

For resolution-independent element placement, store positions as normalized 0–1 values. The assembler multiplies by canvas dimensions at draw time. Use top-left origin internally (SwiftUI convention), convert to bottom-left (CoreGraphics) at the drawing boundary.

## Verify Data Flow Before Adding Conversions

When adding a coordinate conversion method, **trace the value to its producer first**. Plan descriptions and variable names can be wrong about what coordinate space a value lives in. The producer's arithmetic is the source of truth.

**Verification steps:**
1. Find where the struct/value is instantiated
2. Check the arithmetic used to compute each coordinate field (e.g., `midX * width` = pixel space, not normalized)
3. Verify against the consumer's expected coordinate space
4. Only then write the conversion method

**Failure mode:** If the producer already outputs pixel coordinates and the conversion multiplies by image size again, the result overflows and clamps to edges — crops appear anchored at corners instead of centered.

## CGPath Construction

`CGPath` only provides initializers for rectangles and ellipses. To build an arbitrary path (polygon clip, hexagonal panel, star shape, etc.), use `CGMutablePath`.

### Building an arbitrary path from vertices

```swift
let mutablePath = CGMutablePath()
mutablePath.move(to: corners[0])
for corner in corners[1...] {
    mutablePath.addLine(to: corner)
}
mutablePath.closeSubpath()
let path: CGPath = mutablePath  // implicit coercion
```

`CGMutablePath` coerces implicitly to `CGPath` — no explicit conversion needed. A closure-based `CGPath` factory initializer does not exist in the current SDK.

### Computing bounding rect from known vertices

`CGMutablePath` does not expose `boundingRect` in Swift. For convex polygons with known vertices, compute the bounding rect manually:

```swift
let minX = min(corners[0].x, corners[1].x, corners[2].x, corners[3].x)
let minY = min(corners[0].y, corners[1].y, corners[2].y, corners[3].y)
let maxX = max(corners[0].x, corners[1].x, corners[2].x, corners[3].x)
let maxY = max(corners[0].y, corners[1].y, corners[2].y, corners[3].y)
let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
```

This is O(1) for a fixed vertex count and more efficient than iterating path elements or coercing to `CGPath` first.

## Hexagonal Grid Layout (Pointy-Top)

Use axial coordinates `(q, r)` for honeycomb placement — **not polar angles**. Polar ring placement produces elliptical rings with overlapping hexagons at diagonal angles.

### Axial to Pixel Conversion

```swift
let x = centerX + (CGFloat(q) + CGFloat(r) / 2.0) * sqrt(3) * R_eff
let y = centerY + CGFloat(r) * 1.5 * R_eff
```

**Pitfall:** `CGFloat(q + r / 2)` truncates odd `r` — use `CGFloat(q) + CGFloat(r) / 2.0`.

### Effective Radius (Fits Canvas Including Hex Extents)

`R_eff` determines center positions. Must account for hex extent beyond outermost centers:

```swift
let R_eff = min(
    canvasW / (sqrt(3) * (2 * rings + 1)),
    canvasH / (3 * rings + sqrt(3))
)
```

**Pitfall:** `W / (2√3·rings)` only places outermost centers at canvas edge — hexagons extend `√3·R` horizontally and `R` vertically beyond their centers, clipping ring-1 hexagons off-canvas.

### Visual Hexagon Radius

```swift
let R = max(sqrt(3) / 2 * R_eff - spacing / 2, spacing)
```

Minimum center-to-center distance on an axial pointy-top grid is `√3·R_eff` (not `2·R_eff`). Guard against negative `R`.

### Frame Dimensions

```swift
let frameWidth = sqrt(3) * R
let frameHeight = 2 * R
```

### Ring Traversal

For ring N (0 = center), start at `(q: N, r: 0)` and walk 6 directions, `N` steps each:

```swift
let directions: [(dq: Int, dr: Int)] = [
    (0, -1), (-1, 0), (-1, 1), (0, 1), (1, 0), (1, -1)
]

var q = ring, r = 0
for dir in directions {
    for _ in 0..<ring {
        q += dir.dq; r += dir.dr
        // place hex at (q, r)
    }
}
```

**Pitfall:** `for step { for direction { ... } }` cycles all 6 directions `step` times, producing duplicates. Correct order: outer loop = directions, inner loop = steps.

### Non-Overlap Test Threshold

Minimum center-to-center distance for non-overlapping pointy-top hexagons is `2·R`. Since `frame.width = √3·R`, the threshold is `2 * frame.width / sqrt(3)`, not `frame.width`.

### Spacing vs Center Positions

`spacing` only affects visual radius `R`, not center positions (which depend on `R_eff`). Tests comparing layout spread across different spacing values will fail — centers don't move.

## Per-Panel Path Clipping

When rendering panels with non-rectangular shapes (hexagons, diagonal slices), clip at the `CGContext` level — not with SwiftUI `.clipShape`.

### Why `.clipShape` Fails

`PanelShape.path(in:)` returns a path in origin-local coordinates, but `.position()` places the view elsewhere in the parent `ZStack`. The clip region misses the image content.

### CGContext Clipping Pattern

Pass panel geometry to `renderPanel()`, translate the path by `-boundingRect.origin` (rendering context is origin-local), and clip before drawing:

```swift
func renderPanel(context: CGContext, geometry: PanelGeometry, image: CGImage) {
    let path = geometry.createPath(in: geometry.boundingRect)
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.draw(image, in: geometry.boundingRect)
    context.restoreGState()
}
```

**Protocol impact:** Adding `geometry` to `renderPanel()` cascades to `PanelRenderer`, `PreviewManager`, `CollageViewModel`, all test mocks, and all test call sites.
