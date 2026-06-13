# SRP Decomposition Plan — CollageMaker

**Source reviews:** `_agent_docs/reviews/2026-06-12-review-mitch.md`, `_agent_docs/reviews/2026-06-12-review-harold.md`
**Scope:** Decompose CollageViewModel (1,092 lines), CollageEditorView, CollageAssembler (497 lines), PanelCropEditor (674 lines), ContentView.sidebar (260 lines)
**Target:** CollageViewModel reduced to ~450 lines; 5-6 focused managers; pure geometry utilities
**Deferred:** LayoutManager extraction (layout orchestration is inherently cross-cutting)
**Status:** Phase 2 complete (2026-06-13)

---

## Phase 0: Pure Utilities (No dependencies, zero risk)

### 0.1 Extract `PolygonClipper`

**Goal:** Remove Sutherland-Hodgman clipping algorithm from `PanelCropEditor.swift` into a pure struct.

**New file:** `Services/PolygonClipper.swift`

**Extract from `Views/PanelCropEditor.swift`:**
- `clipPolygon(_ subject: [CGPoint], to clipRect: CGRect) -> [CGPoint]`
- `ClipEdge` enum
- (~70 lines total)

**Design:**
```swift
/// Pure struct — Sutherland-Hodgman polygon clipping.
struct PolygonClipper {
    static func clip(_ subject: [CGPoint], to clipRect: CGRect) -> [CGPoint]
}
```

**Callers to update:**
- `CropPreviewView.computeQuadInContainer` — change to `PolygonClipper.clip`

**Tests:** Create `PolygonClipperTests.swift` — rectangle clip, point-on-edge, empty input, fully inside/outside.

**Complexity:** 15 min

---

### 0.2 Consolidate Coordinate Math into `CoordinateConverter`

**Goal:** Move all coordinate transform static methods from `CropManager` and views into the existing `CoordinateConverter` pure struct.

**Move from `CropManager`:**
- `static func screenToCanvasPoint(_:in:)` — pure transform
- `static func hitTestPanel(at:panelFrames:panelGeometries:previewSize:)` — pure geometry

**Remove from views:**
- `CollageEditorView.canvasToPreviewFrame()` — already delegated to `CoordinateConverter`
- `CollageEditorView.panelAt()` — replace with `CoordinateConverter.hitTestPanel`
- `TitleDragHandler.canvasToPreviewFrame()` — already uses `CropManager.canvasToPreviewFrame` which delegates to `CoordinateConverter`

**After this step, `CropManager` is purely crop-state management with no static geometry methods.**

**Tests:** Extend `CoordinateConverterTests.swift` with hit-test and screen-to-canvas cases.

**Complexity:** 30 min

---

## Phase 1: Manager Extractions (Medium risk)

### 1.1 Extract `BackgroundManager`

**Goal:** Remove all background state and setters from `CollageViewModel`.

**New file:** `ViewModel/BackgroundManager.swift`

**Move from `CollageViewModel`:**
- Properties (8): `backgroundColor`, `backgroundStyle`, `gradientStartColor`, `gradientEndColor`, `gradientAngle`, `backgroundImage`, `backgroundImagePath`, `backgroundOpacity`
- Methods: `setBackgroundImage()`, `updateBackground()`
- All associated `didSet` logic (debounced save + undo + preview update)

**Design:**
```swift
@MainActor
@Observable
final class BackgroundManager {
    var isInitializing: Bool = false

    var backgroundColor: NSColor = .black
    var backgroundStyle: BackgroundStyle = .solid
    var gradientStartColor: NSColor = .black
    var gradientEndColor: NSColor = .darkGray
    var gradientAngle: Double = 0
    var backgroundImage: NSImage?
    var backgroundImagePath: String?
    var backgroundOpacity: Double = 1.0

    func buildConfig() -> BackgroundConfig
    func setBackgroundImage(_ image: NSImage, viewModel: CollageViewModel)
    func updateBackground(viewModel: CollageViewModel)
}
```

**ViewModel delegation pattern:**
```swift
// In CollageViewModel:
var backgroundManager: BackgroundManager = BackgroundManager()

// Computed properties for backward compatibility:
var backgroundColor: NSColor {
    get { backgroundManager.backgroundColor }
    set {
        let old = backgroundManager.backgroundColor
        backgroundManager.backgroundColor = newValue
        registerUndo(oldValue: old, actionName: "Background Color", target: \.backgroundColor)
        debouncedSave()
        backgroundManager.updateBackground(viewModel: self)
    }
}
// ... similar for other background properties
```

**Callers to update:**
- `UserDefaultsPersistence.save` — read from `viewModel.backgroundManager.*`
- `UserDefaultsPersistence.load` — set on `viewModel.backgroundManager.*`
- `ExportPanel` bindings — use `viewModel.backgroundManager.*`
- `buildAssemblyConfig()` — read from `backgroundManager`
- `clearAll()` — delegate to `backgroundManager.reset()`

**Tests:** Create `BackgroundManagerTests.swift`. Update `CollageViewModelTests` to access through manager.

**Complexity:** 1.5 hrs

---

### 1.2 Extract `TitleManager`

**Goal:** Remove all title state, CoreText caching, setter methods, and drag state from `CollageViewModel`.

**New file:** `ViewModel/TitleManager.swift`

**Move from `CollageViewModel`:**
- Properties: `titleAttrString`, `titleStyle`, `isDraggingTitle`, `cachedTitleBounds`, `cachedTitleLayoutKey`, `cachedTitleString`, `titleImageVersion`
- Computed: `title`, `cachedTitleCanvasFrame`, `cachedTitleMinWidth`
- Methods: 9 `setTitle*` methods, `updateTitleImage()`, `updateTitleImageLive()`, `finishTitleDrag()`, `registerTitleStyleUndo()`, `applyTitleChange()`, `titleViewUpdate()`, `ensureTitleBounds()`
- (~150 lines total)

**Design:**
```swift
@MainActor
@Observable
final class TitleManager {
    var isInitializing: Bool = false

    var titleAttrString: NSAttributedString = NSAttributedString(string: "")
    var titleStyle: TitleStyle = .defaultStyle
    var isDraggingTitle: Bool = false

    private var cachedBounds: TitleBoundsCache?
    private var cachedLayoutKey: TitleStyle.LayoutKey?
    private var cachedString: NSAttributedString?
    var titleImageVersion: Int = 0

    var canvasFrame: CGRect?
    var minWidth: CGFloat

    func setFontFamily(_ family: String, viewModel: CollageViewModel)
    func setFontSize(_ size: CGFloat, viewModel: CollageViewModel)
    func setFontColor(_ color: NSColor, viewModel: CollageViewModel)
    func setBackgroundColor(_ color: NSColor, viewModel: CollageViewModel)
    func setAlignment(_ alignment: NSTextAlignment, viewModel: CollageViewModel)
    func setShowBackground(_ show: Bool, viewModel: CollageViewModel)
    func setWeight(_ weight: Font.Weight, viewModel: CollageViewModel)
    func setItalic(_ italic: Bool, viewModel: CollageViewModel)
    func setUnderline(_ underline: Bool, viewModel: CollageViewModel)

    func updateImage(viewModel: CollageViewModel)
    func updateImageLive(viewModel: CollageViewModel)
    func finishDrag(viewModel: CollageViewModel)
}
```

**`@Observable` tracking:** Use version counter for `canvasFrame` and `minWidth` (matches existing `titleImageVersion` precedent). Direct delegate read for `titleStyle` and `titleAttrString`.

**ViewModel delegation:**
```swift
// In CollageViewModel:
var titleManager: TitleManager = TitleManager()

var titleStyle: TitleStyle {
    get { titleManager.titleStyle }
    set { titleManager.titleStyle = newValue }
}
var cachedTitleCanvasFrame: CGRect? { titleManager.canvasFrame }
var cachedTitleMinWidth: CGFloat { titleManager.minWidth }
var isDraggingTitle: Bool { titleManager.isDraggingTitle }
```

**Callers to update:**
- `UserDefaultsPersistence.save` — read from `viewModel.titleManager.*`
- `UserDefaultsPersistence.load` — set on `viewModel.titleManager.*`
- `ExportPanel` title bindings — call `viewModel.titleManager.setFontFamily(...)` etc.
- `CollageEditorView` title drag — call `viewModel.titleManager.*`
- `buildAssemblyConfig()` — read from `titleManager`
- `clearAll()` — delegate to `titleManager.reset()`

**Tests:** Create `TitleManagerTests.swift`. Migrate title tests from `CollageViewModelTests`.

**Complexity:** 2.5 hrs

---

## Phase 2: View Cleanup (Low risk, depends on Phase 1)

### 2.1 Clean `CollageEditorView`

**Goal:** Remove coordinate math and hit testing from the view body; delegate to `CoordinateConverter`.

**File:** `Views/CollageEditorView.swift`

**Changes:**
- Remove `canvasToPreviewFrame()` private method — replace all calls with `CoordinateConverter.canvasToPreviewFrame`
- Remove `panelAt()` private method — replace with `CoordinateConverter.hitTestPanel`
- Keep gesture closures (gesture logic is a view-layer concern)
- Keep `GestureCoordinator` (already extracted as `@Observable` class)

**Net effect:** Body shrinks by ~20 lines of math; becomes purely declarative UI + gesture coordination.

**Tests:** No new tests needed (behavior unchanged).

**Complexity:** 30 min

---

### 2.2 Decompose `ContentView.sidebar`

**Goal:** Split the 260-line `sidebar` computed property into focused sub-views.

**New files:**
- `Views/ImageLibrarySidebar.swift` (~100 lines) — search, image list, drag-drop, browse
- `Views/LayoutConfigSidebar.swift` (~90 lines) — layout picker, gutter, style-specific controls
- `Views/StatusSidebar.swift` (~40 lines) — processing indicator, panel count notice

**Design:**
```swift
// In ContentView:
private var sidebar: some View {
    Form {
        ImageLibrarySidebar(viewModel: viewModel)
        LayoutConfigSidebar(viewModel: viewModel)
        if !viewModel.imageLibrary.images.isEmpty {
            StatusSidebar(viewModel: viewModel)
        }
    }
    .formStyle(.grouped)
    // drag-drop overlay and tap-to-browse stay in parent (apply to whole sidebar)
}
```

Each subview: `struct: View` with `@Bindable var viewModel: CollageViewModel`.

**Tests:** No new tests needed (UI-only decomposition).

**Complexity:** 30 min

---

## Phase 3: Assembler Split (Medium risk, independent)

### 3.1 Split `CollageAssembler` into Focused Renderers

**Goal:** Split the 497-line `CollageAssembler` into focused renderer structs coordinated by a thin orchestrator.

**New files:**
- `Services/PanelRenderer.swift` (~80 lines) — `renderPanel()`, `drawPanels()`, `drawClampedCrop()`
- `Services/BackgroundRenderer.swift` (~60 lines) — `renderBackground()`, `drawGradient()`, `drawImageBackground()`
- `Services/OverlayRenderer.swift` (~20 lines) — `renderOverlay()`, `drawOverlay()`

**Refactored `CollageAssembler` (~120 lines):**
```swift
final class CollageAssembler: CollageAssembly, @unchecked Sendable {
    private let scheduler = RenderScheduler()
    private let panelRenderer = PanelRenderer()
    private let backgroundRenderer = BackgroundRenderer()
    private let overlayRenderer = OverlayRenderer()

    // Orchestrator methods:
    func assembleWithCGImages(...) -> NSImage?
    func assemblePreviewWithCGImages(...) -> NSImage?
    // Context creation helpers stay here
}
```

**Key decisions:**
- Protocol composition (`CollageAssembly: CollageRenderer, PanelRenderer, ...`) stays — it's well-designed for test mocking
- `RenderScheduler` stays shared (thread-safety mechanism for `NSGraphicsContext.current`)
- Title rendering already uses `TitleRendererCT` — no extraction needed
- Context creation helpers (`createPureCGContext`, `createBitmapContext`) stay in orchestrator

**Tests:** Update `CollageAssemblerTests` to test orchestrator behavior. Create test files for each renderer.

**Complexity:** 1.5 hrs

---

## Risks and Mitigations

### Risk 1: `@Observable` Delegation Chain Breakage

**Problem:** Views reading `viewModel.backgroundColor` break if computed property delegation doesn't properly propagate observation events.

**Mitigation:**
- Version counter pattern for async-updated properties (precedent: `cropMapVersion`, `titleImageVersion`)
- Computed property delegation for synchronous reads
- Test with `CollageViewModelTests` after each extraction

### Risk 2: Undo Registration Across Managers

**Problem:** Undo actions register on `self` (ViewModel); after extraction, undo targets need to restore through managers.

**Mitigation:**
- Keep `undoManager` on `CollageViewModel` (it is the coordinator)
- Manager methods accept `viewModel: CollageViewModel` for undo registration
- Pattern: `undoManager.registerUndo(withTarget: viewModel) { target in target.backgroundManager.backgroundColor = oldValue }`
- Matches existing `ImageLibraryManager` pattern

### Risk 3: Persistence Layer Coupling

**Problem:** `UserDefaultsPersistence.save(_ viewModel:)` reads properties directly from `CollageViewModel`.

**Mitigation:**
- Update `save` to read from `viewModel.backgroundManager.*` and `viewModel.titleManager.*`
- `PersistenceBundle` stays flat (just a data struct)
- `ViewModelPersistence` protocol signature unchanged
- `UserDefaultsPersistence.Keys` unchanged

### Risk 4: `isInitializing` Guard Proliferation

**Problem:** Each extracted manager needs its own `isInitializing` guard to prevent `didSet` side effects during ViewModel init.

**Mitigation:**
- Each manager has its own `isInitializing` flag, set by ViewModel during construction
- Alternative: managers expose `applyChange(value, viewModel)` methods instead of `didSet` — cleaner but more plumbing

### Risk 5: Test Breakage

**Problem:** 18+ test files reference `CollageViewModel` properties that move to managers.

**Mitigation:**
- Run full test suite after each phase
- `makeViewModel()` helper unchanged (ViewModel init stays the same)
- Access pattern: `vm.backgroundColor` becomes `vm.backgroundManager.backgroundColor`

---

## Summary

| Step | New File(s) | Files Changed | Complexity | Estimate |
|------|-------------|---------------|------------|----------|
| 0.1: `PolygonClipper` | `Services/PolygonClipper.swift` | 2 | Low | 15 min |
| 0.2: Coordinate math | (update `CoordinateConverter`) | 4 | Low | 30 min |
| 1.1: `BackgroundManager` | `ViewModel/BackgroundManager.swift` | 6 | Medium | 1.5 hrs |
| 1.2: `TitleManager` | `ViewModel/TitleManager.swift` | 7 | Medium-High | 2.5 hrs |
| 2.1: EditorView cleanup | (none) | 1 | Low | 30 min |
| 2.2: Sidebar decomposition | 3 new Views | 4 | Low | 30 min |
| 3.1: Assembler split | 3 new Services | 5 | Medium | 1.5 hrs |
| **Total** | **7 new files** | | | **~7.5 hrs** |

---

## Post-Decomposition File Structure

```
ViewModel/
├── CollageViewModel.swift        (~450 lines, down from 1,092)
├── BackgroundManager.swift       (~100 lines, new)
├── TitleManager.swift            (~150 lines, new)
├── CropManager.swift             (unchanged, minus static methods)
├── ExportManager.swift           (unchanged)
├── ImageLibraryManager.swift     (unchanged)
└── Debouncer.swift               (unchanged)

Services/
├── CollageAssembler.swift        (~120 lines, down from 497)
├── PanelRenderer.swift           (~80 lines, new)
├── BackgroundRenderer.swift      (~60 lines, new)
├── OverlayRenderer.swift         (~20 lines, new)
├── PolygonClipper.swift          (~40 lines, new)
├── PreviewManager.swift          (unchanged)
├── CoordinateConverter.swift     (updated, ~20 new lines)
└── ... (rest unchanged)

Views/
├── CollageEditorView.swift       (~400 lines, down from 448)
├── PanelCropEditor.swift         (~580 lines, down from 674)
├── ImageLibrarySidebar.swift     (~100 lines, new)
├── LayoutConfigSidebar.swift     (~90 lines, new)
├── StatusSidebar.swift           (~40 lines, new)
├── ContentView.swift             (~200 lines, down from 383)
└── ... (rest unchanged)
```
