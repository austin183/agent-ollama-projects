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
