# Visual Debug Overlay for Coordinate System Bugs

**Date:** 2026-06-20
**Session:** 120

## What Happened

Investigating why faces were misaligned in cropped panels. The bug could be in the Vision API, the coordinate conversion, the portrait swap, or the crop application. Rather than adding extensive logging and hoping to parse the numbers, we added a `#if DEBUG` visual overlay on the crop preview that draws a red dot at the computed saliency center.

## Result

The overlay immediately showed the center point was correct (red dot on the face), but the crop was wrong (face excluded from the visible area). This isolated the bug to `SaliencyResult.cropOrigin` in under a minute of visual inspection.

## Learning

**When debugging coordinate system bugs, a visual overlay is faster than structured logging.**

Mapping an internal coordinate value through the same transform chain as the UI (e.g., `FitMath.fit()` + offset/scale math) and drawing it directly on the preview gives immediate visual confirmation of whether the coordinate is correct or displaced.

**Pattern:**
```swift
#if DEBUG
if let debugValue {
    let (fittedSize, fitOffset) = FitMath.fit(imageSize, into: containerSize)
    let previewPoint = CGPoint(
        x: fitOffset.x + debugValue.x / imageSize.width * fittedSize.width,
        y: fitOffset.y + debugValue.y / imageSize.height * fittedSize.height
    )
    Circle().fill(Color.red).frame(width: 8, height: 8).position(previewPoint)
}
#endif
```

**When to use:** Any time you have an internal coordinate value (center, origin, bounding box) that should align with visible content. Draw it on top of the content and look for misalignment.

**Why it beats logging:** You don't need to mentally convert between coordinate spaces or search through log output. Misalignment is instantly visible.

## Related

- `verify-data-flow-before-coordinate-conversion.md` — trace values to their producer
- `collagemaker-prototype-2-coordinate-systems-learnings.md` — Vision/CG/NSImage origin differences
