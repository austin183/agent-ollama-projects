# NSViewRepresentable — AppKit Integration Patterns for SwiftUI

## Overview

`NSViewRepresentable` is the bridge protocol for embedding AppKit `NSView` objects in SwiftUI views. It's useful when you need AppKit capabilities not available in SwiftUI.

## Protocol Requirements

```swift
@MainActor @preconcurrency
protocol NSViewRepresentable : View where Self.Body == Never {
    associatedtype NSViewType : NSView
    associatedtype Coordinator = Void

    func makeNSView(context: Context) -> NSViewType
    func updateNSView(_ nsView: NSViewType, context: Context)
}
```

### Optional Methods

| Method | Purpose |
|---|---|
| `makeCoordinator()` | Create coordinator object for delegation/target-action |
| `sizeThatFits(proposed:nsView:context:)` | Suggest intrinsic content size |
| `dismantleNSView(coordinator:)` | Cleanup when view is removed |

### Context

`Context` provides:
- `coordinator` — The coordinator object from `makeCoordinator()`
- `environment` — SwiftUI environment values

## Basic Pattern

```swift
struct MyAppKitView: NSViewRepresentable {
    // Input from SwiftUI
    let someValue: String

    func makeNSView(context: Context) -> NSCustomView {
        let view = NSCustomView()
        // One-time setup
        return view
    }

    func updateNSView(_ nsView: NSCustomView, context: Context) {
        // Respond to SwiftUI state changes
        nsView.someProperty = someValue
    }
}
```

**Important:** SwiftUI controls layout via `frame` and `bounds`. Don't set these properties directly — it conflicts with SwiftUI and causes undefined behavior.

## Coordinator Pattern

Use a coordinator to forward delegate messages and handle target-action:

```swift
struct CollageImageView: NSViewRepresentable {
    @EnvironmentObject var viewModel: CollageViewModel
    let panels: [ImagePanel]

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        imageView.isEditable = false
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = viewModel.previewImage

        // Add gesture recognizers (idempotent — remove old ones first)
        nsView.gestureRecognizers?.forEach { nsView.removeGestureRecognizer($0) }

        let panGesture = NSPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        let magnifyGesture = NSMagnifyingGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMagnify(_:))
        )

        nsView.addGestureRecognizer(panGesture)
        nsView.addGestureRecognizer(magnifyGesture)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    class Coordinator: NSObject {
        let parent: CollageImageView

        init(parent: CollageImageView) {
            self.parent = parent
        }

        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            let translation = gesture.translation(in: gesture.view)

            switch gesture.state {
            case .began, .changed:
                // Convert location to canvas coordinates and find panel
                parent.viewModel.panCrop(at: location, by: translation)
                gesture.setTranslation(.zero, in: gesture.view)
            case .ended, .cancelled:
                parent.viewModel.applyPanCrop()
            default:
                break
            }
        }

        @objc func handleMagnify(_ gesture: NSMagnifyingGestureRecognizer) {
            let location = gesture.location(in: gesture.view)

            switch gesture.state {
            case .began, .changed:
                parent.viewModel.pinchZoom(at: location, magnification: gesture.magnification)
            case .ended, .cancelled:
                parent.viewModel.applyPinchZoom()
            default:
                break
            }
        }

        // Allow simultaneous gesture recognition
        func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: NSGestureRecognizer) -> Bool {
            return true
        }
    }
}
```

## Gesture Recognizer Integration

### NSPanGestureRecognizer

For drag-to-pan crop:
```swift
let pan = NSPanGestureRecognizer(target: coordinator, action: #selector(handlePan(_:)))
pan.minimumTranslationMagnitude = 5  // Equivalent to DragGesture(minimumDistance: 5)
```

### NSMagnifyingGestureRecognizer

For pinch-to-zoom crop:
```swift
let magnify = NSMagnifyingGestureRecognizer(
    target: coordinator,
    action: #selector(handleMagnify(_:))
)
```

**Note:** On macOS, `NSMagnifyingGestureRecognizer` recognizes:
- Trackpad pinch gestures
- Scroll wheel with Option key

### NSGestureRecognizer.State

| State | When |
|---|---|
| `.possible` | Initial state |
| `.began` | Gesture recognized |
| `.changed` | Gesture updated (pan translation, magnification) |
| `.ended` | Gesture completed |
| `.cancelled` | Gesture interrupted (window lost focus, etc.) |
| `.failed` | Gesture failed to recognize |

### Simultaneous Gesture Recognition

By default, gesture recognizers don't recognize simultaneously. Override in the view:

```swift
// Option 1: In the NSView subclass
override func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer,
                                 shouldRecognizeSimultaneouslyWith other: NSGestureRecognizer) -> Bool {
    return true
}

// Option 2: Set delegate on the gesture recognizer
pan.delegate = coordinator  // Coordinator conforms to NSGestureRecognizerDelegate
```

## Coordinate Conversion

### From NSView to Canvas

```swift
func previewToCanvas(_ point: CGPoint, previewSize: CGSize, canvasSize: CGSize = CGSize(width: 1920, height: 1080)) -> CGPoint {
    // Calculate the fitted image size within the preview frame
    let canvasAspect = canvasSize.width / canvasSize.height
    let previewAspect = previewSize.width / previewSize.height

    var fittedSize: CGSize
    if canvasAspect > previewAspect {
        // Preview is constrained by height
        fittedSize = CGSize(
            width: canvasSize.width * (previewSize.height / canvasSize.height),
            height: previewSize.height
        )
    } else {
        // Preview is constrained by width
        fittedSize = CGSize(
            width: previewSize.width,
            height: canvasSize.height * (previewSize.width / canvasSize.width)
        )
    }

    // Center offset
    let offsetX = (previewSize.width - fittedSize.width) / 2
    let offsetY = (previewSize.height - fittedSize.height) / 2

    // Check if point is within the fitted image area
    guard point.x >= offsetX, point.x < offsetX + fittedSize.width,
          point.y >= offsetY, point.y < offsetY + fittedSize.height else {
        return .zero
    }

    // Convert to canvas coordinates
    let canvasX = (point.x - offsetX) / fittedSize.width * canvasSize.width
    let canvasY = (point.y - offsetY) / fittedSize.height * canvasSize.height

    return CGPoint(x: canvasX, y: canvasY)
}
```

### Panel Hit Testing

```swift
func panel(at point: CGPoint, panels: [ImagePanel]) -> ImagePanel? {
    return panels.first(where: { $0.frame.contains(point) })
}
```

## EnvironmentObject Across the Bridge

`@EnvironmentObject` works in `NSViewRepresentable`:

```swift
struct CollageImageView: NSViewRepresentable {
    @EnvironmentObject var viewModel: CollageViewModel

    func makeNSView(context: Context) -> NSImageView {
        // viewModel is accessible here
        return NSImageView()
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        // viewModel is accessible here
        nsView.image = viewModel.previewImage
    }
}
```

The coordinator can access it through the parent:

```swift
class Coordinator: NSObject {
    let parent: CollageImageView

    @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
        // Access viewModel through parent
        parent.viewModel.panCrop(...)
    }
}
```

## Custom NSView Subclass for Hit Testing

For more control, create a custom NSView subclass:

```swift
class CollagePreviewView: NSImageView {
    var panels: [ImagePanel] = []
    var canvasSize: CGSize = CGSize(width: 1920, height: 1080)

    // Override to provide custom hit testing
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Convert point to bounds coordinates
        let boundsPoint = convert(point, to: nil)

        // Convert to canvas coordinates
        let canvasPoint = previewToCanvas(boundsPoint)

        // Find panel at point
        if let _ = panels.first(where: { $0.frame.contains(canvasPoint) }) {
            return self
        }

        return super.hitTest(point)
    }

    // Draw selection overlay
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw selection border around selected panel
        if let selectedPanel = panels.first(where: { /* selected */ }) {
            let panelRect = canvasToPreviewFrame(selectedPanel.frame)
            let borderPath = NSBezierRect(panelRect)
            NSColor.systemBlue.setStroke()
            borderPath.lineWidth = 2
            borderPath.stroke()
        }
    }

    func previewToCanvas(_ point: CGPoint) -> CGPoint {
        // ... conversion logic
    }

    func canvasToPreviewFrame(_ canvasRect: CGRect) -> CGRect {
        // ... conversion logic
    }
}
```

## Integration Cost Assessment

### What Needs to Change

1. **Create `CollagePreviewView`** — Custom NSImageView subclass with gesture handling and overlay drawing
2. **Create `CollageImageView`** — NSViewRepresentable wrapper
3. **Update `CollageEditorView`** — Replace `Image(nsImage:)` with `CollageImageView`
4. **Update `CollageViewModel`** — Add `panCrop(at:by:)` and `pinchZoom(at:magnification:)` methods that take location for panel targeting

### What Stays the Same

- `@EnvironmentObject` pattern for ViewModel injection
- `ImagePanel`, `CropInfo`, `ImageItem` models
- `LayoutGenerator`, `SaliencyAnalyzer`, `CollageAssembler` services
- `PanelCropEditor`, `ExportPanel`, `ImagePickerView` views

### Estimated Effort

| Task | Complexity |
|---|---|
| Custom NSImageView subclass | Medium |
| NSViewRepresentable wrapper | Low |
| Gesture recognizer handlers | Medium |
| Coordinate conversion functions | Medium |
| ViewModel method updates | Low |
| Selection overlay drawing | Low |
| **Total** | **Medium** |

## Comparison with Pure SwiftUI Approach

| Aspect | ZStack + Overlays | NSViewRepresentable |
|---|---|---|
| Per-panel targeting | Manual hit testing | Built-in hitTest |
| Simultaneous gestures | `SimultaneousGesture` type | `shouldRecognizeSimultaneouslyWith` |
| Visual feedback | Overlay shapes | Custom draw(_:)|
| Coordinate conversion | Manual calculation | NSView.convert |
| View recreation issues | Possible | Managed by AppKit |
| Complexity | Lower | Higher |
| Performance | Good for <20 panels | Good for any count |
| SwiftUI integration | Native | Bridge required |

## Recommendation

For the CollageMaker project with 1-20 panels, **the ZStack overlay approach is sufficient** and avoids the complexity of NSViewRepresentable. Use NSViewRepresentable only if:

1. ZStack overlay approach has performance issues with many panels
2. Need advanced AppKit features (e.g., rubber band selection, complex hit testing)
3. SwiftUI gesture composition proves unreliable

The ZStack approach with `panelId`-based crop lookup (from `cgrect-equality-crop-lookup.md`) is the recommended path forward.
