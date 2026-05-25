# Gesture Targeting — Per-Panel Hit Testing, Overlapping Regions, and Coexisting Gestures

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

See `../appkit/nsviarepresentable.md` for `NSPanGestureRecognizer` + `NSMagnifyingGestureRecognizer` with native hit testing.

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

## Key Findings

1. **`DragGesture.startLocation` for panel locking** — hit-test on first `onChanged` to determine target, use `@State` flag to prevent re-locking
2. **`simultaneousGesture` on ZStack overlays causes last-one-wins** — all overlay gestures fire simultaneously. Do NOT use per-panel `.simultaneousGesture` overlays. Use parent-level gesture with hit-testing instead.
3. **Canvas is NOT suitable** — no per-element interactivity
4. **NSViewRepresentable is viable** — more complex but native AppKit gesture handling
5. **Multiple `simultaneousGesture` DragGestures on same parent** — Valid when each gesture has distinct hit-test regions, locking flags, and cross-gesture guards. Do NOT confuse with per-overlay `.simultaneousGesture` (finding #2), which fires all overlay gestures simultaneously.
6. **@Observable property assignment naturally debounces live preview** — Setting `viewModel.property = value` during `onChanged` fires `didSet`, which typically calls `updatePreview()`. If `updatePreview()` uses `Task.detached` with stale task cancellation (`previewTask?.cancel()`), live drag updates are naturally debounced without additional throttling.

## Pitfalls

- **`.simultaneousGesture` on ZStack overlays causes last-one-wins** — All overlay gestures fire simultaneously. Use parent-level gesture with `startLocation` hit-testing instead
- **`isDragging` flag doesn't prevent simultaneous gesture conflict** — When two `simultaneousGesture` DragGestures fire on the same view, setting `isDraggingTitle = true` in one handler doesn't propagate to the other handler's `onChanged` until the next render cycle. Both handlers run in the same pass with stale state. Use preemptive region exclusion (`contains(startLocation)` check) in the lower-priority gesture instead.
- **ZStack overlay rectangle stretches vertically** — A `Rectangle()` in a ZStack overlay with `.frame(width: 8)` stretches vertically to fill the full ZStack height. Must specify both dimensions: `.frame(width: 8, height: boxHeight)`.
