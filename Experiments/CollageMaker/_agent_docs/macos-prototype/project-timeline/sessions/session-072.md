# Preview Lag Fixes — Phase 3: Per-Panel Task Tracking — Session 72

**Date:** 2026-05-31
**Plan:** `_agent_docs/plans/2026-05-31-preview-lag-fixes.md` (Phase 3)

## Context

Phases 1 and 2 reduced render count (8-40x debounce) and per-render CPU (4x smaller bitmap). Phase 3 targets sequential panel rendering: `PreviewManager` had a single `panelPreviewTask` variable, so when `updateAllPanelPreviews` iterated panels, each call to `updatePanelPreview` cancelled the previous panel's task. Only the last panel's task survived — earlier panels were discarded.

## Changes

### `PreviewManager.swift`

- `panelPreviewTask: Task<Void, Never>?` → `panelPreviewTasks: [UUID: Task<Void, Never>] = [:]`
- `updatePanelPreview` now cancels and stores per-panel tasks via `panelPreviewTasks[panelId]`
- `clearAll()` and `cancelAll()` iterate `panelPreviewTasks.values.forEach { $0.cancel() }` and call `removeAll()`

### `PreviewManagerTests.swift`

- `multiplePanelsRenderConcurrently` — 3 panels submitted individually, all render
- `updateAllPanelPreviewsRendersAllConcurrently` — batch method renders all 3 panels

## Design Decisions

- **Dictionary keyed by UUID** — Same key type as `panelGenerations` and `panelRenderedImages`, keeping all per-panel state consistently keyed.
- **No new synchronization needed** — `PreviewManager` is `@MainActor`; all dictionary access is on the main actor.
- **Cancelled tasks linger until `clearAll()`** — Matches existing behavior of `panelRenderedImages` and `panelGenerations` (also only cleaned up in `clearAll()`). Dictionary is bounded by panel count.

## Review Findings (diff-review agent)

No bugs found. Noted:
- Generation guards and dictionary mutations are correctly confined to `@MainActor`
- No memory leaks — cancelled tasks overwritten or cleaned by `clearAll()`/`cancelAll()`
- **Test quality gap**: New tests verify completion, not true concurrency. A slow mock assembler would be needed to assert total time is ~max(individual) rather than ~sum(individual).

## Build & Test

- Build: succeeded, zero warnings
- All 110 unit tests passing (including 2 new Phase 3 tests)
- App launches successfully via `build_and_run.sh --verify`

## Expected Impact

N panels render in parallel instead of sequentially. For a 6-panel layout, initial render time drops from 6x to ~1x (bounded by the serial render queue, but tasks submit non-blockingly).

## Learnings Assessment

No new learnings captured. The per-panel `[UUID: Task]` pattern is a direct analogue of the per-panel `[UUID: Int]` generation counter documented in `generation-counter-stale-render-learnings.md` (Session 69). No API gotchas, edge cases, or unexpected behaviors arose during implementation.
