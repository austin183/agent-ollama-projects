# NSViewRepresentable — AppKit Integration for SwiftUI

## Overview

`NSViewRepresentable` bridges AppKit `NSView` objects into SwiftUI. Use when you need AppKit capabilities not available in SwiftUI (advanced gesture recognition, custom hit testing, native controls).

## Protocol Requirements

```swift
protocol NSViewRepresentable {
    associatedtype NSViewType : NSView
    associatedtype Coordinator = Void

    func makeNSView(context: Context) -> NSViewType
    func updateNSView(_ nsView: NSViewType, context: Context)
}
```

**Important:** SwiftUI controls layout via `frame` and `bounds`. Don't set these directly — it conflicts with SwiftUI.

## Basic Pattern

```swift
struct MyAppKitView: NSViewRepresentable {
    let someValue: String

    func makeNSView(context: Context) -> NSCustomView {
        let view = NSCustomView()
        // One-time setup
        return view
    }

    func updateNSView(_ nsView: NSCustomView, context: Context) {
        nsView.someProperty = someValue
    }
}
```

## Gesture Recognizer Integration with Coordinator

```swift
struct CollageImageView: NSViewRepresentable {
    @EnvironmentObject var viewModel: CollageViewModel
    let panels: [ImagePanel]

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = viewModel.previewImage

        // Idempotent — remove old recognizers first
        nsView.gestureRecognizers?.forEach { nsView.removeGestureRecognizer($0) }

        let pan = NSPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.minimumTranslationMagnitude = 5

        let magnify = NSMagnifyingGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMagnify(_:))
        )

        nsView.addGestureRecognizer(pan)
        nsView.addGestureRecognizer(magnify)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    class Coordinator: NSObject {
        let parent: CollageImageView

        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            let translation = gesture.translation(in: gesture.view)

            switch gesture.state {
            case .began, .changed:
                parent.viewModel.panCrop(at: location, by: translation)
                gesture.setTranslation(.zero, in: gesture.view)
            case .ended, .cancelled:
                parent.viewModel.applyPanCrop()
            default: break
            }
        }

        @objc func handleMagnify(_ gesture: NSMagnifyingGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            switch gesture.state {
            case .began, .changed:
                parent.viewModel.pinchZoom(at: location, magnification: gesture.magnification)
            case .ended, .cancelled:
                parent.viewModel.applyPinchZoom()
            default: break
            }
        }
    }
}
```

## NSGestureRecognizer.State

| State | When |
|---|---|
| `.possible` | Initial state |
| `.began` | Gesture recognized |
| `.changed` | Gesture updated |
| `.ended` | Gesture completed |
| `.cancelled` | Interrupted (window lost focus) |
| `.failed` | Failed to recognize |

## Simultaneous Gesture Recognition

By default, gesture recognizers don't recognize simultaneously. Enable:

```swift
// In NSView subclass
override func gestureRecognizer(_ gr: NSGestureRecognizer,
                                 shouldRecognizeSimultaneouslyWith other: NSGestureRecognizer) -> Bool {
    return true
}

// Or: set delegate on gesture recognizer
pan.delegate = coordinator
```

## Coordinate Conversion

### Preview to Canvas

```swift
func previewToCanvas(_ point: CGPoint, previewSize: CGSize, canvasSize: CGSize = CGSize(width: 1920, height: 1080)) -> CGPoint {
    let canvasAspect = canvasSize.width / canvasSize.height
    let previewAspect = previewSize.width / previewSize.height

    var fittedSize: CGSize
    if canvasAspect > previewAspect {
        fittedSize = CGSize(width: canvasSize.width * (previewSize.height / canvasSize.height), height: previewSize.height)
    } else {
        fittedSize = CGSize(width: previewSize.width, height: canvasSize.height * (previewSize.width / canvasSize.width))
    }

    let offsetX = (previewSize.width - fittedSize.width) / 2
    let offsetY = (previewSize.height - fittedSize.height) / 2

    guard point.x >= offsetX, point.x < offsetX + fittedSize.width,
          point.y >= offsetY, point.y < offsetY + fittedSize.height else {
        return .zero
    }

    let canvasX = (point.x - offsetX) / fittedSize.width * canvasSize.width
    let canvasY = (point.y - offsetY) / fittedSize.height * canvasSize.height
    return CGPoint(x: canvasX, y: canvasY)
}
```

### Panel Hit Testing

```swift
func panel(at point: CGPoint, panels: [ImagePanel]) -> ImagePanel? {
    panels.first(where: { $0.frame.contains(point) })
}
```

## EnvironmentObject Across the Bridge

`@EnvironmentObject` works in `NSViewRepresentable`. The coordinator accesses it through the parent:

```swift
class Coordinator: NSObject {
    let parent: CollageImageView
    @objc func handlePan(_ g: NSPanGestureRecognizer) {
        parent.viewModel.panCrop(...)  // Access through parent
    }
}
```

## Comparison: ZStack vs NSViewRepresentable

| Aspect | ZStack + Overlays | NSViewRepresentable |
|---|---|---|
| Per-panel targeting | Manual hit testing | Built-in hitTest |
| Simultaneous gestures | `SimultaneousGesture` | `shouldRecognizeSimultaneouslyWith` |
| Visual feedback | Overlay shapes | Custom draw(_:) |
| Coordinate conversion | Manual calculation | NSView.convert |
| View recreation issues | Possible | Managed by AppKit |
| Complexity | Lower | Higher |

## Recommendation

For 1-20 panels, **ZStack overlay approach is sufficient**. Use NSViewRepresentable only if:
1. ZStack has performance issues with many panels
2. Need advanced AppKit features (rubber band selection, complex hit testing)
3. SwiftUI gesture composition proves unreliable

## Closure-Based API (Coordinator Alternative)

For simple event capture, passing closures through `updateNSView` avoids Coordinator boilerplate. Store closures as properties on your `NSView` subclass and update each frame:

```swift
struct ScrollCaptureView: NSViewRepresentable {
    let onScroll: (CGFloat, CGFloat) -> Void
    let panelFrames: [CGRect]  // SwiftUI-space frames for hit testing

    func makeNSView(context: Context) -> CaptureView {
        CaptureView()
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.onScroll = onScroll
        nsView.panelFrames = panelFrames
    }

    class CaptureView: NSView {
        var onScroll: (CGFloat, CGFloat) -> Void = { _, _ in }
        var panelFrames: [CGRect] = []

        override func scrollWheel(with event: NSEvent) {
            onScroll(event.scrollingDeltaX, event.scrollingDeltaY)
        }
    }
}
```

**Key points:**
- Closures update each frame via `updateNSView` — no Coordinator needed
- Avoid retain cycles: closures should capture `[weak self]` on `@Observable` classes
- Pass precomputed SwiftUI-space frames for hit testing in the AppKit layer

## AppKit/SwiftUI Coordinate Mismatch

When hit-testing in an `NSViewRepresentable` against SwiftUI frames, be aware of the Y-axis origin difference:

- `convert(event.locationInWindow, from: nil)` returns **AppKit coordinates** (bottom-left origin)
- SwiftUI frames use **top-left origin**

Flip Y before hit testing:
```swift
let location = convert(event.locationInWindow, from: nil)
let flippedY = bounds.height - location.y  // Convert to top-left origin
let point = CGPoint(x: location.x, y: flippedY)
```

This is a third coordinate system bridge point in macOS apps (after `canvasToPreviewFrame` Y-flip and CoreGraphics Y-flip).

## NSView Transparency

`NSView.isOpaque` is **get-only** on macOS — it's computed from `wantsLayer` + `layer?.isOpaque`, not directly settable. An `NSView` overlay is transparent by default when no custom drawing is performed. Do not attempt `view.isOpaque = false`.

## Scroll Input Capture (Canvas Pan Pattern)

When you need scroll wheel input to drive something other than a `ScrollView` (e.g., adjusting a crop viewport), capture raw `scrollWheel(with:)` events:

```swift
struct ScrollPanView: NSViewRepresentable {
    let onScroll: (CGFloat, CGFloat) -> Void  // deltaX, deltaY

    func makeNSView(context: Context) -> NSView {
        let view = PanCaptureView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as! PanCaptureView).onScroll = onScroll
    }

    class PanCaptureView: NSView {
        var onScroll: (CGFloat, CGFloat) -> Void = { _, _ in }

        override func scrollWheel(with event: NSEvent) {
            onScroll(event.scrollingDeltaX, event.scrollingDeltaY)
        }
    }
}
```

**Key points:**
- Two-finger scroll is the macOS convention — `scrollWheel` events are the right approach
- Check `event.isDirectionInvertedFromDevice` for trackpad vs mouse handling
- `NSEvent.Phase` tracks gesture state: `.began`, `.changed`, `.ended`, `.cancelled`
- See `../ui/scroll-views.md` for the full canvas pan pattern and HIG guidelines
