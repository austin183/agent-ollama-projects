# CollageMaker — Architectural Code Review
**Date:** 2026-06-22
**Reviewer:** Marcos
**Scope:** Full codebase — Models, Services, ViewModel, Views, Tests

---

## Executive Summary

CollageMaker is a well-architected macOS SwiftUI app with strong foundations: protocol-based abstractions, `@Observable`/`@MainActor` patterns, actor-isolated services, and a manager extraction strategy that keeps subsystems decoupled. The codebase demonstrates hard-won knowledge from 30+ session learnings, particularly around gesture handling, coordinate transforms, and `@Observable` pitfalls.

However, several critical issues emerged that affect correctness, maintainability, and testability. The largest concern is the 1,063-line `CollageViewModel` that continues to accumulate responsibilities. The Models layer has cross-layer dependencies and silent data loss in `CropInfo` serialization. The Services layer has an unused parameter bug in `BackgroundRenderer`, synchronous file I/O on the main thread, and missing protocols that prevent test isolation.

**Overall assessment:** Good architecture with 6 critical issues requiring immediate attention, 18 recommended improvements, and a significantly under-tested Models layer.

---

## Critical Issues (Must Fix)

### C1. `CropInfo` Codable Silently Degrades `.path` Geometries to Rectangles
**File:** `Models/ImagePanel.swift:53-77`
**Layer:** Models
**Severity:** Data loss on save/load

The `encode` method only persists `destination.boundingRect` (line 63). When deserializing a `.path` geometry, the original `CGPath` is replaced with a plain rectangle (line 73). Collages using diagonal slices or hexagonal layouts will silently degrade to rectangular panels after persistence.

```swift
// Line 63: only boundingRect encoded — path data discarded
try container.encode(destination.boundingRect, forKey: .destinationRect)
// Line 73: always creates rect path, never the original
destination = .path(cgPath: CGPath(rect: destRect, transform: nil), boundingRect: destRect)
```

**Fix:** Persist path point data via `PanelGeometry.extractPathPoints`, or fail loudly with a documented limitation.

---

### C2. `BackgroundRenderer.renderBackground` Ignores `previewSize` Parameter
**File:** `Services/BackgroundRenderer.swift:58-92`
**Layer:** Services
**Severity:** Performance bug — renders at full resolution for previews

The `previewSize: CGSize` parameter is accepted but never used. The method creates a context at `canvasSize`, renders at `canvasSize`, and returns an `NSImage` at `canvasSize`. Every background preview renders at full canvas resolution, wasting GPU memory and CPU.

```swift
static func renderBackground(
    config: BackgroundConfig,
    canvasSize: CGSize,
    backgroundImage: CGImage?,
    previewSize: CGSize  // ← NEVER USED
) -> NSImage? {
    guard let context = createContext(size: canvasSize) else { return nil }
    // ... draws at canvasSize ...
    return NSImage(cgImage: cgImage, size: canvasSize)  // ← should be previewSize
}
```

**Fix:** Create the context at `previewSize`, scale the context, draw at `canvasSize` coordinates. Mirror the pattern in `CollageAssembler.renderPreviewIntoContext`.

---

### C3. `UserDefaultsPersistence.load()` Blocks Main Thread with Synchronous File I/O
**File:** `Services/UserDefaultsPersistence.swift:251-273`
**Layer:** Services
**Severity:** Launch jank

`loadBackgroundImage()` and `loadDoubleExposureMaskImage()` synchronously read image data from disk on the main thread during `CollageViewModel.init()`. For large background images, this creates a visible jank spike on app launch.

```swift
private func loadBackgroundImage() -> (image: NSImage?, path: String?) {
    // ...
    let data = try? Data(contentsOf: url),       // ← BLOCKING FILE I/O
    let image = NSImage(data: data) else {       // ← BLOCKING DECODE
```

**Fix:** Return only the path from `load()`. Load images asynchronously after init. `PersistenceBundle` should contain `backgroundImagePath: String?` but not `backgroundImage: NSImage?`.

---

### C4. `Debouncer` Tasks Never Cleaned Up on Deallocation
**File:** `ViewModel/Debouncer.swift:1-25`
**Layer:** ViewModel
**Severity:** Guaranteed task leaks

`Debouncer` stores `Task<Void, Never>` instances but has no `deinit`. When `CollageViewModel` is deallocated, all pending debounce tasks continue running with dangling captures.

```swift
final class Debouncer {
    private var tasks: [String: Task<Void, Never>] = [:]
    // No deinit — tasks leak
}
```

**Fix:** Add `deinit { cancelAll() }`.

---

### C5. `@Observable` Delegation Chain Breaks SwiftUI Observation for `cropMap`
**File:** `CollageViewModel.swift:102-105`, `Views/PanelCropEditor.swift:176,182`
**Layer:** ViewModel → Views
**Severity:** Silent UI staleness

`CollageViewModel.cropMap` is a computed property delegating to `cropManager.cropMap`. Per skill reference (`references/state/observable-bindable.md`), computed properties are invisible to SwiftUI's observation system. When `CropManager.cropMap` mutates, SwiftUI does NOT re-render views reading `viewModel.cropMap`.

```swift
var cropMap: [UUID: CropInfo] {
    get { cropManager.cropMap }
    set { cropManager.cropMap = newValue }
}
```

**Fix:** Add a `cropVersion: Int` stored property to `CollageViewModel` (matching the `titleImageVersion` pattern already used for `titleImage`), or have `PanelCropEditor` read `viewModel.cropManager.cropMap` directly.

---

### C6. `DropPreviewView` Receives `GestureCoordinator` as `let` (Not Observed)
**File:** `Views/DropPreviewView.swift:6`
**Layer:** Views
**Severity:** Drag preview never updates

```swift
let gestureCoordinator: GestureCoordinator  // WRONG — GestureCoordinator is @Observable
```

A plain `let` parameter renders once and never updates. The drag preview (source highlight, target highlight, cursor thumbnail) will not update during drags.

**Fix:** Pass specific state values as value types, or restructure to avoid observing `GestureCoordinator` from this view.

---

## Recommended Improvements (Should Fix)

### R1. `CollageViewModel` Exceeds Single Responsibility — 1,063 Lines
**File:** `ViewModel/CollageViewModel.swift`
**Layer:** ViewModel

The VM handles ~12 distinct responsibilities: layout orchestration, crop gestures, scroll pan, title editing, background config, image operations, export, preview rendering, saliency, undo/redo, debouncing, and settings persistence.

**Areas ripe for extraction:**
- Scroll pan + pinch coordination (lines 643-793)
- Six nearly identical `setTitle*` methods (lines 929-994)
- Overlay crop methods (lines 712-758)

---

### R2. `CollageAssembly` Protocol Violates Interface Segregation
**File:** `Services/CollageAssembler.swift:61`
**Layer:** Services

The "fat protocol" bundles 5 capabilities (`CollageRenderer`, `PanelRendering`, `BackgroundRendering`, `TitleRendering`, `OverlayRendering`). Callers that need one capability are forced to depend on all five.

**Fix:** Have callers depend on the specific sub-protocol they need. `ExportManager` already does this correctly.

---

### R3. Missing Protocols for `DropHandler`, `RenderScheduler`, `PreviewManager`
**Files:** `Services/DropHandler.swift`, `Services/RenderScheduler.swift`, `Services/PreviewManager.swift`
**Layer:** Services

Unlike `SaliencyAnalysis`, `ImagePicker`, and `CollageAssembly`, these services lack abstractions. Tests cannot inject mocks.

**Fix:** Create `DropHandling`, `RenderScheduling`, and `PreviewManagement` protocols.

---

### R4. `TitleTextData` Creates Models → Services Cross-Layer Dependency
**File:** `Models/AssemblyConfig.swift:15`
**Layer:** Models

`TitleConfig.textData` is of type `TitleTextData`, which is defined in `Services/TitleRendererCT.swift`. This inverts the expected layering — Models should not depend on Services.

**Fix:** Move `TitleTextData` to Models, or use a different representation in `TitleConfig`.

---

### R5. `TitleStyle.default` Creates `NSColor` at Type Initialization
**File:** `Models/TitleStyle.swift:44-54`
**Layer:** Models

`NSColor` is `@MainActor`-only. A `static let` property initializer runs at module load time, which may not be on the main actor.

**Fix:** Use `static func defaultStyle() -> TitleStyle` as a computed property, or use `CGColor` for defaults.

---

### R6. Gesture Types (`TitleHitResult`, `TitleResizeEdge`) in Models Layer
**File:** `Models/TitleStyle.swift:5-11`
**Layer:** Models

Purely UI interaction types have no business in Models. They belong in `Views/GestureTypes.swift` or `ViewModel/TitleInteraction.swift`.

---

### R7. `SaliencyAnalyzer.analyzeAll` Silently Drops Failed Images
**File:** `Services/SaliencyAnalyzer.swift:117-143`
**Layer:** Services

When individual image analysis fails, the error is logged but the image is silently omitted from results. The caller receives fewer results than input images with no indication of which indices failed.

**Fix:** Return fallback results for failed images or return `[SaliencyResult?]`.

---

### R8. `UserDefaultsPersistence.save(_:)` Tightly Couples to `CollageViewModel`
**File:** `Services/UserDefaultsPersistence.swift:84-114`
**Layer:** Services

The persistence layer directly accesses 20+ properties on `CollageViewModel`. Any ViewModel property rename breaks persistence.

**Fix:** Pass a `PersistenceBundle` to `save()` instead of the ViewModel.

---

### R9. `ImageCoordinator` Has Excessive Dependencies (6 objects)
**File:** `ViewModel/ImageCoordinator.swift:31-56`
**Layer:** ViewModel

Holds direct references to `ImageLibraryManager`, `LayoutManager`, `CropManager`, `PreviewManager`, `UndoManager`, and `SaliencyAnalyzer`. Violates ISP.

**Fix:** Accept narrower protocols or return data snapshots for the VM to apply.

---

### R10. `BackgroundConfig` Duplicates Color State (NSColor + CGColor)
**File:** `Models/AssemblyConfig.swift:28-57`
**Layer:** Models

Stores both `NSColor` and `CGColor` representations of the same values. Architecturally sound for concurrency safety, but creates maintenance burden.

**Fix:** Consider a `ColorPair: Sendable` helper type to encapsulate the pattern.

---

### R11. `PanelCropEditor` Is 520 Lines with Business Logic
**File:** `Views/PanelCropEditor.swift`
**Layer:** Views

Contains 10 `@State` variables, 60+ lines of `adjustCropDuringDrag` business logic, and a nested `CropPreviewView` struct. Edge detection, coordinate conversion, and drag mode state transitions should be in a coordinator.

**Fix:** Extract a `CropOverlayCoordinator` that owns state and drag logic.

---

### R12. `CollageEditorView` Embeds 150 Lines of Gesture Logic in View Body
**File:** `Views/CollageEditorView.swift:82-228`
**Layer:** Views

Three `simultaneousGesture` modifiers with title hit-testing, drag, resize, panel swap, and pinch-to-zoom logic in the view body. Each `onChanged` closure writes to `@Observable` properties, triggering full body re-evaluation cascades at 60fps.

**Fix:** Extract gestures into coordinator structs with local `@State`. Sync to ViewModel on `onEnded`.

---

### R13. `AttributedStringEditor` Uses Legacy `ObservableObject` Pattern
**File:** `Views/AttributedStringEditor.swift:29,217,231`
**Layer:** Views

Uses `@StateObject`/`ObservableObject`/`@ObservedObject` while the rest of the codebase uses `@Observable`/`@Bindable`.

**Fix:** Migrate `StyleableTextViewHolder` to `@Observable`.

---

### R14. `PreviewManager.awaitPendingTasks()` Is a Sleep-Based Synchronization Hack
**File:** `Services/PreviewManager.swift:236-238`
**Layer:** Services

A 300ms `Task.sleep` is a fragile test synchronization mechanism.

**Fix:** Use `AsyncStream` or `CheckedContinuation` to signal actual task completion.

---

### R15. `TitleTextData.extract(from:)` Lacks `@MainActor` Annotation
**File:** `Services/TitleRendererCT.swift:21-41`
**Layer:** Services

The doc comment says "Must be called on the main actor" but there is no compiler-enforced isolation.

**Fix:** Add `@MainActor` to the method.

---

### R16. `CollageAssembler` Is `@unchecked Sendable` Without Compiler Verification
**File:** `Services/CollageAssembler.swift:83`
**Layer:** Services

A future change adding mutable state would silently break the `Sendable` guarantee.

**Fix:** Extract `RenderScheduler` as a dependency or convert to an actor.

---

### R17. `exportManager` Is an IUO — Unnecessary Crash Risk
**File:** `ViewModel/CollageViewModel.swift:88`
**Layer:** ViewModel

```swift
var exportManager: ExportManager!
```

**Fix:** Make it a non-optional `let` property.

---

### R18. `customImageOrder` Setter Missing Undo Registration
**File:** `ViewModel/CollageViewModel.swift:91-97`
**Layer:** ViewModel

Unlike other setters, changes to `customImageOrder` are not undoable.

**Fix:** Add undo registration or convert to a method.

---

## Test Coverage Gaps

### High-Priority Gaps (Logic-Heavy Files with No Tests)

| File | Layer | Priority |
|------|-------|----------|
| `Models/ImagePanel.swift` | Models | **High** — core data model, Codable round-trip |
| `Models/PanelGeometry.swift` | Models | **High** — geometry math, path extraction |
| `Models/AssemblyConfig.swift` | Models | **High** — config composition |
| `Models/ImageItem.swift` | Models | **High** — core data model |
| `Models/ImageItem+Filtering.swift` | Models | **Medium** — search/filter logic |
| `Services/BackgroundRenderer.swift` | Services | **High** — rendering logic (has C2 bug) |
| `Services/PanelRenderer.swift` | Services | **High** — rendering logic |
| `Services/OverlayRenderer.swift` | Services | **Medium** — rendering logic |
| `Services/DropHandler.swift` | Services | **Medium** — user interaction |
| `ViewModel/Debouncer.swift` | ViewModel | **High** — concurrency logic (has C4 bug) |
| `ViewModel/FrameTempo.swift` | ViewModel | **Low** — timing constants |

### Coverage Summary

- **Models layer:** 9 of 10 files untested (90% gap)
- **Services layer:** 9 of 19 files untested (47% gap)
- **ViewModel layer:** 4 of 12 files untested (33% gap)

The Models layer is the most concerning gap — `CropInfo` Codable (C1) and `PanelGeometry` path extraction both lack tests.

---

## SOLID Principles Assessment

| Principle | Status | Details |
|-----------|--------|---------|
| **Single Responsibility** | ⚠️ Partial | `CollageViewModel` (1,063 lines, ~12 responsibilities). `TitleStyle.swift` contains data + gesture types. `SaliencyResult` contains data + crop math. |
| **Open/Closed** | ✅ Good | `LayoutStyle` enum with strategy pattern. `PanelGeometry` extensible via cases. Managers follow pure accumulator pattern. |
| **Liskov Substitution** | ✅ N/A | No inheritance hierarchy — protocol-based design. |
| **Interface Segregation** | ⚠️ Partial | `CollageAssembly` bundles 5 capabilities. `ImageCoordinator` has 6 dependencies. |
| **Dependency Inversion** | ⚠️ Partial | Models depend on Services (`TitleTextData`). UI types (`TitleHitResult`) in Models layer. Most VM dependencies are protocol-based. |

---

## Architectural Strengths

1. **Protocol-based design** — `SaliencyAnalysis`, `ImagePicker`, `CollageAssembly`, `ViewModelPersistence` enable test mocking
2. **Concurrency patterns** — `RenderScheduler` actor, `nonisolated` on `SaliencyAnalyzer.analyze`, generation counters, `[weak self]` captures
3. **Manager extraction** — `CropManager`, `LayoutManager`, `BackgroundManager`, `TitleManager`, `ExportManager` are well-scoped
4. **Pure rendering structs** — `PanelRenderer`, `BackgroundRenderer`, `OverlayRenderer`, `PolygonClipper`, `FitMath`, `ContextFactory` are stateless
5. **`@unchecked Sendable` documentation** — Every instance has a safety comment explaining the justification
6. **CoreGraphics/AppKit boundary** — `BackgroundConfig` captures `CGColor` at init time to avoid cross-thread evaluation

---

## Prioritized Action Plan

### Immediate (This Week)
1. **C2** — Fix `BackgroundRenderer.renderBackground` to use `previewSize`
2. **C4** — Add `deinit` to `Debouncer`
3. **C5** — Add `cropVersion` counter to fix `cropMap` observation
4. **C6** — Fix `DropPreviewView` gesture coordinator observation

### Short Term (Next Sprint)
5. **C1** — Fix `CropInfo` Codable to preserve path data
6. **C3** — Move synchronous image loading off main thread
7. **R15** — Add `@MainActor` to `TitleTextData.extract(from:)`
8. **R17** — Convert `exportManager` IUO to non-optional

### Medium Term (Next Release)
9. **R1/R12** — Extract scroll pan and gesture logic from `CollageViewModel`/`CollageEditorView`
10. **R3** — Add protocols for `DropHandler`, `RenderScheduler`, `PreviewManager`
11. **R4** — Move `TitleTextData` to Models layer
12. **Test gaps** — Add tests for `CropInfo` Codable, `Debouncer`, `BackgroundRenderer`

### Long Term
13. **R1** — Consider splitting `CollageViewModel` into 2-3 focused coordinators
14. **R2** — Decompose `CollageAssembly` into consumer-specific protocol compositions

---

## Conclusion

The CollageMaker codebase demonstrates strong architectural fundamentals with protocol-based design, proper concurrency patterns, and well-scoped managers. The critical issues are fixable without restructuring, and the recommended improvements address the main maintainability risks. The largest long-term risk is `CollageViewModel` growth — proactive extraction before it reaches 1,500 lines will prevent a refactor crisis.
