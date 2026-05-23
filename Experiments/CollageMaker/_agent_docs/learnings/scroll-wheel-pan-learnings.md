# Scroll Wheel Pan — Learnings

**Date:** 2026-05-13
**Purpose:** Document learnings from replacing `DragGesture` with `NSViewRepresentable` scroll wheel capture for canvas pan.

## What Worked

- **Closure-based API over Coordinator** — Passing closures directly through `NSViewRepresentable.updateNSView` avoided the Coordinator boilerplate. The `ScrollCaptureView` class stores closures as properties and updates them each frame. No retain cycle issues since closures capture `[weak self]` on the `@Observable` class.
- **`scaledPanelFrames` cache reuse** — The hit test in `ScrollCaptureView` uses the precomputed SwiftUI-space frames from `CollageEditorView`, avoiding duplicate `canvasToPreviewFrame` logic in the AppKit layer.
- **`DispatchWorkItem` for commit timer** — Avoids the `Timer`-in-`@State` pitfall (deallocation during struct recreation). Same pattern already used in `CollageViewModel.applyPanLive()` for `previewDebounce`.
- **State machine in `@Observable` class** — Moving `scrollPanPanelId`, `scrollPanAccumulator`, and `scrollCommitTimer` from the view struct to `CollageViewModel` avoided the `[weak self]`-on-struct error entirely.

## What Didn't Work / Gaps

- **`isOpaque` is get-only on `NSView`** — The plan specified `view.isOpaque = false` for a transparent overlay. On macOS, `NSView.isOpaque` is computed from `wantsLayer` + `layer?.isOpaque`, not settable. The overlay is transparent by default since no drawing is performed.
- **`NSEvent.Phase.failed` is iOS-only** — The `.failed` case doesn't exist in `NSEvent.Phase` on macOS. Only `.began`, `.changed`, `.ended`, `.cancelled`, and `.mayBegin` are available.
- **`[weak self]` cannot apply to structs** — `CollageEditorView` is a `struct`, so `[weak self]` in closures produces a compile error. The fix is to move timer/state to a class (`CollageViewModel`) or capture `self` by value (struct semantics, no weak needed).
- **`scrollSensitivity` needed `CGFloat`, not `Double`** — macOS `Slider` binds to `CGFloat` for `NSControl` compatibility. `UserDefaults` stores as `Double`, requiring bridging in the property wrapper.

## What Was Confusing

- **AppKit vs SwiftUI coordinate systems in `NSViewRepresentable`** — `convert(event.locationInWindow, from: nil)` returns AppKit coordinates (bottom-left origin), but the `scaledPanelFrames` cache is in SwiftUI coordinates (top-left origin). Without `location.y = bounds.height - location.y`, the hit test targets the wrong panel vertically. This is a third coordinate system bridge point in the app (after `canvasToPreviewFrame` Y-flip and CoreGraphics Y-flip).
- **`endGesture()` clearing `gestureBaseOrigin` mid-scroll** — After the 150ms commit timer fires, `cropManager.applyPan(finish: true)` calls `endGesture()` which clears `gestureBaseOrigin`. The next `scrollPanDelta` call to `applyPan(finish: false)` then fails its guard because `gestureBaseOrigin` is `nil`. The fix is to immediately call `cropManager.beginPan(panelId:)` after commit to re-establish the base origin, so continued scrolling works seamlessly.

## Skill Improvements

### `building-swiftui-macos-apps/SKILL.md` — Common Pitfalls
Add to Gestures section:
- **`[weak self]` on struct produces compile error** — Only applies to class types. For struct views, either capture `self` by value (no weak needed) or move timer/state to a class.
- **`NSEvent.Phase` differs from iOS** — `.failed` is iOS-only. macOS phases: `.began`, `.changed`, `.ended`, `.cancelled`, `.mayBegin`.
- **`NSView.isOpaque` is get-only on macOS** — Cannot be set directly. Computed from `wantsLayer` + `layer?.isOpaque`.

### `building-swiftui-macos-apps/REFERENCES/nsviarepresentable.md`
Add note about AppKit/SwiftUI coordinate mismatch in hit testing:
- `convert(event.locationInWindow, from: nil)` returns bottom-left origin
- SwiftUI frames are top-left origin
- Flip Y with `location.y = bounds.height - location.y` before hit testing against SwiftUI frames

### `building-swiftui-macos-apps/REFERENCES/swiftui-gestures.md`
Add note about `CropManager.endGesture()` clearing state mid-gesture when commit timer fires during sustained scroll. Solution: re-call `beginPan(panelId:)` after commit to re-establish base origin.

## Next Steps

- Test with mouse wheel (not just trackpad) to verify ×10 multiplier feels right
- Consider moving sensitivity slider to Settings scene once default is tuned
- Add telemetry for scroll pan actions (`log` in `beginScrollPan`, `endScrollPan`)

---
**Status**: Closed
**Follow-up**: Batch 5 (next improvement cycle)
