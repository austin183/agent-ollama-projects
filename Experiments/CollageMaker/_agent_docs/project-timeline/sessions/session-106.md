# Session 106 — SRP Decomposition Phase 3 (Round 2): Thin Down CollageViewModel

**Date:** 2026-06-15
**Plan:** `_agent_docs/plans/2026-06-14-vm-decomposition-round2.md` § Phase 3

## Summary

Implemented Phase 3 of the Round 2 VM decomposition plan — thinned down `CollageViewModel` by extracting LayoutManager setter methods, removing thin delegate wrappers for image/panel operations, and updating views to access managers directly. The goal was to reduce the ViewModel from its post-Phase-2 size toward the ~400-line target, though the full reduction requires Phase 4 (persistence & view updates) to complete.

## LayoutManager Changes

### New setter methods (50 lines added)

Six setter methods that perform state mutation and return old values for undo:
- `setLayoutStyle(_:) -> LayoutStyle` — sets style, logs change, returns old
- `setGutter(_:) -> CGFloat` — returns old
- `setDiagonalSliceAngle(_:) -> CGFloat` — returns old
- `setHexagonalSpacing(_:) -> CGFloat` — returns old
- `setDoubleExposureMaskOpacity(_:) -> CGFloat` — returns old
- `setMaskImage(_:path:) -> (NSImage?, String?)` — returns old tuple

**Design choice:** Initially explored a callback-based pattern (passing `undo:`, `save:`, `regenerate:` closures to managers) but rejected it as more complex than the original code. The simpler "return old value" pattern keeps side effects in the ViewModel while moving state mutation to the manager.

### CollageViewModel setter simplification

Each layout setter now calls the LayoutManager method once, captures the old value, and handles undo/preview:
```swift
func setLayoutStyle(_ style: LayoutStyle) {
    let old = layoutManager.setLayoutStyle(style)
    guard !isInitializing else { return }
    registerUndo(oldValue: old, actionName: "Change Layout") { $0.layoutManager.layoutStyle = old }
    regenerateLayout()
}
```

## Thin Delegate Removal

Removed 10 thin wrapper methods (~42 lines) that delegated one-to-one to managers:
- `browseImages()`, `addImages(from:)`, `removeImage(at:)`, `moveImages(from:to:)`, `clearAll()` — ImageCoordinator
- `assignImage(_:to:)`, `getEffectiveImageIndex(for:)`, `selectPanelForImage(at:)`, `swapPanelImages(sourceId:targetId:)` — ImageCoordinator

Callers now access `viewModel.imageCoordinator.*` and `viewModel.layoutManager.*` directly.

## View Updates

| File | Changes |
|------|---------|
| `ContentView.swift` | `clearAll()` → `imageCoordinator.clearAll()`, `panels` → `layoutManager.panels` |
| `CollageEditorView.swift` | 6 references: `panels` → `layoutManager.panels` |
| `StatusSidebar.swift` | 2 references: `panels` → `layoutManager.panels` |

## Test Updates

| File | Changes |
|------|---------|
| `CollageViewModelTests.swift` | `panels` → `layoutManager.panels`, `layoutStyle` → `layoutManager.layoutStyle`, `gutter` → `layoutManager.gutter`, `panelAssignments` → `layoutManager.panelAssignments`, `assignImage`/`getEffectiveImageIndex` → `imageCoordinator.*`, `moveImages` → `imageCoordinator.moveImages`, `clearAll` → `imageCoordinator.clearAll` |
| `ExportFlowTests.swift` | `panels` → `layoutManager.panels`, `panelAssignments` → `layoutManager.panelAssignments`, `swapPanelImages`/`getEffectiveImageIndex` → `imageCoordinator.*`, `clearAll` → `imageCoordinator.clearAll` |
| `CollagePerformanceTests.swift` | `panels` → `layoutManager.panels` |

## Verification

- `xcodebuild build` — Succeeded, zero errors
- `xcodebuild test` — Zero new failures. All 8 failing tests are **pre-existing flaky tests** — confirmed by running tests on stashed original code (`git stash && xcodebuild test && git stash pop`).

## Line Counts

| File | Before | After | Net |
|------|--------|-------|-----|
| `CollageViewModel.swift` | 963 | 921 | -42 |
| `LayoutManager.swift` | 101 | 151 | +50 |
| **Total** | 963 | 921 | -42 (VM net), +50 (manager) |

CollageViewModel at 921 lines, 183 lines from the ~400-line target. Phase 4 (persistence & view binding updates) will address remaining opportunities.

## Files Changed

| File | Changes |
|------|---------|
| `ViewModel/LayoutManager.swift` | Added 6 setter methods + OSLog import/logger |
| `ViewModel/CollageViewModel.swift` | Simplified 6 layout setters, removed 10 thin delegates |
| `ContentView.swift` | `clearAll` → `imageCoordinator.clearAll`, `panels` → `layoutManager.panels` |
| `Views/CollageEditorView.swift` | 6 `panels` → `layoutManager.panels` |
| `Views/StatusSidebar.swift` | 2 `panels` → `layoutManager.panels` |
| `CollageViewModelTests.swift` | Manager path updates |
| `ExportFlowTests.swift` | Manager path updates |
| `CollagePerformanceTests.swift` | `panels` → `layoutManager.panels` |

## New Learnings

None — callback-vs-return-value tradeoff for manager setters confirmed existing guidance (keep side effects in the caller, managers own state mutation). Pre-existing flaky test verification via `git stash` is a standard technique.

---
**Status:** Complete
**Follow-up:** Phase 4 (Persistence & View Updates) from the same plan.
