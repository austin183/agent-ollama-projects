# Gesture Rendering Performance — Eliminate Mid-Gesture CoreGraphics Work

**Date:** 2026-06-03
**Problem:** Panning and zooming a large image becomes choppy when zoomed out. Previous fixes (title layout cache, pinch throttle, PanelOverlay consolidation, panelFrames dedup) reduced SwiftUI body-evaluation cost but didn't address the CoreGraphics rendering bottleneck.

**Root cause:** Debounced preview renders fire ~every 150ms during sustained gestures. When zoomed out, `sourceRect` is large (many megapixels), so `context.draw(cropped, in: destRect)` with `.high` interpolation is expensive. The resulting `NSImage` assignment to `@MainActor` state interrupts the 33fps `cropMapVersion` notification cycle, causing visible frame drops.

---

## Status of Previous Plans

| Plan | Status |
|------|--------|
| `defer-cropmap-notify-scroll-throttle.md` | Implemented |
| `2026-05-31-preview-lag-fixes.md` | Implemented |
| `2026-05-31-editor-performance-plan.md` Phases 1-2 | Implemented |
| `2026-06-03-pan-zoom-performance.md` Phase 1 | Implemented — title cache in ViewModel |
| `2026-06-03-pan-zoom-performance.md` Phase 2 | Implemented — pinch throttle at 16ms |
| `2026-06-03-pan-zoom-performance.md` Phase 3 | Implemented — PanelOverlay consolidation |
| `2026-06-03-pan-zoom-performance.md` Phase 4 | Implemented — panelFrames dedup |
| `2026-06-02-preview-rendering-pure-cg.md` | Not started (separate concern) |

---

## Phase 1 — Cancel Debounced Preview Renders During Active Gestures (CRITICAL)

**Problem:** Three debounce tasks fire `updatePanelPreview()` 150ms after each gesture event:
- `scrollPanDelta()` (line 757-763) — scroll pan
- `applyPinchLive()` (line 675-681) — pinch zoom
- `applyOverlayCropLive()` (line 723-727) — panel editor drag

During sustained scrolling, each new scroll event cancels the previous debounce task and starts a new 150ms timer. This means a render completes roughly every 150ms during active gestures. The rendered `NSImage` is assigned to `panelRenderedImages[panelId]` on `@MainActor`, interrupting the swiftui body-evaluation cycle.

**Why it's wasteful:** The mid-gesture render produces an image that is immediately stale — the next scroll event has already changed the crop. The final post-gesture `updatePanelPreview()` (called in `onPanEnded`, CollageEditorView.swift:145) already produces the correct final image.

**Impact:** Highest. Eliminates the expensive CoreGraphics work from the gesture hot path entirely.

### 1A — Gate preview render on `isLiveGesturing`

**File: `ViewModel/CollageViewModel.swift`**

In `scrollPanDelta()`, cancel the debounce task without rescheduling during active gestures:

```swift
func scrollPanDelta(_ delta: CGSize) {
    cropManager.scrollPanAccumulateDelta(delta, sensitivity: scrollSensitivity)
    cropManager.scrollPanApply(
        panels: panels,
        images: images,
        panelAssignments: panelAssignments,
        finish: false
    )
    throttledNotifyCropMapChanged()

    previewDebounceTask?.cancel()
    previewDebounceTask = nil  // Do NOT reschedule during active gesture

    scheduleScrollPanCommit()
}
```

In `applyPinchLive()`, same pattern:

```swift
func applyPinchLive() {
    cropManager.applyPinch(panelId: nil, panels: panels, images: images, panelAssignments: panelAssignments, finish: false)
    throttledNotifyCropMapChanged()

    panelPreviewTask?.cancel()
    panelPreviewTask = nil  // Do NOT reschedule during active gesture
}
```

In `applyOverlayCropLive()`, same pattern:

```swift
func applyOverlayCropLive(panelId: UUID, sourceRect: CGRect) {
    guard let crop = cropMap[panelId] else { return }
    let newCrop = CropInfo(
        panelId: panelId,
        sourceRect: sourceRect,
        destinationRect: crop.destinationRect
    )
    cropManager.cropMap[panelId] = newCrop
    throttledNotifyCropMapChanged()

    panelPreviewTask?.cancel()
    panelPreviewTask = nil  // Do NOT reschedule during active gesture
}
```

**Key insight:** The post-gesture render is already wired:
- Scroll pan: `onPanEnded` closure (CollageEditorView.swift:144-146) calls `updatePanelPreview(panelId:)`
- Pinch: `onEnded` closure (CollageEditorView.swift:304) calls `applyPinch(panelId:)` which calls `updatePanelPreview(panelId:)`
- Overlay crop: `finishOverlayCrop()` (line 732) calls `updatePanelPreview(panelId:)`

These final renders produce the correct image with no mid-gesture overhead.

### 1B — Cancel in-flight render tasks on gesture begin

A render task from a previous gesture may still be executing on the background render queue when a new gesture begins. Its completion will assign a stale `NSImage` to `panelRenderedImages`, causing a visible flash.

**File: `ViewModel/CollageViewModel.swift`**

In the gesture begin methods, cancel any pending preview tasks:

```swift
func beginScrollPan(panelId: UUID) {
    previewDebounceTask?.cancel()
    previewDebounceTask = nil
    cropManager.beginScrollPan(panelId: panelId)
}

func beginPinch(panelId: UUID) {
    panelPreviewTask?.cancel()
    panelPreviewTask = nil
    cropManager.beginPinch(panelId: panelId)
}
```

**File: `Services/PreviewManager.swift`**

The `updatePanelPreview()` method already has generation counter guards (lines 95, 101) that discard stale results. No change needed — a render that started before gesture begin will complete with an old generation number and be discarded.

### 1C — Verification

**Manual test:**
1. Add a large image (4000+ px)
2. Zoom out so the image fills most of the panel
3. Scroll pan rapidly — should be smooth with no hitch
4. Release scroll — final render completes and image updates

**Log verification:** Run with `bash script/build_and_run.sh --telemetry` and filter for "Preview Assembly" — no preview renders should appear during active scrolling, only one render after gesture ends.

---

## Phase 2 — Lower Interpolation Quality for Preview Renders

**Problem:** `CollageAssembler` uses `context.interpolationQuality = .high` for all rendering, including preview images. The `.high` quality bilinear/trilinear filtering is significantly more expensive than `.medium` for large downsample operations (e.g., 3000x3000 sourceRect → 480x270 panel).

**Impact:** High. Preview images are transient — they exist only until the next render. Export images use a separate code path (`renderIntoContext`, line 127) which already uses `.high` and should keep it for quality.

### 2A — Use `.medium` interpolation for preview

**File: `Services/CollageAssembler.swift`**

In `renderPreviewIntoContext()` (line 158), change:

```swift
context.interpolationQuality = .medium  // Preview: speed over quality
```

In `renderPanel()` (line 349), change:

```swift
context.interpolationQuality = .medium  // Panel preview: speed over quality
```

**Keep `.high` for:**
- `renderIntoContext()` (line 127) — export path, quality matters
- `renderBackground()` — background image at canvas size, not a per-gesture hot path
- `renderTitle()` — text rendering, quality matters

### 2B — Verification

**Visual check:** Zoom out to show large area of image. Preview should look acceptable (`.medium` = bilinear, vs `.high` = trilinear). The difference is imperceptible at preview size (960x540 max). Export output is unchanged — export uses `.high`.

---

## Phase 3 — Eliminate Mid-Scroll Commit Timer

**Problem:** `scheduleScrollPanCommit()` (CollageViewModel.swift:768-781) schedules a `DispatchWorkItem` that fires 150ms after each scroll event. The timer calls `scrollPanApply(finish: true)` which calls `endGesture()` (clearing `gestureBaseOrigin`), then immediately calls `beginPan(panelId:)` to re-establish the base origin.

This mid-scroll commit:
1. Resets the gesture state machine mid-scroll, adding unnecessary state churn
2. Is unnecessary — the accumulated delta in `scrollPanAccumulator` is sufficient for correct pan behavior
3. Can race with the debounce task from Phase 1 if both fire at similar times

**Impact:** Low-moderate. Removes state churn and potential race conditions.

### 3A — Remove the commit timer

**File: `ViewModel/CollageViewModel.swift`**

Remove the `scrollCommitTimer` property (line 206) and the `scheduleScrollPanCommit()` method (lines 768-781). Remove the call to `scheduleScrollPanCommit()` from `scrollPanDelta()` (line 765).

Remove the timer cancellation from `endScrollPan()` (line 784):

```swift
func endScrollPan() {
    cropManager.endScrollPan()
    notifyCropMapChanged()
}
```

### 3B — Verify scroll pan behavior

The scroll pan flow without the commit timer:
1. `.began` → `beginScrollPan()` → sets `scrollPanPanelId`, resets accumulator, calls `beginPan()` to capture base origin
2. `.changed` → `scrollPanDelta()` → accumulates delta, applies to crop map, notifies
3. `.ended` → `endScrollPan()` → clears `scrollPanPanelId` and accumulator, calls `notifyCropMapChanged()`

The `beginPan()` in step 1 captures `gestureBaseOrigin` from the current crop. Step 2 applies accumulated delta relative to that origin. Step 3 cleans up. The `scrollPanAccumulator` in `CropManager` persists across the gesture, so there's no need to "commit" mid-scroll.

**Manual test:** Scroll pan in both directions, verify smooth behavior and correct final crop position.

---

## Phase 4 — Increase Crop Notification Throttle During Scroll

**Problem:** `throttledNotifyCropMapChanged()` fires at 30ms (~33fps) for all gesture types. For scroll pan, where the user is moving through image content rapidly, 60ms (~16fps) is visually indistinguishable but halves the SwiftUI body re-evaluation cost.

**Impact:** Low. Marginal reduction in body-evaluation frequency. Combined with Phase 1 (which eliminates the more expensive render work), this further reduces main thread pressure.

### 4A — Dual-interval throttle

**File: `ViewModel/CollageViewModel.swift`**

Replace the single throttle with two intervals:

```swift
private var lastCropNotifyTime: ContinuousClock.Instant = ContinuousClock.now
private let cropNotifyInterval: Duration = .milliseconds(30)
private let scrollCropNotifyInterval: Duration = .milliseconds(60)

private func throttledNotifyCropMapChanged(forScrollPan: Bool = false) {
    let interval = forScrollPan ? scrollCropNotifyInterval : cropNotifyInterval
    let now = ContinuousClock.now
    if now - lastCropNotifyTime >= interval {
        lastCropNotifyTime = now
        notifyCropMapChanged()
    }
}
```

Update `scrollPanDelta()` to pass the flag:

```swift
throttledNotifyCropMapChanged(forScrollPan: true)
```

Keep `applyPinchLive()` and `applyOverlayCropLive()` at the default 30ms:

```swift
throttledNotifyCropMapChanged()  // 30ms for pinch and overlay crop
```

### 4B — Verification

**Manual test:** Scroll pan should feel identical. Pinch zoom should feel identical (still 30ms).

---

## Summary

| Phase | Fix | Effort | Impact |
|-------|-----|--------|--------|
| 1 | Cancel debounced preview renders during gestures | Small (3 lines × 3 methods) | **CRITICAL** — eliminates expensive CG work from gesture hot path |
| 2 | `.medium` interpolation for preview | Small (2 lines) | **HIGH** — faster downsample for large sourceRect |
| 3 | Remove mid-scroll commit timer | Small (remove 15 lines) | Low-moderate — removes state churn |
| 4 | 60ms throttle for scroll pan | Small (add flag parameter) | Low — halves body re-evaluations during scroll |

**Combined impact:** Phase 1 eliminates the CoreGraphics rendering that causes main thread jank. Phase 2 makes any remaining renders faster. Phases 3-4 reduce the notification and state overhead. Together, panning/zooming zoomed-out images should be as smooth as zoomed-in images.

## Files Modified (Aggregate)

| File | Phases |
|------|--------|
| `ViewModel/CollageViewModel.swift` | 1, 3, 4 |
| `Services/CollageAssembler.swift` | 2 |

## Rollback Plan

Each phase is independently revertable:
- **Phase 1:** Restore the `Task.sleep(150ms)` + `updatePanelPreview()` pattern in each method
- **Phase 2:** Change `.medium` back to `.high` in two locations
- **Phase 3:** Restore `scrollCommitTimer` property and `scheduleScrollPanCommit()` method
- **Phase 4:** Remove `forScrollPan` parameter, revert to single interval

## Risks

| Risk | Mitigation |
|------|-----------|
| Phase 1: No live preview update during long pauses in gesture | If the user pauses mid-gesture for >0ms, the crop offset is still visible via `cropMapVersion` — the SwiftUI body re-renders with updated panel frames. The visual feedback is the panel frame moving, not the image content changing. |
| Phase 1: In-flight render from previous gesture overwrites current state | PreviewManager generation counter guards (lines 95, 101) discard stale results. |
| Phase 2: Preview quality noticeably worse | `.medium` = bilinear filtering, indistinguishable from `.high` at preview resolution (960x540). Export uses `.high` unchanged. |
| Phase 3: Scroll pan accumulates unbounded delta | `scrollPanAccumulator` is clamped by `applyPan()` which clamps `sourceRect` to image bounds. No unbounded accumulation. |
| Phase 3: Gesture origin drift over long scroll sessions | `beginScrollPan()` captures fresh `gestureBaseOrigin` from current crop. Accumulator resets to zero. Each new scroll gesture starts from correct state. |
| Phase 4: Scroll pan feels less responsive | 60ms = 16fps, which is the minimum for perceived smoothness in scrolling content. Users are moving through image content, not tracking precise position. |
