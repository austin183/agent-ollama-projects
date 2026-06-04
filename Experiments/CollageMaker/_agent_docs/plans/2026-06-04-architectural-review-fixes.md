# 2026-06-04 Architectural Review Fixes — Execution Plan

**Source review:** `_agent_docs/reviews/2026-06-04-full-architectural-review.md`
**Scope:** 2 Critical, 10 Warning, 18 Suggestion findings + 4 test gaps
**Status:** Not started

---

## Phase 1: Immediate — Critical Fixes & Quick Wins (4 items) — COMPLETED

### 1.1 C-2: Delete `TitleMetrics.swift` + update doc comment

**Status:** `TitleMetrics.swift` file deleted. Remaining: update doc comment.

**Files changed:**
- `Services/TitleRendererCT.swift`

**Edit at line 217:**
```swift
// FROM:
/// Bounding box relative to baseline origin, matching TitleMetrics.boundingBox semantics.

// TO:
/// Bounding box relative to baseline origin.
```

---

### 1.2 S-2: Remove `exportManager` double-init

**File:** `ViewModel/CollageViewModel.swift:88`

**Current:**
```swift
var exportManager: ExportManager = ExportManager(assembler: CollageAssembler())
```

**Change to:**
```swift
var exportManager: ExportManager!
```

Line 385 in `init` already sets it: `self.exportManager = ExportManager(assembler: assembler)`

---

### 1.3 W-10: Fix force cast in `ScrollPanView`

**File:** `Views/ScrollPanView.swift:19`

**Current:**
```swift
func updateNSView(_ nsView: NSView, context: Context) {
    let view = nsView as! ScrollCaptureView
```

**Change to:**
```swift
func updateNSView(_ nsView: NSView, context: Context) {
    guard let view = nsView as? ScrollCaptureView else { return }
```

---

### 1.4 C-1: Fix `isProcessing` race condition

**Problem:** `ExportManager.export()` and `CollageViewModel.analyzeSaliency()` both set/clear
`isProcessing` independently. A `defer { isProcessing = false }` from one can clear the flag
while the other is still running.

**Files changed:**
- `ViewModel/CollageViewModel.swift`
- `ViewModel/ExportManager.swift`

**Step 1 — CollageViewModel.swift line 336:**
```swift
// FROM:
var isProcessing: Bool = false

// TO:
private var processingCount = 0
var isProcessing: Bool { processingCount > 0 }

func beginProcessing() { processingCount += 1 }
func endProcessing() { processingCount = max(0, processingCount - 1) }
```

**Step 2 — CollageViewModel.swift lines 598-599 (analyzeSaliency):**
```swift
// FROM:
isProcessing = true
defer { isProcessing = false }

// TO:
beginProcessing()
defer { endProcessing() }
```

**Step 3 — CollageViewModel.swift line 478 (clearAll):**
```swift
// FROM:
isProcessing = false

// TO:
processingCount = 0
```

**Step 4 — ExportManager.swift lines 29 and 32:**
```swift
// FROM:
viewModel.isProcessing = true
// ...
defer { viewModel.isProcessing = false; isExporting = false }

// TO:
viewModel.beginProcessing()
// ...
defer { viewModel.endProcessing(); isExporting = false }
```

---

## Phase 2: Short-term — Refactoring (6 items) — COMPLETED

### 2.1 W-5: Extract property change helper + refactor title setters

**File:** `ViewModel/CollageViewModel.swift`

**Problem:** 12 `didSet` blocks repeat the same pattern (guard, undo, save, side effect). 7
title setter methods each duplicate the same 8-line pattern.

**Approach:** Two-part refactoring.

#### Part A: Extract `registerUndo` helper

Add after `debouncedSave()` (around line 354):

```swift
private func registerUndo<Value>(oldValue: Value, actionName: String, restore: @escaping (CollageViewModel) -> Void) {
    guard !isInitializing else { return }
    undoManager.registerUndo(withTarget: self) { target in
        restore(target)
    }
    undoManager.setActionName(actionName)
    debouncedSave()
}
```

Then simplify each `didSet`. Example for `layoutStyle`:

```swift
// FROM (lines 134-145):
var layoutStyle: LayoutStyle = .hero {
    didSet {
        guard !isInitializing else { return }
        undoManager.registerUndo(withTarget: self) { target in
            target.layoutStyle = oldValue
        }
        undoManager.setActionName("Change Layout")
        debouncedSave()
        logger.info("Layout style changed to \(self.layoutStyle.rawValue, privacy: .public)")
        regenerateLayout()
    }
}

// TO:
var layoutStyle: LayoutStyle = .hero {
    didSet {
        registerUndo(oldValue: oldValue, actionName: "Change Layout") { $0.layoutStyle = oldValue }
        logger.info("Layout style changed to \(self.layoutStyle.rawValue, privacy: .public)")
        regenerateLayout()
    }
}
```

Apply same pattern to: `titleAttrString`, `titleStyle`, `backgroundColor`, `exportQuality`,
`backgroundStyle`, `gradientStartColor`, `gradientEndColor`, `gradientAngle`, `backgroundImage`,
`backgroundOpacity`. The `gutter` property uses a debounce task and should NOT be changed.

#### Part B: Title setter helper

Add before `setTitleFontFamily` (around line 935):

```swift
private func applyTitleChange<Value>(
    at keyPath: WritableKeyPath<TitleStyle, Value>,
    oldValue: Value,
    actionName: String,
    sideEffect: @escaping @MainActor () -> Void
) {
    guard !isInitializing else { return }
    undoManager.registerUndo(withTarget: self) { target in
        target.titleStyle[keyPath: keyPath] = oldValue
    }
    undoManager.setActionName(actionName)
    debouncedSave()
    sideEffect()
}

private func titleViewUpdate() {
    if isLayeredMode {
        updateTitleImage()
    } else {
        updatePreview()
    }
}
```

Then refactor each setter. Example:

```swift
// FROM setTitleFontFamily (lines 935-945):
func setTitleFontFamily(_ family: String) {
    guard !isInitializing else { return }
    let oldValue = titleStyle.fontFamily
    titleStyle.fontFamily = family
    undoManager.registerUndo(withTarget: self) { target in
        target.setTitleFontFamily(oldValue)
    }
    undoManager.setActionName("Change Font Family")
    updateTitleImageLive()
    debouncedSave()
}

// TO:
func setTitleFontFamily(_ family: String) {
    let oldValue = titleStyle.fontFamily
    titleStyle.fontFamily = family
    applyTitleChange(at: \.fontFamily, oldValue: oldValue, actionName: "Change Font Family") {
        self.updateTitleImageLive()
    }
}
```

For `setTitleFontSize`, the side effect is the debounce task, not `updateTitleImage()`:

```swift
func setTitleFontSize(_ size: CGFloat) {
    let oldValue = titleStyle.fontSize
    titleStyle.fontSize = size
    applyTitleChange(at: \.fontSize, oldValue: oldValue, actionName: "Change Font Size") {
        self.fontSizeDebounceTask?.cancel()
        self.fontSizeDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            self?.updateTitleImage()
        }
    }
}
```

For the four setters that share the same side effect (`setTitleBackgroundColor`,
`setTitleFontColor`, `setTitleAlignment`, `setTitleShowBackground`):

```swift
func setTitleBackgroundColor(_ color: NSColor) {
    let oldValue = titleStyle.backgroundColor
    titleStyle.backgroundColor = color
    applyTitleChange(at: \.backgroundColor, oldValue: oldValue, actionName: "Change Title BG Color", sideEffect: titleViewUpdate)
}
```

---

### 2.2 W-2: Fix ExportManager DIP violation

**File:** `ViewModel/ExportManager.swift`

**Problem:** ExportManager directly mutates `viewModel.isProcessing` and `viewModel.errorMessage`.

**Step 1 — Define `ExportResult`** (add before `ExportManager` class):

```swift
enum ExportResult {
    case success(URL)
    case cancelled
    case failure(Error)
}
```

**Step 2 — Refactor `export` method signature:**

```swift
func export(
    config: AssemblyConfig,
    cgImages: [CGImage],
    backgroundImage: CGImage?,
    quality: Double
) async -> ExportResult
```

**Step 3 — Remove VM mutations from ExportManager:**
- Remove `viewModel.isProcessing` / `viewModel.beginProcessing()` calls
- Remove `viewModel.errorMessage = error.localizedDescription`
- Return `ExportResult` instead of `URL?`

**Step 4 — Update `CollageViewModel.exportCollage()`:**

```swift
func exportCollage() async -> URL? {
    beginProcessing()
    defer { endProcessing() }
    errorMessage = nil

    guard !panels.isEmpty else { return nil }

    let config = buildAssemblyConfig()
    let cgImages = imageLibrary.images.map { $0.cgImage }
    let bgCG = backgroundImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)

    switch await exportManager.export(
        config: config,
        cgImages: cgImages,
        backgroundImage: bgCG,
        quality: exportQuality
    ) {
    case .success(let url):
        return url
    case .cancelled:
        return nil
    case .failure(let error):
        errorMessage = error.localizedDescription
        return nil
    }
}
```

**Step 5 — The save panel UI** still needs to run on main thread. The `export` method needs to
show the save panel synchronously (it's `@MainActor`), then do the async rendering. The method
signature stays `@MainActor func export(...) async -> ExportResult`.

---

### 2.3 W-8: Extract `cancelAllTasks()` in PreviewManager

**File:** `Services/PreviewManager.swift:172-204`

**Current:** `clearAll()` (lines 172-191) and `cancelAll()` (lines 193-204) share identical
task cancellation code (5 lines each).

**Change:**

```swift
// Add new private method:
private func cancelAllTasks() {
    previewTask?.cancel()
    previewDebounceTask?.cancel()
    panelPreviewTasks.values.forEach { $0.cancel() }
    backgroundTask?.cancel()
    titleTask?.cancel()
    previewTask = nil
    previewDebounceTask = nil
    panelPreviewTasks.removeAll()
    backgroundTask = nil
    titleTask = nil
}

// clearAll becomes:
func clearAll() {
    cancelAllTasks()
    previewImage = nil
    previewBackgroundImage = nil
    panelRenderedImages.removeAll()
    titleImage = nil
    previewGeneration = 0
    backgroundGeneration = 0
    panelGenerations.removeAll()
    titleGeneration = 0
}

// cancelAll becomes:
func cancelAll() {
    cancelAllTasks()
}
```

---

### 2.4 W-9: Extract `CTAttributedStringBuilder`

**File:** `Services/TitleRendererCT.swift:54-215`

**Problem:** `TitleBoundsCT.compute()` (lines 54-100) and `TitleMetricsCT.prepare()` (lines
147-215) both build a `CFAttributedString` with identical steps:
1. `CFAttributedStringCreateMutable`
2. `CFAttributedStringReplaceString`
3. Set paragraph style with `kCTParagraphStyleAttributeName`
4. Loop over runs, apply `kCTFontAttributeName` with `makeCTFont`
5. `CTFramesetterCreateWithAttributedString`

`TitleMetricsCT` additionally applies `kCTForegroundColorAttributeName` (step 6).

**Extract:**

```swift
// Add before TitleBoundsCT:
struct CTAttributedStringBuilder {
    static func build(
        textData: TitleTextData,
        style: TitleStyle,
        foregroundColor: CGColor? = nil
    ) -> (cfAttrString: CFAttributedString, stringLength: CFIndex, primaryFont: CTFont) {
        let paragraphStyle = makeParagraphStyle(alignment: style.alignment)

        let cfAttrString = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0)!
        CFAttributedStringReplaceString(cfAttrString, CFRange(), textData.text as CFString)
        let stringLength = CFAttributedStringGetLength(cfAttrString)

        CFAttributedStringSetAttribute(
            cfAttrString,
            CFRange(location: 0, length: stringLength),
            kCTParagraphStyleAttributeName,
            paragraphStyle
        )

        var primaryFont: CTFont?
        for run in textData.runs {
            let traits = CTFontSymbolicTraits(rawValue: run.symbolicTraitsRawValue)
            let font = makeCTFont(
                existingFamily: run.fontFamily,
                existingTraits: traits,
                baseFamily: style.fontFamily,
                targetSize: style.fontSize
            )
            CFAttributedStringSetAttribute(
                cfAttrString,
                CFRange(location: run.range.location, length: run.range.length),
                kCTFontAttributeName,
                font
            )
            if primaryFont == nil {
                primaryFont = font
            }
        }

        if let fgColor = foregroundColor {
            CFAttributedStringSetAttribute(
                cfAttrString,
                CFRange(location: 0, length: stringLength),
                kCTForegroundColorAttributeName,
                fgColor
            )
        }

        let pFont = primaryFont ?? CTFontCreateUIFontForLanguage(.system, style.fontSize, nil)!
        return (cfAttrString, stringLength, pFont)
    }
}
```

Then update `TitleBoundsCT.compute()`:

```swift
static func compute(textData: TitleTextData, style: TitleStyle) -> TitleBoundsCT {
    let (cfAttrString, stringLength, pFont) = CTAttributedStringBuilder.build(
        textData: textData,
        style: style
    )

    let framesetter = CTFramesetterCreateWithAttributedString(cfAttrString)

    return TitleBoundsCT(
        framesetter: framesetter,
        stringLength: stringLength,
        fontDescent: CTFontGetDescent(pFont),
        styleWidth: style.width
    )
}
```

And update `TitleMetricsCT.prepare()` similarly, passing `foregroundColor: fontColor`.

---

### 2.5 W-7: BackgroundConfig stored CGColor properties (kept as-is)

**File:** `Models/AssemblyConfig.swift:21-52`

**Decision:** Kept CGColor as stored properties. Computed properties (`var backgroundColor: CGColor { color.cgColor }`) would evaluate `NSColor.cgColor` on background threads (RenderScheduler, Task.detached), which is undefined behavior. The stored approach captures `.cgColor` at init time on MainActor, then the `CGColor` values cross actor boundaries safely.

**Change:** Improved the `@unchecked Sendable` safety comment to document this correctly:
```swift
// Safety: NSColor is MainActor-only, but BackgroundConfig is only ever
// constructed on the main actor. CGColor values are captured at init time
// on the main actor and then accessed safely on background threads.
```

**Note:** The `@unchecked Sendable` justification comment here also addresses S-5 for this type.

---

### 2.6 W-3: Structured AssemblyConfig secondary init

**File:** `Models/AssemblyConfig.swift` (add after existing init)

```swift
extension AssemblyConfig {
    /// Construct from pre-built sub-configs — avoids the 14-parameter flattened init.
    init(
        layout: LayoutConfig,
        title: TitleConfig,
        background: BackgroundConfig,
        canvasSize: CGSize
    ) {
        self.layout = layout
        self.title = title
        self.background = background
        self.canvasSize = canvasSize
    }
}
```

After this is added, update `TestHelpers.swift` `makeAssemblyConfig()` to use the new init
for cleaner test code.

---

## Phase 3: Medium-term — Architecture (3 items)

### 3.1 S-1: Convert `GestureCoordinator` to `@Observable`

**Files changed:**
- `Views/GestureCoordinator.swift`
- `Views/CollageEditorView.swift:20`

**GestureCoordinator.swift — FROM:**
```swift
import Combine
import CoreGraphics
import SwiftUI

@MainActor
final class GestureCoordinator: ObservableObject {
    @Published var pinchPanelId: UUID?
    @Published var dragTitleLocked: Bool = false
    // ... 6 more @Published properties
```

**TO:**
```swift
import CoreGraphics

@MainActor
@Observable
final class GestureCoordinator {
    var pinchPanelId: UUID?
    var dragTitleLocked: Bool = false
    // ... 6 more properties (no @Published needed)
```

**CollageEditorView.swift:20 — FROM:**
```swift
@StateObject private var gestureCoordinator = GestureCoordinator()
```

**TO:**
```swift
private var gestureCoordinator = GestureCoordinator()
```

With `@Observable`, the view observes `gestureCoordinator` automatically through the
`@Bindable` / value binding chain. Since `gestureCoordinator` is a property of the struct,
SwiftUI will track it as state.

Actually, the correct approach is:
```swift
@State private var gestureCoordinator = GestureCoordinator()
```

`@State` wraps the `@Observable` class and provides structural observation.

---

### 3.2 W-6: Extract business logic from Views

**Files changed:**
- `Views/CollageEditorView.swift` — extract title drag/resize logic
- `ContentView.swift` — extract drop handling

#### 3.2.1 TitleDragHandler

Create `Views/TitleDragHandler.swift`:

```swift
import CoreGraphics
import SwiftUI

struct TitleDragHandler {
    let titleCanvasFrame: CGRect
    let previewSize: CGSize
    let resizeHandleWidth: CGFloat
    let handleThreshold: CGFloat

    init(titleCanvasFrame: CGRect, previewSize: CGSize) {
        self.titleCanvasFrame = titleCanvasFrame
        self.previewSize = previewSize
        self.resizeHandleWidth = 8
        self.handleThreshold = resizeHandleWidth + 2
    }

    func hitTest(at location: CGPoint) -> TitleHitResult {
        let tf = canvasToPreviewFrame(titleCanvasFrame, in: previewSize)

        // Left resize handle
        if tf.minX - handleThreshold <= location.x,
           location.x <= tf.minX + handleThreshold,
           tf.minY <= location.y, location.y <= tf.maxY {
            return .resize(.left)
        }
        // Right resize handle
        if tf.maxX - handleThreshold <= location.x,
           location.x <= tf.maxX + handleThreshold,
           tf.minY <= location.y, location.y <= tf.maxY {
            return .resize(.right)
        }
        // Title body
        if tf.contains(location) {
            return .drag
        }
        return .none
    }

    func computeDragPosition(
        screenLocation: CGPoint,
        offset: CGPoint,
        canvasSize: CGSize
    ) -> (positionX: CGFloat, positionY: CGFloat) {
        let canvasPoint = CropManager.screenToCanvasPoint(screenLocation, in: previewSize)
        let positionX = (canvasPoint.x + offset.x) / canvasSize.width
        let positionY = 1.0 - (canvasPoint.y + offset.y) / canvasSize.height
        return (positionX, positionY)
    }

    func computeResizeWidth(
        screenLocation: CGPoint,
        edge: TitleResizeEdge,
        currentFrame: CGRect,
        minWidth: CGFloat
    ) -> (width: CGFloat, positionXDelta: CGFloat) {
        let canvasPoint = CropManager.screenToCanvasPoint(screenLocation, in: previewSize)
        let canvasX = canvasPoint.x

        switch edge {
        case .right:
            let newWidth = max(minWidth, canvasX - currentFrame.minX)
            return (newWidth, 0)
        case .left:
            let newWidth = max(minWidth, currentFrame.maxX - canvasX)
            let dx = (currentFrame.width - newWidth) / 2
            return (newWidth, dx)
        case .none:
            return (0, 0)
        }
    }

    private func canvasToPreviewFrame(_ canvasRect: CGRect, in previewSize: CGSize) -> CGRect {
        CropManager.canvasToPreviewFrame(canvasRect, in: previewSize)
    }
}

enum TitleHitResult {
    case none, drag, resize(TitleResizeEdge)
}
```

Then in `CollageEditorView.swift`, replace the inline hit detection (lines 153-186) with
`TitleDragHandler` calls.

#### 3.2.2 DropHandler

Create `Services/DropHandler.swift`:

```swift
import Foundation
import UniformTypeIdentifiers

struct DropHandler {
    private let imageTypes: [UTType]

    init() {
        self.imageTypes = [.jpeg, .png, .tiff, .heic, .heif]
    }

    func loadImageURLs(from itemProviders: [NSItemProvider]) async -> [URL] {
        await withTaskGroup(of: URL?.self) { group in
            for provider in itemProviders {
                group.addTask {
                    await self.extractURL(from: provider)
                }
            }

            var urls: [URL] = []
            for await url in group {
                if let url { urls.append(url) }
            }
            return urls
        }
    }

    private func extractURL(from provider: NSItemProvider) async -> URL? {
        // Try file URL first
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            do {
                let loaded = try await provider.loadItem(
                    forTypeIdentifier: UTType.fileURL.identifier
                )
                if let url = loaded as? URL {
                    return validate(url)
                }
                if let nsurl = loaded as? NSURL, let url = URL(cgURL: nsurl) {
                    return validate(url)
                }
            } catch {
                // fall through to data loading
            }
        }

        // Fall back to data loading
        for uttype in imageTypes {
            if provider.hasItemConformingToTypeIdentifier(uttype.identifier) {
                do {
                    let data = try await provider.loadDataRepresentation(
                        forTypeIdentifier: uttype.identifier
                    )
                    return await MainActor.run {
                        Self.saveTempData(data, uttype: uttype)
                    }
                } catch {
                    continue
                }
            }
        }
        return nil
    }

    private func validate(_ url: URL) -> URL? {
        guard imageTypes.contains(where: { $0.conforms(to: UTType(filenameExtension: url.pathExtension)) })
        else { return nil }
        return url
    }

    private static func saveTempData(_ data: Data, uttype: UTType) -> URL? {
        // Create temp file
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "drop_\(UUID().uuidString).\(uttype.preferredFilenameExtension ?? "dat")"
        let url = tempDir.appendingPathComponent(filename)
        try? data.write(to: url)
        return url
    }
}
```

Then in `ContentView.swift`, replace the inline drop handling (lines 257-324) with:
```swift
let handler = DropHandler()
let urls = await handler.loadImageURLs(from: itemProviders)
await viewModel.addImages(from: urls)
```

---

### 3.3 W-4: CollageAssembler sub-renderer injection

**Status:** Defer for now. The current protocol hierarchy (`CollageRenderer`, `PanelRenderer`,
`BackgroundRenderer`, `TitleRenderer`) already supports granular mocking. The monolith is 428
lines but well-organized with private methods. Sub-renderer injection would add indirection
without clear benefit at this size. Revisit if the file exceeds 600 lines.

---

## Phase 4: Polish (16 items)

### 4.1 S-3: Offload title bounds to background Task

**File:** `ViewModel/CollageViewModel.swift:44-86`

The `ensureTitleBounds()` method calls `TitleBoundsCT.compute()` synchronously on `@MainActor`.
For complex attributed strings with multiple font runs, this can cause main-thread jank.

**Approach:** Add a background task that computes bounds asynchronously:

```swift
private var titleBoundsTask: Task<Void, Never>?

private func computeTitleBoundsAsync() {
    titleBoundsTask?.cancel()
    let textData = TitleTextData.extract(from: titleAttrString)
    let style = titleStyle
    let layoutKey = style.layoutKey
    let attrStr = titleAttrString

    titleBoundsTask = Task.detached { [textData, style, layoutKey, attrStr] in
        let bounds = TitleBoundsCT.compute(textData: textData, style: style)
        await MainActor.run {
            // Update cache if still current
            // (Compare layoutKey and attrStr to detect staleness)
        }
    }
}
```

**Risk:** Medium. The synchronous path is currently fast for typical titles. This change adds
complexity for a marginal gain. Defer unless profiling shows a problem.

---

### 4.2 S-4: Deduplicate NSColorPickerView

**Files:** `Views/ExportPanel.swift:264-299`, `Views/SettingsView.swift:1-47`

Both define `NSViewRepresentable` wrappers for `NSColorWell`. The `ExportPanel` version is
`NSColorPickerView`. The `SettingsView` version is `UserDefaultsColorView` (which also
persists to UserDefaults).

**Approach:** Extract a shared `ColorWellView` from the `ExportPanel` version. Keep
`UserDefaultsColorView` in SettingsView as-is since it adds persistence logic.

Create `Views/ColorWellView.swift`:

```swift
import AppKit
import SwiftUI

struct ColorWellView: NSViewRepresentable {
    @Binding var color: NSColor

    func makeNSView(context: Context) -> NSColorWell {
        let well = NSColorWell()
        well.isContinuous = true
        well.alphaValue = 1.0
        well.target = context.coordinator
        well.action = #selector(Coordinator.colorChanged(_:))
        well.color = color
        return well
    }

    func updateNSView(_ well: NSColorWell, context: Context) {
        well.color = color
    }

    func makeCoordinator() -> Coordinator { Coordinator(color: $color) }

    class Coordinator: NSObject {
        @Binding var color: NSColor
        init(color: Binding<NSColor>) { _color = color; super.init() }
        @objc func colorChanged(_ sender: NSColorWell) { color = sender.color }
    }
}
```

Then replace `NSColorPickerView` in `ExportPanel.swift` with `ColorWellView` and delete the
local struct definition.

---

### 4.3 S-5: Add @unchecked Sendable justification comments

**Files:** `Models/AssemblyConfig.swift` lines 10, 19, 33, 99

Add comments to each `@unchecked Sendable`:

```swift
// LayoutConfig: @unchecked Sendable
// Safety: Contains [ImagePanel] (struct with UUID + CGRect + Int),
// [CropInfo] (struct with CGRect), and [UUID: Int]. All Sendable.

// TitleConfig: @unchecked Sendable
// Safety: Contains TitleTextData (Sendable), TitleStyle (@unchecked Sendable
// due to NSColor), and CGColor (Sendable).

// BackgroundConfig: @unchecked Sendable
// Safety: Contains NSColor which is MainActor-only, but BackgroundConfig is
// only constructed on the main actor and the CGColor computed properties
// are captured before crossing actor boundaries.

// AssemblyConfig: @unchecked Sendable
// Safety: Contains LayoutConfig, TitleConfig, BackgroundConfig (all
// @unchecked Sendable) and CGSize (Sendable).
```

---

### 4.4 S-6: Precompute panelFrames in CollageEditorView

**File:** `Views/CollageEditorView.swift:38,336`

**Problem:** `panelFrames` is computed in the `body` GeometryReader (line 38) and again in
`panelAt()` (line 337) on every tap/drag.

**Approach:** Compute once in `body`, pass into `panelAt` via a `@State` variable or a
computed property that the gesture closures capture.

Actually, the simpler fix: make `panelAt` accept the precomputed frames:

```swift
// Add parameter:
private func panelAt(location: CGPoint, panelFrames: [UUID: CGRect]) -> UUID? {
    if let id = CropManager.hitTestPanel(at: location, panelFrames: panelFrames),
       let panel = viewModel.panels.first(where: { $0.id == id }),
       let frame = panelFrames[id] {
        // ...
    }
    return nil
}
```

Then in the gesture closures, capture `panelFrames` from the GeometryReader scope and pass it
in. Delete the `freshFrames` computation inside `panelAt`.

---

### 4.5 S-7: Move undo registration from View to ViewModel

**File:** `Views/CollageEditorView.swift:130-141,220-226,291-307`

**Problem:** The View layer registers undo actions for scroll pan, title drag, and pinch zoom.

**Approach:** Add ViewModel methods:

```swift
func beginGestureUndo() { undoManager.beginUndoGrouping() }
func endGestureUndo(actionName: String) {
    undoManager.setActionName(actionName)
    undoManager.endUndoGrouping()
}
func registerTitleStyleUndo(oldStyle: TitleStyle) {
    undoManager.registerUndo(withTarget: self) { $0.titleStyle = oldStyle }
    undoManager.setActionName("Move Title")
}
```

Then in the view, call `viewModel.beginGestureUndo()` instead of
`viewModel.undoManager.beginUndoGrouping()`.

---

### 4.6 S-8: Extract search filtering extension

**Files:** `ContentView.swift:20-28`, `Views/ImagePickerGrid.swift:10-18`

Create `Models/ImageItem+Filtering.swift`:

```swift
extension Array where Element == ImageItem {
    func indexed(by query: String) -> [(index: Int, item: ImageItem)] {
        if query.isEmpty {
            return enumerated().map { ($0.offset, $0.element) }
        }
        return enumerated()
            .filter { $0.element.filename.localizedCaseInsensitiveContains(query) }
            .map { ($0.offset, $0.element) }
    }
}
```

Then in both views:
```swift
// FROM:
private var filteredImages: [(index: Int, item: ImageItem)] { ... }

// TO:
private var filteredImages: [(index: Int, item: ImageItem)] {
    viewModel.imageLibrary.images.indexed(by: searchQuery)
}
// or
private var filteredImages: [(index: Int, item: ImageItem)] {
    images.indexed(by: searchQuery)
}
```

---

### 4.7 S-9: Store single image repr in ImageItem

**File:** `Models/ImageItem.swift`

**Current:** Stores `nsImage`, `cgImage`, and `thumbnail` (3 representations).

**Analysis:** The `nsImage` property is used for display in the sidebar thumbnails. But the
`thumbnail` property already serves this purpose. Check callers:

- `ContentView.swift` sidebar uses `item.thumbnail` for display
- `CollageEditorView.swift` uses `item.thumbnail` for drag preview
- `CollageAssembler` uses `item.cgImage` for rendering
- `ImageLibraryManager` constructs both from the same source data

**Approach:** Remove `nsImage` from `ImageItem`. Derive `NSImage` from `cgImage` at the call
site if needed. This halves the memory for the full-resolution image data.

**Risk:** Medium — verify no caller uses `item.nsImage` directly. If any do, derive on demand:
```swift
extension ImageItem {
    var nsImage: NSImage {
        NSImage(cgImage: cgImage, size: size)
    }
}
```

---

### 4.8 S-10: Parameterize Vision requests in SaliencyAnalyzer

**File:** `Services/SaliencyAnalyzer.swift:38-39`

**Current:** Hardcodes `VNGenerateAttentionBasedSaliencyImageRequest` and
`VNDetectFaceRectanglesRequest`.

**Approach:** Add a configuration enum:

```swift
enum SaliencyMode: Sendable {
    case attentionBased  // current default
    case faceOnly
    case combined        // current behavior
}
```

And parameterize the `analyze` method. **Low priority** — the current mode works well and
there's no UI to change the mode.

---

### 4.9 S-11: NaN/infinity guards in FitMath

**File:** `Services/FitMath.swift:10,34`

**Current guards:** `sourceSize.height > 0` — catches zero but not NaN/Infinity.

**Change:**
```swift
// fit() guard:
guard sourceSize.height > 0, sourceSize.height.isFinite,
      containerSize.height > 0, containerSize.height.isFinite else {
    return (.zero, .zero)
}

// sourceRect() guard:
guard imageSize.height > 0, imageSize.height.isFinite,
      panelSize.height > 0, panelSize.height.isFinite else {
    return .zero
}
```

---

### 4.10 S-12: Fix deprecated noneSkipFirst in ImageLibraryManager

**File:** `ViewModel/ImageLibraryManager.swift:66`

**Current:**
```swift
bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
```

**Change to:**
```swift
bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
```

---

### 4.11 S-13: Replace arbitrary sleep in awaitPendingTasks

**File:** `Services/PreviewManager.swift:208-210`

**Current:**
```swift
func awaitPendingTasks() async {
    try? await Task.sleep(nanoseconds: 300_000_000)
}
```

**Approach:** Use a `TaskCompletionBox` (Swift 5.10+) or an `AsyncStream`:

```swift
@MainActor
final class PreviewManager {
    // ... existing properties

    private var pendingTaskCount = 0
    private var taskCompletionContinuation: CheckedContinuation<Void, Never>?

    func awaitPendingTasks() async {
        guard pendingTaskCount > 0 else { return }
        await withCheckedContinuation { cont in
            taskCompletionContinuation = cont
        }
    }

    private func signalAllTasksComplete() {
        pendingTaskCount -= 1
        if pendingTaskCount <= 0, let cont = taskCompletionContinuation {
            taskCompletionContinuation = nil
            cont.resume()
        }
    }
}
```

**Risk:** Medium — this changes the synchronization primitive and needs careful integration
with all task creation/cleanup paths. **Defer** if time-constrained.

---

### 4.12 S-14: Split LoggingExtensions.swift

**File:** `Services/LoggingExtensions.swift`

**Current:** Contains `DebugHelpers` struct and `NSColor+rgbaHex` extension.

**Split into:**
- `Services/DebugHelpers.swift` — move `DebugHelpers` struct
- `Services/NSColor+Hex.swift` — move `NSColor` extension

Delete `LoggingExtensions.swift`.

---

### 4.13 S-15: Split SaliencyResult.cropOrigin

**File:** `Models/SaliencyResult.swift:15-35`

**Current:** Combines Vision coordinate swap and clamping in one method.

**Split into:**
```swift
/// Converts the normalized Vision center to image-space coordinates.
/// Vision uses bottom-left origin; CGImage uses top-left.
/// For portrait images, VNImageRequestHandler rotates 90°, swapping x/y.
func toImageSpace(for imageSize: CGSize) -> CGPoint {
    var pt = CGPoint(x: center.x * imageSize.width, y: center.y * imageSize.height)
    if imageSize.width < imageSize.height {
        pt = CGPoint(x: center.y * imageSize.width, y: center.x * imageSize.height)
    }
    return pt
}

func cropOrigin(for imageSize: CGSize, cropSize: CGSize) -> CGPoint {
    let imageCenter = toImageSpace(for: imageSize)
    let halfW = cropSize.width / 2
    let halfH = cropSize.height / 2
    var originX = imageCenter.x - halfW
    var originY = imageCenter.y - halfH
    originX = max(0, min(originX, imageSize.width - cropSize.width))
    originY = max(0, min(originY, imageSize.height - cropSize.height))
    return CGPoint(x: originX, y: originY)
}
```

---

### 4.14 S-16: Fix TitleStyle.LayoutKey visibility

**File:** `Models/TitleStyle.swift:8-20`

**Current:** `public struct LayoutKey` inside internal `TitleStyle`.

**Change:** Remove `public` from `LayoutKey` and its members:

```swift
// FROM:
public struct LayoutKey: Hashable {
    public let fontFamily: String
    public let fontSize: CGFloat
    public let width: CGFloat
    public let alignment: NSTextAlignment
    public init(...) { ... }
}

// TO:
struct LayoutKey: Hashable {
    let fontFamily: String
    let fontSize: CGFloat
    let width: CGFloat
    let alignment: NSTextAlignment
}
```

Also remove `public` from `layoutKey` computed property (line 33).

---

### 4.15 S-17: Rename CanvasConfig or expand

**File:** `Models/CanvasConfig.swift`

**Current:** Only 2 constants for a type named after the entire canvas subsystem.

**Approach:** Rename to `SizeConstants` and expand:

```swift
import CoreGraphics

enum SizeConstants {
    static let defaultCanvasSize = CGSize(width: 1920, height: 1080)
    static let defaultPreviewSize = CGSize(width: 960, height: 540)
    static let canvasAspect: CGFloat { defaultCanvasSize.width / defaultCanvasSize.height }
    static let canvasToPreviewScale: CGFloat { defaultPreviewSize.width / defaultCanvasSize.width }
}
```

Update all callers (15+ locations) from `CanvasConfig` to `SizeConstants`.

---

### 4.16 S-18: Remove SplitMix64 RandomNumberGenerator conformance

**File:** `Services/LayoutGenerator.swift:206`

**Current:** Conforms to `RandomNumberGenerator` but only uses manual bit extraction.

**Change:**
```swift
// FROM:
struct SplitMix64: RandomNumberGenerator {

// TO:
/// Deterministic PRNG for reproducible mosaic layouts.
struct SeededPRNG {
```

Rename all references from `SplitMix64` to `SeededPRNG`.

---

## Phase 5: Tests (4 items)

### 5.1 CG-1: Add RenderScheduler tests

**New file:** `CollageMakerTests/RenderSchedulerTests.swift`

The `RenderScheduler` actor serializes `NSGraphicsContext.current` access. Test:
1. Concurrent renders complete without race conditions
2. Cancellation is respected
3. Task isolation is maintained

```swift
@Suite(.serialized) struct RenderSchedulerTests {
    @Test func concurrentRendersComplete() async throws {
        let scheduler = RenderScheduler()
        await withTaskGroup(of: Int.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    let result = await scheduler.render {
                        // Create a CGContext and draw
                        return 1
                    }
                    return result ?? 0
                }
            }
            // All tasks should complete
        }
    }

    @Test func cancellationIsRespected() async {
        // ...
    }
}
```

---

### 5.2 CG-2: Add ExportManager tests

**New file:** `CollageMakerTests/ExportManagerTests.swift`

Test:
1. Export with empty panels returns nil/cancelled
2. Export with valid config produces result
3. Cancellation during export is respected
4. Error handling propagates correctly

```swift
@MainActor
@Suite struct ExportManagerTests {
    @Test func exportWithEmptyPanelsReturnsCancelled() async {
        let manager = ExportManager(assembler: TrackingAssembler())
        let result = await manager.export(
            config: makeAssemblyConfig(),
            cgImages: [],
            backgroundImage: nil,
            quality: 0.9
        )
        #expect(result == .cancelled)
    }
    // ...
}
```

---

### 5.3 CG-3: Add ImageLibraryManager tests

**New file:** `CollageMakerTests/ImageLibraryManagerTests.swift`

Test:
1. `moveImages` with custom order produces correct mapping
2. `buildMoveMapping` edge cases (move to beginning, end, no-op)
3. `clearAll` resets state

```swift
@MainActor
@Suite struct ImageLibraryManagerTests {
    @Test func moveImagesUpdatesCustomOrder() {
        let manager = ImageLibraryManager()
        manager.images = [
            createTestImageItem(filename: "a.jpg"),
            createTestImageItem(filename: "b.jpg"),
            createTestImageItem(filename: "c.jpg"),
        ]
        manager.customImageOrder = [0, 1, 2]
        manager.moveImages(from: IndexSet([0]), to: 2)
        #expect(manager.customImageOrder == [1, 2, 0])
    }
    // ...
}
```

---

### 5.4 Mock consolidation

**Current mocks:**
| Mock | File | Purpose |
|------|------|---------|
| `TrackingAssembler` | `TestHelpers.swift:49` | Captures call data |
| `MockAssembler` | `CollageViewModelTests.swift:29` | Returns configurable data |
| `TestPreviewAssembler` | `PreviewManagerTests.swift:7` | Simple stubs |
| `GenerationControlledAssembler` | `PreviewManagerTests.swift:300` | Configurable delay |

**Approach:** Consolidate into `TestHelpers.swift` as a single configurable mock:

```swift
final class TestAssembler: CollageAssembly {
    var trackCalls: Bool = false
    var assembleData: Data? = Data()
    var assemblePreviewImage: NSImage?
    var previewDelayMs: UInt64 = 0
    var shouldThrow = false

    // Call counters (only incremented when trackCalls = true)
    var assembleCalls = 0
    var previewCalls = 0
    var renderPanelCalls = 0
    var renderBackgroundCalls = 0
    var titleRenderCalls = 0

    // Last call data
    var lastAssembleConfig: AssemblyConfig?
    // ...

    // Implement all protocol methods
}
```

Then update each test file to use `TestAssembler` with appropriate configuration.

---

## Execution Order & Estimated Effort

| Order | Item | Est. Time | Risk |
|-------|------|-----------|------|
| 1 | 1.1 C-2 doc comment | 2 min | None |
| 2 | 1.2 S-2 double-init | 2 min | None |
| 3 | 1.3 W-10 force cast | 2 min | None |
| 4 | 1.4 C-1 isProcessing race | 30 min | Low |
| 5 | 2.1 W-5 property helper | 1 hr | Medium |
| 6 | 2.2 W-2 ExportManager DIP | 45 min | Medium |
| 7 | 2.3 W-8 cancelAllTasks | 15 min | Low |
| 8 | 2.4 W-9 CTAttributedStringBuilder | 45 min | Medium |
| 9 | 2.5 W-7 BackgroundConfig CGColor | 20 min | Low |
| 10 | 2.6 W-3 AssemblyConfig init | 20 min | Low |
| 11 | 3.1 S-1 GestureCoordinator | 30 min | Medium |
| 12 | 3.2 W-6 View logic extraction | 1-2 hr | High |
| 13 | 4.1-4.16 Polish items | ~4 hr total | Low each |
| 14 | 5.1-5.4 Tests | ~2 hr | Low |

**Total: ~12-14 hours**

## Verification

After each phase, run:
```bash
bash script/build_and_run.sh --verify
```

After Phase 5, run full test suite:
```bash
xcodebuild test -project CollageMaker/CollageMaker.xcodeproj -scheme CollageMaker -destination 'platform=macOS,arch=arm64'
```
