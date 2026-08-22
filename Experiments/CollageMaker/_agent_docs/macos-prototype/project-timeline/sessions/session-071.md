# Preview Lag Fixes — Phase 2: Preview Size Rendering — Session 71

**Date:** 2026-05-31
**Plan:** `_agent_docs/plans/2026-05-31-preview-lag-fixes.md` (Phase 2)

## Context

Phase 1 debounced background/title property changes (8-40x fewer renders). Phase 2 targets per-render CPU: `assemblePreviewWithCGImages` rendered at full canvas resolution (1920x1080 = 2,073,600 pixels) then used `NSImage(cgImage:size:)` with `previewSize` (960x540) as a display hint. The bitmap was already fully rendered at 4x the needed resolution before being downscaled by AppKit for display.

## Changes

### New `renderPreviewIntoContext` method (`CollageAssembler.swift:165-237`)

Creates an `NSBitmapImageRep` at `previewSize` (960x540) instead of `canvasSize` (1920x1080), then applies `context.scaleBy(x: scale, y: scale)` where `scale = previewSize.width / config.canvasSize.width` (0.5). All existing drawing calls (`drawGradient`, `drawImageBackground`, `drawPanels`, `drawTitle`) continue using canvas coordinates unchanged — CoreGraphics handles the downscaling via the CTM with `.high` interpolation quality.

### Updated `assemblePreviewWithCGImages` (`CollageAssembler.swift:103-124`)

Changed to call `renderPreviewIntoContext` instead of `renderIntoContext`. The full-resolution `renderIntoContext` path remains unchanged for export.

## Design Decisions

- **Width-only scale calculation** — Safe because both `defaultCanvasSize` (1920x1080) and `defaultPreviewSize` (960x540) share 16:9 aspect ratio, so `960/1920 == 540/1080 == 0.5`.
- **Export path unchanged** — `assembleWithCGImages` continues to use `renderIntoContext` at full resolution. Only preview rendering is affected.
- **No coordinate changes needed** — The `scaleBy` CTM transform is transparent to all drawing code that operates in canvas coordinates.

## Review Findings (diff-review agent)

No issues found. Confirmed:
- `scaleBy` is standard CoreGraphics practice; CTM correctly transforms all drawing operations
- `TitleMetrics.boundingBox` is pure measurement, no graphics context dependency
- `defer { NSGraphicsContext.restoreGraphicsState() }` covers all exit paths
- Thread safety guaranteed by serial `DispatchQueue` in `RenderScheduler`

## Build & Test

- Build: succeeded, zero warnings
- All 143 unit tests passing (including `assemblePreviewSize` which asserts correct output size)
- App launches successfully via `build_and_run.sh --verify`

## Expected Impact

4x reduction in per-render CPU time (518,400 pixels vs 2,073,600). Combined with Phase 1's 8-40x reduction in render count, total CPU drops 32-160x during slider/color picker interaction.
