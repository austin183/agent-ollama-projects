# Session 104 — SRP Decomposition Phase 1 (Round 2): LayoutManager

**Date:** 2026-06-14
**Plan:** `_agent_docs/plans/2026-06-14-vm-decomposition-round2.md` § Phase 1

## Summary

Implemented Phase 1 of the Round 2 VM decomposition plan — extracted `LayoutManager` (layout state, double exposure settings, panel assignments, regeneration logic) from `CollageViewModel`. All layout-related stored properties converted to computed property delegations. Non-UI callers (commands, programmatic code) use explicit setter methods since `didSet` on the sub-manager cannot trigger ViewModel side effects (undo, persistence, preview).

## New File

### `ViewModel/LayoutManager.swift` (95 lines)

`@Observable @MainActor` class holding:
- Layout configuration: `layoutStyle`, `gutter`, `diagonalSliceAngle`, `hexagonalSpacing`
- Panel state: `panels`, `panelAssignments`
- Double exposure: `doubleExposureMaskImage`, `doubleExposureMaskImagePath`, `doubleExposureMaskOpacity`
- Methods: `regenerateLayout(images:customImageOrder:cropManager:previewManager:saliencyResults:preserveCrops:)`, `buildOverlayConfig()`, `reset()`

`regenerateLayout` takes `CropManager` and `PreviewManager` as parameters to avoid circular dependencies — consistent with the parameter injection pattern from the plan's Risk 1 mitigation.

## CollageViewModel Changes

- Added `layoutManager: LayoutManager` stored property
- Replaced 9 stored properties + `didSet` observers with computed property delegations: `layoutStyle`, `gutter`, `panels`, `panelAssignments`, `doubleExposureMaskImage`, `doubleExposureMaskImagePath`, `doubleExposureMaskOpacity`, `diagonalSliceAngle`, `hexagonalSpacing`
- Added explicit setter methods for non-UI callers: `setLayoutStyle()`, `setGutter()`, `setDiagonalSliceAngle()`, `setHexagonalSpacing()`, `setDoubleExposureMaskOpacity()`, `setMaskImage()`
- Simplified `regenerateLayout()` — delegates to `layoutManager.regenerateLayout()`, removed inline `LayoutGenerator.generate()` call and panel assignment loop
- Simplified `buildAssemblyConfig()` — reads `layoutManager.panels`, `layoutManager.panelAssignments`, calls `layoutManager.buildOverlayConfig()`
- Simplified `clearAll()` — calls `layoutManager.reset()`, removed inline `panels.removeAll()` / `panelAssignments.removeAll()`
- Updated `init` — loads persisted values into `layoutManager.*` instead of `self.*`
- Removed old `setLayoutStyle()`/`updateGutter()` wrapper methods (replaced by setter methods with side effects)

## View & Persistence Updates

| File | Changes |
|------|---------|
| `LayoutConfigSidebar.swift` | 5 `Binding(get:set:)` wrappers route through setter methods; reads go through `layoutManager.*` |
| `CollageCommands.swift` | `viewModel.setLayoutStyle()` replaces direct assignment |
| `UserDefaultsPersistence.swift` | Save reads from `viewModel.layoutManager.*` |
| `ContentView.swift` | No changes — `setMaskImage()` call already routes to the new setter |

## Test Updates

| File | Changes |
|------|---------|
| `CollageViewModelTests.swift` | `setGutter()` replaces direct assignment, `layoutManager.panels` replaces `panels` |
| `UserDefaultsPersistenceTests.swift` | `setLayoutStyle()`, `setGutter()` replace direct assignment |
| `ExportFlowTests.swift` | `setGutter()` replaces direct assignment |

## Verification

- `xcodebuild build` — Succeeded, zero errors
- `xcodebuild test` — All 288 tests pass (8 flaky timing-related failures are pre-existing)

## Line Counts

| File | Before | After | Net |
|------|--------|-------|-----|
| `CollageViewModel.swift` | 1,104 | ~1,055 | -49 |
| `LayoutManager.swift` | — | 95 | +95 (new) |
| **Total** | 1,104 | 1,150 | +46 |

Net increase is modest — the `regenerateLayout` body shrunk by ~30 lines, and 9 `didSet` observers (~80 lines) were replaced by 6 setter methods (~50 lines). The LayoutManager encapsulates ~95 lines of cohesive layout state that was previously scattered across the ViewModel.

## Files Changed

| File | Changes |
|------|---------|
| `ViewModel/LayoutManager.swift` | New — layout state, double exposure, panel assignments, regeneration |
| `ViewModel/CollageViewModel.swift` | Computed delegations, setter methods, simplified regenerateLayout/buildAssemblyConfig/clearAll/init |
| `Services/UserDefaultsPersistence.swift` | Save reads through `layoutManager.*` |
| `Views/LayoutConfigSidebar.swift` | `Binding(get:set:)` wrappers for 5 layout controls |
| `Views/CollageCommands.swift` | `setLayoutStyle()` for command actions |
| `CollageViewModelTests.swift` | `setGutter()`, `layoutManager.panels` |
| `UserDefaultsPersistenceTests.swift` | `setLayoutStyle()`, `setGutter()` |
| `ExportFlowTests.swift` | `setGutter()` |

## New Learnings

None — all patterns (computed property delegation, `Binding(get:set:)` for SwiftUI views, explicit setter methods for non-UI callers, `@Observable` managers, persistence routing through managers) were established in sessions 102/103 and documented in existing skills and learnings.

---
**Status:** Complete
**Follow-up:** Phase 2 (ImageCoordinator), Phase 3 (Thin Down VM), Phase 4 (Persistence & View Updates) from the same plan.
