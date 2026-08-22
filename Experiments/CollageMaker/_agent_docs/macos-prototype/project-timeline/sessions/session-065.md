# Arch Review Phase 2 Refactors — Session 65

**Date:** 2026-05-29
**Plan:** `_agent_docs/plans/2026-05-29-architectural-review-fixes.md` (Phase 2)

## Changes

### 2.1 — Deduplicate CollageAssembler rendering
Extracted `renderIntoContext(config:cgImages:backgroundImage:) -> NSBitmapImageRep?` sharing bitmap context creation, panel/title drawing between `assembleWithCGImages` and `assemblePreviewWithCGImages`. Each method now only handles its final encoding step (JPEG Data vs NSImage).

### 2.2 — Split CollageAssembly protocol (ISP)
Created 4 focused sub-protocols: `CollageRenderer`, `PanelRenderer`, `BackgroundRenderer`, `TitleRenderer`. `CollageAssembly` inherits from all four. Enables callers to depend on only the methods they need.

### 2.3 — Cache TitleMetrics in ViewModel
Added `cachedTitleMetrics: TitleMetrics?` invalidated in `titleAttrString`/`titleStyle` `didSet`. New `titleMetrics` computed property provides lazy caching. `CollageEditorView.titleCanvasFrame` and `titleMinWidth` now read from `viewModel.titleMetrics` instead of recomputing `boundingRect` on every body evaluation during 60Hz title drag.

### 2.4 — Replace NSKeyedArchiver with RGBA hex
Added `NSColor.rgbaHex` getter and `init?(rgbaHex:)` in `LoggingExtensions.swift`. Updated `TitleStyle.encode/init(from:)` and `UserDefaultsColorView` to use hex strings instead of `NSKeyedArchiver`. Note: existing persisted data using archived color format will fall back to defaults on load (graceful degradation).

### 2.5 — Collapse scroll pan into CropManager
Added scroll pan state (`scrollPanPanelId`, `scrollPanAccumulator`) and methods (`beginScrollPan`, `scrollPanAccumulateDelta`, `scrollPanApply`, `endScrollPan`) to `CropManager`. `CollageViewModel` now delegates directly, removing its `scrollPanManager` dependency. `activePanelId` now returns `scrollPanPanelId ?? gestureActivePanelId` for unified preview targeting.

### 2.6 — LayoutGenerator strategy pattern
Created `LayoutStrategy` protocol with `UniformLayoutStrategy`, `HeroLayoutStrategy`, `MosaicLayoutStrategy` implementations. `LayoutGenerator.generate` dispatches via `LayoutStyle.makeStrategy()`. Extension defined in `LayoutGenerator.swift` after the strategy structs (see learnings doc for gotcha).

## Build & Test
- Build: succeeded
- All 140+ unit tests passing
