# SwiftUI Gestures — Targeting, Coordinate Spaces, and Composition

## DragGesture — Location and Coordinate Space

`DragGesture` provides location information through `DragGesture.Value`:

### Key Properties

| Property | Type | Available In | Description |
|---|---|---|---|
| `location` | `CGPoint` | `onChanged`, `onEnded` | Current pointer location in the gesture's coordinate space |
| `startLocation` | `CGPoint` | `onChanged`, `onEnded` | Location where the gesture began |
| `translation` | `CGSize` | `onChanged`, `onEnded` | Delta from start to current position |
| `predictedEndLocation` | `CGPoint` | `onChanged` only | Predicted final location based on velocity |
| `velocity` | `CGSize` | `onEnded` only | Velocity at gesture end |

**Important:** `location` is available in both `onChanged` and `onEnded` callbacks. The research item question "Does DragGesture provide location in onChanged?" — **Yes, it does.**

### Coordinate Space Configuration

```swift
// Default: local coordinate space of the view the gesture is attached to
DragGesture()

// Explicit local coordinate space
DragGesture(coordinateSpace: .local)

// Global screen coordinate space
DragGesture(coordinateSpace: .global)

// Named coordinate space — maps to an ancestor view
DragGesture(coordinateSpace: .named("preview"))
```

The coordinate space is set via the initializer:
```swift
init(minimumDistance: CGFloat, coordinateSpace: some CoordinateSpaceProtocol)
```

## CoordinateSpace Protocol

Three built-in coordinate spaces:

| Space | Usage | Description |
|---|---|---|
| `.local` | Default | Local coordinate space of the view's parent |
| `.global` | Screen-wide | Global screen coordinate space |
| `.named(_:)` | Ancestor-scoped | Named coordinate space defined by an ancestor view |

### Named Coordinate Spaces

Define a named coordinate space on an ancestor, then reference it:

```swift
VStack {
    GeometryReader { proxy in
        // proxy.frame(in: .named("container")) gives frame in ancestor's space
    }
}
.coordinateSpace(.named("container"))
```

For gestures, use the same named space:
```swift
DragGesture(coordinateSpace: .named("preview"))
```

## Gesture Composition

Three composition types for combining gestures:

### 1. Simultaneous Gestures

Multiple gestures recognized at the same time. Use `simultaneousGesture(_:including:)` modifier or the `SimultaneousGesture` type:

```swift
// Using modifier
view
    .gesture(drag)
    .simultaneousGesture(magnify)

// Using type
let combined = SimultaneousGesture(drag, magnify)
```

### 2. Sequenced Gestures

One gesture must complete before the next begins. Use `sequenced(before:)`:

```swift
LongPressGesture(minimumDuration: 0.5)
    .sequenced(before: DragGesture())
```

The `SequenceGesture.Value` enum tracks state:
- `.first(true)` — first gesture in progress
- `.second(true, let secondValue)` — first confirmed, second in progress
- `.second(true, let secondValue?)` — both completed (in `onEnded`)

### 3. Exclusive Gestures

Only one gesture wins. Use `ExclusiveGesture`:

```swift
let either = ExclusiveGesture(tap, longPress)
```

## GestureMask — Controlling Gesture Propagation

`GestureMask` is an `OptionSet` that controls how `gesture(_:including:)` affects subviews:

| Option | Effect |
|---|---|
| `.all` | Default — gesture competes with both view's own gestures and subview gestures |
| `.gesture` | Only competes with the view's own gestures, not subviews |
| `.subviews` | Only competes with subview gestures, not the view's own |
| `.none` | Doesn't compete with any existing gestures |

```swift
// Gesture competes with subview gestures (default)
view.gesture(drag, including: .all)

// Gesture doesn't interfere with subview gestures
view.gesture(drag, including: .gesture)
```

## MagnifyGesture (Pinch-to-Zoom on macOS)

```swift
struct MagnifyGestureView: View {
    @GestureState private var magnifyBy = 1.0

    var magnification: some Gesture {
        MagnifyGesture()
            .updating($magnifyBy) { value, gestureState, transaction in
                gestureState = value.magnification
            }
    }

    var body: some View {
        Circle()
            .frame(width: 100, height: 100)
            .scaleEffect(magnifyBy)
            .gesture(magnification)
    }
}
```

**Note:** On macOS, `MagnifyGesture` recognizes scroll wheel with Option key, or trackpad pinch gestures.

## Per-Panel Gesture Targeting Approaches

### Approach 1: ZStack with Overlay Rectangles (Recommended)

Overlay invisible rectangles on top of the composite preview image, each with its own gesture:

```swift
ZStack {
    // Composite preview image
    Image(nsImage: previewImage!)
        .resizable()
        .aspectRatio(contentMode: .fit)

    // Per-panel gesture overlays
    ForEach(panels) { panel in
        Rectangle()
            .fill(Color.clear)
            .frame(width: panelFrame.width, height: panelFrame.height)
            .position(x: panelFrame.midX, y: panelFrame.midY)
            .contentShape(Rectangle()) // For hit testing
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        viewModel.panCrop(panelId: panel.id, by: value.translation)
                    }
                    .onEnded { value in
                        viewModel.applyPanCrop(panelId: panel.id)
                    }
            )
    }
}
```

**Coordinate Space:** The overlay rectangles need to account for the aspect-ratio fit scaling of the preview image. Use `GeometryReader` to get the actual rendered size:

```swift
GeometryReader { geometry in
    ZStack {
        Image(nsImage: previewImage!)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: geometry.size.width, height: geometry.size.height)

        ForEach(panels) { panel in
            // Convert canvas coords to preview coords
            let scaledFrame = canvasToPreviewFrame(panel.frame, in: geometry.size)
            Rectangle()
                .fill(Color.clear)
                .frame(width: scaledFrame.width, height: scaledFrame.height)
                .position(x: scaledFrame.midX, y: scaledFrame.midY)
                // ... gestures
        }
    }
}
```

### Approach 2: Single Gesture with Hit Testing

Attach one gesture to the preview, then determine which panel was touched:

```swift
Image(nsImage: previewImage!)
    .gesture(
        DragGesture(minimumDistance: 5, coordinateSpace: .named("preview"))
            .onChanged { value in
                // Convert gesture location to canvas coordinates
                let canvasPoint = previewToCanvas(value.location, in: previewSize)
                // Find panel at point
                if let panel = panels.first(where: { $0.frame.contains(canvasPoint) }) {
                    viewModel.panCrop(panelId: panel.id, by: value.translation)
                }
            }
    )
    .coordinateSpace(.named("preview"))
```

**Limitation:** `DragGesture.Value.location` in `onChanged` is in the gesture's coordinate space. With `.named("preview")`, it's relative to the named coordinate space ancestor.

### Approach 3: Canvas (NOT Recommended for Interactive Elements)

**Apple docs explicitly state:** "A canvas doesn't offer interactivity or accessibility for individual elements, including for views that you pass in as symbols."

Canvas is designed for high-performance drawing, not interactive gesture zones. **Do not use Canvas for per-panel gestures.**

### Approach 4: NSViewRepresentable with NSImageView

Wrap an AppKit `NSImageView` in `NSViewRepresentable` for native gesture recognition:

```swift
struct CollageImageView: NSViewRepresentable {
    @EnvironmentObject var viewModel: CollageViewModel
    let panels: [ImagePanel]

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        imageView.postsFrameChangedNotifications = true
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = viewModel.previewImage
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSGestureRecognizerDelegate {
        let parent: CollageImageView

        init(_ parent: CollageImageView) {
            self.parent = parent
        }

        func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: NSGestureRecognizer) -> Bool {
            return true
        }
    }
}
```

Add gesture recognizers in `updateNSView`:
```swift
// Add pan and magnify gesture recognizers
let panGesture = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
let magnifyGesture = NSMagnifyingGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMagnify(_:)))
nsView.addGestureRecognizer(panGesture)
nsView.addGestureRecognizer(magnifyGesture)
```

**Hit testing:** Use `nsView.convert(point, from: nsView.superview)` to get coordinates, then check against panel frames.

**Pros:**
- Native AppKit gesture recognition
- Built-in hit testing
- Proper coordinate conversion
- No SwiftUI view recreation issues

**Cons:**
- More complex integration
- Need Coordinator for gesture handling
- Bridge between AppKit and SwiftUI state

## NSGestureRecognizerRepresentable

For custom gesture recognizers without full NSViewRepresentable:

```swift
struct MyGestureRecognizer: NSGestureRecognizerRepresentable {
    typealias NSGestureRecognizerType = NSPanGestureRecognizer

    func makeNSGestureRecognizer(context: Context) -> NSPanGestureRecognizer {
        let gesture = NSPanGestureRecognizer()
        return gesture
    }

    func handleNSGestureRecognizerAction(_ gesture: NSPanGestureRecognizer,
                                          context: Context) {
        let location = gesture.location(in: gesture.view)
        // Convert using context.converter
        let swiftUIPoint = context.converter.convert(
            location,
            from: gesture,
            to: .local
        )
    }
}
```

Attach with `.gesture(_:)` modifier.

## Key Findings for CollageMaker

1. **DragGesture provides `location` in `onChanged`** — confirmed by Apple docs
2. **SimultaneousGesture can combine drag + pinch** — use `SimultaneousGesture(drag, magnify)` or the `.simultaneousGesture()` modifier
3. **Per-panel gesture zones on composite image** — ZStack with clear Rectangle overlays is the simplest SwiftUI approach
4. **Canvas is NOT suitable** — Apple explicitly states it doesn't offer interactivity for individual elements
5. **NSViewRepresentable is viable** — more complex but provides native AppKit gesture handling
6. **Coordinate space conversion** — `previewToCanvas()` must account for aspect-ratio fit scaling between the preview frame and the 1920x1080 canvas
