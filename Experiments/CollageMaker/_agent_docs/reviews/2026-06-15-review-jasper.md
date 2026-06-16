# Code Review — 2026-06-15 (Jasper)

**Scope:** SRP decomposition refactors (Phases 1–5) + test stability fix
**Commits:** `811aebb` through `f8ce61d` (10 commits, 32 files, +1702 / -930 lines)
**Reviewer:** Jasper

---

## Executive Summary

The SRP decomposition is a **meaningful improvement** over the prior monolithic `CollageViewModel`. The extraction of `BackgroundManager`, `TitleManager`, `LayoutManager`, `ImageCoordinator`, and the renderer split in `CollageAssembler` demonstrates good architectural intent. The test stability fix correctly identifies and resolves both the `customImageOrder` invariant and the async task interference.

However, the refactoring stopped short of full decoupling. Three patterns undermine the decomposition:

1. **Manager back-references to `CollageViewModel`** create circular dependencies
2. **Views reach directly into manager internals** bypassing the VM boundary
3. **`ImageCoordinator` became a second orchestrator** with cross-manager reset authority

The net result is that the decomposition achieved data ownership separation but not behavioral decoupling. A property rename in a manager still ripples through views, persistence, and other managers.

---

## Critical Issues

### C1. Circular Dependency: Managers hold back-references to CollageViewModel

**Files:** `BackgroundManager.swift:32`, `TitleManager.swift:69-86`

Both `BackgroundManager.updateBackground(viewModel:)` and `TitleManager.updateImage(viewModel:)` accept `CollageViewModel` as a parameter and reach into its internals:

```swift
// BackgroundManager.swift:32
func updateBackground(viewModel: CollageViewModel) {
    viewModel.previewManager.updateBackground(...)  // reaches into VM internals
}

// TitleManager.swift:69
func updateImage(viewModel: CollageViewModel) {
    viewModel.titleImageVersion += 1                // mutates VM state
    viewModel.previewManager.updateTitleImage(...)  // reaches into VM internals
}
```

**Violation:** Dependency Inversion Principle. Managers should depend on abstractions, not the concrete `CollageViewModel`. Creates a circular ownership graph: `VM → TitleManager → VM`.

**Fix:** Inject a protocol or use callbacks. For example:
```swift
protocol PreviewUpdatable {
    func updateTitleImage(attrString: NSAttributedString, style: TitleStyle, canvasSize: CGSize)
    func incrementTitleVersion()
}
```
Or have managers emit events that the VM handles.

---

### C2. ImageCoordinator is a God Class / Second Orchestrator

**File:** `ImageCoordinator.swift`

`ImageCoordinator` holds strong references to 7 dependencies (line 26-42) and `clearAll()` (lines 87-113) orchestrates a global reset across all manager boundaries:

```swift
func clearAll() {
    viewModel.backgroundManager.reset()
    viewModel.titleManager.reset()
    layoutManager.reset()
    viewModel.exportManager.exportTask?.cancel()
    cropManager.cropMap.removeAll()
    previewManager.clearAll()
    viewModel.selectedPanelId = nil
    viewModel.errorMessage = nil
}
```

**Violation:** Single Responsibility Principle. `ImageCoordinator` should manage image library state, not coordinate a full-application reset.

**Fix:** Move cross-manager coordination back to `CollageViewModel`. `ImageCoordinator.clearAll()` should only clear its own domain (images, saliency results) and return what was cleared. The VM decides what downstream effects to trigger.

---

### C3. Views Directly Access Manager Internals (30+ locations)

**Affected files:** `ContentView.swift`, `CollageEditorView.swift`, `LayoutConfigSidebar.swift`, `ImageLibrarySidebar.swift`, `StatusSidebar.swift`, `ExportPanel.swift`

The decomposition extracted managers as `@Observable` classes, but views consistently reach through the VM:

- `ContentView.swift:40` — `viewModel.imageLibrary.images.isEmpty`
- `ContentView.swift:45` — `viewModel.imageCoordinator.browseImages()`
- `CollageEditorView.swift:36` — `viewModel.layoutManager.panels`
- `LayoutConfigSidebar.swift:56` — `viewModel.layoutManager.layoutStyle`
- `StatusSidebar.swift:13` — `viewModel.exportManager.isExporting`

**Violation:** Separation of Concerns. If a manager's internal state changes, every view accessing it directly must be updated. The VM should be the single access point.

**Fix:** Add computed properties on `CollageViewModel` for all state that views need, and add convenience methods for all operations. Views should only reference `viewModel.xxx`, never `viewModel.someManager.xxx`.

---

### C4. ExportPanel Receives Managers as Direct Parameters

**File:** `ExportPanel.swift:7-8`

```swift
let backgroundManager: BackgroundManager
let titleManager: TitleManager
```

Passed from `ContentView.swift:148`:
```swift
ExportPanel(viewModel: viewModel, backgroundManager: viewModel.backgroundManager, titleManager: viewModel.titleManager)
```

**Violation:** This bypasses the VM's undo registration, debounced save, and preview update side effects. If `ExportPanel` directly sets `backgroundManager.backgroundColor = .red`, it bypasses all VM setter logic.

**Fix:** Remove the manager parameters. The `@Bindable` wrapper on the VM already enables binding to any observable property through computed properties.

---

### C5. Business Logic in Views

**Files:** `ContentView.swift:97-125`, `ExportPanel.swift:269-284`

- `handleDrop(from:)` performs file I/O and calls coordinator methods
- `chooseMaskImage()` and `chooseBackgroundImage()` are 90% duplicate `NSOpenPanel` flows

**Violation:** Presentation layer should not contain data-loading pipelines.

**Fix:** Move file-picking flows to VM methods or a dedicated coordinator. Extract the duplicated `NSOpenPanel` pattern to a shared helper.

---

### C6. UserDefaultsPersistence Reaches into Manager Hierarchy

**File:** `UserDefaultsPersistence.swift:81-111`

The `save(_:)` method accesses 17+ manager properties directly:
```swift
defaults.set(viewModel.layoutManager.layoutStyle.rawValue, ...)
defaults.set(Double(viewModel.layoutManager.gutter), ...)
defaults.set(viewModel.backgroundStyle.rawValue, ...)
```

**Violation:** Persistence depends on the concrete manager structure. Any rename breaks persistence. Prevents testing persistence in isolation.

**Fix:** Have `CollageViewModel.buildPersistenceBundle()` aggregate all persistable state into a plain struct, then save that struct. Persistence should never see managers.

---

### C7. BackgroundRenderer.renderBackground — canvasSize/previewSize Mismatch

**File:** `BackgroundRenderer.swift:58-92`

The method creates a CG context at `canvasSize` but returns `NSImage(cgImage: cgImage, size: previewSize)`. When these differ (always in preview rendering), the NSImage size metadata is wrong, causing incorrect display scale.

**Fix:** Either create the context at `previewSize` with appropriate scaling, or return `NSImage(cgImage: cgImage, size: canvasSize)` and let the caller scale.

---

### C8. CollageAssembly Protocol Too Broad

**File:** `CollageAssembler.swift:61`

```swift
protocol CollageAssembly: CollageRenderer, PanelRendering, BackgroundRendering, TitleRendering, OverlayRendering {}
```

`ExportManager` stores `any CollageAssembly` but only calls `assembleWithCGImages` (from `CollageRenderer`). It is unnecessarily coupled to 4 rendering interfaces it never uses.

**Violation:** Interface Segregation Principle.

**Fix:** Change `ExportManager` to depend on `any CollageRenderer`.

---

### C9. Inconsistent @Observable Conformance

**Files:** `CropManager.swift:7`, `ImageCoordinator.swift:14`

`CropManager` and `ImageCoordinator` lack `@Observable`, while all other managers have it. If any view reads `viewModel.cropManager.cropMap` directly, it will never receive updates.

**Fix:** Add `@Observable` to `CropManager`. Evaluate whether `ImageCoordinator` should be observable or if it should be a plain helper class.

---

### C10. Missing Test Suites for New Managers

**Missing files:**
- `ImageCoordinatorTests.swift` — 193 lines of logic, no dedicated tests
- `LayoutManagerTests.swift` — 151 lines, no dedicated tests
- `TitleManagerTests.swift` — 102 lines, no dedicated tests
- `BackgroundManagerTests.swift` — 54 lines, no dedicated tests

Key untested paths:
- `ImageCoordinator.addImages` → saliency trigger
- `ImageCoordinator.clearAll()` → cross-manager reset sequence
- `LayoutManager.regenerateLayout(preserveCrops: true)` → crop preservation flow
- `TitleManager` caching behavior and `reset()`

---

## Nit Issues

### N1. CollageViewModel Still 926 Lines

Data ownership is delegated, but behavior orchestration (undo, debounce, preview scheduling, crop gesture coordination) remains concentrated. Consider extracting crop gesture orchestration (~150 lines) into a `CropGestureOrchestrator`.

### N2. Duplicate `isInitializing` Guard Pattern

Appears in ~20 property setters with slight variations. Line 42 has a side effect in the guard (`titleManager.titleAttrString = newValue`), which is inconsistent with the simple early returns elsewhere. Consider handling `isInitializing` at the `init` level.

### N3. TitleManager.updateImageLive is a No-op Alias

`TitleManager.swift:78-80` calls `updateImage(viewModel:)` with no distinction. Either implement distinct behavior or remove.

### N4. LayoutManager.buildLayoutConfig Returns Empty Crop Map

`LayoutManager.swift:75-81` always returns `crops: [:]`. Remove if unused, or accept the crop map as a parameter.

### N5. Inconsistent Setter Patterns Across Managers

`LayoutManager` setters return old values for undo. `BackgroundManager` has no equivalent — the VM captures old values inline. Standardize.

### N6. ImageCoordinator Has IUO for viewModel

`CollageViewModel.swift:31` declares `var imageCoordinator: ImageCoordinator!`. The IUO exists because of circular init ordering. Restructure init to avoid.

### N7. Duplicate analyzeSaliency Call Paths

`ImageCoordinator.swift` calls `analyzeSaliency()` from 3 places with identical `Task { [weak self] in ... }` wrappers. Extract to `scheduleSaliencyAnalysis()`.

### N8. CollageEditorView Is 444 Lines

Handles 4+ gesture types inline. Consider extracting each into child views or gesture modifier extensions.

### N9. @unchecked Sendable Without Safety Comment

`CollageAssembler.swift:83` — Add a comment documenting why the conformance is safe.

### N10. ContextFactory.bytesPerRow Hardcodes RGBA

`ContextFactory.swift:7` — Use `nil` to let CoreGraphics calculate, or derive from color space.

---

## What's Done Well

1. **RenderScheduler** — Elegant solution to NSGraphicsContext concurrency. Serial queue + `withCheckedContinuation` gives async semantics with guaranteed serialization.

2. **Dual drawXxx/renderXxx interface** — Each renderer cleanly separates compositing (into shared context) from standalone rendering (own context). This is the key design insight enabling the layered preview architecture.

3. **Test stability fix** — The `customImageOrder` sync is a genuine production fix, not a test workaround. The async cancellation pattern is correct.

4. **Protocol-based dependency injection** — `CollageAssembly` and sub-protocols enable the test suite to use mocks while keeping production code clean.

5. **TitleTextData Sendable extraction** — Correctly addresses the CoreText-on-background-thread problem. Pure data extraction on main actor, Sendable transfer to background.

---

## Architecture Dependency Graph

```
CollageViewModel (926 lines, owns all managers)
  ├── LayoutManager (@Observable)       ← clean, no back-refs
  ├── BackgroundManager (@Observable) ──┐
  ├── TitleManager (@Observable) ───────┤ back-ref to VM (C1)
  ├── CropManager (NO @Observable)      │ ← C9
  ├── PreviewManager (@Observable)      │
  ├── ExportManager (@Observable)       │
  ├── ImageLibraryManager (@Observable) │
  └── ImageCoordinator (NO @Observable)┘ ← C9, God class (C2)
        ├── refs: imageLibrary, layoutManager, cropManager
        ├── refs: previewManager, undoManager, saliencyAnalyzer
        └── refs: viewModel (strong)    ← C1, C2

Views (30+ locations) ──────────────────┐
  reach through VM to managers directly ← C3

UserDefaultsPersistence ────────────────┐
  reaches into manager internals        ← C6
```

---

## Approval Decision

**Request Changes**

The SRP decomposition is directionally correct and represents meaningful progress. However, the circular dependencies (C1), the God class anti-pattern in `ImageCoordinator` (C2), and the pervasive direct manager access from views (C3) are architectural issues that will compound with each new feature. They should be addressed before the decomposition is considered complete.

### Recommended Fix Order

1. **Eliminate manager back-refs** (C1) — Replace with protocol/callback injection
2. **Decompose ImageCoordinator.clearAll** (C2) — Move cross-manager coordination to VM
3. **Add VM-level accessors** (C3, C4) — Computed properties and methods for all view needs
4. **Extract persistence bundle** (C6) — VM aggregates state, persistence sees only a struct
5. **Fix BackgroundRenderer size mismatch** (C7) — Correct canvasSize/previewSize handling
6. **Narrow ExportManager dependency** (C8) — Use `CollageRenderer` instead of `CollageAssembly`
7. **Add @Observable to CropManager** (C9) — Prevent latent observation bugs
8. **Add test suites** (C10) — Cover new manager classes
