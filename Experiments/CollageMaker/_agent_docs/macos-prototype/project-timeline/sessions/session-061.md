# Session 61 — 2026-05-29

### Round 19 CR — Debounce overlay crop live gestures

**Goal:** Debounce `applyOverlayCrop` during PanelCropEditor drag/resize gestures to eliminate main-thread hitches caused by full collage re-composite on every gesture delta.

**Source:** `_agent_docs/change-requests/round-19.md`

---

## Problem

`applyOverlayCrop(panelId:sourceRect:)` was called synchronously on every `DragGesture.onChanged` tick (~60Hz), triggering:
1. `updatePreview()` — full collage re-composite (all panels, background, title)
2. `updatePanelPreview(panelId:)` — individual panel render (redundant with above)

This caused CPU spikes and hitches during panel editor drag/resize, unlike the scroll-pan and pinch paths which already used 150ms debounce + panel-only render.

## Changes

### Version counter for @Observable cropMap tracking

`@Observable` cannot track in-place dictionary subscript mutations — only whole-property reassignments. When the live path mutates `cropManager.cropMap[panelId]`, SwiftUI receives no change signal and the overlay preview in `PanelCropEditor` won't update.

**Solution:** Added `cropMapVersion` stored property on `CollageViewModel`. The `cropMap` computed getter reads the version (establishing observation dependency), and mutations increment it via `notifyCropMapChanged()`.

### Split overlay crop into live + finish

Pattern matches existing `applyPanLive`/`applyPan` and `applyPinchLive`/`applyPinch`:

- **`applyOverlayCropLive(panelId:sourceRect:)`** — Updates `cropManager.cropMap` immediately, fires `notifyCropMapChanged()` for overlay preview, debounces panel preview render with 150ms delay. Does NOT call `updatePreview()`.
- **`finishOverlayCrop(panelId:)`** — Cancels pending debounce, runs full `updatePreview()` + `updatePanelPreview` for final composite.
- **`applyOverlayCrop`** — Retained for non-gesture callers, delegates to live + finish.

### Wired PanelCropEditor to new methods

- `onChanged` → `applyOverlayCropLive` (was `applyOverlayCrop`)
- `onEnded` → `finishOverlayCrop(panelId:)` (new call for final composite)

### Fixed @Observable tracking in PanelCropEditor

Changed `viewModel.cropManager.cropMap[panel.id]` → `viewModel.cropMap[panel.id]` so the view reads through the version-tracked computed property, receiving change signals from `notifyCropMapChanged()`.

### Extended notifyCropMapChanged to pan/pinch live paths

Added `notifyCropMapChanged()` to `applyPanLive` and `applyPinchLive` for consistency — safe no-op since no view currently reads `cropMap` during those gestures, but ensures correctness if one does in the future.

## Tests Verified

- **Build:** Succeeded — zero errors
- **Tests:** All 183+ unit tests passing, 0 failures

## Files Changed

| File | Change |
|---|---|
| `ViewModel/CollageViewModel.swift` | Added `cropMapVersion`, `notifyCropMapChanged()`, `applyOverlayCropLive`, `finishOverlayCrop`; updated `cropMap` getter; extended `applyPanLive`/`applyPinchLive` |
| `Views/PanelCropEditor.swift` | Wired `onChanged` → `applyOverlayCropLive`, `onEnded` → `finishOverlayCrop`; switched to `viewModel.cropMap` |
