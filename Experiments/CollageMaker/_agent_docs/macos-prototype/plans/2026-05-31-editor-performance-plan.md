# Collage Editor Performance Plan

**Goal:** Make live editing feel instant when working with large images and frequent gesture events (title drag, font resize, scroll pan). Strategy: render faster and more precisely, never skip frames.

**Date:** 2026-05-31

---

## Baseline Problems

| # | Problem | Location | Impact |
|---|---------|----------|--------|
| A | `cachedTitleMetrics` invalidated on every `titleStyle` change, including position-only drags | `CollageViewModel.swift:95` | Full text layout (string copy, font enumeration, `FontMerger.merge`, CoreText `boundingRect`) ~60x/sec during title drag |
| B | `renderTitle()` allocates a 1920x1080 bitmap (2M pixels) to draw a title that's typically ~500x60 | `CollageAssembler.swift:517-528` | Every title render fills 2M pixels, ~99% transparent |
| C | `titleAttrString.didSet` calls `updatePreview()` unconditionally, compositing all panels + title at 960x540 — even in layered mode where `previewImage` is never displayed | `CollageViewModel.swift:85` | Every keystroke triggers full composite |
| D | Scroll pan fires `notifyCropMapChanged()` on every event, invalidating SwiftUI view tree; CG render is debounced 150ms, creating visible lag | `CollageViewModel.swift:687` | Stale image during scroll, unnecessary view re-evaluations |
| E | `panelFrames` computed in body and recomputed in `panelAt()` | `CollageEditorView.swift:57-59, 400-402` | Duplicate work per body evaluation |

---

## Phase 1 — TitleMetrics Cache Key

**Problem addressed:** A

**Why first:** Smallest blast radius. Purely internal to `TitleStyle` + `CollageViewModel`. No rendering or view changes.

### 1A — Tests

**New file: `CollageMakerTests/TitleStyleLayoutKeyTests.swift`**

- `layoutKeyEqualWhenOnlyPositionXDiffers` — create two `TitleStyle` values differing only in `positionX`; assert equal layout keys
- `layoutKeyEqualWhenOnlyPositionYDiffers` — same for `positionY`
- `layoutKeyEqualWhenOnlyFontColorDiffers` — color doesn't affect layout
- `layoutKeyEqualWhenOnlyBackgroundColorDiffers`
- `layoutKeyEqualWhenOnlyShowBackgroundDiffers`
- `layoutKeyDiffersWhenFontSizeChanges` — 48 vs 56
- `layoutKeyDiffersWhenFontFamilyChanges` — "" vs "Helvetica"
- `layoutKeyDiffersWhenWidthChanges` — 0 vs 800
- `layoutKeyDiffersWhenAlignmentChanges` — .center vs .left

**New file: `CollageMakerTests/TitleMetricsCacheTests.swift`**

- `titleMetricsReturnsNilForEmptyString` — set empty `titleAttrString`; assert `titleMetrics == nil`
- `titleMetricsCachesResultOnSecondAccess` — set title; access `titleMetrics` twice; verify same underlying `preparedString`
- `titleMetricsInvalidatedByTitleStringChange` — change `titleAttrString`; assert new `preparedString`
- `titleMetricsInvalidatedByFontSizeChange` — change `titleStyle.fontSize`; assert new `preparedString`
- `titleMetricsInvalidatedByFontFamilyChange` — change `titleStyle.fontFamily`; assert new `preparedString`
- `titleMetricsInvalidatedByWidthChange` — change `titleStyle.width`; assert new `preparedString` (width affects `effectiveWidth` which affects `boundingBox`)
- `titleMetricsNOTInvalidatedByPositionXChange` — change `titleStyle.positionX`; assert `preparedString` is unchanged
- `titleMetricsNOTInvalidatedByPositionYChange` — change `titleStyle.positionY`; assert `preparedString` is unchanged
- `titleMetricsNOTInvalidatedByFontColorChange` — change `titleStyle.fontColor`; assert `preparedString` is unchanged

### 1B — Changes

**`Models/TitleStyle.swift`**

Add a `LayoutKey` struct — a value type containing only the properties that affect text layout:

```
struct LayoutKey: Hashable {
    let fontFamily: String
    let fontSize: CGFloat
    let width: CGFloat
    let alignment: NSTextAlignment
}
```

Add `var layoutKey: LayoutKey { get }` computed property on `TitleStyle`.

**`ViewModel/CollageViewModel.swift`**

Change `cachedTitleMetrics` from `TitleMetrics?` to `(metrics: TitleMetrics, layoutKey: TitleStyle.LayoutKey, titleHash: Int)?`.

In `titleMetrics` computed property:
- Compute `layoutKey` from current `titleStyle` and `titleHash` from `titleAttrString`
- Only create new `TitleMetrics` when key or hash differs from cache

In `titleStyle.didSet`:
- Only set `cachedTitleMetrics = nil` when `oldValue.layoutKey != titleStyle.layoutKey`

In `titleAttrString.didSet`:
- Only set `cachedTitleMetrics = nil` when the string content actually changed (compare `oldValue.string != titleAttrString.string`)

---

## Phase 2 — Title Setter Side Effects

**Problem addressed:** C (partial), and establishes regression safety for Phase 1 cache changes

**Why second:** Validates the `titleStyle.didSet` / `titleAttrString.didSet` dispatch logic before we add more branches.

### 2A — Tests

**New tests in `CollageMakerTests/CollageViewModelTests.swift`**

Use `TrackingAssembler` (existing mock pattern from `ExportFlowTests.swift`) to verify method calls.

- `titleAttrStringSetterCallsUpdatePreview` — set `titleAttrString`; verify `trackingAssembler.previewCalls` increased
- `titleStyleSetterNotDraggingCallsUpdatePreview` — set `titleStyle` with `isDraggingTitle == false`; verify `previewCalls` increased
- `titleStyleSetterDraggingCallsUpdateTitleImageLive` — set `titleStyle` with `isDraggingTitle == true`; verify `titleRenderCalls` increased (after debounce)
- `titleStyleSetterDraggingSkipsUndo` — set `titleStyle` with `isDraggingTitle == true`; verify `undoManager` was NOT called (or check that the action was not registered)
- `finishTitleDragRendersImmediately` — call `finishTitleDrag()`; verify title render was called
- `setTitleFontFamilyCallsUpdateTitleImageLive` — call `setTitleFontFamily(_:)`; verify title render
- `setTitleFontSizeCallsUpdateTitleImageDebounced` — call `setTitleFontSize(_:)`; verify title render after debounce

### 2B — Changes

**`ViewModel/CollageViewModel.swift`**

In `titleAttrString.didSet`:
- Guard `updatePreview()` with `!isLayeredMode`
- When `isLayeredMode` is true, call `updateTitleImage()` instead (only the title component needs updating)

In `titleStyle.didSet` when `!isDraggingTitle`:
- Guard `updatePreview()` with `!isLayeredMode`
- When `isLayeredMode` is true, call `updateTitleImage()` instead

---

## Phase 3 — Tight Title Render - Skipped

**Problem addressed:** B

**Why third:** Renders faster by reducing pixel count. Depends on Phase 1 (cheap `TitleMetrics` during drag) to compute bounding box efficiently.

### 3A — Tests

**New tests in `CollageAssemblerTests.swift`**

- `renderTitleReturnsNilForEmptyString` — pass empty `NSAttributedString`; assert `nil`
- `renderTitleReturnsNonNilImage` — pass valid title; assert non-nil `NSImage`
- `renderTitleImageHasCorrectSize` — verify output image size matches canvas size
- `renderTitleDrawsTextAtPosition` — render with known `positionX`/`positionY`; sample pixels to verify text is present at expected region
- `renderTitleDrawsBackgroundWhenEnabled` — `showBackground = true`; verify background pixels are non-transparent
- `renderTitleSkipsBackgroundWhenDisabled` — `showBackground = false`; verify no background pixels
- `renderTitleTightReturnsSmallerImage` — call new `renderTitleTight`; assert image size is smaller than full canvas
- `renderTitleTightContainsTextPixels` — verify the tight image contains non-transparent pixels (the text)

**New tests in `PreviewManagerTests.swift`**

- `updateTitleImageTightSetsTitleAndFrame` — verify `titleImage` and `titleFrame` are both set
- `updateTitleImageTightEmptyReturnsNil` — empty string; verify `titleImage == nil`

### 3B — Changes

**`Services/CollageAssembler.swift`**

Add `renderTitleTight(titleAttrString:titleStyle:canvasWidth:) async -> (image: NSImage?, frame: CGRect?)`:
- Compute `TitleMetrics` to get `boundingBox` and `minNaturalWidth`
- Determine the tight bounding box in canvas coordinates (using `positionX`, `positionY`, `effectiveWidth`)
- Create `NSBitmapImageRep` at the tight box size (add padding, e.g., 12pt on each side like the existing background padding)
- Set up `CGContext`, translate origin so the title draws at (0,0) in the tight context
- Call `drawTitle` logic (or extract a `drawTitle(into:metrics:drawRect:)` variant that takes the draw rect as parameter)
- Return the tight `NSImage` and the canvas-space `CGRect`

**`Services/CollageAssembly` protocol**

Add `renderTitleTight(...) async -> (image: NSImage?, frame: CGRect?)`

**`PreviewManager.swift`**

Add `titleFrame: CGRect?` property. Add `updateTitleImageTight(...)` that calls `assembler.renderTitleTight`, sets both `titleImage` and `titleFrame`.

**`ViewModel/CollageViewModel.swift`**

Add `titleFrame: CGRect?` passthrough to `PreviewManager`. Add `updateTitleImageTight()` and `updateTitleImageTightLive()` (debounced variant). In `titleStyle.didSet` when `isDraggingTitle`, call `updateTitleImageTightLive()` instead of `updateTitleImageLive()`.

**`Views/CollageEditorView.swift`**

In layered mode, replace:
```swift
Image(nsImage: titleImg)
    .resizable()
    .aspectRatio(contentMode: .fit)
    .frame(width: geometry.size.width, height: geometry.size.height)
```
with:
```swift
if let titleImg = viewModel.titleImage,
   let tf = viewModel.titleFrame,
   let scaled = canvasToPreviewFrame(tf, in: geometry.size) {
    Image(nsImage: titleImg)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: scaled.width, height: scaled.height)
        .position(x: scaled.midX, y: scaled.midY)
}
```

---

## Phase 4 — Scroll Pan Live Offset

**Problem addressed:** D

**Why fourth:** Largest architectural change. Replaces crop-mutation-per-event with SwiftUI offset + commit-on-end. Independent of title changes.

### 4A — Tests

**New tests in `CropManagerTests.swift`**

- `beginScrollPanSetsPanelIdAndResetsAccumulator` — verify `scrollPanPanelId`, `scrollPanAccumulator == .zero`
- `scrollPanAccumulateDeltaAppliesSensitivity` — accumulate known delta; verify `scrollPanAccumulatorValue == delta * sensitivity`
- `scrollPanAccumulateDeltaIgnoresWhenNoPanel` — call without `beginScrollPan`; verify accumulator unchanged
- `scrollPanAccumulateDeltaAddsUp` — two calls; verify accumulator is sum
- `scrollPanApplyUpdatesCropMap` — apply with test panels/images; verify `cropMap` entry has updated `sourceRect.origin`
- `scrollPanApplyFinishFalsePreservesGestureState` — apply with `finish: false`; verify `gestureActivePanelId` is still set
- `scrollPanApplyFinishTrueEndsGesture` — apply with `finish: true`; verify `gestureActivePanelId == nil`
- `endScrollPanResetsState` — verify `scrollPanPanelId == nil`, `scrollPanAccumulator == .zero`
- `scrollPanFullLifecycle` — begin → accumulate → accumulate → apply → end; verify crop changed correctly
- `scrollPanClampsToImageBounds` — accumulate large delta; verify `sourceRect` doesn't exceed image bounds

**New tests in `CollageViewModelTests.swift`**

- `beginScrollPanDelegatesToCropManager` — verify `cropManager` state after call
- `scrollPanDeltaSetsLiveOffset` — verify `liveScrollPanOffset` is updated, `cropMapVersion` is NOT incremented
- `scrollPanDeltaAccumulatesOffset` — two calls; verify offset accumulates
- `commitScrollPanAppliesCrop` — call `commitScrollPan()`; verify `cropMap` is updated, `liveScrollPanOffset` is reset
- `endScrollPanClearsState` — verify `liveScrollPanPanelId == nil`, `liveScrollPanOffset == .zero`

### 4B — Changes

**`ViewModel/CollageViewModel.swift`**

Add:
```swift
var liveScrollPanOffset: CGSize = .zero
var liveScrollPanPanelId: UUID?
```

Modify `scrollPanDelta(_:)`:
- Accumulate delta into `liveScrollPanOffset` (scaled by `scrollSensitivity`)
- Set `liveScrollPanPanelId` from `cropManager.scrollPanActivePanelId`
- Do NOT call `cropManager.scrollPanAccumulateDelta()`, `cropManager.scrollPanApply()`, or `notifyCropMapChanged()`
- Do NOT schedule the 150ms render debounce or `scheduleScrollPanCommit()`

Add `commitScrollPan()`:
- Look up the accumulated offset and active panel
- Call `cropManager.scrollPanAccumulateDelta(liveScrollPanOffset, sensitivity: 1)` (sensitivity already applied)
- Call `cropManager.scrollPanApply(..., finish: true)`
- Call `notifyCropMapChanged()`
- Call `updatePanelPreview(panelId:)` for the affected panel
- Reset `liveScrollPanOffset = .zero`, `liveScrollPanPanelId = nil`

Modify `endScrollPan()`:
- Call `commitScrollPan()` before `cropManager.endScrollPan()`

**`Views/CollageEditorView.swift`**

In the `ForEach` that renders panel images (layered mode), apply:
```swift
.offset(panel.id == viewModel.liveScrollPanPanelId ?
    canvasToPreviewOffset(viewModel.liveScrollPanOffset) : .zero)
```

Add helper `canvasToPreviewOffset(_ canvasOffset: CGSize, in previewSize: CGSize) -> CGSize` that scales the canvas-space offset to preview-space using the same ratio as `canvasToPreviewFrame`.

In `ScrollPanView` `onPanEnded`:
- Replace inline `updatePanelPreview` call with `viewModel.endScrollPan()` (which now commits internally)

**`CropManager.swift`**

Add `scrollPanCommit(accumulatedOffset: CGSize, panels:images:panelAssignments:)` that:
- Applies the pre-accumulated offset directly to the active panel's crop
- Calls `endScrollPan()` internally

---

## Phase 5 — Deduplicate panelFrames

**Problem addressed:** E

**Why last:** Smallest impact, trivial change.

### 5A — Tests

No new tests needed — this is a pure deduplication with no behavioral change. The existing body rendering behavior is exercised by the UI.

### 5B — Changes

**`Views/CollageEditorView.swift`**

Change `panelAt(location:in:)` to accept `panelFrames` as a parameter:
```swift
private func panelAt(frames panelFrames: [UUID: CGRect], location: CGPoint) -> UUID?
```

Pass the already-computed `panelFrames` from the body closure into all calls to `panelAt`.

---

## Expected Results After All Phases

| Action | Before | After |
|--------|--------|-------|
| Title position drag | Full text layout + 1920x1080 CG render at 60Hz | Cached metrics + tight bounding-box render at 60Hz |
| Title font size change | Full text layout + 1920x1080 CG render | Full text layout (1x) + tight render |
| Title keystroke | Full composite of all panels + title at 960x540 | Only title component update in layered mode |
| Scroll pan | cropMap mutation + SwiftUI invalidation + 150ms CG lag | SwiftUI `.offset` at 120Hz, CG render on gesture end |
| Panel frame computation | 2x per body evaluation | 1x per body evaluation |

## Rollback Plan

Each phase is independently revertable. If a phase introduces regressions:
- Phase 1: Revert `TitleStyle.LayoutKey` and restore `cachedTitleMetrics = nil` in both setters
- Phase 2: Remove `!isLayeredMode` guards
- Phase 3: Revert to `updateTitleImageLive()` and full-canvas title render
- Phase 4: Restore original `scrollPanDelta()` with `notifyCropMapChanged()` and 150ms debounce; remove `liveScrollPanOffset`
- Phase 5: Revert `panelAt` signature
