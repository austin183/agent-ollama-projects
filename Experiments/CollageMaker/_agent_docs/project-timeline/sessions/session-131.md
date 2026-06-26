# Session 131 — Visual Validation Automation Phase 1 (UndoManager Coalescing)

**Date:** 2026-06-25
**Plan:** `2026-06-24-visual-validation-automation.md` Phase 1

## Summary

Continued debugging 2 failing undo tests from session 130. Fixed 3 production bugs. Remaining 2 failures root-caused to `UndoManager` coalescing consecutive registrations within the same run loop cycle. Session paused for next iteration.

## Changes

### 1. `ImageLibraryManager.removeImage` — fire `onImagesChanged` callback

**File:** `ViewModel/ImageLibraryManager.swift` (line 97-102)

`removeImage` was missing the `onImagesChanged?()` call that `addImages` and `moveImages` already fire. Without it, `regenerateLayout()` was never triggered after image removal, leaving stale panels (e.g. 3 panels for 2 images). Added the callback.

### 2. `ImageDomainState` — added `panelAssignments`

**File:** `ViewModel/ImageCoordinator.swift`

Added `panelAssignments: [UUID: Int]` to `ImageDomainState` struct. The `clearDomain()` method now captures `layoutManager.panelAssignments` so the `clearAll` undo handler can fully restore the image-to-panel mapping.

### 3. `CollageViewModel.clearAll` undo handler — restore `panelAssignments`

**File:** `ViewModel/CollageViewModel.swift` (line 621)

Added `target.layoutManager.panelAssignments = oldDomain.panelAssignments` to the undo handler.

### 4. `registerUndo` — explicit undo grouping (attempted)

**File:** `ViewModel/CollageViewModel.swift` (line 407-415)

Wrapped `registerUndo` with `beginUndoGrouping`/`endUndoGrouping` to prevent UndoManager from coalescing consecutive registrations. Did not resolve the suite-level failures.

## Verification

- Build: succeeded
- Tests: 448 pass (450 total, 7 new — 5 pass, 2 fail)
- Pre-existing failures: 0
- **Fixed:** `undoAfterImageRemoval` and `undoMultiStepSequence` now pass (were failing in sessions 128-130)
- **Remaining failures:** `undoAfterLayoutStyleChange` (0.007s) and `undoClearAllRestoresFullState` (0.128s)

## Key Discoveries

### `UndoManager` coalesces consecutive registrations

File-based debug output revealed: after two `setLayoutStyle` calls (hero -> uniform -> hero), only ONE undo action exists. After undo: `canUndo=false, style=hero`. The `UndoManager` coalesces consecutive registrations targeting the same object within a single run loop cycle — standard Cocoa behavior.

### Suite-level contamination source identified

`AppKitInit` suite (which initializes `NSApplication.shared`) is the contamination source. When it runs before `CollageViewModelUndoTests`, the `UndoManager` behavior changes — likely due to `NSApplication` affecting the run loop or event processing that `UndoManager` relies on for action boundaries.

## New Learnings

- `ImageLibraryManager.removeImage` was the outlier — `addImages` and `moveImages` already fire `onImagesChanged`
- `UndoManager` coalesces consecutive undo registrations targeting the same object within a single run loop cycle
- `NSApplication.shared` initialization affects `UndoManager` behavior in tests

## Remaining Issues

### `undoAfterLayoutStyleChange` (0.007s)

Two `setLayoutStyle` calls register only one undo action. Need explicit undo grouping or proxy targets.

### `undoClearAllRestoresFullState` (0.128s)

Passes in isolation, fails in suite. Likely `AppKitInit` contamination. May need additional state in undo handler (`customImageOrder`, `layoutVersion`, `panelRenderedImages`).

---
**Status**: Open (2 tests failing, down from 4)
**Follow-up**: Fix UndoManager coalescing with explicit `beginUndoGrouping`/`endUndoGrouping` in `setLayoutStyle`. Investigate whether `clearAll` undo needs additional state. Consider separating `AppKitInit` into its own test target.
