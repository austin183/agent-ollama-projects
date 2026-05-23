# SwiftUI ScrollPhase and ScrollGeometry — Monitoring Scroll State

## Source
- https://developer.apple.com/documentation/swiftui/scrollphase
- https://developer.apple.com/documentation/swiftui/scrollgeometry
- https://developer.apple.com/documentation/swiftui/view/onscrollphasechange(_:):
- https://developer.apple.com/documentation/swiftui/scrollphasechangecontext

## ScrollPhase

```swift
@frozen enum ScrollPhase
```

A scroll gesture can be in one of four phases:

| Phase | Description |
|-------|-------------|
| `idle` | No active scroll is occurring |
| `panning` | An active scroll being driven by the user is occurring |
| `decelerating` | The user has stopped driving a scroll and the scroll view is decelerating to its final target |
| `animating` | The system is animating to a final target as a result of a programmatic animated scroll from using a ScrollViewReader or scrollPosition(id:anchor:) modifier |

### Checking for Active Scrolling

```swift
var isScrolling: Bool
```

Returns `true` when the scroll phase is `panning`, `decelerating`, or `animating`.

### Platform-Specific Phase Names

On macOS, the phases may also be referenced as:
- `tracking` — User is actively scrolling
- `interacting` — User interaction in progress
- `mayBegin` — Gesture may begin

## onScrollPhaseChange(_:)

```swift
func onScrollPhaseChange(_ action: @escaping (ScrollPhase, ScrollPhase) -> Void) -> some View
```

Use this modifier to be informed of changes to a scroll view's phase. When the phase changes, the system invokes the action.

### Basic Usage

```swift
@Binding var selection: SelectionValue?

ScrollView {
    // ...
}
.onScrollPhaseChange { oldPhase, newPhase in
    if newPhase == .decelerating || newPhase == .idle {
        selection = updateSelection()
    }
}
```

### With Context (Geometry and Velocity)

```swift
@Binding var hidesToolbarContent: Bool
@State private var lastOffset: CGFloat = 0.0

ScrollView {
    // ...
}
.onScrollPhaseChange { oldPhase, newPhase, context in
    if newPhase == .interacting {
        lastOffset = context.geometry.contentOffset.y
    }
    if oldPhase == .interacting, newPhase != .animating,
        context.geometry.contentOffset.y - lastOffset < 0.0
    {
        hidesToolbarContent = true
    } else {
        hidesToolbarContent = false
    }
}
```

### Important Limitation

If multiple scroll views are found within the view hierarchy, only the first one will invoke the closure and a runtime issue will be logged:

```swift
VStack {
    ScrollView(.vertical) { ... }  // Only this one triggers the closure
    ScrollView(.horizontal) { ... }
}
.onScrollPhaseChange { ... }
```

## ScrollPhaseChangeContext

```swift
struct ScrollPhaseChangeContext {
    var geometry: ScrollGeometry
    var velocity: CGVector?
}
```

You don't create this type directly. SwiftUI provides an instance in the `onScrollPhaseChange(_:)` modifier.

- **geometry** — The current scroll geometry at the time of the phase change
- **velocity** — The scroll velocity as a `CGVector` (dx, dy)

## ScrollGeometry

```swift
struct ScrollGeometry {
    var bounds: CGRect           // The scroll view's bounds
    var containerSize: CGSize    // Size of the scrollable container
    var contentInsets: EdgeInsets // Insets applied to content
    var contentOffset: CGPoint   // Current scroll offset
    var contentSize: CGSize      // Total size of scrollable content
    var visibleRect: CGRect      // Currently visible portion of content
}
```

SwiftUI provides values of this type when using modifiers like `onScrollGeometryChange(_:action:)` or `onScrollPhaseChange(_:)`.

### Initializer

```swift
init(contentOffset: CGPoint, contentSize: CGSize, contentInsets: EdgeInsets, containerSize: CGSize)
```

## onScrollGeometryChange(_:action:)

```swift
func onScrollGeometryChange<T>(
    for: T.Type,
    of: (ScrollGeometry) -> T,
    action: (T, T) -> Void
) -> some View
```

Monitors changes to scroll geometry properties. The closure receives the old and new values of the extracted property.

## Related Modifiers

### scrollDisabled(_:)

```swift
func scrollDisabled(_ disabled: Bool) -> some View
```

Controls whether a `ScrollView` can scroll. Passes through the environment, affecting all scroll views in the hierarchy.

### scrollBounceBehavior(_:axes:)

```swift
func scrollBounceBehavior(
    _ behavior: ScrollBounceBehavior,
    axes: Axis.Set = [.vertical]
) -> some View
```

Configures bounce behavior when scrolling to the end of content.

### ScrollBounceBehavior Values

| Value | Description |
|-------|-------------|
| `.automatic` | System-determined bounce behavior |
| `.always` | Always bounce at content edges |
| `.basedOnSize` | Only bounce if content is large enough to require scrolling |

## Relevance to CollageMaker Batch 4

**Limited direct applicability, but useful for understanding scroll state.**

For the `ScrollPanView` implementation:
- `ScrollPhase` concepts map to `NSEvent.Phase` in the AppKit layer:
  - `ScrollPhase.idle` ↔ No scroll events
  - `ScrollPhase.panning` ↔ `NSEvent.Phase.began` + `NSEvent.Phase.changed`
  - `ScrollPhase.decelerating` ↔ `NSEvent.Phase.ended` (momentum scrolling)
- `ScrollGeometry.contentOffset` is analogous to tracking cumulative pan delta
- `ScrollPhaseChangeContext.velocity` maps to computing velocity from scroll deltas

The `onScrollPhaseChange` modifier is designed for `ScrollView` — since we're using raw `scrollWheel` events on an `NSView` overlay, we handle phase tracking manually via `NSEvent.mPhase`.

However, these SwiftUI scroll modifiers could be useful for:
- The sidebar `ScrollView` with thumbnail strip (Batch 2, item #4)
- The detail panel `ScrollView` (Batch 1, item #1)
- Flashing scroll indicators when focus shifts to a panel
