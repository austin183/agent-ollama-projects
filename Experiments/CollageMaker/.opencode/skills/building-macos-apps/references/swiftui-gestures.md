# SwiftUI Gestures — Targeting, Coordinate Spaces, and Composition

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

## Per-Panel Gesture Targeting

### Approach 1: Parent Gesture with Hit Testing (Recommended)

Place a single gesture at the parent level and hit-test `startLocation` on first `onChanged` to lock onto the target panel:

```swift
struct EditorView: View {
    @State private var dragPanelId: UUID?
    @State private var pinchPanelId: UUID?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image(nsImage: previewImage!)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geometry.size.width, height: geometry.size.height)

                // Lightweight hit areas (no gestures attached)
                ForEach(panels) { panel in
                    let scaledFrame = canvasToPreviewFrame(panel.frame, in: geometry.size)
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: scaledFrame.width, height: scaledFrame.height)
                        .position(x: scaledFrame.midX, y: scaledFrame.midY)
                }

                // Selection indicator
                if let selectedId = selectedPanelId,
                   let panel = panels.first(where: { $0.id == selectedId }) {
                    let scaledFrame = canvasToPreviewFrame(panel.frame, in: geometry.size)
                    Rectangle()
                        .fill(Color.clear)
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: scaledFrame.width, height: scaledFrame.height)
                        .position(x: scaledFrame.midX, y: scaledFrame.midY)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        if dragPanelId == nil,
                           let id = panelAt(location: value.startLocation, in: geometry.size) {
                            dragPanelId = id
                            viewModel.beginPan(panelId: id)
                        }
                        if dragPanelId != nil {
                            viewModel.pan(by: value.translation)
                        }
                    }
                    .onEnded { _ in
                        if let id = dragPanelId {
                            viewModel.applyPan(panelId: id)
                        }
                        dragPanelId = nil
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        if pinchPanelId == nil, let id = selectedPanelId {
                            pinchPanelId = id
                            viewModel.beginPinch(panelId: id)
                        }
                        if pinchPanelId != nil {
                            viewModel.pinch(magnification: value)
                        }
                    }
                    .onEnded { _ in
                        if let id = pinchPanelId {
                            viewModel.applyPinch(panelId: id)
                        }
                        pinchPanelId = nil
                    }
            )
            .onTapGesture { location in
                if let id = panelAt(location: location, in: geometry.size) {
                    selectedPanelId = id
                } else {
                    selectedPanelId = nil
                }
            }
        }
    }

    private func panelAt(location: CGPoint, in previewSize: CGSize) -> UUID? {
        for panel in panels {
            let scaledFrame = canvasToPreviewFrame(panel.frame, in: previewSize)
            if scaledFrame.contains(location) {
                return panel.id
            }
        }
        return nil
    }
}
```

**Key points:**
- **`DragGesture.startLocation`** locks the target panel on first `onChanged` — the `@State` flag prevents re-locking mid-drag
- **`MagnificationGesture` has no location** — `MagnificationGesture.Value` is a `CGFloat` only, with no `location` or `startLocation`. Target the selected panel instead
- **`@State` flag pattern** — `dragPanelId`/`pinchPanelId` track which panel owns the gesture. Reset in `onEnded`
- **No `.onStarted`** — `DragGesture` and `MagnificationGesture` have no `.onStarted` modifier. Use a `@State` flag in the first `onChanged` for gesture initialization

### Approach 2: ZStack with Overlay Rectangles (KNOWN ISSUE)

**WARNING:** This approach does NOT work reliably with `.simultaneousGesture`. When multiple clear `Rectangle` overlays each attach `.simultaneousGesture(drag)`, all gestures fire simultaneously and the last overlay wins. The `simultaneousGesture` modifier is designed to let gestures compete with other gestures, not to isolate per-region targeting.

Using `.gesture()` instead of `.simultaneousGesture()` may work for simple cases but has its own issues with gesture priority and tap detection. **Prefer Approach 1.**

### Approach 3: NSViewRepresentable

See `references/nsviarepresentable.md` for `NSPanGestureRecognizer` + `NSMagnifyingGestureRecognizer` with native hit testing.

### Approach 4: Canvas (NOT Recommended)

**Apple docs explicitly state:** "A canvas doesn't offer interactivity or accessibility for individual elements." Do not use Canvas for per-panel gestures.

## Multiple Coexisting DragGestures

When a canvas needs multiple independent drag actions (e.g., dragging a title overlay, reordering panels, and panning the viewport), you can layer multiple `DragGesture` instances as `.simultaneousGesture` on the same parent ZStack. Each gesture must have its own hit-test region and locking flag.

```swift
struct EditorView: View {
    @State private var dragTitleLocked = false
    @State private var dragSourcePanelId: UUID?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // ... canvas content ...

                // Title hit area
                if let titleFrame = titleFrame {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: titleFrame.width, height: titleFrame.height)
                        .position(x: titleFrame.midX, y: titleFrame.midY)
                }

                // Panel hit areas
                ForEach(panels) { panel in
                    let scaledFrame = canvasToPreviewFrame(panel.frame, in: geometry.size)
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: scaledFrame.width, height: scaledFrame.height)
                        .position(x: scaledFrame.midX, y: scaledFrame.midY)
                }
            }
            // Gesture 1: Title drag
            .simultaneousGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        if !dragTitleLocked {
                            let scaledTitle = canvasToPreviewFrame(titleFrame!, in: geometry.size)
                            guard scaledTitle.contains(value.startLocation) else { return }
                            dragTitleLocked = true
                            viewModel.beginTitleDrag()
                        }
                        if dragTitleLocked {
                            viewModel.dragTitle(by: value.translation)
                        }
                    }
                    .onEnded { _ in
                        if dragTitleLocked {
                            viewModel.endTitleDrag()
                        }
                        dragTitleLocked = false
                    }
            )
            // Gesture 2: Panel reorder drag
            .simultaneousGesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        guard !viewModel.isDraggingTitle else { return }
                        if dragSourcePanelId == nil,
                           let id = panelAt(location: value.startLocation, in: geometry.size) {
                            dragSourcePanelId = id
                            viewModel.beginPanelReorder(panelId: id)
                        }
                        if dragSourcePanelId != nil {
                            viewModel.updateReorderCursor(location: value.location)
                        }
                    }
                    .onEnded { value in
                        if let sourceId = dragSourcePanelId {
                            let targetId = panelAt(location: value.location, in: geometry.size)
                            viewModel.endPanelReorder(sourceId: sourceId, targetId: targetId)
                        }
                        dragSourcePanelId = nil
                    }
            )
        }
    }
}
```

**Key rules:**
- **Each gesture uses `startLocation` on first `onChanged`** to determine its hit-test target
- **A `@State` flag per gesture** (`dragTitleLocked`, `dragSourcePanelId`) prevents re-locking mid-gesture
- **Cross-gesture guards** prevent conflict — the panel reorder gesture checks `guard !viewModel.isDraggingTitle else { return }` so the title gesture wins when both could fire
- **`minimumDistance: 5`** on all drag gestures prevents tap-to-select conflict
- **Scroll pan via `NSViewRepresentable`** is a different input modality (`scrollWheel(with:)`) and doesn't conflict with SwiftUI DragGestures

## Overlapping Hit Regions

When multiple `simultaneousGesture` handlers on the same view have overlapping hit regions (e.g., a title overlay sitting visually on top of panel hit areas), you must use **preemptive region exclusion** in the lower-priority gesture.

### Why ZStack Visual Order Doesn't Help

The title overlay rectangle appears visually above the panel hit areas in the ZStack, but SwiftUI's `simultaneousGesture` attaches to the ZStack as a whole, not to individual children. ZStack visual stacking order has no effect on which gesture fires. Both gestures receive the same `startLocation` regardless of which visual element is "on top."

### Why `isDragging` Flags Don't Work

An existing `guard !viewModel.isDraggingTitle else { return }` in the panel drag handler only prevents panel drag *after* the title drag has locked. But both `simultaneousGesture` DragGestures fire their `onChanged` in the same pass. The title drag sets `isDraggingTitle = true` in its `onChanged`, but the panel drag's `onChanged` also runs simultaneously with `isDraggingTitle` still `false`. The `@Observable` property update doesn't propagate until the next render cycle, so the guard doesn't help within the same gesture event.

### Preemptive Exclusion Pattern

```swift
// Lower-priority gesture checks higher-priority region first
.simultaneousGesture(
    DragGesture(minimumDistance: 5)
        .onChanged { value in
            // Preemptive exclusion: bail if drag started on higher-priority region
            if let highPriorityFrame = highPriorityRegion,
               highPriorityFrame.contains(value.startLocation) {
                return
            }
            // Normal hit-test for this gesture's region
            if let id = hitTest(value.startLocation) {
                // ... lock and handle
            }
        }
)
```

**Why this works:** The check runs in the same closure before any state mutation. The higher-priority gesture's own handler still runs independently and locks normally. No timing issues, no render-cycle dependencies.

### Tap Gesture Priority

The same preemptive exclusion pattern applies to `.onTapGesture`:

```swift
.onTapGesture { location in
    // Preemptive exclusion
    if let highPriorityFrame = highPriorityRegion,
       highPriorityFrame.contains(location) {
        return
    }
    // Normal tap handling
    if let id = hitTest(location) {
        select(id)
    }
}
```

### Alternatives Considered but Rejected

- **`.highPriorityGesture` instead of `.simultaneousGesture`** — would prevent both from firing, but we need them to coexist for non-overlapping regions (title drag on title, panel drag on panel)
- **Separate ZStack layers with `.allowsHitTesting(false)`** — would break the shared coordinate space and overlay rendering
- **Combining into a single DragGesture with if/else branching** — works but loses the clean separation of concerns between gesture handlers

## Ghost Cursor Overlay Pattern

During a drag-to-reorder gesture, show a semi-transparent thumbnail of the dragged content following the cursor for visual feedback:

```swift
@State private var dragCursorLocation: CGPoint?
@State private var dragSourceImageIndex: Int?

// In DragGesture onChanged:
dragCursorLocation = value.location

// In the ZStack overlay:
if let location = dragCursorLocation,
   let imgIdx = dragSourceImageIndex,
   let thumbnail = images[imgIdx].thumbnail {
    Image(nsImage: thumbnail)
        .resizable()
        .frame(width: 64, height: 64)
        .opacity(0.7)
        .position(location)
        .allowsHitTesting(false)
}
```

**Visual feedback strokes** — Highlight source and target panels during drag:
- Source panel: cyan stroke (`Color.cyan`, `lineWidth: 2.5`)
- Target panel: green stroke (`Color.green`, `lineWidth: 2.5`)
- Both use `.stroke(Color, lineWidth: 2.5)` on clear rectangles positioned at the panel's scaled frame

**Key points:**
- Use pre-generated thumbnail (e.g., 64x64), NOT the full-resolution image
- `.allowsHitTesting(false)` prevents the ghost cursor from intercepting hit tests for target panel detection
- Reset both `dragCursorLocation` and `dragSourceImageIndex` to `nil` in `onEnded`

## Edge-Based Resize Handle Pattern

When an overlay element needs both drag-to-move and drag-to-resize, distinguish the two by checking whether `startLocation` falls within a threshold of the element's edge on first `onChanged`:

```swift
let handleThreshold = resizeHandleWidth + 2  // visual handle + comfortable grab area

if tf.minX - handleThreshold <= startLocation.x,
   startLocation.x <= tf.minX + handleThreshold,
   tf.minY <= startLocation.y, startLocation.y <= tf.maxY {
    // Left edge resize
} else if tf.maxX - handleThreshold <= startLocation.x,
          startLocation.x <= tf.maxX + handleThreshold,
          tf.minY <= startLocation.y, startLocation.y <= tf.maxY {
    // Right edge resize
} else if tf.contains(startLocation) {
    // Drag to move
}
```

**Key points:**
- The threshold extends beyond the visual handle width (`+ 2`) for a comfortable grab area
- Y bounds check (`tf.minY ... tf.maxY`) ensures the drag started vertically within the box, not just horizontally near the edge
- A single `@State` enum (e.g., `TitleResizeEdge`) tracks which mode is active, avoiding multiple boolean flags
- All three modes share the same `DragGesture` — no additional gesture modifiers needed

### Right vs Left Edge Resize Semantics

- **Right edge resize** anchors the left edge of the box — width grows/shrinks rightward, position stays fixed
- **Left edge resize** adjusts `positionX` by half the width delta — the box appears to grow/shrink from the center, which matches user expectation for symmetric resizing

```swift
if titleResizeEdge == .right {
    let newWidth = max(minX, canvasX - tf.minX)
    style.width = newWidth
} else {
    let newWidth = max(minX, tf.maxX - canvasX)
    let dx = (tf.width - newWidth) / 2
    style.width = newWidth
    style.positionX = style.positionX + dx / canvasSize.width
}
```

### Minimum Width from Natural Text Bounds

To prevent a text box from shrinking below its content, compute the unbounded natural width:

```swift
let naturalBounds = attributedString.boundingRect(
    with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
    options: [.usesLineFragmentOrigin, .usesFontLeading]
)
let minWidth = naturalBounds.width
```

**Swift type ambiguity:** `.greatestFiniteMagnitude` is ambiguous without explicit type — both `Float` and `Double` have the property. Must use `CGFloat.greatestFiniteMagnitude`.

### ZStack Overlay Frame Sizing

A `Rectangle()` in a ZStack overlay with `.frame(width: 8)` stretches vertically to fill the full ZStack height. To vertically bound the rectangle, specify both dimensions: `.frame(width: 8, height: boxHeight)`. Without explicit height, the overlay fills available vertical space rather than matching the target element.

## Key Findings

1. **`DragGesture.location` available in `onChanged`** — use for hit testing during drag
2. **`DragGesture.startLocation` for panel locking** — hit-test on first `onChanged` to determine target, use `@State` flag to prevent re-locking
3. **`SimultaneousGesture` combines drag + pinch** — or use `.simultaneousGesture()` modifier
4. **`simultaneousGesture` on ZStack overlays causes last-one-wins** — all overlay gestures fire simultaneously. Do NOT use per-panel `.simultaneousGesture` overlays. Use parent-level gesture with hit-testing instead.
5. **`MagnificationGesture` has no location** — `Value` is `CGFloat` only. Cannot hit-test panel under pinch. Target the selected panel.
6. **No `.onStarted` on `DragGesture`/`MagnificationGesture`** — Use `@State` flag in first `onChanged` for gesture initialization
7. **Canvas is NOT suitable** — no per-element interactivity
8. **NSViewRepresentable is viable** — more complex but native AppKit gesture handling
9. **Coordinate conversion is critical** — `previewToCanvas()` must account for aspect-ratio fit scaling
10. **Inverse conversion for drag positioning** — When converting `DragGesture.Value.location` back to canvas coordinates, you must reverse the canvas-to-preview transformation: subtract centering offset, scale by canvas/fitted ratio, flip Y from top-left to bottom-left, then optionally convert back to normalized top-left for storage. See the "Preview-to-Canvas Inverse Conversion" section in the main skill.
11. **@Observable property assignment naturally debounces live preview** — Setting `viewModel.property = value` during `onChanged` fires `didSet`, which typically calls `updatePreview()`. If `updatePreview()` uses `Task.detached` with stale task cancellation (`previewTask?.cancel()`), live drag updates are naturally debounced without additional throttling.
12. **Multiple `simultaneousGesture` DragGestures on same parent** — Valid when each gesture has distinct hit-test regions, locking flags, and cross-gesture guards. Do NOT confuse with per-overlay `.simultaneousGesture` (finding #4), which fires all overlay gestures simultaneously.
13. **Edge resize with single DragGesture** — Distinguish drag-to-move vs drag-to-resize by checking `startLocation` proximity to element edges on first `onChanged`. Use a single `@State` enum to track mode. Right edge anchors left position; left edge adjusts position by half the width delta for symmetric resize.
14. **ZStack overlay rectangles need explicit height** — `.frame(width: 8)` on a `Rectangle()` in a ZStack overlay stretches vertically to fill the full ZStack height. Must specify both dimensions: `.frame(width: 8, height: boxHeight)`.
15. **`CGFloat.greatestFiniteMagnitude` requires explicit type** — `.greatestFiniteMagnitude` alone is ambiguous between `Float` and `Double`. Always prefix with `CGFloat.`

## Pitfalls

- **`.simultaneousGesture` on ZStack overlays causes last-one-wins** — All overlay gestures fire simultaneously. Use parent-level gesture with `startLocation` hit-testing instead
- **`MagnificationGesture` has no location** — `Value` is `CGFloat` only. Cannot hit-test panel under pinch. Target the selected panel.
- **No `.onStarted` on `DragGesture`/`MagnificationGesture`** — Use `@State` flag in first `onChanged` for gesture initialization
- **`MagnificationGesture` cumulative values invert zoom direction** — `value.magnification` is cumulative from gesture start (>1 = spread fingers = zoom in). For source-rect zoom, use `baseZoom / magnification` (division), NOT `baseZoom * magnification` (multiplication). Multiplying makes the source rect larger, which zooms out.
- **Zoom percentage display is counterintuitive** — `sourceW / destW * 100` decreases as you zoom in. Use `destW / sourceW * 100` for the expected behavior: higher percentage = more zoomed in.
- **`onEnded`-only updates are jarring** — Users expect live preview during drag/pinch. Use `finish: Bool` parameter on gesture methods: `finish: false` in `onChanged` for live updates, `finish: true` in `onEnded` to commit.
- **`NSEvent.Phase` differs from iOS** — `.failed` is iOS-only. macOS phases: `.began`, `.changed`, `.ended`, `.cancelled`, `.mayBegin`.
- **`NSView.isOpaque` is get-only on macOS** — Cannot be set directly. It's computed from `wantsLayer` + `layer?.isOpaque`. An `NSView` overlay is transparent by default when no drawing is performed.
- **`isDragging` flag doesn't prevent simultaneous gesture conflict** — When two `simultaneousGesture` DragGestures fire on the same view, setting `isDraggingTitle = true` in one handler doesn't propagate to the other handler's `onChanged` until the next render cycle. Both handlers run in the same pass with stale state. Use preemptive region exclusion (`contains(startLocation)` check) in the lower-priority gesture instead.
- **ZStack overlay rectangle stretches vertically** — A `Rectangle()` in a ZStack overlay with `.frame(width: 8)` stretches vertically to fill the full ZStack height. Must specify both dimensions: `.frame(width: 8, height: boxHeight)`.
- **`CGFloat.greatestFiniteMagnitude` requires explicit type** — `.greatestFiniteMagnitude` alone is ambiguous between `Float` and `Double`. Always use `CGFloat.greatestFiniteMagnitude`.
- **Cumulative translation compounds with live binding state** — `DragGesture.Value.translation` is cumulative from drag start. If the target state is read from a `@Bindable` property inside `onChanged`, the binding returns the already-updated state each tick, causing compounding. Capture the base state at drag start in a `@State` variable. Never re-read the live binding for the base during the gesture.
- **Pan manager subtraction inverts direct drag** — A pan method that computes `baseOrigin - panDelta` implements indirect scroll semantics. Direct drag requires negated translation or bypassing the pan pipeline entirely.
16. **Inverse coordinate transform with letterboxing** — When a gesture modifies a rect in container coordinates from a `.aspectRatio(.fit)` image, converting back to source requires subtracting the letterboxing offset before scaling: `sourceX = (containerX - offsetX) / fittedW * imageW`. Using `containerX * scaleX` double-applies the offset, causing the visual element to jump away from the cursor. See `references/coordinate-systems.md` "Inverse Transform Pitfall".
