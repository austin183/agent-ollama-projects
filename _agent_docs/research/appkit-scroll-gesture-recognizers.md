# AppKit Gesture Recognizers for Scroll-Based Panning

## Source
- https://developer.apple.com/documentation/appkit/nspangesturerecognizer
- https://developer.apple.com/documentation/appkit/nsscrollview
- Existing research: `nsviarepresentable-integration.md`, `swiftui-gesture-targeting.md`

## NSPanGestureRecognizer

```swift
class NSPanGestureRecognizer : NSGestureRecognizer
```

The gesture is recognized when the user clicks all specified buttons, drags the mouse, and releases one or more of the buttons. Use the pan gesture recognizer to retrieve the distance traveled during the pan and the location of the mouse as it pans.

### Configuration

```swift
var buttonMask: Int                    // Which mouse buttons to track
var numberOfTouchesRequired: Int       // Number of touches for recognition
```

Upon creation, the gesture recognizer is configured to recognize pan gestures involving only the primary button. It also delays sending primary button events to the view by setting `delaysPrimaryMouseButtonEvents` to `true`.

### Tracking Methods

```swift
func translation(in view: NSView?) -> NSPoint     // Distance traveled during pan
func setTranslation(_ translation: NSPoint, in view: NSView?)  // Reset translation
func velocity(in view: NSView?) -> NSPoint        // Current velocity
```

### Gesture State

| State | When |
|-------|------|
| `.possible` | Initial state |
| `.began` | Gesture recognized |
| `.changed` | Gesture updated (pan translation changed) |
| `.ended` | Gesture completed |
| `.cancelled` | Gesture interrupted |
| `.failed` | Gesture failed to recognize |

## NSScrollView

```swift
class NSScrollView : NSView
```

The central coordinator for AppKit's scrolling machinery, composed of `NSScrollView`, `NSClipView`, and `NSScroller`.

### Key Properties

```swift
var documentView: NSView?           // The view being scrolled
var contentView: NSClipView         // The clipping view
var horizontalScroller: NSScroller?
var verticalScroller: NSScroller?
var hasHorizontalScroller: Bool
var hasVerticalScroller: Bool
var contentSize: NSSize
var documentVisibleRect: NSRect
```

### Class Methods

```swift
class func frameSize(forContentSize: NSSize, ...) -> NSSize
class func contentSize(forFrameSize: NSSize, ...) -> NSSize
```

## Two Approaches for Canvas Panning

### Approach A: Override scrollWheel(with:) (Recommended for Batch 4)

**Pros:**
- Captures native two-finger trackpad scroll directly
- No gesture recognizer conflicts
- System-native feel with momentum and elasticity
- Simple implementation — override one method in `NSView`

**Cons:**
- Must manually track pan state (begin, update, commit)
- Must handle coordinate conversion
- Momentum scrolling requires separate handling

```swift
class ScrollPanNSView: NSView {
    private var activePanelId: UUID?

    override func scrollWheel(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let deltaX = -event.scrollingDeltaX
        let deltaY = -event.scrollingDeltaY

        switch event.phase {
        case .began:
            activePanelId = hitTestPanel(at: location)
            if let id = activePanelId {
                coordinator?.beginPan(id)
            }
        case .changed:
            if let id = activePanelId {
                coordinator?.pan(by: CGSize(width: deltaX, height: deltaY))
                coordinator?.applyPanLive()
            }
        case .ended, .cancelled:
            if let id = activePanelId {
                coordinator?.applyPan(id)
            }
            activePanelId = nil
        default: break
        }
    }
}
```

### Approach B: NSPanGestureRecognizer on NSView

**Pros:**
- Familiar gesture recognizer pattern
- Built-in state machine
- Velocity tracking available

**Cons:**
- Competes with system scroll handling
- May interfere with `NSScrollView` behavior
- Requires gesture recognizer delegate for simultaneous recognition
- Not the conventional macOS input for panning content

```swift
let panGesture = NSPanGestureRecognizer(
    target: context.coordinator,
    action: #selector(Coordinator.handlePan(_:))
)
panGesture.numberOfTouchesRequired = 2  // Two-finger pan
nsView.addGestureRecognizer(panGesture)
```

## Why scrollWheel(with:) Over NSPanGestureRecognizer

For the CollageMaker canvas pan use case, **overriding `scrollWheel(with:)` is the better choice** because:

1. **macOS convention:** Two-finger trackpad scroll is the standard way to pan/scroll content on macOS. Users expect this behavior.
2. **No conflicts:** `scrollWheel` events are distinct from mouse drag events, so they don't conflict with sidebar image reorder (`onMove`) or panel selection (`onTapGesture`).
3. **System integration:** The system handles momentum, elasticity, and scroll indicators automatically.
4. **Simpler:** One method override vs. gesture recognizer setup with delegate, state tracking, and conflict resolution.
5. **Preserves pinch zoom:** `MagnificationGesture` (pinch to zoom) operates on a different event type and won't interfere.

## Gesture Input Mode Separation

| Input Mode | Event Type | Handler | Purpose |
|------------|-----------|---------|---------|
| Two-finger trackpad scroll | `NSEventType.scrollWheel` | `scrollWheel(with:)` | Canvas pan |
| Trackpad pinch | `NSEventType.magnify` | `MagnificationGesture` | Zoom |
| Single finger tap | `NSEventType.leftMouseDown` | `onTapGesture` | Panel selection |
| Single finger drag | `NSEventType.leftMouseDrag` | Sidebar `onMove` | Image reorder |

These are distinct input modes handled by different systems, so there's no conflict.

## Relevance to CollageMaker Batch 4

The plan calls for an `NSViewRepresentable` with a transparent `NSView` that overrides `scrollWheel(with:)`. This approach:

1. Captures two-finger scroll events on the canvas overlay
2. Hit-tests the scroll location against panel frames to determine target
3. Converts scroll deltas to pan deltas with negation (`-scrollingDeltaX/Y`)
4. Tracks pan state via `NSEvent.Phase` (began → changed → ended)
5. Commits pan on `.ended` phase, with optional debounce for momentum

The existing `nsviarepresentable-integration.md` research already covers the `NSViewRepresentable` bridge pattern, coordinator setup, and coordinate conversion. The new `appkit-scrollwheel-events.md` research covers the scroll event specifics.
