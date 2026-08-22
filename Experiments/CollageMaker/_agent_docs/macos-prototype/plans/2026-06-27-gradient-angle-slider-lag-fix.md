# Gradient Angle Slider Lag — Background-Only Render + Deferred Undo

**Date**: 2026-06-27
**Change Request**: `_agent_docs/change-requests/round-107.3.md`
**Status**: Planned

## Problem

Dragging the gradient angle slider (and other background-only properties) triggers a full composite render — background + all N panels + title — even though only the background changed. Additionally, undo registration fires on every slider tick (~30-60/sec), creating hundreds of undo entries for a single drag gesture.

## Root Cause

1. Background property setters (`gradientAngle`, `gradientStartColor`, `gradientEndColor`, `backgroundColor`, `backgroundOpacity`) all call `updatePreviewDebounced()` → full composite render
2. `PreviewManager.updateBackground()` already exists as a fast background-only path but is never called from these setters
3. Undo registration happens in the setter immediately, before the debounced render fires
4. The editor transiently enters non-layered mode (`isLayeredMode = false`) after `regenerateLayout()`, rendering a full composite that is immediately superseded by `updateAllPanelPreviews()`

## Design

### Part A: Background-Only Render Path

Route background-only property changes through the dedicated `updateBackground()` method instead of the full composite render. The editor always uses layered mode for display; the full composite is only needed for export (which builds it fresh).

### Part B: Deferred Undo

Defer undo registration until 150ms after the last property change. Capture the pre-interaction value so Cmd+Z reverts to the value before the drag started, producing a single undo entry per gesture.

### Part C: Always Layered Mode

Remove the transient non-layered mode in `regenerateLayout()`. The editor view is always in layered mode; the non-layered path renders a full composite that is immediately superseded by `updateAllPanelPreviews()`.

## Implementation

### 1. `FrameTempo.swift` — Add constant

Add a named constant for the background undo debounce delay:

```swift
// Add to existing enum
static let backgroundUndoDebounce: Duration = .milliseconds(150)
```

### 2. `BackgroundManager.swift` — Interaction tracking + deferred undo

Add interaction tracking state and deferred undo methods. The manager tracks whether a continuous interaction (slider drag, color picker drag) is in progress, and captures pre-interaction values so undo reverts to the value before the interaction started.

```swift
// MARK: - Deferred Undo State

private var interacting: Bool = false
private var preInteractionGradientAngle: Double = 0
private var preInteractionGradientStartColor: NSColor = .black
private var preInteractionGradientEndColor: NSColor = .darkGray
private var preInteractionBackgroundColor: NSColor = .black
private var preInteractionBackgroundOpacity: Double = 1.0

var deferredUndoTask: Task<Void, Never>?

func beginInteraction() {
    interacting = true
    preInteractionGradientAngle = gradientAngle
    preInteractionGradientStartColor = gradientStartColor
    preInteractionGradientEndColor = gradientEndColor
    preInteractionBackgroundColor = backgroundColor
    preInteractionBackgroundOpacity = backgroundOpacity
}

func endInteraction() {
    interacting = false
}

func registerDeferredUndo(actionName: String, restore: @escaping @MainActor () -> Void) {
    deferredUndoTask?.cancel()
    deferredUndoTask = Task { [weak self] in
        guard let self else { return }
        try? await Task.sleep(for: FrameTempo.backgroundUndoDebounce)
        guard !Task.isCancelled else { return }
        restore()
        self.deferredUndoTask = nil
    }
}

func cancelDeferredUndo() {
    deferredUndoTask?.cancel()
    deferredUndoTask = nil
}
```

### 3. `CollageViewModel.swift` — Background property setters

Replace the 5 background property setters with the new pattern: immediate `updateBackground()` + deferred undo registration.

#### `gradientAngle` (line 295-307)

Before:
```swift
var gradientAngle: Double {
    get { backgroundManager.gradientAngle }
    set {
        let old = backgroundManager.gradientAngle
        backgroundManager.gradientAngle = newValue
        guard !isInitializing else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.backgroundManager.gradientAngle = old
        }
        undoManager.setActionName("Change Gradient Angle")
        updatePreviewDebounced()
    }
}
```

After:
```swift
var gradientAngle: Double {
    get { backgroundManager.gradientAngle }
    set {
        backgroundManager.gradientAngle = newValue
        guard !isInitializing else { return }
        if !backgroundManager.interacting {
            backgroundManager.beginInteraction()
        }
        backgroundManager.registerDeferredUndo(actionName: "Change Gradient Angle") { [preValue = backgroundManager.preInteractionGradientAngle] in
            self.undoManager.registerUndo(withTarget: self) { $0.backgroundManager.gradientAngle = preValue }
            self.undoManager.setActionName("Change Gradient Angle")
        }
        updateBackground()
    }
}
```

#### `gradientStartColor` (line 267-278)

Same pattern — replace `updatePreviewDebounced()` with `updateBackground()`, defer undo via `backgroundManager.registerDeferredUndo()`, capture `preInteractionGradientStartColor`.

#### `gradientEndColor` (line 281-293)

Same pattern — capture `preInteractionGradientEndColor`.

#### `backgroundColor` (line 228-243)

Same pattern — replace the debounced `updatePreview()` with immediate `updateBackground()`, defer undo via `backgroundManager.registerDeferredUndo()`, capture `preInteractionBackgroundColor`.

#### `backgroundOpacity` (line 331-343)

Same pattern — capture `preInteractionBackgroundOpacity`.

**Key differences from current code:**
- No `debouncer.debounce(id: "previewRender", ...)` or `debouncer.debounce(id: "backgroundColor", ...)` 
- No immediate `undoManager.registerUndo()` in the setter
- `updateBackground()` is called immediately (no debounce) — the background-only render is ~1ms, fast enough for real-time updates

### 4. `CollageViewModel.swift` — `regenerateLayout()`

Remove the transient non-layered mode path (line 605-608):

Before:
```swift
isLayeredMode = false
updatePreview()
updateAllPanelPreviews()
```

After:
```swift
updateAllPanelPreviews()
```

This eliminates the wasted full composite render that is immediately superseded by the layered render. The editor view always uses layered mode for display.

### 5. `CollageViewModel.swift` — `awaitPendingTasks()`

Add `backgroundManager.deferredUndoTask` to the synchronization list so tests can await deferred undo:

```swift
func awaitPendingTasks() async {
    await imageCoordinator.awaitPendingTasks()
    await previewManager.awaitPendingTasks()
    if let task = deferredUndoTask {
        await task.value
    }
    if let task = backgroundManager.deferredUndoTask {
        await task.value
    }
}
```

### 6. `CollageViewModel.swift` — `clearAll()`

Cancel any pending deferred undo in `clearAll()`:

```swift
backgroundManager.cancelDeferredUndo()
```

## Files Modified

| File | Lines | Change |
|------|-------|--------|
| `FrameTempo.swift` | +1 | Add `backgroundUndoDebounce` constant |
| `BackgroundManager.swift` | ~30 lines | Add interaction tracking + deferred undo methods |
| `CollageViewModel.swift` | ~40 lines | Rewrite 5 background setters, simplify `regenerateLayout()`, update `awaitPendingTasks()`, update `clearAll()` |

## Verification

### Automated
- `bash script/run_tests.sh` — all tests pass
- Check `ExportFlowTests.swift:82` — sets `isLayeredMode = false`; may need adjustment if it expects `previewImage` to be populated by `regenerateLayout`

### Manual
1. **Gradient angle slider**: Drag the slider — preview should update smoothly without stuttering
2. **Undo behavior**: Drag slider, release, wait 150ms, Cmd+Z — should revert to pre-drag value (single undo step)
3. **Color pickers**: Drag gradient start/end color wells — smooth updates, single undo on release
4. **Background opacity**: Drag opacity slider — smooth updates, single undo on release
5. **Layered mode**: Verify layered mode background updates in real-time during slider drag
6. **Export**: Verify export still produces correct composite with updated background

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| `ExportFlowTests` expects `isLayeredMode = false` and `previewImage` to be set by `regenerateLayout` | `updateAllPanelPreviews()` does not set `previewImage`; may need to add a test-specific path or update the test |
| Rapid slider drag followed by layout change — deferred undo may fire after layout change | `clearAll()` and `regenerateLayout()` should cancel `backgroundManager.deferredUndoTask` |
| `isLayeredMode` is now effectively always `true` after `regenerateLayout` | The `isLayeredMode = false` line was only setting the transient state; `updateAllPanelPreviews()` already sets it to `true` |

## Notes

- The full composite (`previewImage`) is still built by `updatePreview()` for layout-affecting changes (layout style, gutter, panel operations). Export builds its own fresh composite.
- The `debouncer.debounce(id: "previewRender", ...)` call is still used by other properties (e.g., `doubleExposureMaskOpacity`) and should not be removed.
- `updateBackground()` calls `previewManager.updateBackground()` which runs async on a background task with its own generation counter for stale-result discard.
