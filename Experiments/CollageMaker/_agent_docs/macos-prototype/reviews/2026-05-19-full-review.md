# CollageMaker Code Review

**Date:** 2026-05-19
**Scope:** Full project architecture and code quality review

---

## Executive Summary

CollageMaker is a well-structured macOS SwiftUI app with good separation of concerns across Models, Services, ViewModel, and Views. The project demonstrates strong understanding of Swift concurrency, `@Observable` state management, and Vision/CoreGraphics integration. The primary area for improvement is the `CollageViewModel`, which has grown to 778 lines and should be decomposed.

**Overall: Approve with suggested refactors** (no blocking issues)

---

## Architecture & SOLID Analysis

### Strengths

| Area | Assessment |
|------|------------|
| **Layering** | Clean Models / Services / ViewModel / Views separation |
| **DIP** | `SaliencyAnalysis` and `CollageAssembly` protocols enable testability |
| **Concurrency** | `actor SaliencyAnalyzer` for thread-safe ML; `Task.detached` for heavy CG work |
| **State** | `@Observable` + `@Bindable` pattern used correctly throughout |
| **Testing** | Mock services, good `LayoutGenerator` coverage, `CropManager` tests |

### SRP — CollageViewModel (778 lines)

The ViewModel handles image loading, layout regeneration, saliency orchestration, crop management, scroll pan state, preview rendering, and export. Several responsibilities should be extracted:

- **Scroll pan state** (`scrollPanPanelId`, `scrollPanAccumulator`, `scrollCommitTimer`) belongs in a dedicated scroll manager or the view layer
- **Image loading** (`addImages`, `browseImages`) could be an `ImageLoader` service
- **Export orchestration** (`exportCollage`) could be an `ExportService`

**Suggestion:** Extract scroll pan into `ScrollPanManager`, image loading into `ImageLoaderService`, and export into `ExportService`. Target ~300 lines for the ViewModel.

### OCP — LayoutGenerator

The `generate` method switches on `LayoutStyle`. Adding a new layout style requires modifying `LayoutGenerator`. Consider a protocol-based approach:

```swift
protocol LayoutStrategy {
    func generate(numImages: Int, canvasSize: CGSize, gutter: CGFloat, imageOrder: [Int]?) -> [ImagePanel]
}
```

**Priority:** Low — 3 styles is manageable with a switch.

### DIP — CollageAssembly protocol

The protocol methods accept 14-15 parameters. This is error-prone and hard to maintain.

**Suggestion:** Introduce an `AssemblyConfig` struct to group parameters:

```swift
struct AssemblyConfig {
    let panels: [ImagePanel]
    let cgImages: [CGImage?]
    let crops: [UUID: CropInfo]
    let panelAssignments: [UUID: Int]
    let titleAttrString: NSAttributedString
    let titleStyle: TitleStyle
    let background: BackgroundConfig
    let canvasSize: CGSize
    // ...
}
```

---

## Critical Issues

### 1. `SaliencyAnalyzer.analyze` extracts CGImage off-main-thread

`SaliencyAnalyzer` is an `actor`. The `analyze` method calls `image.cgImage(forProposedRect:...)` on an actor isolation thread, not the main thread. `NSImage` methods are AppKit and should be called on the main actor.

**Location:** `Services/SaliencyAnalyzer.swift:24`

**Fix:** Extract `CGImage` on the main thread before passing to the analyzer. The `addImages` method already extracts `cgImage` from `nsImage` on a background queue — consider extracting it on the main thread before the `Task` that calls `analyzeSaliency`. Alternatively, change the `SaliencyAnalysis` protocol to accept `CGImage` instead of `NSImage`.

### 2. `addImages` blocks the main actor

The `dispatchGroup.wait()` call blocks the calling thread. Since `addImages` is called from the main actor context (via `browseImages` callback and drop handler), this blocks the main thread during image loading.

**Location:** `ViewModel/CollageViewModel.swift:313`

**Fix:** Make `addImages` an `async` function and use `await` with `Task.detached` instead of `DispatchGroup`.

### 3. `exportCollage` shows NSSavePanel on main actor inside async

`NSApplication.shared.runModal(for: savePanel)` blocks the main thread. This is called inside `exportCollage()` which is marked `async`, giving callers the impression it won't block.

**Location:** `ViewModel/CollageMaker.swift:714`

**Fix:** Document the blocking behavior or extract the save panel into a separate synchronous method, keeping only the async export work in the async function.

---

## Code Quality Issues

### 4. Duplicated font measurement logic

The NSAttributedString font measurement and merging logic appears in three places:
- `CollageAssembler.drawTitle` (lines 391-456)
- `CollageEditorView.titleCanvasFrame` (lines 43-95)
- `CollageEditorView.titleMinWidth` (lines 97-135)

**Fix:** Extract to a `TitleMetrics` struct or `NSAttributedString` extension.

### 5. Duplicated `normalizeForEditor` font handling

The font descriptor + traits merging pattern (`enumerateAttribute(.font)`, `withSymbolicTraits`, `NSFont(descriptor:size:)`) is repeated across `AttributedStringEditor.swift`, `CollageAssembler.swift`, and `CollageEditorView.swift`.

**Fix:** Extract to a shared `FontMerger` utility.

### 6. `CropManager` dual static/instance methods

Methods like `canvasToPreviewFrame`, `sourceRectInContainer`, `hitTestPanel`, `translateZoom`, and `screenToCanvasPoint` exist as both static and instance methods, with the instance methods simply delegating to `Self.method()`.

**Location:** `ViewModel/CropManager.swift:188-251`

**Fix:** Remove the instance wrappers. Callers should use `CropManager.staticMethod()` or `CoordinateConverter.staticMethod()` directly. The `CoordinateConverter` struct already exists for this purpose.

### 7. `buildMoveMapping` complexity

The move mapping logic in `CollageViewModel` (lines 370-388) is complex and operates on index positions with boundary-sensitive arithmetic.

**Location:** `ViewModel/CollageViewModel.swift:370`

**Suggestion:** Add a dedicated unit test for edge cases (move to start, move to end, single element, empty customImageOrder).

### 8. `backgroundImage` not persisted

The `backgroundImage` property on `CollageViewModel` is never saved to `UserDefaults`. It will be lost on app restart.

**Location:** `ViewModel/CollageViewModel.swift:182`

**Fix:** Either persist the background image path or document this as intentional (ephemeral setting).

### 9. Mosaic layout is non-deterministic

`LayoutGenerator.generateMosaic` uses `Float.random(in: 0..<1)` for split ratios. This makes layouts non-reproducible and hard to test.

**Location:** `Services/LayoutGenerator.swift:140`

**Fix:** Accept a `seed: UInt64?` parameter for `RandomNumberGenerator`, or use a deterministic algorithm based on image count.

---

## macOS-Specific Patterns

### 10. `ContentView.handleDrop` uses legacy DispatchGroup

The drop handler uses `DispatchGroup` + `NSLock` + callbacks. This could be modernized with Swift concurrency.

**Location:** `ContentView.swift:258-306`

**Fix:** Use `async let` with `withThrowingTaskGroup` for cleaner concurrent item loading.

### 11. `@State` in `CollageMakerApp` for ViewModel

The app uses `@State private var viewModel = CollageViewModel()`. For an `@Observable` class, `@State` is correct — but this means the ViewModel cannot be recreated (e.g., for a "New Collage" command).

**Location:** `CollageMakerApp.swift:11`

**Nit:** Consider `@StateObject` if you ever need to swap ViewModels, or document why `@State` is sufficient.

### 12. `SettingsView` key mismatch

`SettingsView` uses `@AppStorage("layoutStyle")` which maps to the same `UserDefaults` key as `CollageViewModel`. However, `SettingsView` also has `@AppStorage("defaultTitle")`, `@AppStorage("defaultFontFamily")`, etc., which are never read by `CollageViewModel`.

**Location:** `Views/SettingsView.swift:54-61`

**Fix:** Either wire these defaults into `CollageViewModel` initialization, or rename the keys to clarify they are "default" values (not active values).

---

## Testing Assessment

### Coverage

| Component | Status |
|-----------|--------|
| `LayoutGenerator` | Good — 20+ tests covering all styles, bounds, uniqueness |
| `CollageViewModel` | Moderate — initial state, layout, clear, assignment, error handling |
| `CropManager` | Present (separate test file) |
| `SaliencyAnalyzer` | Present (separate test file) |
| `CollageAssembler` | Present (separate test file) |
| `ExportFlow` | Present (separate test file) |
| Views | None (expected for SwiftUI) |

### Gap

- No test for `addImages` blocking behavior
- No test for `exportCollage` end-to-end flow
- No test for `buildMoveMapping` edge cases
- No test for `SaliencyAnalyzer` thread safety (CGImage extraction)

---

## Style & Consistency (Nits)

- **Nit:** `CollageCommands` has `.accessibilityLabel` and `.accessibilityHint` on `Button` inside `Commands`. Menu buttons derive accessibility from their labels — these modifiers are redundant.
- **Nit:** `LoggingExtensions.swift` defines global functions (`rectStr`, `pointStr`, `sizeStr`). Consider making them `static` methods on a `DebugHelpers` struct to avoid global namespace pollution.
- **Nit:** `ImagePickerGrid` and `ContentView` share the same `filteredImages` computed property pattern. Extract to a reusable `@ViewBuilder` or extension.
- **Nit:** `TitleStyle.CodingKeys` is in a separate extension without `: Codable`, which follows the skill guidance correctly. However, the `fromUserDefaults`/`saveToUserDefaults` methods in another extension could be consolidated.

---

## Summary of Actions

| Priority | Issue | File |
|----------|-------|------|
| **Critical** | CGImage extraction off-main-thread in actor | `SaliencyAnalyzer.swift` |
| **Critical** | `addImages` blocks main actor | `CollageViewModel.swift` |
| **High** | Extract scroll pan state from ViewModel | `CollageViewModel.swift` |
| **High** | Parameter explosion in `CollageAssembly` | `CollageAssembler.swift` |
| **Medium** | Duplicated font measurement logic (3 locations) | Multiple |
| **Medium** | `CropManager` dual static/instance methods | `CropManager.swift` |
| **Medium** | `backgroundImage` not persisted | `CollageViewModel.swift` |
| **Low** | Mosaic layout non-deterministic | `LayoutGenerator.swift` |
| **Low** | `exportCollage` NSSavePanel blocking | `CollageViewModel.swift` |
| **Nit** | Redundant accessibility on menu items | `CollageCommands.swift` |
| **Nit** | Global logging helper functions | `LoggingExtensions.swift` |
