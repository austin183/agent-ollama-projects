# Session 102 — SRP Decomposition Phase 1: BackgroundManager & TitleManager

**Date:** 2026-06-13
**Plan:** `_agent_docs/plans/2026-06-13-srp-decomposition.md`

## Summary

Implemented Phase 1 of the SRP decomposition plan — extracted `BackgroundManager` (8 background properties + methods) and `TitleManager` (title state, CoreText caching, setter methods) from `CollageViewModel`. Applied the established `@Observable` delegation chain pattern with computed property wrappers that encode undo registration, debounced persistence, and preview update side effects.

## BackgroundManager

**New file:** `ViewModel/BackgroundManager.swift` (54 lines)

Extracted from `CollageViewModel`:
- 8 stored properties: `backgroundColor`, `backgroundStyle`, `gradientStartColor`, `gradientEndColor`, `gradientAngle`, `backgroundImage`, `backgroundImagePath`, `backgroundOpacity`
- Methods: `buildConfig()`, `setBackgroundImage()`, `updateBackground()`, `reset()`

ViewModel computed property delegation pattern for each property — getter reads manager, setter captures old value, applies side effects (undo + save + preview):
```swift
var backgroundColor: NSColor {
    get { backgroundManager.backgroundColor }
    set {
        let old = backgroundManager.backgroundColor
        backgroundManager.backgroundColor = newValue
        guard !isInitializing else { return }
        // undo + debouncedSave + updatePreview
    }
}
```

## TitleManager

**New file:** `ViewModel/TitleManager.swift` (102 lines)

Extracted from `CollageViewModel`:
- Properties: `titleAttrString`, `titleStyle`, `isDraggingTitle`
- CoreText bounds cache: `TitleBoundsCache`, `ensureTitleBounds()`, `cachedLayoutKey`, `cachedString`, `boundsVersion`
- Computed: `canvasFrame`, `minWidth`, `title`
- Methods: `updateImage()`, `updateImageLive()`, `finishDrag()`, `reset()`

The `boundsVersion` counter replaces the ViewModel's `titleImageVersion` for cache invalidation within the manager, preserving the version counter pattern from session 76.

## CollageViewModel Changes

- Added `backgroundManager: BackgroundManager` and `titleManager: TitleManager` stored properties
- Replaced 8 background stored properties + `didSet` with computed delegations
- Replaced `titleAttrString`, `titleStyle`, `isDraggingTitle` stored properties with computed delegations
- Removed `ensureTitleBounds()`, `cachedTitleBounds`, `cachedTitleLayoutKey`, `cachedTitleString` (moved to TitleManager)
- Updated `buildAssemblyConfig()` to read from managers
- Updated `clearAll()` to call `backgroundManager.reset()` and `titleManager.reset()`
- Updated `setTitle*` methods to operate on `titleManager.titleStyle`
- Updated `updateTitleImage()` / `updateTitleImageLive()` / `finishTitleDrag()` to delegate to manager
- Promoted `titleImageVersion` from `private` to internal (manager needs to increment)
- Promoted `debouncer` from `private` to internal (manager needs to cancel tasks)
- Promoted `debouncedSave()` from `private` to internal (manager calls on finish)

## ExportPanel Changes

- Added `backgroundManager: BackgroundManager` and `titleManager: TitleManager` parameters
- Background bindings converted from `$viewModel.backgroundColor` to explicit `Binding(get:set:)` — computed properties on `@Observable` classes cannot use `@Bindable` shorthand (established pattern from skill)
- Title attributed string binding similarly wrapped

## ContentView Changes

- `ExportPanel` instantiation passes `viewModel.backgroundManager` and `viewModel.titleManager`

## CollageEditorView

No changes needed — title drag logic reads `viewModel.isDraggingTitle`, `viewModel.titleStyle`, `viewModel.cachedTitleCanvasFrame` through computed properties, which delegate to the manager transparently.

## Verification

- `xcodebuild build` — Succeeded, zero errors
- `xcodebuild test` — All 247+ tests pass
- Line counts: CollageViewModel 1,104 lines (was 1,092), BackgroundManager 54, TitleManager 102

## Files Changed

| File | Changes |
|------|---------|
| `ViewModel/BackgroundManager.swift` | New — 8 background properties, config builder, reset |
| `ViewModel/TitleManager.swift` | New — title state, CoreText cache, bounds version counter |
| `ViewModel/CollageViewModel.swift` | Computed property delegation, init/clearAll/buildAssemblyConfig updates, access control promotions |
| `Views/ExportPanel.swift` | Manager parameters, explicit `Binding(get:set:)` for computed properties |
| `ContentView.swift` | Pass managers to ExportPanel |

## New Learnings

None — all patterns (computed property delegation, version counters, `Binding(get:set:)` for computed properties, access control for manager cross-references) were established in prior sessions and documented in existing learnings.

---
**Status:** Complete
**Follow-up:** Phase 2 (View Cleanup), Phase 3 (Assembler Split) from the same plan.
