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
- See [scroll-views.md](scroll-views.md) for the full canvas pan pattern and HIG guidelines

## NSTextView with NSAttributedString Binding

When wrapping `NSTextView` in `NSViewRepresentable` for rich text editing, use `NSAttributedString` bindings instead of plain `String`.

### Basic Pattern

```swift
struct AttributedTextView: NSViewRepresentable {
    @Binding var attributedString: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.backgroundColor = NSColor.clear
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainerInset = NSSize(width: 4, height: 4)
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let currentText = textView.textStorage ?? NSAttributedString(string: "")
        if !currentText.isEqual(attributedString) {
            let savedRange = textView.selectedRange
            textView.textStorage?.setAttributedString(attributedString)
            let clampedRange = NSRange(
                location: min(savedRange.location, attributedString.length),
                length: min(savedRange.length, attributedString.length - min(savedRange.location, attributedString.length))
            )
            textView.selectedRange = clampedRange
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(attributedString: $attributedString)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var attributedString: NSAttributedString

        init(attributedString: Binding<NSAttributedString>) {
            _attributedString = attributedString
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let newStorage = textView.textStorage else { return }
            attributedString = NSAttributedString(attributedString: newStorage)
        }
    }
}
```

### Critical Details

- **`isEqual` for cursor preservation** — Use `NSTextStorage.isEqual(_:)` (not `==` or `===`) to compare content before updating. `isEqual` compares both string content and attributes. Using `===` always triggers (different instances), and comparing `.string` misses attribute changes.
- **Copy with `NSAttributedString(attributedString:)`** — Create a copy in `textDidChange` rather than assigning `NSTextStorage` directly, to avoid lifetime issues.
- **`drawsBackground = false`** — Without this, the text view renders its own white background, conflicting with SwiftUI styling.
- **`widthTracksTextView = true`** — Auto-width for single-line or wrapping text.
- **`heightTracksTextView = false`** — Fixed height to prevent the text view from growing unbounded.

### textDidChange Does NOT Fire for Attribute-Only Changes

`NSTextViewDelegate.textDidChange(_:)` only fires when string **content** changes (characters added, removed, or replaced). It does NOT fire for attribute-only changes (e.g., toggling bold, italic, underline). The SwiftUI binding and ViewModel's `didSet` will not be triggered by style-only edits.

**Fix:** After any attribute-only mutation on `NSTextStorage`, explicitly read and assign:

```swift
private func syncBinding() {
    guard let textView = textView,
          let textStorage = textView.textStorage else { return }
    attributedString = NSAttributedString(attributedString: textStorage)
}
```

Call `syncBinding()` at the end of each style toggle method (`toggleBold`, `toggleItalic`, `toggleUnderline`).

### ObservableObject Holder with PassthroughSubject

A lightweight holder class that exposes `NSTextView?` to the SwiftUI parent for style queries needs `ObservableObject` conformance. Use `PassthroughSubject` for external notification:

```swift
class TextViewHolder: ObservableObject {
    let objectWillChange = PassthroughSubject<TextViewHolder, Never>()
    var textView: NSTextView? {
        didSet { objectWillChange.send(self) }
    }
}
```

This allows `@StateObject` in the SwiftUI view to react when the representable assigns the text view.

### Re-entrancy Cascade Trap

When a coordinator's `textDidChange` normalizes text and assigns to a SwiftUI binding, the binding update triggers SwiftUI's render cycle, which calls `updateNSView`. If `updateNSView` modifies `typingAttributes` or `defaultParagraphStyle`, this mutates `NSTextStorage` and fires another `textDidChange`, creating a recursive loop that corrupts state.

**Cascade path:**
```
User types → textDidChange → normalize → attributedString = normalized
→ SwiftUI re-renders → updateNSView → typingAttributes = newAttrs
→ NSTextStorage mutates → textDidChange → (loop)
```

**Symptom:** After changing a color or other style, editing text causes the color to reset. The recursive loop corrupts intermediate state.

**Fix 1 — Coordinator guard flag:**
```swift
final class Coordinator: NSObject, NSTextViewDelegate {
    @Binding var attributedString: NSAttributedString
    private var isUpdating = false

    init(attributedString: Binding<NSAttributedString>) {
        _attributedString = attributedString
    }

    func textDidChange(_ notification: Notification) {
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        guard let textView = notification.object as? NSTextView,
              let newStorage = textView.textStorage else { return }
        attributedString = NSAttributedString(attributedString: newStorage)
    }
}
```

**Fix 2 — updateNSView early return:** Only update `typingAttributes` when the underlying value actually changed. Compare specific properties before assigning:

```swift
func updateNSView(_ nsView: NSScrollView, context: Context) {
    guard let textView = nsView.documentView as? NSTextView else { return }

    // Content check (as above)
    let currentText = textView.textStorage ?? NSAttributedString(string: "")
    if !currentText.isEqual(attributedString) {
        let savedRange = textView.selectedRange
        textView.textStorage?.setAttributedString(attributedString)
        textView.selectedRange = NSRange(
            location: min(savedRange.location, attributedString.length),
            length: min(savedRange.length, max(0, attributedString.length - savedRange.location))
        )
    }

    // Style check — only assign when font actually differs
    let targetFont = NSFont.systemFont(ofSize: 13)  // or your font source
    if let currentFont = textView.typingAttributes[.font] as? NSFont,
       currentFont.fontName == targetFont.fontName,
       currentFont.pointSize == targetFont.pointSize {
        return  // No style change needed — skip typingAttributes assignment
    }
    textView.typingAttributes[.font] = targetFont
}
```

Both fixes together eliminate the cascade: the guard prevents re-entrant normalization, and the early return prevents unnecessary `typingAttributes` mutations.

## NSColorWell

When wrapping `NSColorWell` in `NSViewRepresentable`, bind to `NSColor` with a coordinator for color change callbacks.

### Basic Pattern

```swift
struct ColorWellView: NSViewRepresentable {
    @Binding var color: NSColor

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell()
        well.isContinuous = true
        well.color = color  // Initialize from binding — never omit
        well.alphaValue = 1.0  // Enable alpha display if color may have transparency
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        well.color = color  // Always assign unconditionally — no equality guard
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(color: $color)
    }

    final class Coordinator: NSObject {
        @Binding var color: NSColor

        init(color: Binding<NSColor>) {
            _color = color
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            color = sender.color
        }
    }
}
```

### Color Equality Trap

`NSColor ==` compares underlying `CGColor` values, which can differ for visually identical colors in different color spaces (e.g., sRGB vs Display P3). Using `well.color != color` as a guard in `updateNSView` means the color well may not receive binding updates, causing stale state.

**Anti-pattern:**
```swift
func updateNSView(_ well: NSColorWell, context: Context) {
    if well.color != color {  // FALSE for same visual color, different color space
        well.color = color
    }
}
```

**Fix:** Always unconditionally assign. Never guard `NSColorWell.color` with `!=`.

### Alpha Handling

When the bound color may have an alpha component, set `well.alphaValue = 1.0` in `makeNSView`. This ensures the color well renders and accepts alpha values. (`NSColorWell` has no `allowsAlpha` property on macOS — that exists on iOS only.)
