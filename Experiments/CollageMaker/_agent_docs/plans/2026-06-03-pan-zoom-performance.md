# Pan/Zoom Gesture Performance — Remaining Fixes

**Date:** 2026-06-03
**Problem:** Panning and zooming images in preview panels lags when zoomed out. Previous fixes (throttled cropMap notification at 30ms, scroll pan throttle at 16ms, debounced background properties, per-panel task tracking) reduced the problem but didn't eliminate it.

**Remaining root causes:**
1. CoreText title layout runs on every `body` evaluation — including during crop gestures
2. Pinch gesture fires unthrottled (200-500fps trackpad sample rate)
3. Three separate `ForEach` iterations over panels in the editor ZStack
4. `panelFrames` dictionary built twice per body evaluation

---

## Status of Previous Plans

| Plan | Status |
|------|--------|
| `defer-cropmap-notify-scroll-throttle.md` | Implemented — throttled notify at 30ms, scroll throttle at 16ms |
| `2026-05-31-preview-lag-fixes.md` Phase 1 | Implemented — `updatePreviewDebounced()` on color/gradient/opacity |
| `2026-05-31-preview-lag-fixes.md` Phase 3 | Implemented — per-panel task tracking in `PreviewManager` |
| `2026-05-31-editor-performance-plan.md` Phase 1 | Partially — `TitleStyle.LayoutKey` exists but title layout still runs in view body |
| `2026-05-31-editor-performance-plan.md` Phase 2 | Implemented — `titleStyle.didSet` guards for `isLayeredMode` |
| `2026-05-31-editor-performance-plan.md` Phase 3 | Skipped (tight title render) |
| `2026-05-31-editor-performance-plan.md` Phase 4 | Not started (scroll pan live offset) |
| `2026-05-31-editor-performance-plan.md` Phase 5 | Not started (deduplicate panelFrames) |
| `2026-06-02-preview-rendering-pure-cg.md` | Not started (NSBitmapImageRep → CGContext) |

---

## Phase 1 — Cache Title Layout in ViewModel (CRITICAL)

**Problem:** `CollageEditorView.titleCanvasFrame` and `titleMinWidth` (lines 23-53) run full CoreText layout on every `body` evaluation. This includes `TitleTextData.extract()` (enumerates NSAttributedString attributes) and `TitleBoundsCT.compute()` (creates CFAttributedString, CTFonts per run, CTFramesetter, calls `CTFramesetterSuggestFrameSizeWithConstraints`). These computed properties depend on `viewModel.titleAttrString` and `viewModel.titleStyle`, but `@Observable` has no path-based granularity — incrementing `cropMapVersion` causes the entire `body` to re-evaluate, including these expensive computed properties.

**Impact:** Highest. CoreText object creation runs 33x/sec during gestures for no visual benefit.

### 1A — Add cached title bounds and computed frame properties

**File: `ViewModel/CollageViewModel.swift`**

Add private cache storage and a lazy computation method:

```swift
/// Cached CoreText bounds — only depends on layout-affecting properties.
private var cachedTitleBounds: TitleBoundsCT? = nil
private var cachedTitleLayoutKey: TitleStyle.LayoutKey? = nil
/// Last titleAttrString for equality comparison (stored as string + attribute-aware check).
private var cachedTitleString: NSAttributedString?

private func ensureTitleBounds() -> TitleBoundsCT? {
    guard !titleAttrString.string.isEmpty else {
        cachedTitleBounds = nil
        return nil
    }
    let currentKey = titleStyle.layoutKey
    if let cachedStr = cachedTitleString, cachedStr.isEqual(titleAttrString),
       cachedTitleLayoutKey == currentKey {
        return cachedTitleBounds
    }
    cachedTitleString = titleAttrString
    let textData = TitleTextData.extract(from: titleAttrString)
    let bounds = TitleBoundsCT.compute(textData: textData, style: titleStyle)
    cachedTitleBounds = bounds
    cachedTitleLayoutKey = currentKey
    return bounds
}
```

Add two public computed properties that use the cache:

```swift
var cachedTitleCanvasFrame: CGRect? {
    guard let bounds = ensureTitleBounds() else { return nil }
    let canvasSize = CanvasConfig.defaultCanvasSize
    let boundingBox = bounds.boundingBox(canvasWidth: canvasSize.width)
    let drawWidth = titleStyle.effectiveWidth(canvasWidth: canvasSize.width)
    let anchorX = titleStyle.positionX * canvasSize.width
    let drawX = anchorX - drawWidth / 2
    let anchorYcg = canvasSize.height - titleStyle.positionY * canvasSize.height
    let baselineY = anchorYcg - boundingBox.height
    let textTop = baselineY + boundingBox.origin.y
    return CGRect(x: drawX, y: textTop - 12, width: drawWidth, height: boundingBox.height + 24)
}

var cachedTitleMinWidth: CGFloat {
    guard let bounds = ensureTitleBounds() else { return 0 }
    let canvasSize = CanvasConfig.defaultCanvasSize
    return bounds.minNaturalWidth(canvasWidth: canvasSize.width)
}
```

**Key insight:** `cachedTitleCanvasFrame` is a computed property. The CoreText work is gated by `ensureTitleBounds()` which caches the `TitleBoundsCT` result. Position changes during drag recompute the canvas rect (cheap math) but reuse the cached bounds (no CoreText). Layout changes invalidate the bounds cache and trigger fresh CoreText layout.

### 1B — Cache invalidation strategy

**No `didSet` changes needed.** The caching is entirely internal to the computed properties. `ensureTitleBounds()` checks `titleStyle.layoutKey` and `titleAttrString.isEqual()` on every read — if neither changed, the cached `TitleBoundsCT` is returned.

**Position changes during drag:** `positionX`/`positionY` are NOT in `LayoutKey`, so a position change does NOT invalidate the bounds cache. The `cachedTitleCanvasFrame` computed property still re-reads `titleStyle.positionX`/`positionY` and recomputes the CGRect (cheap math, no CoreText).

**`@Observable` tracking:** The stored properties `cachedTitleBounds`, `cachedTitleLayoutKey`, and `cachedTitleString` are read by `ensureTitleBounds()`, establishing `@Observable` dependencies. During crop gestures, none of these stored properties change — the cache hits and returns early. During title content/style changes, `cachedTitleBounds` is assigned, triggering view invalidation (which is correct, the frame needs updating).

### 1C — Lazy initialization

The cache is lazily populated on first read of `cachedTitleCanvasFrame` or `cachedTitleMinWidth`. No explicit initialization needed in `init` — the first body evaluation after the view appears will populate the cache.

### 1D — Replace computed properties in CollageEditorView

**File: `Views/CollageEditorView.swift`**

Replace the CoreText-heavy computed properties (lines 23-53) with thin delegators:

```swift
// Remove lines 23-53 (titleCanvasFrame, titleMinWidth computed properties with CoreText)
// Replace with:
private var titleCanvasFrame: CGRect? {
    viewModel.cachedTitleCanvasFrame
}

private var titleMinWidth: CGFloat {
    viewModel.cachedTitleMinWidth
}
```

The view's computed properties delegate to the ViewModel's computed properties. The ViewModel's `ensureTitleBounds()` caches the CoreText result, so during crop gestures the only work is cheap CGRect math. The `@Observable` dependency chain is: view reads `viewModel.cachedTitleCanvasFrame` → reads `titleStyle` (stored, tracked) + `cachedTitleBounds` (stored, tracked) → cache hit returns bounds → CGRect math.

### 1E — Tests

**New tests in `CollageMakerTests/CollageViewModelTests.swift`:**

- `cachedTitleCanvasFrameIsNullForEmptyTitle` — empty `titleAttrString`; assert `cachedTitleCanvasFrame == nil`
- `cachedTitleCanvasFramePopulatedAfterTitleSet` — set title; assert non-nil frame
- `cachedTitleCanvasFrameUpdatesOnTitleChange` — change title string; assert frame updated
- `cachedTitleCanvasFrameUpdatesOnFontSizeChange` — change `fontSize`; assert frame updated
- `cachedTitleCanvasFrameUpdatesOnWidthChange` — change `width`; assert frame updated
- `cachedTitleCanvasFrameUpdatesOnPositionChange` — change `positionX`; assert frame updated (position affects canvas rect, not bounds cache)
- `cachedTitleBoundsNotRecomputedForPositionChange` — read `cachedTitleBounds` reference, change `positionX`, read again; assert same reference (CoreText not re-run)
- `cachedTitleBoundsRecomputedOnFontSizeChange` — change `fontSize`; assert new bounds reference
- `cachedTitleMinWidthUpdatesOnTitleChange` — change title string; assert minWidth updated
- `cachedTitleMinWidthUnchangedForPositionChange` — change `positionX`; assert minWidth unchanged

**Verification:** Build + test pass. Manual: scroll pan and pinch gestures feel smooth with no hitch. Instruments: no CoreText allocation during crop gestures.

---

## Phase 2 — Throttle Pinch Gesture

**Problem:** `MagnificationGesture().onChanged` (CollageEditorView.swift:357-368) fires at full trackpad sample rate (~200-500fps). Each invocation calls `applyPinchLive()` which does dictionary lookups, `panels.first(where:)` linear scan, and Task creation/cancellation. Compare to scroll pan which is throttled to 16ms at the source (`ScrollPanView.swift:53-57`).

**Impact:** High. Unnecessary Task churn and crop math at hundreds of fps.

### 2A — Add throttle to GestureCoordinator

**File: `Views/GestureCoordinator.swift`**

Add throttle state to the coordinator (which already tracks `pinchPanelId`):

```swift
@MainActor
final class GestureCoordinator: ObservableObject {
    // ... existing properties ...

    private var lastPinchTime: ContinuousClock.Instant = .now
    private let pinchThrottleInterval: Duration = .milliseconds(16)

    /// Returns true if the pinch event should be processed (not throttled away).
    func shouldProcessPinch() -> Bool {
        let now = ContinuousClock.now
        if now - lastPinchTime >= pinchThrottleInterval {
            lastPinchTime = now
            return true
        }
        return false
    }
}
```

### 2B — Apply throttle in the gesture handler

**File: `Views/CollageEditorView.swift`**

In the `MagnificationGesture().onChanged` closure (line 358-368), guard the `applyPinchLive()` call:

```swift
.onChanged { value in
    if gestureCoordinator.pinchPanelId == nil, let id = viewModel.selectedPanelId {
        gestureCoordinator.pinchPanelId = id
        viewModel.beginPinch(panelId: id)
        viewModel.undoManager.beginUndoGrouping()
        viewModel.isLiveGesturing = true
    }
    if gestureCoordinator.pinchPanelId != nil {
        viewModel.pinch(magnification: value)
        if gestureCoordinator.shouldProcessPinch() {
            viewModel.applyPinchLive()
        }
    }
}
```

**Note:** `viewModel.pinch(magnification:)` still runs every frame (it just stores a CGFloat in CropManager). Only `applyPinchLive()` — which does crop math, notification, and Task churn — is throttled. This way the final magnification value is always the latest, but the expensive side effects are throttled.

### 2C — Tests

No new unit tests needed — the throttle is a simple clock guard. The existing pinch tests in `CropManagerTests.swift` exercise the crop math. Manual verification: pinch zoom feels smooth, no visible difference from before (16ms = 60fps, which is the display refresh rate).

**Verification:** Build + test pass. Manual: pinch zoom is smooth.

---

## Phase 3 — Consolidate Panel ForEach Loops

**Problem:** The editor ZStack iterates over `viewModel.panels` three times:
1. Line 76-85: Rendered panel images (layered mode)
2. Line 101-124: Panel hit areas with context menus
3. Line 178-195: Selection highlight

Each `ForEach` has overhead: identity tracking, view creation, and diffing. For a 10-panel layout, this is 30 view instances created per body evaluation.

**Impact:** Moderate. Combined with the other fixes, this reduces per-body-evaluation work.

### 3A — Create a PanelView wrapper

**File: `Views/CollageEditorView.swift`**

Replace the three separate `ForEach` blocks with a single `ForEach` that builds a `PanelOverlay` view containing the image, hit area, and selection highlight:

```swift
ForEach(viewModel.panels) { panel in
    PanelOverlay(
        panel: panel,
        scaledFrame: panelFrames[panel.id],
        viewModel: viewModel,
        gestureCoordinator: gestureCoordinator
    )
}
```

### 3B — Extract PanelOverlay view

**File: `Views/CollageEditorView.swift`** (new private struct at bottom, after `PanelHitArea`)

```swift
private struct PanelOverlay: View {
    let panel: ImagePanel
    let scaledFrame: CGRect?
    let viewModel: CollageViewModel
    let gestureCoordinator: GestureCoordinator

    var body: some View {
        Group {
            if viewModel.isLayeredMode,
               let renderedImage = viewModel.panelRenderedImages[panel.id],
               let frame = scaledFrame {
                Image(nsImage: renderedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }

            if let frame = scaledFrame {
                let imageIndex = viewModel.getEffectiveImageIndex(for: panel.id)
                PanelHitArea(
                    panel: panel,
                    frame: frame,
                    viewModel: viewModel,
                    imageIndex: imageIndex
                )
                .accessibilityLabel("Image panel")
                .accessibilityAddTraits(viewModel.selectedPanelId == panel.id ? [.isSelected] : [])
                .contextMenu {
                    Button("Reset Crop") {
                        viewModel.resetCrop(panelId: panel.id)
                    }
                    Divider()
                    if let idx = imageIndex {
                        Button("Remove Image", role: .destructive) {
                            viewModel.removeImage(at: idx)
                        }
                    }
                }
            }

            if viewModel.selectedPanelId == panel.id, let frame = scaledFrame {
                Rectangle()
                    .fill(Color.clear)
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
    }
}
```

Remove the three existing `ForEach` blocks (lines 76-85, 101-124, 178-195) and the standalone selection highlight block.

### 3C — Verification

**Verification:** Build + test pass. Manual: panel interaction, selection, context menus, and image rendering all work identically.

---

## Phase 4 — Deduplicate panelFrames Construction

**Problem:** `panelFrames` is built inside the `GeometryReader` closure (line 62-64) and rebuilt again in `panelAt()` (line 405-408). Each construction is O(N) with `canvasToPreviewFrame` per panel.

**Impact:** Low-moderate. The `panelAt()` call happens during tap and drag gestures, not during the 33fps crop notification cycle, so the main `body`-level duplication is the primary concern.

### 4A — Pass panelFrames to panelAt

**File: `Views/CollageEditorView.swift`**

Change `panelAt` to accept the pre-computed dictionary:

```swift
private func panelAt(frames panelFrames: [UUID: CGRect], location: CGPoint) -> UUID? {
    if let id = CropManager.hitTestPanel(at: location, panelFrames: panelFrames),
       let panel = viewModel.panels.first(where: { $0.id == id }),
       let frame = panelFrames[id] {
        logger.debug("panelAt: idx=\(panel.imageIndex) frame=\(DebugHelpers.rectStr(frame)) tap=\(DebugHelpers.pointStr(location)) hits=true")
        return id
    }
    return nil
}
```

Update all callers to pass `panelFrames`:
- Line 327: `panelAt(frames: panelFrames, location: value.startLocation)`
- Line 335: `panelAt(frames: panelFrames, location: value.location)`
- Line 347: `panelAt(frames: panelFrames, location: value.location)`
- Line 384: `panelAt(frames: panelFrames, location: location)`

**Note:** The `panelAt` calls inside the `onTapGesture` closure (line 384) don't have access to `panelFrames` from the `GeometryReader` closure. For this call site, we need to either:
- Keep the inline `reduce` in `onTapGesture`, or
- Extract `panelAt` to accept `previewSize` and rebuild the frames (current behavior for this one call)

**Decision:** The `onTapGesture` call is infrequent (one per tap, not per-frame). Keep its current inline construction. Only optimize the drag gesture calls (lines 327, 335, 347) which fire per-frame.

### 4B — Verification

**Verification:** Build + test pass. Manual: panel selection, drag-and-drop swap work identically.

---

## Summary

| Phase | Fix | Effort | Impact |
|-------|-----|--------|--------|
| 1 | Cache title layout in ViewModel | Medium (add cache storage + computed props, replace view computed props) | **CRITICAL** — eliminates CoreText from gesture hot path |
| 2 | Throttle pinch gesture | Small (add throttle to coordinator, guard in onChanged) | **HIGH** — reduces Task churn from 200-500fps to 60fps |
| 3 | Consolidate ForEach loops | Medium (extract PanelOverlay, remove 3 loops) | Moderate — fewer view instances per body eval |
| 4 | Deduplicate panelFrames | Small (pass dict to panelAt) | Low-moderate — eliminates O(N) rebuild during drag |

**Combined impact:** Phase 1 alone eliminates the most expensive per-frame work (CoreText layout with CFAttributedString/CTFramesetter creation). Phase 2 reduces the input rate feeding that pipeline. Phases 3-4 reduce the per-body-evaluation cost for the remaining 33fps notifications.

## Files Modified (Aggregate)

| File | Phases |
|------|--------|
| `ViewModel/CollageViewModel.swift` | 1 |
| `Views/CollageEditorView.swift` | 1, 2, 3, 4 |
| `Views/GestureCoordinator.swift` | 2 |
| `CollageMakerTests/CollageViewModelTests.swift` | 1 |

## Rollback Plan

Each phase is independently revertable:
- **Phase 1:** Remove `cachedTitleBounds`, `cachedTitleLayoutKey`, `cachedTitleString`, `ensureTitleBounds()`, `cachedTitleCanvasFrame`, `cachedTitleMinWidth` from ViewModel; restore original CoreText computed properties in the view
- **Phase 2:** Remove `shouldProcessPinch()` from GestureCoordinator; remove guard in `onChanged`
- **Phase 3:** Remove `PanelOverlay`; restore three separate `ForEach` blocks
- **Phase 4:** Revert `panelAt` signature; restore inline `reduce`

## Risks

| Risk | Mitigation |
|------|------------|
| Phase 1: Title frame stale after style change | Cache invalidated by `layoutKey` comparison in `ensureTitleBounds()`. Any layout-affecting change produces a new key. |
| Phase 1: `cachedTitleString` retains large NSAttributedString | Only one string retained at a time (replaced on change). Negligible memory. |
| Phase 1: `TitleBoundsCT` retains CTFramesetter | `TitleBoundsCT` stores a `CTFramesetter` (CoreFoundation object). One retained at a time. Freed when replaced. |
| Phase 2: Pinch feels less responsive | 16ms throttle = 60fps, matching display rate. Magnification value still updates every frame (only side effects are throttled). |
| Phase 3: Context menu or accessibility breaks | `PanelOverlay` preserves the exact same modifiers. Test context menu and VoiceOver manually. |
