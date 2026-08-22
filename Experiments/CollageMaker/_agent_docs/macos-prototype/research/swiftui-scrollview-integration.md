# SwiftUI ScrollView Integration Patterns for Custom Content

## Source
- https://developer.apple.com/documentation/swiftui/scrollview
- https://developer.apple.com/documentation/swiftui/scrollviewreader
- https://developer.apple.com/documentation/swiftui/view/scrolltargetlayout(isenabled:)
- Existing research: `swiftui-scroll-target-behavior.md`, `swiftui-scroll-phase-geometry.md`

## ScrollView Basics

```swift
struct ScrollView<Content> where Content : View
```

The scroll view displays its content within the scrollable content region. As the user performs platform-appropriate scroll gestures, the scroll view adjusts what portion of the underlying content is visible. `ScrollView` can scroll horizontally, vertically, or both, but does not provide zooming functionality.

### Initializers

```swift
// Single axis (vertical by default)
init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content)

// With content and indicator control
init(_ axes: Axis.Set, content: () -> Content)
```

### Properties

```swift
var content: Content
var axes: Axis.Set
var showsIndicators: Bool
```

## Controlling Scroll Position

### defaultScrollAnchor(_:)

Influences where a scroll view is initially scrolled:

```swift
// Start in center of content
ScrollView([.horizontal, .vertical]) {
    // content
}
.defaultScrollAnchor(.center)

// Start at bottom
ScrollView {
    // content
}
.defaultScrollAnchor(.bottom)
```

### ScrollViewReader / ScrollViewProxy

For programmatic scrolling, wrap scroll views with a `ScrollViewReader`:

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

**Important:** You may not use the `ScrollViewProxy` during execution of the content view builder. Only actions created within content can call the proxy, such as gesture handlers or `onChange(of:perform:)`.

### scrollPosition(id:anchor:)

```swift
func scrollPosition(id: Binding<Hashable?>, anchor: UnitPoint?) -> some View
```

Two-way binding for scroll position by target ID.

## Scroll Target System

The scroll target system provides fine-grained control over scroll settling behavior:

| Component | Purpose |
|-----------|---------|
| `scrollTargetBehavior(_:)` | Set paging, view-aligned, or custom settling |
| `scrollTargetLayout(isEnabled:)` | Mark a layout container's children as scroll targets |
| `ScrollTarget` | Represents a target's anchor and rectangle |
| `ScrollTargetBehavior` | Protocol for custom scroll settling logic |

## Modifiers Summary

| Modifier | Purpose |
|----------|---------|
| `scrollTargetBehavior(_:)` | Control scroll settling (paging, view-aligned, custom) |
| `scrollTargetLayout(isEnabled:)` | Mark children as scroll targets |
| `scrollDisabled(_:)` | Disable scrolling entirely |
| `scrollBounceBehavior(_:axes:)` | Configure bounce at content edges |
| `scrollIndicators(_:axes:)` | Control scroll bar visibility |
| `scrollIndicatorsFlash(onAppear:)` | Flash scroll bars to draw attention |
| `scrollContentBackground(_:)` | Control content background visibility |
| `scrollClipDisabled(_:)` | Disable content clipping |
| `defaultScrollAnchor(_:)` | Set initial scroll position |
| `onScrollPhaseChange(_:)` | Monitor scroll phase changes |
| `onScrollGeometryChange(_:action:)` | Monitor geometry changes |
| `onScrollTargetVisibilityChange(_:threshold:)` | Monitor which targets are visible |
| `onScrollVisibilityChange(_:)` | Monitor view visibility in scroll container |

## When NOT to Use ScrollView for Canvas Panning

The CollageMaker canvas is a **fixed-size composite image** (1920x1080) displayed within a preview frame. The "panning" operation doesn't scroll a scrollable container — it adjusts the crop viewport within each panel's source image. This is fundamentally different from scrolling:

| ScrollView | Canvas Pan |
|------------|-----------|
| Scrolls content within a container | Adjusts crop rectangle within source image |
| Content offset changes | Crop origin changes per panel |
| Deceleration and momentum built-in | Must implement manually |
| Scroll indicators managed by system | No scroll indicators needed |
| Works with LazyVStack/LazyHStack | Works with composite image overlay |

**Conclusion:** `ScrollView` is not the right primitive for canvas panning. The `scrollWheel(with:)` override on an `NSView` overlay is the correct approach because it captures the raw scroll input and converts it to crop pan deltas, without the overhead and constraints of a `ScrollView`.

## Where ScrollView IS Used in CollageMaker

1. **Detail panel** (Batch 1, item #1) — Wrap the inspector `VStack` in `ScrollView` for scrollable properties
2. **Hero thumbnail strip** (Batch 2, item #4) — Horizontal `ScrollView` with `HStack` of thumbnail buttons
3. **Sidebar image list** — The `Form`/`NSTableView` provides its own scrolling

For these uses, the standard `ScrollView` patterns apply. `scrollTargetBehavior(.viewAligned)` could be useful for the hero thumbnail strip to snap to individual thumbnails.

## Relevance to CollageMaker Batch 4

The `ScrollView` research confirms that:
1. **Canvas panning is not a scroll operation** — it's a crop viewport adjustment triggered by scroll input
2. **Raw `scrollWheel` events are the right abstraction** — they give us the input without `ScrollView` semantics
3. **`ScrollView` is used elsewhere** — detail panel and thumbnail strip benefit from standard `ScrollView` patterns
4. **`ScrollViewReader` could help** — if we need programmatic scrolling in the detail panel or thumbnail strip
