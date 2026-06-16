# Defer notifyCropMapChanged + Scroll Throttle

**Date**: 2026-06-01
**Status**: Implemented — build passes, all 30 tests pass. Refined to use throttled notification for live feedback.
**Goal**: Eliminate per-frame SwiftUI re-evaluation during pan/zoom gestures to fix lag that worsens when zoomed out, while maintaining responsive live visual feedback.

## Root Cause

`notifyCropMapChanged()` fires synchronously on every gesture frame (every scroll wheel event, every magnification sample, every overlay drag delta). This increments `cropMapVersion`, which invalidates ALL SwiftUI views that depend on `cropMap` via `@Observable`. The existing 150ms debounce only defers the expensive CoreGraphics rendering, NOT the SwiftUI view re-evaluation.

During a trackpad scroll gesture (60-120 events/sec), this means `CollageEditorView.body` and `PanelCropEditor.body` re-evaluate 60-120 times/sec — O(n) work that produces zero visual change because the rendered images haven't updated yet.

## Changes Made

### 1. Throttled `notifyCropMapChanged()` in live gesture methods (~33fps)

**File: `CollageViewModel.swift`**

Added `throttledNotifyCropMapChanged()` method that fires at most every ~30ms (~33fps) using `ContinuousClock` + `Duration.milliseconds(30)`. This replaces the per-frame synchronous `notifyCropMapChanged()` in all 4 live gesture methods:

- **`applyPanLive()`**: Replaced `notifyCropMapChanged()` with `throttledNotifyCropMapChanged()` in the synchronous path.
- **`applyPinchLive()`**: Replaced `notifyCropMapChanged()` with `throttledNotifyCropMapChanged()` in the synchronous path.
- **`scrollPanDelta()`**: Replaced `notifyCropMapChanged()` with `throttledNotifyCropMapChanged()` in the synchronous path.
- **`applyOverlayCropLive()`**: Replaced `notifyCropMapChanged()` with `throttledNotifyCropMapChanged()` in the synchronous path.
- **`scheduleScrollPanCommit()`**: Removed `notifyCropMapChanged()` — the throttled version in `scrollPanDelta()` handles notification.

### 2. `notifyCropMapChanged()` in gesture-end paths

Discovered that gesture-end paths were missing `notifyCropMapChanged()` after deferring the live calls. Added to ensure final state is always visible:

- **`endScrollPan()`**: Added `notifyCropMapChanged()` after `cropManager.endScrollPan()`.
- **`applyPinch(panelId:)`** (finish variant): Added `notifyCropMapChanged()` after `updatePanelPreview()`.
- **`finishOverlayCrop()`**: Added `notifyCropMapChanged()` after `updatePanelPreview()`.

### 3. Throttle scroll events at source (~60fps)

**File: `ScrollPanView.swift`**

Added `lastScrollTime` property to `ScrollCaptureView` and a guard in `scrollWheel(with:)` `case .changed:` that skips processing if less than ~16ms has elapsed since the last processed event (using `ContinuousClock` + `Duration.milliseconds(16)`).

## Why This Works

`panelRenderedImages` is an `@Observable` property. When the async render completes and writes `panelRenderedImages[panelId] = result` (PreviewManager.swift:102), SwiftUI re-evaluates any view that reads it (CollageEditorView.swift:72). So the main canvas image update happens regardless. `notifyCropMapChanged()` only needs to fire to also update `PanelCropEditor` (which reads `cropMap` at PanelCropEditor.swift:19, 35). By throttling it to ~33fps, we get live visual feedback during gestures without the per-frame overhead. By calling it in gesture-end paths, we ensure the final state is always visible.

## What Was NOT Changed

- Undo/redo — restores `cropMap` directly and calls `updatePanelPreview()`
- Existing tests — verify assembler calls after debounce sleep, unaffected

## Expected Outcome

During active pan/zoom gestures, `CollageEditorView.body` and `PanelCropEditor.body` re-evaluate at ~33fps instead of 60-120fps. Combined with the scroll throttle (~60fps max), this eliminates the lag that worsens when zoomed out while maintaining responsive live visual feedback.
