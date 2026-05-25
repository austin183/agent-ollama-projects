# SwiftUI Overlay Patterns

## eoFill Cutout for "Dim Except Region" Overlays

To create a "dim everything except this region" overlay without masks or shape subtraction:

```swift
Path { path in
    path.addRect(fullContainer)
    path.addRect(visibleRegion)
}
.fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
```

The even-odd fill rule fills the outer rect but punches a hole for the inner rect. Add a `Path` stroke around the visible region at ~80% white opacity for clear visual separation.

**Pitfall:** `.ultraThinMaterial` or other material fills render as a solid gray box rather than a translucent window. Use the eoFill Path approach for the proper cutout effect.

## Fixed Container for Stable Image Previews

When showing a crop preview, constrain the image to a fixed-height container with `.aspectRatio(contentMode: .fit)`. Without a fixed container, the image scales up as zoom decreases below 100%, making the overlay appear to overshoot. With a fixed container, only the overlay rectangle changes, keeping the preview intuitive.
