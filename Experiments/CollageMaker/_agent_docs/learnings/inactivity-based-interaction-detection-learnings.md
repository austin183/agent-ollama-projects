# Inactivity-Based End-of-Interaction Detection — Learnings

**Date:** 2026-06-27
**Purpose:** Document learnings from implementing deferred undo grouping for background property sliders (gradient angle, colors, opacity) that lack explicit gesture lifecycle callbacks.

## What Worked

### Immediate undo registration with deferred grouping finalization

For continuous controls like sliders and color pickers, the user expects Cmd+Z to work immediately after releasing the mouse — not after an arbitrary delay. The pattern:

1. **Register undo immediately** in the property setter (synchronous, on MainActor)
2. **Wrap in `beginUndoGrouping()`/`endUndoGrouping()`** so multiple property changes during one interaction collapse into a single undo step
3. **Use an inactivity timer** (150ms) to infer end-of-interaction and finalize the group

```swift
var gradientAngle: Double {
    get { backgroundManager.gradientAngle }
    set {
        guard !isInitializing else { return }

        let startedGroup = backgroundManager.beginInteraction()
        if startedGroup {
            undoManager.beginUndoGrouping()  // Group all property changes
        }

        backgroundManager.gradientAngle = newValue

        let preValue = backgroundManager.preInteractionGradientAngle
        self.undoManager.registerUndo(withTarget: self) { $0.backgroundManager.gradientAngle = preValue }
        // Undo registered immediately — Cmd+Z works right away

        backgroundManager.registerDeferredUndo(actionName: "Change Gradient Angle") { [weak self] in
            guard let self else { return }
            self.undoManager.setActionName("Change Gradient Angle")
            self.undoManager.endUndoGrouping()  // Finalize as single undo step
        }
        updateBackground()  // Fast background-only render (~1ms)
    }
}
```

**Why this works:** The undo action exists on the stack immediately, so Cmd+Z is responsive. The grouping ensures that if the user changes multiple properties during one interaction (e.g., gradient angle then opacity), they get a single undo step instead of two.

### Interaction state machine with `beginInteraction() -> Bool`

The `BackgroundManager` tracks whether an interaction is in progress. `beginInteraction()` returns `true` only on the first call within an interaction sequence, signaling the caller to open the undo group:

```swift
func beginInteraction() -> Bool {
    if interacting { return false }  // Already in interaction — skip
    interacting = true
    preInteractionGradientAngle = gradientAngle  // Capture BEFORE assignment
    // ... capture all pre-values
    return true  // Caller should call undoManager.beginUndoGrouping()
}
```

This separation of concerns lets `BackgroundManager` own the state tracking while `CollageViewModel` owns the UndoManager coordination.

### Open group cleanup in `clearAll()`

If a background property interaction was in progress when `clearAll()` is called, close its open undo group so the "Clear All" undo doesn't get lumped into it:

```swift
func clearAll() {
    guard !imageLibrary.images.isEmpty else { return }

    if backgroundManager.interacting {
        undoManager.endUndoGrouping()  // Close orphaned group
    }
    backgroundManager.cancelDeferredUndo()
    // ... rest of clearAll
}
```

Without this, the open group stays on the stack and subsequent undo registrations get lumped into it.

## What Didn't Work / Gaps

### `interacting` flag never reset (critical bug)

**Problem:** The initial implementation called `beginInteraction()` but never called `endInteraction()`. After the first slider drag, `interacting` stayed `true` forever. All subsequent drags skipped `beginInteraction()` and used stale pre-interaction values from the session start — Cmd+Z reverted to the wrong value.

**Fix:** Call `endInteraction()` in `registerDeferredUndo` (after finalize) and in `cancelDeferredUndo()`.

```swift
func registerDeferredUndo(actionName: String, finalize: @escaping () -> Void) {
    deferredUndoTask?.cancel()
    deferredUndoTask = Task { [weak self] in
        guard let self else { return }
        try? await Task.sleep(for: FrameTempo.backgroundUndoDebounce)
        guard !Task.isCancelled else { return }
        finalize()
        self.endInteraction()  // <-- Reset interacting flag here
        self.deferredUndoTask = nil
    }
}

func cancelDeferredUndo() {
    deferredUndoTask?.cancel()
    deferredUndoTask = nil
    if interacting { endInteraction() }  // <-- And here
}
```

**Lesson:** Boolean state flags that track "in progress" must have a guaranteed reset path. Every code path that can terminate the interaction (timer expiry, cancellation, external interrupt) must call the reset method. Consider using a struct with `deinit` or a RAII-style wrapper to make this automatic.

### Pre-interaction capture order matters

**Problem:** First implementation set the property value BEFORE calling `beginInteraction()`, so the pre-interaction capture read the NEW value instead of the OLD value. Cmd+Z restored the new value (no-op).

**Fix:** Call `beginInteraction()` first, then assign the new value:

```swift
let startedGroup = backgroundManager.beginInteraction()  // Captures OLD values
if startedGroup { undoManager.beginUndoGrouping() }
backgroundManager.gradientAngle = newValue  // Now safe to assign
```

## Key Patterns

### When to use inactivity-based detection vs. explicit gesture lifecycle

| Control type | Has explicit start/end? | Detection method |
|---|---|---|
| Scroll pan, pinch, title drag | Yes (gesture callbacks) | View-layer `beginUndoGrouping()`/`endUndoGrouping()` tied to `onChanged`/`onEnded` |
| Slider drag, color picker drag | No (property setter fires per-tick) | Inactivity timer (150ms) + interaction state machine |
| Typing in text field | No (each keystroke is discrete) | Immediate undo registration, no grouping needed |

**Rule of thumb:** If the control produces more than ~10 events/sec during normal interaction AND lacks explicit start/end callbacks, use inactivity-based detection with immediate undo registration + deferred grouping finalization.

### Separation of concerns: state tracking vs. undo coordination

`BackgroundManager` owns:
- Interaction state (`interacting`, `preInteraction*` values)
- Inactivity timer lifecycle (`deferredUndoTask`)
- State transitions (`beginInteraction()`, `endInteraction()`, `cancelDeferredUndo()`)

`CollageViewModel` owns:
- UndoManager coordination (`beginUndoGrouping()`, `registerUndo()`, `endUndoGrouping()`)
- Property assignment side effects (`updateBackground()`)

The manager returns a `Bool` from `beginInteraction()` to signal "should I open an undo group?" without directly accessing the UndoManager. This keeps the manager testable in isolation.

## Skill Improvements

### `gesture-undo-batching-learnings.md` — Add section on property-level interactions

Add a new section after the existing gesture patterns:

**Property-level undo grouping with inactivity detection** — For continuous controls like sliders and color pickers that lack explicit gesture lifecycle callbacks, use an inactivity timer (150ms) to infer end-of-interaction. Register the undo action immediately (for Cmd+Z responsiveness), wrap it in `beginUndoGrouping()`/`endUndoGrouping()`, and finalize the group after the inactivity window expires. This produces a single undo step per interaction while keeping undo available instantly.

**Critical guard:** Boolean state flags that track "in progress" must have a guaranteed reset path on every termination code path (timer expiry, cancellation, external interrupt). Consider RAII-style wrappers to make this automatic.

### `undomanager-integration-learnings.md` — Add note on immediate registration

Add a note: When using `beginUndoGrouping()`/`endUndoGrouping()` for grouping, register the undo action immediately (not deferred). The group is just a container — the undo action must exist on the stack before `endUndoGrouping()` closes it. Deferring registration until after the inactivity window makes Cmd+Z unresponsive during that window.

## Next Steps

- Consider extracting the interaction state machine into a reusable `InteractionTracker` utility
- Document the 150ms inactivity window choice in `FrameTempo.swift` comments (already there, but could reference this learning)

---
**Status:** Closed
**Follow-up:** Session 140 — Gradient Angle Slider Lag Fix
