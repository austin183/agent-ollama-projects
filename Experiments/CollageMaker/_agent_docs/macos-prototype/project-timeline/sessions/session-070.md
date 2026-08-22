# Preview Lag Fixes — Phase 1: Debounce — Session 70

**Date:** 2026-05-31
**Plan:** `_agent_docs/plans/2026-05-31-preview-lag-fixes.md` (Phase 1)

## Context

Phases 1-3 of preview performance eliminated redundant gesture renders, made queue entry non-blocking, and added generation counters to discard stale results. But lag persisted during slider drags and color picker interaction. Root cause: 6 background/title property `didSet` observers fired `updatePreview()` immediately with no debounce — a single slider drag could fire 50+ events, each spawning a full-canvas render.

## Changes

### New `updatePreviewDebounced()` method (`CollageViewModel.swift`)

150ms debounce using the existing cancel-sleep-render pattern:
```swift
func updatePreviewDebounced() {
    previewRenderDebounceTask?.cancel()
    previewRenderDebounceTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 150_000_000)
        self?.updatePreview()
    }
}
```

Separate `previewRenderDebounceTask` from existing `previewDebounceTask` — the latter is used by panel pan/pinch/scroll gestures for per-panel crop preview, this one is for full-canvas background/title property changes.

### Property classification: debounced vs immediate

**Debounced** (rapid, continuous interaction):
- `gradientAngle` — slider drag, most frequent offender
- `gradientStartColor` — color picker drag
- `gradientEndColor` — color picker drag
- `backgroundColor` — color picker drag
- `backgroundOpacity` — slider drag

**Immediate** (discrete, user expects instant feedback):
- `titleAttrString` — typing, each keystroke should show
- `titleStyle` — discrete enum picker selection
- `backgroundStyle` — discrete enum picker selection
- `backgroundImage` — discrete image selection

### Cross-boundary cancellation

`regenerateLayout()` and saliency completion handler now cancel `previewRenderDebounceTask?.cancel()` before calling `updatePreview()` directly. Prevents a pending debounced render from firing after a layout-wide re-render already produced fresh state.

## Review Findings (diff-review agent)

1. **`backgroundStyle` should not be debounced** — Reverted to immediate. It's a discrete enum picker, not a continuous drag. User can't click faster than ~5-10x/sec, and a 150ms delay feels sluggish.
2. **Missing cancellation in `regenerateLayout()` and saliency** — Added `previewRenderDebounceTask?.cancel()` at entry points. Without this, a debounced task sleeping 150ms after a slider drag would wake and re-render over the layout's fresh composite.

## Build & Test

- Build: succeeded, zero warnings
- All 182 unit tests passing
- App launches successfully via `build_and_run.sh --verify`

## Expected Impact

8-40x reduction in render queue submissions during slider/color picker interaction. Combined with Phase 2 (render at preview size, 4x faster per render), total CPU drops 32-160x during these interactions.
