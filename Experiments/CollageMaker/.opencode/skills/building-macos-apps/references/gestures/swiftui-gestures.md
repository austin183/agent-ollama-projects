# SwiftUI Gestures — Core APIs, Coordinate Spaces, and Composition

## DragGesture — Location and Coordinate Space

`DragGesture` provides location information through `DragGesture.Value`:

| Property | Type | Available In | Description |
|---|---|---|---|
| `location` | `CGPoint` | `onChanged`, `onEnded` | Current pointer location in gesture's coordinate space |
| `startLocation` | `CGPoint` | `onChanged`, `onEnded` | Location where gesture began |
| `translation` | `CGSize` | `onChanged`, `onEnded` | Delta from start to current position |
| `predictedEndLocation` | `CGPoint` | `onChanged` only | Predicted final location based on velocity |
| `velocity` | `CGSize` | `onEnded` only | Velocity at gesture end |

**Key finding:** `location` is available in both `onChanged` and `onEnded` — confirmed by Apple docs. Use for hit testing during drag.

### Coordinate Space Configuration

```swift
// Default: local coordinate space of the view's parent
DragGesture()

// Explicit local
DragGesture(coordinateSpace: .local)

// Global screen coordinates
DragGesture(coordinateSpace: .global)

// Named coordinate space — maps to ancestor view
DragGesture(coordinateSpace: .named("preview"))
```

## CoordinateSpace Protocol

| Space | Usage | Description |
|---|---|---|
| `.local` | Default | Local coordinate space of view's parent |
| `.global` | Screen-wide | Global screen coordinate space |
| `.named(_:)` | Ancestor-scoped | Named space defined by ancestor view |

### Named Coordinate Spaces

```swift
VStack {
    GeometryReader { proxy in
        // proxy.frame(in: .named("container")) gives frame in ancestor's space
    }
}
.coordinateSpace(.named("container"))

// Reference in gesture:
DragGesture(coordinateSpace: .named("preview"))
```

## Gesture Composition

### Simultaneous Gestures

```swift
// Using modifier
view
    .gesture(drag)
    .simultaneousGesture(magnify)

// Using type
let combined = SimultaneousGesture(drag, magnify)
```

### Sequenced Gestures

```swift
LongPressGesture(minimumDuration: 0.5)
    .sequenced(before: DragGesture())
```

### Exclusive Gestures

```swift
let either = ExclusiveGesture(tap, longPress)
```

## GestureMask — Controlling Propagation

| Option | Effect |
|---|---|
| `.all` | Default — competes with view and subview gestures |
| `.gesture` | Only competes with view's own gestures |
| `.subviews` | Only competes with subview gestures |
| `.none` | Doesn't compete with any existing gestures |

```swift
view.gesture(drag, including: .gesture)  // Doesn't interfere with subviews
```

## MagnificationGesture (Pinch-to-Zoom on macOS)

```swift
@GestureState private var magnifyBy = 1.0

var magnification: some Gesture {
    MagnificationGesture()
        .updating($magnifyBy) { value, state, _ in
            state = value.magnification
        }
}

// On macOS: scroll wheel + Option key, or trackpad pinch
```

### Cumulative Magnification Values

`MagnificationGesture.Value.magnification` is **cumulative** from gesture start, NOT incremental:
- `1.0` = no change from gesture start
- `> 1.0` = fingers spread (user wants to zoom **in**)
- `< 1.0` = fingers squeezed (user wants to zoom **out**)

This means `onChanged` fires with the total magnification since the gesture began, not the delta since the last call.

### Zoom Direction: Division, Not Multiplication

When zooming controls a source rect (showing a portion of a larger image), the relationship is **inverse**: zooming in means a **smaller** source rect. Therefore:

```swift
// WRONG — multiplying by magnification > 1 makes source rect larger (zooms out)
let newZoom = baseZoom * magnification

// CORRECT — dividing by magnification > 1 makes source rect smaller (zooms in)
let newZoom = baseZoom / magnification
```

The mental model: spreading fingers (magnification > 1) should show a smaller portion of the image at full display size. Division achieves this by shrinking the source rect.

### Zoom Percentage Display

If displaying zoom percentage to the user, the intuitive formula depends on your semantics:

```swift
// "How much of the source image is visible?" — decreases as you zoom in
let pct = sourceW / destW * 100

// "How zoomed in am I?" — increases as you zoom in (recommended)
let pct = destW / sourceW * 100
```

Use `destW / sourceW` for the expected behavior: higher percentage = more zoomed in.

### Live Preview During Gestures

For responsive gesture feedback, update preview during `onChanged`, not just `onEnded`. Use the `finish: Bool` pattern on your gesture handler methods:

```swift
// In your manager/viewmodel:
func applyPan(panelId: UUID, finish: Bool = true) {
    if finish {
        // Commit: clear gesture state, update base values
        gestureState = nil
    }
    // Apply transform and trigger preview (both live and final)
    updatePreview()
}

// In your view:
.onChanged { value in
    viewModel.applyPan(panelId: id, finish: false)  // Live update
}
.onEnded { _ in
    viewModel.applyPan(panelId: id, finish: true)   // Commit
}
```

### Commit Timer State Reset During Sustained Gestures

When a gesture uses a commit timer (e.g., 150ms `DispatchWorkItem`) that calls `endGesture()` mid-scroll, `endGesture()` clears `gestureBaseOrigin`. The next delta call to `applyPan(finish: false)` then fails its guard because `gestureBaseOrigin` is `nil`.

**Fix:** Immediately re-call `beginPan(panelId:)` after the commit timer fires to re-establish the base origin, so continued scrolling works seamlessly:

```swift
// After commit timer fires:
cropManager.applyPan(panelId: id, finish: true)  // Calls endGesture() internally
cropManager.beginPan(panelId: id)                // Re-establishes gestureBaseOrigin
```

### Debounce-Free Live Preview with Task Cancellation

When live preview triggers expensive work (e.g., image rendering), use `Task.detached` with cancellation instead of explicit debounce:

```swift
@MainActor
class CropManager: ObservableObject {
    private var previewTask: Task<Void, Never>?

    func updatePreview() {
        // Cancel any in-flight preview — handles rapid gesture ticks
        previewTask?.cancel()

        previewTask = Task.detached { [weak self] in
            // Heavy rendering work...
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self?.previewImage = renderedImage
            }
        }
    }
}
```

`previewTask?.cancel()` at the top of `updatePreview()` naturally drops stale work without debounce timers or frame-rate limiting.

### Throttled Background Render for Live Feedback

The cancel-previous-task pattern above works for low-frequency gestures. For high-frequency gestures (~60fps `DragGesture.onChanged`), every render gets cancelled because the next event arrives before the render completes. Throttle instead:

```swift
private var lastScrollRenderTime: ContinuousClock.Instant = .now

private func throttledScrollPanRender() {
    let now = ContinuousClock.now
    guard now - lastScrollRenderTime >= FrameTempo.scrollRenderInterval else { return }
    lastScrollRenderTime = now

    previewDebounceTask?.cancel()
    previewDebounceTask = Task.detached { [weak self] in
        guard !Task.isCancelled else { return }
        await MainActor.run { self?.updatePanelPreview() }
    }
}
```

**Debounce vs throttle choice:**
- **Debounce** (sleep N ms, render after quiet period) — good for final-quality render after user stops interacting. Bad for live feedback.
- **Throttle** (fire every N ms during active input) — gives responsive feedback during gesture. Use `Task.detached` + `await MainActor.run` for offloading rendering while safely mutating `@Observable` state.
- For scroll pan (moving through content), ~16fps (60ms) throttle is sufficient. For pinch zoom (precise framing), render on every throttled gesture event. Source intervals from a centralized timing enum rather than inline literals — see [references/tooling/performance-debugging.md](references/tooling/performance-debugging.md) § "Centralized Timing Constants".

**Non-layered mode feedback:** In rendering modes where the preview is a static composite (not per-layer), crop changes don't affect pixel content. `cropMapVersion`-driven frame updates only affect overlays visible in layered mode. Throttled render of the full composite is required for live feedback in non-layered mode.

## Key Findings

1. **`DragGesture.location` available in `onChanged`** — use for hit testing during drag
2. **`SimultaneousGesture` combines drag + pinch** — or use `.simultaneousGesture()` modifier
3. **`MagnificationGesture` has no location** — `Value` is `CGFloat` only. Cannot hit-test panel under pinch. Target the selected panel.
4. **No `.onStarted` on `DragGesture`/`MagnificationGesture`** — Use `@State` flag in first `onChanged` for gesture initialization
5. **Coordinate conversion is critical** — `previewToCanvas()` must account for aspect-ratio fit scaling

## Pitfalls

- **`MagnificationGesture` has no location** — `Value` is `CGFloat` only. Cannot hit-test panel under pinch. Target the selected panel.
- **No `.onStarted` on `DragGesture`/`MagnificationGesture`** — Use `@State` flag in first `onChanged` for gesture initialization
- **`MagnificationGesture` cumulative values invert zoom direction** — `value.magnification` is cumulative from gesture start (>1 = spread fingers = zoom in). For source-rect zoom, use `baseZoom / magnification` (division), NOT `baseZoom * magnification` (multiplication). Multiplying makes the source rect larger, which zooms out.
- **Zoom percentage display is counterintuitive** — `sourceW / destW * 100` decreases as you zoom in. Use `destW / sourceW * 100` for the expected behavior: higher percentage = more zoomed in.
- **`onEnded`-only updates are jarring** — Users expect live preview during drag/pinch. Use `finish: Bool` parameter on gesture methods: `finish: false` in `onChanged` for live updates, `finish: true` in `onEnded` to commit.
- **`NSEvent.Phase` differs from iOS** — `.failed` is iOS-only. macOS phases: `.began`, `.changed`, `.ended`, `.cancelled`, `.mayBegin`.
- **`NSView.isOpaque` is get-only on macOS** — Cannot be set directly. It's computed from `wantsLayer` + `layer?.isOpaque`. An `NSView` overlay is transparent by default when no drawing is performed.
- **Cumulative translation compounds with live binding state** — `DragGesture.Value.translation` is cumulative from drag start. If the target state is read from a `@Bindable` property inside `onChanged`, the binding returns the already-updated state each tick, causing compounding. Capture the base state at drag start in a `@State` variable. Never re-read the live binding for the base during the gesture.
- **Pan manager subtraction inverts direct drag** — A pan method that computes `baseOrigin - panDelta` implements indirect scroll semantics. Direct drag requires negated translation or bypassing the pan pipeline entirely.
- **Hardcoded zoom limits don't scale** — `clamp(min: 0.5, max: 3.0)` assumes a fixed image/panel relationship. When the image is much larger than the panel, the max prevents zooming out enough to see the full image. Compute the zoom-out limit dynamically from actual dimensions.
- **CG-rendered content needs CG live preview, not SwiftUI overlay** — SwiftUI `Text` uses a different font engine than `NSAttributedString.draw(in:)`. Font metrics (ascent, descent, leading, em-square) differ even with identical font descriptors. A SwiftUI overlay will never match CG output pixel-for-pixel. For live gesture feedback on CG-rendered content (titles, watermarks, annotations), debounce the CG render at ~150ms on the specific layer, not the full composite. Show the pre-rendered `NSImage` during the debounce gap for continuity. Cancel the debounce task and run a full composite on gesture end.
- **High-frequency gesture cancels every render** — `DragGesture.onChanged` fires at ~60fps. The "cancel previous task + schedule new render" pattern will cancel every render because the next event arrives before the render completes. Throttle the render cadence at the ViewModel level (e.g., 50ms) instead of canceling on every event.
- **Body re-evaluation cascade from gesture state** — Writing to `@Observable` or parent `@State` on every `onChanged` tick re-evaluates all sibling views. Fix: isolate gesture state in a self-contained struct with local `@State`, sync to ViewModel once on `onEnded`. See [references/state/observable-bindable.md](references/state/observable-bindable.md) § "Body Re-evaluation Cascades During Gestures"
- **Zoom anchor drift from using new bounds for both anchor and offset** — When computing the zoom anchor, the anchor's source coordinate must come from the old (pre-zoom) crop, while the offset uses the new (post-zoom) visible region. Using new bounds for both creates a feedback loop — the anchor itself moves as zoom changes, causing visible drift on every pinch.
- **Center-based zoom drifts on sheared parallelograms** — For `.path` panels with diagonal edges, `boundingBox.width/2` as the anchor drifts proportionally to `tan(angle)/2`. Use a fixed corner anchor (top-left for left-clipped, bottom-right for right-clipped) instead of any computed center.
- **Anchoring to `sourceRect.midX` drifts off-canvas panels** — The full source rect center differs from the visible center by `(scaledW - visibleW)/2`. Always anchor to a point the user can see, not to a point that may be off-screen.

### Dynamic Zoom Bounds

When zoom controls a source rect (showing a portion of a larger image), the zoom-out limit must be computed from the image and panel sizes:

```swift
// Zoom-out limit: largest source rect that fits inside the image
let maxZoomOut = Swift.min(image.size.width / panelSize.width,
                           image.size.height / panelSize.height)

// Zoom-in floor: fixed constant (content-independent)
let minZoomIn: CGFloat = 0.5  // 2x magnification

let newZoom = clamp(baseZoom / magnification, min: minZoomIn, max: maxZoomOut)
```

**Why `min` on both axes:** The source rect maintains the panel's aspect ratio. The dimension with the smaller `image/panel` ratio is the constraining axis — the source rect would exceed the image boundary on that axis first. `min` picks the tighter constraint without branching on aspect ratio comparisons.

**Zoom factor semantics:** The zoom factor `sourceW / panelW` is the natural unit:
- `1.0` — source rect matches panel size (1:1 display)
- `> 1.0` — zoomed in (source rect larger than panel, showing smaller image portion)
- `< 1.0` — zoomed out (source rect smaller than panel, image stretched)

The max zoom-out is where the source rect equals the largest panel-aspect-matched rect that fits inside the image.

**Zoom-in floor is constant:** Unlike zoom-out (content-dependent), zoom-in has a fixed semantic floor. `0.5` means the source rect is half the panel size (2x magnification), independent of image dimensions.

### Zoom Anchor Computation

When applying pinch zoom, the anchor point must remain visually fixed. The anchor's **source coordinate** comes from the **old** (pre-zoom) crop, while the **offset** subtracted uses the **new** (post-zoom) visible region. Using new bounds for both creates feedback drift — the anchor moves as zoom changes.

```swift
// NEW visible bounds (post-zoom dimensions)
let visBounds = Self.computeVisibleSourceBounds(
    destRect: crop.destinationRect, sourceW: scaledW, sourceH: scaledH
)

// OLD visible bounds (pre-zoom, from current crop)
let oldVisBounds = Self.computeVisibleSourceBounds(
    destRect: crop.destinationRect,
    sourceW: crop.sourceRect.width, sourceH: crop.sourceRect.height
)

// Anchor source coordinate from OLD crop (the point that should stay fixed)
let anchorEffX = crop.sourceRect.origin.x + oldVisBounds.offsetX + oldVisBounds.visibleW / 2

// Anchor offset within NEW visible region
let anchorOffsetX = visBounds.visibleW / 2

// New origin = anchor coordinate minus offset
let maxEffX = max(0, image.size.width - visBounds.visibleW)
let newEffX = clamp(anchorEffX - anchorOffsetX, min: 0, max: maxEffX)
let newOX = newEffX - visBounds.offsetX
```

**Why old bounds for the anchor:** The anchor is a point in the image that should not move during zoom. It is defined by the current (pre-zoom) crop state. Using new bounds shifts the anchor as zoom changes.

**Why new bounds for the offset:** The offset represents "distance from anchor to the new source rect origin." It must use new visible dimensions since that is what the source rect will be after zoom.

### Corner Anchors for Irregular Shapes

For `.path` panels (parallelograms, triangles, hexagons), center-based zoom drifts on sheared shapes — drift proportional to `tan(angle)/2`. At 43° this is obvious. Use a fixed corner anchor instead:

```swift
if dest.minX < 0 {
    // Left edge clipped — anchor at top-left
    anchorEffX = baseEffX; anchorOffsetX = 0
    anchorEffY = baseEffY; anchorOffsetY = 0
} else if dest.maxX > canvasWidth {
    // Right edge clipped — anchor at bottom-right
    anchorEffX = baseEffX + oldVisBounds.visibleW; anchorOffsetX = visBounds.visibleW
    anchorEffY = baseEffY + oldVisBounds.visibleH; anchorOffsetY = visBounds.visibleH
} else {
    // Fully on-canvas — anchor at top-left
    anchorEffX = baseEffX; anchorOffsetX = 0
    anchorEffY = baseEffY; anchorOffsetY = 0
}
```

**When to use:** Any `.path` panel where the shape is not a rectangle. A fixed corner is more predictable than any computed center for irregular geometry.

### `computeVisibleSourceBounds` as Static Method

Make `computeVisibleSourceBounds` a `static func` on `CropManager`. It computes the visible source region given a destination rect and scaled source dimensions. Being static enables reuse from `PanelCropEditor` (overlay drag initialization), `CropManager` (pan and pinch), and tests — eliminating duplicated math.
