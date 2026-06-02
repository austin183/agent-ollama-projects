# Title Background Color Bug & Test Pollution Fix — Session 76

**Date:** 2026-06-01
**Change Request:** User-reported bug: title background color picker doesn't update preview; flaky unit test failure.

## Context

Two issues: (1) selecting a new background color for the Title in the ExportPanel did not change the preview, and (2) `TitleMetricsCacheTests.titleMetricsInvalidatedByFontFamilyChange()` failed intermittently in the full test suite but passed in isolation.

## Changes

### Bug 1: Title background color not updating preview

**Root cause (layer 1):** `@Bindable` bindings to nested struct properties (e.g., `$viewModel.titleStyle.backgroundColor`) can bypass the `titleStyle.didSet` observer in `@Observable` classes. The SwiftUI observation system tracks nested mutations directly without invoking the property-level `didSet`, so `updatePreview()` was never called.

**Fix (layer 1):** Added explicit setter methods in `CollageViewModel`:
- `setTitleBackgroundColor(_:)` — sets color, registers undo, calls `updateTitleImage()` or `updatePreview()`, debounced save
- `setTitleFontColor(_:)` — same pattern
- `setTitleAlignment(_:)` — same pattern
- `setTitleShowBackground(_:)` — same pattern

Updated `ExportPanel.swift` to wrap each binding with `Binding(get:set:)` that calls the explicit setter instead of using direct `$viewModel.titleStyle.*` bindings.

**Root cause (layer 2):** After the setter fix, `updateTitleImage()` was being called correctly, but the view still didn't re-render. The `titleImage` computed property on `CollageViewModel` delegates to `previewManager.titleImage`. When `PreviewManager` updates `titleImage` asynchronously, `CollageViewModel`'s `@Observable` system doesn't know the computed property has changed.

**Fix (layer 2):** Added `titleImageVersion` counter (same pattern as existing `cropMapVersion`):
- `titleImage` getter reads `titleImageVersion` first to establish observation dependency
- `updateTitleImage()` increments `titleImageVersion` to trigger view re-renders

**Additional fix:** `NSColorPickerView.updateNSView` now re-sets `well.target` and `well.action` to ensure the coordinator reference survives SwiftUI view updates.

### Bug 2: Flaky test `titleMetricsInvalidatedByFontFamilyChange()`

**Root cause:** All test suites shared `UserDefaults.standard` via `UserDefaultsPersistence`. The debounced save (300ms delay) from one test would persist state that the next test's `CollageViewModel` initializer would load, polluting the initial `titleStyle.fontFamily` value.

**Fix:** Each test suite now creates VMs with isolated `UserDefaults` suites (unique per-VM via UUID):
- `TitleMetricsCacheTests` — added `makeViewModel()` helper with UUID suite
- `CollageViewModelTests` — added `makeViewModel()` helper, updated all 20+ inline VM creations
- `ExportFlowTests` — added `makeViewModel()` helper, updated all 13 inline VM creations
- `CollagePerformanceTests` — added `makeViewModel()` helper, updated 2 inline VM creations

## Files Changed

- `ViewModel/CollageViewModel.swift` — 4 new setter methods, `titleImageVersion` counter, `titleImage` getter update, `updateTitleImage()` increment
- `Views/ExportPanel.swift` — 4 binding wrappers route through setters, `NSColorPickerView.updateNSView` target/action re-assignment
- `CollageMakerTests/TitleMetricsCacheTests.swift` — `makeViewModel()` with isolated UserDefaults
- `CollageMakerTests/CollageViewModelTests.swift` — `makeViewModel()` with isolated UserDefaults, all inline creations updated
- `CollageMakerTests/ExportFlowTests.swift` — `makeViewModel()` with isolated UserDefaults, all inline creations updated
- `CollageMakerTests/CollagePerformanceTests.swift` — `makeViewModel()` with isolated UserDefaults, all inline creations updated

## Build & Test

- Build: succeeded, zero warnings
- All unit tests passing (207 total, zero failures)

## Learnings

Two new learnings documented in `_agent_docs/learnings/`:
1. **@Observable version counter for async delegate mutations** — bridging `PreviewManager`'s async `titleImage` updates through `CollageViewModel`'s computed property
2. **@Bindable nested struct mutations bypass didSet** — explicit setter pattern for guaranteed side effects
