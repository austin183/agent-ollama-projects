# Preview Update Performance — Phase 1 — Session 67

**Date:** 2026-05-30
**Plan:** `_agent_docs/plans/2026-05-30-preview-update-performance.md` (Phase 1)

## Context

The layered rendering architecture (`panelRenderedImages`, `previewBackgroundImage`, `titleImage`) displays individual layers in a `ZStack`. The view switches from composite fallback to layered mode when `panelRenderedImages` is populated. Once in layered mode, `updatePreview()` renders the full composite image (`previewImage`) which is never displayed — wasted CPU during continuous interactions.

## Changes

### P1 — `scheduleScrollPanCommit`: Remove wasted composite during sustained scrolling
`CollageViewModel.swift` — Removed `self.updatePreview()` from the 150ms commit timer closure. The timer still persists crop state and re-establishes `beginPan` for gesture continuity, but no longer launches a full composite render. During a 1-second scroll, this eliminates ~6 wasted composite renders.

### P2 — `CollageEditorView.onPanEnded`: Single panel update at scroll gesture end
`CollageEditorView.swift` — Replaced `updatePreview()` + `updateAllPanelPreviews()` with a single `updatePanelPreview(panelId:)` for the active scroll-pan panel. Panel ID is captured before `endScrollPan()` to avoid the nil returned after the scroll pan state is cleared.

### P3 — `finishOverlayCrop`: Remove composite + redundant panel render
`CollageViewModel.swift` — Removed `updatePreview()` from `finishOverlayCrop`. The panel was already rendered by the debounced live task; only the final `updatePanelPreview(panelId:)` is needed.

### P4 — `applyPan` / `applyPinch`: Replace composite with single panel update
`CollageViewModel.swift` — Both methods now call `updatePanelPreview(panelId:)` instead of `updatePreview()`. Guards against nil `panelId`. The panel preview was already updated by the debounced live task; the gesture-end call ensures a final committed render.

### P5 — Pinch `onEnded`: Remove redundant `updateAllPanelPreviews`
`CollageEditorView.swift` — Removed `viewModel.updateAllPanelPreviews()` from pinch gesture end. `applyPinch` (after P4 fix) handles the single panel update.

### P6 — `finishTitleDrag`: Replace composite with title-only render
`CollageViewModel.swift` — Replaced `updatePreview()` with `updateTitleImage()`. Only the title layer changed during the drag; no need to re-render the full composite + background.

## Unchanged (per plan)
- **P11 `analyzeSaliency`**: Composite + all panels left as-is — serves as loading placeholder during saliency computation gap
- **P12 `regenerateLayout`**: Composite + all panels left as-is — intentional composite-fallback pattern for initial render

## Expected Impact
- Scroll wheel pan: ~1 composite eliminated per 150ms of sustained scrolling + 1 composite + N panels at gesture end
- Pinch zoom: 1 composite + N panels eliminated at gesture end
- Title drag: 1 composite + 1 background render eliminated at gesture end
- Overlay crop: 1 composite + 1 redundant panel eliminated at gesture end
- Each composite at 1920x1080 takes ~50-100ms; removing these during continuous interactions eliminates the primary source of CPU spikes

## Build & Test
- Build: succeeded (zero errors, zero warnings)
- All 167+ unit tests passing (1 pre-existing failure: `FontMergerTests/mergesBoldTrait`)
