# Session 115 — SRP Remediation Phase 8: Polish

**Date:** 2026-06-18
**Plan:** `_agent_docs/plans/2026-06-15-srp-remediation-plan.md` § Phase 8

## Summary

Implemented all 8 Phase 8 polish items from the SRP remediation plan. Seven completed, one (8.6 `isInitializing` reduction) cancelled as too risky for a polish pass. Ran diff-review-g31 which caught one bug: `setBackgroundImage` undo closure missing `backgroundImagePath` restoration.

## Changes

### 8.1 — Magic numbers → `MosaicConfig` struct (LayoutGenerator.swift)
Extracted mosaic split ratios (0.25, 0.33, 0.4) and probability thresholds (0.3, 0.6) into a `MosaicConfig` struct with a `splitRatio(for:hasPanels:)` method. `MosaicLayoutStrategy` now calls `MosaicConfig.default.splitRatio(...)` instead of inline `if/else`.

### 8.2 — `SeededPRNG` → `Math+Utils.swift`
Moved `SeededPRNG` struct from end of `LayoutGenerator.swift` to new `Services/Math+Utils.swift`. Single consumer (`MosaicLayoutStrategy`) so no cross-file breaking changes.

### 8.3 — Accessibility on title resize handles (CollageEditorView.swift)
Added `.accessibilityLabel("Resize title left/right edge")` and `.accessibilityAddTraits(.isButton)` to the two orange resize handle rectangles.

### 8.4 — Decompose `CollageEditorView` (444→~240 lines)
Extracted four subviews from the main ZStack:
- `CanvasBackgroundView` — layered background image or composite preview
- `PanelsOverlayView` — `ForEach` panel overlays, double exposure overlay, title image
- `TitleInteractionOverlay` — title bounding frame and resize handles
- `DropPreviewView` — drag source/target highlights, cursor thumbnail

Required promoting `PanelOverlay` and `overlayBlendMode(from:)` from `private` to internal.

### 8.5 — Standardize `BackgroundManager.setBackgroundImage`
Changed to return `(NSImage?, String?)` tuple of old values, matching the pattern used by `LayoutManager.setMaskImage`. Updated `CollageViewModel.setBackgroundImage` call site to capture both values.

### 8.6 — `isInitializing` guards (Cancelled)
22 occurrences across `CollageViewModel.swift`. Reducing would require significant structural changes (e.g., init-phase setter variants) with high regression risk. Deferred.

### 8.7 — Extract `scheduleSaliencyAnalysis()` (ImageCoordinator.swift)
Extracted the duplicated `guard !images.isEmpty && !isProcessing { Task { analyzeSaliency() } }` pattern from `addImages`, `removeImage`, and `moveImages` into a single private helper.

### 8.8 — `bytesPerRow` fix (ContextFactory.swift)
Replaced manual `Int(size.width) * 4` calculation with `0` (system-calculated). Matches Apple's documented recommendation.

## Bugs Caught by diff-review-g31

**Incomplete undo restoration:** `CollageViewModel.setBackgroundImage` captured `oldPath` from the manager but never restored `backgroundImagePath` in its undo closure. Fixed by adding `target.backgroundManager.backgroundImagePath = oldPath` to match the `setMaskImage` pattern.

## Verification

- `xcodebuild build` — Succeeded
- `xcodebuild test -only-testing:CollageMakerTests` — 440 tests passed, 0 failures
- diff-review-g31 — 1 bug found and fixed

## Files Changed

| File | Changes |
|------|---------|
| `Services/ContextFactory.swift` | bytesPerRow: manual → 0 |
| `Services/LayoutGenerator.swift` | Magic numbers → MosaicConfig, removed SeededPRNG |
| `Services/Math+Utils.swift` | New file, SeededPRNG |
| `ViewModel/BackgroundManager.swift` | setBackgroundImage returns old values |
| `ViewModel/CollageViewModel.swift` | setBackgroundImage undo fix |
| `ViewModel/ImageCoordinator.swift` | scheduleSaliencyAnalysis() extraction |
| `Views/CollageEditorView.swift` | Decomposed ZStack, promoted PanelOverlay/overlayBlendMode |
| `Views/CanvasBackgroundView.swift` | New file |
| `Views/PanelsOverlayView.swift` | New file |
| `Views/TitleInteractionOverlay.swift` | New file |
| `Views/DropPreviewView.swift` | New file |

## New Learnings

None. All patterns used in this session (config struct extraction, utility file extraction, view decomposition, dedup extraction, accessibility modifiers, setter returning old values for undo) are standard practices covered by existing skills. The diff-review-caught undo bug was a mechanical oversight, not a deep pattern.

---
**Status:** Complete
**Follow-up:** Phase 8 complete. All SRP remediation phases (1–8) now done.
