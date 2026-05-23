# AppKit Scroll Wheel Events — NSEvent and NSResponder

## Source
- https://developer.apple.com/documentation/appkit/nsevent
- https://developer.apple.com/documentation/appkit/nsevent/scrollingdeltay
- https://developer.apple.com/documentation/appkit/nsevent/phase
- https://developer.apple.com/documentation/appkit/nsresponder/scrollwheel(with:)
- https://developer.apple.com/documentation/appkit/nsview/1483365-scrollwheel

## NSResponder.scrollWheel(with:)

```swift
func scrollWheel(with event: NSEvent)
```

Called when a scroll wheel event occurs. The default implementation passes this message to the next responder.

Override in an `NSView` subclass to capture scroll events:

```swift
class CustomView: NSView {
    override func scrollWheel(with event: NSEvent) {
        // Handle scroll event
        super.scrollWheel(with: event)
    }
}
```

## NSEvent Scroll Properties

### scrollingDeltaX / scrollingDeltaY

```swift
var scrollingDeltaX: CGFloat { get }
var scrollingDeltaY: CGFloat { get }
```

**This is the preferred property for accessing scroll wheel delta values.** When `hasPreciseScrollingDeltas` is `false`, multiply the value returned by this method by the line or row height. Otherwise scroll by the returned amount.

### deltaX / deltaY / deltaZ

```swift
var deltaX: CGFloat { get }
var deltaY: CGFloat { get }
var deltaZ: CGFloat { get }
```

Raw delta values. May or may not be precise depending on `hasPreciseScrollingDeltas`.

### hasPreciseScrollingDeltas

```swift
var hasPreciseScrollingDeltas: Bool { get }
```

Indicates whether the scrolling deltas are precise (pixel-based) or approximate (line-based). Trackpad two-finger scroll typically returns `true`. Mouse wheel typically returns `false`.

### isDirectionInvertedFromDevice

```swift
var isDirectionInvertedFromDevice: Bool { get }
```

Indicates whether the scrolling direction is inverted from the device's natural direction. This accounts for the "Natural Scrolling" system preference. **Important: Do not manually invert deltas — use `scrollingDeltaX/Y` which already account for this setting.**

## NSEvent.Phase

```swift
struct Phase : OptionSet {
    static var began: NSEvent.Phase
    static var stationary: NSEvent.Phase
    static var changed: NSEvent.Phase
    static var ended: NSEvent.Phase
    static var cancelled: NSEvent.Phase
    static var mayBegin: NSEvent.Phase
}
```

Tracks the phase of a continuous gesture (scroll, magnify, rotate, swipe).

| Phase | When It Fires |
|-------|---------------|
| `.mayBegin` | Gesture might begin (pre-recognition) |
| `.began` | Gesture recognized and began |
| `.stationary` | Gesture recognized but input hasn't moved |
| `.changed` | Gesture input has changed (continuous updates) |
| `.ended` | Gesture completed |
| `.cancelled` | Gesture interrupted by system |

### momentumPhase

```swift
var momentumPhase: NSEvent.Phase { get }
```

The phase of the momentum scroll, if any. After the user lifts their fingers, the scroll view may continue scrolling with momentum. This property tracks that momentum phase independently of the primary `phase`.

## NSEvent General Properties (Relevant to Scroll)

```swift
var locationInWindow: NSPoint { get }  // Mouse location in window coordinates
var timestamp: TimeInterval { get }     // Event timestamp
var type: NSEvent.EventType { get }     // Event type (.scrollWheel)
```

## Scroll Event Flow in AppKit

1. User performs two-finger scroll on trackpad (or uses mouse wheel)
2. System generates `NSEvent` with `type == .scrollWheel`
3. Event is delivered to the key view's first responder, then up the responder chain
4. `NSResponder.scrollWheel(with:)` is called on each responder
5. `NSScrollView` intercepts and handles the event for its content
6. If not handled, event continues up the responder chain

## Capturing Scroll Events in NSViewRepresentable

For the `ScrollPanView` use case, override `scrollWheel(with:)` in a custom `NSView`:

```swift
class ScrollPanNSView: NSView {
    override func scrollWheel(with event: NSEvent) {
        guard event.type == .scrollWheel else {
            super.scrollWheel(with: event)
            return
        }

        // Use scrollingDeltaX/Y (preferred, accounts for natural scrolling)
        let deltaX = -event.scrollingDeltaX
        let deltaY = -event.scrollingDeltaY

        // Convert window coords to view coords for hit testing
        let location = convert(event.locationInWindow, from: nil)

        switch event.phase {
        case .began:
            // Hit-test to find target panel
            if activePanelId == nil {
                activePanelId = hitTestPanel(at: location)
                if let id = activePanelId {
                    coordinator?.beginPan(id)
                }
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
        default:
            break
        }
    }
}
```

## Coordinate Conversion

```swift
// Convert event location from window coordinates to view coordinates
let viewLocation = convert(event.locationInWindow, from: nil)

// Convert from view coordinates to superview coordinates
let superviewLocation = convert(viewLocation, to: superview)

// Convert from view coordinates to window coordinates
let windowLocation = convert(viewLocation, to: nil)
```

## Scroll Event Timing Considerations

- Trackpad two-finger scroll generates many rapid `.changed` events
- Each `.changed` event contains a small delta (typically 1-5 points)
- `.ended` fires when fingers lift from trackpad
- Momentum scrolling continues after `.ended` with separate events where `momentumPhase` is set
- **For pan commit:** Use a debounce timer (100ms no-events) after `.ended` to handle momentum, or commit immediately on `.ended` and let momentum events create new pan sessions

## Relevance to CollageMaker Batch 4

This is the **core mechanism** for the two-finger scroll pan implementation:

1. **`scrollingDeltaX/Y`** are the preferred properties — they account for natural scrolling and precision
2. **`NSEvent.Phase`** maps directly to pan lifecycle: `began` → start pan, `changed` → apply delta, `ended` → commit pan
3. **`locationInWindow`** + `convert(_:from:)` provides the cursor position for panel hit testing
4. **`momentumPhase`** may need special handling — either ignore momentum events or use them for continued panning
5. **Negating deltas** (`-scrollingDeltaX`, `-scrollingDeltaY`) converts scroll direction to pan direction, matching the existing `DragGesture` behavior

### Direction Verification

```
Scroll down (finger moves up on trackpad) → scrollingDeltaY < 0 → pan(by: (0, -deltaY)) → positive Y delta
Drag down (finger moves down on screen)   → translation.height > 0 → pan(by: (0, translation.height)) → positive Y delta
Both produce same visual result: crop viewport moves down
```
