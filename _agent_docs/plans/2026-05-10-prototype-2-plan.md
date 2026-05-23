# CollageMaker Protoype 2 — Implementation Plan

**Date:** 2026-05-10
**Source:** Protoype 1 timeline (`_agent_docs/project-timeline/project-timeline.md`), SOLID review (`_agent_docs/reviews/collagemaker-solid-review.md`), SOLID fixes plan (`_agent_docs/plans/2026-05-10-collagemaker-solid-review-fixes.md`)
**Scope:** CollageMaker macOS SwiftUI application in `CollageMaker/CollageMaker/`

---

## Overview

Protoype 2 rebuilds CollageMaker from a fresh Xcode project, incorporating all lessons learned from Protoype 1's 9 development sessions and the SOLID code review. Every architectural decision is informed by a real bug or pain point from Protoype 1.

**Core changes from Protoype 1:**
- `CropManager` extracted from the start — no god-class ViewModel
- `[UUID: CropInfo]` dictionary for crop storage — no `CGRect ==` bugs
- Per-panel gesture overlays — no wrong-panel targeting
- Protocol-based DI — testable with mocks from day 1
- `@EnvironmentObject` only — no `@ObservedObject` crashes
- Multiple layout presets (uniform, hero, mosaic)
- Auto-analyze saliency on image load
- Drag-and-drop + folder browse only (no PhotosPicker complexity)
- Tests written in parallel with implementation

---

## Protoype 1 Lessons Applied

| Protoype 1 Problem | Session | Protoype 2 Solution |
|---|---|---|
| `@ObservedObject` stored property → `MainActor.assumeIsolated` SIGABRT | Session 5 | `@EnvironmentObject` only, from day 1 |
| `@State` with `Timer?` lost on re-render | Session 6 | Reference types in `@StateObject` class |
| `.onChange(of:)` loses tracker after view recreation | Session 8 | `.onReceive($publisher.dropFirst())` |
| `CGRect ==` crop lookup fails with CGFloat precision | Session 9 | `[UUID: CropInfo]` dict, `panelId` key |
| 507-line god-class ViewModel (7 responsibilities) | SOLID review | Extract `CropManager` from the start |
| No protocol abstractions for services | SOLID review | `SaliencyAnalysis`/`CollageAssembly` protocols + DI |
| Single gesture, wrong panel targeting | Session 9 | Per-panel ZStack overlays with hit testing |
| Hardcoded 1920x1080 in 4+ locations | SOLID review | `CanvasConfig` constant |
| Missing EXIF orientation in `VNImageRequestHandler` | SOLID review | Pass orientation from day 1 |
| Export blocks UI on MainActor | SOLID review | `Task.detached` background executor |
| Hardcoded test paths to `/Users/austin/Pictures/...` | SOLID review | Synthetic `NSBitmapImageRep` images only |
| Debug print in production | SOLID review | None from the start |
| `panelCrops` computed property O(n×m) | SOLID review | `cropMap` is already O(1) |
| `ThumbnailView.thumbnail` creates new NSImage every access | SOLID review | `NSCache<NSUUID, NSImage>` |
| Auto-analyze on load with no images | SOLID review | Auto-analyze only when images exist |

---

## Architecture

```
Views (@EnvironmentObject)
  ↓
CollageViewModel (@MainActor, thin orchestrator, ~150 lines)
  ├─ CropManager (@MainActor, gesture state + crop logic)
  ↓
Services (actor / struct / class, protocol-based, DI)
  ├─ SaliencyAnalyzer (actor) : SaliencyAnalysis
  ├─ LayoutGenerator (struct) : pure computation
  └─ CollageAssembler (class) : CollageAssembly
  ↓
Apple Frameworks (Vision, CoreGraphics, AppKit)
```

**Key design decisions:**
- `CollageViewModel` is a thin orchestrator (~150 lines) — crop state machine lives in `CropManager`
- Services are injected via protocols with default concrete implementations
- `CropManager` owns gesture state, debounce timer, and `[UUID: CropInfo]` dictionary
- All views use `@EnvironmentObject` — no `@ObservedObject` stored properties
- Synthetic test images via `NSBitmapImageRep` — no hardcoded file paths

---

## File Structure

```
CollageMaker/CollageMaker/
  CollageMakerApp.swift            # @main, defaultSize, .environmentObject
  ContentView.swift                # NavigationSplitView: sidebar + editor + export
  Assets.xcassets/

  Models/
    CanvasConfig.swift             # Shared constants (canvas size, preview size)
    ImageItem.swift                # Loaded image wrapper (id, nsImage, filename, size)
    ImagePanel.swift               # ImagePanel (layout panel) + CropInfo (with panelId: UUID)
    SaliencyResult.swift           # Center of interest + radius + confidence + crop helper
    LayoutStyle.swift              # enum: .uniform, .hero, .mosaic

  Services/
    SaliencyAnalyzer.swift         # actor, Vision saliency + face detection, SaliencyAnalysis protocol
    LayoutGenerator.swift          # pure struct, algorithmic mosaic, supports LayoutStyle
    CollageAssembler.swift         # class, CoreGraphics compositing, CollageAssembly protocol

  ViewModel/
    CollageViewModel.swift         # @MainActor ObservableObject, thin orchestrator, DI
    CropManager.swift              # @MainActor class, gesture state machine, crop logic

  Views/
    ImagePickerView.swift          # Drag-and-drop + NSOpenPanel folder browse
    CollageEditorView.swift        # Preview + per-panel gesture overlays + selected border
    PanelCropEditor.swift          # Panel info + Reset Crop button + gesture hints
    ExportPanel.swift              # Title, quality, background color, export button

CollageMaker/CollageMakerTests/
  TestHelpers.swift                # Shared createTestCGImage, createTestImageItem
  LayoutGeneratorTests.swift       # All layouts, all styles, hero, bounds, uniqueness
  SaliencyResultTests.swift        # Crop origin calculation, portrait handling
  CollageAssemblerTests.swift      # Assembly, preview, title, multiple panels
  SaliencyAnalyzerTests.swift      # Error paths, valid image analysis, batch count
  CropManagerTests.swift           # UUID lookup, pan/pinch, clamping, reset
  CollageViewModelTests.swift      # State transitions, mock services, layout/style changes
```

---

## Layout Presets

| Style | Description | Visual |
|---|---|---|
| **Uniform** | Equal-size grid, no hero. Clean, balanced look. | Grid of equal rectangles |
| **Hero** | One panel spans 2 cells, others fill remaining grid. Dramatic emphasis. | Large panel + smaller surrounding panels |
| **Mosaic** | Varied panel sizes (1/4, 1/3, 1/6, etc.). Dynamic, magazine-style. | Mixed large and small panels |

User selects preset in sidebar. Changing preset regenerates layout and crops. Hero index preserved when switching from `.hero` to another style.

### `LayoutStyle` Enum

```swift
enum LayoutStyle: String, CaseIterable, Identifiable {
    case uniform, hero, mosaic

    var id: String { self.rawValue }
    var title: String { ... }          // "Uniform", "Hero", "Mosaic"
    var icon: String { ... }           // SF Symbol name
}
```

---

## Gesture Design

Per-panel ZStack overlay approach — avoids the single-gesture wrong-panel targeting bug from Protoype 1:

```
ZStack {
  Image(nsImage: preview)        // Composite preview, aspect-ratio fit
    .scaledToFit()
    .id("preview")

  // Per-panel gesture overlays
  ForEach(panels) { panel in
    Rectangle().fill(.clear)
      .frame(width: previewW, height: previewH)
      .position(previewX, previewY)
      .gesture(
        SimultaneousGesture(
          DragGesture(minimumDistance: 5),
          MagnificationGesture()
        )
      )
  }

  // Selected panel border
  Rectangle()
    .stroke(Color.white, lineWidth: 2)
    .frame(...)
    .position(...)
}
```

**Coordinate conversion:** `canvasToPreviewFrame(panel.frame)` handles aspect-ratio fit scaling with letterbox offset calculation. Must account for the difference between canvas aspect ratio (16:9) and the SwiftUI view's available size.

**Panel selection:** `onTapGesture` on each overlay rectangle selects the panel. Tap on empty canvas area deselects.

---

## CropManager Design

```swift
@MainActor
final class CropManager {
    var cropMap: [UUID: CropInfo] = [:]

    // Gesture state
    private var gestureBaseOrigin: CGPoint?
    private var gestureBaseZoom: CGFloat?
    private var panDelta: CGSize = .zero
    private var zoomDelta: CGFloat = 1.0

    // Methods
    func computeInitialCrops(panels: [ImagePanel], images: [ImageItem])
    func computeCropsFromSaliency(panels: [ImagePanel], images: [ImageItem], results: [Int: SaliencyResult])
    func panCrop(panelId: UUID, by: CGSize, panels: [ImagePanel], images: [ImageItem])
    func applyPanCrop(panelId: UUID?)
    func pinchZoom(panelId: UUID, magnification: CGFloat, panels: [ImagePanel], images: [ImageItem])
    func applyPinchZoom(panelId: UUID?)
    func resetCrop(panelId: UUID, panels: [ImagePanel], images: [ImageItem])
    func resetAllCrops(panels: [ImagePanel], images: [ImageItem])

    var cropsArray: [CropInfo] { Array(cropMap.values).sorted { $0.destinationRect.origin.y < $1.destinationRect.origin.y } }
}
```

**Key decisions:**
- `CropManager` is NOT `ObservableObject` — the ViewModel mirrors `cropMap` as `@Published`
- Methods take `panels` and `images` as parameters — no circular dependency
- `objectWillChange` callback pattern: ViewModel calls `objectWillChange.send()` after delegate methods return

---

## CollageViewModel Design

```swift
@MainActor
final class CollageViewModel: ObservableObject {
    // Services (DI)
    private let saliencyAnalyzer: SaliencyAnalysis
    private let assembler: CollageAssembly
    private let cropManager = CropManager()

    // Published state
    @Published var images: [ImageItem] = []
    @Published var panels: [ImagePanel] = []
    @Published var cropMap: [UUID: CropInfo] = [:]
    @Published var selectedPanelId: UUID?
    @Published var layoutStyle: LayoutStyle = .hero
    @Published var heroIndex: Int?
    @Published var title: String = ""
    @Published var gutter: CGFloat = 4
    @Published var backgroundColor: NSColor = .black
    @Published var exportQuality: Double = 0.92
    @Published var previewImage: NSImage?
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?

    // Image loading
    func addImages(from urls: [URL])
    func removeImage(at index: Int)
    func clearAll()

    // Layout
    func regenerateLayout()
    func setLayoutStyle(_ style: LayoutStyle)
    func setHeroIndex(_ index: Int?)
    func updateGutter(_ value: CGFloat)

    // Saliency
    func analyzeSaliency() async

    // Crop (delegated to CropManager)
    func panCrop(panelId: UUID, by: CGSize)
    func applyPanCrop()
    func pinchZoom(panelId: UUID, magnification: CGFloat)
    func applyPinchZoom()
    func resetCrop(panelId: UUID)

    // Preview & export
    func updatePreview()
    func exportCollage() async -> URL?

    init(saliencyAnalyzer: SaliencyAnalysis = SaliencyAnalyzer(),
         assembler: CollageAssembly = CollageAssembler())
}
```

**Target:** ~150 lines (vs Protoype 1's 507 lines)

---

## Implementation Phases

Each phase compiles and passes tests independently. Pause after each phase for manual verification.

---

### Phase 1: Models + Constants

**Files:** 5 new files
- `Models/CanvasConfig.swift` — `defaultCanvasSize`, `defaultPreviewSize` constants
- `Models/LayoutStyle.swift` — `uniform`, `hero`, `mosaic` enum with titles and icons
- `Models/ImageItem.swift` — `id: UUID`, `nsImage: NSImage`, `filename: String`, `size: CGSize`
- `Models/ImagePanel.swift` — `ImagePanel` struct + `CropInfo` with `panelId: UUID`
- `Models/SaliencyResult.swift` — `center`, `radius`, `confidence`, `cropOrigin` computed property

**Success criteria:**
- [ ] Project compiles with zero errors
- [ ] All models are value types (structs)
- [ ] `CropInfo.panelId` exists (not `destinationRect` for lookups)
- [ ] `CanvasConfig.defaultCanvasSize` is `CGSize(width: 1920, height: 1080)`

---

### Phase 2: Services + Protocols

**Files:** 3 new files
- `Services/SaliencyAnalyzer.swift` — `actor`, `SaliencyAnalysis` protocol, EXIF orientation, `VNGenerateAttentionBasedSaliencyImageRequest` + `VNDetectFaceRectanglesRequest`
- `Services/LayoutGenerator.swift` — `struct`, `generate(numImages:heroIndex:canvasSize:gutter:style:)`, supports `.uniform`, `.hero`, `.mosaic`
- `Services/CollageAssembler.swift` — `class`, `CollageAssembly` protocol, `assemble` + `assembleWithCGImages` + `assemblePreview` + `assemblePreviewWithCGImages`

**Success criteria:**
- [ ] `SaliencyAnalysis` and `CollageAssembly` protocols exist
- [ ] `SaliencyAnalyzer` passes `orientation` to `VNImageRequestHandler`
- [ ] `LayoutGenerator` handles 1-10+ images for all 3 styles
- [ ] `CollageAssembler` uses `interpolationQuality = .high`, `saveGState`/`restoreGState`
- [ ] `NSAttributedString.draw(at:)` for title (not deprecated CGContext text API)
- [ ] Project compiles with zero errors

---

### Phase 3: CropManager + ViewModel

**Files:** 2 new files
- `ViewModel/CropManager.swift` — gesture state machine, `[UUID: CropInfo]` dict, pan/pinch with clamping
- `ViewModel/CollageViewModel.swift` — thin orchestrator, DI, image loading, layout, saliency, preview, background export

**Success criteria:**
- [ ] `CollageViewModel` under 200 lines
- [ ] `CropManager` handles pan (with bounds clamping) and pinch (0.5-3.0 range)
- [ ] Services injected via `init` with default implementations
- [ ] `exportCollage` runs assembly on `Task.detached` background executor
- [ ] `analyzeSaliency` auto-triggers when images are added (only if images exist)
- [ ] `cropMap` is `[UUID: CropInfo]`, keyed by `panel.id`
- [ ] Project compiles with zero errors

---

### Phase 4: Views

**Files:** 5 files (2 new, 3 modified)
- `Views/ImagePickerView.swift` — drag-and-drop `.onDrop` + `NSOpenPanel` folder browse
- `Views/CollageEditorView.swift` — preview image + per-panel gesture overlays + `canvasToPreviewFrame()` conversion + selected panel border
- `Views/PanelCropEditor.swift` — panel info, "Reset Crop" button, gesture hints
- `Views/ExportPanel.swift` — title field, quality slider, background color picker, export button with progress
- `ContentView.swift` — `NavigationSplitView` with sidebar (image list, layout style picker, gutter slider), editor, export panel

**Success criteria:**
- [ ] All views use `@EnvironmentObject` (no `@ObservedObject`)
- [ ] Per-panel gesture overlays work with coordinate conversion
- [ ] Selected panel highlighted with white border
- [ ] Layout style picker in sidebar
- [ ] `.onReceive(viewModel.$property.dropFirst())` pattern used (not `.onChange`)
- [ ] Project compiles with zero errors

---

### Phase 5: App Wiring + Build

**Files:** 1 modified
- `CollageMakerApp.swift` — `.environmentObject(viewModel)`, `defaultSize`

**Success criteria:**
- [ ] App launches with `NavigationSplitView` layout
- [ ] Zero errors, zero warnings (excluding AppIntents metadata)
- [ ] Clean build via `xcodebuild`

---

### Phase 6: Tests

**Files:** 7 test files
- `TestHelpers.swift` — `createTestCGImage(color:size:)` via `NSBitmapImageRep`, `createTestImageItem(color:size:)`
- `LayoutGeneratorTests.swift` — All image counts (1-12), all 3 styles, hero index, canvas bounds, panel uniqueness
- `SaliencyResultTests.swift` — Crop origin calculation, portrait image handling
- `CollageAssemblerTests.swift` — Single/multiple panel assembly, title overlay, preview generation, `assembleWithCGImages`
- `SaliencyAnalyzerTests.swift` — Empty image throws, valid image returns result, batch count correct
- `CropManagerTests.swift` — UUID lookup, pan moves source rect, pan clamps to bounds, pinch changes zoom, pinch clamps min/max, reset works
- `CollageViewModelTests.swift` — Add images triggers layout, layout style change regenerates, mock services via DI, state transitions

**Success criteria:**
- [ ] All tests pass (target: 35+ tests)
- [ ] No hardcoded file paths
- [ ] All test structs annotated `@MainActor`
- [ ] `NSApplication.shared` initialized via `@Suite`
- [ ] Mock services used for ViewModel tests
- [ ] `xcodebuild test -only-testing:CollageMakerTests` passes

---

### Phase 7: Manual Testing

**Steps:**
1. Build and launch app
2. Drag 4-6 images onto the app
3. Verify layout generates with preview (saliency auto-analyzes)
4. Switch layout style (uniform, hero, mosaic), verify layout changes
5. Select hero image, verify layout updates
6. Click a panel to select (white border appears)
7. Drag on a panel to pan crop, verify preview updates on gesture end
8. Pinch on a panel to zoom crop, verify preview updates
9. Click "Reset Crop", verify crop resets
10. Adjust gutter slider, verify layout regenerates
11. Set title, adjust quality, click Export, verify save dialog and file output
12. Verify no crashes, no frozen UI during export

---

## What We're NOT Doing

- **Not** adding PhotosPicker — drag-and-drop + folder browse covers the user's workflow
- **Not** adding PNG/HEIC export — only JPEG
- **Not** adding per-panel rotation/flipping
- **Not** adding artistic overlap/shadow effects
- **Not** adding automatic color harmonization
- **Not** modifying `CollageMakerUITests` — boilerplate only
- **Not** introducing a `LayoutStrategy` protocol — the `switch` in `LayoutGenerator` is acceptable for finite strategies

---

## Performance Considerations

- **Crop lookup:** O(1) dictionary by UUID (vs Protoype 1's O(n) array search)
- **Saliency analysis:** Concurrent with `withThrowingTaskGroup`, 50-200ms per image
- **Export:** `Task.detached` background executor prevents UI blocking
- **Thumbnails:** `NSCache<NSUUID, NSImage>` prevents redundant generation
- **Preview:** `objectWillChange.send()` before `previewImage` assignment

---

## Concurrency Rules

- `@MainActor` on `CollageViewModel` and `CropManager`
- `actor` on `SaliencyAnalyzer` for thread-safe Vision calls
- `Task { [weak self] }` for async ViewModel updates
- `Task.detached` for heavy computation (export assembly)
- `defer { isProcessing = false }` always resets processing state
- Cancel previous `Task` before starting new one

---

## State Management Rules

- `@EnvironmentObject` only — never `@ObservedObject` stored properties
- `@StateObject` for view-local class state (timers, debouncers)
- Never store reference types in `@State`
- `.onReceive(viewModel.$property.dropFirst())` for reacting to `@Published` changes
- `objectWillChange.send()` before batch mutations
- `.id()` on conditionally shown views to stabilize identity

---

## Testing Rules

- `NSBitmapImageRep` with RGBA for test CGImages (not `[.byteOrder32Big]`)
- `@MainActor` on test structs when testing `@MainActor` types
- `NSGraphicsContext.saveGraphicsState()` / `restoreGraphicsState()` for test drawing
- Synthetic images only — no hardcoded file paths
- Protocol-based mocking for service isolation
- `-only-testing:CollageMakerTests` flag for Swift Testing framework

---

## References

- Protoype 1 plan: `_agent_docs/plans/initial-plan.md`
- Protoype 1 timeline: `_agent_docs/project-timeline/project-timeline.md`
- SOLID review: `_agent_docs/reviews/collagemaker-solid-review.md`
- SOLID fixes plan: `_agent_docs/plans/2026-05-10-collagemaker-solid-review-fixes.md`
- Corrupted Protoype 1 code: `/Users/austin/workspace/agent-ollama-projects/claudeharness/workspace/SwiftCollageProject/CollageMaker/CollageMaker`
- CLAUDE.md (project guidelines): root of workspace
