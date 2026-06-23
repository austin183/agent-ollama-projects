# CollageMaker — Review Fixes Plan

**Date:** 2026-06-23
**Reviews Addressed:**
- `_agent_docs/reviews/2026-06-22-review-marcos.md` (Marcos — architectural)
- `_agent_docs/reviews/2026-06-22-review-victoria.md` (Victoria — architecture & implementation)

---

## Summary

| Phase | Items | Risk | Est. Lines |
|-------|-------|------|-----------|
| 1 | C2, C4, R15, R17 | Very Low | ~20 |
| 2 | C0, C1 | Low | ~30 |
| 3 | C3, R18, R14, R5, R13 | Low-Medium | ~80 |
| 4 | R4, R6, R3, R1/R12, Victoria, R10 | Medium | ~300+ |

**C5 (`cropMap` observation)** — False positive. `PanelCropEditor` already uses `getCropVersion(for:)` with `.onChange` for change detection. No fix needed.
**C6 (`DropPreviewView`)** — False positive. `GestureCoordinator` is `@Observable`, passed via `@State` from parent. SwiftUI 2.0+ tracks `@Observable` references through plain `let` properties. No fix needed.

---

## Phase 1: Quick Bug Fixes

### 1. C2 — Fix `BackgroundRenderer.renderBackground` to use `previewSize`

**File:** `Services/BackgroundRenderer.swift:58-92`
**Bug:** The `previewSize: CGSize` parameter is accepted but never used. The method creates a context at `canvasSize`, draws at `canvasSize`, and returns an `NSImage` at `canvasSize`. Every background preview renders at full canvas resolution.

**Fix:** Create the bitmap context at `previewSize`, then scale the context so drawing at `canvasSize` coordinates produces the correct scaled output. Mirror the pattern in `CollageAssembler.renderPreviewIntoContext`.

```swift
// Before: context at canvasSize, no scaling
guard let context = createContext(size: canvasSize) else { return nil }

// After: context at previewSize, scaled to canvasSize coordinates
guard let context = createContext(size: previewSize) else { return nil }
context.scaleBy(x: previewSize.width / canvasSize.width,
                y: previewSize.height / canvasSize.height)
// ... rest of drawing at canvasSize coordinates stays the same
```

Return `NSImage(cgImage: cgImage, size: previewSize)`.

**Verification:** Build + run. Background previews should render at the smaller preview size.

---

### 2. C4 — Add `deinit` to `Debouncer`

**File:** `ViewModel/Debouncer.swift`
**Bug:** `Debouncer` stores `Task<Void, Never>` instances but has no `deinit`. When `CollageViewModel` is deallocated, all pending debounce tasks continue running with dangling captures.

**Fix:** Add `deinit { cancelAll() }`.

```swift
deinit {
    cancelAll()
}
```

**Verification:** Build passes.

---

### 3. R15 — Add `@MainActor` to `TitleTextData.extract(from:)`

**File:** `Services/TitleRendererCT.swift:22`
**Bug:** The doc comment says "Must be called on the main actor" but there is no compiler-enforced isolation. The method accesses `NSFont`, which is `@MainActor`-only.

**Fix:** Add `@MainActor` to the method signature:
```swift
@MainActor
static func extract(from attrString: NSAttributedString) -> TitleTextData {
```

**Verification:** Build passes, no new concurrency warnings.

---

### 4. R17 — Convert `exportManager` IUO to non-optional `let`

**File:** `ViewModel/CollageViewModel.swift:88`
**Bug:** `var exportManager: ExportManager!` is an implicitly unwrapped optional — unnecessary crash risk.

**Fix:** Change to `private let exportManager: ExportManager`, initialized in `init` at line 429 (already initialized, just make it `let` and non-optional).

**Changes:**
- Line 88: `var exportManager: ExportManager!` → `private let exportManager: ExportManager`
- Line 429: `self.exportManager = ExportManager(...)` stays the same

**Verification:** Build passes, all tests pass.

---

## Phase 2: Data Correctness

### 5. C0 — Fix `SaliencyAnalyzer.analyzeAll` index mismatch

**File:** `Services/SaliencyAnalyzer.swift:117-143`
**Bug:** When individual image analysis fails, the error is logged but the result is silently omitted. The caller (`ImageCoordinator.analyzeSaliency` line 169) enumerates the shorter results array and assigns results to wrong indices, silently corrupting the saliency-to-image mapping.

**Example:** If image at index 3 fails, the 8 results that follow are assigned to indices 0-7 instead of 0-2 and 4-9.

**Fix:** Return a fallback result for failed indices instead of dropping them. Use the same fallback pattern already used in `analyze()` for empty-points images (line 80-86):

```swift
case .failure(let error):
    logger.error("Saliency analysis failed for image at index \(index): \(error.localizedDescription, privacy: .public)")
    let img = cgImages[index]
    let fallback = SaliencyResult(
        center: CGPoint(x: CGFloat(img.width) / 2, y: CGFloat(img.height) / 2),
        radius: min(CGFloat(img.width), CGFloat(img.height)) / 3,
        confidence: 0.5
    )
    results[index] = fallback
```

**Changes:** ~8 lines in `analyzeAll`.

**Verification:** Add a test with a mock analyzer that fails for one image, verifying that the returned array has the same count as the input, and that the failed index gets a fallback result.

---

### 6. C1 — Fix `CropInfo` Codable to preserve `.path` data

**File:** `Models/ImagePanel.swift:53-77`, `Models/PanelGeometry.swift`
**Bug:** `CropInfo.encode` only persists `destination.boundingRect`. When deserializing a `.path` geometry, the original `CGPath` is replaced with a plain rectangle. Collages using diagonal slices or hexagonal layouts will silently degrade to rectangular panels after persistence.

**Analysis:** All `.path` geometries in the codebase are simple closed polygons:
- Diagonal slices → parallelograms (4 vertices, `moveTo` + 3x `addLineTo` + `closeSubpath`)
- Hexagonal → hexagons (6 vertices, `moveTo` + 5x `addLineTo` + `closeSubpath`)

The existing `PanelGeometry.extractPathPoints` extracts all vertices faithfully.

**Fix:** Add a `destinationPathVertices` coding key. On encode, extract and serialize `[CGPoint]` for `.path` geometries. On decode, reconstruct the `CGPath` from vertices.

**In `ImagePanel.swift`:**
```swift
enum CodingKeys: String, CodingKey {
    case panelId, sourceRect, destinationType, destinationRect, destinationPathVertices
}

func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(panelId, forKey: .panelId)
    try container.encode(sourceRect, forKey: .sourceRect)
    switch destination {
    case .rect:
        try container.encode("rect" as String, forKey: .destinationType)
        try container.encode(destination.boundingRect, forKey: .destinationRect)
    case .path:
        try container.encode("path" as String, forKey: .destinationType)
        try container.encode(destination.boundingRect, forKey: .destinationRect)
        let vertices = PanelGeometry.extractPathPoints(
            (destination as! PanelGeometry.path).cgPath  // or via helper
        )
        try container.encode(vertices, forKey: .destinationPathVertices)
    }
}
```

Need to expose `cgPath` from `PanelGeometry` — add a computed property or helper:
```swift
// In PanelGeometry.swift
var pathVertices: [CGPoint]? {
    switch self {
    case .rect: return nil
    case .path(let cgPath, _): return PanelGeometry.extractPathPoints(cgPath)
    }
}
```

**In decode:**
```swift
if destType == "path" {
    let vertices = try container.decodeIfPresent([CGPoint].self, forKey: .destinationPathVertices)
    if let vertices, vertices.count >= 3 {
        destination = PanelGeometry.path(fromVertices: vertices, boundingRect: destRect)
    } else {
        // Fallback for old serialized data that lacks vertex data
        destination = .path(cgPath: CGPath(rect: destRect, transform: nil), boundingRect: destRect)
    }
}
```

**In `PanelGeometry.swift`:** Add reconstruction helper:
```swift
static func path(fromVertices vertices: [CGPoint], boundingRect: CGRect) -> PanelGeometry {
    let mutablePath = CGMutablePath()
    mutablePath.move(to: vertices[0])
    for i in 1..<vertices.count {
        mutablePath.addLine(to: vertices[i])
    }
    mutablePath.closeSubpath()
    return .path(cgPath: mutablePath, boundingRect: boundingRect)
}
```

**Verification:** Add Codable round-trip tests for diagonal slice (4-vertex parallelogram) and hexagonal (6-vertex) geometries. Verify vertex positions are preserved within floating-point tolerance.

---

## Phase 3: Performance & Architecture

### 7. C3 — Defer background/mask image loading off main thread

**Files:** `Services/UserDefaultsPersistence.swift:251-273`, `ViewModel/CollageViewModel.swift:446-468`
**Bug:** `loadBackgroundImage()` and `loadDoubleExposureMaskImage()` synchronously read image data from disk on the main thread during `CollageViewModel.init()`. For large background images, this creates a visible jank spike on app launch.

**Approach (standalone, easy to revert):**

**Step 1 — `UserDefaultsPersistence.swift`:** Simplify `loadBackgroundImage()` and `loadDoubleExposureMaskImage()` to return only the path, not the image:

```swift
private func loadBackgroundImage() -> (image: NSImage?, path: String?) {
    guard let path = defaults.string(forKey: Keys.backgroundImagePath),
          FileManager.default.fileExists(atPath: path) else {
        return (nil, nil)
    }
    return (nil, path)  // path only, no image loading
}

private func loadDoubleExposureMaskImage() -> (image: NSImage?, path: String?) {
    guard let path = defaults.string(forKey: Keys.doubleExposureMaskImagePath),
          FileManager.default.fileExists(atPath: path) else {
        return (nil, nil)
    }
    return (nil, path)  // path only, no image loading
}
```

**Step 2 — `CollageViewModel.init`:** After `isInitializing = false`, spawn async tasks to load images:

```swift
// At the end of init, after isInitializing = false:
if let bgPath = backgroundImagePath {
    Task { [bgPath] in
        guard let url = URL(string: bgPath),
              let data = try? await Data(contentsOf: URL(fileURLWithPath: bgPath)),
              let image = NSImage(data: data) else { return }
        await MainActor.run {
            self.backgroundManager.backgroundImage = image
            self.updatePreview()
        }
    }
}

if let maskPath = layoutManager.doubleExposureMaskImagePath {
    Task { [maskPath] in
        guard let data = try? await Data(contentsOf: URL(fileURLWithPath: maskPath)),
              let image = NSImage(data: data) else { return }
        await MainActor.run {
            self.layoutManager.doubleExposureMaskImage = image
        }
    }
}
```

**Changes:** ~10 lines in `UserDefaultsPersistence`, ~20 lines in `CollageViewModel.init`.

**Verification:** Build + run. Background image should load shortly after launch without blocking the main thread.

---

### 8. R18 — Add undo registration to `customImageOrder` setter

**File:** `ViewModel/CollageViewModel.swift:91-97`
**Bug:** Unlike other setters, changes to `customImageOrder` are not undoable.

**Fix:** Add undo registration matching the pattern used by other setters:

```swift
var customImageOrder: [Int] {
    get { imageLibrary.customImageOrder }
    set {
        guard !isInitializing else { imageLibrary.customImageOrder = newValue; return }
        let old = imageLibrary.customImageOrder
        registerUndo(oldValue: old, actionName: "Reorder Images") {
            $0.imageLibrary.customImageOrder = old
        }
        imageLibrary.customImageOrder = newValue
    }
}
```

**Changes:** ~8 lines.

**Verification:** Build passes, manual test of undo after reorder.

---

### 9. R14 — Replace `awaitPendingTasks()` sleep with task snapshot

**File:** `Services/PreviewManager.swift:236-238`
**Bug:** A 300ms `Task.sleep` is a fragile test synchronization mechanism. It may be insufficient on slow hardware or excessive on fast hardware.

**Fix:** Snapshot all current task handles and `await` their completion:

```swift
func awaitPendingTasks() async {
    let snapshot: [Task<Void, Never>] = [
        previewTask,
        previewDebounceTask,
        backgroundTask,
        overlayTask,
        titleTask,
    ].compactMap { $0 } + panelPreviewTasks.values

    for task in snapshot {
        await task.value
    }
}
```

This is deterministic — it terminates immediately when all rendering is done. Since each `updatePreview` call cancels the previous task and creates a new one, the snapshot approach correctly awaits the most recently spawned tasks (the pattern used in tests is always: trigger action → await → assert).

**Changes:** ~10 lines.

**Verification:** All 23 call sites in `CollageViewModelTests` should pass.

---

### 10. R5 — Fix `TitleStyle.default` NSColor init

**File:** `Models/TitleStyle.swift:44-54`
**Bug:** `NSColor` is `@MainActor`-only. A `static let` property initializer runs at module load time, which may not be on the main actor.

**Fix:** Convert to a computed factory method:

```swift
static func defaultStyle() -> TitleStyle {
    TitleStyle(
        fontFamily: "",
        fontSize: 48,
        fontColor: NSColor.white.withAlphaComponent(0.8),
        backgroundColor: NSColor.black.withAlphaComponent(0.4),
        alignment: .center,
        showBackground: true,
        positionX: 0.5,
        positionY: 0.88,
        width: 0
    )
}
```

Update all call sites from `TitleStyle.default` to `TitleStyle.defaultStyle()`.

Also update `init(from:)` which references `TitleStyle.default.positionX`, `.positionY`, `.width`, `.fontColor`, `.backgroundColor` (lines 88-104).

**Changes:** ~10 lines in `TitleStyle.swift` + all call sites.

**Verification:** Build passes.

---

### 11. R13 — Migrate `AttributedStringEditor` to `@Observable`

**File:** `Views/AttributedStringEditor.swift`
**Bug:** Uses legacy `ObservableObject`/`@StateObject`/`@ObservedObject` while the rest of the codebase uses `@Observable`/`@Bindable`.

**Fix:**

1. Replace `StyleableTextViewHolder` (lines 217-226):
```swift
// Before:
class StyleableTextViewHolder: ObservableObject {
    let objectWillChange = PassthroughSubject<StyleableTextViewHolder, Never>()
    var textView: NSTextView? {
        didSet {
            DispatchQueue.main.async {
                self.objectWillChange.send(self)
            }
        }
    }
}

// After:
@Observable
class StyleableTextViewHolder {
    var textView: NSTextView?
}
```

2. Replace `@StateObject` (line 29) with `@State`:
```swift
@State private var textViewHolder = StyleableTextViewHolder()
```

3. Replace `@ObservedObject` (line 231) with plain property:
```swift
var textViewHolder: StyleableTextViewHolder
```

4. Remove the `dispatchSetTextView` call that manually sends `objectWillChange` — `@Observable` handles this automatically when `textView` is assigned in `makeNSView`/`updateNSView`.

**Changes:** ~15 lines.

**Verification:** Build passes, text editing still works.

---

## Phase 4: Larger Refactors

### 12. R4 — Move `TitleTextData` to Models layer

**Files:** `Services/TitleRendererCT.swift` → `Models/TitleTextData.swift`
**Bug:** `TitleTextData` is defined in a Services file but used by `TitleConfig` in Models. This inverts the expected layering.

**Fix:**
1. Create `Models/TitleTextData.swift` with the `TitleTextData` struct and `TitleTextRun` struct
2. Move `static func extract(from:)` to the new file (with `@MainActor` from R15)
3. Remove from `Services/TitleRendererCT.swift`
4. Update imports in files that use `TitleTextData`

**Verification:** Build passes, no import cycle issues.

---

### 13. R6 — Move gesture types out of Models

**File:** `Models/TitleStyle.swift:5-11`
**Bug:** `TitleResizeEdge` and `TitleHitResult` are purely UI interaction types with no business in the Models layer.

**Fix:** Move to `ViewModel/TitleManager.swift` (where `TitleManager` already uses them) or create a small `ViewModel/TitleInteractionTypes.swift`.

**Changes:** Move 7 lines, update imports in `CollageEditorView.swift`, `TitleManager.swift`, etc.

**Verification:** Build passes.

---

### 14. R3 — Add protocols for `DropHandler`, `RenderScheduler`, `PreviewManager`

**`DropHandler`** (`Services/DropHandler.swift`):
- Create `DropHandling` protocol with the `handleDrop` method signature
- Add `DropHandler: DropHandling` conformance
- Update `ContentView` to depend on the protocol

**`RenderScheduler`** (`Services/RenderScheduler.swift`):
- Create `RenderScheduling` protocol
- Add `RenderScheduler: RenderScheduling` conformance
- Update `CollageAssembler` to depend on the protocol

**`PreviewManager`** (`Services/PreviewManager.swift`):
- Create `PreviewManagement` protocol with public method signatures
- Add `PreviewManager: PreviewManagement` conformance
- Update `ImageCoordinator` to depend on the protocol

**Changes:** ~60 lines of protocol definitions + call site updates.

**Verification:** Build passes, tests can inject mocks.

---

### 15. R1/R12 — Extract gesture logic from `CollageEditorView`

**Target:** Title drag gesture (lines 82-148, ~65 lines) and panel swap gesture (lines 149-188, ~40 lines).

**Title drag gesture extraction:**

Create `TitleDragGestureBuilder` as a struct that produces a `DragGesture` modifier:

```swift
struct TitleDragGestureBuilder {
    let coordinator: GestureCoordinator
    let viewModel: CollageViewModel
    let titleCanvasFrame: CGRect?
    let previewSize: CGSize

    func build() -> some Gesture {
        DragGesture(minimumDistance: 5)
            .simultaneousWith(MagnificationGesture())
            .onChanged { value in /* delegate to coordinator + VM */ }
            .onEnded { value in /* delegate to coordinator + VM */ }
    }
}
```

The coordinator (`GestureCoordinator`) already holds transient state (`dragTitleLocked`, `titleResizeEdge`, `oldTitleStyle`, `dragTitleOffset`). The extraction moves the inline branching logic (hit testing, resize computation, drag offset tracking) out of the view body closures into methods on the coordinator or a dedicated builder.

**Panel swap gesture extraction:**

Similar pattern — extract the `hitPanel` call, `getEffectiveImageIndex`, and `swapPanelImages` delegation into a builder struct.

**Changes:**
- New file: `Views/EditorGestureBuilders.swift` (~120 lines)
- Refactor `CollageEditorView.swift` to use builders (~100 lines reduction)

**Verification:** Build passes, title drag/resize and panel swap work correctly.

---

### 16. Victoria High — Move coordinate math from Views to Managers

**Scope:** The `hitPanel` logic and gesture coordinate conversions in `CollageEditorView` should move into `TitleManager` and `LayoutManager`.

**Current state:** The view body contains inline `hitPanel(at:panelFrames:panelGeometries:previewSize:)` (line 239-247) that wraps `CoordinateConverter.hitTestPanel`. Gesture closures perform coordinate conversions between preview space and canvas space.

**Fix:**
- Add `hitPanel(at:previewSize:) -> UUID?` to `LayoutManager` that takes raw preview coordinates and returns the hit panel ID
- Add `convertGestureLocation(toCanvas:) -> CGPoint` helpers to relevant managers
- The view should only report raw gesture events (location, magnification)

**Verification:** Build passes, gestures work identically.

---

### 17. R10 — `ColorPair` helper for `BackgroundConfig`

**File:** `Models/AssemblyConfig.swift:28-57`
**Issue:** `BackgroundConfig` stores both `NSColor` and `CGColor` representations of the same values (6 properties for 3 logical colors).

**Fix:** Create a `ColorPair: Sendable` helper:

```swift
struct ColorPair: Sendable {
    let nsColor: NSColor
    let cgColor: CGColor

    init(_ nsColor: NSColor) {
        self.nsColor = nsColor
        self.cgColor = nsColor.cgColor
    }
}
```

Update `BackgroundConfig` to use `ColorPair` for `color`, `gradientStartColor`, `gradientEndColor`.

**Changes:** New type (~10 lines), update `BackgroundConfig` and all consumers (~30 lines).

**Verification:** Build passes.

---

## Execution Order & Dependencies

```
Phase 1 (independent, any order):
  1. C2  → BackgroundRenderer
  2. C4  → Debouncer
  3. R15 → TitleRendererCT
  4. R17 → CollageViewModel

Phase 2 (independent):
  5. C0  → SaliencyAnalyzer
  6. C1  → ImagePanel + PanelGeometry

Phase 3 (mostly independent):
  7. C3  → UserDefaultsPersistence + CollageViewModel (depends on nothing)
  8. R18 → CollageViewModel
  9. R14 → PreviewManager
  10. R5 → TitleStyle (+ all call sites)
  11. R13 → AttributedStringEditor

Phase 4 (some dependencies):
  12. R4 → TitleTextData (depends on R15 for @MainActor)
  13. R6 → TitleStyle gesture types
  14. R3 → Protocol extraction
  15. R1/R12 → Gesture extraction from CollageEditorView
  16. Victoria → Coordinate math extraction
  17. R10 → ColorPair helper
```

## Rollback Strategy

Each phase is independently revertible:
- **Phase 1:** Each fix is a self-contained change to a single file.
- **Phase 2:** Each fix touches a small, well-defined scope.
- **Phase 3:** C3 is explicitly designed as a standalone change — if the async image loading causes issues, reverting `UserDefaultsPersistence.swift` and `CollageViewModel.init` restores the original behavior.
- **Phase 4:** Each refactor is a structural change that should be committed separately.

## Testing After Each Phase

After completing each phase:
1. `xcodebuild` build succeeds
2. Run existing tests: `xcodebuild test -project CollageMaker/CollageMaker.xcodeproj -scheme CollageMaker -destination 'platform=macOS,arch=arm64' -only-testing:CollageMakerTests`
3. Manual smoke test: launch app, verify preview renders, gestures work
