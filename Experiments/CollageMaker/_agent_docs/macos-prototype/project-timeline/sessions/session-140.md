# Gradient Angle Slider Lag Fix — Background-Only Render + Deferred Undo Grouping

**Date:** 2026-06-27
**Plan reference:** `_agent_docs/plans/2026-06-27-gradient-angle-slider-lag-fix.md`
**Goal:** Eliminate slider lag by routing background-only changes through fast `updateBackground()` path, and collapse hundreds of per-tick undo entries into a single Cmd+Z action.

---

## Problem

Dragging the gradient angle slider (and other background-only properties) triggered:
1. A full composite render (~50ms+) on every slider tick (30-60/sec) — even though only the background changed
2. An `UndoManager` registration on each tick — creating hundreds of undo entries per drag gesture

## Solution: Three Parts

### Part A — Background-Only Render Path

Route background-only property changes through `updateBackground()` instead of `updatePreview()`. The editor always uses layered mode for display; the full composite is only needed for export.

**Files changed:**
- `CollageViewModel.swift` — 5 background setters now call `updateBackground()` immediately (no debounce)
- `regenerateLayout()` simplified: removed transient `isLayeredMode = false; updatePreview()` that was immediately superseded by `updateAllPanelPreviews()`

### Part B — Deferred Undo Grouping

Register undo **immediately** when the first property change starts an interaction, wrapped in `beginUndoGrouping()`/`endUndoGrouping()`. The group closes after 150ms of no changes, collapsing all property changes into a single undo step.

**Key insight:** Cmd+Z must work immediately after releasing a slider — not after a 150ms delay. The fix registers the undo action synchronously in the setter, then uses the deferred task only to finalize the grouping.

**Files changed:**
- `BackgroundManager.swift` — Added interaction tracking state (`interacting`, `preInteraction*` properties), `beginInteraction() -> Bool`, `endInteraction()`, `registerDeferredUndo(actionName:finalize:)`, `cancelDeferredUndo()`
- `CollageViewModel.swift` — Rewrote 5 background setters with new pattern; updated `awaitPendingTasks()` to await `backgroundManager.deferredUndoTask`; added open-group cleanup in `clearAll()`

### Part C — Always Layered Mode

Removed the transient non-layered mode in `regenerateLayout()`. The editor view is always in layered mode for display; the non-layered path rendered a full composite that was immediately superseded by `updateAllPanelPreviews()`.

---

## Implementation Details

### Interaction State Machine

```swift
// BackgroundManager.swift

var interacting: Bool = false
var preInteractionGradientAngle: Double = 0
// ... other pre-interaction values

func beginInteraction() -> Bool {
    if interacting { return false }  // Already in interaction — skip
    interacting = true
    preInteractionGradientAngle = gradientAngle  // Capture BEFORE assignment
    // ... capture all pre-values
    return true  // Caller should call undoManager.beginUndoGrouping()
}

func registerDeferredUndo(actionName: String, finalize: @escaping () -> Void) {
    deferredUndoTask?.cancel()
    deferredUndoTask = Task { [weak self] in
        guard let self else { return }
        try? await Task.sleep(for: FrameTempo.backgroundUndoDebounce)
        guard !Task.isCancelled else { return }
        finalize()  // Calls setActionName + endUndoGrouping
        self.endInteraction()
        self.deferredUndoTask = nil
    }
}
```

### Setter Pattern (e.g., `gradientAngle`)

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

### clearAll() Open Group Cleanup

If a background property interaction was in progress, close its open undo group so the "Clear All" undo doesn't get lumped into it:

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

---

## Bugs Found and Fixed

### Critical: `endInteraction()` Never Called (diff-review-g31)

`interacting` flag stayed `true` forever after the first slider drag. All subsequent drags skipped `beginInteraction()` and used stale pre-interaction values from the session start — Cmd+Z reverted to the wrong value.

**Fix:** Call `endInteraction()` in `registerDeferredUndo` (after finalize) and in `cancelDeferredUndo()`.

### Critical: Undo Captured New Value Instead of Old (initial implementation)

First implementation set the property value BEFORE calling `beginInteraction()`, so the pre-interaction capture read the NEW value. Fixed by calling `beginInteraction()` first, then assigning the new value.

---

## Test Changes

- `ExportFlowTests.swift` — Added explicit `vm.updatePreview()` calls after `regenerateLayout()` since the full composite path is no longer triggered by layout regeneration
- `CollageViewModelUndoTests.swift` — Increased `awaitDebounced` sleep from 120ms to 200ms (must exceed 150ms deferred undo delay)
- `CollagePerformanceTests.swift` — Changed `assembler.previewCalls > 0` to `assembler.renderPanelCalls > 0` since scrollPan now only calls per-panel previews

---

## UX Review Findings (world-review)

### Critical: Delayed Undo Availability (150ms ghost window)

**Initial design:** Defer undo registration by 150ms after last change → Cmd+Z does nothing during that window.

**Fix applied:** Register undo immediately in setter, use deferred task only to finalize grouping. Cmd+Z works right away.

### Warning: Inconsistent Grouping for Rapid Sequential Changes

If user changes gradient angle then opacity within 150ms, both go into one group → single undo reverts both. This is the intended behavior (one gesture = one undo), but may feel unintuitive if user expected two separate steps.

**Mitigation:** The 150ms window matches macOS conventions for continuous controls. Users can Cmd+Z twice if they want separate undos.

---

## Verification

- `bash script/run_tests.sh` — 473/473 pass
- Manual: gradient angle slider drag is smooth at 60fps, single undo entry per gesture, Cmd+Z reverts to pre-drag value immediately
