# Gesture Render Cancellation and State Cleanup — Learnings 2026-06-03

**Purpose**: Capture learnings from session 81 — eliminating mid-gesture CoreGraphics renders and fixing the resulting state machine and visual feedback gaps.

## What Worked

- **Throttled background render replaces debounce** — The original plan eliminated all mid-gesture renders by canceling debounce tasks and setting to `nil`. This worked for performance but eliminated live visual feedback in non-layered mode (where `previewImage` is a static composite that doesn't reflect crop changes). The fix: throttle background renders at the same cadence as crop notifications (60ms for scroll pan, 50ms for overlay crop) instead of debouncing. Throttle fires immediately on first eligible event, giving responsive feedback without the 150ms debounce delay.

```swift
private var lastScrollRenderTime: ContinuousClock.Instant = ContinuousClock.now
private let scrollRenderInterval: Duration = .milliseconds(60)

private func throttledScrollPanRender() {
    let now = ContinuousClock.now
    guard now - lastScrollRenderTime >= scrollRenderInterval,
          let panelId = cropManager.scrollPanActivePanelId else { return }
    lastScrollRenderTime = now
    previewDebounceTask?.cancel()
    previewDebounceTask = Task.detached { [weak self, panelId] in
        guard let self else { return }
        await MainActor.run { self.updatePanelPreview(panelId: panelId) }
    }
}
```

- **High-frequency gesture throttle** — Overlay crop drag fires at ~60fps via `DragGesture.onChanged`. With "cancel previous task + schedule new render" pattern, every render gets cancelled because the next drag event arrives before the render completes. Throttling the render cadence (50ms) at the ViewModel level ensures renders actually complete and provide visual feedback.

- **`diff-review` caught dual-responsibility state cleanup** — The removed `scheduleScrollPanCommit()` timer did double duty: committing accumulated delta AND calling `scrollPanApply(finish: true)` which called `endGesture()`. Removing the timer exposed that `gestureActivePanelId` was never cleared at gesture end, causing subsequent pinch to target a stale panel.

## What Didn't Work / Gaps

- **Non-layered mode feedback loss** — The plan assumed `cropMapVersion`-driven panel frame updates would provide visual feedback during gestures. But in non-layered mode, the `previewImage` is a static composite — crop changes don't affect its pixel content. `cropMapVersion` only affects panel frame overlays (visible in layered mode). The fix required understanding the rendering mode distinction.

- **Gesture-end render task cancellation** — `endScrollPan()` didn't cancel `previewDebounceTask`. A pending scroll pan render could fire after gesture end and overwrite a subsequent gesture's result. Different gesture types use different task variables (`previewDebounceTask` vs `panelPreviewTask`), so they don't cancel each other automatically.

## What Was Confusing

- **Debounce vs throttle for live feedback** — Debounce (150ms sleep) defers render until after a quiet period — good for final quality, bad for live feedback. Throttle (fire every N ms) gives responsive feedback during active input. The choice depends on whether the user needs to see intermediate state changes during the gesture. For scroll pan (moving through content), 16fps throttle is sufficient. For pinch zoom (precise framing), render on every throttled gesture event.

## Skill Improvements

### Update `building-macos-apps` Skill — Performance Notes

1. **Dual-responsibility state cleanup** — When a timer or background task performs both state commits AND cleanup (e.g., calling `endGesture()`), removing it for performance requires moving cleanup to the explicit gesture-end path. Audit what the timer did beyond its primary purpose.

2. **Throttled background render for live feedback** — When eliminating debounced mid-gesture renders breaks visual feedback, replace with throttled background renders at the same cadence as crop notifications. Use `Task.detached` + `await MainActor.run` for offloading rendering while safely mutating `@Observable` state.

3. **High-frequency gesture throttle** — When a gesture fires at ~60fps (e.g., `DragGesture.onChanged`), the "cancel previous task + schedule new render" pattern cancels every render. Throttle the render cadence at the ViewModel level instead.

---
**Status**: Completed
**Follow-up**: Monitor gesture responsiveness with user feedback
