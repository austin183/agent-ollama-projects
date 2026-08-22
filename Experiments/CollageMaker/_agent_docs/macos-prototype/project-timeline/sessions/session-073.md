# Round 20 CR: Gutter Slider Bug Fix — Session 73

**Date:** 2026-05-31
**Change Request:** `_agent_docs/change-requests/round-20.md`

## Context

Two bugs in gutter slider interaction:
1. **Panels disappear during drag** — `regenerateLayout()` fired 30-60x/sec, each call cleared `panelRenderedImages` synchronously then kicked off async render, leaving a blank canvas during every intermediate slider position.
2. **Image transforms reset** — `regenerateLayout()` called `cropMap.removeAll()` + recomputed crops from saliency, destroying user pan/zoom adjustments. New panel UUIDs meant old crop entries wouldn't match anyway.

## Changes

### `CollageViewModel.swift`
- **Debounced gutter `didSet`** — New `gutterDebounceTask` (150ms) defers `regenerateLayout()` until user stops dragging. Undo registration and `debouncedSave()` moved into the debounced callback (not `didSet`), eliminating spurious undo entries per slider tick.
- **`regenerateLayout(preserveCrops:)`** — New boolean parameter. When `true`, extracts crops and rendered images by slot index before regeneration, then reapplies by slot index to new panel UUIDs.
- **Conditional `panelRenderedImages` clear** — `removeAll()` only in non-preserve path (layout style change, image add/remove). Preserve path remaps images to new UUIDs.

### `CropManager.swift`
- **`cropsBySlot(_:)`** — Extracts `sourceRect` values by slot index from `cropMap`.
- **`applyCropsBySlot(_:panels:)`** — Applies extracted `sourceRect` values to new panels by slot index, computing new `destinationRect` from panel frames.

### `PreviewManager.swift`
- **`panelRenderedImagesBySlot(_:)`** — Extracts rendered `NSImage` values by slot index.
- **`applyRenderedBySlot(_:panels:)`** — Applies extracted images to new panels by slot index.

### `ExportFlowTests.swift`
- **`gutterChangeRegeneratesLayout`** — Made async, added `await Task.sleep` before capturing `panelsNoGutter` so debounced layout fires before assertion.

## Design Decisions

- **Slot-index preservation** — Panel UUIDs change on every layout regeneration, but slot index (position in `panels` array) corresponds to the same image via `customImageOrder`. Extracting by index before and applying after preserves user-adjusted crops and rendered images across UUID identity changes.
- **Defer undo to commit** — Registering undo in `didSet` for a debounced property creates one undo entry per slider tick (~30-60). Moving to the debounced callback creates one entry per drag gesture.
- **First regression — memory leak** — Initial fix removed `panelRenderedImages.removeAll()` entirely. diff-review caught that non-preserve callers (layout style change, image add/remove) now leaked orphaned `NSImage` entries. Fixed by gating `removeAll()` in the non-preserve branch.
- **Second regression — trivial test** — Test captured `panelsNoGutter` before debounce fired, so it compared `[]` to `[non-empty]`. Fixed by awaiting first debounce.

## Build & Test

- Build: succeeded, zero warnings
- All 168 unit tests passing
- App launches successfully via `build_and_run.sh --verify`
- diff-review agent found 2 bugs (memory leak, trivial test), both fixed

## Learnings

See `../learnings/slot-index-state-preservation-learnings.md`
