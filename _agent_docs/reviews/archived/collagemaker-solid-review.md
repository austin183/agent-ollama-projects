# CollageMaker — SOLID & Architecture Review

**Date:** 2026-05-16
**Scope:** Full codebase review (2,582 lines across 8 source files, 6 test files)
**Architecture:** MVVM with `@Observable`, SwiftUI + AppKit, macOS desktop app

---

## Executive Summary

CollageMaker is well-architected for a project of its scope. The MVVM layering is clean, protocol-based dependency injection enables meaningful unit tests, and the separation of concerns across Models/ViewModel/Services/Views is consistent and effective. The test suite (65+ tests) provides solid coverage of pure logic.

**Verdict: Approve with suggested improvements.** No blocking architectural issues, but several opportunities to strengthen SRP, DIP, and OCP adherence.

---

## Architecture & Design

### Strengths

| Area | Assessment |
|------|-----------|
| **Layering** | Models, ViewModel, Services, and Views are cleanly separated with no cross-layer leakage |
| **DI** | `SaliencyAnalysis` and `CollageAssembly` protocols enable test doubles; `CollageViewModel` accepts both in its designated initializer |
| **Concurrency** | `SaliencyAnalyzer` as an `actor` with `withThrowingTaskGroup` is correct and safe |
| **Observability** | Modern `@Observable` macro (not legacy `ObservableObject`); structured `OSLog` throughout |
| **Pure Functions** | `LayoutGenerator` is a stateless static struct — deterministic, testable, no side effects |
| **Extraction** | `CropManager` was extracted from the ViewModel, correctly encapsulating gesture lifecycle state |

### Issues

#### 1. `CollageViewModel` approaching God class (SRP violation)

**Severity:** Medium
**File:** `CollageViewModel.swift` (655 lines)

The ViewModel handles: image loading, layout generation, crop management, saliency orchestration, scroll panning, preview rendering, export, and UserDefaults persistence. While `CropManager` was extracted, the class still has too many reasons to change.

**Suggested fix:** Extract an `ImageLoader` service to own the `addImages`/`browseImages` logic (including the `DispatchGroup`/`DispatchQueue` pattern). Consider an `ExportCoordinator` for the export flow. This would bring the ViewModel to ~400 lines.

#### 2. UserDefaults tightly coupled into ViewModel (DIP violation)

**Severity:** Medium
**File:** `CollageViewModel.swift:40-154`

Every persisted property (`layoutStyle`, `gutter`, `backgroundColor`, `exportQuality`, `backgroundStyle`, `gradientStartColor`, `gradientEndColor`, `gradientAngle`, `backgroundOpacity`, `customImageOrder`) reads from or writes to `UserDefaults.standard` directly in `didSet`/`willSet`. This couples the ViewModel to a specific persistence mechanism and makes it impossible to test with alternate defaults.

**Suggested fix:** Introduce a `SettingsStorage` protocol:

```swift
protocol SettingsStorage {
    func save<T: Codable>(_ value: T, key: String)
    func load<T: Codable>(_ type: T.Type, key: String) -> T?
    func save(_ color: NSColor, key: String)
    func loadColor(key: String) -> NSColor?
}
```

Inject via `CollageViewModel.init(settingsStorage:)`. Default to a `UserDefaultsSettingsStorage` concrete implementation in production, and a `InMemorySettingsStorage` in tests.

#### 3. `TitleStyle` persists itself (SRP violation)

**Severity:** Low-Medium
**File:** `TitleStyle.swift:33-46`

The model struct contains `fromUserDefaults()` and `saveToUserDefaults()` methods. A data model should not know about persistence.

**Suggested fix:** Remove persistence methods from `TitleStyle`. The ViewModel (or a `SettingsStorage` as above) should handle loading/saving. The model should remain a pure value type.

#### 4. `addImages` blocks the main actor

**Severity:** Medium
**File:** `CollageViewModel.swift:245`

```swift
dispatchGroup.wait()  // Blocks @MainActor
```

Although image loading runs on a background queue, `dispatchGroup.wait()` is called on the main actor. For large numbers of high-resolution images, this blocks the UI.

**Suggested fix:** Convert to async/await:

```swift
func addImages(from urls: [URL]) async {
    let items = await withTaskGroup(of: ImageItem?.self) { group in
        for url in urls {
            group.addTask { @MainActor in
                // load image on background, return ImageItem or nil
            }
        }
        // collect results
    }
    // update state
}
```

#### 5. No cancellation of stale saliency tasks

**Severity:** Low
**File:** `CollageViewModel.swift:252-256`, `CollageViewModel.swift:262-266`

Each `addImages`, `removeImage`, and `moveImages` kicks off a new `Task { await analyzeSaliency() }` without cancelling the previous one. Rapid add/remove cycles could produce stale results that overwrite newer state.

**Suggested fix:** Track the saliency task like the export task:

```swift
private var saliencyTask: Task<Void, Never>?

func analyzeSaliency() async {
    saliencyTask?.cancel()
    // ...
}
```

#### 6. Mosaic layout uses randomness (OCP concern)

**Severity:** Low
**File:** `LayoutGenerator.swift:139`

```swift
let rand = Float.random(in: 0..<1)
```

The mosaic layout produces different results for the same input. This makes deterministic testing and user reproducibility impossible.

**Suggested fix:** Inject a split ratio generator:

```swift
protocol SplitRatioGenerator {
    func next() -> CGFloat
}

struct DeterministicSplitRatioGenerator: SplitRatioGenerator {
    // Use a seeded PRNG or fixed ratios
}
```

Alternatively, offer a "shuffle" button in the UI to regenerate the mosaic, making the randomness explicit and user-controlled.

#### 7. `CollageAssembly` protocol is too broad (ISP violation)

**Severity:** Low
**File:** `CollageAssembler.swift:11-83`

The protocol defines 4 methods, each with 16+ parameters. The `NSImage`-based methods (`assemble`, `assemblePreview`) are thin wrappers that convert to `CGImage` and delegate to the `CGImage`-based methods. Consumers that only need CGImage rendering are forced to implement all 4.

**Suggested fix:** Split into two protocols:

```swift
protocol CollageAssemblyWithCGImages {
    func assembleWithCGImages(...) -> Data?
    func assemblePreviewWithCGImages(...) -> NSImage?
}

protocol CollageAssembly: CollageAssemblyWithCGImages {
    func assemble(...) -> Data?
    func assemblePreview(...) -> NSImage?
}
```

Or consolidate to a single `AssemblyConfig` struct to reduce parameter count.

#### 8. `CollageViewModelTests` pollutes production namespace

**Severity:** Low
**File:** `CollageViewModelTests.swift:172-208`

The test file extends `CollageViewModel` with `cropManager_computeInitialCrops()` and `computeBestFitSource()`. This adds methods to the production type that only exist to serve tests.

**Suggested fix:** Either:
- Make `CropManager` accessible via a test property on `CollageViewModel` (e.g., `#if DEBUG var testCropManager: CropManager { cropManager }`)
- Or use Swift's `@_testable` more carefully and expose `CropManager` directly

#### 9. `ImagePickerGrid` appears unused

**Severity:** Informational
**File:** `ImagePickerGrid.swift`

This view is not referenced anywhere in the codebase. Either remove it or wire it up.

#### 10. Hardcoded canvas size

**Severity:** Informational
**File:** `CanvasConfig.swift`

`CanvasConfig.defaultCanvasSize` is `1920x1080` with no user-facing way to change it. If output resolution becomes a feature requirement, every call site will need updating.

**Suggested fix:** Consider making `canvasSize` a configurable property on the ViewModel, persisted to UserDefaults alongside other settings.

---

## Code Quality

### Function Size & Focus

Most functions are well-scoped. Notable exceptions:

- `CollageEditorView.body` (`CollageEditorView.swift:121-390`): 270-line body property with extensive gesture handling logic inline. The `simultaneousGesture` closures are complex and hard to follow. Consider extracting gesture handlers into dedicated `NSViewRepresentable` or a coordinator object.
- `CollageViewModel.updatePreview()` / `exportCollage()` (`CollageViewModel.swift:547-654`): Both capture 15+ local variables before dispatching to the assembler. An `AssemblyConfig` struct would eliminate this boilerplate and improve readability.

### Naming

Naming is clear and consistent throughout. `panelAssignments`, `cropMap`, `scaledPanelFrames` all communicate intent well.

**Nit:** `scrollPanAccumulator` (`CollageViewModel.swift:498`) could be named `scrollPanDelta` for consistency with `panDelta` in `CropManager`.

### Error Handling

- `SaliencyAnalyzer` throws `SaliencyError.invalidImage` and `.analysisFailed` appropriately
- `CollageViewModel` surfaces errors to `errorMessage` for UI display
- `CollageAssembler` returns `nil` on failure (silent failure — consider logging or returning a result type)

**Nit:** `CollageAssembler.assembleWithCGImages` returns `nil` on context creation failure without logging. Add a `logger.error` call.

---

## Testing

### Coverage

| Suite | Tests | Assessment |
|-------|-------|-----------|
| `LayoutGeneratorTests` | 20 | Excellent — covers all styles, edge cases, bounds, uniqueness |
| `CropManagerTests` | 13 | Good — covers pan, pinch, clamping, reset, saliency crops |
| `CollageAssemblerTests` | 10 | Good — covers preview, export, title, gradient, edge cases |
| `CollageViewModelTests` | 10 | Adequate — covers state, layout, clear, assignment, errors |
| `SaliencyResultTests` | 7 | Good — covers `cropOrigin` thoroughly |
| `SaliencyAnalyzerTests` | 5 | Adequate — covers happy path and error cases |
| UITests | 2 | Stub — no meaningful assertions |

### Test Quality

- Mock services (`MockSaliencyAnalyzer`, `MockAssembler`) are well-designed and enable isolated testing
- Swift Testing framework (`#expect`) is used consistently
- `@MainActor` isolation is respected in test suites

**Gap:** No tests for `ContentView`, `CollageEditorView`, or `ExportPanel`. SwiftUI view tests are challenging but the gesture handling logic in `CollageEditorView` is complex enough to warrant at least snapshot or interaction tests.

**Gap:** No tests for `ScrollPanView` or `PanelCropEditor`.

---

## Separation of Concerns

### Assessment by Layer

| Layer | Files | Concerns |
|-------|-------|----------|
| **Models** | 7 files | Pure value types. Exception: `TitleStyle` contains persistence logic |
| **ViewModel** | 2 files | State + orchestration. `CropManager` correctly extracted |
| **Services** | 3 files | Infrastructure. Clean boundaries, no UI dependencies |
| **Views** | 7 files | Presentation. `CollageEditorView` contains significant gesture/coordinate logic that could be extracted |

### Data Flow

```
UI gesture → CollageViewModel → CropManager (crop state)
                → LayoutGenerator (panel layout, pure)
                → SaliencyAnalyzer (async analysis, actor-isolated)
                → CollageAssembler (rasterization, detached task)
                → UserDefaults (persistence, inline)
```

The flow is unidirectional and well-structured. No circular dependencies.

---

## Style & Consistency

- Logging is consistent: `private let logger = Logger(subsystem: "...", category: "...")` in every file
- Privacy annotations on log messages are used throughout
- `@Observable` + `@Bindable` pattern is applied uniformly
- `Task.detached` is used correctly for background work
- Force unwraps are minimal and guarded

**Nit:** `CollageEditorView.swift:12-22` defines `rectStr`, `pointStr`, `sizeStr` as file-private functions. These are logging helpers that could live in a shared `LoggingExtensions` file alongside other debug utilities.

**Nit:** `CollageAssembler.swift:179` has a nested string interpolation in the log message: `"\("\(Int(canvasSize.width))x\(Int(canvasSize.height))", privacy: .public)"`. This is redundant — simplify to `"\(Int(canvasSize.width))x\(Int(canvasSize.height))", privacy: .public`.

---

## Summary of Findings

| # | Issue | Principle | Severity | Effort |
|---|-------|-----------|----------|--------|
| 1 | `CollageViewModel` approaching God class | SRP | Medium | Medium |
| 2 | UserDefaults tightly coupled in ViewModel | DIP | Medium | Medium |
| 3 | `TitleStyle` persists itself | SRP | Low-Med | Small |
| 4 | `addImages` blocks main actor | Performance | Medium | Small |
| 5 | No saliency task cancellation | Correctness | Low | Small |
| 6 | Mosaic randomness | OCP/Testing | Low | Small |
| 7 | `CollageAssembly` protocol too broad | ISP | Low | Small |
| 8 | Tests pollute production namespace | Testability | Low | Small |
| 9 | `ImagePickerGrid` unused | Dead code | Info | Trivial |
| 10 | Hardcoded canvas size | Extensibility | Info | Medium |

---

## Recommendations (Prioritized)

1. **Extract `ImageLoader` service** — Move image loading logic from `CollageViewModel.addImages` into a dedicated service. Convert `addImages` to `async` to eliminate the `dispatchGroup.wait()` main thread block.

2. **Abstract `UserDefaults` behind `SettingsStorage` protocol** — This single change addresses both the tight coupling in the ViewModel and the persistence-in-model problem in `TitleStyle`.

3. **Track and cancel stale saliency tasks** — Add a `saliencyTask` property with cancellation before starting new analysis.

4. **Seed or externalize mosaic randomness** — Make mosaic layout reproducible and testable.

5. **Extract gesture coordinate logic from `CollageEditorView.body`** — The 270-line body with inline gesture handlers is the hardest-to-read code in the project. Consider a `CanvasGestureCoordinator` or breaking into subviews.
