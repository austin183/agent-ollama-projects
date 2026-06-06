# New Layout Styles Implementation
- Related to plans in `Experiments/CollageMaker/_agent_docs/plans/2026-05-22-new-layout-styles-plan.md`
- Three new enum cases already exist in `LayoutStyle`: `.doubleExposure`, `.diagonalSlices`, `.hexagonal` (`LayoutStyle.swift:7-9`)
- `PanelGeometry` enum already supports `.rect(CGRect)` and `.path(cgPath: CGPath, boundingRect: CGRect)` (`PanelGeometry.swift:8-10`)
- `ImagePanel` already uses `PanelGeometry` with backward-compatible `frame` accessor (`ImagePanel.swift:7`)
- `CollageAssembler.drawPanels()` already clips to `panel.geometry.cgPath` when non-nil (`CollageAssembler.swift:327-332`)
- `PanelShape: Shape` in `CollageEditorView.swift:339-351` already renders CGPath shapes in SwiftUI
- Hit testing in `CropManager.hitTestPanel()` already uses `cgPath.contains(_:)` for path geometry (`CropManager.swift:281-284`)
- ViewModel style-specific properties exist: `doubleExposureMaskImage/Opacity`, `diagonalSliceAngle`, `hexagonalSpacing` (`CollageViewModel.swift:143-170`)
- UserDefaults persistence wired for `doubleExposureMaskOpacity`, `diagonalSliceAngle`, `hexagonalSpacing` (`UserDefaultsPersistence.swift:47-49`)
- **Three layout strategies are stubs** that delegate to `UniformLayoutStrategy` (`LayoutGenerator.swift:209-243`) — these need algorithm implementation

## Style 1: Double Exposure (Silhouette Mask)
- **Visual Description:** Based on Image 1. This is a standard grid layout (similar to `.uniform` or `.mosaic`) but with a large, semi-transparent silhouette mask (e.g., a human profile or abstract shape) overlaid on top of the entire collage.
- **Implementation:**
    - The layout logic should generate standard rectangular panels for the background images.
    - The rendering engine already supports a "Global Mask" / "Overlay" layer via `OverlayConfig` + `drawOverlay()` (`CollageAssembler.swift:344-350`)
    - Overlay is wired in `buildAssemblyConfig()` at `CollageViewModel.swift:828-839` — creates `OverlayConfig` with `.multiply` blend mode when `layoutStyle == .doubleExposure` and `doubleExposureMaskImage` is set
    - The mask should be a user-provided image (stored in `doubleExposureMaskImage: NSImage?`)
    - **TODO:** `DoubleExposureLayoutStrategy` is a stub at `LayoutGenerator.swift:209` — likely just needs to stay as uniform grid (overlay is canvas-wide, not per-panel)
    - **TODO:** `doubleExposureMaskImage` is NOT persisted — add `doubleExposureMaskImagePath` UserDefaults key

## Style 2: Diagonal Slices
- **Visual Description:** Based on Image 2. The canvas is divided into angled strips running from top-left to bottom-right (or vice versa), separated by white gutters.
- **Implementation:**
    - `ImagePanel` already supports polygonal clipping paths via `PanelGeometry.path(cgPath:boundingRect:)` — no model changes needed
    - `CollageAssembler.drawPanels()` already clips to `panel.geometry.cgPath` — no rendering changes needed
    - **Algorithm:**
        - Read angle from `diagonalSliceAngle` ViewModel property (default 45°)
        - Divide the canvas into $N$ parallel diagonal bands based on number of images
        - Generate parallelogram `CGPath` for each band
        - Return `[ImagePanel]` with `.path` geometry
    - **TODO:** `DiagonalSlicesLayoutStrategy` is a stub at `LayoutGenerator.swift:221` — implement parallelogram CGPath generation
    - **BLOCKER:** `LayoutStrategy.generate()` protocol only takes `gutter: CGFloat` — diagonal needs `diagonalSliceAngle`. See "Protocol Signature Refactoring" below.

## Style 3: Hexagonal / Radial Honeycomb
- **Visual Description:** Based on Image 3. A "Hero" style layout where the first image is placed in the exact center, and subsequent images surround it in a ring, forming a honeycomb/hexagonal pattern.
- **Implementation:**
    - `ImagePanel` already supports arbitrary `CGPath` shapes — no model changes needed
    - **Algorithm:**
        - Image 0 is centered in the canvas as a hexagon
        - Remaining images are calculated using trigonometry (sine/cosine) to position them in a circle around the center image
        - Each panel is clipped to a hexagonal `CGPath` with `hexagonalSpacing` (default 8.0) as inter-hexagon gap
    - **TODO:** `HexagonalLayoutStrategy` is a stub at `LayoutGenerator.swift:233` — implement hexagonal CGPath generation and honeycomb positioning
    - **BLOCKER:** `LayoutStrategy.generate()` protocol only takes `gutter: CGFloat` — hexagonal needs `hexagonalSpacing`. See "Protocol Signature Refactoring" below.

## Technical Requirements

### Protocol Signature Refactoring (BLOCKER for Diagonal + Hexagonal)

**Problem:** `LayoutStrategy.generate()` signature only accepts `gutter: CGFloat`. The new styles need style-specific parameters:
- Diagonal needs `diagonalSliceAngle: CGFloat` (from ViewModel)
- Hexagonal needs `hexagonalSpacing: CGFloat` (from ViewModel)

**Recommended fix:** Change `makeStrategy()` factory to accept style-specific configuration and return configured strategy instances:

```swift
func makeStrategy(sliceAngle: CGFloat, hexSpacing: CGFloat) -> LayoutStrategy {
    switch self {
    case .diagonalSlices: return DiagonalSlicesLayoutStrategy(angle: sliceAngle)
    case .hexagonal: return HexagonalLayoutStrategy(spacing: hexSpacing)
    default: return ...
    }
}
```

This requires threading ViewModel properties through `LayoutGenerator.generate()` → `makeStrategy()` → strategy init.

### CropInfo Codable is Lossy for Path Geometry

**Problem:** `CropInfo.encode()` (`ImagePanel.swift:53-64`) only stores `"path"` discriminator + bounding rect. The actual `CGPath` shape is lost. `init(from:)` reconstructs a rectangular path.

**Impact:** Hexagonal/diagonal layouts will revert to rectangular panels after app restart.

**Recommended fix:** Don't persist path geometry directly. Instead, regenerate panel geometry from layout style + parameters on app load. The ViewModel already calls `regenerateLayout()` on init, which rebuilds panels from `LayoutGenerator.generate()`.

### Gutter Handling

- **Diagonal mode:** `gutter` becomes the gap between parallel diagonal bands
- **Hexagonal mode:** `hexagonalSpacing` (not `gutter`) drives inter-hexagon gaps
- Consider whether the shared `gutter` parameter should be renamed to `spacing` for clarity, or if each strategy should read its own config

### Panel Editor in Sidebar

- `PanelShape` already renders non-rectangular shapes in the SwiftUI canvas view
- `CollageAssembler.renderPanel()` (`CollageAssembler.swift:364-392`) only clips to rect — sidebar crop preview will show rectangular preview for shaped panels
- **Consideration:** Add path clipping to `renderPanel()` for visual consistency, or accept rectangular sidebar preview

### Crop Computation

- `CropManager.computeInitialCrops()` uses `panel.frame.size` (bounding rect) for crop calculations
- For non-rectangular panels, the crop will be rectangular but visible area is shaped — corners will be clipped away
- **Consideration:** Compute inscribed rectangle within path shape for more efficient cropping (lower priority)
