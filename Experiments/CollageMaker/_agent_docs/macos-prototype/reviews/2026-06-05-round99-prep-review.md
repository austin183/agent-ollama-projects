# CollageMaker — Pre-Round-99 Refactoring Review

**Date:** 2026-06-05
**Scope:** Codebase readiness for non-rectangular layout styles (round-99)
**Target change:** `_agent_docs/change-requests/round-99.md` — Double Exposure, Diagonal Slices, Hexagonal layouts
**Prior review:** 2026-06-04 full architectural review (findings C-1 through S-18 carried forward)

---

## Executive Summary

Round-99 requires three new layout styles, two of which (**Diagonal Slices** and **Hexagonal**) break the fundamental rectangular assumption baked into the data model, rendering pipeline, gesture hit-testing, and SwiftUI views. **Double Exposure** is the simplest — it reuses rectangular panels and only adds an overlay mask layer.

The current architecture has a well-designed strategy pattern in `LayoutGenerator.swift` that is already extensible. However, the `CGRect`-only geometry in `ImagePanel` and `CropInfo` creates a cascade of breaking changes across ~10 files. The bottleneck is not the layout generation — it's the downstream consumers that assume rectangular panels.

**Recommended refactoring investment:** 3 focused changes to the data model and rendering pipeline, touching ~8 files. These are prerequisite to any non-rectangular style and should be completed before implementing the layout algorithms themselves.

---

## Impact Analysis by Style

| Concern | Double Exposure | Diagonal Slices | Hexagonal |
|---|---|---|---|
| `ImagePanel.frame: CGRect` | OK — rect panels | **BLOCKED** — needs CGPath | **BLOCKED** — needs CGPath |
| `CropInfo.destinationRect: CGRect` | OK | **BLOCKED** | **BLOCKED** |
| `LayoutStrategy` protocol | Reuse existing strategy | New strategy, OCP-friendly | New strategy, OCP-friendly |
| `CollageAssembler.drawPanels()` | Add overlay step | Change `clip(to:)` | Change `clip(to:)` |
| `PanelOverlay` SwiftUI view | Add mask overlay | Change Rectangle to Shape | Change Rectangle to Shape |
| `CropManager.hitTestPanel()` | OK — rect panels | Path containment needed | Path containment needed |
| `PanelCropEditor` sidebar | OK | Visual mismatch (crop rect vs hex display) | Visual mismatch |
| New ViewModel config | `silhouetteMaskImage: NSImage?` | `sliceAngle: CGFloat?` | ring/spacing config |
| `AssemblyConfig` | Add overlay config | No change | No change |

---

## Critical Findings (Blocking Round-99)

### C-1: `ImagePanel.frame: CGRect` is the single point of failure

**File:** `Models/ImagePanel.swift:7`
**Severity:** Critical

The `frame: CGRect` property is the only geometry representation. Every downstream consumer — layout generation, crop management, rendering, hit-testing, SwiftUI preview — derives from this field. Adding a `clipPath: CGPath?` as a second property is the minimal change, but introduces a dual-representation problem: which is authoritative for bounding box, hit-testing, and SwiftUI sizing?

**Recommended refactor:** Introduce `PanelGeometry` as an enum:

```swift
enum PanelGeometry: Codable {
    case rect(CGRect)
    case path(CGPath, boundingRect: CGRect)
}

extension PanelGeometry {
    var boundingRect: CGRect {
        switch self {
        case .rect(let r): return r
        case .path(_, let r): return r
        }
    }
}
```

Then change `ImagePanel.frame` to `geometry: PanelGeometry`. Provide a backward-compatible computed property `var frame: CGRect { geometry.boundingRect }` during migration.

**Files affected:** `ImagePanel.swift`, `LayoutGenerator.swift` (all 3 strategies), `CollageAssembler.swift`, `CropManager.swift`, `CollageEditorView.swift`, `PanelCropEditor.swift`, `AssemblyConfig.swift`, `CollageViewModel.swift`

---

### C-2: `CropInfo.destinationRect: CGRect` duplicates the rectangular assumption

**File:** `Models/ImagePanel.swift:23`
**Severity:** Critical

`CropInfo` stores `destinationRect: CGRect` to track where the cropped image should be drawn. For non-rectangular panels, this is insufficient — the destination is a path, not a rect. The crop's `sourceRect` can remain rectangular (you're always selecting a rectangular region of the source image), but the destination must support arbitrary shapes.

**Recommended refactor:** Change `destinationRect` to `destination: PanelGeometry` (same type as above). The `sourceRect` stays as `CGRect` — the source crop is always rectangular regardless of panel shape.

**Files affected:** `ImagePanel.swift`, `CropManager.swift` (all crop computation), `CollageAssembler.swift` (`drawPanels()`, `renderPanel()`), `PanelCropEditor.swift`

---

### C-3: `CollageAssembler.drawPanels()` clips to CGRect only

**File:** `Services/CollageAssembler.swift:318`
**Severity:** Critical

```swift
context.clip(to: destRect)
```

This single line assumes rectangular clipping. For diagonal slices and hexagonal panels, clipping must use `context.addPath(panelGeometry.cgPath)` followed by `context.clip()`.

**Recommended refactor:** After `PanelGeometry` is introduced, change the clip to:

```swift
switch panel.geometry {
case .rect:
    context.clip(to: panel.geometry.boundingRect)
case .path(let cgPath, _):
    context.addPath(cgPath)
    context.clip()
}
```

Same change needed in `renderPanel()` at line 355.

**Additional concern:** The `context.draw(cropped, in: destRect)` call at line 321 draws the cropped image into a rectangular destination. For non-rectangular panels, the image still fills the bounding rect — the clip path handles the shape. This means the drawing call doesn't need to change, only the clip.

---

## Warning Findings (Should Address Before Round-99)

### W-1: `LayoutStyle.makeStrategy()` switch violates OCP

**File:** `Services/LayoutGenerator.swift:195-201`
**Severity:** Warning

Every new layout style requires editing the `makeStrategy()` switch. This is the classic OCP violation in a strategy pattern.

**Recommended refactor:** Use an associated value or a registry pattern:

```swift
extension LayoutStyle {
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
}
```

This is acceptable for now — the switch is short and lives in one place. No need for a registry pattern until the enum grows beyond ~10 cases. Just be aware that each new case is a required edit.

---

### W-2: `CollageEditorView` hit testing uses `CGRect.contains()` only

**File:** `Views/CollageEditorView.swift:321-329`, `ViewModel/CropManager.swift:265-270`
**Severity:** Warning

```swift
static func hitTestPanel(at location: CGPoint, panelFrames: [UUID: CGRect]) -> UUID? {
    for (id, frame) in panelFrames where frame.contains(location) {
        return id
    }
    return nil
}
```

`CGRect.contains()` is O(1) and fast. For non-rectangular panels, hit testing must use `CGPath.contains(point)`, which is more expensive. Additionally, the current API takes `[UUID: CGRect]`, which won't carry path information.

**Recommended refactor:** Change the signature to accept `[UUID: PanelGeometry]` and dispatch on geometry type:

```swift
static func hitTestPanel(at location: CGPoint, panels: [UUID: PanelGeometry]) -> UUID? {
    for (id, geometry) in panels {
        switch geometry {
        case .rect(let rect):
            if rect.contains(location) { return id }
        case .path(let path, _):
            if path.contains(location) { return id }
        }
    }
    return nil
}
```

Performance consideration: `CGPath.contains()` uses point-in-polygon testing (ray casting), which is O(n) in vertices. For hexagonal panels (6 vertices), this is negligible. For complex paths with many vertices, consider caching a rasterized hit-test mask.

---

### W-3: SwiftUI `PanelOverlay` renders `Rectangle()` for all panels

**File:** `Views/CollageEditorView.swift:336-398`
**Severity:** Warning

Three locations use `Rectangle()`:
- `PanelHitArea` (line 343): Clear hit area
- `PanelOverlay` selection indicator (line 391): White stroke
- Drag source/target highlights (lines 96-111): Cyan/green stroke

**Recommended refactor:** Create a `PanelShape` SwiftUI `Shape` that renders either a rectangle or a custom path:

```swift
struct PanelShape: Shape {
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

Replace `Rectangle()` with `PanelShape(geometry: panel.geometry)` in all three locations.

---

### W-4: `PanelCropEditor` assumes rectangular crop handles

**File:** `Views/PanelCropEditor.swift` (entire file, 409 lines)
**Severity:** Warning

The crop editor shows 4 corner handles and a rectangular dim overlay. For non-rectangular panels, the source crop is still rectangular (you select a rect from the source image), but the *visual feedback* is misleading — users won't see how the hexagonal/diagonal clip affects the final appearance.

**Recommended refactor:** The crop editor's core functionality (source rect selection) doesn't need to change. However, add a *preview* of the panel shape as an overlay on the crop preview. This could be a low-opacity `Shape` overlay showing the hexagonal/diagonal clip boundary. This way users understand that while they're adjusting a rectangular crop region, the final display will be clipped to the panel shape.

**Alternative:** Defer this until after the core geometry refactoring. The crop editor will still function correctly for non-rectangular panels — the source crop is rectangular regardless of destination shape.

---

### W-5: `AssemblyConfig` has no overlay/mask support

**File:** `Models/AssemblyConfig.swift:59-102`
**Severity:** Warning

Double Exposure requires rendering a silhouette mask overlay on top of the panels. The current `AssemblyConfig` has no concept of overlays.

**Recommended refactor:** Add an optional overlay configuration:

```swift
struct OverlayConfig: @unchecked Sendable {
    let maskImage: CGImage
    let opacity: CGFloat
    let blendMode: CGBlendMode
}

struct AssemblyConfig {
    let layout: LayoutConfig
    let title: TitleConfig
    let background: BackgroundConfig
    let canvasSize: CGSize
    let overlay: OverlayConfig?  // NEW
}
```

Then add a rendering step in `CollageAssembler.renderIntoContext()` after `drawPanels()`:

```swift
if let overlay = config.overlay {
    drawOverlay(into: context, overlay: overlay, canvasSize: config.canvasSize)
}
```

---

### W-6: `CollageViewModel` layout change flow doesn't carry style-specific config

**File:** `ViewModel/CollageViewModel.swift:134-140`
**Severity:** Warning

The `layoutStyle` property's `didSet` calls `regenerateLayout()`, which calls `LayoutGenerator.generate()`. But new styles may need style-specific parameters (silhouette mask for double exposure, angle for diagonal slices, ring count for hexagonal).

**Recommended refactor:** Add style-specific configuration properties to the view model. These could be:
- `silhouetteMaskImage: NSImage?` for double exposure
- `diagonalSliceAngle: CGFloat` for diagonal slices
- `hexagonalRings: Int` or `hexagonalSpacing: CGFloat` for hexagonal

Pass these through `LayoutGenerator.generate()` as optional parameters, or encode them in the `LayoutStrategy` protocol signature.

**Alternative:** Create a `LayoutConfig` struct that holds style-specific parameters, avoiding parameter bloat on `LayoutGenerator.generate()`.

---

## Suggestion Findings (Nice-to-Have Before Round-99)

### S-1: Extract `PanelGeometry` to its own file

**Suggestion:** Rather than adding `PanelGeometry` to `ImagePanel.swift`, create `Models/PanelGeometry.swift`. This keeps the geometry abstraction isolated and makes it easy to add path utilities (hexagon generation, parallelogram generation) as static methods on the type.

### S-2: Add `CGPath` factory methods for common shapes

**Suggestion:** Create a `PathFactory` struct with static methods:

```swift
struct PathFactory {
    static func hexagon(center: CGPoint, radius: CGFloat, path: CGPath) -> CGPath { ... }
    static func parallelogram(bounds: CGRect, angle: CGFloat, shear: CGFloat) -> CGPath { ... }
}
```

This keeps the layout strategies clean and centralizes path generation logic.

### S-3: Consider `PanelGeometry` Codable conformance carefully

**Suggestion:** `CGPath` doesn't conform to `Codable`. The `PanelGeometry.path` case will need custom encoding — likely storing the path as a serialized point array + reconstruction instructions. For the initial implementation, consider whether non-rectangular layouts need to be persisted, or if they can be regenerated on load.

### S-4: Test `CGPath.contains()` performance with many panels

**Suggestion:** The mosaic layout can produce up to 20 panels. With path-based hit testing, each tap requires iterating all panels and calling `CGPath.contains()`. Benchmark this to ensure it stays under the 50ms discrete interaction budget from the skill reference.

### S-5: Coordinate system awareness for `CGPath`

**Suggestion:** The skill reference emphasizes coordinate system traps (Vision bottom-left vs CoreGraphics bottom-left vs NSImage/SwiftUI top-left). `CGPath` created in a layout strategy will be in canvas coordinates (CoreGraphics, bottom-left). When rendered in SwiftUI via `Path(cgPath)`, SwiftUI expects top-left. Verify that the path coordinates are flipped correctly, or create the path in the right coordinate space for each consumer.

---

## Recommended Refactoring Order

Complete these in sequence to minimize cascading changes:

### Phase 1: Data Model (touches 2 files)

1. **Create `Models/PanelGeometry.swift`** — Define the enum with `rect`/`path` cases, `boundingRect` computed property, `cgPath` computed property
2. **Update `Models/ImagePanel.swift`** — Replace `frame: CGRect` with `geometry: PanelGeometry`, add backward-compatible `var frame: CGRect` computed property
3. **Update `Models/ImagePanel.swift`** — Change `CropInfo.destinationRect` to `destination: PanelGeometry`

### Phase 2: Layout Generation (touches 1 file)

4. **Update `Services/LayoutGenerator.swift`** — Existing strategies emit `.rect` geometry. Add `makeStrategy()` cases for new styles (can be stub implementations returning empty arrays)

### Phase 3: Rendering (touches 1 file)

5. **Update `Services/CollageAssembler.swift`** — `drawPanels()` and `renderPanel()` clip to `PanelGeometry`. Add `drawOverlay()` for double exposure

### Phase 4: Crop Management (touches 1 file)

6. **Update `ViewModel/CropManager.swift`** — `hitTestPanel()` dispatches on geometry type. `computeInitialCrops()` and related methods use `PanelGeometry.boundingRect` for panel size

### Phase 5: SwiftUI Views (touches 2 files)

7. **Update `Views/CollageEditorView.swift`** — `PanelOverlay` and `PanelHitArea` render `PanelShape`. Drag highlights use path-based shapes
8. **Update `Views/PanelCropEditor.swift`** — Optional: add shape preview overlay

### Phase 6: Configuration (touches 2 files)

9. **Update `Models/AssemblyConfig.swift`** — Add `OverlayConfig?` for double exposure
10. **Update `ViewModel/CollageViewModel.swift`** — Add style-specific config properties, update `buildAssemblyConfig()`

---

## OCP Assessment

| Component | OCP Status | Notes |
|---|---|---|
| `LayoutStrategy` protocol | **Open** | New strategies are additive — no existing code modified |
| `LayoutStyle` enum | **Open** | New cases are additive |
| `LayoutStyle.makeStrategy()` | **Closed** | Requires edit for each new case (acceptable for small enum) |
| `ImagePanel` | **Closed** | Requires edit to support non-rect geometry |
| `CropInfo` | **Closed** | Requires edit to support non-rect destination |
| `CollageAssembler.drawPanels()` | **Closed** | Requires edit to support path clipping |
| `CollageEditorView` | **Closed** | Requires edit to render non-rect shapes |
| `CropManager.hitTestPanel()` | **Closed** | Requires edit for path-based hit testing |

The strategy pattern is well-designed. The OCP violations are all in the *consumers* of `ImagePanel`, not in the layout generation itself. The refactoring plan above addresses each violation with a minimal change.

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Breaking existing layout tests | High | Medium | Keep `frame` as computed property during migration; update tests in Phase 1 |
| Coordinate system bugs in CGPath | High | High | Return to skill reference `coordinate-systems.md`; add unit tests for path generation |
| SwiftUI Path/CGPath conversion issues | Medium | Medium | Test `Path(cgPath)` rendering early with a simple hexagon |
| Performance regression in hit testing | Low | Low | Hexagonal panels have 6 vertices — negligible overhead |
| `CGPath` Codable serialization | Medium | Medium | Defer persistence of non-rect layouts; regenerate on load |
| Crop editor confusion for users | Medium | Low | Add shape preview overlay (W-4) or document the behavior |

---

## Conclusion

The codebase is in good shape for round-99. The strategy pattern in `LayoutGenerator` is extensible, and the protocol-based rendering in `CollageAssembler` provides clean injection points. The primary blocker is the `CGRect`-only geometry in `ImagePanel` and `CropInfo`, which requires a focused refactoring of the data model (`PanelGeometry` enum) with cascading updates to ~8 files.

**Estimated effort:** Phase 1-3 (data model + rendering) is the critical path and should be completed in a single session to maintain context. Phases 4-6 can follow incrementally as each new layout style is implemented.

**Go/No-Go recommendation:** **Go** — proceed with Phase 1 refactoring. The changes are well-scoped, the existing architecture supports extension, and the risk is manageable with the mitigation strategies above.
