# CollageMaker — Full Architectural Review

**Date:** 2026-06-04
**Scope:** Entire codebase (41 production files, ~7,500 lines; 18 test files, ~3,400 lines)
**Prior review:** 2026-06-02 (findings C-1 through S-10 carried forward; this review focuses on new findings and updated assessment)

---

## Executive Summary

CollageMaker is a **well-architected** macOS SwiftUI app with strong conventions across all layers. The protocol-based dependency injection, actor isolation for Vision/CoreGraphics, `@Observable` + `@MainActor` state management, and generation-based stale-task discard are all sophisticated patterns executed correctly. The test suite provides solid coverage of core logic with ~59% test-to-code ratio.

**What improved since 2026-06-02:**
- CoreText migration (C-1 from prior review) completed — `TitleRendererCT` eliminates AppKit mutation on background threads
- `RenderScheduler` actor added for `NSGraphicsContext.current` serialization
- `PreviewManager` extracted with generation-based stale-result discard
- `CropManager` extracted as pure state machine
- Learning documentation expanded to 55 files

**Primary concerns (new):**

| # | Severity | Finding |
|---|----------|---------|
| 1 | Critical | `isProcessing` race condition — dual writers without coordination |
| 2 | Critical | `TitleMetrics.swift` is dead code after CoreText migration |
| 3 | Warning | `CollageViewModel` at 1,042 lines — god class |
| 4 | Warning | `ExportManager` mutates ViewModel state directly (DIP violation) |
| 5 | Warning | `AssemblyConfig` 15-parameter constructor contradicts nested struct design |
| 6 | Warning | `CollageAssembler` 428-line monolith despite protocol hierarchy |
| 7 | Warning | Property change pipeline duplicated 12+ times in ViewModel |
| 8 | Warning | Business logic in Views (drop handling, gesture math, undo registration) |
| 9 | Warning | `PreviewManager.clearAll()` / `cancelAll()` duplicate cancellation logic |
| 10 | Warning | `ScrollPanView` force cast |

**Severity breakdown:** 2 Critical, 10 Warnings, 18 Suggestions

---

## Critical Findings

### C-1: `isProcessing` Race Condition — Dual Writers Without Coordination

**Files:** `ExportManager.swift:30,32` / `CollageViewModel.swift:598-599`

Both `ExportManager.export()` and `CollageViewModel.analyzeSaliency()` independently set and clear `viewModel.isProcessing`:

```swift
// ExportManager.swift:30-32
viewModel.isProcessing = true
// ...
defer { viewModel.isProcessing = false; isExporting = false }

// CollageViewModel.swift:598-599
isProcessing = true
defer { isProcessing = false }
```

If a user triggers export while saliency analysis is running (or vice versa), the `defer` from the first operation can clear `isProcessing` while the second is still active. The UI status in `ContentView.swift:209-227` would incorrectly show "Ready".

**Impact:** UI shows misleading state; user could trigger overlapping operations thinking the app is idle.

**Fix:** Replace the boolean with a reference-counted processing tracker:

```swift
private var processingCount = 0
var isProcessing: Bool { processingCount > 0 }

func beginProcessing() { processingCount += 1 }
func endProcessing() { processingCount = max(0, processingCount - 1) }
```

---

### C-2: `TitleMetrics.swift` Is Dead Code After CoreText Migration

**File:** `TitleMetrics.swift:1-36`

The AppKit-based `TitleMetrics` struct is **completely unused**. The CoreText migration replaced all callers with `TitleMetricsCT` and `TitleBoundsCT`. The only remaining references are its own definition and a doc comment in `TitleRendererCT.swift:217`.

**Impact:** Dead code ships in the binary, adds confusion for future maintainers, and obscures migration completion.

**Fix:** Delete `TitleMetrics.swift`. Update the doc comment in `TitleRendererCT.swift:217`.

---

## Warnings

### W-1: `CollageViewModel` Is a God Class (1,042 lines, 15+ responsibilities)

**File:** `CollageViewModel.swift`

The VM manages: image library, crop state, preview rendering, export, undo registration, debounced persistence, title configuration (7+ setters), saliency orchestration, layout regeneration, panel assignment, scroll pan, and 7+ separate debounce tasks.

Every property `didSet` repeats the same 3-4 step pipeline (guard, undo, save, preview) 12+ times. Title setters (lines 935-1025) each duplicate undo + save + preview logic.

**Impact:** Hard to test in isolation. Any change to the property-change pipeline requires editing 12+ locations.

**Suggestion:** Extract:
- `LayoutManager` — owns layout regeneration, gutter, style changes
- `TitleConfigManager` — owns `TitleStyle` and all title setters
- `ProcessingTracker` — owns `isProcessing` with reference counting (fixes C-1)

### W-2: Dependency Inversion Violation — Managers Mutate ViewModel State Directly

**File:** `ExportManager.swift:30,32,78`

`ExportManager` directly mutates `viewModel.isProcessing` and `viewModel.errorMessage`. While the assembler is injected via DI, the export method takes a whole `CollageViewModel` and reaches into its internals.

**Impact:** Managers become untestable in isolation. State mutation paths are scattered and hard to audit.

**Fix:** Change `export(viewModel:)` to `export(config: AssemblyConfig, cgImages: [CGImage], ...) async -> ExportResult` where `ExportResult` is an enum. The ViewModel wraps the call and manages its own state.

### W-3: `AssemblyConfig` Constructor Has 15 Parameters

**File:** `AssemblyConfig.swift:60-96`

The constructor takes 15 parameters, then internally constructs 3 nested structs (`LayoutConfig`, `TitleConfig`, `BackgroundConfig`). This **flattened API contradicts its own internal structure**.

**Impact:** Error-prone construction, hard to call correctly, any change to a nested config requires changing the public API.

**Fix:** Provide a secondary initializer:

```swift
init(
    layout: LayoutConfig,
    title: TitleConfig,
    background: BackgroundConfig,
    canvasSize: CGSize
) {
    self.layout = layout
    self.title = title
    self.background = background
    self.canvasSize = canvasSize
}
```

### W-4: `CollageAssembler` Combines 5 Rendering Concerns (428 lines)

**File:** `CollageAssembler.swift`

Despite the well-designed protocol hierarchy (`CollageRenderer`, `PanelRenderer`, `BackgroundRenderer`, `TitleRenderer`), the **single conforming class** bundles all concerns: full collage assembly, preview assembly, background rendering, panel drawing, and title rendering.

**Impact:** Cannot be partially mocked for integration tests. Any change to one rendering concern risks another.

**Fix:** Consider injecting sub-renderers:

```swift
final class CollageAssembler: CollageAssembly {
    private let backgroundRenderer: BackgroundDrawing
    private let panelDrawer: PanelDrawing
    private let titleDrawer: TitleDrawing
    private let scheduler: RenderScheduler
}
```

### W-5: Property Change Pipeline Duplicated 12+ Times

**File:** `CollageViewModel.swift:134-307`

Every configurable property repeats the same `didSet` pipeline:

```swift
didSet {
    guard !isInitializing else { return }
    undoManager.registerUndo(withTarget: self) { }
    undoManager.setActionName("...")
    debouncedSave()
    updatePreview() / regenerateLayout()
}
```

This is ~120 lines of near-identical boilerplate.

**Fix:** Extract a helper:

```swift
private func applyChange<Value>(oldValue: Value, actionName: String, sideEffect: @escaping () -> Void) {
    guard !isInitializing else { return }
    undoManager.registerUndo(withTarget: self) { /* restore oldValue */ }
    undoManager.setActionName(actionName)
    debouncedSave()
    sideEffect()
}
```

### W-6: Business Logic Embedded in Views

**Files:** `CollageEditorView.swift:150-234` / `ContentView.swift:270-324` / `PanelCropEditor.swift:131-282`

- **Title drag/resize** (~80 lines): Hit detection, coordinate conversion, width clamping, position normalization embedded in gesture closures
- **Drop handling** (~55 lines): `NSItemProvider` parsing, UTType validation, URL conversion in `ContentView`
- **Crop math** (~150 lines): Coordinate transformation, aspect-ratio preservation, clamping in `PanelCropEditor`

**Impact:** Untestable without SwiftUI view rendering. Complex numerical logic mixed with gesture state management.

**Fix:** Extract pure computation structs:
- `struct TitleDragHandler { func handleDrag(...) -> TitleStyle? }`
- `struct DropHandler { func loadImageURLs(from: [NSItemProvider]) async -> [URL] }`
- Move coordinate math to `CropManager` or a new `CropCoordinateMath` struct

### W-7: `BackgroundConfig` Stores Redundant NSColor + CGColor Pairs

**File:** `AssemblyConfig.swift:21-52`

```swift
struct BackgroundConfig {
    let color: NSColor
    let gradientStartColor: NSColor
    let gradientEndColor: NSColor
    // ...
    let backgroundColor: CGColor          // derived
    let gradientStartCGColor: CGColor     // derived
    let gradientEndCGColor: CGColor       // derived
}
```

The `CGColor` properties are derived in the initializer via `.cgColor`. This doubles memory usage and creates a stale data risk.

**Fix:** Store only `NSColor` and derive `CGColor` via computed properties.

### W-8: `PreviewManager.clearAll()` and `cancelAll()` Duplicate Cancellation Logic

**File:** `PreviewManager.swift:172-204`

Both methods contain identical task cancellation sequences (5 lines each). Adding a new task property requires updating 2 sites.

**Fix:** Extract `private func cancelAllTasks()` and have both methods call it.

### W-9: `TitleBoundsCT` and `TitleMetricsCT` Duplicate AttributedString Construction

**File:** `TitleRendererCT.swift:54-215`

Both `TitleBoundsCT.compute()` and `TitleMetricsCT.prepare()` contain near-identical CoreFoundation sequences: create mutable attributed string, apply paragraph style, iterate runs, apply font attributes, create framesetter.

**Impact:** ~30 lines of duplicated boilerplate. Bug fixes must be applied to both.

**Fix:** Extract `struct CTAttributedStringBuilder { static func build(...) -> CFAttributedString }`.

### W-10: Force Cast in `ScrollPanView.updateNSView`

**File:** `ScrollPanView.swift:20`

```swift
let view = nsView as! ScrollCaptureView
```

If SwiftUI recreates the underlying view, the force cast crashes.

**Fix:** Use `guard let view = nsView as? ScrollCaptureView else { return }`.

---

## Suggestions

### S-1: `GestureCoordinator` Uses `@ObservableObject` Instead of `@Observable`

**File:** `GestureCoordinator.swift:6`

The sole `ObservableObject`/`@Published` class in an otherwise `@Observable` codebase. Requires `@StateObject` in `CollageEditorView`.

**Fix:** Convert to `@Observable final class GestureCoordinator`.

### S-2: `exportManager` Double-Initialization

**File:** `CollageViewModel.swift:88,385`

```swift
var exportManager: ExportManager = ExportManager(assembler: CollageAssembler())  // line 88
// ...
self.exportManager = ExportManager(assembler: assembler)  // line 385
```

The property-level initializer creates a `CollageAssembler()` that is immediately discarded.

**Fix:** Remove the default value from the property declaration.

### S-3: Title Bounds Cache Computed Synchronously on Main Thread

**File:** `CollageViewModel.swift:44-86`

`ensureTitleBounds()` calls `TitleBoundsCT.compute()` synchronously on `@MainActor`. Complex attributed strings with multiple font runs can cause main-thread jank.

**Fix:** Offload to a background Task and update cache asynchronously.

### S-4: `NSColorPickerView` Duplicated in Two Files

**Files:** `ExportPanel.swift:264-299` / `SettingsView.swift`

Both define `NSViewRepresentable` wrappers for `NSColorWell` with nearly identical `makeNSView`/`updateNSView`/`Coordinator` patterns.

**Fix:** Extract a shared `ColorWellView` representable.

### S-5: `@unchecked Sendable` on Config Structs Lacks Justification Comments

**Files:** `AssemblyConfig.swift:10, 19, 33, 99`

Four `@unchecked Sendable` conformances with no comments explaining the safety justification. `BackgroundConfig` is the riskiest (contains `NSColor`).

**Fix:** Add justification comments or convert `BackgroundConfig` to store only `CGColor` (see W-7).

### S-6: `panelFrames` Computed Twice Per Frame

**File:** `CollageEditorView.swift:38,336`

`panelAt` is called from both `.onTapGesture` and `DragGesture`, recomputing the entire frame map each time.

**Fix:** Precompute `panelFrames` once in `body` and pass into `panelAt`.

### S-7: Undo Registration in View Layer

**File:** `CollageEditorView.swift:130-141,220-226,291-307`

The View layer registers undo actions for title drag and pinch zoom. The View shouldn't know about `undoManager`.

**Fix:** Move all undo registration into ViewModel methods.

### S-8: Search Filtering Logic Duplicated

**Files:** `ContentView.swift:20-28` / `ImagePickerGrid.swift:10-18`

Both views implement identical search filtering with `localizedCaseInsensitiveContains`.

**Fix:** Extract `extension Array where Element == ImageItem { func filtered(by query: String) -> ... }`.

### S-9: `ImageItem` Stores Both `NSImage` and `CGImage`

**File:** `ImageItem.swift:7-8`

Both properties hold the same pixel data in different wrapper types. For 20 images at 4K resolution, this doubles memory usage.

**Fix:** Store only one and derive the other lazily.

### S-10: `SaliencyAnalyzer` Hardcodes Vision Request Types

**File:** `SaliencyAnalyzer.swift:38-47`

The choice of Vision requests is embedded in `analyze()`. No way to configure saliency-only, face-only, or different algorithms.

**Fix:** Inject request factories or configuration.

### S-11: `FitMath` Doesn't Guard Against NaN/Infinity

**File:** `FitMath.swift:10,34`

The guard checks `> 0` but not `.isNaN` / `.isInfinite`. A NaN height would pass the guard.

**Fix:** Add `.isFinite` checks.

### S-12: `ImageLibraryManager.addImages` — Deprecated Alpha Info

**File:** `ImageLibraryManager.swift:66`

`CGImageAlphaInfo.noneSkipFirst` is deprecated and produces thumbnail artifacts.

**Fix:** Use `.noneSkipLast` or `.none`.

### S-13: `PreviewManager.awaitPendingTasks()` Uses Arbitrary Sleep

**File:** `PreviewManager.swift:208-210`

300ms magic number for test synchronization.

**Fix:** Use `AsyncCondition` or a completion signal.

### S-14: `LoggingExtensions.swift` Mixes Unrelated Concerns

**File:** `LoggingExtensions.swift`

Contains both debug string formatting (`DebugHelpers`) and `NSColor` hex encoding/decoding (`rgbaHex`).

**Fix:** Split into separate files.

### S-15: `SaliencyResult.cropOrigin` Combines Coordinate Transform and Crop Math

**File:** `SaliencyResult.swift:15-35`

Does both Vision coordinate swap and clamping in one method.

**Fix:** Split into `toImageSpace()` and `clampedCropOrigin()`.

### S-16: `TitleStyle.LayoutKey` Has Unnecessary `public` Visibility

**File:** `TitleStyle.swift:8-20`

All members are `public` but `LayoutKey` is nested within module-internal `TitleStyle`.

**Fix:** Remove `public` modifiers.

### S-17: `CanvasConfig` Is Underutilized

**File:** `CanvasConfig.swift`

Only 2 constants for a type named after the entire canvas subsystem.

**Fix:** Rename to `SizeConstants` or expand with related values.

### S-18: `SplitMix64` Conforms to `RandomNumberGenerator` Unnecessarily

**File:** `LayoutGenerator.swift:206`

The protocol conformance is incidental — only manual bit extraction is used.

**Fix:** Remove conformance, rename to `SeededPRNG`.

---

## Testing Review

### Coverage Gaps

| File | Lines | Risk | Status |
|------|-------|------|--------|
| `RenderScheduler.swift` | 18 | **High** | Zero test coverage of CoreGraphics serialization |
| `ExportManager.swift` | 86 | **High** | No tests for save panel, file I/O, cancellation |
| `ImageLibraryManager.swift` | 145 | **Medium** | No tests for concurrent loading, move mapping |

### Mock Quality

**Good:** `TrackingAssembler` captures call data across tests. `GenerationControlledAssembler` enables stale-result testing. UserDefaults isolation via unique suite names.

**Warning:** Three near-duplicate `CollageAssembly` mocks across files (`TrackingAssembler`, `MockAssembler`, `TestPreviewAssembler`). Consolidate into `TestHelpers.swift`.

### Concurrency Testing

**Good:** 8 dedicated concurrency tests (concurrent rendering, stale discard, background thread safety). `@Suite(.serialized)` prevents intra-suite races.

**Warning:** 16 tests use `Task.sleep` for synchronization instead of `awaitPendingTasks()` — flakiness risk.

### Performance Tests

**Warning:** `CollagePerformanceTests` are behavioral tests with `TrackingAssembler`, not actual benchmarks. Either rename or convert to `#measure` with real images.

---

## Architecture Strengths

1. **Protocol hierarchy for `CollageAssembly`** — Four focused sub-protocols (`CollageRenderer`, `PanelRenderer`, `BackgroundRenderer`, `TitleRenderer`) enable granular mocking
2. **Generation-based stale-task discard** — `PreviewManager` uses integer counters to discard superseded async results — correct and performant
3. **Actor isolation** — `SaliencyAnalyzer` and `RenderScheduler` provide thread-safe Vision and CoreGraphics access
4. **`@Observable` + `@MainActor`** — Idiomatic Swift 5.9+ state management with version counters for delegation chains
5. **Strategy pattern for layouts** — `LayoutStrategy` protocol with `UniformLayoutStrategy`, `HeroLayoutStrategy`, `MosaicLayoutStrategy`
6. **Debounced persistence** — 300ms debounce prevents excessive `UserDefaults` writes during rapid interaction
7. **Undo integration** — 60-level undo for all user actions, properly grouped for gestures
8. **CoreText migration** — Thread-safe title rendering that eliminated the critical AppKit-on-background-thread issue

---

## Recommendations by Priority

### Immediate (fix this week)

1. **Delete `TitleMetrics.swift`** (C-2) — dead code cleanup
2. **Fix `isProcessing` race condition** (C-1) — reference-counted processing tracker
3. **Fix force cast in `ScrollPanView`** (W-10) — defensive guard
4. **Remove `exportManager` double-init** (S-2) — wasted allocation

### Short-term (next sprint)

5. **Extract property change helper** (W-5) — reduces 120 lines of boilerplate
6. **Fix `ExportManager` DIP violation** (W-2) — return `ExportResult` instead of mutating ViewModel
7. **Extract `cancelAllTasks()` in `PreviewManager`** (W-8) — eliminates duplication
8. **Add `RenderScheduler` tests** (CG-1) — critical untested concurrency primitive
9. **Add `ExportManager` tests** (CG-2) — critical untested flow
10. **Add `ImageLibraryManager` tests** (CG-3) — move mapping logic is non-trivial

### Medium-term (next release)

11. **Begin `CollageViewModel` decomposition** (W-1) — extract `LayoutManager` and `TitleConfigManager`
12. **Extract business logic from Views** (W-6) — `TitleDragHandler`, `DropHandler`
13. **Provide structured `AssemblyConfig` init** (W-3) — reduces construction errors
14. **Consolidate test mocks** — single `TestHelpers.swift` location
15. **Convert `GestureCoordinator` to `@Observable`** (S-1)

---

## Scorecard

| Category | Score | Notes |
|----------|-------|-------|
| SOLID Principles | 7/10 | Good protocol usage; DIP violation in ExportManager; SRP stretched in ViewModel |
| Separation of Concerns | 7/10 | Clear layering; business logic leaks into Views |
| Concurrency | 8/10 | Actors, Sendable, generation counters — solid; race condition in isProcessing |
| Test Coverage | 6/10 | Good core coverage; critical gaps in RenderScheduler, ExportManager, ImageLibraryManager |
| Code Duplication | 7/10 | Property pipeline repeated 12×; mock duplication; color picker duplication |
| Documentation | 8/10 | 55 learning files, extensive session history; @unchecked Sendable lacks comments |
| **Overall** | **7.2/10** | Well-architected foundation with clear path to 9/10 |
