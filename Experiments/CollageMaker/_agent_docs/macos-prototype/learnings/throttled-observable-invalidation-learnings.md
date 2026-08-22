# Throttled @Observable Invalidation — Learnings 2026-06-02

**Purpose**: Capture learnings from session 77 — reducing per-frame SwiftUI re-evaluation during pan/zoom gestures while maintaining live visual feedback.

## What Worked

- **`ContinuousClock` + `Duration` for time-based throttling** — The idiomatic Swift approach for time-based logic. `ContinuousClock.now` returns an instant that survives sleep/wake, and `Duration.milliseconds(30)` is self-documenting. Replaces `mach_absolute_time()` which returns ticks (not nanoseconds) and requires `mach_timebase_info` conversion.

```swift
private var lastNotifyTime: ContinuousClock.Instant = ContinuousClock.now
private let notifyInterval: Duration = .milliseconds(30)

private func throttledNotify() {
    let now = ContinuousClock.now
    if now - lastNotifyTime >= notifyInterval {
        lastNotifyTime = now
        // ... notify ...
    }
}
```

- **Throttled notification pattern** — Bounding `@Observable` invalidation frequency (e.g., ~33fps) during high-rate gestures. Distinct from debouncing (which defers notification until after a quiet period) — throttling fires immediately on the first event, then skips events until the interval elapses. This gives live visual feedback during active gestures without per-frame overhead.

- **`diff-review` caught gesture-end notification gap** — When per-frame notification is deferred to a debounce callback, gesture-end paths that cancel the debounce (e.g., `finishOverlayCrop` calls `panelPreviewTask?.cancel()`) never fire the notification. The `diff-review` subagent identified 3 missing `notifyCropMapChanged()` calls in gesture-end paths that would have left `PanelCropEditor` showing stale crop data after the user released.

## What Didn't Work / Gaps

- **`mach_absolute_time()` returns ticks, not nanoseconds** — The raw `UInt64` from `mach_absolute_time()` is clock ticks, whose nanosecond equivalent depends on `mach_timebase_info`. Comparing against a hardcoded nanosecond threshold (like `16_000_000`) produces incorrect behavior — on Apple Silicon, the tick-to-nanos ratio varies. The scroll throttle with this bug dropped too many events, making scroll pan feel unresponsive.

- **Full deferral eliminated live feedback** — The initial approach of removing `notifyCropMapChanged()` entirely from the synchronous path and only calling it in the debounce callback meant the view never updated during active gestures. The user saw the same stale image until 150ms after the gesture stopped. Throttling (not deferral) was the right balance.

## What Was Confusing

- **Debounce vs. throttle for `@Observable` invalidation** — Debounce defers notification until after a quiet period (good for expensive renders). Throttle bounds notification frequency during active input (good for live visual feedback). The `cropMapVersion` counter needed throttling, not debouncing, because the view re-evaluation is what the user sees in real-time — the actual image rendering is already debounced separately.

## Skill Improvements

### Update `building-macos-apps` Skill — Performance Section

1. **Throttled `@Observable` invalidation pattern** — When a version counter triggers full view re-evaluation, throttle its increments during high-rate input:

```swift
private var lastNotifyTime: ContinuousClock.Instant = ContinuousClock.now
private let notifyInterval: Duration = .milliseconds(30) // ~33fps

private func throttledNotify() {
    let now = ContinuousClock.now
    if now - lastNotifyTime >= notifyInterval {
        lastNotifyTime = now
        versionCounter += 1
    }
}
```

2. **`mach_absolute_time()` gotcha** — Returns clock ticks, not nanoseconds. Do not compare against hardcoded nanosecond values. Use `ContinuousClock` + `Duration` instead.

3. **Gesture-end notification gap** — When deferring per-frame notification to a debounce callback, remember that gesture-end paths often cancel the debounce task. Add explicit notification to gesture-end methods (`onEnded`, `finish*`) to ensure final state is visible.

---
**Status**: Completed
**Follow-up**: Monitor gesture responsiveness with user feedback
