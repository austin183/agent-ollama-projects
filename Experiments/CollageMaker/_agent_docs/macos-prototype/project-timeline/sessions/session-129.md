# Session 129 — Visual Validation Automation Phase 1 (Debugging)

**Date:** 2026-06-25
**Plan:** `2026-06-24-visual-validation-automation.md` Phase 1

## Summary

Continued debugging 3 failing undo tests from session 128. Tests pass in isolation but fail within the full suite. Discovered the root cause is not cross-contamination between suites, but rather something within the `@Suite(.serialized)` execution itself. Reordered tests to run simpler ones first, removed redundant `regenerateLayout()` calls from `undoAfterLayoutStyleChange`, and fixed `removeImage` to not call `regenerateLayout()` manually (since `removeImage` in the gauntlet should rely on the undo handler's own `regenerateLayout()` call). Session paused for theory generation.

## Changes

### Test file: `CollageViewModelUndoTests.swift`

- Removed redundant `vm.regenerateLayout()` after `vm.setLayoutStyle()` — `setLayoutStyle` already calls `regenerateLayout` internally
- Removed `vm.regenerateLayout()` after `vm.removeImage(at:)` in `undoMultiStepSequence` — the `removeImage` undo handler already includes its own `regenerateLayout()`, and the test should verify the removal without manual regeneration
- Reordered tests to run simpler ones first (title, image removal, crop, gutter) before complex tests (layout style, clear all, multi-step gauntlet)
- Removed debug print statements

## Key Discoveries

### Tests pass in isolation but fail within suite

All 3 failing tests (`undoMultiStepSequence`, `undoClearAllRestoresFullState`, `undoAfterLayoutStyleChange`) pass when run individually via `-only-testing` but fail when the full suite runs. Even selecting all 3 by name passes, but selecting the suite fails. This suggests the Swift Testing framework may be running tests differently when invoked at suite level vs individual test level.

### `@Suite(.serialized)` doesn't prevent the issue

The suite-level `.serialized` attribute should ensure tests run sequentially, yet the failures persist. This eliminates simple concurrency between tests within the suite as the cause.

### `UndoManager` is per-ViewModel

Each test creates a fresh `CollageViewModel` with its own `UndoManager`, so there's no shared undo stack between tests. UserDefaults isolation via UUID suite names also prevents persistence cross-talk.

## Verification

- Build: succeeded
- Tests: 443 pass (450 total, 7 new — 4 pass, 3 fail)
- Isolation tests: All 3 failing tests pass when run individually

## Two Theories for Next Session

### Theory 1: Swift Testing framework re-entrancy with `@Suite(.serialized)`

When Swift Testing runs a `@Suite(.serialized)` suite, it may dispatch the test methods through a different concurrency mechanism than individual test invocation. The `@MainActor` + `@Suite(.serialized)` combination might cause the async test methods to be suspended/resumed in an unexpected way, leading to debounced operations (like `setGutter` and `backgroundColor` which use a 20ms debounce) not completing before the test's undo operations execute. The `awaitDebounced` helper sleeps for 120ms, but if the debouncer's Task is scheduled on a different actor or run loop, the sleep may not be sufficient. **Investigation:** Try increasing the debounce sleep to 500ms, or replace the debouncer with a synchronous implementation in tests.

### Theory 2: `removeImage` doesn't regenerate layout synchronously

In `undoMultiStepSequence`, after `vm.removeImage(at: 2)`, the test awaits pending tasks. But `removeImage` in the ViewModel calls `imageCoordinator.removeImage()` which removes from `imageLibrary.images`, triggering the `onImagesChanged` callback which calls `regenerateLayout()`. However, the `onImagesChanged` callback is set up in the VM init and may fire asynchronously or within a Task. If `regenerateLayout` hasn't completed by the time the snapshot is taken, the panel count assertion could fail. **Investigation:** Check whether `onImagesChanged` fires synchronously and whether `regenerateLayout` completes before `awaitPendingTasks()` returns.

## New Learnings

None yet — pending resolution of the 3 failing tests.

---
**Status**: Open (3 tests failing, 2 theories proposed)
**Follow-up**: Test Theory 1 (debouncer asynchrony) and Theory 2 (removeImage callback timing)

---

# Second Opinion
We asked another developer agent to review our progress for feedback.  These are additional items we can consider for our next session.

```
I have reviewed the progress on Phase 1 of the Visual Validation Automation Plan and analyzed the failing tests.
Analysis of Failures
The 3 failing tests (undoMultiStepSequence, undoClearAllRestoresFullState, undoAfterLayoutStyleChange) pass in isolation but fail in the suite. This strongly suggests non-deterministic state corruption caused by floating asynchronous tasks.
1. Debouncer Leak in clearAll(): CollageViewModel.clearAll() resets the state but does not cancel pending debounced operations (e.g., setGutter or backgroundColor). If a user changes the gutter and immediately clears the collage, the debounced regenerateLayout() call will eventually fire, potentially clobbering the state restored by an undo() of the clear operation.
2. Untracked Saliency Tasks: ImageCoordinator triggers saliency analysis using Task { ... } in scheduleSaliencyAnalysis(). These tasks are not tracked by PreviewManager or any other synchronization mechanism. When they complete, they call computeCropsFromSaliency and updatePreview(), which can modify the state (specifically cropMap and previewImage) at an unexpected time, causing assertions to fail during undo sequences.
3. Incomplete Synchronization: CollageViewModel.awaitPendingTasks() only awaits rendering tasks in PreviewManager. It does not await the floating saliency tasks in ImageCoordinator or the debounced tasks in Debouncer.
Recommended Path Forward
We have sufficient information to solve these issues. I recommend the following implementation plan:
1. Fix clearAll Correctness: Modify CollageViewModel.clearAll() to call debouncer.cancelAll() to prevent stale layout changes from firing after a clear.
2. Implement Task Tracking in ImageCoordinator: 
- Store the current saliency analysis Task in a property.
- Add an awaitPendingTasks() method to ImageCoordinator to await this task.
3. Unify Synchronization: Update CollageViewModel.awaitPendingTasks() to await both ImageCoordinator.awaitPendingTasks() and PreviewManager.awaitPendingTasks().
4. Verification: Run the CollageViewModelUndoTests suite. If failures persist, I will introduce a more aggressive awaitDebounced helper that explicitly yields to the MainActor multiple times.
No further research is required; the root causes are evident in the current implementation of asynchronous task management and synchronization.
```