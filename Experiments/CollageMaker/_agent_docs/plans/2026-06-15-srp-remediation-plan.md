# SRP Decomposition — Remediation Plan

**Date:** 2026-06-15
**Based on:** Jasper review (`_agent_docs/reviews/2026-06-15-review-jasper.md`) + Richard review (`_agent_docs/reviews/2026-06-15-review-richard.md`)
**Validated by:** planner, planner-g31, manual spot-checks

---

## Validation Summary

All findings from both reviews confirmed against current codebase state.

| Finding | Source | Severity | Validated | Notes |
|---------|--------|----------|-----------|-------|
| C1: Manager back-refs to VM | Jasper | Critical | ✅ | 4 methods in TitleManager + BackgroundManager |
| C2: ImageCoordinator God class | Jasper | Critical | ✅ | 8 dependencies, cross-manager clearAll() |
| C3: Views access manager internals | Jasper | High | ✅ | 69 locations across 8 view files |
| C4: ExportPanel manager params | Jasper | Medium | ✅ | Mostly unused, trivial fix |
| C5: Business logic in views | Jasper | Medium | ✅ | NSOpenPanel duplication |
| C6: Persistence reaches managers | Jasper | Medium | ✅ | 6 direct accesses (not 17 as claimed) |
| C7: BackgroundRenderer size mismatch | Jasper | Medium | ✅ | canvasSize ≠ previewSize at line 91 |
| C8: CollageAssembly too broad | Jasper | Low | ✅ | 1-line fix |
| C9: Missing @Observable | Jasper | Low | ✅ | CropManager, has cropMapVersion workaround |
| C10: Missing test suites | Jasper | Medium | ✅ | 4 managers lack dedicated tests |
| R1: Crop logic in PanelCropEditor | Richard | High | ✅ | Lines 173–357, ~185 lines of math |
| R2: Title logic in CollageEditorView | Richard | High | ✅ | Lines 164–285, hit-testing + resize |
| R3: Magic numbers in LayoutGenerator | Richard | Low | ✅ | 0.25, 0.33, 0.4, 0.3, 0.6 |
| R4: panelFrames computed in body | Richard | Medium | ✅ | Line 36, runs on every body evaluation |
| R5: Accessibility gaps | Richard | Medium | ✅ | Title resize handles lack labels/traits |

---

## Execution Rules

- **Sequential phases** — each phase must pass its gate before the next begins
- **Per-file mechanical passes** — Phase 4 touches one view file at a time with build + test gate
- **TDD for Phase 6** — write tests for new manager methods before extracting view logic
- **Polish stays separate** — Phase 8 is a final cleanup, not interleaved

---

## Phase 1: Quick Wins (0.5 days)

Low-risk, high-signal fixes. No dependencies on other phases.

### 1.1 — C8: Narrow ExportManager dependency
- **File:** `ExportManager.swift:54`
- **Change:** `private let assembler: any CollageAssembly` → `private let assembler: any CollageRenderer`
- **Rationale:** ExportManager only calls `assembleWithCGImages()` from `CollageRenderer`. Depends on 4 rendering interfaces it never uses.

### 1.2 — C4: Remove ExportPanel manager parameters
- **Files:** `ExportPanel.swift:7-8`, `ContentView.swift:148`
- **Change:** Remove `backgroundManager` and `titleManager` parameters. Replace `titleManager.titleStyle.fontFamily` with `viewModel.titleStyle.fontFamily`.
- **Rationale:** Parameters are unused except for one `displayFamily` computed property. Bypasses VM undo/save/preview side effects.

### 1.3 — C9: Add @Observable to CropManager
- **Files:** `CropManager.swift:7`, `CollageViewModel.swift:34, 100-110`
- **Change:** Add `@Observable` to CropManager. Remove `cropMapVersion` workaround and `notifyCropMapChanged()` / `throttledNotifyCropMapChanged()` from VM.
- **Rationale:** Eliminates the version counter hack. CropManager becomes properly observable.

### 1.4 — C7: Fix BackgroundRenderer size mismatch
- **File:** `BackgroundRenderer.swift:91`
- **Change:** `NSImage(cgImage: cgImage, size: previewSize)` → `NSImage(cgImage: cgImage, size: canvasSize)`
- **Rationale:** CG context created at canvasSize, but NSImage tagged with previewSize. Wrong size metadata causes incorrect display scale.

### 1.5 — N3: Remove TitleManager.updateImageLive no-op
- **File:** `TitleManager.swift:78-80`
- **Change:** Remove `updateImageLive(viewModel:)`. Update all call sites to `updateImage(viewModel:)`.
- **Rationale:** It's an exact alias with no distinction.

### 1.6 — N4: Remove dead LayoutManager.buildLayoutConfig
- **File:** `LayoutManager.swift:75-81`
- **Change:** Remove the method that always returns `crops: [:]` and is never called.
- **Rationale:** Dead code.

### 1.7 — N9: Add @unchecked Sendable safety comment
- **File:** `CollageAssembler.swift:83`
- **Change:** Add comment documenting why the conformance is safe (all mutable state is MainActor-isolated).
- **Rationale:** Documentation for future maintainers.

**Gate:** `xcodebuild` build + `xcodebuild test`

---

## Phase 2: Break Circular Dependencies (C1) (1.5 days)

Managers currently accept `CollageViewModel` and reach into its internals, creating circular ownership graphs.

### 2.1 — Create PreviewUpdatable protocol
- **New file:** `ViewModel/PreviewUpdatable.swift`
- **Methods:**
  - `func updateTitleImage(attrString: NSAttributedString, style: TitleStyle, canvasSize: CGSize)`
  - `func incrementTitleVersion()`
  - `func updateBackground(config: BackgroundConfig, canvasSize: CGSize, backgroundImage: CGImage?, previewSize: CGSize)`
  - `func cancelDebouncer(id: String)`
  - `func debouncedSave()`

### 2.2 — Create ImageCoordinationTarget protocol
- **New file:** `ViewModel/ImageCoordinationTarget.swift`
- **Members:**
  - `func beginProcessing()` / `func endProcessing()`
  - `var isProcessing: Bool { get }`
  - `func updatePreview()` / `func updateAllPanelPreviews()` / `func updatePanelPreview(panelId: UUID)`
  - `func resetCrop(panelId: UUID)`
  - `var selectedPanelId: UUID? { get set }`
  - `var errorMessage: String? { get set }`
  - `var customImageOrder: [Int] { get set }`
  - `func regenerateLayout()`
  - `func cancelDebouncer(id: String)`

### 2.3 — CollageViewModel conforms to both protocols
- **File:** `CollageViewModel.swift`
- **Change:** Add `extension CollageViewModel: PreviewUpdatable` and `extension CollageViewModel: ImageCoordinationTarget` delegating to existing methods.

### 2.4 — Refactor TitleManager
- **File:** `TitleManager.swift`
- **Changes:**
  - `updateImage(viewModel:)` → `updateImage(updater: PreviewUpdatable)`
  - `finishDrag(viewModel:)` → `finishDrag(updater: PreviewUpdatable)`
  - `updateImageLive(viewModel:)` → removed (Phase 1.5)

### 2.5 — Refactor BackgroundManager
- **File:** `BackgroundManager.swift`
- **Change:** `updateBackground(viewModel:)` → `updateBackground(updater: PreviewUpdatable)`

### 2.6 — Refactor ImageCoordinator
- **File:** `ImageCoordinator.swift`
- **Change:** Replace `private let viewModel: CollageViewModel` with `private let target: ImageCoordinationTarget`. All VM calls go through `target`.

### 2.7 — Update all call sites
- **Files:** `CollageViewModel.swift` (init + callers)
- **Change:** Pass `self as any PreviewUpdatable` / `self as any ImageCoordinationTarget` to managers.

**Gate:** Build + full test suite + app launches without crashes

---

## Phase 3: Decompose ImageCoordinator (C2) (2 days)

ImageCoordinator is a second orchestrator with cross-manager reset authority. Reduce it to managing only its own domain (images, saliency).

### 3.1 — Extract clearAll to clearDomain
- **File:** `ImageCoordinator.swift:87-113`
- **Change:** `clearAll()` → `clearDomain()` only clears `imageLibrary` and `saliencyResults`. Returns `(oldImages: [NSImage], oldPanels: [ImagePanel], oldCropMap: [UUID: CropInfo])`.

### 3.2 — VM handles cross-manager reset
- **File:** `CollageViewModel.swift`
- **Change:** New `clearAll()` method that calls `imageCoordinator.clearDomain()`, then resets backgroundManager, titleManager, layoutManager, cropManager, previewManager, exportManager, selectedPanelId, errorMessage. Registers undo.

### 3.3 — Extract undo registration from coordinator
- **File:** `ImageCoordinator.swift:59-85, 140-161`
- **Change:** `removeImage`, `moveImages`, `swapPanelImages` no longer do undo registration. They return the data needed for undo. VM wrapper methods handle undo + downstream effects.

New pattern:
```swift
// ImageCoordinator:
func removeImage(at index: Int) -> (image: NSImage, at: Int)? { ... }

// CollageViewModel:
func removeImage(at index: Int) {
    guard let (removed, at) = imageCoordinator.removeImage(at: index) else { return }
    undoManager.registerUndo(withTarget: self) { target in
        target.imageLibrary.images.insert(removed, at: at)
        target.regenerateLayout()
    }
    // ... saliency, preview, etc.
}
```

### 3.4 — Saliency callbacks through protocol
- **File:** `ImageCoordinator.swift:165-192`
- **Change:** All `viewModel.xxx` calls in `analyzeSaliency()` go through `target: ImageCoordinationTarget`.

### 3.5 — Remove IUO for imageCoordinator
- **File:** `CollageViewModel.swift:31`
- **Change:** Restructure init so ImageCoordinator is created after other dependencies. `var imageCoordinator: ImageCoordinator` (no `!`).

**Gate:** Build + tests pass + manual verification of clearAll/undo behavior

---

## Phase 4: VM-Level Accessors & Mechanical View Pass (C3, C6) (2 days)

One file at a time. Each sub-phase: add missing VM accessors if needed → replace `viewModel.manager.xxx` → build → test → verify.

### Current VM accessor inventory

Already exists on VM: `images`, `panels`, `layoutStyle`, `gutter`, `customImageOrder`, `cropMap`, `selectedPanelId`, `isProcessing`, `isExporting`, `isDraggingTitle`, `errorMessage`, `exportSuccessMessage`, `dismissExportSuccess()`, `titleAttrString`, `titleStyle`, `title`, `backgroundColor`, `backgroundStyle`, `gradientStartColor`, `gradientEndColor`, `gradientAngle`, `backgroundImage`, `backgroundImagePath`, `backgroundOpacity`, `doubleExposureMaskImage`, `doubleExposureMaskImagePath`, `doubleExposureMaskOpacity`, `diagonalSliceAngle`, `hexagonalSpacing`, `previewImage`, `previewBackgroundImage`, `overlayImage`, `panelRenderedImages`, `titleImage`, `panelAssignments`

### New VM accessors needed

| Accessor | Type | Manager Source | Status |
|----------|------|----------------|--------|
| `browseImages()` | method | `imageCoordinator.browseImages()` | ✅ |
| `getEffectiveImageIndex(for:)` | method | `imageCoordinator.getEffectiveImageIndex(for:)` | ✅ |
| `swapPanelImages(sourceId:targetId:)` | method | `imageCoordinator.swapPanelImages(...)` | ✅ (pre-existing) |
| `removeImage(at:)` | method | `imageCoordinator.removeImage(at:)` + undo + saliency | ✅ (pre-existing) |
| `moveImages(from:to:)` | method | `imageCoordinator.moveImages(from:to:)` + undo + saliency | ✅ (pre-existing) |
| `selectPanelForImage(at:)` | method | `imageCoordinator.selectPanelForImage(at:)` | ✅ |
| `clearAll()` | method | Phase 3.2 | ✅ (pre-existing) |
| `addImages(from:)` | method | `imageCoordinator.addImages(from:)` | |
| `scrollPanActivePanelId` | computed | `cropManager.scrollPanActivePanelId` | |

### Sub-phases

| Sub-phase | File | Replacements | Notes |
|-----------|------|-------------|-------|
| 4.1 | `CollageCommands.swift` | 1 | `imageCoordinator.browseImages()` | ✅ DONE |
| 4.2 | `StatusSidebar.swift` | 4 | `exportManager.isExporting`, `imageLibrary.images.count`, `layoutManager.panels.count` | ✅ DONE |
| 4.3 | `ImageLibrarySidebar.swift` | 7 | `imageLibrary.images`, `imageCoordinator.removeImage`, `selectPanelForImage`, `moveImages`, `browseImages` | ✅ DONE |
| 4.4 | `ExportPanel.swift` | 6 | `exportManager.isExporting`, `successMessage`, `dismissSuccess()`, `imageLibrary.images.isEmpty` | ✅ DONE |
| 4.5 | `ContentView.swift` | 8 | `imageLibrary.images`, `imageCoordinator.browseImages/clearAll/addImages`, `layoutManager.panels` | ✅ DONE |
| 4.6 | `LayoutConfigSidebar.swift` | 16 | `layoutManager.layoutStyle`, `gutter`, `diagonalSliceAngle`, `hexagonalSpacing`, `doubleExposureMaskOpacity`, `doubleExposureMaskImage` |
| 4.7 | `PanelCropEditor.swift` | 3 | `imageCoordinator.getEffectiveImageIndex`, `imageLibrary.images` | ✅ DONE |
| 4.8 | `CollageEditorView.swift` | 14 | `layoutManager.panels`, `imageLibrary.images`, `imageCoordinator.getEffectiveImageIndex/swapPanelImages/removeImage`, `cropManager.scrollPanActivePanelId` |

**4.9 — Fix C6: Persistence bundle**
- **File:** `UserDefaultsPersistence.swift:81-111`
- **Change:** All `viewModel.layoutManager.xxx` accesses in `save(_:)` use VM-level computed properties instead. After 4.1–4.8, all LayoutManager properties accessed by persistence are available through the VM.

**Gate per sub-phase:** `xcodebuild` build + `xcodebuild test`

---

## Phase 5: TDD — Test New Manager Methods (1.5 days)

Write tests for the new methods that will receive extracted view logic. Tests define the contract before extraction.

### 5.1 — CropManager new method tests
- **File:** `CollageMakerTests/CropManagerTests.swift` (extend)
- **Methods to test:**
  - `adjustCropDuringDrag(translation:image:crop:container:geometry:mode:)` → returns `CropInfo`
    - Clamping to image bounds
    - Proportional scaling during drag
    - Coordinate transform: drag space → image space
    - Path panel visible offset handling
  - `handleResize(edge:delta:image:crop:container:geometry:)` → returns `CropInfo`
    - Corner resize: proportional scaling
    - Edge resize: single-axis scaling
    - Minimum crop size enforcement

### 5.2 — TitleManager new method tests
- **File:** `CollageMakerTests/TitleManagerTests.swift` (new)
- **Methods to test:**
  - `hitTestTitle(location:frame:previewSize:)` → `TitleHitResult`
    - Hit resize handles (left/right edges)
    - Hit drag region (center)
    - Miss (outside frame)
  - `computeTitleDragOffset(startLocation:frame:previewSize:)` → `CGPoint`
    - Offset from title center to drag start
  - `computeTitleResize(screenLocation:edge:frame:minWidth:canvasSize:)` → `(newWidth, positionDelta)`
    - Width clamping to minWidth
    - Position delta for width change

### 5.3 — CoordinateConverter utility tests (if new utility is created)
- **File:** `CollageMakerTests/CoordinateConverterTests.swift` (extend if needed)
- **Tests:** Vision → CG coordinate flips, portrait rotation swaps

**Gate:** All new tests pass

---

## Phase 6: Extract Business Logic from Views (C5, R1, R2) (2 days)

Extract algorithms from views into managers. Views become thin gesture wrappers.

### 6.1 — Crop logic: PanelCropEditor → CropManager
- **Source:** `PanelCropEditor.swift:173-357` (~185 lines)
- **Destination:** `CropManager.swift`
- **New methods:**
  - `adjustCropDuringDrag(translation:image:crop:container:geometry:mode:)` → `CropInfo`
  - `handleResize(edge:delta:image:crop:container:geometry:)` → `CropInfo`
- **View becomes:** Thin `DragGesture` / `MagnificationGesture` callbacks that call manager methods and set results.

### 6.2 — Title logic: CollageEditorView → TitleManager
- **Source:** `CollageEditorView.swift:164-285` (~120 lines)
- **Destination:** `TitleManager.swift`
- **New methods:**
  - `hitTestTitle(location:frame:previewSize:)` → `TitleHitResult`
  - `computeTitleDragOffset(startLocation:frame:previewSize:)` → `CGPoint`
  - `computeTitleResize(screenLocation:edge:frame:minWidth:canvasSize:)` → `(newWidth, positionDelta)`
- **View becomes:** Thin gesture callbacks that call manager methods.

### 6.3 — NSOpenPanel flows: ContentView + ExportPanel → ImagePickerService
- **Source:** `ContentView.swift:110-125` (`chooseMaskImage`), `ExportPanel.swift:269-284` (`chooseBackgroundImage`)
- **New file:** `Services/ImagePickerService.swift`
- **Protocol:** `ImagePicker` with `func pickImage(allowedTypes:) async -> (image: NSImage?, path: String?)`
- **Default impl:** `DefaultImagePicker` using `NSOpenPanel`
- **VM methods:** `chooseMaskImage()`, `chooseBackgroundImage()` call through service

### 6.4 — Cache panelFrames in VM (R4)
- **Source:** `CollageEditorView.swift:36`
- **Change:** Compute `panelFrames: [UUID: CGRect]` in VM as a cached property that invalidates when `panels` or canvas geometry changes. Remove `reduce` from `body`.

**Gate:** Build + tests pass + visual verification of crop/title interactions

---

## Phase 7: Test Coverage for New Managers (C10) (1.5 days)

### 7.1 — ImageCoordinatorTests
- **New file:** `CollageMakerTests/ImageCoordinatorTests.swift`
- **Coverage:**
  - `addImages` → triggers saliency analysis
  - `removeImage` → returns removed image and index
  - `moveImages` → updates customImageOrder
  - `clearDomain` → clears images and saliency results
  - `assignImage` → updates panel assignments
  - `getEffectiveImageIndex` → fallback to panel index
  - `swapPanelImages` → swaps assignments and crops

### 7.2 — LayoutManagerTests
- **New file:** `CollageMakerTests/LayoutManagerTests.swift`
- **Coverage:**
  - `regenerateLayout(preserveCrops: true)` → preserves crop rectangles
  - `regenerateLayout(preserveCrops: false)` → resets crops
  - Layout style transitions
  - Panel assignment persistence across regenerations

### 7.3 — TitleManagerTests (extend from Phase 5)
- **File:** `CollageMakerTests/TitleManagerTests.swift`
- **Additional coverage:**
  - Bounds caching behavior (cache hit/miss)
  - `reset()` → clears state and cache
  - `canvasFrame` computation
  - Protocol-based `updateImage` / `finishDrag`

### 7.4 — BackgroundManagerTests
- **New file:** `CollageMakerTests/BackgroundManagerTests.swift`
- **Coverage:**
  - `buildConfig()` → correct BackgroundConfig
  - `setBackgroundImage` → stores image and path
  - `reset()` → restores defaults
  - Protocol-based `updateBackground`

**Gate:** All tests pass

---

## Phase 8: Polish (1 day)

| # | Item | File | Description |
|---|------|------|-------------|
| 8.1 | Magic numbers | `LayoutGenerator.swift` | Extract ratios (0.25, 0.33, 0.4) and thresholds (0.3, 0.6) to `MosaicConfig` struct |
| 8.2 | SeededPRNG | `LayoutGenerator.swift:385-399` | Move to `Math+Utils.swift` |
| 8.3 | Accessibility | `CollageEditorView.swift:83-102` | Add `.accessibilityLabel()` and `.accessibilityTraits()` to title resize handles |
| 8.4 | Decompose editor | `CollageEditorView.swift` (444 lines) | Extract into `CanvasBackgroundView`, `PanelsOverlayView`, `TitleInteractionOverlay`, `DropPreviewView` |
| 8.5 | Setter patterns | Multiple managers | Standardize: all managers return old values for undo, or VM captures consistently |
| 8.6 | isInitializing | `CollageViewModel.swift` | Handle at init level, reduce ~20 scattered guards |
| 8.7 | Duplicate saliency calls | `ImageCoordinator.swift` | Extract to `scheduleSaliencyAnalysis()` helper |
| 8.8 | bytesPerRow | `ContextFactory.swift:7` | Use `nil` or derive from color space |

**Gate:** Build + tests pass

---

## Dependency Graph

```
Phase 1 (Quick Wins)
    ↓
Phase 2 (Break C1) ─────┐
    ↓                    ↓
Phase 3 (Decompose C2) ─┤
    ↓                    ↓
Phase 4 (VM Accessors) ──┤
    ↓                    ↓
Phase 5 (TDD) ───────────┼──→ Phase 6 (Extract Logic)
                         ↓
                       Phase 7 (Manager Tests)

Phase 8 (Polish) — any time after Phase 1
```

Phase 5 feeds Phase 6 (tests define the contract). Phase 7 tests the managers after all refactoring is complete.

---

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| Phase 4 mechanical pass introduces regressions | One file at a time, build + test gate per file |
| Phase 2 protocol changes break test mocks | Update `CollageViewModelTests` mocks to conform to new protocols |
| Phase 3 clearAll refactoring changes undo behavior | Verify undo behavior manually after phase |
| Phase 5 TDD tests are incomplete | Existing UI serves as behavioral reference; extract-as-is if tests miss edge cases |
| Phase 6 crop logic extraction changes behavior | Tests from Phase 5 serve as regression guard; visual verification |
| Phase 1.4 BackgroundRenderer size fix breaks preview | Verify with visual inspection after build |

---

## Estimated Effort

| Phase | Days | Key Deliverables |
|-------|------|-----------------|
| 1: Quick Wins | 0.5 | 7 small fixes, no dependencies |
| 2: Break C1 | 1.5 | 2 protocols, 3 manager refactors |
| 3: Decompose C2 | 2.0 | ImageCoordinator → domain-only, VM orchestrates |
| 4: VM Accessors | 2.0 | 8 sub-phases, 69 view replacements |
| 5: TDD | 1.5 | Tests for new CropManager/TitleManager methods |
| 6: Extract Logic | 2.0 | ~305 lines of logic moved from views to managers |
| 7: Manager Tests | 1.5 | 4 new/extended test suites |
| 8: Polish | 1.0 | 8 cleanup items |
| **Total** | **12 days** | |
