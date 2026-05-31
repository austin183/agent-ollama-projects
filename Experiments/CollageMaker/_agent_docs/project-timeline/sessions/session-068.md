# Preview Update Performance — Phase 2 — Session 68

**Date:** 2026-05-30
**Plan:** `_agent_docs/plans/2026-05-30-preview-update-performance.md` (Phase 2)

## Context

Phase 1 (session 67) eliminated redundant rendering calls. Phase 2 targets the blocking queue entry problem: `renderQueue.sync { }` blocks the calling thread even though callers are off-main-actor via `Task.detached`. During rapid gestures, 5-10 tasks queue up each blocking their thread waiting for the serial queue, causing accumulated latency.

## Changes

### Protocol methods made `async`

All 5 rendering methods across 4 protocols (`CollageRenderer`, `PanelRenderer`, `BackgroundRenderer`, `TitleRenderer`) changed from synchronous to `async`. This includes the default `assemble()` convenience method in the `CollageAssembly` extension.

### `CollageAssembler` — `withCheckedContinuation` + `async` queue submission

Each rendering method replaced `renderQueue.sync { ... }` with:
```swift
await withCheckedContinuation { cont in
    renderQueue.async {
        // ... rendering work ...
        cont.resume(returning: result)
    }
}
```

The serial `DispatchQueue` is retained (needed for `NSGraphicsContext.current` thread safety) but submission is now non-blocking. The calling thread yields immediately after dispatching work.

### `PreviewManager` — removed `Task.detached` wrappers

Callers changed from:
```swift
let result = await Task.detached { assembler.method(...) }.value
```
to:
```swift
let result = await assembler.method(...)
```

The `Task.detached` wrapper is no longer needed because the async method handles off-main-actor dispatch internally via the serial queue + continuation.

### `ExportManager` — `await` on assembler call

`assembler.assembleWithCGImages(...)` now requires `await` inside the `Task.detached` closure.

### `@unchecked Sendable` conformance

Added to model types that contain non-Sendable AppKit types (`NSColor`, `NSAttributedString`):
- `AssemblyConfig`, `LayoutConfig`, `TitleConfig`, `BackgroundConfig`
- `TitleStyle`
- `NSAttributedString` (extension in CollageAssembler.swift)
- `CollageAssembler` class itself

### Test updates

- All 3 mock assemblers (`MockAssembler`, `TrackingAssembler`, `TestPreviewAssembler`) — added `async` to 5 protocol methods each
- `CollageAssemblerTests` — 9 synchronous tests converted to `async` with `await` at call sites
- 3 concurrent tests already used `await` (was a no-op); now become actual async suspension

## Build & Test
- Build: succeeded (1 expected warning: `NSAttributedString` Sendable extension on imported type)
- All 172+ unit tests passing
