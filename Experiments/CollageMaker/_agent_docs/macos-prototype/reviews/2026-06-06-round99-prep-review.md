# Round-99 Prep Review — 2026-06-06

## Purpose

Assess codebase readiness for implementing the three new layout styles (`doubleExposure`, `diagonalSlices`, `hexagonal`) and identify refactoring opportunities to smooth implementation.

## Executive Summary

**Good news:** The infrastructure for non-rectangular panels is largely already in place. `PanelGeometry`, path-based clipping in `CollageAssembler`, SwiftUI `PanelShape`, and hit testing all support arbitrary `CGPath` shapes. The three new `LayoutStyle` enum cases exist with titles, icons, ViewModel properties, and UserDefaults persistence.

**Current gap:** The three layout strategies are stubs that delegate to `UniformLayoutStrategy`. The primary work is implementing the geometry algorithms. Several supporting areas need attention before the implementation will be complete.

## What's Already Done (vs. Round-99 Descriptions)

| Round-99 Statement | Current State |
|---|---|
| "Add three new enum cases to `LayoutStyle`" | ✅ Done — `.doubleExposure`, `.diagonalSlices`, `.hexagonal` exist with titles and icons (`LayoutStyle.swift:7-9`) |
| "`ImagePanel` currently uses `frame: CGRect` — needs `clipPath: CGPath?`" | ✅ Done — `ImagePanel` uses `PanelGeometry` enum with `.rect(CGRect)` and `.path(cgPath: CGPath, boundingRect: CGRect)` cases (`PanelGeometry.swift:8-10`) |
| "Rendering engine must support Global Mask / Overlay layer" | ✅ Done — `OverlayConfig` + `drawOverlay()` in `CollageAssembler.swift:344-350`, wired in `buildAssemblyConfig()` at `CollageViewModel.swift:828-839` |
| "Panels must be clipped to hexagonal shapes using `CGPath`" | ✅ Done — `drawPanels()` at `CollageAssembler.swift:327-332` clips to `panel.geometry.cgPath` when non-nil |
| "Panel Editor in Right Hand Sidebar with various shapes" | ✅ Done — `PanelShape: Shape` at `CollageEditorView.swift:339-351` renders CGPath shapes; hit testing at `CropManager.swift:265-291` uses `cgPath.contains(_:)` |
| ViewModel style-specific properties | ✅ Done — `doubleExposureMaskImage/Opacity`, `diagonalSliceAngle`, `hexagonalSpacing` at `CollageViewModel.swift:143-170` |
| UserDefaults persistence | ✅ Done — Keys at `UserDefaultsPersistence.swift:47-49`, save/load wired |

## What Remains: Strategy Implementation

All three strategies are stubs at `LayoutGenerator.swift:209-243`:

### 1. `DoubleExposureLayoutStrategy` (line 209)
- **Current:** Delegates to `UniformLayoutStrategy`
- **Needed:** Likely still rectangular panels — the overlay is canvas-wide, not per-panel. May need to decide between uniform grid vs. a more artistic layout. The overlay rendering (`drawOverlay`) is already complete.
- **Refactoring note:** Consider whether double exposure should produce a single large panel (the "background" photo) with the mask on top, rather than a grid. The current design treats it as grid + overlay, which matches the round-99 description.

### 2. `DiagonalSlicesLayoutStrategy` (line 221)
- **Current:** Delegates to `UniformLayoutStrategy`
- **Needed:** Generate parallelogram `CGPath` shapes for each slice. Each panel should be a `.path(cgPath: boundingRect:)` geometry.
- **Algorithm sketch:**
  - Convert `diagonalSliceAngle` (from ViewModel, default 45°) to radians
  - For N images, compute N parallel diagonal bands across the canvas
  - Each band is a parallelogram defined by 4 corner points
  - Create `CGPath` from the 4 points, compute bounding rect
  - Return `[ImagePanel]` with `.path` geometry
- **Gutter:** The shared `gutter` parameter should become the gap between parallel bands. May need to pass `diagonalSliceAngle` through the `LayoutStrategy` protocol.

### 3. `HexagonalLayoutStrategy` (line 233)
- **Current:** Delegates to `UniformLayoutStrategy`
- **Needed:** Generate hexagonal `CGPath` shapes arranged in a honeycomb pattern.
- **Algorithm sketch:**
  - Center hexagon for image 0
  - Ring of hexagons around center for remaining images
  - Use `hexagonalSpacing` (from ViewModel, default 8.0) as gap between hexagons
  - Each hexagon is a 6-point `CGPath`
- **Gutter:** The `hexagonalSpacing` ViewModel property should drive inter-hexagon gaps, not the shared `gutter` parameter.

## Refactoring Opportunities (Before/During Implementation)

### CRITICAL: Protocol Signature Needs Style-Specific Parameters

**Issue:** `LayoutStrategy.generate()` takes `gutter: CGFloat` but the new styles need different parameters:
- Diagonal needs `diagonalSliceAngle: CGFloat`
- Hexagonal needs `hexagonalSpacing: CGFloat`

**Options:**
1. **Add optional parameters to the protocol** — `sliceAngle: CGFloat?`, `hexSpacing: CGFloat?`
2. **Pass a configuration dictionary** — Less type-safe, but flexible
3. **Create style-specific strategy structs that capture their config** — e.g., `DiagonalSlicesLayoutStrategy(angle: CGFloat)` — cleanest, but requires changing the factory method

**Recommendation:** Option 3. Change `makeStrategy()` to accept style-specific configuration. Example:
```swift
func makeStrategy(angle: CGFloat, hexSpacing: CGFloat) -> LayoutStrategy {
    switch self {
    case .diagonalSlices: return DiagonalSlicesLayoutStrategy(angle: angle)
    case .hexagonal: return HexagonalLayoutStrategy(spacing: hexSpacing)
    default: return ...
    }
}
```
This requires threading the ViewModel properties through `LayoutGenerator.generate()` and into `makeStrategy()`.

### HIGH: CropInfo Codable is Lossy for Path Geometry

**Issue:** `CropInfo.encode()` at `ImagePanel.swift:53-64` stores only `"path"` as discriminator + bounding rect. The actual `CGPath` shape is lost on serialization. `init(from:)` at line 72-73 reconstructs a rectangular path.

**Impact:** If a user creates a hexagonal layout, closes the app, and reopens, the panels will lose their hexagonal shapes and revert to rectangles.

**Fix options:**
1. **Parameterized paths:** Store the parameters needed to reconstruct the path (e.g., `"hexagon"`, `"diagonal"`, angle, spacing) instead of the raw CGPath
2. **CGPath data serialization:** Use `CGPath` element enumeration to serialize to `[UInt8]` — complex, fragile
3. **Regenerate on load:** Don't persist path geometry at all — regenerate from layout style + parameters on app launch

**Recommendation:** Option 3 is simplest. Store layout style, parameters, and crop sourceRects. Regenerate panel geometry from the layout strategy on load. This is already partially how the app works — `regenerateLayout()` in the ViewModel rebuilds panels from the style.

### MEDIUM: Crop Computation Uses Bounding Rect

**Issue:** `CropManager.computeInitialCrops()` at line 70 uses `panel.frame.size` (which is `geometry.boundingRect.size`). For a hexagonal panel inscribed in a rectangle, the crop will be rectangular but the visible area is hexagonal — the corners will be clipped away.

**Impact:** Wasted pixels in corners, potentially cutting off important content that would have been visible in a rectangular crop.

**Fix:** Could compute an "inscribed rectangle" within the path shape for crop purposes. For hexagons, this would be a smaller rect that fits entirely within the hexagon. Lower priority — the current behavior is functional, just not optimal.

### MEDIUM: `renderPanel` Doesn't Support Path Clipping

**Issue:** `CollageAssembler.renderPanel()` at line 364-392 always clips to rectangular `destRect`. Comment says "Path clipping is not needed here" since it's for sidebar preview.

**Impact:** Sidebar crop preview for non-rectangular panels will show the full rectangular crop, not the shaped panel. This is a visual inconsistency.

**Fix:** Add path clipping support to `renderPanel()`, or accept that sidebar preview is rectangular.

### LOW: `doubleExposureMaskImage` Not Persisted

**Issue:** The mask image for double exposure is stored in memory only. No UserDefaults key persists it.

**Impact:** Mask image is lost on app restart.

**Fix:** Add a `doubleExposureMaskImagePath` key (similar to `backgroundImagePath`) to persist the file path.

### LOW: Gutter Parameter Ambiguity

**Issue:** The `gutter: CGFloat` parameter in `LayoutStrategy.generate()` has different meanings per style:
- Uniform/Hero/Mosaic: gap between rectangular panels
- Diagonal: gap between parallel diagonal bands
- Hexagonal: gap between hexagons (but `hexagonalSpacing` is the ViewModel property for this)

**Impact:** Confusing API, potential for inconsistent behavior.

**Fix:** The strategy-struct approach (recommended above) can encapsulate style-specific spacing. The protocol could use a generic `spacing: CGFloat` parameter, or each strategy reads its own config.

## Architecture Quality Assessment

### SOLID Principles

| Principle | Assessment |
|---|---|
| **SRP** | Good — `PanelGeometry` handles shape, `LayoutStrategy` handles layout math, `CollageAssembler` handles rendering |
| **OCP** | Good — new styles add new strategy structs without modifying existing ones. Factory pattern via `makeStrategy()` |
| **LSP** | N/A — no inheritance hierarchy |
| **ISP** | Good — `LayoutStrategy` protocol is minimal (one method). `CollageAssembly` composes 4 focused protocols |
| **DIP** | Good — `CollageAssembler` depends on `CollageAssembly` protocol, strategies depend on `LayoutStrategy` protocol |

### Separation of Concerns

- **Layout math** is isolated in `LayoutGenerator.swift` — easy to test and modify
- **Rendering** is isolated in `CollageAssembler.swift` — already path-aware
- **UI** is in `CollageEditorView.swift` — `PanelShape` handles shape rendering
- **State** is in `CollageViewModel` — style-specific properties are well-organized

### Testing Readiness

- `LayoutStrategy` protocol is pure function — easy to unit test with `@Test`
- Strategy implementation should test: panel count, geometry types, bounding rect coverage, no overlap
- `PanelGeometry` is simple enum — straightforward to test

## Updated Round-99 Technical Requirements

The round-99.md file has been updated to reflect current codebase state. Key corrections:
1. `ImagePanel` already supports `PanelGeometry` (rect + path) — no update needed
2. `CollageAssembler` already clips panels to `CGPath` — rendering pipeline is ready
3. `PanelShape` SwiftUI view already renders non-rectangular shapes
4. Hit testing already supports `cgPath.contains(_:)`
5. Three strategies are stubs awaiting algorithm implementation
6. Protocol signature needs extension for style-specific parameters
7. `CropInfo` Codable is lossy for path geometry — needs addressing for persistence

## Recommended Implementation Order

1. **Extend `LayoutStrategy` protocol** — Add optional style-specific parameters, or refactor factory to pass configured strategy instances
2. **Implement `DiagonalSlicesLayoutStrategy`** — Parallelogram CGPath generation
3. **Implement `HexagonalLayoutStrategy`** — Hexagonal CGPath generation with honeycomb positioning
4. **Implement `DoubleExposureLayoutStrategy`** — May just need to keep rectangular panels (overlay is canvas-wide)
5. **Fix `CropInfo` persistence** — Either parameterize paths or regenerate on load
6. **Add `doubleExposureMaskImage` persistence** — File path key in UserDefaults
7. **Consider `renderPanel` path clipping** — For sidebar preview consistency
8. **Add tests** — Strategy output validation, geometry correctness
