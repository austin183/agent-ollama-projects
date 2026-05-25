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
