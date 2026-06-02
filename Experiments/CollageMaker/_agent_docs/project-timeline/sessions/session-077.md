# Gesture Performance: Throttled @Observable Invalidation — Session 77

**Date:** 2026-06-02
**Change Request:** Pan/zoom lag worsens when zoomed out — per-frame SwiftUI re-evaluation consumes CPU during gestures.

## Context

The user reported that panning and zooming felt sluggish, especially when zoomed out (more panels visible = larger view tree). Investigation revealed that `notifyCropMapChanged()` fired synchronously on every gesture frame (60-120 times/sec for scroll wheel), triggering full `CollageEditorView.body` and `PanelCropEditor.body` re-evaluations via `@Observable`. The existing 150ms debounce only deferred the expensive CoreGraphics rendering, not the SwiftUI view re-evaluation.

## Changes

### Phase 1: Defer notification (initial attempt)

Removed synchronous `notifyCropMapChanged()` from all 4 live gesture methods (`applyPanLive`, `applyPinchLive`, `scrollPanDelta`, `applyOverlayCropLive`) and the scroll commit timer. Moved notification into the debounce callback after `updatePanelPreview()`.

**Problem discovered by user:** Scroll pan "hardly moves at all" — the `mach_absolute_time()`-based scroll throttle was dropping too many events (it returns ticks, not nanoseconds). Overlay crop updates "take too long" — with full deferral, there's no visual feedback during the gesture.

### Phase 2: Throttled notification (final approach)

**New method:** `throttledNotifyCropMapChanged()` — fires at most every ~30ms (~33fps) using `ContinuousClock.now` + `Duration.milliseconds(30)`. Replaced per-frame `notifyCropMapChanged()` in all 4 live methods.

**Scroll throttle fix:** Replaced `mach_absolute_time()` with `ContinuousClock` + `Duration.milliseconds(16)` in `ScrollPanView.ScrollCaptureView.scrollWheel(with:)`.

**Gesture-end notification gap fix:** Discovered that gesture-end paths (`endScrollPan`, `applyPinch(finish)`, `finishOverlayCrop`) cancel the debounce task before it fires, so `notifyCropMapChanged()` never executes. Added explicit `notifyCropMapChanged()` to each gesture-end method.

## Files Changed

- `ViewModel/CollageViewModel.swift` — `throttledNotifyCropMapChanged()` method + throttle state, wired into 4 live methods, removed from debounce callbacks, added to 3 gesture-end methods, removed from `scheduleScrollPanCommit()`
- `Views/ScrollPanView.swift` — `ContinuousClock` + `Duration` throttle in `scrollWheel`, replaced `mach_absolute_time()`

## Build & Test

- Build: succeeded, zero warnings
- All unit tests passing (30 tests, zero failures)

## Learnings

Three new learnings documented in `_agent_docs/learnings/`:
1. **Throttled @Observable invalidation** — bounding notification frequency during high-rate gestures
2. **Gesture-end notification gap** — deferring per-frame notification to debounce creates a gap where gesture-end paths cancel the debounce
3. **`mach_absolute_time()` returns ticks, not nanoseconds** — `ContinuousClock` is the correct Swift alternative
