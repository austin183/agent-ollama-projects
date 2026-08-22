# Animation FPS Consistency & Responsiveness

**Date:** 2026-06-21
**Problem:** Animation frame rates are inconsistent across actions. Zoom runs at ~60fps while pan runs at ~16fps. Title font size slider has a 150ms lag before the new size snaps in instantly rather than animating with the drag. Overlay crop editor runs at ~20fps, also inconsistent.

**Research references:**
- `_agent_docs/research/performance/swiftui-scroll-performance-jacobs-tech-tavern.md` — Jacob's Tech Tavern SwiftUI scroll performance patterns
- `_agent_docs/research/performance/wwdc2025-306.txt` — WWDC 2025 Session 306: SwiftUI performance with Instruments

**Relevant learnings:**
- `swiftui-text-vs-cg-font-metrics-learnings.md` — SwiftUI `Text` cannot match CG-rendered font metrics pixel-for-pixel
- `throttled-observable-invalidation-learnings.md` — throttle vs. debounce for live feedback
- `gesture-render-cancellation-learnings.md` — throttled background render patterns
- `observable-body-re-evaluation-cascade.md` — struct isolation to prevent re-render cascades
- `per-panel-incremental-rendering-learnings.md` — async rendering state races
- `property-debounce-strategy-learnings.md` — continuous vs discrete property debounce

**Relevant prior plans:**
| Plan | Status |
|------|--------|
| `defer-cropmap-notify-scroll-throttle.md` | Implemented — throttled notify at 30ms, scroll throttle at 16ms |
| `2026-06-03-pan-zoom-performance.md` | Implemented — cached title layout, panel frame cache, pinch throttle |
| `2026-06-03-gesture-rendering-performance.md` | Implemented — throttled background renders, gesture-end cleanup |
| `2026-05-31-editor-performance-plan.md` | Partially implemented — various phases |

---

## Architecture vs. Recommendations

### What the research says

From WWDC 306:
1. **Keep view bodies fast** — anything running in `body` that misses the frame deadline causes hitches
2. **Minimize unnecessary updates** — design data flow so only necessary view bodies update when data changes
3. **Granular dependencies** — each view should depend only on the specific data it needs, not broad collections

From Jacob's Tech Tavern:
1. **Minimize dependencies** — views should have as little `@State`/`@Observable` as possible
2. **Background processing** — offload heavy work (image transforms, data parsing) to background threads
3. **Profile before optimizing** — verify with Instruments

### Current architecture alignment

**Good:**
- CoreGraphics rendering runs on background threads via `Task.detached` in `PreviewManager`
- Per-panel incremental rendering avoids full-canvas re-composites
- `PanelFrameCache` moves O(N) coordinate transforms out of the body path
- `GestureCoordinator` uses local `@State`, not `@Observable`, to avoid triggering body re-renders
- Debouncer centralizes debounce logic with per-ID cancellation

**Misaligned:**
- Inconsistent render throttle intervals across gesture types (60ms, 50ms, 150ms vs 16ms)
- Title font size uses 150ms debounce with no intermediate visual feedback
- `cropMap` is a single `@Observable` property — any crop mutation triggers all observers
- `isLiveGesturing` toggles in the main ZStack, triggering full canvas body re-evaluation

---

## Root Causes

### Zoom FPS >> Pan FPS

| Gesture | Event Throttle | Render Throttle | Effective FPS |
|---------|---------------|-----------------|---------------|
| Pinch Zoom | 16ms (`GestureCoordinator.shouldProcessPinch`) | 0ms debounce | ~60 fps |
| Scroll Pan | 16ms (`ScrollCaptureView`) | **60ms** (`scrollRenderInterval`) | ~16 fps |
| Overlay Crop | unthrottled | **50ms** (`overlayRenderInterval`) | ~20 fps |
| Pan (live) | unthrottled | **150ms** debounce | ~6 fps |

The 60ms `scrollRenderInterval` at `CollageViewModel.swift:771` is 4x slower than pinch. The 150ms `panPreview` debounce at line 670 is even worse — only updating the rendered image 150ms after the gesture stops changing.

### Title Font Size Lag

The slider calls `setTitleFontSize()` which:
1. Mutates `titleStyle.fontSize` immediately (the slider value updates)
2. Debounces the visual render at 150ms (`CollageViewModel.swift:947`)
3. The debounced callback increments `titleImageVersion` and spawns an async NSImage render
4. 150ms later, the new image snaps in

There is no intermediate visual feedback — the user drags, waits, and sees the final size appear.

### Unnecessary View Body Re-renders

**`cropMap` broad dependency:** `PanelCropEditor` reads `viewModel.cropMap[panel.id]` at line 32 of its body. Since `cropMap` is a single `@Observable` property on `CropManager`, any crop mutation (including canvas gestures on other panels) triggers this view to re-evaluate.

**`isLiveGesturing` in main ZStack:** Toggles on every gesture begin/end. Because it's an `@Observable` property used inside the main canvas `ZStack`, each toggle triggers the entire canvas body re-evaluation including `GeometryReader`, `computePanelFrames`, and all child views.

---

## Phase 1 — FPS Consistency (Quick Wins)

**Goal:** Align all gesture-driven rendering to ~60fps (16ms interval).

**Effort:** ~10 min | **Impact:** High — eliminates perceptible FPS disparity

### 1A — Scroll pan render interval: 60ms -> 16ms

**File: `CollageViewModel.swift` line 771**

```swift
private let scrollRenderInterval: Duration = .milliseconds(60)
```
Change to:
```swift
private let scrollRenderInterval: Duration = .milliseconds(16)
```

**Rationale:** 60ms = ~16fps. Pinch zoom runs at ~60fps. Aligning eliminates the perceptible FPS gap between scroll pan and pinch zoom.

**Risk:** 4x more CoreGraphics panel renders per second during scroll pan. The per-panel `renderPanel` is already async on a background thread via `Task.detached` in `PreviewManager`, so main thread impact should be minimal. Monitor CPU with Instruments if needed.

### 1B — Pan preview debounce: 150ms -> 16ms

**File: `CollageViewModel.swift` line 670**

```swift
debouncer.debounce(id: "panPreview", delay: .milliseconds(150)) { [weak self] in
```
Change to:
```swift
debouncer.debounce(id: "panPreview", delay: .milliseconds(16)) { [weak self] in
```

**Rationale:** 150ms debounce means the rendered image only updates 150ms after pan gestures stop changing. At 16ms, the image updates ~60fps during active panning, matching pinch zoom responsiveness.

**Note:** This is a debounce (not a throttle), so it fires once 16ms after the last gesture event. Combined with the immediate `cropMap` mutation (which updates the SwiftUI frame overlays), this provides both instant frame updates and near-instant image updates.

### 1C — Overlay crop render interval: 50ms -> 16ms

**File: `CollageViewModel.swift` line 732**

```swift
private let overlayRenderInterval: Duration = .milliseconds(50)
```
Change to:
```swift
private let overlayRenderInterval: Duration = .milliseconds(16)
```

**Rationale:** 50ms = ~20fps. Aligning to 16ms brings overlay crop (sidebar drag/resize) to ~60fps, consistent with all other gesture interactions.

### Verification

Build and run. Perform each gesture on the same panel and compare smoothness:
1. Scroll-wheel pan — should match pinch zoom smoothness
2. Pinch zoom — baseline, should be unchanged
3. Overlay crop drag (sidebar) — should feel smoother
4. Direct pan (if applicable) — should update faster

---

## Phase 2 — Title Font Size Live Preview

**Goal:** Show instant visual feedback when dragging the font size slider, eliminating the 150ms lag + snap.

**Effort:** ~1 hr | **Impact:** High — eliminates font size lag

### Approach: SwiftUI Text overlay during drag

During slider drag, render a lightweight `Text` view at the title's position on the canvas. When the debounced NSImage render completes, swap back to the accurate CG-rendered image.

**Tradeoff:** Per `swiftui-text-vs-cg-font-metrics-learnings.md`, SwiftUI `Text` cannot match CG-rendered font metrics pixel-for-pixel. The font size will be approximately correct (growing/shrinking with the slider), but ascent/descent/leading may differ slightly. This is acceptable for a live preview — the final image is always the accurate CG render.

### 2A — Add `isAdjustingFontSize` state

**File: `CollageViewModel.swift`**

Add a new `@Observable` property near the other title-related state:
```swift
var isAdjustingFontSize: Bool = false
```

### 2B — Modify `setTitleFontSize` to track drag state

**File: `CollageViewModel.swift` lines 943-951**

Current code:
```swift
func setTitleFontSize(_ size: CGFloat) {
    let oldValue = titleManager.titleStyle.fontSize
    titleManager.titleStyle.fontSize = size
    applyTitleChange(at: \.fontSize, oldValue: oldValue, actionName: "Change Font Size") {
        self.debouncer.debounce(id: "fontSize", delay: .milliseconds(150)) { [weak self] in
            guard let self else { return }
            self.titleManager.updateImage(updater: self)
        }
    }
}
```

Change to:
```swift
func setTitleFontSize(_ size: CGFloat) {
    let oldValue = titleManager.titleStyle.fontSize
    titleManager.titleStyle.fontSize = size
    isAdjustingFontSize = true
    applyTitleChange(at: \.fontSize, oldValue: oldValue, actionName: "Change Font Size") {
        self.debouncer.debounce(id: "fontSize", delay: .milliseconds(150)) { [weak self] in
            guard let self else { return }
            self.isAdjustingFontSize = false
            self.titleManager.updateImage(updater: self)
        }
    }
}
```

**Behavior:** `isAdjustingFontSize` is set to `true` immediately when the slider moves. After the 150ms debounce fires and the NSImage render is scheduled, it's set to `false`. During the `true` window, the Text overlay is visible. Once the NSImage render completes, the overlay is hidden.

### 2C — Create `TitleLivePreviewView`

**New file: `Views/TitleLivePreviewView.swift`**

A SwiftUI view that renders the title text using `Text` with the current `titleStyle`:

```swift
import SwiftUI

struct TitleLivePreviewView: View {
    let title: String
    let titleStyle: TitleStyle
    let frame: CGRect

    var body: some View {
        VStack(spacing: 0) {
            if titleStyle.showBackground {
                Rectangle()
                    .fill(Color(titleStyle.backgroundColor))
            }
            Text(title)
                .font(customFont)
                .foregroundStyle(Color(titleStyle.fontColor))
                .multilineTextAlignment(textAlignment)
                .frame(width: frame.width, alignment: textAlignment)
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .allowsHitTesting(false)
    }

    private var customFont: Font {
        if titleStyle.fontFamily.isEmpty {
            return .system(size: titleStyle.fontSize, weight: .bold)
        }
        return .custom(titleStyle.fontFamily, size: titleStyle.fontSize)
    }

    private var textAlignment: Alignment {
        switch titleStyle.alignment {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        @unknown default: return .center
        }
    }
}
```

**Key design decisions:**
- `.allowsHitTesting(false)` — the overlay should not intercept gestures meant for the canvas
- Uses `frame.width` from the scaled preview frame, not the canvas frame
- Background rectangle respects `showBackground` flag
- Text alignment maps `NSTextAlignment` to SwiftUI `Alignment`

### 2D — Add overlay to canvas ZStack

**File: `CollageEditorView.swift`**

Add the live preview to the ZStack, positioned above `PanelsOverlayView` and below `TitleInteractionOverlay`:

After line 41 (`PanelsOverlayView(...)`), add:
```swift
if viewModel.isAdjustingFontSize,
   let scaled = titleFrame,
   !viewModel.title.isEmpty {
    TitleLivePreviewView(
        title: viewModel.title,
        titleStyle: viewModel.titleStyle,
        frame: scaled
    )
}
```

**Placement rationale:** Above `PanelsOverlayView` so it overlays the canvas, below `TitleInteractionOverlay` so the orange handles remain on top during adjustment.

### 2E — Handle non-layered mode

In non-layered mode, the title is baked into `previewImage` (the full composite). The Text overlay will appear on top of the composite image, which is fine — it provides live feedback during the drag, and after the debounced render completes, the new composite image replaces the old one with the Text overlay hidden.

No special handling needed — the overlay works in both modes.

### Verification

1. Add a title to the collage
2. Drag the font size slider slowly — text should grow/shrink instantly on the canvas
3. Release the slider — after ~150ms, the accurate NSImage replaces the Text overlay
4. Verify the final rendered image matches expectations (font family, color, background, alignment)
5. Test with reduced motion enabled — should work the same (no animation modifiers involved)

---

## Phase 3 — Reduce Unnecessary Re-renders

**Goal:** Reduce `@Observable`-driven body re-evaluations that don't contribute to visible changes.

**Effort:** ~45 min | **Impact:** Medium — fewer wasted CPU cycles during gestures

### 3A — Isolate `isLiveGesturing` from canvas ZStack

**Problem:** `isLiveGesturing` toggles on every gesture begin/end (~60fps during active gestures). Because it's an `@Observable` property of `CollageViewModel`, each toggle invalidates `CollageEditorView.body`, re-evaluating the entire `GeometryReader` + `ZStack` tree.

**Current code (`TitleInteractionOverlay.swift`):**
```swift
var body: some View {
    if !isLiveGesturing {
        // ... orange handles ...
    }
}
```

This conditional `if` causes SwiftUI to add/remove the overlay from the hierarchy on each toggle, triggering layout passes.

**Solution:** Keep the overlay in the hierarchy and use `.opacity()` + `.allowsHitTesting()` instead:

```swift
var body: some View {
    Rectangle()
        .fill(Color.clear)
        .stroke(Color.orange, lineWidth: 1.5)
        .frame(width: scaledFrame.width, height: scaledFrame.height)
        .position(x: scaledFrame.midX, y: scaledFrame.midY)
        .contentShape(Rectangle())
        .help("Drag to reposition title")
    // ... resize handles ...
    .opacity(isLiveGesturing ? 0 : 1)
    .allowsHitTesting(!isLiveGesturing)
}
```

**Rationale:** The view stays in the hierarchy, so SwiftUI doesn't need to add/remove it. The `.opacity(0)` makes it invisible, and `.allowsHitTesting(false)` prevents it from intercepting gestures. This follows the pattern from `observable-body-re-evaluation-cascade.md` — keeping the view in the hierarchy avoids sibling re-evaluation.

### 3B — Localize `cropMap` dependency in `PanelCropEditor`

**Problem:** `PanelCropEditor` reads `viewModel.cropMap[panel.id]` at line 32 of its body. Since `cropMap` is a single `@Observable` property on `CropManager`, any crop mutation (including canvas gestures on other panels) triggers this view to re-evaluate.

**Solution:** Add a per-panel crop version counter to `CropManager` that only increments when that specific panel's crop changes.

**File: `CropManager.swift`**

Add a version tracking dictionary:
```swift
private var cropVersions: [UUID: Int] = [:]
```

Create a helper to update crop info that also increments the version:
```swift
private func setCropInfo(_ info: CropInfo, panelId: UUID) {
    cropMap[panelId] = info
    cropVersions[panelId, default: 0] += 1
}
```

Update all places in `CropManager` that write to `cropMap` to use `setCropInfo` instead. There are 4 write sites:
1. `applyPan` line 184: `cropMap[id] = CropInfo(...)` 
2. `applyPinch` line 275: `cropMap[id] = CropInfo(...)`
3. `resetCrop` line 294: `cropMap[panelId] = CropInfo(...)`
4. `computeInitialCrops` line 77: `cropMap[panel.id] = CropInfo(...)`
5. `computeCropsFromSaliency` line 107: `cropMap[panel.id] = CropInfo(...)`
6. `applyCropsBySlot` line 128: `cropMap[panel.id] = CropInfo(...)`

Add a getter for the version:
```swift
func getCropVersion(panelId: UUID) -> Int {
    cropVersions[panelId, default: 0]
}
```

**File: `CollageViewModel.swift`**

Expose the version through the ViewModel:
```swift
func getCropVersion(for panelId: UUID) -> Int {
    cropManager.getCropVersion(panelId: panelId)
}
```

**File: `PanelCropEditor.swift`**

Replace the broad `cropMap` dependency with a version-gated local `@State`:

Add local state:
```swift
@State private var localCrop: CropInfo?
@State private var cropVersion: Int = 0
```

Use `.task(id:)` to sync when the version changes:
```swift
.task(id: cropVersion) {
    localCrop = viewModel.cropMap[panel.id]
}
```

And in the body, read from `localCrop` instead of `viewModel.cropMap[panel.id]`. Add a periodic version check using `.task(id:)` on the panel ID:

Actually, a simpler approach: use a computed property on the view that reads the version, and only refresh the local state when it changes:

```swift
var body: some View {
    let version = viewModel.getCropVersion(for: panel.id)

    Group {
        // ... existing content, using localCrop instead of crop ...
    }
    .task(id: version) {
        localCrop = viewModel.cropMap[panel.id]
    }
}
```

Wait — this still reads `viewModel.cropMap` in the body. The cleaner approach is to use `.onChange`:

```swift
@State private var localCrop: CropInfo?
@State private var lastVersion: Int = 0

var body: some View {
    // Don't read cropMap in body — use localCrop
    let crop = localCrop

    VStack { ... }
    .task(id: panel.id) {
        // Initial load
        localCrop = viewModel.cropMap[panel.id]
        lastVersion = viewModel.getCropVersion(for: panel.id)
    }
    .onChange(of: viewModel.getCropVersion(for: panel.id)) { newVersion in
        guard newVersion != lastVersion else { return }
        lastVersion = newVersion
        localCrop = viewModel.cropMap[panel.id]
    }
}
```

**Rationale:** The `PanelCropEditor` body no longer reads `cropMap` directly. It only reads the version counter (an `Int`), and uses `.onChange` to update local `@State` when the version changes. Since `.onChange` only fires for this panel's version, gestures on other panels won't trigger re-evaluations.

**Note:** `onChange` will still cause the `PanelCropEditor.body` to re-evaluate when checking the version, but the check is a cheap `Int` comparison, and the body content uses `localCrop` which won't have changed for other-panel gestures.

### Verification

After Phase 3 changes, use SwiftUI Instruments (Xcode 26+):
1. Profile with the SwiftUI template
2. Perform a pinch zoom on one panel while the sidebar shows a different panel's editor
3. Check that `PanelCropEditor.body` does NOT re-evaluate during the pinch
4. Check that `CollageEditorView.body` re-evaluations are reduced when gestures start/stop (due to 3A)

---

## Summary

| Phase | Effort | Impact | Files Changed |
|-------|--------|--------|---------------|
| 1. FPS Consistency | ~10 min | High — eliminates perceptible FPS disparity | `CollageViewModel.swift` (3 constants) |
| 2. Font Size Preview | ~1 hr | High — eliminates 150ms font size lag | `CollageViewModel.swift`, new `TitleLivePreviewView.swift`, `CollageEditorView.swift` |
| 3. Reduce Re-renders | ~45 min | Medium — fewer wasted CPU cycles | `TitleInteractionOverlay.swift`, `CropManager.swift`, `CollageViewModel.swift`, `PanelCropEditor.swift` |

### After all phases: verify with Instruments

Run the SwiftUI Instruments template and check:
- **Long View Body Updates** — no orange/red bars during gestures
- **Cause & Effect Graph** — dependency chains are localized (no broad `cropMap` cascades)
- **Time Profiler** — CPU samples during gestures are in rendering tasks, not view body evaluation

---

**Status:** Proposed
**Follow-up:** Execute Phase 1, then Phase 2, then Phase 3, verifying after each phase
