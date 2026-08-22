# Session 130 — Visual Validation Automation Phase 1 (Async Task Fixes)

**Date:** 2026-06-25
**Plan:** `2026-06-24-visual-validation-automation.md` Phase 1

## Summary

Implemented the second-opinion diagnosis from session 129: async task leaks from `Debouncer` and `ImageCoordinator` corrupt undo test state. Made 3 production code fixes. Reduced failing tests from 4 to 2 (`undoAfterImageRemoval` and `undoAfterLayoutStyleChange`). The remaining failures stem from `awaitPendingTasks()` not covering all async work paths, and `regenerateLayout` triggering saliency analysis that races with undo operations. Session paused for next iteration.

## Changes

### 1. `CollageViewModel.clearAll()` — cancel debouncer and saliency tasks

**File:** `ViewModel/CollageViewModel.swift` (line 595-596)

Added `debouncer.cancelAll()` and `imageCoordinator.cancelSaliencyTask()` at the start of `clearAll()`. This prevents stale debounced operations (gutter, backgroundColor) and in-flight saliency analysis from firing on cleared state, which was corrupting undo handlers.

### 2. `ImageCoordinator` — saliency task tracking

**File:** `ViewModel/ImageCoordinator.swift`

- Added `private var saliencyTask: Task<Void, Never>?` property
- `scheduleSaliencyAnalysis()` now stores the task reference and cancels the previous one before creating a new one
- Added `cancelSaliencyTask()` method for explicit cancellation
- Added `awaitPendingTasks()` method for test synchronization
- `analyzeSaliency()` now checks `Task.isCancelled` after the async `analyzeAll` call, discarding results if the task was cancelled (prevents stale saliency results from overwriting restored state)

### 3. `CollageViewModel.awaitPendingTasks()` — unified synchronization

**File:** `ViewModel/CollageViewModel.swift` (line 1064)

Extended to also `await imageCoordinator.awaitPendingTasks()` before `previewManager.awaitPendingTasks()`, so tests can synchronize with both saliency and rendering tasks.

## Verification

- Build: succeeded
- Tests: 448 pass (450 total, 7 new — 5 pass, 2 fail)
- Pre-existing failures: 0 (all pre-existing tests still pass)
- **Fixed:** `undoClearAllRestoresFullState` and `undoMultiStepSequence` now pass (were failing in sessions 128/129)
- **Remaining failures:** `undoAfterImageRemoval` (0.044s) and `undoAfterLayoutStyleChange` (0.003s)

## Key Discoveries

### `undoAfterImageRemoval` was already failing before our changes

Stashing the production changes revealed `undoAfterImageRemoval` was already failing at 0.092s — our changes only made it crash faster (0.002s initially), indicating the `awaitPendingTasks` change exposed a different code path. With the saliency task now properly awaited, the test runs to completion (0.044s) but still fails on an assertion.

### `awaitPendingTasks` must cover all async work

The original `awaitPendingTasks()` only covered `PreviewManager` tasks. Tests that call `regenerateLayout()` spawn saliency analysis tasks that weren't awaited, causing non-deterministic timing between test assertions and async state mutations.

### `Task.isCancelled` guard prevents stale state

The `Task.isCancelled` check inside `analyzeSaliency()` is essential — without it, a cancelled saliency task can complete and overwrite `saliencyResults` and `cropMap` after an undo handler has restored state.

## Remaining Issues

### `undoAfterImageRemoval` (0.044s)

The test adds 3 images, removes one, then undos. With the saliency task now properly awaited, the test runs but an assertion fails. Likely the undo handler's `regenerateLayout()` spawns a new saliency task that races with the test's final assertions.

### `undoAfterLayoutStyleChange` (0.003s)

The test changes layout style hero → uniform → hero, then undos to restore uniform. Fails at 0.003s suggesting a crash or assertion failure early in the undo. May be related to `setLayoutStyle` triggering `regenerateLayout()` which spawns saliency tasks.

## New Learnings

None yet — pending resolution of the 2 remaining failing tests.

---
**Status**: Open (2 tests failing, down from 4)
**Follow-up**: Debug `undoAfterImageRemoval` and `undoAfterLayoutStyleChange` assertion failures. May need to add `awaitPendingTasks()` calls after undo operations in these specific tests, or investigate whether `regenerateLayout()` in undo handlers should suppress saliency analysis.
