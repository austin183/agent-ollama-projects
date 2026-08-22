# CollageMaker — Full Architectural Review

**Date:** 2026-06-02
**Scope:** Entire codebase (33 production files, 5,823 lines; 18 test files, 3,325 lines)

---

## Executive Summary

The CollageMaker architecture is **well-designed overall**. Services are behind protocols, actors provide thread-safe isolation, `@Observable` + `@MainActor` state management is idiomatic, and the test suite covers core logic thoroughly. The codebase demonstrates sophisticated patterns: generation-based stale result discard, debounced persistence, undo/redo integration, and strategy-pattern layout generation.

**Primary concerns:**
1. `CollageViewModel` at 998 lines is a god class that should be decomposed
2. AppKit mutation on the background render queue (title rendering bug)
3. Business logic embedded in Views (drop handling, crop math)
4. Significant testing gaps in Views, managers, and persistence migration

**Severity breakdown:** 1 Critical, 8 Warnings, 10 Suggestions

---

## Critical Findings

### C-1: AppKit Mutation on Background Render Queue — **Deferred to Round 21**

**Files:** `TitleMetrics.swift:8-21`, `CollageAssembler.swift:365-405`

`TitleMetrics.prepare()` creates and mutates `NSMutableAttributedString`, `NSMutableParagraphStyle`, and calls `FontMerger.merge()` (which manipulates `NSFont`). This is invoked from `CollageAssembler.drawTitle()`, which runs inside `scheduler.render {}` on the **background dispatch queue**. AppKit types are not thread-safe.

Additionally, `attributedString.draw(in:)` at `CollageAssembler.swift:404` walks AppKit internals on a background thread.

**Impact:** Undefined behavior. May work today but can crash or corrupt on any macOS version. Every preview render and export with a title exercises this path.

**Deferred to:** [`_agent_docs/change-requests/round-21.md`](../change-requests/round-21.md) — migrate title rendering from AppKit (`NSAttributedString.draw`, `boundingRect`) to pure CoreText (`CTFrameDraw`, `CTFramesetterSuggestFrameSize`) on the background render queue. Estimated effort: ~2 hours, ~120 lines of new code.

---

## Warnings

### W-1: CollageViewModel is a God Class (998 lines, 12+ responsibilities)

**File:** `CollageViewModel.swift`

The VM manages: image library, crop state, preview rendering, export, undo registration, debounced persistence, title configuration (7 setters), saliency orchestration, layout regeneration, panel assignment, scroll pan, and 7 separate debounce tasks.

Every property `didSet` repeats the same 3-4 step pipeline (guard, undo, save, preview) 10+ times. This is hard to test and maintain.

**Suggestion:** Extract:
- `LayoutManager` — owns layout regeneration, gutter, style changes
- `TitleConfigManager` — owns `TitleStyle` and all title setters
- `PropertyChangeHandler` — encapsulates the undo + save + preview pipeline

### W-2: Title Configuration Buried in ViewModel (lines 891-981)

**File:** `CollageViewModel.swift`

Seven dedicated setter methods (`setTitleFontFamily`, `setTitleFontSize`, etc.) each duplicate the undo + save + preview pattern. These 91 lines belong in a `@Observable final class TitleConfigManager`.

### W-3: Drop Handling Business Logic in ContentView (lines 270-324)

**File:** `ContentView.swift`

`handleDrop` contains ~55 lines of `NSItemProvider` parsing, UTType validation, and URL conversion. This is file-system + type-validation business logic in a SwiftUI View that cannot be unit-tested independently.

**Fix:** Extract `struct DropHandler { func loadImageURLs(from: [NSItemProvider]) async -> [URL] }`.

### W-4: Title Frame Math Duplicated (View vs Assembler)

**Files:** `CollageEditorView.swift:23-44`, `CollageAssembler.swift:365-405`

Title positioning math (anchor calculation, draw width, bounding box, baseline Y) appears identically in both the editor view (for hit testing) and the assembler (for rendering). A mismatch would cause the hit area to not align with the rendered title.

**Fix:** Extract `struct TitleLayout { func computeFrame(style: TitleStyle, metrics: TitleMetrics, canvasSize: CGSize) -> CGRect }`.

### W-5: Gesture-to-Crop Math in PanelCropEditor (lines 131-282)

**File:** `PanelCropEditor.swift`

~150 lines of coordinate transformation, aspect-ratio preservation, and clamping logic live in a View. This complex numerical business logic cannot be unit-tested without rendering SwiftUI.

**Fix:** Extract `struct OverlayCropCalculator { func cropFromDrag(...) -> CGRect }` as a pure, testable utility.

### W-6: LayoutStyle Factory Switch Violates OCP (lines 194-202)

**File:** `LayoutGenerator.swift`

```swift
func makeStrategy() -> LayoutStrategy {
    switch self {
    case .uniform: return UniformLayoutStrategy()
    case .hero: return HeroLayoutStrategy()
    case .mosaic: return MosaicLayoutStrategy()
    }
}
```

Adding a new layout style requires modifying this switch. For a 3-case enum this is low urgency, but worth noting for future extensibility.

### W-7: BackgroundStyle Switch Duplicated 3×

**File:** `CollageAssembler.swift:194-216, 261-286, 480-502`

The `switch config.background.style` block appears in `renderPreviewIntoContext`, `createBitmapContext`, and `renderBackground`. Adding a new background type requires modifying 3 switch statements.

**Fix:** Extract `protocol BackgroundRenderer` with concrete implementations per style.

### W-8: SaliencyAnalyzer.analyzeAll Provides Zero Parallelism

**File:** `SaliencyAnalyzer.swift:100-116`

`withThrowingTaskGroup` spawns concurrent tasks, but each calls `await self.analyze(cgImage)` — an actor-isolated method. Actor isolation serializes all entries, so tasks execute sequentially. The task group adds overhead without concurrency benefit.

**Fix:** Replace with a simple `for` loop, or extract Vision request logic into a non-actor-isolated helper.

---

## Suggestions

### S-1: Dead Initialization of ExportManager (line 35)

**File:** `CollageViewModel.swift`

```swift
var exportManager: ExportManager = ExportManager(assembler: CollageAssembler())
```

Creates an assembler + render scheduler + dispatch queue that is immediately overwritten in `init`. Remove the default value.

### S-2: @unchecked Sendable Needs Full Justification

**Files:** `AssemblyConfig.swift`, `TitleStyle.swift`, `CollageAssembler.swift`

Five types are marked `@unchecked Sendable`. `NSAttributedString` has a comment justifying its usage. `NSColor` (embedded in `BackgroundConfig` and `TitleStyle`) has no comment. Add justifications or refactor to pass only Sendable portions across boundaries.

### S-3: 7 Debounce Tasks Could Be Consolidated

**File:** `CollageViewModel.swift`

Seven separate `Task<Void, Never>?` variables manage debouncing. A generic `DebounceScheduler<T>` actor could consolidate this pattern.

### S-4: Undo Registration Scattered Across 3 Files

**Files:** `CollageViewModel.swift`, `CollageEditorView.swift`

Views access `viewModel.undoManager` directly. Create an `UndoScope` helper to encapsulate `beginGrouping/registerUndo/setActionName/endGrouping`.

### S-5: UserDefaultsPersistence Coupled to ViewModel

**File:** `UserDefaultsPersistence.swift:64-85`

Persistence accesses `CollageViewModel` properties directly. Define `protocol Persistable` and work with `PersistenceBundle` only.

### S-6: TitleStyle Direct Mutation Bypasses Setter Side Effects

`TitleStyle` is a struct. Direct property mutation (`vm.titleStyle.fontColor = .red`) bypasses the `didSet` on the `titleStyle` property, skipping undo registration and preview updates. The code works around this with dedicated setter methods, but the pattern is fragile.

### S-7: isInitializing Flag Anti-Pattern (14+ sites)

**File:** `CollageViewModel.swift`

Consider two-phase init or a `withMutation` pattern to suppress side effects during deserialization.

### S-8: DispatchWorkItem vs Task Inconsistency

**File:** `CollageViewModel.swift:738-751`

`scrollCommitTimer` uses `DispatchWorkItem` while the rest of the codebase uses `Task`. Consider `Task { @MainActor ... }` with `Task.sleep` for consistency.

### S-9: handleDrop URL Parsing is Fragile (line 304)

**File:** `ContentView.swift`

```swift
url = URL(fileURLWithPath: String(urlStr.dropFirst(7)))
```

The `dropFirst(7)` hack for `file://` prefix is brittle. Use `URL(string:)` which handles the scheme properly.

### S-10: No Error Feedback for Failed Export

**File:** `ExportManager.swift`

When assembly returns `nil` (rendering failed), the file simply won't be written with no user-visible error. Set `errorMessage` and present feedback.

---

## Testing Review

### Coverage Summary

| Category | Coverage | Notes |
|----------|----------|-------|
| Core math (Fit, Layout, Crop, Saliency) | ~95% | Well-covered with edge cases |
| Services (Assembler, Preview, Render) | ~90% | Concurrent stress tests present |
| ViewModel state transitions | ~80% | Missing undo/redo verification |
| Persistence | ~60% | Legacy migration untested |
| Managers (ImageLibrary, Export) | ~10% | Critical gap |
| View logic | ~15% | `detectDragMode`, `normalizeForEditor` untested |
| Integration | ~30% | No full-pipeline test |

### P0 — Missing Tests (Bug Prevention)

1. **`ImageLibraryManagerTests`** — `moveImages()` with custom order permutations, `addImages()` error paths
2. **`UserDefaultsPersistence` migration tests** — Legacy key fallback paths
3. **`UserDefaultsPersistence` background image tests** — Missing file, invalid data
4. **`ExportManager` tests** — Mock assembler, error/cancellation paths

### P1 — Missing Tests (Reliability)

5. **`CropPreviewView.detectDragMode()` tests** — Pure function, all 5 drag modes
6. **Undo/redo integration tests** — Verify state restoration after undo
7. **`normalizeForEditor()` tests** — Font/alignment normalization

### P2 — Test Hygiene

8. Replace `Task.sleep()` with `awaitPendingTasks()` in `ExportFlowTests` and `CollagePerformanceTests`
9. Rename `PanelCropEditorTests` to `CropMathTests` (it tests `CropManager`, not the view)
10. UI tests are Xcode boilerplate stubs — add at least one meaningful interaction test

### Test Quality Strengths

- Isolated `UserDefaults` suites prevent cross-test contamination
- Protocol-based mocks (`MockSaliencyAnalyzer`, `TrackingAssembler`) are well-designed
- `@Suite(.serialized)` and `AppKitInit` ensure proper test environment
- Concurrent assembler stress tests and generation-based stale discard tests are sophisticated

---

## Strengths

- **Protocol hierarchy** for `CollageAssembly` enables thorough mocking
- **Generation-based stale result discard** in `PreviewManager` is a sophisticated, correct pattern
- **Proper concurrency model**: actors for shared state, `@MainActor` for UI, `Task.detached` for background
- **Comprehensive OSLog** instrumentation with appropriate categories
- **Undo/redo** for all user actions
- **Debounced persistence** avoids excessive `UserDefaults` writes
- **Accessibility labels** throughout the UI
- **Well-designed models**: value types with `Identifiable`, `Equatable`, `Codable`
- **Cache invalidation** via `LayoutKey` struct is elegant and correct

---

## Recommendation

**Approve with changes.** The architecture is fundamentally sound. The critical finding (C-1, AppKit on background queue) should be fixed before the next release. The 8 warnings are maintainability concerns that should be addressed incrementally — the highest ROI is decomposing `CollageViewModel` and extracting business logic from Views.
