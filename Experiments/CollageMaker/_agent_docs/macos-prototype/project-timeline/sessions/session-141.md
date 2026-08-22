# Slice Angle/Hex Spacing/Mask Opacity Slider Debounce — Align with setGutter Pattern

**Date:** 2026-06-27
**Plan reference:** `_agent_docs/plans/2026-06-27-slice-angle-slider-debounce.md`
**CR reference:** `_agent_docs/change-requests/round-107.4.md`
**Goal:** Eliminate blank canvas and undo spam when dragging slice angle, hex spacing, or mask opacity sliders by matching the established `setGutter` debounce pattern.

---

## Problem

Dragging the diagonal slice angle slider (0°→75°) fired ~75 full layout regenerations with no debouncing — each regeneration cleared rendered panel images before recomputing crops and re-rendering, producing a blank canvas. Main-thread CoreGraphics compositing + Vision saliency analysis blocked the UI thread, making the app feel frozen. Each tick also registered its own undo entry (~75 undo entries per drag).

The hex spacing slider had the same issue. The mask opacity slider was already debounce-rendered but still produced ~30-60 undo entries per gesture.

## Solution: Three Setters Aligned to setGutter Pattern

All three setters now follow the established `setGutter` pattern at line 176-187:
1. Property value updated immediately (binding label reflects current value)
2. Undo registration + side effects deferred into debounced callback (id + delay)
3. Inline `undoManager.registerUndo(withTarget:)` + `setActionName()` — no begin/end grouping wrapper

### `setDiagonalSliceAngle` (line 189-202)

**Before:** Immediate `registerUndo(oldValue:actionName:)` helper + `regenerateLayout(preserveCrops: false)` on every tick.
**After:** Debounced with id `"sliceAngle"`, inline undo registration, `preserveCrops: true`. The `layoutStyle == .diagonalSlices` guard is captured inside the closure via `self.layoutStyle`.

### `setHexagonalSpacing` (line 204-217)

**Before:** Same problematic pattern as slice angle.
**After:** Debounced with id `"hexSpacing"`, inline undo registration, `preserveCrops: true`. The `layoutStyle == .hexagonal` guard is captured inside the closure.

### `setDoubleExposureMaskOpacity` (line 219-230)

**Before:** Immediate `registerUndo(oldValue:actionName:)` + `updatePreviewDebounced()`.
**After:** Debounced with id `"maskOpacity"`, inline undo registration, `updatePreviewDebounced()` moved inside the callback. Renders remain debounced (inner method adds its own 20ms), but undo is now one entry per gesture instead of ~30-60.

## Files Modified

| File | Lines Changed |
|------|---------------|
| `CollageViewModel.swift` | ~18 lines (3 setter rewrites) |

## Verification

- `bash script/run_tests.sh` — 472/473 pass (pre-existing FontMergerTests failure unrelated to changes)
- diff-review-g31: No issues found
- world-review: Confirmed polished UX behavior; minor note about potential "snap" on release when crops realign to new panel geometry

## Notes

- The `registerUndo(oldValue:actionName:)` helper (line 454) still exists and is used by other setters — only these three were changed because they had the debounce pattern available via `debouncer.debounce()`
- Debounce ids (`"sliceAngle"`, `"hexSpacing"`, `"maskOpacity"`) do not collide with existing ids: `"gutter"`, `"previewRender"`, `"panPreview"`, `"pinchPreview"`, `"overlayRender"`, `"scrollPanPreview"`, `"fontSize"`
- `FrameTempo.layoutChangeDebounce` = 20ms — same delay used by gutter slider
