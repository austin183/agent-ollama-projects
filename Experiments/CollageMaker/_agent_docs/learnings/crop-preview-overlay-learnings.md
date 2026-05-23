# Crop Preview Overlay — Learnings 2026-05-15

**Purpose:** Document learnings from implementing the Panel Editor crop preview, replacing the image picker with a visual overlay showing the active sourceRect region.

## What Worked

- **eoFill Path cutout** — Using `Path` with two `addRect` calls (full container + visible region) filled with `FillStyle(eoFill: true)` creates a clean "hole" in the overlay. The even-odd fill rule punches through exactly where the visible region is, with no complex mask or shape subtraction needed.
- **Fixed container + aspect-ratio fit** — Constraining the preview to a fixed height (140px) with `.aspectRatio(contentMode: .fit)` keeps the image stable regardless of zoom level. Only the overlay rectangle changes, making the preview intuitive.
- **White stroke border** — Adding a `Path` stroke around the visible region at 80% white opacity provides clear visual separation between the dimmed and visible areas without obscuring the image content.

## What Didn't Work / Gaps

- **EXIF coordinate mismatch** — `Image(nsImage:)` applies EXIF orientation corrections (rotation, flip) before display, but `sourceRect` coordinates live in raw CGImage pixel space. The overlay appeared shifted or rotated. Fix: create `NSImage(cgImage: image.cgImage, size: .zero)` to strip EXIF metadata, ensuring the displayed image matches the CGImage coordinate space.
- **Solid overlay approach** — Initial implementation used `.ultraThinMaterial` filled rectangle, which rendered as a solid gray box rather than a translucent window. The eoFill Path approach was needed for the proper cutout effect.
- **Image scaling instability** — Without a fixed container, the preview image scaled up as zoom decreased below 100%, making the overlay appear to overshoot. The fixed-height container with `.aspectRatio(contentMode: .fit)` resolved this.

## Key Patterns

### EXIF-Safe Image Display

When overlaying SwiftUI views on top of an `NSImage` whose coordinates come from CGImage operations (crop, saliency, etc.), always strip EXIF metadata:

```swift
// WRONG — applies EXIF rotation/flip, shifting coordinates
Image(nsImage: imageItem.nsImage)

// RIGHT — strips EXIF, display matches CGImage pixel coords
let displayImage = NSImage(cgImage: imageItem.cgImage, size: .zero)
Image(nsImage: displayImage)
```

### eoFill Cutout Pattern

For a "dim everything except this region" overlay:

```swift
Path { path in
    path.addRect(fullContainer)
    path.addRect(visibleRegion)
}
.fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
```

The even-odd fill rule fills the outer rect but punches a hole for the inner rect.

### aspectRatio Fit Coordinate Conversion

When mapping a rect from image pixel space to a SwiftUI container using `.aspectRatio(contentMode: .fit)`:

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

## Next Steps

- Consider adding the EXIF coordinate trap to `building-swiftui-macos-apps` skill Common Pitfalls section
- The `ImagePickerGrid` is no longer used by `PanelCropEditor` but retained for potential reuse

---
**Status**: Closed
**Follow-up**: Round 4 items 2-5 (heroIndex fix, font dropdown, alignment icons, BG toggle)
