# Gesture Undo Batching — Learnings 2026-05-19

**Purpose:** Document learnings from Phase 4 of the HIG Review plan — integrating undo batching into SwiftUI gesture handlers, where the View layer owns the undo grouping lifecycle.

---

## What Worked

### View-layer undo grouping for gestures

The existing `hig-undo-redo.md` reference shows undo batching as ViewModel methods (`beginCropAdjustment()` / `endCropAdjustment()`). Phase 4 implemented batching directly inside the View's gesture callbacks, which required exposing `undoManager` from `private` to `internal` on the ViewModel:

```swift
// CollageViewModel.swift
let undoManager = UndoManager()  // was: private let
```

The View calls grouping methods directly:

```swift
ScrollPanView(
    onPanBegan: { id in
        viewModel.undoManager.beginUndoGrouping()
        viewModel.beginScrollPan(panelId: id)
        return true
    },
    onPanEnded: {
        viewModel.undoManager.setActionName("Adjust Crop")
        viewModel.undoManager.endUndoGrouping()
        viewModel.endScrollPan()
    }
)
```

**Why this works:** The gesture lifecycle (begin → changed → ended) lives in the View. Having the View call `beginUndoGrouping()` at gesture start and `endUndoGrouping()` at gesture end ensures all incremental crop updates during the gesture are collapsed into a single undo entry. The ViewModel's individual methods (`scrollPanDelta`, `pinch`, etc.) continue to fire per-event — they just don't each register their own undo.

### Three gesture batching patterns

**Scroll pan** — grouping wraps the `ScrollPanView` callbacks directly. Simple, no extra state needed.

**Pinch (MagnificationGesture)** — grouping starts on first `onChanged` (when `pinchPanelId` transitions from nil), ends on `onEnded`:

```swift
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

**Title drag** — undo registration happens at drag *end*, not beginning (see below).

### End-of-gesture undo registration (title drag)

For title drag, the standard "register undo before mutation" pattern doesn't apply directly, because the drag gesture starts anywhere on the canvas and only locks onto the title region after hit-testing in the first `onChanged`. The old state (`TitleStyle`) can only be captured at that lock point, and the undo should only be registered if the style actually changed.

The solution: capture `oldTitleStyle` in `@State` when the drag locks, then register the undo at `onEnded`:

```swift
@State private var oldTitleStyle: TitleStyle?

// In onChanged, when dragTitleLocked first becomes true:
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

**Key difference from property-level undo:** Property-level undo (`didSet` on `titleStyle`) fires on every intermediate position change during the drag, registering many undo entries. The end-of-gesture registration produces exactly one undo entry for the entire drag. The `didSet` undo for `titleStyle` still fires, but each intermediate undo is immediately superseded by the next change — only the end-of-gesture undo captures the full before→after delta that the user expects.

**Note:** This means title drag will produce two undo entries: the individual `didSet` entries for each style assignment during the drag, plus the single "Move Title" entry registered at the end. The "Move Title" entry is the one the user will actually use (it's first in the undo stack). The intermediate `didSet` entries sit behind it and will never be reached unless the user redoes past "Move Title". This is acceptable — the primary undo behavior is correct, and the extra entries are harmless dead weight.

### Property-level undo grouping with inactivity detection

For continuous controls like sliders and color pickers that lack explicit gesture lifecycle callbacks, use an inactivity timer (~150ms) to infer end-of-interaction. Register the undo action immediately (for Cmd+Z responsiveness), wrap it in `beginUndoGrouping()`/`endUndoGrouping()`, and finalize the group after the inactivity window expires. This produces a single undo step per interaction while keeping undo available instantly.

```swift
var gradientAngle: Double {
    get { backgroundManager.gradientAngle }
    set {
        let startedGroup = backgroundManager.beginInteraction()  // Captures OLD values first
        if startedGroup { undoManager.beginUndoGrouping() }
        backgroundManager.gradientAngle = newValue
        let preValue = backgroundManager.preInteractionGradientAngle
        self.undoManager.registerUndo(withTarget: self) { $0.backgroundManager.gradientAngle = preValue }
        backgroundManager.registerDeferredUndo(actionName: "Change Gradient Angle") { [weak self] in
            guard let self else { return }
            self.undoManager.setActionName("Change Gradient Angle")
            self.undoManager.endUndoGrouping()
        }
        updateBackground()
    }
}
```

**Critical guard:** Boolean state flags that track "in progress" must have a guaranteed reset path on every termination code path (timer expiry, cancellation, external interrupt). Missing a reset path is a critical bug — after the first slider drag, `interacting` stays `true` forever and all subsequent drags use stale pre-interaction values. Consider RAII-style wrappers to make this automatic.

**Separation of concerns:** The manager (`BackgroundManager`) owns interaction state and timer lifecycle; it returns `Bool` from `beginInteraction()` to signal "should I open an undo group?" without directly accessing the UndoManager. The ViewModel owns UndoManager coordination and property side effects. This keeps the manager testable in isolation.

---

## What Didn't Work / Gaps

### Intermediate `didSet` undo entries during gestures

As noted above, dragging the title fires `titleStyle`'s `didSet` on every position update, each registering its own undo entry. These accumulate behind the "Move Title" entry. For a long drag, this could be dozens of undo entries in the stack.

**Possible fix:** Suppress `didSet` undo registration during active gestures by adding a flag like `isDraggingTitle` that `didSet` checks:

```swift
var titleStyle: TitleStyle = .default {
    didSet {
        if !isDraggingTitle {
            undoManager.registerUndo(withTarget: self) { target in
                target.titleStyle = oldValue
            }
            undoManager.setActionName("Change Title Style")
        }
        // ... persist, updatePreview ...
    }
}
```

This is a reasonable refinement for future work. The current behavior is functionally correct (Cmd+Z works as expected), just slightly wasteful on memory.

### `backgroundExtensionEffect` API mismatch

The plan specified `.backgroundExtensionEffect(.sidebar)`. The actual SDK 26.5 API only accepts `.backgroundExtensionEffect()` (no arguments) or `.backgroundExtensionEffect(isEnabled: Bool)`. The skill reference `hig-sidebars.md` already shows the correct no-argument form. The plan's `.sidebar` variant may exist in a later SDK or was conflated with another API. Always verify modifier signatures against the target SDK.

---

## Skill Improvements

### `hig-undo-redo.md` — View-layer gesture batching

Add a new section after the existing "Batching Related Actions" section:

**View-layer gesture batching** — When gesture lifecycle lives in the View (e.g., `ScrollPanView` callbacks, `MagnificationGesture`), the View calls `undoManager.beginUndoGrouping()` / `endUndoGrouping()` directly. This requires `undoManager` to be `internal` (not `private`) on the ViewModel. Include the three patterns: scroll pan, pinch, and end-of-gesture registration for title drag.

### `hig-undo-redo.md` — Suppressing `didSet` undo during gestures

Add a note about the interaction between `didSet` undo registration and gesture batching: when a property with `didSet` undo is modified many times during a gesture, each modification registers its own undo entry. Consider adding a guard flag (e.g., `isDraggingTitle`) to suppress `didSet` undo during active gestures, relying on the gesture's end-of-gesture registration instead.

---

## Next Steps

- Update `hig-undo-redo.md` with View-layer gesture batching patterns and `didSet` suppression guard
- Consider adding `isDraggingTitle` guard to `titleStyle` `didSet` to eliminate intermediate undo entries

---
**Status:** Closed
**Follow-up:** `hig-undo-redo.md` skill update; optional `didSet` suppression refinement
