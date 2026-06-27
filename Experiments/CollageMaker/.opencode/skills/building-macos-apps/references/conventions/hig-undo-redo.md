# HIG: Undo and Redo

## UndoManager Integration

```swift
@MainActor @Observable final class CollageViewModel {
    private let undoManager = UndoManager()

    func removeImage(at index: Int) {
        let removed = images[index]
        undoManager.registerUndo(withTarget: self) { target in
            target.images.insert(removed, at: index)
        }
        undoManager.setActionName("Remove Image")
        images.remove(at: index)
    }

    func changeLayout(to newLayout: LayoutStyle) {
        let oldLayout = layout
        undoManager.registerUndo(withTarget: self) { target in
            target.layout = oldLayout
        }
        undoManager.setActionName("Change Layout")
        layout = newLayout
    }
}
```

## Descriptive Action Names

Use specific action names in the Edit menu, not generic "Undo":

```swift
// Produces "Undo Remove Image" in Edit menu
undoManager.setActionName("Remove Image")

// Produces "Undo Change Layout"
undoManager.setActionName("Change Layout")

// Produces "Undo Reorder Images"
undoManager.setActionName("Reorder Images")
```

## Batching Related Actions

For continuous adjustments (crop pan/zoom), batch into a single undo unit:

```swift
func beginCropAdjustment() {
    undoManager.beginUndoGrouping()
}

func endCropAdjustment() {
    undoManager.setActionName("Adjust Crop")
    undoManager.endUndoGrouping()
}

// Call begin on gesture start, end on gesture end
// All crop position changes between begin/end are one undo
```

**Immediate registration, deferred finalization:** The undo action must be registered synchronously (before `endUndoGrouping()` closes the group). The group is just a container — `registerUndo` happens per-event; only the grouping closure (`begin`/`end`) is deferred. Deferring registration until after an inactivity window makes Cmd+Z unresponsive during that window. See [Property-Level Undo Grouping](#property-level-undo-grouping-inactivity-based-detection) for the full pattern with code.

## View-layer Gesture Batching

When gesture lifecycle lives in the View, the View owns the undo grouping lifecycle. This requires `undoManager` to be `internal` (not `private`) on the ViewModel.

### Scroll pan — direct callback wrapping

```swift
ScrollPanView(
    onPanBegan: { id in
        viewModel.undoManager.beginUndoGrouping()
        viewModel.beginScrollPan(panelId: id)
    },
    onPanEnded: {
        viewModel.undoManager.setActionName("Adjust Crop")
        viewModel.undoManager.endUndoGrouping()
        viewModel.endScrollPan()
    }
)
```

### Pinch — stateful lock on first onChanged

```swift
@State private var pinchPanelId: UUID?

.magnificationGesture()
    .onChanged { value in
        if pinchPanelId == nil, let id = viewModel.selectedPanelId {
            pinchPanelId = id
            viewModel.beginPinch(panelId: id)
            viewModel.undoManager.beginUndoGrouping()
        }
        // ... incremental updates ...
    }
    .onEnded { _ in
        if let id = pinchPanelId {
            viewModel.applyPinch(panelId: id)
            viewModel.undoManager.setActionName("Adjust Crop")
            viewModel.undoManager.endUndoGrouping()
        }
        pinchPanelId = nil
    }
```

### End-of-gesture undo registration

When old state can only be captured mid-gesture (e.g., drag locks onto a region after hit-testing), register undo at gesture end instead of before each mutation:

```swift
@State private var oldTitleStyle: TitleStyle?

// In onChanged, when drag first locks:
oldTitleStyle = viewModel.titleStyle

// In onEnded:
if let oldStyle = oldTitleStyle {
    viewModel.undoManager.registerUndo(withTarget: viewModel) { target in
        target.titleStyle = oldStyle
    }
    viewModel.undoManager.setActionName("Move Title")
}
oldTitleStyle = nil
```

This produces one undo entry for the entire gesture, rather than one per intermediate change.

## Suppressing `didSet` Undo During Gestures

When a property with `didSet` undo registration is modified many times during a gesture, each modification registers its own undo entry. Guard against this with a flag:

```swift
private var isDraggingTitle = false

var titleStyle: TitleStyle = .default {
    didSet {
        if !isDraggingTitle {
            undoManager.registerUndo(withTarget: self) { target in
                target.titleStyle = oldValue
            }
            undoManager.setActionName("Change Title Style")
        }
        // ... persist, side effects ...
    }
}
```

Set the flag at gesture start, clear at gesture end. The gesture's own end-of-gesture undo registration handles the single before→after entry. Without the guard, intermediate `didSet` entries accumulate in the undo stack as harmless but wasteful dead weight.

## Property-Level Undo Grouping (Inactivity-Based Detection)

For continuous controls like sliders and color pickers that **lack explicit gesture lifecycle callbacks**, use an inactivity timer to infer end-of-interaction. The control fires property setters at high frequency (~60fps), so grouping must be deferred while undo registration is immediate.

### Pattern: Immediate Registration + Deferred Grouping Finalization

Register the undo action synchronously on every setter call (Cmd+Z works instantly). Wrap in `beginUndoGrouping()`/`endUndoGrouping()`. Close the group after an inactivity window expires (~150ms).

```swift
var gradientAngle: Double {
    get { backgroundManager.gradientAngle }
    set {
        guard !isInitializing else { return }

        let startedGroup = backgroundManager.beginInteraction()
        if startedGroup {
            undoManager.beginUndoGrouping()  // Group all property changes in this interaction
        }

        backgroundManager.gradientAngle = newValue

        // Undo registered IMMEDIATELY — Cmd+Z works right away
        let preValue = backgroundManager.preInteractionGradientAngle
        self.undoManager.registerUndo(withTarget: self) { $0.backgroundManager.gradientAngle = preValue }

        // Group finalization deferred until inactivity window expires
        backgroundManager.registerDeferredUndo(actionName: "Change Gradient Angle") { [weak self] in
            guard let self else { return }
            self.undoManager.setActionName("Change Gradient Angle")
            self.undoManager.endUndoGrouping()  // Finalize as single undo step
        }
        updateBackground()
    }
}
```

### Interaction State Machine

A manager owns the interaction state and returns `Bool` from `beginInteraction()` to signal "should I open an undo group?":

```swift
func beginInteraction() -> Bool {
    if interacting { return false }  // Already in progress — skip
    interacting = true
    preInteractionGradientAngle = gradientAngle  // Capture BEFORE assignment
    return true  // Caller should call undoManager.beginUndoGrouping()
}

func endInteraction() {
    interacting = false
}
```

**Separation of concerns:** The manager owns interaction state (`interacting`, `preInteraction*` values, timer lifecycle). The ViewModel owns UndoManager coordination. The manager returns `Bool` without directly accessing the UndoManager — keeps it testable in isolation.

### Critical: Guaranteed Reset on Every Termination Path

Boolean "in progress" flags must reset on **every** code path that terminates the interaction (timer expiry, cancellation, external interrupt). Missing a reset path is a critical bug — after first slider drag, `interacting` stays `true` forever and all subsequent drags use stale pre-interaction values.

```swift
func registerDeferredUndo(actionName: String, finalize: @escaping () -> Void) {
    deferredUndoTask?.cancel()
    deferredUndoTask = Task { [weak self] in
        guard let self else { return }
        try? await Task.sleep(for: FrameTempo.backgroundUndoDebounce)  // ~150ms
        guard !Task.isCancelled else { return }
        finalize()
        self.endInteraction()  // Reset on timer expiry
        self.deferredUndoTask = nil
    }
}

func cancelDeferredUndo() {
    deferredUndoTask?.cancel()
    deferredUndoTask = nil
    if interacting { endInteraction() }  // Reset on cancellation too
}
```

**Consider RAII-style wrappers** to make reset automatic. A struct with `deinit` that calls `endInteraction()` eliminates entire classes of missed-reset bugs.

### Open Group Cleanup on External Interrupts

If an external action (e.g., `clearAll()`) occurs while a property interaction is in progress, close the open undo group so the external action doesn't get lumped into it:

```swift
func clearAll() {
    if backgroundManager.interacting {
        undoManager.endUndoGrouping()  // Close orphaned group
        backgroundManager.cancelDeferredUndo()
    }
    // ... rest of clearAll
}
```

### When to Use Inactivity Detection vs. Explicit Gesture Lifecycle

| Control type | Has explicit start/end? | Detection method |
|---|---|---|
| Scroll pan, pinch, title drag | Yes (gesture callbacks) | `beginUndoGrouping()`/`endUndoGrouping()` tied to `onChanged`/`onEnded` |
| Slider drag, color picker drag | No (property setter fires per-tick) | Inactivity timer (~150ms) + interaction state machine |
| Typing in text field | No (each keystroke is discrete) | Immediate undo registration, no grouping needed |

**Rule of thumb:** If the control produces more than ~10 events/sec during normal interaction AND lacks explicit start/end callbacks, use inactivity-based detection with immediate undo registration + deferred grouping finalization.

### Pre-Interaction Capture Order Matters

Call `beginInteraction()` **before** assigning the new value so the manager captures the OLD value:

```swift
let startedGroup = backgroundManager.beginInteraction()  // Captures OLD values first
if startedGroup { undoManager.beginUndoGrouping() }
backgroundManager.gradientAngle = newValue  // Now safe to assign new value
```

Assigning before `beginInteraction()` causes it to read the NEW value instead of the old — Cmd+Z becomes a no-op.

## macOS-Specific

- **Place undo/redo in Edit menu at top** — system handles this automatically with UndoManager
- **Command-Z** (undo) and **Shift-Command-Z** (redo) work automatically
- **Don't add undo buttons to the UI** — rely on Edit menu and keyboard shortcuts

## Actions to Make Undoable

| Action | Action Name |
|---|---|
| Image reordering | "Reorder Images" |
| Crop adjustments | "Adjust Crop" (batched) |
| Image removal | "Remove Image" |
| Layout changes | "Change Layout" |
| Title text edits | "Edit Title" |
| Title drag/move | "Move Title" (end-of-gesture) |
| Background changes | "Change Background" |
| Drag-and-drop operations | "Move Image" / "Drop Image" |

## @Observable with UndoManager

```swift
@MainActor @Observable final class ViewModel {
    private let undoManager = UndoManager()

    var titleStyle: TitleStyle = .default {
        didSet {
            // Register undo for title changes
            undoManager.registerUndo(withTarget: self) { target in
                target.titleStyle = oldValue
            }
            undoManager.setActionName("Change Title Style")
        }
    }
}
```

Register undo **before** making the change, capturing the old value for restoration.

## `didSet` Ordering with UndoManager

When a `didSet` observer contains undo registration, persistence, and side effects, the order matters:

```swift
var gutter: CGFloat = 0 {
    didSet {
        // 1. Register undo first (captures oldValue)
        undoManager.registerUndo(withTarget: self) { target in
            target.gutter = oldValue
        }
        undoManager.setActionName("Change Gutter")
        // 2. Persist second
        UserDefaults.standard.set(Double(gutter), forKey: "gutter")
        // 3. Side effects last
        regenerateLayout()
    }
}
```

**Order:** undo registration → persist → side effects. This ensures undo restores the old value, which triggers `didSet` again — re-persisting the old value and re-running side effects. Undo should fully reverse the action, including persistence.

## Protocol Target Workaround

`UndoManager.registerUndo(withTarget:handler:)` requires `TargetType: AnyObject`. A protocol-typed variable (`any ProtocolName`) fails even when the protocol inherits `AnyObject`, because the existential is not a concrete class type.

**Two-part fix:**

```swift
// 1. Protocol must be a class protocol
protocol ImageCoordinationTarget: AnyObject {
    func regenerateLayout()
}

// 2. Use the coordinator (self) as the target, not the protocol existential
final class ImageCoordinator {
    private let target: ImageCoordinationTarget
    private let undoManager: UndoManager

    func removeImage(at index: Int) {
        let removed = imageLibrary.images[index]
        // WRONG: registerUndo(withTarget: target) — compile error
        undoManager.registerUndo(withTarget: self) { _ in
            self.imageLibrary.images.insert(removed, at: index)
            self.target.regenerateLayout()
        }
        undoManager.setActionName("Remove Image")
        imageLibrary.images.remove(at: index)
    }
}
```

**Why it works:** `self` is the concrete coordinator class (satisfies `AnyObject`). The closure captures `self`, which owns the `target` reference and routes mutations through it. The coordinator stays alive (owned by the ViewModel) when undo fires.

**When this applies:** Any time you break a circular dependency with a protocol (DIP) and need undo actions that mutate state on the protocol target.

**Alternative (not recommended):** Passing the concrete ViewModel as a second `undoTarget` parameter defeats the protocol abstraction — the coordinator would still import the concrete type.

## Collection Mutation Undo Patterns

Three distinct patterns for undoing array mutations:

### Remove → Insert

```swift
func removeImage(at index: Int) {
    let removed = images[index]
    undoManager.registerUndo(withTarget: self) { target in
        target.images.insert(removed, at: index)
        target.regenerateLayout()
    }
    undoManager.setActionName("Remove Image")
    images.remove(at: index)
}
```

### Move → Restore Permutation

For complex reordering (move, swap), capture the pre-mutation permutation array rather than reversing individual operations:

```swift
func moveImages(from: IndexSet, to: Int) {
    let oldCustomOrder = customImageOrder
    // ... perform move ...
    undoManager.registerUndo(withTarget: self) { target in
        target.customImageOrder = oldCustomOrder
        target.regenerateLayout()
    }
    undoManager.setActionName("Reorder Images")
}
```

### Clear All → Full State Restore

```swift
func clearAll() {
    guard !images.isEmpty else { return }
    let oldImages = images, oldPanels = panels, oldCropMap = cropMap, oldCustomOrder = customImageOrder
    undoManager.registerUndo(withTarget: self) { target in
        target.images = oldImages
        target.panels = oldPanels
        target.cropMap = oldCropMap
        target.customImageOrder = oldCustomOrder
        target.regenerateLayout()
    }
    undoManager.setActionName("Clear All")
    images.removeAll()
    panels.removeAll()
    cropMap.removeAll()
    customImageOrder = nil
}
```

**Key insight:** For complex mutations, capturing the pre-mutation state is simpler and more reliable than reversing individual operations.

### Guarding Non-Undoable State

When an operation has no prior state to restore, return early without registering undo:

```swift
func resetCrop(panelId: UUID) {
    guard let oldCrop = cropMap[panelId] else { return }
    undoManager.registerUndo(withTarget: self) { target in
        target.cropMap[panelId] = oldCrop
        target.regenerateLayout()
    }
    undoManager.setActionName("Reset Crop")
    cropMap[panelId] = nil
}
```

This prevents registering a no-op undo action when there's nothing to undo.

### Deliberate Exclusions

Adding images (`addImages(from:)`) is typically NOT made undoable — it's a high-frequency, low-cost operation during setup, and undoing additions would require tracking full image data in the undo stack. If needed, a "Remove All Added" batch action is more practical than per-image undo.
