# Further Decomposition Plan — CollageViewModel (Round 2)

**Source:** `CollageViewModel.swift` (1,104 lines, post-SRP Phase 1)
**Scope:** Extract remaining responsibilities from CollageViewModel into focused managers
**Target:** CollageViewModel reduced to ~400 lines
**Status:** Planned (2026-06-14)

---

## Current State

After Phase 1 of the SRP decomposition, `CollageViewModel` still retains these responsibilities:

| Responsibility | Lines (approx) |
|---|---|
| Layout state & orchestration (`layoutStyle`, `gutter`, `panels`, `panelAssignments`, `customImageOrder`, `regenerateLayout`, `setLayoutStyle`, `updateGutter`) | ~100 |
| Double Exposure settings (`doubleExposureMaskImage`, `doubleExposureMaskOpacity`, `diagonalSliceAngle`, `hexagonalSpacing`) | ~40 |
| Saliency coordination (`saliencyResults`, `analyzeSaliency`) | ~30 |
| Image loading coordination (`browseImages`, `addImages`, `removeImage`, `moveImages`, `clearAll`) | ~60 |
| Panel image assignment (`assignImage`, `getEffectiveImageIndex`, `selectPanelForImage`, `swapPanelImages`) | ~50 |
| Preview & export orchestration (`updatePreview`, `updateAllPanelPreviews`, `updatePanelPreview`, `buildAssemblyConfig`, `exportCollage`) | ~100 |
| Crop gesture coordination (throttling, debouncing, version counters) | ~80 |
| Background/title pass-through properties (undo/debounce wrappers) | ~120 |
| Undo helpers, processing state, error state, init, convenience methods | ~60 |

---

## Phase 1: Extract `LayoutManager`

**Goal:** Move all layout-related state and regeneration logic into a dedicated manager. This was deferred in the prior plan as "inherently cross-cutting" — but with `CropManager` and `PreviewManager` now well-established, the cross-cutting concerns are resolvable via dependency injection.

**New file:** `ViewModel/LayoutManager.swift`

**Move from `CollageViewModel`:**
- Properties (6): `layoutStyle`, `gutter`, `diagonalSliceAngle`, `hexagonalSpacing`, `panels`, `panelAssignments`
- Properties (3): `doubleExposureMaskImage`, `doubleExposureMaskImagePath`, `doubleExposureMaskOpacity`
- Methods: `regenerateLayout(preserveCrops:)`, `setLayoutStyle(_:)`, `updateGutter(_:)`

**Design:**
```swift
@MainActor
@Observable
final class LayoutManager {
    var layoutStyle: LayoutStyle = .hero
    var gutter: CGFloat = 0
    var diagonalSliceAngle: CGFloat = 45.0
    var hexagonalSpacing: CGFloat = 8.0

    var panels: [ImagePanel] = []
    var panelAssignments: [UUID: Int] = [:]

    // Double exposure
    var doubleExposureMaskImage: NSImage?
    var doubleExposureMaskImagePath: String?
    var doubleExposureMaskOpacity: CGFloat = 0.5

    func regenerateLayout(
        images: [ImageItem],
        customImageOrder: [Int],
        cropManager: CropManager,
        previewManager: PreviewManager,
        preserveCrops: Bool
    )

    func buildLayoutConfig() -> LayoutConfig
}
```

**Key decisions:**
- `regenerateLayout` takes `CropManager` and `PreviewManager` as parameters to avoid circular dependencies
- `panelAssignments` moves here (it's layout-adjacent state)
- Double exposure settings move here (they affect assembly layout)
- `customImageOrder` stays in `ImageLibraryManager` (it's image-order state, not layout state)

**Callers to update:**
- `ContentView.sidebar` — bind to `viewModel.layoutManager.*`
- `ExportPanel` — bind to `viewModel.layoutManager.*`
- `UserDefaultsPersistence` — read/write through `viewModel.layoutManager.*`
- `buildAssemblyConfig()` — read from `layoutManager`
- `clearAll()` — delegate to `layoutManager.reset()`

**Tests:** Create `LayoutManagerTests.swift`. Migrate layout tests from `CollageViewModelTests`.

**Complexity:** 2 hrs

---

## Phase 2: Extract `ImageCoordinator`

**Goal:** Move image loading, reordering, removal, and panel assignment logic into a single coordinator. Currently `CollageViewModel` wraps `ImageLibraryManager` calls with undo registration, saliency triggers, and panel selection — this is a cohesive unit of work.

**New file:** `ViewModel/ImageCoordinator.swift`

**Move from `CollageViewModel`:**
- Methods: `browseImages()`, `addImages(from:)`, `removeImage(at:)`, `moveImages(from:to:)`, `clearAll()`
- Methods: `assignImage(_:to:)`, `getEffectiveImageIndex(for:)`, `selectPanelForImage(at:)`, `swapPanelImages(sourceId:targetId:)`

**Design:**
```swift
@MainActor
final class ImageCoordinator {
    let imageLibrary: ImageLibraryManager
    let layoutManager: LayoutManager
    let cropManager: CropManager
    let previewManager: PreviewManager
    let undoManager: UndoManager
    let saliencyAnalyzer: SaliencyAnalysis
    let saveCallback: () -> Void

    // Image operations
    func browseImages()
    func addImages(from urls: [URL]) async
    func removeImage(at index: Int)
    func moveImages(from: IndexSet, to: Int)
    func clearAll(viewModel: CollageViewModel)

    // Panel assignment
    func assignImage(_ imageIndex: Int, to panelId: UUID)
    func getEffectiveImageIndex(for panelId: UUID) -> Int?
    func selectPanelForImage(at imageIndex: Int)
    func swapPanelImages(sourceId: UUID, targetId: UUID)

    // Saliency (moved from VM, since it's triggered by image changes)
    func analyzeSaliency() async
    private var saliencyResults: [Int: SaliencyResult] = [:]
}
```

**Key decisions:**
- `saliencyResults` and `analyzeSaliency` move here because saliency is triggered by image operations and feeds into crop computation — it's part of the "image pipeline"
- `clearAll` needs a reference to `CollageViewModel` to clear preview, export, and error state
- Undo registration for image operations moves into this coordinator
- `selectedPanelId` stays in `CollageViewModel` (it's a UI selection concern, not image management)

**Callers to update:**
- `ContentView.sidebar` — delegate to `viewModel.imageCoordinator.*`
- `CollageEditorView` — delegate to `viewModel.imageCoordinator.*`
- `ContentView.toolbar` — `clearAll` delegates to coordinator

**Tests:** Create `ImageCoordinatorTests.swift`. Migrate image operation tests from `CollageViewModelTests`.

**Complexity:** 2 hrs

---

## Phase 3: Thin Down `CollageViewModel`

**Goal:** After Phases 1-2, the ViewModel becomes a thin coordinator that:
- Instantiates and holds all managers
- Handles `init` / persistence loading
- Provides `buildAssemblyConfig()` (gathers config from all managers)
- Provides `updatePreview()` / `updateAllPanelPreviews()` (orchestrates preview rendering)
- Provides `exportCollage()` (orchestrates export)
- Manages crop gesture coordination (throttling, version counters)
- Manages undo helpers, processing state, error state

**Remaining in `CollageViewModel` (~400 lines):**

| Section | Lines |
|---|---|
| Imports, loggers, init, convenience init | ~50 |
| Computed properties delegating to managers (`title`, `titleStyle`, `backgroundColor`, etc.) | ~80 |
| `cropMap` + throttled notification | ~30 |
| Undo helpers (`registerUndo`, `beginGestureUndo`, `endGestureUndo`) | ~20 |
| Crop gesture methods (delegate to `CropManager` + throttle/notify) | ~60 |
| Scroll pan methods | ~30 |
| Overlay crop methods | ~30 |
| `buildAssemblyConfig()` | ~30 |
| `updatePreview()`, `updateAllPanelPreviews()`, `updatePanelPreview()` | ~40 |
| `exportCollage()` | ~20 |
| Processing state, error state, `debouncedSave` | ~10 |

**Key changes:**
- Remove `layoutStyle`, `gutter`, `panels`, `panelAssignments`, `doubleExposure*` — now on `LayoutManager`
- Remove `saliencyResults`, `analyzeSaliency` — now on `ImageCoordinator`
- Remove `browseImages`, `addImages`, `removeImage`, `moveImages`, `clearAll` — now on `ImageCoordinator`
- Remove `assignImage`, `getEffectiveImageIndex`, `selectPanelForImage`, `swapPanelImages` — now on `ImageCoordinator`
- Remove `regenerateLayout`, `setLayoutStyle`, `updateGutter` — now on `LayoutManager`
- `buildAssemblyConfig()` simplified to read from `layoutManager`, `titleManager`, `backgroundManager`, `cropManager`
- `updatePreview()` simplified to call `buildAssemblyConfig()` and delegate to `previewManager`

**Complexity:** 1.5 hrs (mostly mechanical refactoring)

---

## Phase 4: Persistence & View Updates

**Goal:** Update `UserDefaultsPersistence` and all views to use the new manager paths.

**`UserDefaultsPersistence` changes:**
- `save(_ viewModel:)` — read through `viewModel.layoutManager.*`, `viewModel.imageCoordinator.*`
- `load()` — set on `viewModel.layoutManager.*`, `viewModel.imageCoordinator.*`
- `PersistenceBundle` struct — add `LayoutBundle` and `ImageCoordinatorBundle` nested types if needed

**View binding changes:**
- `ContentView.sidebar` — change `viewModel.layoutStyle` → `viewModel.layoutManager.layoutStyle`
- `ExportPanel` — change `viewModel.backgroundColor` → `viewModel.backgroundManager.backgroundColor`, etc.
- `CollageEditorView` — change `viewModel.cropMap` stays, `viewModel.selectedPanelId` stays

**Complexity:** 1 hr

---

## Risks and Mitigations

### Risk 1: Circular Dependencies Between Managers

**Problem:** `LayoutManager.regenerateLayout` needs `CropManager` and `PreviewManager`. `ImageCoordinator` needs `LayoutManager`, `CropManager`, `PreviewManager`, and `CollageViewModel`.

**Mitigation:**
- Use parameter injection (pass managers as method arguments) rather than stored properties where possible
- `ImageCoordinator` holds weak references to `CollageViewModel` for callbacks
- No manager holds a strong reference back to `CollageViewModel`

### Risk 2: `@Observable` Delegation Chain

**Problem:** Views bound to `viewModel.layoutManager.layoutStyle` may not receive updates if the observation chain breaks.

**Mitigation:**
- `LayoutManager` is `@Observable` — views binding to `viewModel.layoutManager.layoutStyle` will receive updates
- Computed property delegation in `CollageViewModel` for backward compatibility: `var layoutStyle: LayoutStyle { layoutManager.layoutStyle }`

### Risk 3: Undo Registration Across Coordinators

**Problem:** `ImageCoordinator` needs to register undo actions on `CollageViewModel`'s `UndoManager`.

**Mitigation:**
- Pass `UndoManager` to `ImageCoordinator` at construction
- Undo closures reference `imageLibrary`, `layoutManager`, `cropManager` directly
- Pattern: `undoManager.registerUndo { target in target.imageCoordinator.imageLibrary.images.insert(removed, at: at) }`

### Risk 4: `isInitializing` Guard

**Problem:** `isInitializing` is currently on `CollageViewModel` and checked by background/title computed properties.

**Mitigation:**
- Keep `isInitializing` on `CollageViewModel`
- `LayoutManager` and `ImageCoordinator` do not need their own guard — their state is set during `CollageViewModel.init` before `isInitializing = false`
- The computed property wrappers in `CollageViewModel` continue to check `isInitializing`

---

## Summary

| Step | New File(s) | Files Changed | Complexity | Estimate |
|------|-------------|---------------|------------|----------|
| 1: `LayoutManager` | `ViewModel/LayoutManager.swift` | 6 | Medium | 2 hrs |
| 2: `ImageCoordinator` | `ViewModel/ImageCoordinator.swift` | 5 | Medium | 2 hrs |
| 3: Thin down VM | (none) | 1 | Medium | 1.5 hrs |
| 4: Persistence & views | (none) | 6 | Low | 1 hr |
| **Total** | **2 new files** | | | **~6.5 hrs** |

---

## Post-Decomposition File Structure

```
ViewModel/
├── CollageViewModel.swift        (~400 lines, down from 1,104)
│   ├── init / persistence loading
│   ├── Manager references
│   ├── Computed property delegation (title, background, layout)
│   ├── cropMap + throttled notification
│   ├── Undo helpers
│   ├── Crop gesture delegation (pan, pinch, overlay, scroll pan)
│   ├── buildAssemblyConfig()
│   ├── updatePreview() / updateAllPanelPreviews()
│   └── exportCollage()
├── LayoutManager.swift           (~80 lines, new)
│   ├── layoutStyle, gutter, diagonalSliceAngle, hexagonalSpacing
│   ├── panels, panelAssignments
│   ├── doubleExposure settings
│   └── regenerateLayout(), buildLayoutConfig()
├── ImageCoordinator.swift        (~120 lines, new)
│   ├── browseImages, addImages, removeImage, moveImages, clearAll
│   ├── assignImage, swapPanelImages, selectPanelForImage
│   └── analyzeSaliency(), saliencyResults
├── CropManager.swift             (~450 lines, unchanged)
├── TitleManager.swift            (~100 lines, unchanged)
├── BackgroundManager.swift       (~55 lines, unchanged)
├── ExportManager.swift           (~110 lines, unchanged)
├── ImageLibraryManager.swift     (~145 lines, unchanged)
└── Debouncer.swift               (unchanged)

Services/
├── PreviewManager.swift          (unchanged)
├── CollageAssembler.swift        (unchanged)
├── LayoutGenerator.swift         (unchanged)
└── ... (rest unchanged)
```
