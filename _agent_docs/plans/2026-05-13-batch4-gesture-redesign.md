# Batch 4 — Gesture Redesign (Refined Plan)

## Date
2026-05-13

## Source Documents
- `_agent_docs/plans/2026-05-12-scale-analysis-fixes.md` (original Batch 4)
- `building-swiftui-macos-apps/REFERENCES/scroll-views.md`
- `building-swiftui-macos-apps/REFERENCES/swiftui-gestures.md`
- `building-swiftui-macos-apps/REFERENCES/nsviarepresentable.md`
- `swiftui-patterns/SKILL.md`

## Decisions
- Canvas pan: replace single-finger `DragGesture` with two-finger scroll via `scrollWheel(with:)` on an `NSView` overlay
- Closure-based API (not Coordinator) — thin bridge, `CollageEditorView` owns the state machine
- Reuse `scaledPanelFrames` cache — no duplicate coordinate conversion in the AppKit layer
- Commit strategy: 150ms `DispatchWorkItem` timer after last `.changed` or on `.ended` — handles trackpad momentum
- Sensitivity slider in sidebar — lets us tune trackpad vs mouse wheel empirically
- `dragPanelId` renamed to `scrollPanPanelId` for clarity

---

## #11: ScrollPanView — NSViewRepresentable Overlay

**Priority:** P2
**New file:** `CollageMaker/CollageMaker/Views/ScrollPanView.swift`

**Rationale:** Single-finger `DragGesture` conflicts with sidebar `onMove` reorder. Two-finger scroll is the macOS convention for panning content and uses a distinct input channel (`NSEventType.scrollWheel`).

**Key design choices informed by skills:**

- **`event.isDirectionInvertedFromDevice`** — trackpad returns `false` (natural finger motion), mouse returns `true` (system-inverted). Negating unconditionally breaks mouse wheel direction.
- **`event.hasPreciseScrollingDeltas`** — trackpad sends continuous small deltas (1-5 units). Mouse wheel sends discrete 120-unit clicks. Without scaling, mouse wheel pan would be 20-100x too fast.
- **`isOpaque = false` + `wantsLayer = true`** — transparent overlay that doesn't block underlying SwiftUI gestures.
- **Reuses `scaledPanelFrames`** — hit testing uses the precomputed preview-space frames from `CollageEditorView`, avoiding duplicate `canvasToPreviewFrame` logic.
- **Closure-based API** — no Coordinator class. `CollageEditorView` owns the state machine and calls into the ViewModel.

```swift
import AppKit
import SwiftUI

struct ScrollPanView: NSViewRepresentable {
    let scaledPanelFrames: [UUID: CGRect]
    let onPanBegan: (UUID) -> Bool
    let onPanChanged: (CGSize) -> Void
    let onPanEnded: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ScrollCaptureView()
        view.wantsLayer = true
        view.isOpaque = false
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let view = nsView as! ScrollCaptureView
        view.scaledPanelFrames = scaledPanelFrames
        view.onPanBegan = onPanBegan
        view.onPanChanged = onPanChanged
        view.onPanEnded = onPanEnded
    }

    class ScrollCaptureView: NSView {
        var scaledPanelFrames: [UUID: CGRect] = [:]
        var onPanBegan: (UUID) -> Bool = { _ in false }
        var onPanChanged: (CGSize) -> Void = { _ in }
        var onPanEnded: () -> Void = {}
        private var activePanelId: UUID?

        override func scrollWheel(with event: NSEvent) {
            guard event.type == .scrollWheel else {
                super.scrollWheel(with: event)
                return
            }

            let deltaX = event.isDirectionInvertedFromDevice
                ? event.scrollingDeltaX : -event.scrollingDeltaX
            let deltaY = event.isDirectionInvertedFromDevice
                ? event.scrollingDeltaY : -event.scrollingDeltaY

            let baseMultiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1.0 : 10.0

            switch event.phase {
            case .began:
                if activePanelId == nil {
                    let location = convert(event.locationInWindow, from: nil)
                    if let id = hitTest(at: location), onPanBegan(id) {
                        activePanelId = id
                    }
                }
            case .changed:
                if activePanelId != nil {
                    onPanChanged(CGSize(width: deltaX * baseMultiplier, height: deltaY * baseMultiplier))
                }
            case .ended, .cancelled, .failed:
                if activePanelId != nil {
                    onPanEnded()
                }
                activePanelId = nil
            default:
                break
            }
        }

        private func hitTest(at location: CGPoint) -> UUID? {
            for (id, frame) in scaledPanelFrames where frame.contains(location) {
                return id
            }
            return nil
        }
    }
}
```

---

## #12: CollageEditorView Integration

**Priority:** P2
**File:** `CollageMaker/CollageMaker/Views/CollageEditorView.swift`

### Changes

1. **Remove** the `DragGesture(minimumDistance: 5)` `.simultaneousGesture` block (current lines 75-93).

2. **Rename** `dragPanelId` → `scrollPanPanelId`.

3. **Add** scroll pan accumulator state and commit timer:
   ```swift
   @State private var scrollPanAccumulator: CGSize = .zero
   private var scrollCommitWorkItem: DispatchWorkItem?
   ```

4. **Add** `.overlay` with `ScrollPanView` on the `ZStack`, after the existing gesture modifiers and before `.onChange`.

5. **Add** helper methods for scroll pan handling.

### Integration code

```swift
// Inside GeometryReader, on the ZStack:
.overlay {
    ScrollPanView(
        scaledPanelFrames: scaledPanelFrames,
        onPanBegan: { [weak self] id in
            self?.scrollPanPanelId = id
            self?.viewModel.beginPan(panelId: id)
            self?.scrollPanAccumulator = .zero
            return true
        },
        onPanChanged: { [weak self] delta in
            self?.applyScrollDelta(delta)
        },
        onPanEnded: { [weak self] in
            self?.scheduleScrollCommit()
        }
    )
}
```

```swift
private func applyScrollDelta(_ delta: CGSize) {
    guard scrollPanPanelId != nil else { return }
    scrollPanAccumulator.width += delta.width * viewModel.scrollSensitivity
    scrollPanAccumulator.height += delta.height * viewModel.scrollSensitivity
    viewModel.pan(by: scrollPanAccumulator)
    viewModel.applyPanLive()
    scheduleScrollCommit()
}

private func scheduleScrollCommit() {
    scrollCommitWorkItem?.cancel()
    scrollCommitWorkItem = DispatchWorkItem { [weak self] in
        self?.commitScrollPan()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: scrollCommitWorkItem!)
}

private func commitScrollPan() {
    guard let id = scrollPanPanelId else { return }
    viewModel.applyPan(panelId: id)
    scrollPanPanelId = nil
    scrollPanAccumulator = .zero
    scrollCommitWorkItem?.cancel()
    scrollCommitWorkItem = nil
}
```

### Why `DispatchWorkItem` instead of `Timer`

The skills flag `Timer` in `@State` as a known pitfall — `Timer` is a reference type that gets deallocated during SwiftUI struct recreation. `DispatchWorkItem` is cancellable, doesn't require stored reference types, and is the same pattern already used in `CollageViewModel.applyPanLive()` for the `previewDebounce`.

### Commit timing rationale

Trackpad momentum produces `.changed` events after the user lifts their fingers. The 150ms timer fires after the last `.changed` event, so we commit once momentum has settled. The timer is also re-armed on every `.changed`, so a sustained scroll won't commit prematurely. On `.ended`, the timer is started as a fallback in case there are no more `.changed` events.

---

## #13: Scroll Sensitivity Setting

**Priority:** P2
**Files:** `CollageViewModel.swift`, `ContentView.swift`

Add a `scrollSensitivity` property to `CollageViewModel` with UserDefaults persistence, and a slider in the sidebar Layout section to tune it at runtime.

### CollageViewModel.swift

Add after the `gutter` property:

```swift
var scrollSensitivity: Double {
    get {
        if UserDefaults.standard.object(forKey: "scrollSensitivity") != nil {
            return UserDefaults.standard.double(forKey: "scrollSensitivity")
        }
        return 1.0
    }
    set {
        UserDefaults.standard.set(newValue, forKey: "scrollSensitivity")
    }
}
```

Default: `1.0`. Range: `0.1`–`5.0`.

### ContentView.swift

Add inside the Layout `Section`, below the Gutter slider:

```swift
VStack(alignment: .leading) {
    HStack {
        Text("Scroll Sensitivity")
        Spacer()
        Text(String(format: "%.1f", viewModel.scrollSensitivity))
            .foregroundStyle(.secondary)
    }
    .font(.caption)
    Slider(value: $viewModel.scrollSensitivity, in: 0.1...5.0, step: 0.1)
}
```

This lets us empirically tune what feels right for both trackpad and mouse wheel without code changes. Once we land on a good default, the slider can be removed or moved to Settings.

---

## Interaction Matrix (Post-Change)

| Input | Handler | Action |
|-------|---------|--------|
| Two-finger trackpad scroll | `ScrollPanView.scrollWheel` | Pan crop viewport |
| Trackpad pinch | `MagnificationGesture` | Zoom selected panel |
| Option + scroll wheel | `MagnificationGesture` | Zoom selected panel |
| Mouse wheel | `ScrollPanView.scrollWheel` (×10 multiplier) | Pan crop viewport |
| Single click | `onTapGesture` | Select/deselect panel |

No conflicts — each input mode is handled by a distinct system.

---

## Files Summary

| File | Action | Risk |
|------|--------|------|
| `ScrollPanView.swift` | **New** — NSViewRepresentable overlay | Medium (AppKit bridge) |
| `CollageEditorView.swift` | Remove `DragGesture`, add overlay + rename state | Low |
| `CollageViewModel.swift` | Add `scrollSensitivity` property | None |
| `ContentView.swift` | Add sensitivity slider in Layout section | None |

## Testing Checklist

- [ ] Two-finger scroll pans the image under cursor
- [ ] Pan direction matches finger motion (scroll down → image moves down)
- [ ] Mouse wheel pans at reasonable speed (adjust via sensitivity slider)
- [ ] Pinch zoom still works (unaffected by changes)
- [ ] Single-click panel selection still works
- [ ] Sidebar reorder still works (no longer conflicts with pan)
- [ ] Pan commits after scroll momentum settles (150ms timer)
- [ ] Scrolling over empty canvas area does nothing (no panel hit)
- [ ] Sensitivity slider persists across launches
- [ ] Build: zero errors, zero warnings
