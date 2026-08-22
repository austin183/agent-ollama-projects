# Gesture Rendering Performance — Eliminate Mid-Gesture CoreGraphics Work — Session 81

**Date:** 2026-06-03
**Plan:** `2026-06-03-gesture-rendering-performance.md` Phases 1-4

## Context

The user reported that panning and zooming large images (4000+ px) became choppy when zoomed out. Previous fixes (title layout cache, pinch throttle, PanelOverlay consolidation, panelFrames dedup) reduced SwiftUI body-evaluation cost but didn't address the CoreGraphics rendering bottleneck.

**Root cause:** Three debounce tasks fired `updatePanelPreview()` ~150ms after each gesture event. When zoomed out, `sourceRect` is large (many megapixels), so `context.draw(cropped, in: destRect)` with `.high` interpolation is expensive. The resulting `NSImage` assignment to `@MainActor` state interrupted the 33fps `cropMapVersion` notification cycle, causing visible frame drops.

## Approach

Implemented all 4 phases from the plan, then fixed a regression where live gesture feedback was lost.

### Phase 1: Cancel debounced preview renders during active gestures

Removed the `Task.sleep(150ms)` + `updatePanelPreview()` pattern from `scrollPanDelta()`, `applyPinchLive()`, `applyOverlayCropLive()`. Added cancellation in `beginScrollPan()` and `beginPinch()` to discard stale renders from previous gestures.

**Regression discovered by user:** In non-layered mode, `previewImage` is a static composite — crop changes don't affect its pixel content. Eliminating ALL mid-gesture renders eliminated live visual feedback.

**Fix:** Replaced "cancel and nil" with throttled background renders:
- `throttledScrollPanRender()` — fires every 60ms (~16fps) during scroll pan
- `throttledOverlayRender()` — fires every 50ms (~20fps) during overlay crop drag
- Pinch renders on every `applyPinchLive()` call (already throttled at gesture level by `GestureCoordinator.shouldProcessPinch()`)
- All use `Task.detached` + `await MainActor.run` for background rendering with main-actor state mutation

### Phase 2: Lower interpolation quality for preview renders

Changed `context.interpolationQuality` from `.high` to `.medium` in `renderPreviewIntoContext()` and `renderPanel()`. Export path (`renderIntoContext()`) keeps `.high` for quality.

### Phase 3: Remove mid-scroll commit timer

Removed `scrollCommitTimer` property, `scheduleScrollPanCommit()` method (150ms `DispatchWorkItem`), and timer cleanup from `endScrollPan()`. The timer was doing double duty: committing accumulated delta AND calling `endGesture()`. Removing it required moving `endGesture()` to the explicit gesture-end path.

### Phase 4: Dual-interval throttle for scroll pan

`throttledNotifyCropMapChanged(forScrollPan:)` now accepts a flag — scroll pan uses 60ms interval (16fps) vs 30ms (33fps) for pinch/overlay. Halves SwiftUI body re-evaluations during scroll.

## Bugs Fixed by diff-review

1. **`endScrollPan` left `gestureActivePanelId` dangling** — `CropManager.endScrollPan()` only cleared `scrollPanPanelId` but not `gestureActivePanelId` (set by `beginPan()` called from `beginScrollPan()`). Subsequent pinch on a different panel targeted the stale panel via `panelId ?? gestureActivePanelId`. Fix: `endScrollPan()` now calls `endGesture()`.

2. **`endScrollPan` didn't cancel `previewDebounceTask`** — A pending scroll pan render could fire after `endScrollPan()` and overwrite a subsequent pinch result. Fix: cancel `previewDebounceTask` at the top of `endScrollPan()`.

## Build Status

**BUILD SUCCEEDED** — Zero warnings.

**ALL TESTS PASS** — 235+ tests pass.

## Files Changed

- `ViewModel/CollageViewModel.swift` — Throttled render methods, dual-interval throttle, commit timer removal, gesture-end cleanup
- `ViewModel/CropManager.swift` — `endScrollPan()` calls `endGesture()`
- `Services/CollageAssembler.swift` — `.medium` interpolation in preview paths
