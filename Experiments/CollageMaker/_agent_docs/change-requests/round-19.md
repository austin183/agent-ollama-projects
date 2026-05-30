# Debounce overlay crop live gestures

## Problem

`applyOverlayCrop(panelId:sourceRect:)` is called on every `DragGesture.onChanged` tick from `PanelCropEditor` (lines 155, 277). Each call triggers:

1. `updatePreview()` — full collage re-composite (all panels, background, title)
2. `updatePanelPreview(panelId:)` — individual panel render

This fires **synchronously with no debounce**, unlike the scroll-pan and pinch gesture paths which use a 150ms debounce + panel-only render via `applyPanLive()` / `applyPinchLive()`.

Instruments shows hitches and CPU spikes during panel editor drag/resize because the main thread is scheduling a full `CollageAssembler` composite on every gesture delta (~16ms intervals at 60Hz).

## Current code

**CollageViewModel.swift:705-715**
```swift
func applyOverlayCrop(panelId: UUID, sourceRect: CGRect) {
    guard let crop = cropMap[panelId] else { return }
    let newCrop = CropInfo(
        panelId: panelId,
        sourceRect: sourceRect,
        destinationRect: crop.destinationRect
    )
    cropManager.cropMap[panelId] = newCrop
    updatePreview()              // ← full composite, every delta
    updatePanelPreview(panelId: panelId)  // ← redundant with above
}
```

**PanelCropEditor.swift:42-80** — The drag gesture lifecycle already exists:
- `onChanged` → calls `applyOverlayCrop` every delta
- `onEnded` → sets `isLiveGesturing = false`, ends undo grouping

## Existing pattern to follow

**applyPanLive** (CollageViewModel.swift:635-647) and **applyPinchLive** (line 663-672) already implement the correct pattern for continuous gestures:

```swift
func applyPanLive() {
    cropManager.applyPan(..., finish: false)  // update crop state immediately

    previewDebounceTask?.cancel()
    previewDebounceTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 150_000_000)  // 150ms debounce
        if let panelId = self?.cropManager.activePanelId {
            self?.updatePanelPreview(panelId: panelId)    // only affected panel
        }
    }
}
```

The gesture end (`applyPan` / `applyPinch` with `finish: true`) then does the full `updatePreview()`.

## `@Observable` tracking obstacle

`PanelCropEditor` reads `viewModel.cropManager.cropMap[panel.id]` to drive the overlay preview (`CropPreviewView`). `CropManager` is `@Observable`, but `@Observable` **cannot track in-place dictionary subscript mutations** — only whole-property reassignments. When `applyOverlayCropLive` does `cropManager.cropMap[panelId] = newCrop`, SwiftUI receives no change signal and the overlay preview won't update.

The current `applyOverlayCrop` works around this indirectly: `updatePreview()` and `updatePanelPreview()` reassign stored properties (`previewImage`, `panelRenderedImages`), which **does** trigger observation. But the live path skips those full renders, so we need a direct signal.

**Fix: Version counter on `CollageViewModel`.** Add a stored `cropMapVersion` property. The `cropMap` computed property reads it (establishing observation dependency), and in-place mutations increment it:

```swift
private var cropMapVersion = 0

var cropMap: [UUID: CropInfo] {
    get {
        let _ = cropMapVersion  // establishes observation dependency
        return cropManager.cropMap
    }
    set { cropManager.cropMap = newValue }
}

private func notifyCropMapChanged() {
    cropMapVersion += 1
}
```

`applyOverlayCropLive` calls `notifyCropMapChanged()` after mutating `cropManager.cropMap`. This is the same pattern as `NSObject`'s `willChangeValue`/`didChangeValue` — a no-op read establishes the dependency, the counter increment fires the change.

## Proposed fix

Split `applyOverlayCrop` into two methods matching the pan/pinch pattern:

### 1. `applyOverlayCropLive(panelId:sourceRect:)` — called during drag

- Updates `cropManager.cropMap` immediately (for the overlay preview in PanelCropEditor)
- Calls `notifyCropMapChanged()` to fire `@Observable` change signal for the overlay preview
- Debounces the panel preview render with 150ms delay
- Does NOT call `updatePreview()` (no full composite)

### 2. `finishOverlayCrop(panelId:)` — called on gesture end

- The crop state is already in `cropManager.cropMap` from the live updates
- Calls `updatePreview()` for the final full composite
- Calls `updatePanelPreview(panelId:)` for the affected panel

### View changes

**PanelCropEditor.swift** `onChanged` should call `applyOverlayCropLive` instead of `applyOverlayCrop`.

**PanelCropEditor.swift** `onEnded` should call `finishOverlayCrop(panelId:)` to trigger the full composite. The crop state is already committed from the live updates, so no sourceRect needs to be passed.

## Files to modify

- `CollageMaker/ViewModel/CollageViewModel.swift` — add `cropMapVersion` stored property, update `cropMap` getter to read the version, add `notifyCropMapChanged()`, add `applyOverlayCropLive` and `finishOverlayCrop`, keep `applyOverlayCrop` for non-gesture callers
- `CollageMaker/Views/PanelCropEditor.swift` — wire `onChanged` → `applyOverlayCropLive`, `onEnded` → `finishOverlayCrop`

## Verification

- Drag/resize in PanelCropEditor should feel smooth (no hitches)
- Panel editor overlay preview (dim overlay + crop rectangle) should update live during drag, driven by the `cropMapVersion` signal
- Full collage preview should update after gesture ends
- Instruments SwiftUI template should show no red/orange bars during overlay crop drag
- Undo should still work (undo grouping is already wired in `beginOverlayCropUndo` / `endOverlayCropUndo`)
- Confirm `applyPanLive` and `applyPinchLive` also call `notifyCropMapChanged()` if any view reads `cropMap` during those gestures (they currently don't, but the version counter should be safe to add)
