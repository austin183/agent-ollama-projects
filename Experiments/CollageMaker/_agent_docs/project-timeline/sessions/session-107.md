# Session 107 — SRP Remediation Phase 2: Break Circular Dependencies (C1)

**Date:** 2026-06-15
**Plan:** `_agent_docs/plans/2026-06-15-srp-remediation-plan.md` § Phase 2

## Summary

Implemented Phase 2 of the SRP remediation plan — broke circular dependencies between managers and CollageViewModel by introducing two minimal protocols (`PreviewUpdatable`, `ImageCoordinationTarget`). Managers now depend on protocol abstractions instead of the concrete ViewModel, eliminating the circular ownership graph identified in the Jasper review as a Critical finding (C1).

## New Protocol Files

### `ViewModel/PreviewUpdatable.swift` (new, 14 lines)

Protocol for title/background preview updates. Five methods:
- `updateTitleImage(attrString:style:canvasSize:)` — delegates to PreviewManager
- `incrementTitleVersion()` — increments `titleImageVersion` for @Observable async tracking
- `updateBackground(config:canvasSize:backgroundImage:previewSize:)` — delegates to PreviewManager
- `cancelDebouncer(id:)` — cancels stale debounced tasks
- `debouncedSave()` — triggers debounced persistence

### `ViewModel/ImageCoordinationTarget.swift` (new, 17 lines)

Class protocol (`: AnyObject`) for image coordination. Required `AnyObject` conformance because `UndoManager.registerUndo(withTarget:)` requires a class type for its target parameter (see learnings). Members:
- `beginProcessing()` / `endProcessing()` / `var isProcessing: Bool` — processing state
- `updatePreview()` / `updateAllPanelPreviews()` / `updatePanelPreview(panelId:)` — rendering
- `resetCrop(panelId:)` — crop reset with undo
- `var selectedPanelId: UUID?` / `var errorMessage: String?` / `var customImageOrder: [Int]` — state accessors
- `regenerateLayout()` — triggers layout regeneration
- `cancelDebouncer(id:)` — task cancellation

## Manager Refactors

### TitleManager (2.4)

- `updateImage(viewModel: CollageViewModel)` → `updateImage(updater: PreviewUpdatable)`
- `finishDrag(viewModel: CollageViewModel)` → `finishDrag(updater: PreviewUpdatable)`

### BackgroundManager (2.5)

- `updateBackground(viewModel: CollageViewModel)` → `updateBackground(updater: PreviewUpdatable)`

### ImageCoordinator (2.6)

- `private let viewModel: CollageViewModel` → `private let target: ImageCoordinationTarget`
- All VM calls go through `target`
- **Undo closures use `self` as target** — `UndoManager.registerUndo(withTarget: self)` instead of `(withTarget: target)`, since `target` is a protocol reference and `UndoManager` needs a concrete class. Closures access `self.target.property` for mutations.
- Removed direct `viewModel.backgroundManager.*`, `viewModel.titleManager.*`, `viewModel.exportManager.*` references from `clearAll()` — those cross-manager resets now belong to the VM (Phase 3.2)

## CollageViewModel Conformance (2.3)

- `extension CollageViewModel: PreviewUpdatable` — delegates to existing `previewManager`, `debouncer`, `persistence`
- `extension CollageViewModel: ImageCoordinationTarget` — adds `regenerateLayout()` no-arg wrapper
- Init updated: `ImageCoordinator(target: self, ...)` replaces `ImageCoordinator(viewModel: self, ...)`

## Call Site Updates (2.7)

All `viewModel: self` parameters updated to `updater: self` across:
- `CollageViewModel.swift` (title setter methods, `updateBackground()`, `finishTitleDrag()`, layered mode paths)
- `ImageCoordinator.swift` (undo closures, saliency callbacks)

## Verification

- `xcodebuild build` — Succeeded, zero errors
- `xcodebuild test` — All 296 tests passed, zero failures
- `bash script/build_and_run.sh --verify` — Build succeeded, app launched

## Files Changed

| File | Changes |
|------|---------|
| `ViewModel/PreviewUpdatable.swift` | New file — protocol definition |
| `ViewModel/ImageCoordinationTarget.swift` | New file — class protocol definition |
| `ViewModel/CollageViewModel.swift` | Protocol conformance extensions, `target:` init param, `updater:` call sites |
| `ViewModel/TitleManager.swift` | `viewModel:` → `updater: PreviewUpdatable` |
| `ViewModel/BackgroundManager.swift` | `viewModel:` → `updater: PreviewUpdatable` |
| `ViewModel/ImageCoordinator.swift` | Full rewrite: `viewModel` → `target`, undo closures use `self` |

## New Learnings

- `undomanager-anyobject-protocol-target.md` — UndoManager.registerUndo requires AnyObject, workaround for protocol targets

---
**Status:** Complete
**Follow-up:** Phase 3 (Decompose ImageCoordinator) from the same plan.
