# Session 10 — 2026-05-13

### Batch 4: Gesture Redesign — Scroll Wheel Pan

**Goal:** Replace single-finger `DragGesture` for canvas pan with two-finger scroll via `NSViewRepresentable`, resolving conflict with sidebar `onMove` reorder.

**Bugs Discovered and Fixed:**

1. **`isOpaque` get-only on `NSView`** — `ScrollPanView.swift`. The plan specified `view.isOpaque = false`, but `NSView.isOpaque` is a get-only property on macOS (it's computed from `wantsLayer` + `layer?.isOpaque`). Removed the assignment — the overlay is transparent by default since no drawing is performed.

2. **`NSEvent.Phase.failed` not available** — `ScrollPanView.swift`. The `.failed` case doesn't exist in `NSEvent.Phase` on macOS (it's iOS-only). Removed from the `case .ended, .cancelled, .failed` switch, keeping only `.ended` and `.cancelled`.

3. **`[weak self]` on struct** — `CollageEditorView.swift`. The plan used `[weak self]` in closures capturing `self`, but `CollageEditorView` is a `struct`, not a `class`. `[weak self]` can only apply to reference types. Fixed by moving the scroll pan state machine (`scrollPanPanelId`, `scrollPanAccumulator`, `scrollCommitTimer`) into `CollageViewModel` (an `@Observable` class), and having the overlay closures capture `self` by value (struct semantics).

4. **`scrollSensitivity` type mismatch** — `ContentView.swift`. The plan used `Double` for `scrollSensitivity`, but `Slider` on macOS expects `CGFloat` for the binding value to match `NSControl` behavior. Changed to `CGFloat` throughout, with `UserDefaults` bridging via `Double(newValue)`.

5. **Hit test Y-axis inversion** — `ScrollPanView.swift:47`. `convert(event.locationInWindow, from: nil)` returns AppKit coordinates (bottom-left origin), but `scaledPanelFrames` are in SwiftUI coordinates (top-left origin). Without flipping, scrolling over the top panel hit-tested the bottom panel. Fixed with `location.y = bounds.height - location.y`.

6. **Choppy scroll — timer commits mid-gesture** — `CollageViewModel.swift`. The 150ms `DispatchWorkItem` timer fired during pauses in scrolling (fingers still on trackpad), calling `commitScrollPan()` which cleared `scrollPanPanelId`. The next `scrollPanDelta` returned early on the guard, freezing the preview. Fixed by splitting commit from cleanup: `scheduleScrollCommit()` only calls `cropManager.applyPan(finish: true)` to commit the crop, but no longer clears `scrollPanPanelId`. `endScrollPan()` (called on `.ended`) handles the cleanup.

7. **`endGesture()` clears base origin, breaking live pan** — `CropManager.swift`. After `commitScrollPan()` called `applyPan(finish: true)`, the `endGesture()` method cleared `gestureBaseOrigin`, so subsequent `applyPan(finish: false)` calls failed their guard. Fixed by calling `cropManager.beginPan(panelId: id)` immediately after commit to re-establish the base origin for continued panning.

**Production Code Changes:**
- `Views/ScrollPanView.swift` — New file: `NSViewRepresentable` with `ScrollCaptureView` subclass that overrides `scrollWheel(with:)`. Closure-based API (`onPanBegan`, `onPanChanged`, `onPanEnded`). Hit tests against `scaledPanelFrames` cache. Handles trackpad vs mouse wheel via `isDirectionInvertedFromDevice` and `hasPreciseScrollingDeltas`.
- `Views/CollageEditorView.swift` — Removed `DragGesture` + `dragPanelId`. Added `.overlay` with `ScrollPanView`.
- `ViewModel/CollageViewModel.swift` — Added `scrollSensitivity: CGFloat` (UserDefaults-persisted, default 1.0). Added scroll pan state machine (`beginScrollPan`, `scrollPanDelta`, `endScrollPan`) with 150ms commit timer.
- `Views/ContentView.swift` — Added Scroll Sensitivity slider (0.1–5.0) in Layout section.

**Current State:**
- Build: **SUCCEEDED** — zero errors, zero new warnings
- Tests: **67 tests pass** (unchanged)
- Scroll pan: **Working** (two-finger trackpad scroll pans image under cursor)
- Live preview: **Working** (image follows scroll in real time)
- Pinch zoom: **Unaffected** (still works via `MagnificationGesture`)
- Panel selection: **Unaffected** (click still selects)
- Sidebar reorder: **Unaffected** (no longer conflicts with pan)

**Learnings Documented:**
- `_agent_docs/learnings/scroll-wheel-pan-learnings.md`
