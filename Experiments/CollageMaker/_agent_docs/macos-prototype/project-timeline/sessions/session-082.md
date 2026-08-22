# Architectural Review Phase 2 Refactoring — Session 82

**Date:** 2026-06-04
**Plan:** `2026-06-04-architectural-review-fixes.md` Phase 2 (6 items)

## Context

Implemented Phase 2 of the architectural review fixes plan — 6 refactoring items targeting code duplication, DIP violations, and structural improvements.

## Changes

### 2.1 W-5: Extract `registerUndo` helper + refactor title setters

**CollageViewModel.swift** — Extracted `registerUndo<Value>(oldValue:actionName:restore:)` generic helper that consolidates the 3-line pattern (`guard !isInitializing`, `undoManager.registerUndo`, `setActionName`, `debouncedSave`) repeated across 11 `didSet` blocks. Added `applyTitleChange<Value>(at:oldValue:actionName:sideEffect:)` using `WritableKeyPath<TitleStyle, Value>` for undo restoration, plus `titleViewUpdate()` helper. Refactored 6 title setter methods from ~80 lines to ~50 lines.

### 2.2 W-2: Fix ExportManager DIP violation

**ExportManager.swift** — Refactored `export()` to accept pure parameters (`AssemblyConfig`, `[CGImage]`, `CGImage?`, `Double`) and return `ExportResult` enum (`.success(URL)`, `.cancelled`, `.failure(Error)`) instead of accepting and mutating `CollageViewModel`. **CollageViewModel.swift** — `exportCollage()` now owns `isProcessing` lifecycle via `beginProcessing()`/`endProcessing()` and handles `errorMessage`/`successMessage`.

### 2.3 W-8: Extract `cancelAllTasks()` in PreviewManager

**PreviewManager.swift** — Extracted 10-line `cancelAllTasks()` private method, eliminating duplicated task cancellation code between `clearAll()` and `cancelAll()`.

### 2.4 W-9: Extract `CTAttributedStringBuilder`

**TitleRendererCT.swift** — Extracted `CTAttributedStringBuilder.build()` struct that consolidates the ~40-line CFAttributedString creation sequence (create mutable, set paragraph style, loop runs for fonts, optional foreground color) shared between `TitleBoundsCT.compute()` and `TitleMetricsCT.prepare()`.

### 2.5 W-7: BackgroundConfig CGColor properties

**AssemblyConfig.swift** — Attempted to convert `backgroundColor`/`gradientStartCGColor`/`gradientEndCGColor` from stored to computed properties. **diff-review caught a regression:** computed properties evaluate `NSColor.cgColor` on background threads when `BackgroundConfig` crosses actor boundaries via `Task.detached` into `RenderScheduler`. Reverted to stored properties with corrected `@unchecked Sendable` safety comment documenting that CGColor values are captured at init time on MainActor.

### 2.6 W-3: Structured AssemblyConfig secondary init

**AssemblyConfig.swift** — Added `init(layout:title:background:canvasSize:)` convenience init for construction from pre-built sub-configs.

### Additional: Deleted `TitleMetricsTests.swift`

The test file referenced `TitleMetrics` (deleted in Phase 1), causing test target build failure.

## Bugs Discovered

1. **BackgroundConfig computed CGColor regression** — diff-review identified that `var backgroundColor: CGColor { color.cgColor }` would evaluate `NSColor.cgColor` on background threads. The safety comment claiming "CGColor computed properties are captured before crossing actor boundaries" was incorrect — the `NSColor` stored values cross the boundary, and the computed property evaluates `.cgColor` lazily on whatever thread accesses it. **Fix:** Reverted to stored `CGColor` properties, captured in `init` on MainActor.

2. **Swift memberwise init conflict** — When `BackgroundConfig` had all `let` stored properties plus computed properties, Swift synthesized a memberwise init that conflicted with the custom init defined in the extension. **Fix:** Moved init into the struct body alongside the `@unchecked Sendable` conformance.

## Build Status

**BUILD SUCCEEDED** — Zero warnings.

**ALL TESTS PASS** — 235+ tests pass.

## Files Changed

- `ViewModel/CollageViewModel.swift` — `registerUndo` helper, `applyTitleChange`/`titleViewUpdate` helpers, refactored 11 `didSet` blocks + 6 title setters, updated `exportCollage()`
- `ViewModel/ExportManager.swift` — `ExportResult` enum, new `export()` signature, removed VM mutations
- `Services/PreviewManager.swift` — `cancelAllTasks()` extraction
- `Services/TitleRendererCT.swift` — `CTAttributedStringBuilder` extraction, simplified `compute()` and `prepare()`
- `Models/AssemblyConfig.swift` — BackgroundConfig stored CGColor with safety comment, secondary init
- `CollageMakerTests/TitleMetricsTests.swift` — Deleted (referenced deleted type)
