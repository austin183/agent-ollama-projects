# Architectural Review Fixes — Implementation Plan

**Review doc:** `_agent_docs/reviews/2026-05-29-full-architectural-review.md`
**Date:** 2026-05-29
**Status:** Pending

---

## 16 Issues to Address (1 critical, 6 moderate, 9 minor)

Execution order: Phase 1 → Phase 2 → Phase 3, build + test verify after each phase.

---

### Phase 1 — Quick Fixes (6 issues, self-contained, lowest risk)

#### 1.1 — mi8: Remove dead code in CollageViewModel

**File:** `CollageMaker/ViewModel/CollageViewModel.swift:429`

Delete the no-op expression:
```swift
_ = images.map { $0.id }
```

---

#### 1.2 — mi7: Remove @Observable from CropManager

**File:** `CollageMaker/ViewModel/CropManager.swift:7`

Remove the `@Observable` macro. `CollageViewModel` uses a version counter (`cropMapVersion`) to drive observation, not the macro. The macro is dead weight.

---

#### 1.3 — mi2: Unify perfLogger subsystem

**File:** `CollageMaker/Services/SaliencyAnalyzer.swift:12`

Change:
```swift
subsystem: Bundle.main.bundleIdentifier!
```
to:
```swift
subsystem: "austin183.indie.CollageMaker"
```

---

#### 1.4 — M6: Guard against zero dimensions in FitMath

**File:** `CollageMaker/Services/FitMath.swift`

Add guard clauses at the top of `fit()` and `sourceRect()`:
```swift
guard sourceSize.height > 0, containerSize.height > 0 else {
    return .zero
}
```

Update `FitMathTests` with zero-dimension test cases.

---

#### 1.5 — mi1: Remove NSColorWell guard in SettingsView

**File:** `CollageMaker/Views/SettingsView.swift:25-28` (`UserDefaultsColorView.updateNSView`)

Change:
```swift
func updateNSView(_ well: NSColorWell, context: Context) {
    if well.color != color {
        well.color = color
    }
}
```
to:
```swift
func updateNSView(_ well: NSColorWell, context: Context) {
    well.color = color
}
```

`NSColor ==` compares `CGColor` values which differ across color spaces. The guard can prevent the color well from updating when the color is semantically the same but in a different color space. (ExportPanel's `NSColorPickerView` is already correct — no guard.)

---

#### 1.6 — mi5: Simplify imageOrder force-unwrap in LayoutGenerator

**File:** `CollageMaker/Services/LayoutGenerator.swift`

Replace the nil-check-then-force-unwrap pattern (7 occurrences) with optional chaining:

Before:
```swift
imageOrder != nil ? imageOrder![i] : i % numImages
```
After:
```swift
imageOrder?[i] ?? i % numImages
```

Affected lines: 54, 89, 99, 116, 134, 162, 173.

---

### Phase 2 — Moderate Refactors (6 issues)

#### 2.1 — mi4: Deduplicate CollageAssembler rendering

**File:** `CollageMaker/Services/CollageAssembler.swift:67-156`

`assembleWithCGImages` and `assemblePreviewWithCGImages` share ~80% identical code. Extract:

```swift
private func renderIntoContext(
    config: AssemblyConfig,
    cgImages: [CGImage],
    backgroundImage: NSImage?,
    targetSize: CGSize
) -> NSBitmapImageRep?
```

Then have each method only handle the final encoding step (JPEG Data vs NSImage).

---

#### 2.2 — mi6: Split CollageAssembly protocol (ISP)

**File:** `CollageMaker/Services/CollageAssembler.swift:11-44`

Split the 5-method `CollageAssembly` protocol into focused sub-protocols:

```swift
protocol CollageRenderer {
    func assembleWithCGImages(...) -> Data?
    func assemblePreviewWithCGImages(...) -> NSImage?
}

protocol PanelRenderer {
    func renderPanel(...) -> NSImage?
}

protocol BackgroundRenderer {
    func renderBackground(...) -> NSImage?
}

protocol TitleRenderer {
    func renderTitle(...) -> NSImage?
}
```

`CollageAssembler` conforms to all four. Update tests and callers to depend on the specific protocol they need.

---

#### 2.3 — mi3: Cache TitleMetrics in ViewModel

**File:** `CollageMaker/Services/TitleMetrics.swift`, `CollageMaker/ViewModel/CollageViewModel.swift`

`TitleMetrics.boundingBox` and `minNaturalWidth` are computed properties that call `boundingRect` on every access. During title drag at 60Hz, these are recomputed every frame.

**Approach:**
- Add a cached `titleMetrics: TitleMetrics?` stored property in `CollageViewModel`
- Invalidate (set to `nil`) in the `didSet` of `titleAttrString` and `titleStyle`
- Add a computed property that lazily materializes the cache
- Update `CollageEditorView.titleCanvasFrame` to use the cached value from the VM

---

#### 2.4 — mi9: Replace NSKeyedArchiver with secure color encoding

**Files:** `CollageMaker/Models/TitleStyle.swift`, `CollageMaker/Views/SettingsView.swift`

Replace `NSKeyedArchiver` with `requiringSecureCoding: false` with manual RGBA hex encoding for `NSColor`.

**New utility** (can live in `LoggingExtensions.swift` or a new `ColorCoding.swift`):
```swift
extension NSColor {
    var rgbaHex: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#00000000" }
        return String(format: "#%02lX%02lX%02lX%02lX",
                      Int(rgb.redComponent * 255),
                      Int(rgb.greenComponent * 255),
                      Int(rgb.blueComponent * 255),
                      Int(rgb.alphaComponent * 255))
    }

    convenience init?(rgbaHex: String) {
        // Parse hex string, return nil on failure
    }
}
```

Update `TitleStyle.encode(to:)` / `init(from:)` and `UserDefaultsColorView` to use the hex encoding.

---

#### 2.5 — M1: Collapse scroll pan into CropManager

**Files:** `CollageMaker/ViewModel/CollageViewModel.swift:747-798`, `CollageMaker/ViewModel/CropManager.swift`, `CollageMaker/Services/ScrollPanManager.swift`

The scroll pan flow in `scrollPanDelta` directly accesses `cropManager`, `panels`, `images`, `panelAssignments` from the view model. The `scheduleScrollPanCommit` timer re-enters crop manager state management.

**Approach:**
- Add `ScrollPanManager` as a dependency of `CropManager` (or fold the accumulator logic into `CropManager`)
- Give `CropManager` a self-contained scroll pan interface:
  ```swift
  func beginScrollPan(panelId: UUID, sensitivity: CGFloat)
  func scrollPanDelta(_ delta: CGSize)
  func endScrollPan()
  ```
- The `CropManager` handles the accumulator internally, applies pan to all panels, and commits on timeout
- `CollageViewModel` becomes a thin wrapper that delegates to `CropManager` and triggers preview updates

---

#### 2.6 — M5: LayoutGenerator strategy pattern

**File:** `CollageMaker/Services/LayoutGenerator.swift`

Adding a new layout style requires modifying the `generate` method's switch statement (OCP violation).

**Approach:**
```swift
protocol LayoutStrategy {
    func generate(panels: Int, canvasSize: CGSize, gutter: CGFloat, imageOrder: [Int]?) -> [CGRect]
}
```

- Create `UniformLayoutStrategy`, `HeroLayoutStrategy`, `MosaicLayoutStrategy` conforming to the protocol
- `LayoutStyle` provides a static `makeStrategy() -> LayoutStrategy` factory
- `LayoutGenerator.generate` becomes a thin dispatcher:
  ```swift
  static func generate(...) -> [CGRect] {
      style.makeStrategy().generate(...)
  }
  ```
- New layouts can be added by adding a new `LayoutStyle` case + strategy implementation without touching `LayoutGenerator`

---

### Phase 3 — Major Restructuring (4 issues)

#### 3.1 — C1: Extract ExportManager from CollageViewModel

**File:** `CollageMaker/ViewModel/CollageViewModel.swift`

Export `exportCollage()` owns save panel presentation, assembly orchestration, file I/O, `isExporting` state, and `exportSuccessMessage`.

**New file:** `CollageMaker/ViewModel/ExportManager.swift`

```swift
@MainActor
@Observable
final class ExportManager {
    var isExporting: Bool = false
    var successMessage: String? = nil
    let assembler: any CollageAssembly

    func export(viewModel: CollageViewModel) async
    func dismissSuccess()
}
```

**CollageViewModel changes:**
- Remove `isExporting`, `exportSuccessMessage`, `exportTask`
- Remove `exportCollage()`, `dismissExportSuccess()`
- Add `let exportManager = ExportManager(assembler: assembler)`
- Expose `exportManager.isExporting` and `exportManager.successMessage` as computed properties for backward compatibility with views
- Wire `.commands` and `ExportPanel` to use the export manager

---

#### 3.2 — C1: Extract ImageLibraryManager from CollageViewModel

**File:** `CollageMaker/ViewModel/CollageViewModel.swift`

Image library operations: `images`, `browseImages`, `addImages`, `removeImage`, `moveImages`, `clearAll`, `buildMoveMapping`.

**New file:** `CollageMaker/ViewModel/ImageLibraryManager.swift`

```swift
@MainActor
@Observable
final class ImageLibraryManager {
    var images: [ImageItem] = []
    var customImageOrder: [Int] = []

    func browseImages() async
    func addImages(_ newItems: [ImageItem])
    func removeImage(at offsets: IndexSet)
    func moveImages(from: IndexSet, to: Int)
    func clearAll()
}
```

**CollageViewModel changes:**
- Remove `images`, `customImageOrder`
- Remove `browseImages`, `addImages`, `removeImage`, `moveImages`, `clearAll`, `buildMoveMapping`
- Add `let imageLibrary = ImageLibraryManager()`
- Expose `imageLibrary.images` and `imageLibrary.customImageOrder` as computed properties
- Wire `ImagePickerGrid` and sidebar to the new manager
- Ensure `regenerateLayout()` is triggered on image changes (via callback or observation)

---

#### 3.3 — M4: Extract GestureCoordinator from CollageEditorView

**File:** `CollageMaker/Views/CollageEditorView.swift`

The editor view manages 8 `@State` variables for gesture tracking (`pinchPanelId`, `dragTitleLocked`, `titleResizeEdge`, `dragSourcePanelId`, `dragTargetPanelId`, `dragCursorLocation`, `dragSourceImageIndex`, `oldTitleStyle`, `dragTitleOffset`). Three `simultaneousGesture` modifiers compete for input.

**New file:** `CollageMaker/Views/GestureCoordinator.swift`

```swift
@MainActor
final class GestureCoordinator {
    var pinchPanelId: UUID?
    var dragTitleLocked: Bool = false
    var titleResizeEdge: TitleResizeEdge = .none
    var dragSourcePanelId: UUID?
    var dragTargetPanelId: UUID?
    var dragCursorLocation: CGPoint?
    var dragSourceImageIndex: Int = 0
    var oldTitleStyle: TitleStyle?
    var dragTitleOffset: CGPoint = .zero
}
```

**CollageEditorView changes:**
- Replace 8 `@State` vars with `@StateObject private var gestureCoordinator = GestureCoordinator()`
- Update all references from `$pinchPanelId` etc. to `$gestureCoordinator.pinchPanelId` etc.
- Consider extracting the gesture-modifier-heavy ZStack into a separate `@ViewBuilder` function for readability

---

#### 3.4 — M2: Document Settings defaults semantics

**File:** `CollageMaker/Views/SettingsView.swift`

Add a doc comment at the top of `SettingsView` clarifying that settings store defaults for new sessions only. The active `CollageViewModel` is not affected by settings changes.

```swift
/// macOS Settings scene.
/// Values stored here serve as defaults for NEW collage sessions.
/// Changes do NOT affect the currently active collage — the active
/// CollageViewModel owns its own independent state.
struct SettingsView: View {
```

---

## Verification Checklist

After each phase:

```bash
# Build
bash script/build_and_run.sh --verify

# Unit tests
xcodebuild test -project CollageMaker/CollageMaker.xcodeproj -scheme CollageMaker \
    -destination 'platform=macOS,arch=arm64' -only-testing:CollageMakerTests
```

## Deferred (out of scope)

- **M3: ImageItem memory retention** — Defer until memory pressure is observed with real 20MP images. Potential future work: lazy `cgImage`, file URL storage, aggressive thumbnail downsampling.
