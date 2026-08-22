# Slice Angle Slider — Debounce + Crop Preservation

**Date**: 2026-06-27
**Change Request**: `_agent_docs/change-requests/round-107.4.md`
**Status**: Planned

## Problem

Dragging the diagonal slice angle slider (and hex spacing slider) triggers a full layout regeneration — new panel geometry + saliency-based crop recomputation — on every slider tick with no debouncing. A drag from 0° to 75° fires ~75 full regenerations. During each regeneration, rendered panel images are cleared before new ones are computed, producing a blank canvas. Main-thread CoreGraphics compositing and Vision saliency analysis block the UI, making the app feel frozen.

## Root Cause

1. `setDiagonalSliceAngle` (line 189-196) and `setHexagonalSpacing` (line 198-205) call `regenerateLayout(preserveCrops: false)` immediately — no debouncing
2. `preserveCrops: false` discards existing crops and recomputes from saliency analysis on every tick
3. `regenerateLayout` clears `panelRenderedImages` (line 71) before computing new crops and re-rendering — the UI shows panels with no images in between
4. Undo registration fires on every tick, creating ~75 undo entries per drag
5. By contrast, `setGutter` (line 176-187) uses `debouncer.debounce()` with `preserveCrops: true` — smooth, no blank canvas

## Design

Match the `setGutter` pattern: update the property immediately so the binding label reflects the current value, then defer undo registration and layout regeneration to the debounced callback. Use `preserveCrops: true` so existing image content survives during the drag.

## Implementation

### 1. `CollageViewModel.swift` — `setDiagonalSliceAngle` (line 189-196)

Before:
```swift
func setDiagonalSliceAngle(_ value: CGFloat) {
    let old = layoutManager.setDiagonalSliceAngle(value)
    guard !isInitializing else { return }
    registerUndo(oldValue: old, actionName: "Change Slice Angle") { $0.layoutManager.diagonalSliceAngle = old }
    if layoutStyle == .diagonalSlices {
        regenerateLayout(preserveCrops: false)
    }
}
```

After:
```swift
func setDiagonalSliceAngle(_ value: CGFloat) {
    let old = layoutManager.setDiagonalSliceAngle(value)
    guard !isInitializing else { return }
    debouncer.debounce(id: "sliceAngle", delay: FrameTempo.layoutChangeDebounce) { [weak self] in
        guard let self else { return }
        self.undoManager.registerUndo(withTarget: self) { target in
            target.layoutManager.diagonalSliceAngle = old
        }
        self.undoManager.setActionName("Change Slice Angle")
        if self.layoutStyle == .diagonalSlices {
            self.regenerateLayout(preserveCrops: true)
        }
    }
}
```

**Changes:**
- Undo + regeneration moved into debounced callback (id: `"sliceAngle"`, delay: `FrameTempo.layoutChangeDebounce` = 20ms)
- `preserveCrops: false` → `preserveCrops: true`
- `registerUndo` helper replaced with inline `undoManager.registerUndo` (matches `setGutter` pattern)
- `layoutStyle` check captured inside the closure via `self.layoutStyle`

### 2. `CollageViewModel.swift` — `setHexagonalSpacing` (line 198-205)

Same treatment:

Before:
```swift
func setHexagonalSpacing(_ value: CGFloat) {
    let old = layoutManager.setHexagonalSpacing(value)
    guard !isInitializing else { return }
    registerUndo(oldValue: old, actionName: "Change Hex Spacing") { $0.layoutManager.hexagonalSpacing = old }
    if layoutStyle == .hexagonal {
        regenerateLayout(preserveCrops: false)
    }
}
```

After:
```swift
func setHexagonalSpacing(_ value: CGFloat) {
    let old = layoutManager.setHexagonalSpacing(value)
    guard !isInitializing else { return }
    debouncer.debounce(id: "hexSpacing", delay: FrameTempo.layoutChangeDebounce) { [weak self] in
        guard let self else { return }
        self.undoManager.registerUndo(withTarget: self) { target in
            target.layoutManager.hexagonalSpacing = old
        }
        self.undoManager.setActionName("Change Hex Spacing")
        if self.layoutStyle == .hexagonal {
            self.regenerateLayout(preserveCrops: true)
        }
    }
}
```

**Changes:**
- Same pattern as `setDiagonalSliceAngle`, debounce id: `"hexSpacing"`
- `preserveCrops: false` → `preserveCrops: true`

### 3. `CollageViewModel.swift` — `setDoubleExposureMaskOpacity` (line 207-212)

Before:
```swift
func setDoubleExposureMaskOpacity(_ value: CGFloat) {
    let old = layoutManager.setDoubleExposureMaskOpacity(value)
    guard !isInitializing else { return }
    registerUndo(oldValue: old, actionName: "Change Mask Opacity") { $0.layoutManager.doubleExposureMaskOpacity = old }
    updatePreviewDebounced()
}
```

After:
```swift
func setDoubleExposureMaskOpacity(_ value: CGFloat) {
    let old = layoutManager.setDoubleExposureMaskOpacity(value)
    guard !isInitializing else { return }
    debouncer.debounce(id: "maskOpacity", delay: FrameTempo.layoutChangeDebounce) { [weak self] in
        guard let self else { return }
        self.undoManager.registerUndo(withTarget: self) { target in
            target.layoutManager.doubleExposureMaskOpacity = old
        }
        self.undoManager.setActionName("Change Mask Opacity")
        self.updatePreviewDebounced()
    }
}
```

**Changes:**
- Undo registration moves into debounced callback (id: `"maskOpacity"`)
- `updatePreviewDebounced()` moves inside the debounced callback
- Renders are still debounced (the inner `updatePreviewDebounced` adds its own 20ms debounce), but undo is now a single entry per gesture rather than ~30-60 entries

**Note:** This is a minor consistency fix. The mask opacity slider was already debounce-rendered, so it didn't cause a blank canvas. The fix only addresses the undo spam.

## Files Modified

| File | Lines | Change |
|------|-------|--------|
| `CollageViewModel.swift` | ~20 lines | Rewrite `setDiagonalSliceAngle`, `setHexagonalSpacing`, `setDoubleExposureMaskOpacity` |

## Verification

### Automated
- `bash script/run_tests.sh` — all existing tests pass
- `CollageViewModelTests.swift` may need a test for debounced slice angle behavior (similar to `setTitleFontSizeCallsUpdateTitleImageDebounced`)

### Manual
1. **Slice angle slider**: Drag from 0° to 75° — canvas should NOT go blank; existing images remain visible inside panels throughout the drag
2. **Final render**: Upon releasing the slider (or after 20ms pause), final layout renders correctly with updated geometry
3. **Hex spacing slider**: Same smooth behavior as slice angle
4. **Undo**: Cmd+Z after releasing slider should revert to pre-drag value (single undo step, not per-tick)
5. **Mask opacity**: Cmd+Z should produce one undo entry per drag gesture
6. **Compare with gutter slider**: Slice angle and hex spacing should feel similarly smooth and responsive
7. **Edge cases**: Test at slider boundaries (0°, 75°); verify no crash or blank canvas

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| `preserveCrops: true` may leave stale crop rectangles that don't match new panel geometry | Crops are preserved by slot index (via `cropManager.cropsBySlot` / `applyCropsBySlot`). The existing images will be visible inside the new panels, but may need slight adjustment. This is acceptable — the user can re-crop if needed. The gutter slider already uses this pattern. |
| Debounce id collision — `"sliceAngle"` / `"hexSpacing"` / `"maskOpacity"` should not conflict with existing ids | Existing ids: `"gutter"`, `"previewRender"`, `"panPreview"`, `"pinchPreview"`, `"overlayRender"`, `"scrollPanPreview"`, `"fontSize"`. New ids are unique. |
| `layoutStyle` check inside closure — user could switch layout style during the debounce window | The `if self.layoutStyle == .diagonalSlices` guard prevents regenerating if the user switched away from diagonal slices during the drag. This is correct behavior. |
| Old value capture in closure — `old` is captured by reference via `[weak self]` | `old` is a value type (`CGFloat`), captured by the closure at call time. This is correct — it captures the value before the slider started. |

## Notes

- The `setGutter` pattern is the established precedent. These changes bring `setDiagonalSliceAngle`, `setHexagonalSpacing`, and `setDoubleExposureMaskOpacity` into alignment.
- The `registerUndo` helper method (line 454-462) wraps `beginUndoGrouping` / `endUndoGrouping`. The gutter pattern uses inline `undoManager.registerUndo` / `setActionName` without grouping. This is consistent — the debounced callback already represents a single logical action.
- Slider range (0...75°) remains unchanged per user decision.
