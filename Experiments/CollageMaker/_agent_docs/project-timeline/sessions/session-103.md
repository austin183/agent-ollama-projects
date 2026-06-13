# Session 103 — SRP Decomposition Phase 3: Assembler Split

**Date:** 2026-06-13
**Plan:** `_agent_docs/plans/2026-06-13-srp-decomposition.md`

## Summary

Implemented Phase 3 of the SRP decomposition plan — split `CollageAssembler` (497 lines) into three focused renderer structs coordinated by a thin orchestrator. Applied ISP (Interface Segregation Principle) via protocol renaming to avoid naming collisions with new struct types. Post-review fixes consolidated context creation and completed background delegation.

## New Files

### `Services/PanelRenderer.swift` (99 lines)

Pure static struct — CoreGraphics panel rendering logic:
- `drawPanels(into:panels:cgImages:crops:panelAssignments:)` — batch panel drawing with path clipping
- `drawClampedCrop(context:cgImage:sourceRect:destRect:)` — fallback when `cgImage.cropping(to:)` returns nil
- `renderPanel(crop:cgImage:panelSize:geometry:)` — standalone per-panel render (used by PreviewManager)

### `Services/BackgroundRenderer.swift` (104 lines)

Pure static struct — CoreGraphics background rendering logic:
- `drawSolidBackground(into:size:color:)` — solid color fill
- `drawGradient(into:size:startColor:endColor:angle:)` — linear gradient
- `drawImageBackground(into:size:backgroundColor:backgroundImage:opacity:)` — image with opacity
- `renderBackground(config:canvasSize:backgroundImage:previewSize:)` — standalone background render

### `Services/OverlayRenderer.swift` (25 lines)

Pure static struct — CoreGraphics overlay rendering logic:
- `drawOverlay(into:overlay:canvasSize:)` — draws with blend mode + opacity (full composite path)
- `renderOverlay(overlay:canvasSize:)` — standalone render, delegates to `drawOverlay` (layered preview path)

### `Services/ContextFactory.swift` (18 lines)

Shared bitmap context factory — single source of truth for `CGContext` creation with device RGB color space, premultiplied alpha. Replaced 4 identical `createContext`/`createPureCGContext` implementations.

## CollageAssembler Changes (497 → 318 lines)

**Protocol renaming** — Renamed protocols to avoid collision with new struct names:
- `PanelRenderer` → `PanelRendering`
- `BackgroundRenderer` → `BackgroundRendering`
- `OverlayRenderer` → `OverlayRendering`
- `TitleRenderer` → `TitleRendering`

**Delegated all rendering** — All `draw*` calls now route through renderer structs:
- `PanelRenderer.drawPanels()` replaces inline `drawPanels`/`drawClampedCrop`
- `BackgroundRenderer.drawGradient()`/`drawImageBackground()`/`drawSolidBackground()` replace inline background switch
- `OverlayRenderer.drawOverlay()` replaces inline `drawOverlay`

**Extracted `drawBackground()` helper** — Consolidated the background switch from `renderPreviewIntoContext()` and `createBitmapContext()` into a single method. Both callers now share the same code path.

**Title rendering** — Remains in orchestrator (already delegated to `TitleMetricsCT`). No extraction needed.

**Context creation** — All callers now use `ContextFactory.createBitmap(size:)`.

## Post-Review Fixes

The `diff-review-g31` agent review caught 3 issues:

1. **`renderOverlay` missing `setBlendMode`** — Fixed by having `renderOverlay` delegate to `drawOverlay(into:)` instead of duplicating logic. Note: this was a pre-existing design choice (blend mode applied in SwiftUI for layered rendering per `cgblendmode-empty-context-learnings.md`), but the fix ensures consistency for any future callers.

2. **`.solid` background not delegated** — Added `BackgroundRenderer.drawSolidBackground()` and updated both `drawBackground()` and `renderPreviewIntoContext()` to use it. Now all 3 background cases route through `BackgroundRenderer`.

3. **`createContext` duplicated 4x** — Consolidated into `ContextFactory.createBitmap(size:)`.

## Verification

- `xcodebuild build` — Succeeded, zero errors
- `xcodebuild test` — All 247+ tests pass
- `build_and_run.sh --verify` — Build and launch succeeded

## Line Counts

| File | Before | After | Net |
|------|--------|-------|-----|
| `CollageAssembler.swift` | 497 | 318 | -179 |
| `PanelRenderer.swift` | — | 99 | +99 (new) |
| `BackgroundRenderer.swift` | — | 104 | +104 (new) |
| `OverlayRenderer.swift` | — | 25 | +25 (new) |
| `ContextFactory.swift` | — | 18 | +18 (new) |
| **Total** | 497 | 464 | -33 |

## Files Changed

| File | Changes |
|------|---------|
| `Services/PanelRenderer.swift` | New — panel drawing, clamped crop, per-panel render |
| `Services/BackgroundRenderer.swift` | New — solid/gradient/image background drawing |
| `Services/OverlayRenderer.swift` | New — overlay drawing with blend mode |
| `Services/ContextFactory.swift` | New — shared bitmap context factory |
| `Services/CollageAssembler.swift` | Protocol renames, all rendering delegated, `drawBackground()` helper |

## New Learnings

None — all patterns (pure static renderer structs, protocol naming for ISP, shared utility extraction, delegating `renderOverlay` to `drawOverlay` for consistency) were established in prior sessions. The `diff-review-g31` agent flagged `renderOverlay`'s missing `setBlendMode` as a new bug, but it was a pre-existing intentional design documented in `cgblendmode-empty-context-learnings.md`. Providing relevant learning doc context in the agent prompt would improve future reviews.

---
**Status:** Complete
**Follow-up:** Plan phases 0.1, 0.2, 2.1, 2.2 remain. Phase 3 is the final "medium risk" phase.
