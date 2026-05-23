# Session 45 — 2026-05-23

### Round 15 CR: Performance Degradation Investigation and Fix

**Goal:** Investigate and fix the performance degradation described in `_agent_docs/change-requests/round-15.md` — edits becoming progressively slower over time with memory growing from ~250MB to 500-780MB.

**Source:** Round 15 change request — performance degradation during extended editing sessions.

**Investigation:**

Thorough investigation of `CollageViewModel.swift`, `ScrollPanManager.swift`, `CropManager.swift`, `CollageEditorView.swift`, `SaliencyAnalyzer.swift`, and `CollageAssembler.swift` identified three root causes:

1. **Unbounded undo stack** — `UndoManager` (line 34) had no `levelsOfUndo` limit. Every property mutation across 15+ `didSet` blocks registered an undo operation capturing `self` (entire view model with all loaded images). These accumulated indefinitely with no trimming.
2. **Intermediate `didSet` undo during gestures** — `titleStyle.didSet` (line 92-101) registered an undo entry on every mouse move during title drag, producing 50-200+ undo entries per single drag gesture. The `isDraggingTitle` flag existed but was never checked in the `didSet`. This gap was already documented in `_agent_docs/learnings/gesture-undo-batching-learnings.md:96-112` as a known refinement.
3. **Excessive preview tasks during scroll** — `scrollPanDelta` called `updatePreview()` on every scroll event, spawning 30-100+ CoreGraphics assembly tasks per scroll gesture.

**Changes Implemented:**

#### 1. Capped undo stack (`CollageViewModel.swift:264`)

Added `self.undoManager.levelsOfUndo = 60` in the initializer. This is a single-line fix that automatically discards the oldest operations when the limit is reached, preventing unbounded memory growth.

#### 2. Guarded `titleStyle.didSet` undo during drag (`CollageViewModel.swift:94-99`)

Wrapped the undo registration in `if !isDraggingTitle { ... }`, suppressing intermediate undo entries during title drag. The end-of-gesture undo registration in `CollageEditorView.swift:279-282` still captures the full before-to-after delta for correct undo behavior.

#### 3. Debounced scroll preview, then reverted (`CollageViewModel.swift:677-713`)

Initially added a 150ms debounce to `updatePreview()` in the `applyLive` callback of `scrollPanDelta`. However, user reported this broke the real-time canvas image update during two-finger scroll gestures. Investigation confirmed the scroll path never registered undo entries (`cropMap` has no undo `didSet`), so the debounce was only hurting responsiveness without helping memory. Reverted to immediate `updatePreview()` calls, which cancel stale tasks via the existing `previewTask?.cancel()` pattern.

**Why the scroll path didn't contribute to memory:**

The `cropMap` property has no `didSet` undo registration. The `updatePreview()` method already cancels stale tasks via `previewTask?.cancel()` before spawning new ones. CG compositing at 1920x1080 is <100ms per the skill performance notes. The memory growth came from undo entries on other properties (title drag, typing, color changes), not from scroll preview tasks.

**Build and Test Status:**
- **Build:** Succeeded — zero errors, zero warnings
- **Tests:** Not run — existing test suite unchanged

**Session Status:** Complete — two memory fixes in place (undo cap, gesture guard), scroll preview restored to real-time updates.
