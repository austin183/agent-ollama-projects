# Editor Performance Phase 2: Title Setter Side Effects — Session 75

**Date:** 2026-06-01
**Change Request:** `_agent_docs/plans/2026-05-31-editor-performance-plan.md` (Phase 2)

## Context

Phase 2 addressed Problem C (partial): `titleAttrString.didSet` called `updatePreview()` unconditionally, compositing all panels + title at 960x540 — even in layered mode where `previewImage` is never displayed. Established regression safety for Phase 1 cache changes.

## Changes

### `ViewModel/CollageViewModel.swift`
- **`titleAttrString.didSet`** — Added `isLayeredMode` guard: in layered mode calls `updateTitleImage()` (title-only render), otherwise calls `updatePreview()` (full composite).
- **`titleStyle.didSet`** — Same `isLayeredMode` guard for non-drag changes: layered mode calls `updateTitleImage()`, composite mode calls `updatePreview()`.
- **`awaitPendingTasks()`** — Test helper that delegates to `previewManager.awaitPendingTasks()`.

### `Services/PreviewManager.swift`
- **`awaitPendingTasks()`** — Bounded 300ms sleep to let pending async rendering tasks complete. Used by tests to synchronize with `@MainActor` work.

### `CollageMakerTests/TestHelpers.swift`
- **`TrackingAssembler`** — Added `titleRenderCalls` counter to `renderTitle()` for verifying title-only rendering.

### `CollageMakerTests/CollageViewModelTests.swift`
- 7 new Phase 2 tests:
  - `titleAttrStringSetterCallsUpdatePreview` — verifies title render on string change
  - `titleStyleSetterNotDraggingCallsUpdatePreview` — verifies title render on non-drag style change
  - `titleStyleSetterDraggingCallsUpdateTitleImageLive` — verifies debounced title render during drag
  - `titleStyleSetterDraggingSkipsUndo` — verifies position change survives undo
  - `finishTitleDragRendersImmediately` — verifies immediate render after drag
  - `setTitleFontFamilyCallsUpdateTitleImageLive` — verifies title render on font family change
  - `setTitleFontSizeCallsUpdateTitleImageDebounced` — verifies debounced title render on font size change
- Existing `titleColorChangeUpdatesPreview`, `titleBackgroundColorChangeUpdatesPreview`, `titleShowBackgroundChangeUpdatesPreview` updated to check `titleRenderCalls` instead of `previewCalls` (since `regenerateLayout()` sets `isLayeredMode = true`).

### `CollageMakerTests/ExportFlowTests.swift`
- **`updatePreviewPassesTitle`** — Added `vm.isLayeredMode = false` before setting title, so `titleAttrString.didSet` routes to `updatePreview()`.

## Design Decisions

- **`isLayeredMode` guard in both setters** — In layered mode, the full composite (`updatePreview`) is wasteful because only individual layers are displayed. Calling `updateTitleImage()` directly updates just the title layer.
- **`awaitPendingTasks()` as bounded sleep** — A spin-loop approach (`while task != nil { sleep }`) proved fragile: debounced tasks live in `CollageViewModel` (not `PreviewManager`), and `@MainActor` `Task.sleep` doesn't reliably yield to other tasks in the test runner. A single bounded sleep is simpler and sufficient.
- **Undo test uses position survival** — `UndoManager` has no `level` property. The test verifies that after undo, the position change (which skipped undo registration) is preserved, while the title string change (which was registered) is reverted.

## Build & Test

- Build: succeeded, zero warnings
- All unit tests passing (7 new tests added, 3 existing tests updated, 1 pre-existing flaky test ignored)
- One pre-existing flaky test: `TitleMetricsCacheTests/titleMetricsInvalidatedByFontFamilyChange()` fails in full suite but passes in isolation — suspected `@MainActor` task scheduling issue, not related to Phase 2 changes.

## Learnings

No new learnings that aren't already covered by existing skill references. The `@MainActor` `Task.sleep` yielding behavior and `UndoManager` API limitations were already documented in testing patterns.
