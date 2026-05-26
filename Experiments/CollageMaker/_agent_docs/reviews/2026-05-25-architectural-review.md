# CollageMaker — Architectural Code Review

**Date:** 2026-05-25
**Reviewer:** Agent
**Scope:** Full project review (39 Swift files, ~5,400 lines of application code, 97+ tests)

---

## Executive Summary

CollageMaker is a well-structured macOS SwiftUI app with a clean layered architecture. The use of `@Observable` + `@MainActor`, protocol-based dependency injection, and actor isolation for Vision framework calls are strong foundational choices. Test coverage is good at 97+ tests across 8 test files.

The primary area for improvement is the **CollageViewModel**, which has grown into a god class (832 lines, 9+ responsibilities). Several instances of duplicated math logic and a fat configuration struct also warrant attention.

**Verdict:** Approve with suggested refactoring (non-blocking).

---

## SOLID Principles Assessment

### Single Responsibility Principle

| Component | SRP Status | Notes |
|-----------|-----------|-------|
| `CollageViewModel` | **VIOLATED** | 832 lines handling 9+ responsibilities: image loading, layout, panel assignment, saliency, crop gestures, scroll-pan, preview, export, undo, UserDefaults persistence |
| `CropManager` | Partial | Mixes gesture state management with static coordinate conversion utilities |
| `CollageAssembler` | Good | Single focus: CoreGraphics compositing |
| `LayoutGenerator` | Good | Pure function, no side effects |
| `SaliencyAnalyzer` | Good | Actor isolation, single focus on Vision analysis |
| `ScrollPanManager` | Good | Focused on scroll-to-pan accumulation |
| `CollageEditorView` | **STRETCHED** | 427 lines handling title drag/resize, panel swap drag, magnification, tap selection |
| `ExportPanel` | **VIOLATED** | Contains file picker logic and direct UserDefaults writes |

### Open/Closed Principle

- `AssemblyConfig` has 13 fields. Adding new configuration (e.g., shadows, borders, filters) requires modifying the struct and every call site. Consider splitting into sub-configs or using a builder pattern.

### Dependency Inversion Principle

- Well done. `SaliencyAnalysis` and `CollageAssembly` protocols enable clean mocking. `CollageViewModel` depends on abstractions, not concretions.

### Interface Segregation Principle

- `CollageAssembly` protocol has 4 methods, but 2 (`assemble`, `assemblePreview`) are thin wrappers around the CGImage variants. Clients only ever use the CGImage methods. Consider reducing to 2 methods.

---

## Architecture & Design

### Strengths

1. **`@Observable` + `@MainActor`** — Modern, correct approach replacing `@StateObject`/`@ObservedObject`. All UI state flows through a single source of truth.

2. **Protocol-based DI** — `SaliencyAnalysis` and `CollageAssembly` protocols enable comprehensive mocking. `MockSaliencyAnalyzer`, `MockAssembler`, and `TrackingAssembler` (spy pattern) demonstrate good test infrastructure.

3. **Actor isolation for Vision** — `SaliencyAnalyzer` as an `actor` naturally serializes Vision framework calls, avoiding the common pitfall of concurrent VNImageRequestHandler usage.

4. **Undo management** — 60 levels of undo with `beginUndoGrouping`/`endUndoGrouping` for gesture batches. Every user-facing mutation registers an undo action.

5. **Pure function layout** — `LayoutGenerator` is a stateless struct with pure static methods. The `SplitMix64` seeded PRNG for reproducible mosaic layouts is a nice touch.

6. **Consistent logging** — All logging uses `OSLog` with subsystem `austin183.indie.CollageMaker` and per-component categories.

### Concerns

#### 1. CollageViewModel God Class (Critical)

`CollageViewModel` at 832 lines handles:
- Image loading (browse, add, remove, move, clear)
- Layout regeneration
- Panel image assignment and swapping
- Saliency analysis orchestration
- Crop gesture management (pan, pinch, reset, overlay)
- Scroll-pan gesture coordination
- Preview rendering
- Export (save panel, file write)
- Undo management
- UserDefaults persistence (13 property observers with persistence logic)

**Suggested fix:** Extract responsibilities:
- **UserDefaults persistence** → A `PersistentProperties` wrapper or a `UserDefaultsSink` that observes CollageViewModel changes
- **Export orchestration** → An `ExportCoordinator` that handles save panel + file write
- **Image loading** → An `ImageLoader` service

#### 2. UserDefaults Persistence in Property Observers

Every configurable property on `CollageViewModel` embeds persistence logic in `didSet`:

```swift
var gutter: CGFloat = ... {
    didSet {
        undoManager.registerUndo(...)
        UserDefaults.standard.set(...)  // persistence concern
        regenerateLayout()               // business logic concern
    }
}
```

This mixes undo registration, persistence, and side-effect triggering in one observer. A dedicated persistence layer would decouple these concerns.

#### 3. Duplicated Fit/Math Logic

The "aspect-ratio-aware fit" calculation (determine fitted size within container, compute offset) appears in at least 4 locations:

| Location | Purpose |
|----------|---------|
| `CoordinateConverter.canvasToPreviewFrame` | Canvas→preview coordinate transform |
| `CropManager.screenToCanvasPoint` | Screen→canvas point transform |
| `CropManager.computeBestFitSource` | Source image best-fit crop |
| `CropPreviewView.sourceRectInContainer` | Crop rect in container |
| `PanelCropEditor.adjustCropDuringDrag` | Drag-to-resize crop |
| `CoordinateConverter.sourceRectInContainer` | Crop rect in container |

**Suggested fix:** Extract a `FitMath` struct with a single `fitRect(sourceSize, into: containerSize)` method that returns `(fittedSize, offset)`. All callers delegate to this.

#### 4. TitleMetrics Computed in Two Places

`TitleMetrics.prepare()` is called in both `CollageEditorView.titleCanvasFrame` (line 49) and `CollageAssembler.drawTitle` (line 289). The view computes it for overlay positioning, the assembler computes it for rendering. This is acceptable (different layers), but the computation is non-trivial and any change to font/paragraph style handling must be applied in both places.

#### 5. AssemblyConfig Fat Struct

13 fields, growing. Adding shadows, rounded corners, or watermarks would push this further. Consider:

```swift
struct AssemblyConfig {
    let layout: LayoutConfig       // panels, crops, assignments
    let title: TitleConfig         // attrString, style
    let background: BackgroundConfig  // style, colors, gradient, opacity, image
    let canvasSize: CGSize
}
```

#### 6. ExportPanel Bypasses ViewModel

`ExportPanel.chooseBackgroundImage()` (line 227-244) directly writes to `UserDefaults` and calls `viewModel?.updatePreview()`:

```swift
viewModel?.backgroundImage = image
UserDefaults.standard.set(url.path, forKey: ViewModelUserDefaultsKeys.backgroundImagePath)
viewModel?.updatePreview()  // redundant — backgroundImage's didSet already calls this
```

The `UserDefaults` write duplicates what `CollageViewModel.backgroundImage`'s `didSet` should handle. The `updatePreview()` call is redundant since `didSet` already triggers it. File picker logic in a view is also a concern — consider moving to the view model.

#### 7. Test Extension Duplicates Production Code

`CollageViewModelTests.swift` lines 214-249 define a `cropManager_computeInitialCrops()` extension that reimplements `CropManager.computeBestFitSource`. This duplicates logic that already exists in `CropManager`, creating a maintenance liability. The extension should delegate to `cropManager.computeInitialCrops()` instead.

---

## Code Quality

### Function Size

- `CollageViewModel.addImages(from:)` (lines 296-354): 58 lines, handles parallel task group, thumbnail generation, CG context creation. Consider extracting thumbnail generation.
- `CollageViewModel.exportCollage()` (lines 754-825): 71 lines, handles save panel, config building, async task management. Consider extracting save panel logic.
- `PanelCropEditor.adjustCropDuringDrag` (lines 128-216): 88 lines with a large switch. The resize cases are repetitive — consider extracting the common coordinate transform.

### Naming

- Generally clear and consistent. `imageIndex` vs `panelAssignments` distinction is well-named.
- `applyPanLive` vs `applyPan` — the "Live" suffix is unclear. Consider `applyPan(debounced: Bool)`.

### Error Handling

- `SaliencyAnalyzer` has a proper `SaliencyError` enum with `invalidImage` and `analysisFailed`.
- `CollageViewModel` surfaces errors via `errorMessage` property, which is rendered in `ExportPanel`.
- Silent failures: `addImages` silently skips images that fail to load (returns `nil` from task). No user feedback for partial failures.

---

## Testing Assessment

### Coverage

| Area | Tests | Status |
|------|-------|--------|
| Layout generation | 18 | Excellent |
| Crop management | 30 | Excellent |
| Saliency results | 7 | Good |
| Saliency analysis (integration) | 5 | Good |
| Collage assembler | 10 | Good |
| ViewModel core | 13 | Adequate |
| Export flow | 12 | Good |
| Panel crop editor | 8 | Good |
| **ScrollPanManager** | **0** | **Missing** |
| **FontMerger** | **0** | **Missing** |
| **TitleMetrics** | **0** | **Missing** |
| SwiftUI views | 0 | Missing |
| UI tests | Boilerplate only | Missing |

### Test Quality

- `@Suite(.serialized)` on `CollageViewModelTests` and `ExportFlowTests` — correct for `@MainActor` tests, but may mask concurrency issues.
- `TrackingAssembler` spy pattern in `ExportFlowTests` is well-designed for verifying assembler call patterns.
- Tests use `try? await Task.sleep(nanoseconds: 50_000_000)` for async preview tests — fragile timing dependency. Consider a completion handler or actor-based signal.

### Suggestions

1. Add tests for `ScrollPanManager` — critical gesture coordination logic
2. Add tests for `TitleMetrics` — text measurement affects rendering
3. Add tests for `FontMerger` — font trait merging
4. Replace `Task.sleep` in async tests with actor-based completion signaling

---

## Style & Consistency

- Swift 5.0 conventions followed throughout
- `@MainActor` correctly placed on view model and crop manager
- `weak self` captures in closures are consistent
- `privacy: .public` on all OSLog string interpolations (good for privacy compliance)
- No force unwraps in production code paths (audited)
- Nit: `CollageViewModel` line 65 — `UserDefaults.standard.double(forKey: "defaultFontSize")` uses an inline key string instead of a centralized constant

---

## Prioritized Recommendations

### High Priority (should fix)

1. **Extract UserDefaults persistence from CollageViewModel** — Create a persistence layer that observes state changes, removing 13 `UserDefaults.standard.set(...)` calls from property observers
2. **Fix ExportPanel.chooseBackgroundImage()** — Remove direct UserDefaults write and redundant `updatePreview()` call; delegate to view model
3. **Fix test extension duplication** — `CollageViewModelTests.cropManager_computeInitialCrops()` should delegate to `CropManager` instead of reimplementing logic

### Medium Priority (should plan)

4. **Extract FitMath utility** — Consolidate aspect-ratio fit calculations into a single reusable struct
5. **Split AssemblyConfig** — Group related fields into sub-configs for maintainability
6. **Reduce CollageAssembly protocol** — Remove NSImage wrapper methods if only CGImage variants are used
7. **Add tests for ScrollPanManager, TitleMetrics, FontMerger**

### Low Priority (nice to have)

8. **Extract ExportCoordinator** — Move save panel + file write from CollageViewModel
9. **Replace Task.sleep in tests** — Use actor-based completion signaling
10. **Consider view model splitting** — Long-term: extract image loading, export, and persistence into dedicated services

---

## Conclusion

This is a well-engineered app with strong architectural foundations. The dependency injection patterns, actor isolation, undo management, and test infrastructure are all exemplars. The main risk is the CollageViewModel's continued growth — proactively extracting persistence and orchestration concerns will prevent it from becoming unmaintainable as features are added.

No blocking issues. Recommend approving with the above refactoring backlog.
