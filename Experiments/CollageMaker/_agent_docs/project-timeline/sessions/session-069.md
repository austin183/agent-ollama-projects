# Preview Update Performance — Phase 3 — Session 69

**Date:** 2026-05-31
**Plan:** `_agent_docs/plans/2026-05-30-preview-update-performance.md` (Phase 3)

## Context

Phases 1 and 2 eliminated redundant rendering (66% fewer queue submissions) and made queue entry non-blocking (`withCheckedContinuation` + `async`). Phase 3 addresses the final issue: stale render results. Even with non-blocking entry, work already in the FIFO serial queue runs to completion. When rapid gestures produce 5 queued renders, older renders complete after newer ones and overwrite fresh UI state, causing the "catch up" lag.

## Changes

### New `RenderScheduler` actor (`Services/RenderScheduler.swift`)

Thin actor wrapping the serial `DispatchQueue` with `async`/`await` via `withCheckedContinuation`. Provides a generic `render<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T` method that encapsulates the continuation boilerplate.

### `CollageAssembler` refactor

Replaced `private let renderQueue = DispatchQueue(...)` with `private let scheduler = RenderScheduler()`. All 5 rendering methods changed from:
```swift
await withCheckedContinuation { cont in
    renderQueue.async {
        // ... rendering ...
        cont.resume(returning: result)
    }
}
```
to:
```swift
await scheduler.render {
    // ... rendering ...
    return result
}
```

### `PreviewManager` generation tracking

Added generation counters to discard stale render results:
- `previewGeneration: Int` — single counter for preview renders
- `backgroundGeneration: Int` — single counter for background renders
- `panelGenerations: [UUID: Int]` — per-panel counter (fixes `updateAllPanelPreviews` loop where a single counter would only match the last panel)
- `titleGeneration: Int` — single counter for title renders

Each `update*` method increments its counter, captures the value, and checks `guard gen == self.*Generation else { return }` after the `await`. For panel previews, the check happens both before and after the `await` (pre-check guards against starting already-superseded work, post-check guards against stale results).

`clearAll()` resets all generation counters. `cancelAll()` does not (generations remain valid for subsequent renders).

### Test addition

`PreviewManagerTests.stalePreviewRenderIsDiscarded` — uses `GenerationControlledAssembler` with configurable `delayMs` to verify that a fast second render wins over a slow first render.

## Build & Test

- Build: succeeded, zero warnings
- All 38+ unit tests passing (172+ total across all test files)
- App launches successfully via `build_and_run.sh --verify`
