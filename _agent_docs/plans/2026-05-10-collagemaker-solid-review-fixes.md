# CollageMaker SOLID Review Fixes — Implementation Plan

**Date:** 2026-05-10
**Source:** `agent_docs/reviews/collagemaker-solid-review.md`
**Scope:** CollageMaker macOS SwiftUI application in `workspace/SwiftCollageProject/CollageMaker/`

---

## Overview

Address all review findings from the SOLID code review of CollageMaker. The plan refactors the god-class `CollageViewModel` (507 lines) by extracting crop management, introduces protocol-based dependencies for testability, fixes critical bugs (EXIF orientation, CGRect keying), and cleans up code quality issues and tests.

## Current State Analysis

- `CollageViewModel` (507 lines) manages 7 responsibilities: image loading, layout, saliency, gesture crops, slider crops, preview, export
- Services (`SaliencyAnalyzer`, `CollageAssembler`) are hardcoded, not protocol-based
- Crop lookup uses `CGRect` equality (`destinationRect == panel.frame`) — fragile with CGFloat precision
- `SaliencyAnalyzer` ignores EXIF orientation in `VNImageRequestHandler`
- Canvas size `1920x1080` is hardcoded in 4+ locations
- `ContentView` auto-runs saliency analysis on load (wastes resources when no images)
- Export runs synchronously on MainActor, blocking UI
- Tests have hardcoded file paths to `/Users/austin/Pictures/...`
- Duplicate `createTestCGImage` helper in two test files
- `NavigationPane` is dead code; `progressView` extension is globally scoped

## Desired End State

- `CollageViewModel` reduced to ~200 lines, delegating crop operations to `CropManager`
- `SaliencyAnalysis` and `CollageAssembly` protocols with DI in ViewModel
- Crops keyed by `panel.id` (UUID) via `[UUID: CropInfo]` dictionary
- EXIF orientation passed to `VNImageRequestHandler`
- Canvas size from a `CanvasConfig` constant
- No auto-analyze on load; user triggers via button
- Export runs on background executor
- All tests use synthetic images; shared test helpers; new tests for `SaliencyAnalyzer`, `CropManager`, and `CollageViewModel`
- Debug print removed, dead code removed, global extension scoped

### Key Discoveries

- `CollageViewModel.swift:44-45` — Hardcoded `SaliencyAnalyzer()` and `CollageAssembler()`
- `CollageViewModel.swift:63,100,111,417` — `CGRect` equality for crop lookup (`destinationRect == panel.frame`)
- `CollageViewModel.swift:229-237` — `panelCrops` computed property is O(n×m), keyed by `imageIndex` (wrong — should be by `panel.id`)
- `SaliencyAnalyzer.swift:32` — `VNImageRequestHandler(cgImage:cgImage, options: [:])` missing orientation
- `ContentView.swift:27-29` — `.task { await viewModel.analyzeSaliency() }` auto-analyzes on load
- `ContentView.swift:60-62` — Redundant `regenerateLayout()` call (already called by `updateGutter()`)
- `ContentView.swift:113-123` — `NavigationPane` is a no-op wrapper
- `CollageEditorView.swift:58` — Hardcoded `1920` and `1080`
- `ExportPanel.swift:145-149` — Global `View` extension for single-use modifier
- `ImagePickerView.swift:174-184` — `ThumbnailView.thumbnail` creates new NSImage on every access
- `CollageViewModel.swift:64` — `print("DEBUG panCrop: guard failed panelId=\(panelId)")`
- `CollageViewModel.swift:455-491` — `exportCollage()` runs `assembler.assemble()` synchronously on main actor
- `CollageMakerTests.swift:339-341` — Hardcoded file paths
- `CollageMakerTests.swift:161` — `await CollageAssembler()` — unnecessary await on non-actor

## What We're NOT Doing

- **Not** introducing a `LayoutStrategy` protocol — the `switch` in `LayoutGenerator` is acceptable for finite strategies
- **Not** building crop slider UI — the slider state exists but no UI renders it; out of scope
- **Not** adding PNG/HEIC export — only JPEG export is in scope
- **Not** adding per-panel crop persistence across layout changes — current behavior (wipe on layout change) is preserved
- **Not** modifying `CollageMakerUITests` — they are boilerplate

## Implementation Approach

Five phases progressing from non-breaking foundation changes to structural refactoring to test improvements. Each phase compiles and passes tests independently.

---

## Phase 1: Foundation — Protocols, Constants, Quick Fixes

### Overview

Establish protocol abstractions, centralize hardcoded constants, and remove low-risk issues. No behavioral changes — purely structural and cleanup.

### Changes Required:

#### 1. `CanvasConfig` Constant
**File**: `CollageMaker/Models/CanvasConfig.swift` (new)
**Changes**: Extract hardcoded canvas dimensions into a shared constant.

```swift
import CoreGraphics

struct CanvasConfig {
    static let defaultCanvasSize: CGSize = CGSize(width: 1920, height: 1080)
    static let defaultPreviewSize: CGSize = CGSize(width: 960, height: 540)
}
```

Update all references:
- `LayoutGenerator.swift:8` — default `canvasSize` parameter
- `CollageAssembler.swift:36` — default `canvasSize` parameter
- `CollageAssembler.swift:139-140` — default `targetSize` and `canvasSize` parameters
- `CollageEditorView.swift:58` — `previewToCanvas` scale computation
- `CollageEditorView.swift:81` — `handlePreviewTap` scale computation
- `CollageViewModel.swift:305` — `regenerateLayout` canvas size

#### 2. `SaliencyAnalysis` Protocol
**File**: `CollageMaker/Services/SaliencyAnalyzer.swift`
**Changes**: Add protocol conformance.

```swift
protocol SaliencyAnalysis {
    func analyze(_ image: NSImage) async throws -> SaliencyResult
    func analyzeAll(_ images: [NSImage]) async throws -> [SaliencyResult]
}

extension SaliencyAnalyzer: SaliencyAnalysis {}
```

#### 3. `CollageAssembly` Protocol
**File**: `CollageMaker/Services/CollageAssembler.swift`
**Changes**: Add protocol conformance.

```swift
protocol CollageAssembly {
    func assemble(panels:images:crops:title:backgroundColor:quality:) -> Data?
    func assemblePreview(panels:images:crops:title:backgroundColor:targetSize:) -> NSImage?
}

extension CollageAssembler: CollageAssembly {}
```

#### 4. Remove Auto-Analyze
**File**: `CollageMaker/ContentView.swift:27-29`
**Changes**: Remove `.task { await viewModel.analyzeSaliency() }` block. The "Analyze Images" button already triggers analysis.

#### 5. Remove Redundant `regenerateLayout()` Call
**File**: `CollageMaker/ContentView.swift:59-62`
**Changes**: Remove the `.onChange(of: viewModel.gutter)` block. `updateGutter()` already calls `regenerateLayout()`. Change the Slider binding to use `updateGutter`:

```swift
Slider(value: $viewModel.gutter, in: 0...20, step: 1)
    .onChange(of: viewModel.gutter) { oldValue, newValue in
        // Binding already sets gutter; updateGutter is called via a dedicated binding
    }
```

Actually, simpler: keep the Slider binding to `$viewModel.gutter` and remove the `.onChange`. The `updateGutter(_:)` method is called from the slider in the sidebar. Since the slider directly binds to `viewModel.gutter`, and `updateGutter` also sets `gutter` then calls `regenerateLayout`, the cleanest fix is to use a custom binding:

```swift
Slider(
    value: Binding(
        get: { viewModel.gutter },
        set: { viewModel.updateGutter(CGFloat($0)) }
    ),
    in: 0...20,
    step: 1
)
```

This eliminates the `.onChange` entirely.

#### 6. Remove Debug Print
**File**: `CollageMaker/ViewModel/CollageViewModel.swift:64`
**Changes**: Delete `print("DEBUG panCrop: guard failed panelId=\(panelId)")`.

#### 7. Remove `NavigationPane` Dead Code
**File**: `CollageMaker/ContentView.swift:111-123`
**Changes**: Delete `NavigationPane` struct. Replace `sidebar` var to return `List { ... }` directly (or wrap in `NavigationStack` if needed). Since `NavigationPane` is a no-op, replace:

```swift
private var sidebar: some View {
    List {
        Section("Images") { ... }
        Section("Layout") { ... }
    }
    .navigationTitle("CollageMaker")
}
```

#### 8. Scope `progressView` Extension
**File**: `CollageMaker/Views/ExportPanel.swift:145-149`
**Changes**: Change from `extension View` to `extension View where Self == Button<...>` or simply inline the modifier. Simplest: make it a `fileprivate` extension by keeping it in the same file but marking `ProgressViewModifier` as `private` (already is). The `extension View` at file scope is the issue. Change to:

```swift
// Remove the global extension; inline the modifier in ExportPanel
```

Actually, since `ProgressViewModifier` is already `private`, the extension itself is file-scoped in practice. The review flags it as a concern. The fix: change the extension to apply only within the file by using a `@ViewBuilder` helper in `ExportPanel` instead.

### Success Criteria:

#### Automated Verification:
- [ ] Project compiles without errors in Xcode
- [ ] All existing unit tests pass
- [ ] No references to literal `1920` or `1080` remain (verified by grep)
- [ ] No `print("DEBUG` statements remain (verified by grep)
- [ ] `SaliencyAnalysis` and `CollageAssembly` protocols exist and are adopted

#### Manual Verification:
- [ ] App launches without running saliency analysis on startup
- [ ] Gutter slider still regenerates layout on change
- [ ] Export button progress overlay still works
- [ ] Navigation sidebar renders correctly without `NavigationPane`

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 2: Critical Bug Fixes

### Overview

Fix the two critical bugs identified in the review: EXIF orientation in saliency analysis, and CGRect-based crop keying.

### Changes Required:

#### 1. EXIF Orientation in SaliencyAnalyzer
**File**: `CollageMaker/Services/SaliencyAnalyzer.swift:32`
**Changes**: Pass EXIF orientation to `VNImageRequestHandler`.

```swift
// Before:
let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

// After:
let orientation = cgImage.imageOrientation
let handler = VNImageRequestHandler(cgImage: cgImage, options: [.orientation: orientation])
```

Need to add a computed property on `CGImage` to get `CGImagePropertyOrientation`:
```swift
private extension CGImage {
    var imageOrientation: CGImagePropertyOrientation {
        .up // CGImage doesn't carry EXIF; orientation comes from NSImage
    }
}
```

Actually, `CGImage` strips EXIF orientation. The correct approach is to get orientation from the `NSImage` before extracting `CGImage`. Update the `analyze` method signature or options:

```swift
func analyze(_ nsImage: NSImage) async throws -> SaliencyResult {
    guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw SaliencyError.invalidImage
    }

    let orientation: CGImagePropertyOrientation = {
        // NSImage represents orientation via its size representation of the CGImage.
        // If the NSImage size differs from CGImage size in aspect, there may be rotation.
        // For correctness, use .up as CGImage already has pixels in display order.
        return .up
    }()

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [.orientation: orientation])
    // ...
}
```

Wait — the review says "Should pass `orientation: cgImage.imageOrientation` per CLAUDE.md guidelines." The issue is that `NSImage` may have represented the image with rotation, but `cgImage(forProposedRect:)` extracts the raw pixels. If the original image had EXIF rotation, `NSImage` may have already applied it visually, but the `CGImage` pixels may be unrotated.

The safest fix: check if `NSImage` has a size mismatch with `CGImage` that suggests rotation, and pass the appropriate orientation. However, `NSImage` does not expose EXIF orientation directly.

**Decision**: Since `NSImage(contentsOf:)` and `NSImage(data:)` do NOT automatically apply EXIF rotation (unlike UIImage), the `CGImage` extracted from `NSImage` has the raw pixels. We need to determine orientation from the image metadata. The practical approach:

```swift
func analyze(_ nsImage: NSImage) async throws -> SaliencyResult {
    guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw SaliencyError.invalidImage
    }

    let orientation = nsImage.exifOrientation

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [.orientation: orientation])
    // ...
}

private extension NSImage {
    var exifOrientation: CGImagePropertyOrientation {
        // Check if the NSImage size is rotated relative to the CGImage size
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return .up
        }
        let cgSize = CGSize(width: cgImage.width, height: cgImage.height)
        if cgSize.width == cgSize.height { return .up }
        if size.width == cgSize.width && size.height == cgSize.height { return .up }
        if abs(size.width - cgSize.height) < 1 && abs(size.height - cgSize.width) < 1 { return .left }
        return .up
    }
}
```

#### 2. UUID-Based Crop Storage
**File**: `CollageMaker/ViewModel/CollageViewModel.swift`
**Changes**: Replace `crops: [CropInfo]` array with `cropMap: [UUID: CropInfo]` dictionary keyed by `panel.id`.

Changes to `CollageViewModel`:
- `@Published var crops: [CropInfo]` → `@Published var cropMap: [UUID: CropInfo] = [:]`
- Add computed `var crops: [CropInfo]` for backward compatibility with services that expect an array
- Update all crop lookups from `crops.firstIndex(where: { $0.destinationRect == panel.frame })` to `cropMap[panel.id]`
- Update `computeInitialCrops()`, `computeCropsFromSaliency()`, `updateCrop()`, `panCrop()`, `pinchZoom()`, `applyPanCrop()`, `applyPinchZoom()`, `assignImage()`
- Update `panelCrops` computed property — it becomes redundant since `cropMap` IS the dictionary

Specific method changes:

```swift
// panCrop — before:
let index = crops.firstIndex(where: { $0.destinationRect == panel.frame })
crops[index].sourceRect.origin = ...

// panCrop — after:
guard var crop = cropMap[panelId] else { return }
crop.sourceRect.origin = ...
cropMap[panelId] = crop
```

```swift
// updateCrop — before:
if let index = crops.firstIndex(where: { $0.destinationRect == panel.frame }) {
    crops[index].sourceRect = sourceRect
    crops[index].zoom = zoom
    crops = Array(crops)
} else {
    crops.append(CropInfo(...))
}

// updateCrop — after:
var crop = cropMap[panelId] ?? CropInfo(sourceRect: .zero, destinationRect: panel.frame, imageIndex: panel.imageIndex)
crop.sourceRect = sourceRect
crop.zoom = zoom
cropMap[panelId] = crop
objectWillChange.send()
```

```swift
// computeInitialCrops — after:
cropMap.removeAll()
for panel in panels {
    // ... compute sourceRect ...
    cropMap[panel.id] = CropInfo(sourceRect: sourceRect, destinationRect: panel.frame, imageIndex: panel.imageIndex, zoom: 1.0)
}
```

**File**: `CollageMaker/Services/CollageAssembler.swift:72`
**Changes**: The assembler looks up crops by `imageIndex && destinationRect`. Update to accept `cropMap: [UUID: CropInfo]` or keep the array parameter but note the assembler receives the array from the computed property.

Since `assemble` and `assemblePreview` take `crops: [CropInfo]`, add a computed property for backward compatibility:

```swift
var cropsArray: [CropInfo] { Array(cropMap.values) }
```

Then update calls to pass `cropsArray` instead of `crops`. The assembler's lookup at line 72 (`crops.first { $0.imageIndex == panel.imageIndex && $0.destinationRect == panel.frame }`) will still work with the array, but is now more reliable since each entry corresponds to a unique panel.

Actually, better: update the assembler protocol to accept `[UUID: CropInfo]` and look up by `panel.id`. This is cleaner:

```swift
// In CollageAssembly protocol:
func assemble(panels:images:cropMap:title:backgroundColor:quality:) -> Data?

// In assembler:
if let crop = cropMap[panel.id], crop.sourceRect.width > 0 && crop.sourceRect.height > 0 {
    sourceRect = crop.sourceRect
}
```

This requires updating all callers and test code.

#### 3. `panelCrops` Fix
**File**: `CollageMaker/ViewModel/CollageViewModel.swift:229-237`
**Changes**: After UUID-based storage, `panelCrops` is just `cropMap`. Remove the computed property or alias it:

```swift
var panelCrops: [UUID: CropInfo] { cropMap }
```

### Success Criteria:

#### Automated Verification:
- [ ] Project compiles without errors
- [ ] All existing unit tests pass (updated for new signatures)
- [ ] `CropWorkflowIntegrationTests` pass with UUID-based lookup
- [ ] `CropGestureTests` pass with UUID-based lookup
- [ ] No `destinationRect ==` comparisons for crop lookup remain

#### Manual Verification:
- [ ] Pan crop works correctly on all panels
- [ ] Pinch zoom works correctly on all panels
- [ ] Saliency analysis produces correct results for images with EXIF rotation (test with a portrait phone photo)
- [ ] Export produces correct output with crops applied

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 3: Extract CropManager

### Overview

Extract crop management from `CollageViewModel` into a dedicated `CropManager` class. This is the largest structural change, reducing the ViewModel from ~507 lines to ~200 lines.

### Changes Required:

#### 1. New `CropManager` Class
**File**: `CollageMaker/ViewModel/CropManager.swift` (new)
**Changes**: Create a `@MainActor class CropManager: ObservableObject` that owns:

- Gesture state: `gestureBaseCropOrigin`, `gestureBaseZoom`, `gesturePanDelta`, `gestureZoomDelta`
- Slider state: `cropOffsetX`, `cropOffsetY`, `cropZoom`
- Timer: `cropDebounceTimer`
- Crop data: `cropMap: [UUID: CropInfo]`
- Methods: `panCrop`, `applyPanCrop`, `pinchZoom`, `applyPinchZoom`, `scheduleCropUpdate`, `applyCropSliderValues`, `resetCropSliders`, `computeInitialCrops`, `computeCropsFromSaliency`, `updateCrop`, `resetCrops`

The `CropManager` needs access to `images: [ImageItem]` and `panels: [ImagePanel]` to perform crop computations. Pass these as parameters to methods that need them, or provide a `CropContext` struct.

```swift
@MainActor
class CropManager: ObservableObject {
    @Published var cropMap: [UUID: CropInfo] = [:]

    // Slider state
    @Published var cropOffsetX: Double = 0
    @Published var cropOffsetY: Double = 0
    @Published var cropZoom: Double = 1.0

    private var cropDebounceTimer: Timer?

    // Gesture state
    private var gestureBaseCropOrigin: CGPoint?
    private var gestureBaseZoom: CGFloat?
    private var gesturePanDelta: CGSize = .zero
    private var gestureZoomDelta: CGFloat = 1.0

    // Gesture crop
    func panCrop(panelId: UUID, by translation: CGSize, panels: [ImagePanel], images: [ImageItem]) { ... }
    func applyPanCrop(panelId: UUID?, panels: [ImagePanel], objectWillChange: () -> Void) { ... }
    func pinchZoom(panelId: UUID, magnification: CGFloat, panels: [ImagePanel], images: [ImageItem]) { ... }
    func applyPinchZoom(panelId: UUID?, panels: [ImagePanel], objectWillChange: () -> Void) { ... }

    // Slider crop
    func scheduleCropUpdate(apply: @MainActor @escaping () -> Void) { ... }
    func applyCropSliderValues(panelId: UUID?, panels: [ImagePanel], images: [ImageItem], update: (UUID, CGRect, CGFloat) -> Void) { ... }
    func resetCropSliders() { ... }

    // Crop computation
    func computeInitialCrops(panels: [ImagePanel], images: [ImageItem]) { ... }
    func computeCropsFromSaliency(panels: [ImagePanel], images: [ImageItem], saliencyResults: [Int: SaliencyResult]) { ... }
    func updateCrop(for panelId: UUID, panel: ImagePanel, sourceRect: CGRect, zoom: CGFloat) { ... }
    func resetCrops() { ... }

    // Computed
    var cropsArray: [CropInfo] { Array(cropMap.values) }
}
```

**Design decision**: `CropManager` does NOT own `objectWillChange.send()` directly. Instead, methods that mutate state return a `Bool` indicating whether changes were made, and the ViewModel calls `objectWillChange.send()` and `updatePreview()`. Alternatively, use a callback closure.

**Chosen approach**: `CropManager` is `@Published`-free for `cropMap`. Instead, it uses a callback-based design:

```swift
@MainActor
class CropManager {
    var cropMap: [UUID: CropInfo] = [:]

    // Slider state (owned by ViewModel's @Published, but managed by CropManager)
    var cropOffsetX: Double = 0
    var cropOffsetY: Double = 0
    var cropZoom: Double = 1.0

    private var cropDebounceTimer: Timer?
    private var onCropChanged: (() -> Void)?

    // Gesture state
    private var gestureBaseCropOrigin: CGPoint?
    private var gestureBaseZoom: CGFloat?
    private var gesturePanDelta: CGSize = .zero
    private var gestureZoomDelta: CGFloat = 1.0

    func configure(onCropChanged: (() -> Void)?) {
        self.onCropChanged = onCropChanged
    }

    private func notifyChanged() {
        onCropChanged?()
    }

    // ... methods call notifyChanged() after mutations
}
```

Actually, the simplest approach that works with SwiftUI: `CropManager` is a `@MainActor class` that holds the crop data. The ViewModel holds a `@Published var cropManager = CropManager()`. Since the entire object reference is published, any mutation triggers view updates. But this fires too broadly.

**Final design**: `CropManager` is NOT `ObservableObject`. The ViewModel holds `private let cropManager = CropManager()`. The ViewModel's `@Published var cropMap: [UUID: CropInfo]` mirrors the manager's data. Manager methods mutate internally, and the ViewModel syncs:

```swift
// In CollageViewModel:
private let cropManager = CropManager()

@Published var cropMap: [UUID: CropInfo] = [:] {
    didSet { cropManager.cropMap = cropMap }
}

func panCrop(panelId: UUID, by translation: CGSize) {
    cropManager.panCrop(panelId: panelId, by: translation, panels: panels, images: images)
    cropMap = cropManager.cropMap
}

func applyPanCrop() {
    cropManager.applyPanCrop(panelId: selectedPanelId)
    cropMap = cropManager.cropMap
    updatePreview()
}
```

This keeps the ViewModel as the single source of `@Published` truth while delegating logic.

#### 2. Refactored `CollageViewModel`
**File**: `CollageMaker/ViewModel/CollageViewModel.swift`
**Changes**: Remove gesture crop methods, slider crop methods, crop computation methods, and gesture/slider state variables. Replace with `cropManager` delegation.

Removed from ViewModel:
- Lines 39-46: `cropOffsetX/Y/zoom`, `cropDebounceTimer`
- Lines 48-52: gesture state variables
- Lines 58-173: `panCrop`, `applyPanCrop`, `pinchZoom`, `applyPinchZoom`, `resetGestureState`
- Lines 175-227: `scheduleCropUpdate`, `applyCropSliderValues`, `resetCropSliders`
- Lines 229-237: `panelCrops` computed property
- Lines 348-431: `computeInitialCrops`, `computeCropsFromSaliency`, `updateCrop`

Retained in ViewModel:
- Published state properties (images, panels, cropMap, saliencyResults, etc.)
- Image loading methods (addImages, removeImage, clearAll)
- Layout methods (regenerateLayout, setHeroIndex, updateGutter)
- Saliency orchestration (analyzeSaliency)
- Preview (updatePreview)
- Export (exportCollage)
- Panel reassignment (assignImage)
- `cropManager` instance and thin delegation methods

The `selectedPanelId` setter (lines 21-37) currently resets slider state. Update to delegate to `cropManager`.

#### 3. Update Views
**File**: `CollageMaker/Views/CollageEditorView.swift`
**Changes**: No changes needed — views call ViewModel methods, signatures remain the same.

**File**: `CollageMaker/Views/PanelCropEditor.swift`
**Changes**: No changes needed — only uses Reset button, which calls `viewModel` methods.

### Success Criteria:

#### Automated Verification:
- [ ] Project compiles without errors
- [ ] All existing unit tests pass (updated for delegation)
- [ ] `CropGestureTests` pass — exercise CropManager through ViewModel
- [ ] `CropWorkflowIntegrationTests` pass
- [ ] `CollageViewModel.swift` is under 250 lines

#### Manual Verification:
- [ ] Pan crop on preview works for all panels
- [ ] Pinch zoom on preview works for all panels
- [ ] Reset crop button works
- [ ] Saliency analysis still updates crops correctly
- [ ] Layout regeneration still resets crops

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 4: Dependency Injection + Background Export

### Overview

Wire up protocol-based DI for services and move export to a background executor.

### Changes Required:

#### 1. DI in CollageViewModel
**File**: `CollageMaker/ViewModel/CollageViewModel.swift`
**Changes**: Replace hardcoded service instantiation with injected dependencies.

```swift
// Before:
private let saliencyAnalyzer = SaliencyAnalyzer()
private let assembler = CollageAssembler()

// After:
private let saliencyAnalyzer: SaliencyAnalysis
private let assembler: CollageAssembly

init(saliencyAnalyzer: SaliencyAnalysis = SaliencyAnalyzer(),
     assembler: CollageAssembly = CollageAssembler()) {
    self.saliencyAnalyzer = saliencyAnalyzer
    self.assembler = assembler
}
```

#### 2. Background Export
**File**: `CollageMaker/ViewModel/CollageViewModel.swift` — `exportCollage()`
**Changes**: Dispatch assembly to a background executor.

```swift
func exportCollage() async -> URL? {
    guard !images.isEmpty else { return nil }

    let savePanel = NSSavePanel()
    savePanel.allowedContentTypes = [.jpeg]
    savePanel.nameFieldStringValue = "Collage.jpg"
    savePanel.prompt = "Export"
    savePanel.message = "Save collage as JPEG"

    let response = NSApplication.shared.runModal(for: savePanel)
    guard response == .OK, let url = savePanel.url else { return nil }

    isProcessing = true
    defer { isProcessing = false }

    let nsImages = images.map(\.nsImage)

    // Dispatch assembly to background
    let data: Data?
    do {
        data = try await Task.detached(priority: .userInitiated) { [panels = self.panels, crops = self.cropsArray, title = self.title, bg = self.backgroundColor, quality = self.exportQuality] in
            // assembler is a class, safe to access from background if it's thread-safe
            // Since CollageAssembler uses CoreGraphics (thread-safe), this is safe
            return self.assembler.assemble(
                panels: panels,
                images: nsImages,
                crops: crops,
                title: title,
                backgroundColor: bg,
                quality: quality
            )
        }.value
    } catch {
        errorMessage = "Export failed: \(error.localizedDescription)"
        return nil
    }

    guard let data else {
        errorMessage = "Failed to assemble collage"
        return nil
    }

    do {
        try data.write(to: url, options: .atomic)
        return url
    } catch {
        errorMessage = "Failed to save file: \(error.localizedDescription)"
        return nil
    }
}
```

**Note**: `NSImage` instances should not be accessed from background threads. The `nsImages` array is captured in the detached task. `CollageAssembler.assemble()` calls `nsImage.cgImage(forProposedRect:)` which is NOT thread-safe for `NSImage`. Need to convert to `CGImage` on the main actor first:

```swift
// In exportCollage:
let cgImages = await MainActor.run {
    images.map { $0.nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) }
}

let data: Data? = try await Task.detached(priority: .userInitiated) {
    assembler.assembleWithCGImages(
        panels: panels,
        cgImages: cgImages,
        crops: crops,
        title: title,
        backgroundColor: bg,
        quality: quality
    )
}.value
```

This requires the `CollageAssembly` protocol to also expose `assembleWithCGImages`, or we handle it internally.

**Decision**: Add `assembleWithCGImages` to the `CollageAssembly` protocol:

```swift
protocol CollageAssembly {
    func assemble(panels:images:crops:title:backgroundColor:quality:) -> Data?
    func assembleWithCGImages(panels:cgImages:crops:title:backgroundColor:quality:canvasSize:) -> Data?
    func assemblePreview(panels:images:crops:title:backgroundColor:targetSize:) -> NSImage?
    func assemblePreviewWithCGImages(panels:cgImages:crops:title:backgroundColor:targetSize:canvasSize:) -> NSImage?
}
```

#### 3. Thumbnail Caching
**File**: `CollageMaker/Views/ImagePickerView.swift:174-184`
**Changes**: Cache the thumbnail NSImage.

```swift
private var thumbnail: NSImage {
    CachedThumbnail.compute(for: item)
}

// Thread-safe cache
private enum CachedThumbnail {
    private static let cache = NSCache<NSUUID, NSImage>()

    static func compute(for item: ImageItem) -> NSImage {
        if let cached = cache.object(forKey: item.id) { return cached }

        let size = item.size
        let scale = min(160 / size.width, 120 / size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let thumbnail = NSImage(size: newSize)
        thumbnail.lockFocus()
        item.nsImage.draw(in: CGRect(origin: .zero, size: newSize))
        thumbnail.unlockFocus()

        cache.setObject(thumbnail, forKey: item.id)
        return thumbnail
    }
}
```

### Success Criteria:

#### Automated Verification:
- [ ] Project compiles without errors
- [ ] All existing unit tests pass
- [ ] `CollageAssemblerTests` pass with updated protocol
- [ ] No direct `SaliencyAnalyzer()` or `CollageAssembler()` instantiation in production code (except in `init` defaults)

#### Manual Verification:
- [ ] Export of large collage does not freeze UI (progress indicator spins during assembly)
- [ ] Thumbnails render quickly on repeated view appearances
- [ ] All export options (title, quality, background color) work correctly

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 5: Test Fixes and New Tests

### Overview

Fix test issues (hardcoded paths, duplicates, incorrect await) and add missing test coverage.

### Changes Required:

#### 1. Shared Test Helpers
**File**: `CollageMakerTests/TestHelpers.swift` (new)
**Changes**: Extract shared `createTestCGImage` and `createTestImageItem` functions.

```swift
import Testing
import AppKit
import CoreGraphics
@testable import CollageMaker

@MainActor
func createTestCGImage(
    color: CGColor,
    size: CGSize = CGSize(width: 1000, height: 800)
) -> CGImage {
    // ... (from CropDebounceChainTests.swift:8-29)
}

@MainActor
func createTestImageItem(
    color: NSColor = .red,
    size: CGSize = CGSize(width: 1000, height: 800)
) -> ImageItem {
    // ... (from CropDebounceChainTests.swift:32-36)
}
```

Remove duplicate `createTestCGImage` from `CollageMakerTests.swift:272-300` and `CropDebounceChainTests.swift:8-36`.

#### 2. Replace Hardcoded File Paths
**File**: `CollageMakerTests/CollageMakerTests.swift` — `CropWorkflowIntegrationTests`
**Changes**: Replace `loadTestImages()` with synthetic images.

```swift
// Before:
private func loadTestImages() -> [ImageItem] {
    let imageNames = ["Aza.jpg", "Drunkard.jpg", ...]
    // URL(string: "file:///Users/austin/Pictures/...")
}

// After:
private func loadTestImages() -> [ImageItem] {
    [
        createTestImageItem(color: .red),
        createTestImageItem(color: .blue),
        createTestImageItem(color: .green),
        createTestImageItem(color: .orange),
    ]
}
```

Update test assertions that depend on real image dimensions (e.g., crop bounds checks) to account for the synthetic image size (1000x800).

#### 3. Fix `await` on Non-Actor
**File**: `CollageMakerTests/CollageMakerTests.swift:161`
**Changes**: Remove unnecessary `await`.

```swift
// Before:
let assembler = await CollageAssembler()

// After:
let assembler = CollageAssembler()
```

Apply to all 4 assembler test methods.

#### 4. New `SaliencyAnalyzer` Tests
**File**: `CollageMakerTests/SaliencyAnalyzerTests.swift` (new)
**Changes**: Test error paths and basic behavior.

```swift
@MainActor
struct SaliencyAnalyzerTests {

    @Test func analyzeEmptyImageThrowsInvalidImage() async throws {
        let analyzer = SaliencyAnalyzer()
        let emptyImage = NSImage(size: CGSize(width: 0, height: 0))

        do {
            _ = try await analyzer.analyze(emptyImage)
            #expect(FAILURE)
        } catch {
            #expect(error is SaliencyError)
        }
    }

    @Test func analyzeValidImageReturnsResult() async throws {
        let analyzer = SaliencyAnalyzer()
        let image = createTestImageItem(color: .gray).nsImage

        let result = try await analyzer.analyze(image)
        #expect(result.center.x >= 0)
        #expect(result.center.y >= 0)
        #expect(result.radius > 0)
        #expect(result.confidence >= 0)
        #expect(result.confidence <= 1)
    }

    @Test func analyzeAllReturnsCorrectCount() async throws {
        let analyzer = SaliencyAnalyzer()
        let images = (0..<3).map { _ in createTestImageItem(color: .gray).nsImage }

        let results = try await analyzer.analyzeAll(images)
        #expect(results.count == 3)
    }
}
```

#### 5. New `CropManager` Tests
**File**: `CollageMakerTests/CropManagerTests.swift` (new)
**Changes**: Test crop manager in isolation.

```swift
@MainActor
struct CropManagerTests {

    @Test func initialCropsCreateOnePerPanel() async throws { ... }
    @Test func updateCropByPanelId() async throws { ... }
    @Test func updateCropCreatesNewEntryWhenMissing() async throws { ... }
    @Test func cropMapHasNoDuplicates() async throws { ... }
    @Test func saliencyCropsApplyCorrectly() async throws { ... }
}
```

#### 6. New `CollageViewModel` State Transition Tests
**File**: `CollageMakerTests/CollageViewModelTests.swift` (new)
**Changes**: Test key state transitions.

```swift
@MainActor
struct CollageViewModelTests {

    @Test func addImagesTriggersLayoutAndPreview() async throws { ... }
    @Test func removeImageAdjustsHeroIndex() async throws { ... }
    @Test func clearAllResetsAllState() async throws { ... }
    @Test func setHeroIndexRegeneratesLayout() async throws { ... }
    @Test func updateGutterRegeneratesLayout() async throws { ... }
    @Test func selectedPanelIdResetsSliderState() async throws { ... }
}
```

Use mock services:

```swift
@MainActor
struct MockSaliencyAnalyzer: SaliencyAnalysis {
    func analyze(_ image: NSImage) async throws -> SaliencyResult {
        SaliencyResult(center: .zero, radius: 100, confidence: 0.8)
    }
    func analyzeAll(_ images: [NSImage]) async throws -> [SaliencyResult] {
        images.map { _ in SaliencyResult(center: .zero, radius: 100, confidence: 0.8) }
    }
}

struct MockCollageAssembler: CollageAssembly {
    var assembleCalled = false
    func assemble(...) -> Data? { assembleCalled = true; Data() }
    func assembleWithCGImages(...) -> Data? { Data() }
    func assemblePreview(...) -> NSImage? { NSImage(size: .zero) }
    func assemblePreviewWithCGImages(...) -> NSImage? { NSImage(size: .zero) }
}
```

### Success Criteria:

#### Automated Verification:
- [ ] All unit tests pass
- [ ] No hardcoded file paths in tests (verified by grep for `/Users/austin/`)
- [ ] No `await` on non-actor types (verified by review)
- [ ] `TestHelpers.swift` exists with shared helpers
- [ ] `SaliencyAnalyzerTests.swift` exists with at least 3 tests
- [ ] `CropManagerTests.swift` exists with at least 5 tests
- [ ] `CollageViewModelTests.swift` exists with at least 6 tests
- [ ] Total test count increased from 30 to 45+

#### Manual Verification:
- [ ] All tests pass when run from Xcode test navigator
- [ ] Tests run successfully without requiring local image files
- [ ] Test execution time is reasonable (< 30 seconds)

**Implementation Note**: This is the final phase. After completion, run the full test suite and verify the project builds cleanly.

---

## Testing Strategy

### Unit Tests (per phase):
- **Phase 1**: All existing tests still pass; no new tests
- **Phase 2**: All existing tests adapted for UUID-based cropMap; assembler tests updated for protocol
- **Phase 3**: `CropGestureTests` and `CropWorkflowIntegrationTests` adapted for delegation; new `CropManagerTests`
- **Phase 4**: Tests use mock services via DI; new export background test
- **Phase 5**: All test fixes; new `SaliencyAnalyzerTests`, `CollageViewModelTests`; shared helpers

### Integration Tests:
- `CropWorkflowIntegrationTests` verify full crop workflow through ViewModel
- `CropGestureTests` verify gesture chain through ViewModel

### Manual Testing Steps:
1. Launch app, verify no saliency analysis runs on startup
2. Drop 4 images, verify layout generates with preview
3. Select a panel, drag to pan crop, verify preview updates
4. Select a panel, pinch to zoom crop, verify preview updates
5. Click "Analyze Images", verify crops adjust to saliency
6. Adjust gutter slider, verify layout regenerates (single regeneration)
7. Export collage, verify UI remains responsive during assembly
8. Add a portrait-oriented phone photo, verify saliency analysis respects orientation

## Performance Considerations

- **Crop lookup**: O(1) dictionary lookup by UUID replaces O(n) array search by CGRect
- **`panelCrops`**: Eliminated — `cropMap` is already a dictionary
- **Export**: Background executor prevents UI blocking for large collages
- **Thumbnails**: NSCache prevents redundant thumbnail generation
- **Preview**: `objectWillChange.send()` before `previewImage = result` ensures efficient SwiftUI updates

## Migration Notes

- `CropInfo.destinationRect` is retained for rendering but no longer used as a lookup key
- `CollageViewModel.crops` array property replaced by `cropMap` dictionary; `cropsArray` computed property provides backward compatibility for service calls
- Test file `CropDebounceChainTests.swift` renamed conceptually (still tests gesture chain) — no rename needed since it tests through ViewModel

## References

- Review document: `agent_docs/reviews/collagemaker-solid-review.md`
- ViewModel: `CollageMaker/ViewModel/CollageViewModel.swift` (507 lines)
- Services: `CollageMaker/Services/SaliencyAnalyzer.swift` (135 lines), `CollageMaker/Services/CollageAssembler.swift` (199 lines)
- Views: `CollageMaker/ContentView.swift` (127 lines), `CollageMaker/Views/CollageEditorView.swift` (100 lines)
- Tests: `CollageMakerTests/CollageMakerTests.swift` (526 lines), `CollageMakerTests/CropDebounceChainTests.swift` (198 lines)
