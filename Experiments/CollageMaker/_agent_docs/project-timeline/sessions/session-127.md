# Session 127 — Review Fixes Phase 4

**Date:** 2026-06-23
**Plan:** `2026-06-23-review-fixes-plan.md` Phase 4

## Summary

Implemented Phase 4 (larger refactors) of the review fixes plan: R4 (TitleTextData to Models), R6 (gesture types out of Models), R10 (ColorPair helper), R3 (protocol extraction), Victoria (coordinate math to Managers), and R1/R12 (gesture builder extraction). All 6 items completed, build succeeded, all 443 tests passed. diff-review-g31: clean (no issues found).

## Changes

### R4 — Move TitleTextData to Models layer

**Files:** New `Models/TitleTextData.swift`, `Services/TitleRendererCT.swift`

Bug: `TitleTextData` and `TitleTextRun` defined in a Services file but used by `TitleConfig` in Models. This inverted the expected layering (Models should not depend on Services).

Fix: Created `Models/TitleTextData.swift` with `TitleTextData`, `TitleTextRun` structs and `@MainActor static func extract(from:)`. Removed from `TitleRendererCT.swift`. No import changes needed (same module).

### R6 — Move gesture types out of Models

**Files:** `Models/TitleStyle.swift`, `ViewModel/TitleManager.swift`

Bug: `TitleResizeEdge` and `TitleHitResult` are purely UI interaction types defined in the Models layer with no business logic.

Fix: Moved both enums from `TitleStyle.swift` to `TitleManager.swift` (where they're already consumed).

### R10 — ColorPair helper for BackgroundConfig

**Files:** `Models/AssemblyConfig.swift`, `Services/BackgroundRenderer.swift`, `Services/CollageAssembler.swift`, `ViewModel/CollageViewModel.swift`, `CollageMakerTests/BackgroundManagerTests.swift`

Issue: `BackgroundConfig` stored both `NSColor` and `CGColor` representations of the same values (6 properties for 3 logical colors), doubling the surface area for inconsistency.

Fix: Created `ColorPair: @unchecked Sendable` with `nsColor` and `CGColor` properties. Updated `BackgroundConfig` to use `ColorPair` for `color`, `gradientStartColor`, `gradientEndColor`. Init still accepts `NSColor` values and constructs `ColorPairs` internally. Updated all consumers to access `.color.cgColor`, `.gradientStartColor.cgColor`, `.gradientEndColor.cgColor`. Updated test assertions and undo restoration in `CollageViewModel`.

### R3 — Add protocols for DropHandler, RenderScheduler, PreviewManager

**Files:** `Services/DropHandler.swift`, `Services/RenderScheduler.swift`, `Services/PreviewManager.swift`

Issue: Three service classes lacked protocol abstractions, making it harder to inject mocks in tests.

Fix:
- `DropHandling` protocol with `loadImageURLs(from:)` method, `DropHandler: DropHandling` conformance
- `RenderScheduling` protocol with `render<T>(_:)` method, `RenderScheduler: RenderScheduling` conformance
- `PreviewManagement` protocol with all public properties and methods, `PreviewManager: PreviewManagement` conformance

### Victoria — Move coordinate math from Views to Managers

**Files:** `Views/CollageEditorView.swift`, `ViewModel/CollageViewModel.swift`

Issue: The view body contained inline `hitPanel` logic and `panelGeometries` computation — coordinate math that belongs in the ViewModel layer.

Fix: Added `hitPanel(at:previewSize:)` and `panelGeometries` computed property to `CollageViewModel`. Updated `CollageEditorView` to delegate all hit testing to `viewModel.hitPanel(...)`. Removed inline `hitPanel` method and `panelGeometries` computation from the view. Removed unused `titleMinWidth` and `layoutTitleFrame` computed properties.

### R1/R12 — Extract gesture logic from CollageEditorView

**Files:** New `Views/EditorGestureBuilders.swift`, `Views/CollageEditorView.swift`

Issue: `CollageEditorView` body contained ~140 lines of inline gesture closures (title drag, panel swap, pinch) mixing gesture state management with view construction.

Fix: Created three `@MainActor` struct builders:
- `TitleDragGestureBuilder` — title hit test, drag offset tracking, resize computation, undo registration
- `PanelSwapGestureBuilder` — panel hit test, source/target tracking, swap execution
- `PinchGestureBuilder` — pinch panel targeting, magnification forwarding, live preview throttling

Each builder takes `GestureCoordinator`, `CollageViewModel`, and context parameters, producing a `.build() -> some Gesture`. View body reduced from ~236 lines to ~126 lines.

## Verification

- Build: succeeded, zero errors
- Tests: all 443 tests passed
- diff-review-g31: clean, no issues found

## New Learnings

None. All patterns exercised in this session are already documented:
- Protocol extraction for testability → `rendering-lifecycle-extraction-learnings.md`
- Gesture targeting via parent-level hit testing → `swiftui-gesture-targeting-learnings.md`
- @Observable body re-evaluation cascades → `observable-body-re-evaluation-cascade.md`
- @MainActor struct builders → skill reference `references/state/observable-bindable.md`

---
**Status**: Closed
**Follow-up**: All review fix phases (1-4) now complete.
