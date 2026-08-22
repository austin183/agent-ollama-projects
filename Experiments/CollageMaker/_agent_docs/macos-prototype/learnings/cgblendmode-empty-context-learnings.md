# CGBlendMode on Empty CGContext — Learnings

**Date:** 2026-06-08
**Session:** 95
**Purpose:** Document CoreGraphics blend mode behavior on transparent contexts and the SwiftUI-based fix.

## Problem

Applying `CGContext.setBlendMode(.multiply)` when drawing onto a fresh, transparent CGContext produces a black image instead of the intended multiply blend effect.

```swift
let context = CGContext(...) // fresh, all pixels are (0, 0, 0, 0)
context.setBlendMode(.multiply)
context.draw(maskImage, in: rect)
// Result: every pixel is (0, 0, 0, alpha) — black with mask's alpha channel
```

## Root Cause

Multiply blend mode computes: `result = source × destination`. On a transparent context, every destination pixel is `(0, 0, 0, 0)`. The RGB multiplication produces `(0, 0, 0)` regardless of the source. The alpha channel is preserved from the source via the compositing operator, so the result is a black image with the mask's alpha channel.

This is correct behavior per the Porter-Duff specification — the bug is in the assumption that blend mode can be applied at render time to an empty buffer and then composited later.

## Anti-Pattern

Rendering a blend operation into an isolated, empty context and expecting the blend to "stick" for later compositing:

```swift
// WRONG — blend mode baked into empty context
let overlayContext = CGContext(...) // transparent
overlayContext.setBlendMode(.multiply)
overlayContext.draw(maskImage, in: rect)
let overlayImage = context.makeImage() // black image

// Later in ZStack:
Image(nsImage: overlayImage) // black overlay, no blend effect
```

## Fix: Defer Blend Mode to Compositing Layer

Render the overlay image WITHOUT blend mode (just opacity), then apply the blend mode at the compositing layer where the destination pixels actually exist:

```swift
// Render phase — no blend mode, just opacity
let context = CGContext(...)
context.setAlpha(overlay.opacity)
context.draw(maskImage, in: rect)

// Compositing phase — SwiftUI ZStack
Image(nsImage: overlayImage)
    .blendMode(.multiply)  // blend against actual panel content
```

For SwiftUI, map `CGBlendMode` to `SwiftUI.BlendMode`:

```swift
private func overlayBlendMode(from cgBlendMode: CGBlendMode?) -> BlendMode {
    switch cgBlendMode {
    case .multiply: return .multiply
    case .screen: return .screen
    // ...
    default: return .multiply
    }
}
```

## When This Applies

- Any rendering pipeline that pre-renders a layer with a blend mode for later compositing
- Offscreen buffer rendering where the destination is not yet available
- Layered rendering architectures that separate render and composite phases

## Contrast with Correct Usage

The existing `drawOverlay(into:overlay:canvasSize:)` method in `CollageAssembler` works correctly because it draws onto a context that already contains panel content — the multiply operates against actual panel pixels:

```swift
// Context already has background + panels drawn
context.setBlendMode(.multiply)
context.setAlpha(opacity)
context.draw(maskImage, in: canvasRect) // multiply against panel pixels — correct
```

The difference: **blend mode requires non-zero destination pixels to produce a visible effect**.

## Verification

When testing blend mode rendering, check the output pixel values, not just visual appearance:
- A "working" multiply on empty context produces black — which may appear correct if the canvas background is dark
- A "working" multiply on actual content produces darker regions where both source and destination have color

---
**Status:** Closed
**Follow-up:** None
