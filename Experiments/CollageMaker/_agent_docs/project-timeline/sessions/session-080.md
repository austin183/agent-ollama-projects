# Pan/Zoom Performance Phase 1: Cache Title Layout in ViewModel — Session 80

**Date:** 2026-06-03
**Plan:** `2026-06-03-pan-zoom-performance.md` Phase 1

## Context

CoreText title layout (`TitleTextData.extract` + `TitleBoundsCT.compute`) ran on every `body` evaluation in `CollageEditorView`. During crop gestures, `cropMapVersion` increments ~33fps, triggering full body re-evaluation and 33 CoreText object creations per second for no visual benefit.

## Approach

Moved expensive CoreText computation from view computed properties to a cached ViewModel method. View delegates to `viewModel.cachedTitleCanvasFrame` and `viewModel.cachedTitleMinWidth`. The ViewModel's `ensureTitleBounds()` gates CoreText work behind a `LayoutKey` + `NSAttributedString.isEqual()` cache check.

## Changes Completed

### `ViewModel/CollageViewModel.swift`
- Added `TitleBoundsCache` wrapper class (reference type for testable identity)
- Added `cachedTitleBounds`, `cachedTitleLayoutKey`, `cachedTitleString` cache fields
- Added `ensureTitleBounds()` — lazy computation with cache hit/miss logic
- Added `cachedTitleCanvasFrame` — uses cached bounds + cheap CGRect math for position
- Added `cachedTitleMinWidth` — uses cached bounds directly

### `Views/CollageEditorView.swift`
- Replaced 31 lines of CoreText-heavy computed properties with 6-line thin delegators

### `CollageMakerTests/CollageViewModelTests.swift`
- 11 new tests covering cache behavior: empty title, population, title/fontSize/width/position changes, bounds cache hit/miss, clear-restore recovery

## Bug Fixed During Session

- **Clear-restore cache stale nil** — Clearing the title (`""`) set `cachedTitleBounds = nil` but left `cachedTitleString` and `cachedTitleLayoutKey` with stale values. Restoring the same title matched the stale key and returned `nil`. Fix: clear all three cache fields on empty title, plus defensive `let cachedBounds = cachedTitleBounds` guard in the cache-hit check.

## Build Status

**BUILD SUCCEEDED** — Zero warnings.

**ALL TESTS PASS** — 41 CollageViewModelTests pass (247 total).

## Files Changed

- `ViewModel/CollageViewModel.swift` — TitleBoundsCache, ensureTitleBounds, cachedTitleCanvasFrame, cachedTitleMinWidth
- `Views/CollageEditorView.swift` — Thin delegators for titleCanvasFrame, titleMinWidth
- `CollageMakerTests/CollageViewModelTests.swift` — 11 new cached title layout tests
