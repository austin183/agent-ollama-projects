# Round-99 Prep — Non-Rectangular Panel Geometry Refactoring Plan

**Source review:** `_agent_docs/reviews/2026-06-05-round99-prep-review.md`
**Target change:** `_agent_docs/change-requests/round-99.md` — Double Exposure, Diagonal Slices, Hexagonal layouts
**Scope:** 3 Critical, 6 Warning, 5 Suggestion findings from review
**Status:** Not started

---

## Phase 1: Data Model — PanelGeometry Abstraction (2 files, 1 new)

**Goal:** Introduce `PanelGeometry` enum to support both rectangular and path-based panel shapes. Maintain backward compatibility via computed property.

### 1.1 Create `Models/PanelGeometry.swift`

**New file.** Define the geometry abstraction:

```swift
import CoreGraphics
import Foundation

/// Represents the shape of a panel — either a simple rectangle or an arbitrary CGPath.
enum PanelGeometry: Codable, Hashable {
    case rect(CGRect)
    case path(boundingRect: CGRect, elementCount: Int)

    var boundingRect: CGRect {
        switch self {
        case .rect(let r): return r
        case .path(let r, _): return r
        }
    }
}
```

**Design decision:** `CGPath` does NOT conform to `Codable` or `Hashable`. Storing `CGPath` directly in the enum would prevent `PanelGeometry` from conforming to these protocols, which would break `ImagePanel: Equatable` and any persistence. Instead, store the bounding rect + element count for serialization, and reconstruct the `CGPath` on demand from layout context.

**Alternative (simpler for Phase 1):** Store the `CGPath` directly but use `@unchecked Sendable` and skip `Codable`/`Hashable` for the `.path` case. Defer persistence of non-rectangular layouts — regenerate on load.

```swift
import CoreGraphics
import Foundation

enum PanelGeometry: @unchecked Sendable {
    case rect(CGRect)
    case path(cgPath: CGPath, boundingRect: CGRect)

    var boundingRect: CGRect {
        switch self {
        case .rect(let r): return r
        case .path(_, let r): return r
        }
    }

    var cgPath: CGPath? {
        switch self {
        case .rect(let r): return r.cgPath
        case .path(let p, _): return p
        }
    }
}
```

**Recommendation:** Use the second (simpler) form. `CGPath` is reference-type and not `Sendable`, but we create all paths on `@MainActor` and only read them on background threads (CoreGraphics drawing). Document with `@unchecked Sendable` justification.

### 1.2 Update `Models/ImagePanel.swift`

**Line 7 — Change `frame` to `geometry`:**

```swift
// FROM:
struct ImagePanel: Identifiable, Equatable {
    let id: UUID
    let imageIndex: Int
    let frame: CGRect

    init(id: UUID = UUID(), imageIndex: Int, frame: CGRect) {
        self.id = id
        self.imageIndex = imageIndex
        self.frame = frame
    }
```

```swift
// TO:
struct ImagePanel: Identifiable, Equatable {
    let id: UUID
    let imageIndex: Int
    let geometry: PanelGeometry

    /// Backward-compatible accessor — returns bounding rect of geometry.
    var frame: CGRect { geometry.boundingRect }

    init(id: UUID = UUID(), imageIndex: Int, frame: CGRect) {
        self.id = id
        self.imageIndex = imageIndex
        self.geometry = .rect(frame)
    }

    init(id: UUID = UUID(), imageIndex: Int, geometry: PanelGeometry) {
        self.id = id
        self.imageIndex = imageIndex
        self.geometry = geometry
    }
}
```

**Key:** Keep the `init(imageIndex:frame:)` constructor so existing code compiles unchanged. The computed `frame` property provides backward compatibility.

**Line 20-30 — Update `CropInfo`:**

```swift
// FROM:
struct CropInfo: Codable, Equatable {
    let panelId: UUID
    let sourceRect: CGRect
    let destinationRect: CGRect

    init(panelId: UUID, sourceRect: CGRect, destinationRect: CGRect) {
        self.panelId = panelId
        self.sourceRect = sourceRect
        self.destinationRect = destinationRect
    }
}
```

```swift
// TO:
struct CropInfo: Codable, Equatable {
    let panelId: UUID
    let sourceRect: CGRect
    let destination: PanelGeometry

    /// Backward-compatible accessor — returns bounding rect of destination.
    var destinationRect: CGRect { destination.boundingRect }

    init(panelId: UUID, sourceRect: CGRect, destinationRect: CGRect) {
        self.panelId = panelId
        self.sourceRect = sourceRect
        self.destination = .rect(destinationRect)
    }

    init(panelId: UUID, sourceRect: CGRect, destination: PanelGeometry) {
        self.panelId = panelId
        self.sourceRect = sourceRect
        self.destination = destination
    }
}
```

**Cascading compile fixes (use `frame` computed property to minimize changes):**

The `frame` and `destinationRect` computed properties mean existing code using `.frame` and `.destinationRect` continues to compile. The only files that need explicit changes are:
- Files that construct `ImagePanel` with a new geometry type (Phase 2)
- Files that need to access the `CGPath` for clipping/hit-testing (Phase 3-5)

### 1.3 Verify build + tests

```bash
xcodebuild -project CollageMaker/CollageMaker.xcodeproj -scheme CollageMaker -destination 'platform=macOS,arch=arm64' build
xcodebuild test -project CollageMaker/CollageMaker.xcodeproj -scheme CollageMaker -destination 'platform=macOS,arch=arm64' -only-testing:CollageMakerTests
```

**Expected:** Zero changes needed in existing code if computed properties are correct. All existing tests pass.

---

## Phase 2: Layout Generation — Add New Style Cases (1 file)

**Goal:** Wire up `LayoutStyle` enum and factory for new styles. Existing strategies continue emitting `.rect` geometry.

### 2.1 Update `Models/LayoutStyle.swift`

**Line 3-6 — Add new cases:**

```swift
// FROM:
enum LayoutStyle: String, CaseIterable, Identifiable, Codable {
    case uniform
    case hero
    case mosaic
```

```swift
// TO:
enum LayoutStyle: String, CaseIterable, Identifiable, Codable {
    case uniform
    case hero
    case mosaic
    case doubleExposure
    case diagonalSlices
    case hexagonal
```

**Line 10-16 — Add titles:**

```swift
        case .uniform: "Uniform"
        case .hero: "Hero"
        case .mosaic: "Mosaic"
        case .doubleExposure: "Double Exposure"
        case .diagonalSlices: "Diagonal Slices"
        case .hexagonal: "Hexagonal"
```

**Line 18-24 — Add icons:**

```swift
        case .uniform: "square.grid.2x2.fill"
        case .hero: "rectangle.stack.fill"
        case .mosaic: "photo.on.rectangle.angled"
        case .doubleExposure: "person.crop.circle.fill"
        case .diagonalSlices: "line.3.horizontal.decrease"
        case .hexagonal: "hexagon.fill"
```

### 2.2 Update `Services/LayoutGenerator.swift`

**Line 195-201 — Add factory cases:**

```swift
// FROM:
    func makeStrategy() -> LayoutStrategy {
        switch self {
        case .uniform: return UniformLayoutStrategy()
        case .hero: return HeroLayoutStrategy()
        case .mosaic: return MosaicLayoutStrategy()
        }
    }
```

```swift
// TO:
    func makeStrategy() -> LayoutStrategy {
        switch self {
        case .uniform: return UniformLayoutStrategy()
        case .hero: return HeroLayoutStrategy()
        case .mosaic: return MosaicLayoutStrategy()
        case .doubleExposure: return DoubleExposureLayoutStrategy()
        case .diagonalSlices: return DiagonalSlicesLayoutStrategy()
        case .hexagonal: return HexagonalLayoutStrategy()
        }
    }
```

### 2.3 Create stub strategies

Add to `Services/LayoutGenerator.swift` after `MosaicLayoutStrategy`:

```swift
struct DoubleExposureLayoutStrategy: LayoutStrategy {
    func generate(numImages: Int, canvasSize: CGSize, gutter: CGFloat, imageOrder: [Int]?, mosaicSeed: UInt64?) -> [ImagePanel] {
        // Reuse uniform grid layout — silhouette mask is a rendering concern, not layout.
        return UniformLayoutStrategy().generate(
            numImages: numImages,
            canvasSize: canvasSize,
            gutter: gutter,
            imageOrder: imageOrder,
            mosaicSeed: mosaicSeed
        )
    }
}

struct DiagonalSlicesLayoutStrategy: LayoutStrategy {
    func generate(numImages: Int, canvasSize: CGSize, gutter: CGFloat, imageOrder: [Int]?, mosaicSeed: UInt64?) -> [ImagePanel] {
        // TODO: Generate parallelogram panels with CGPath clip paths.
        // For now, fall back to uniform grid.
        return UniformLayoutStrategy().generate(
            numImages: numImages,
            canvasSize: canvasSize,
            gutter: gutter,
            imageOrder: imageOrder,
            mosaicSeed: mosaicSeed
        )
    }
}

struct HexagonalLayoutStrategy: LayoutStrategy {
    func generate(numImages: Int, canvasSize: CGSize, gutter: CGFloat, imageOrder: [Int]?, mosaicSeed: UInt64?) -> [ImagePanel] {
        // TODO: Generate hexagonal panels with CGPath clip paths.
        // For now, fall back to uniform grid.
        return UniformLayoutStrategy().generate(
            numImages: numImages,
            canvasSize: canvasSize,
            gutter: gutter,
            imageOrder: imageOrder,
            mosaicSeed: mosaicSeed
        )
    }
}
```

**Rationale:** `DoubleExposure` reuses `UniformLayoutStrategy` — the silhouette mask is applied during rendering, not layout. The other two are stubs that compile and return valid panels, allowing the UI to wire up the new styles before the geometry algorithms are implemented.

### 2.4 Verify build + tests

Same commands as Phase 1.

---

## Phase 3: Rendering — Path-Based Clipping (1 file)

**Goal:** Update `CollageAssembler` to clip to `CGPath` for non-rectangular panels. Add overlay rendering for double exposure.

### 3.1 Update `Services/CollageAssembler.swift` — `drawPanels()`

**Line 299-328 — Add path-based clipping:**

```swift
// FROM (line 314-324):
            let sourceRect = crop.sourceRect
            let destRect = crop.destinationRect

            context.saveGState()
            context.clip(to: destRect)

            if let cropped = cg.cropping(to: sourceRect) {
                context.draw(cropped, in: destRect)
            } else {
                context.draw(cg, in: destRect)
            }

            context.restoreGState()
```

```swift
// TO:
            let sourceRect = crop.sourceRect
            let destRect = crop.destinationRect

            context.saveGState()

            if let clipPath = panel.geometry.cgPath {
                context.addPath(clipPath)
                context.clip()
            } else {
                context.clip(to: destRect)
            }

            if let cropped = cg.cropping(to: sourceRect) {
                context.draw(cropped, in: destRect)
            } else {
                context.draw(cg, in: destRect)
            }

            context.restoreGState()
```

**Note:** The `context.draw(cropped, in: destRect)` call uses the bounding rect as the destination — the clip path handles the shape. This is correct: the image fills the bounding box, then gets clipped to the path.

### 3.2 Update `Services/CollageAssembler.swift` — `renderPanel()`

**Line 342-368 — Same pattern:**

```swift
// FROM (line 351-355):
            let sourceRect = crop.sourceRect
            let destRect = CGRect(origin: .zero, size: panelSize)

            context.saveGState()
            context.clip(to: destRect)
```

```swift
// TO:
            let sourceRect = crop.sourceRect
            let destRect = CGRect(origin: .zero, size: panelSize)

            context.saveGState()
            context.clip(to: destRect)
            // Note: renderPanel is used for the sidebar crop preview, which
            // always renders into a rectangular preview area. Path clipping
            // is not needed here — the preview shows the rectangular crop
            // region of the source image.
```

**Design decision:** `renderPanel()` is called for the sidebar crop preview. The crop preview always shows a rectangular region (the source crop), so path clipping is NOT needed here. The panel shape is only relevant in the main canvas rendering.

### 3.3 Add `OverlayConfig` to `Models/AssemblyConfig.swift`

**After line 57 — New struct:**

```swift
struct OverlayConfig: @unchecked Sendable {
    let maskImage: CGImage
    let opacity: CGFloat
    let blendMode: CGBlendMode

    init(maskImage: CGImage, opacity: CGFloat = 0.5, blendMode: CGBlendMode = .multiply) {
        self.maskImage = maskImage
        self.opacity = opacity
        self.blendMode = blendMode
    }
}
```

**Line 59-64 — Add to AssemblyConfig:**

```swift
// FROM:
struct AssemblyConfig {
    let layout: LayoutConfig
    let title: TitleConfig
    let background: BackgroundConfig
    let canvasSize: CGSize
```

```swift
// TO:
struct AssemblyConfig {
    let layout: LayoutConfig
    let title: TitleConfig
    let background: BackgroundConfig
    let canvasSize: CGSize
    let overlay: OverlayConfig?
```

Update both initializers to accept `overlay: OverlayConfig? = nil`.

### 3.4 Update `Services/CollageAssembler.swift` — Add overlay rendering

**In `renderIntoContext()` after `drawPanels()` (line 135):**

```swift
        drawPanels(
            into: context,
            panels: config.layout.panels,
            cgImages: cgImages,
            crops: config.layout.crops,
            panelAssignments: config.layout.panelAssignments
        )

        // NEW: Draw overlay (e.g., silhouette mask for double exposure)
        if let overlay = config.overlay {
            drawOverlay(into: context, overlay: overlay, canvasSize: config.canvasSize)
        }

        if !config.title.textData.text.isEmpty {
```

**In `renderPreviewIntoContext()` after `drawPanels()` (line 191):**

Same addition.

**New private method:**

```swift
    private func drawOverlay(into context: CGContext, overlay: OverlayConfig, canvasSize: CGSize) {
        context.saveGState()
        context.setBlendMode(overlay.blendMode)
        context.setAlpha(overlay.opacity)
        context.draw(overlay.maskImage, in: CGRect(origin: .zero, size: canvasSize))
        context.restoreGState()
    }
```

### 3.5 Verify build + tests

Same commands. CollageAssemblerTests create `CropInfo` with `destinationRect:` parameter — the backward-compatible initializer should handle this.

---

## Phase 4: Crop Management — Path Hit Testing (1 file)

**Goal:** Update `CropManager.hitTestPanel()` to support path-based containment for non-rectangular panels.

### 4.1 Update `ViewModel/CropManager.swift` — `hitTestPanel()`

**Line 265-270 — Add path containment:**

```swift
// FROM:
    static func hitTestPanel(at location: CGPoint, panelFrames: [UUID: CGRect]) -> UUID? {
        for (id, frame) in panelFrames where frame.contains(location) {
            return id
        }
        return nil
    }
```

```swift
// TO:
    static func hitTestPanel(at location: CGPoint, panelFrames: [UUID: CGRect], panelGeometries: [UUID: PanelGeometry]? = nil) -> UUID? {
        // First pass: fast CGRect check (works for both rect and path panels)
        let candidates = panelFrames.filter { $0.value.contains(location) }
        guard !candidates.isEmpty else { return nil }

        // Second pass: precise path containment for non-rectangular panels
        if let geometries = panelGeometries {
            for (id, _) in candidates {
                if let geometry = geometries[id], case .path(let cgPath, _) = geometry {
                    if cgPath.contains(location) {
                        return id
                    }
                }
            }
            // If we got here, none of the path panels contained the point.
            // Fall through to return first rect panel candidate.
        }

        // Return first candidate (rect panel or fallback)
        return candidates.first?.key
    }
```

**Design decision:** Two-pass hit testing. First pass uses `CGRect.contains()` (O(1)) to find candidates within bounding boxes. Second pass uses `CGPath.contains()` (O(vertices)) only for non-rectangular candidates. This preserves fast hit testing for rectangular layouts while supporting path panels.

### 4.2 Update `Views/CollageEditorView.swift` — Call site

**Line 36-38 — Build geometry map alongside frame map:**

```swift
// FROM:
                let panelFrames = viewModel.panels.reduce(into: [UUID: CGRect]()) { dict, panel in
                    dict[panel.id] = canvasToPreviewFrame(panel.frame, in: geometry.size)
                }
```

```swift
// TO:
                let panelFrames = viewModel.panels.reduce(into: [UUID: CGRect]()) { dict, panel in
                    dict[panel.id] = canvasToPreviewFrame(panel.frame, in: geometry.size)
                }
                let panelGeometries = Dictionary(uniqueKeysWithValues: viewModel.panels.map { ($0.id, $0.geometry) })
```

**Line 321-328 — Pass geometries to hit test:**

```swift
// FROM:
    private func panelAt(location: CGPoint, panelFrames: [UUID: CGRect]) -> UUID? {
        if let id = CropManager.hitTestPanel(at: location, panelFrames: panelFrames),
```

```swift
// TO:
    private func panelAt(location: CGPoint, panelFrames: [UUID: CGRect], panelGeometries: [UUID: PanelGeometry]) -> UUID? {
        if let id = CropManager.hitTestPanel(at: location, panelFrames: panelFrames, panelGeometries: panelGeometries),
```

**Update all call sites of `panelAt()`** (lines 242, 250, 262, 300) to pass `panelGeometries`.

### 4.3 Verify build + tests

Same commands.

---

## Phase 5: SwiftUI Views — Shape-Based Rendering (2 files)

**Goal:** Replace `Rectangle()` with `PanelShape` in `CollageEditorView`. Optionally update `PanelCropEditor`.

### 5.1 Add `PanelShape` to `Views/CollageEditorView.swift`

**Before `PanelHitArea` (line 336):**

```swift
private struct PanelShape: Shape {
    let geometry: PanelGeometry

    func path(in rect: CGRect) -> Path {
        switch geometry {
        case .rect:
            return Path(rect)
        case .path(let cgPath, _):
            return Path(cgPath)
        }
    }
}
```

### 5.2 Update `PanelHitArea`

**Line 342-347:**

```swift
// FROM:
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }
```

```swift
// TO:
    var body: some View {
        PanelShape(geometry: panel.geometry)
            .fill(Color.clear)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }
```

### 5.3 Update `PanelOverlay` selection indicator

**Line 390-396:**

```swift
// FROM:
            if viewModel.selectedPanelId == panel.id, let frame = scaledFrame {
                Rectangle()
                    .fill(Color.clear)
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
```

```swift
// TO:
            if viewModel.selectedPanelId == panel.id, let frame = scaledFrame {
                PanelShape(geometry: panel.geometry)
                    .fill(Color.clear)
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
```

### 5.4 Update drag source/target highlights

**Lines 94-111:**

```swift
// FROM:
                    if let sourceId = gestureCoordinator.dragSourcePanelId,
                       let scaledFrame = panelFrames[sourceId] {
                        Rectangle()
                            .fill(Color.clear)
                            .stroke(Color.cyan, lineWidth: 2.5)
                            .frame(width: scaledFrame.width, height: scaledFrame.height)
                            .position(x: scaledFrame.midX, y: scaledFrame.midY)
                    }

                    if let targetId = gestureCoordinator.dragTargetPanelId,
                       let scaledFrame = panelFrames[targetId],
                       targetId != gestureCoordinator.dragSourcePanelId {
                        Rectangle()
                            .fill(Color.clear)
                            .stroke(Color.green, lineWidth: 2.5)
                            .frame(width: scaledFrame.width, height: scaledFrame.height)
                            .position(x: scaledFrame.midX, y: scaledFrame.midY)
                    }
```

```swift
// TO:
                    if let sourceId = gestureCoordinator.dragSourcePanelId,
                       let scaledFrame = panelFrames[sourceId],
                       let sourcePanel = viewModel.panels.first(where: { $0.id == sourceId }) {
                        PanelShape(geometry: sourcePanel.geometry)
                            .fill(Color.clear)
                            .stroke(Color.cyan, lineWidth: 2.5)
                            .frame(width: scaledFrame.width, height: scaledFrame.height)
                            .position(x: scaledFrame.midX, y: scaledFrame.midY)
                    }

                    if let targetId = gestureCoordinator.dragTargetPanelId,
                       let scaledFrame = panelFrames[targetId],
                       targetId != gestureCoordinator.dragSourcePanelId,
                       let targetPanel = viewModel.panels.first(where: { $0.id == targetId }) {
                        PanelShape(geometry: targetPanel.geometry)
                            .fill(Color.clear)
                            .stroke(Color.green, lineWidth: 2.5)
                            .frame(width: scaledFrame.width, height: scaledFrame.height)
                            .position(x: scaledFrame.midX, y: scaledFrame.midY)
                    }
```

### 5.5 Optional: `PanelCropEditor` shape preview overlay

**Defer to after Phase 6.** The crop editor functions correctly with non-rectangular panels — the source crop is always rectangular. Adding a shape preview overlay is a UX enhancement, not a blocker.

### 5.6 Verify build + tests

Same commands.

---

## Phase 6: Configuration — Style-Specific Properties (2 files)

**Goal:** Wire up style-specific configuration through `CollageViewModel` and `AssemblyConfig`.

### 6.1 Update `ViewModel/CollageViewModel.swift` — Style config properties

**Near `layoutStyle` (line 134) — Add style-specific properties:**

```swift
    // Style-specific configuration
    var doubleExposureMaskImage: NSImage?
    var doubleExposureMaskOpacity: CGFloat = 0.5
    var diagonalSliceAngle: CGFloat = 45.0
    var hexagonalSpacing: CGFloat = 8.0
```

**These properties should be persisted via UserDefaults if the app supports saving/loading collages. Wire up in `didSet` with the existing `debouncedSave()` pattern.**

### 6.2 Update `buildAssemblyConfig()` to include overlay

**Line 776-796:**

```swift
// FROM:
    func buildAssemblyConfig() -> AssemblyConfig {
        let textData = TitleTextData.extract(from: titleAttrString)
        let fontColor = titleStyle.fontColor.cgColor
        let titleBgColor = titleStyle.backgroundColor.cgColor
        return AssemblyConfig(
            panels: panels,
            crops: cropMap,
            panelAssignments: panelAssignments,
            titleTextData: textData,
            titleStyle: titleStyle,
            titleFontColor: fontColor,
            titleBackgroundColor: titleBgColor,
            backgroundColor: backgroundColor,
            backgroundStyle: backgroundStyle,
            gradientStartColor: gradientStartColor,
            gradientEndColor: gradientEndColor,
            gradientAngle: gradientAngle,
            backgroundOpacity: backgroundOpacity,
            canvasSize: SizeConstants.defaultCanvasSize
        )
    }
```

```swift
// TO:
    func buildAssemblyConfig() -> AssemblyConfig {
        let textData = TitleTextData.extract(from: titleAttrString)
        let fontColor = titleStyle.fontColor.cgColor
        let titleBgColor = titleStyle.backgroundColor.cgColor

        let overlay: OverlayConfig? = {
            guard layoutStyle == .doubleExposure,
                  let maskImage = doubleExposureMaskImage,
                  let cgImage = maskImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            return OverlayConfig(
                maskImage: cgImage,
                opacity: doubleExposureMaskOpacity,
                blendMode: .multiply
            )
        }()

        return AssemblyConfig(
            panels: panels,
            crops: cropMap,
            panelAssignments: panelAssignments,
            titleTextData: textData,
            titleStyle: titleStyle,
            titleFontColor: fontColor,
            titleBackgroundColor: titleBgColor,
            backgroundColor: backgroundColor,
            backgroundStyle: backgroundStyle,
            gradientStartColor: gradientStartColor,
            gradientEndColor: gradientEndColor,
            gradientAngle: gradientAngle,
            backgroundOpacity: backgroundOpacity,
            canvasSize: SizeConstants.defaultCanvasSize,
            overlay: overlay
        )
    }
```

### 6.3 Verify build + tests

Same commands.

---

## Verification Checklist

After all phases complete:

- [ ] `xcodebuild build` — zero errors, zero warnings
- [ ] `xcodebuild test` — all existing tests pass
- [ ] Launch app — existing layouts (uniform, hero, mosaic) render identically
- [ ] Select new layout style — UI shows new options in sidebar
- [ ] Double Exposure — renders grid panels with mask overlay
- [ ] Diagonal Slices — stub renders grid panels (geometry TBD)
- [ ] Hexagonal — stub renders grid panels (geometry TBD)
- [ ] Panel selection (tap) — works for all layouts
- [ ] Panel drag-swap — works for all layouts
- [ ] Panel pinch-zoom — works for all layouts
- [ ] Crop editor — works for all layouts

---

## Files Changed Summary

| File | Phase | Changes |
|---|---|---|
| `Models/PanelGeometry.swift` | 1 | **NEW** — geometry enum |
| `Models/ImagePanel.swift` | 1 | `frame` → `geometry` + backward compat; `CropInfo.destinationRect` → `destination` |
| `Models/LayoutStyle.swift` | 2 | Add 3 new cases, titles, icons |
| `Services/LayoutGenerator.swift` | 2 | Add 3 stub strategies + factory cases |
| `Models/AssemblyConfig.swift` | 3 | Add `OverlayConfig` + `overlay` field |
| `Services/CollageAssembler.swift` | 3 | Path-based clipping in `drawPanels()`; `drawOverlay()` method |
| `ViewModel/CropManager.swift` | 4 | Two-pass `hitTestPanel()` with path containment |
| `Views/CollageEditorView.swift` | 4, 5 | `PanelShape` shape; geometry-aware hit testing; shape-based highlights |
| `ViewModel/CollageViewModel.swift` | 6 | Style-specific config; `buildAssemblyConfig()` overlay |

**Total:** 1 new file, 8 modified files. No deletions.

---

## Rollback Plan

Each phase is independently reversible:
- Phase 1: Remove `PanelGeometry.swift`, revert `ImagePanel`/`CropInfo` to `CGRect`
- Phase 2: Remove new `LayoutStyle` cases and stub strategies
- Phase 3: Revert `drawPanels()` to `clip(to: destRect)`, remove `OverlayConfig`
- Phase 4: Revert `hitTestPanel()` to single-pass `CGRect.contains()`
- Phase 5: Replace `PanelShape` with `Rectangle()`
- Phase 6: Remove style-specific properties, revert `buildAssemblyConfig()`

---

## Coordination with Round-99 Implementation

After this refactoring plan completes, round-99 implementation becomes:

1. **Double Exposure:** Find or create silhouette mask asset → wire to `doubleExposureMaskImage` → test overlay rendering. No geometry changes needed.

2. **Diagonal Slices:** Implement `DiagonalSlicesLayoutStrategy.generate()` to:
   - Compute parallelogram vertices from canvas size, image count, and angle
   - Create `CGPath` for each parallelogram
   - Return `ImagePanel` with `geometry: .path(cgPath: path, boundingRect: bounds)`

3. **Hexagonal:** Implement `HexagonalLayoutStrategy.generate()` to:
   - Position center hexagon + surrounding ring using trigonometry
   - Create `CGPath` for each hexagon
   - Return `ImagePanel` with `geometry: .path(cgPath: path, boundingRect: bounds)`

Both non-rectangular strategies will use the existing `PanelGeometry.path` case and the rendering/hit-testing pipeline will handle them automatically.

---

## Risks and Mitigations

| Risk | Phase | Mitigation |
|---|---|---|
| `CGPath` coordinate system mismatch (CG bottom-left vs SwiftUI top-left) | 3, 5 | Test `PanelShape` rendering early; consult `coordinate-systems.md` skill ref |
| `Path(cgPath)` creates inverted path in SwiftUI | 5 | May need to flip Y coordinates in `PanelShape.path(in:)` |
| Backward compat break in test fixtures | 1 | `frame` and `destinationRect` computed properties should prevent this |
| `CropInfo` Codable break for saved collages | 1 | `destinationRect` initializer accepts `CGRect` — existing encoded data decodes via backward compat |
| Performance: path hit testing on 20+ panels | 4 | Two-pass design limits path tests to bounding-box candidates |
