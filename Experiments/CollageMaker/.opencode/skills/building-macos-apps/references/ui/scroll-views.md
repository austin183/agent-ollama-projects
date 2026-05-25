# Scroll Views — ScrollView, ScrollPhase, ScrollTarget, and Custom Scroll Input

## When to Use ScrollView

`ScrollView` is the right primitive when you need to scroll content within a container. Standard uses include scrollable detail panels, horizontal thumbnail strips, and long forms.

**Do NOT use `ScrollView` for canvas panning.** Canvas pan is a crop viewport adjustment, not a scroll operation. The scroll delta adjusts the crop origin within each panel's source image, not a content offset. Use raw `scrollWheel(with:)` events on an `NSView` overlay instead.

| ScrollView | Canvas Pan |
|---|---|
| Scrolls content within a container | Adjusts crop rectangle within source image |
| Content offset changes | Crop origin changes per panel |
| Deceleration and momentum built-in | Must implement manually |
| Scroll indicators managed by system | No scroll indicators needed |
| Works with LazyVStack/LazyHStack | Works with composite image overlay |

## ScrollView Basics

```swift
// Single axis (vertical by default)
ScrollView { content }

// Both axes
ScrollView([.horizontal, .vertical], showsIndicators: true) { content }

// No scroll bars
ScrollView(.vertical, showsIndicators: false) { content }
```

## Controlling Scroll Position

### defaultScrollAnchor

```swift
ScrollView([.horizontal, .vertical]) { content }
    .defaultScrollAnchor(.center)   // Start centered
```

### ScrollViewReader and ScrollViewProxy

For programmatic scrolling, wrap with `ScrollViewReader`:

```swift
@Namespace var topID
@Namespace var bottomID

var body: some View {
    ScrollViewReader { proxy in
        ScrollView {
            Button("Scroll to Bottom") {
                withAnimation {
                    proxy.scrollTo(bottomID)
                }
            }
            .id(topID)

            // ... content ...

            Button("Top") {
                withAnimation {
                    proxy.scrollTo(topID)
                }
            }
            .id(bottomID)
        }
    }
}
```

**Important:** You may NOT use `ScrollViewProxy` during execution of the content view builder. Only actions created within content can call the proxy (e.g., gesture handlers, `onChange`).

### scrollPosition(id:anchor:)

Two-way binding for scroll position by target ID:

```swift
ScrollView {
    ForEach(items) { item in
        ItemView(item)
            .id(item.id)
    }
}
.scrollPosition(id: $scrollItemID, anchor: .top)
```

## Scroll Target Behavior (Snapping and Paging)

Control where a scroll view settles after the user releases a scroll gesture.

### Built-in Behaviors

```swift
// Page-by-page scrolling — settles to container-aligned boundaries
ScrollView {
    LazyVStack(spacing: 0) {
        ForEach(items) { FullScreenItem($0) }
    }
}
.scrollTargetBehavior(.paging)

// View-aligned — settles on individual view geometry
ScrollView(.horizontal) {
    LazyHStack(spacing: 10) {
        ForEach(items) { ItemView($0) }
    }
    .scrollTargetLayout()  // Each child becomes a scroll target
}
.scrollTargetBehavior(.viewAligned)
```

### Custom Scroll Target Behavior

```swift
struct GridScrollTargetBehavior: ScrollTargetBehavior {
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        target.rect.x.round(toMultipleOf: round(context.containerSize.width / 10.0))
    }
}
```

### scrollTargetLayout

Apply to layout containers (`LazyHStack`, `VStack`) within a `ScrollView`. Each individual view becomes a scroll target. Nested target layouts are NOT also targets.

## ScrollPhase and ScrollGeometry (Monitoring Scroll State)

### ScrollPhase

A scroll gesture has four phases:

| Phase | Description |
|---|---|
| `idle` | No active scroll |
| `panning` | User is actively scrolling |
| `decelerating` | Scroll view decelerating to final target |
| `animating` | System animating to target from programmatic scroll |

`ScrollPhase.isScrolling` returns `true` for `panning`, `decelerating`, or `animating`.

### onScrollPhaseChange

```swift
ScrollView { content }
    .onScrollPhaseChange { oldPhase, newPhase in
        if newPhase == .idle {
            // Scroll complete — update selection, hide overlays, etc.
        }
    }

// With geometry and velocity context
.onScrollPhaseChange { oldPhase, newPhase, context in
    let offset = context.geometry.contentOffset.y
    let velocity = context.velocity  // CGVector(dx, dy)
}
```

**Important limitation:** If multiple scroll views exist in the view hierarchy, only the first one triggers the closure. A runtime issue will be logged.

### ScrollGeometry

```swift
struct ScrollGeometry {
    var bounds: CGRect           // Scroll view bounds
    var containerSize: CGSize    // Scrollable container size
    var contentInsets: EdgeInsets
    var contentOffset: CGPoint   // Current scroll offset
    var contentSize: CGSize      // Total scrollable content size
    var visibleRect: CGRect      // Currently visible portion
}
```

### onScrollGeometryChange

Monitor geometry property changes:

```swift
ScrollView { content }
    .onScrollGeometryChange(for: CGPoint.self) { geometry in
        geometry.contentOffset
    } action: { oldOffset, newOffset in
        // React to offset changes
    }
```

## Useful Scroll Modifiers

| Modifier | Purpose |
|---|---|
| `scrollTargetBehavior(_:)` | Paging, view-aligned, or custom settling |
| `scrollTargetLayout(isEnabled:)` | Mark children as scroll targets |
| `scrollDisabled(_:)` | Disable scrolling (passes through environment) |
| `scrollBounceBehavior(_:axes:)` | Configure bounce at edges (`.automatic`, `.always`, `.basedOnSize`) |
| `scrollIndicators(_:axes:)` | Control scroll bar visibility |
| `scrollIndicatorsFlash(onAppear:)` | Flash scroll bars to draw attention |
| `scrollContentBackground(_:)` | Control content background |
| `scrollClipDisabled(_:)` | Disable content clipping |
| `defaultScrollAnchor(_:)` | Set initial scroll position |
| `onScrollPhaseChange(_:)` | Monitor scroll phase changes |
| `onScrollGeometryChange(_:action:)` | Monitor geometry changes |
| `onScrollTargetVisibilityChange(_:threshold:)` | Monitor target visibility |

## HIG Guidelines

### Nesting Rules

- **Avoid nesting scroll views with the same orientation** — creates unpredictable, hard-to-control interface
- **Cross-orientation nesting is fine** — horizontal inside vertical (or vice versa) works well

### Scroll Indicators

- Scroll indicators are translucent and appear after scrolling begins
- On macOS, scroll indicators are commonly called scroll bars
- Use small or mini scroll bars in panels when space is tight
- Indicators provide visual feedback about scroll position and proportion of visible content

### Making Content Appear Scrollable

Because scroll indicators aren't always visible, make it obvious when content extends beyond the view. Displaying partial content at the edge indicates more content exists.

### Scroll Edge Effects

A scroll edge effect is a variable blur between content and Liquid Glass controls (toolbars, etc.). The system applies automatically when a pinned element overlaps scrolling content.

| Style | Platform | Use |
|---|---|---|
| Soft edge | iOS, iPadOS, most macOS cases | Subtle transition for toolbars |
| Hard edge | macOS | Stronger boundary for interactive text, backless controls, pinned headers |

Only use when a scroll view is adjacent to floating interface elements. They are not decorative.

## Custom Scroll Input (Canvas Pan Pattern)

When you need scroll input to drive something other than a `ScrollView` (e.g., adjusting a crop viewport), capture raw `scrollWheel(with:)` events on an `NSView` overlay.

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
            // Convert scroll delta to pan delta
            let deltaX = event.scrollingDeltaX
            let deltaY = event.scrollingDeltaY
            onScroll(deltaX, deltaY)
        }
    }
}
```

**Key points:**
- Two-finger scroll is the macOS convention — `scrollWheel` events are the right approach
- Custom scroll behavior should feel natural with momentum and bounce (per HIG)
- `NSEvent.Phase` tracks gesture state: `.began`, `.changed`, `.ended`, `.cancelled`
- `NSEvent.isDirectionInvertedFromDevice` — check this to handle trackpad vs mouse correctly
- The `NSView` overlay approach captures native `NSEvent` events, preserving system feel

## Common Pitfalls

1. **`onScrollPhaseChange` only fires for first ScrollView** — If multiple scroll views exist in the hierarchy, only the first triggers the closure
2. **`ScrollViewProxy` cannot be called in view builder** — Only callable from within content actions (gesture handlers, `onChange`)
3. **Nested same-orientation scroll views** — Creates unpredictable scrolling behavior per HIG
4. **`scrollDisabled(_:)` propagates through environment** — Affects all scroll views in the hierarchy, not just the target
5. **Using ScrollView for canvas pan** — Canvas pan adjusts crop viewport, not scroll offset. Use raw `scrollWheel` events instead
6. **`NSEvent.Phase` differs from iOS** — `.failed` is iOS-only. macOS phases: `.began`, `.changed`, `.ended`, `.cancelled`, `.mayBegin`.

## Typical CollageMaker Uses

1. **Detail panel** — Wrap inspector `VStack` in `ScrollView` for scrollable properties
2. **Hero thumbnail strip** — Horizontal `ScrollView` with `LazyHStack` of thumbnails. Use `.scrollTargetBehavior(.viewAligned)` + `.scrollTargetLayout()` for snapping
3. **Sidebar image list** — `Form`/`NSTableView` provides its own scrolling
4. **Canvas pan** — `scrollWheel(with:)` override on `NSView` overlay, NOT `ScrollView`
