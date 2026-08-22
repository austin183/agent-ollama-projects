# Session 119 — Round 102: Double Exposure Layout→Overlay + Stale Overlay Bug Fix

**Date:** 2026-06-19
**Change Request:** round-102.md

## Summary

Removed `doubleExposure` from `LayoutStyle` enum and promoted overlay/mask controls to a global option available for all layouts. Fixed a stale overlay rendering bug discovered during testing.

## Changes

### Double Exposure Layout → Global Overlay

**Rationale:** Double Exposure doesn't affect panel geometry — `DoubleExposureLayoutStrategy` was just a stub delegating to `UniformLayoutStrategy`. The actual effect is a canvas-wide overlay applied on top of panels, independent of layout.

**Files changed (6):**

1. **`Models/LayoutStyle.swift`** — Removed `case doubleExposure` from enum, title, and icon switches. Added `LayoutStyle.migrate(rawValue:)` static method for backward compatibility (maps `"doubleExposure"` → `.uniform`).

2. **`Services/LayoutGenerator.swift`** — Removed `DoubleExposureLayoutStrategy` struct and its `makeStrategy()` case.

3. **`ViewModel/LayoutManager.swift`** — `buildOverlayConfig()` no longer gates on `layoutStyle == .doubleExposure`. Overlay activates whenever a mask image is set, regardless of layout.

4. **`Services/UserDefaultsPersistence.swift`** — `load()` now uses `LayoutStyle.migrate()` instead of direct `init(rawValue:)`, so saved projects with `doubleExposure` layout load as `.uniform`.

5. **`Views/LayoutConfigSidebar.swift`** — Double exposure controls moved to a new `Section("Overlay")` that appears when images are loaded. "Choose Mask" button always visible; opacity slider only shows when a mask is set.

6. **`CollageMakerTests/LayoutManagerTests.swift`** — Removed `buildOverlayConfigReturnsNilForNonDoubleExposure` test. Updated remaining overlay tests to not set `.doubleExposure` layout style.

### Stale Overlay Bug Fix

**Bug:** Removing the overlay mask image left the old overlay image visible on the canvas.

**Root cause:** `updatePreview()` and `updateAllPanelPreviews()` only updated the overlay when `config.overlay` was non-nil (`if let overlay = config.overlay { ... }`). When the mask was removed, `config.overlay` became `nil`, so the stale `overlayImage` in `previewManager` was never cleared.

**Fix:** Added `else` branches in both methods to clear `previewManager.overlayImage` and `previewManager.overlayBlendMode` when no overlay config exists.

## Verification

- Build: zero errors, zero warnings
- All unit tests passing
