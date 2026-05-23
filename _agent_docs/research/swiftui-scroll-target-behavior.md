# SwiftUI ScrollTargetBehavior — Scroll Settling and Alignment

## Source
- https://developer.apple.com/documentation/swiftui/scrolltargetbehavior
- https://developer.apple.com/documentation/swiftui/view/scrolltargetlayout(isenabled:)
- https://developer.apple.com/documentation/swiftui/scrolltarget

## Overview

A scrollable view calculates where scroll gestures should end using its deceleration rate and the state of its scroll gesture by default. A scroll target behavior allows for customizing this logic.

## Protocol

```swift
protocol ScrollTargetBehavior {
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext)
}
```

You define a scroll behavior using the `updateTarget(_:context:)` method. Using this method, you can control where someone can scroll in a scrollable view.

### Custom Scroll Target Example

```swift
struct BasicScrollTargetBehavior: ScrollTargetBehavior {
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        // Align to every 1/10 the size of the scroll view.
        target.rect.x.round(
            toMultipleOf: round(context.containerSize.width / 10.0))
    }
}
```

## Built-In Behaviors

### PagingScrollTargetBehavior (`.paging`)

Uses the geometry of the scroll view to decide where to allow scrolls to end. Every view in the lazy stack is flexible in both directions and the scroll view will settle to container-aligned boundaries.

```swift
ScrollView {
    LazyVStack(spacing: 0.0) {
        ForEach(items) { item in
            FullScreenItem(item)
        }
    }
}
.scrollTargetBehavior(.paging)
```

### ViewAlignedScrollTargetBehavior (`.viewAligned`)

Always settles on the geometry of individual views. Configure which views should be used for settling using the `scrollTargetLayout(isEnabled:)` modifier.

```swift
ScrollView(.horizontal) {
    LazyHStack(spacing: 10.0) {
        ForEach(items) { item in
            ItemView(item)
        }
    }
    .scrollTargetLayout()  // Each child becomes a scroll target
}
.scrollTargetBehavior(.viewAligned)
.safeAreaPadding(.horizontal, 20.0)
```

## scrollTargetLayout(isEnabled:)

Apply this modifier to layout containers like `LazyHStack` or `VStack` within a `ScrollView` that contain the main repeating content. Each individual view in that layout will be considered for alignment.

```swift
func scrollTargetLayout(isEnabled: Bool = true) -> some View
```

Scroll target layouts act as a convenience for applying a `scrollTarget(isEnabled:)` modifier to each view in the layout. A scroll target layout ensures that any target layout nested within the primary one will not also become a scroll target layout.

```swift
LazyHStack { // a scroll target layout
    VStack { ... } // not a scroll target layout
    LazyHStack { ... } // also not a scroll target layout
}
.scrollTargetLayout()
```

## ScrollTarget Struct

```swift
struct ScrollTarget {
    var anchor: UnitPoint?
    var rect: CGRect
}
```

Provides the anchor point and rectangle for a scroll target. Used by `ScrollTargetBehavior.updateTarget(_:context:)` to modify where scrolling settles.

## ScrollTargetBehaviorContext

```swift
struct ScrollTargetBehaviorContext {
    var containerSize: CGSize
    // ... other properties
}
```

Provides context information to the `updateTarget(_:context:)` method, including the container size for calculating alignment.

## Relevance to CollageMaker Batch 4

**Not directly applicable to the canvas pan use case.** `ScrollTargetBehavior` is designed for controlling where a `ScrollView` settles after the user releases a scroll gesture — useful for paging, snapping to grid, or aligning to content boundaries.

For the CollageMaker canvas pan:
- We're not using a `ScrollView` for the canvas — we're capturing raw `scrollWheel` events on an `NSView` overlay.
- The scroll delta is converted directly to crop pan delta, not to scroll offset.
- No deceleration/settling behavior is needed — the pan is applied live and committed on gesture end.

However, `ScrollTargetBehavior` could be relevant if we later add:
- A scrollable thumbnail strip that snaps to individual thumbnails
- A properties panel that pages between sections
- Grid-aligned scrolling for layout templates

## Conforming Types

| Type | Purpose |
|------|---------|
| `AnyScrollTargetBehavior` | Type-erased wrapper |
| `PagingScrollTargetBehavior` | Page-by-page scrolling |
| `ViewAlignedScrollTargetBehavior` | Settle on individual view geometry |
