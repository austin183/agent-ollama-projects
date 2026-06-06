# Round-99: New Layout Styles Implementation Plan

**Date**: 2026-06-06
**Source review**: `_agent_docs/reviews/2026-06-06-round99-prep-review.md`
**Prep refactoring**: `_agent_docs/plans/2026-06-05-round99-prep-refactoring.md` (complete)
**Target change**: `_agent_docs/change-requests/round-99.md`
**Scope**: Implement three new layout strategies, protocol refactoring for style-specific parameters, persistence fixes, polish

**Prerequisites:**
- `PanelGeometry` enum with `.rect` and `.path` cases — done
- `CollageAssembler.drawPanels()` path clipping — done
- `PanelShape` SwiftUI rendering — done
- `CropManager.hitTestPanel()` path hit testing — done
- `OverlayConfig` + `drawOverlay()` — done
- `LayoutStyle` enum with 6 cases — done
- ViewModel style-specific properties — done
- Three stub strategies that delegate to `UniformLayoutStrategy` — done

---

## Phase 1: Protocol Refactoring — Style-Specific Strategy Configuration

**Goal:** Enable `DiagonalSlicesLayoutStrategy` to receive `diagonalSliceAngle` and `HexagonalLayoutStrategy` to receive `hexagonalSpacing` through configured strategy instances, without changing the `LayoutStrategy` protocol signature.

### 1.1 Update `LayoutStyle.makeStrategy()` to Accept Configuration

**File:** `Services/LayoutGenerator.swift`

**Current (line 194-205):**
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

**New:** Add an overloaded factory that accepts style-specific parameters. The existing parameterless `makeStrategy()` remains for the three original styles.

```swift
extension LayoutStyle {
    func makeStrategy(
        sliceAngle: CGFloat = 45.0,
        hexSpacing: CGFloat = 8.0
    ) -> LayoutStrategy {
        switch self {
        case .uniform: return UniformLayoutStrategy()
        case .hero: return HeroLayoutStrategy()
        case .mosaic: return MosaicLayoutStrategy()
        case .doubleExposure: return DoubleExposureLayoutStrategy()
        case .diagonalSlices: return DiagonalSlicesLayoutStrategy(angle: sliceAngle)
        case .hexagonal: return HexagonalLayoutStrategy(spacing: hexSpacing)
        }
    }
}
```

**Rationale:** The existing `LayoutStrategy` protocol stays unchanged. Each new strategy struct stores its own configuration. The three original strategies are unaffected.

### 1.2 Update `LayoutGenerator.generate()` to Forward Parameters

**File:** `Services/LayoutGenerator.swift`

**Current (line 8-25):**
```swift
struct LayoutGenerator {
    static func generate(
        numImages: Int,
        canvasSize: CGSize = SizeConstants.defaultCanvasSize,
        gutter: CGFloat = 4,
        style: LayoutStyle = .hero,
        imageOrder: [Int]? = nil,
        mosaicSeed: UInt64? = nil
    ) -> [ImagePanel] {
        style.makeStrategy().generate(...)
    }
}
```

**New:** Add optional style-specific parameters with defaults.

```swift
struct LayoutGenerator {
    static func generate(
        numImages: Int,
        canvasSize: CGSize = SizeConstants.defaultCanvasSize,
        gutter: CGFloat = 4,
        style: LayoutStyle = .hero,
        imageOrder: [Int]? = nil,
        mosaicSeed: UInt64? = nil,
        sliceAngle: CGFloat = 45.0,
        hexSpacing: CGFloat = 8.0
    ) -> [ImagePanel] {
        style.makeStrategy(sliceAngle: sliceAngle, hexSpacing: hexSpacing).generate(
            numImages: numImages,
            canvasSize: canvasSize,
            gutter: gutter,
            imageOrder: imageOrder,
            mosaicSeed: mosaicSeed
        )
    }
}
```

**Rationale:** Default values mean all 40 existing test call sites compile unchanged. Only the production call in `CollageViewModel` needs to pass the ViewModel properties.

### 1.3 Update `CollageViewModel.regenerateLayout()` to Pass Style Parameters

**File:** `ViewModel/CollageViewModel.swift`

**Current (line 522-528):**
```swift
        panels = LayoutGenerator.generate(
            numImages: images.count,
            canvasSize: SizeConstants.defaultCanvasSize,
            gutter: gutter,
            style: layoutStyle,
            imageOrder: customImageOrder
        )
```

**New:**
```swift
        panels = LayoutGenerator.generate(
            numImages: images.count,
            canvasSize: SizeConstants.defaultCanvasSize,
            gutter: gutter,
            style: layoutStyle,
            imageOrder: customImageOrder,
            sliceAngle: diagonalSliceAngle,
            hexSpacing: hexagonalSpacing
        )
```

### 1.4 Update Stub Strategies to Accept Configuration

**File:** `Services/LayoutGenerator.swift`

**DiagonalSlicesLayoutStrategy (line 221-230):**
```swift
struct DiagonalSlicesLayoutStrategy: LayoutStrategy {
    let angle: CGFloat

    init(angle: CGFloat = 45.0) {
        self.angle = angle
    }

    func generate(numImages: Int, canvasSize: CGSize, gutter: CGFloat, imageOrder: [Int]?, mosaicSeed: UInt64?) -> [ImagePanel] {
        // TODO: Implement parallelogram geometry
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

**HexagonalLayoutStrategy (line 233-242):**
```swift
struct HexagonalLayoutStrategy: LayoutStrategy {
    let spacing: CGFloat

    init(spacing: CGFloat = 8.0) {
        self.spacing = spacing
    }

    func generate(numImages: Int, canvasSize: CGSize, gutter: CGFloat, imageOrder: [Int]?, mosaicSeed: UInt64?) -> [ImagePanel] {
        // TODO: Implement hexagonal geometry
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

### 1.5 Wire `diagonalSliceAngle` and `hexagonalSpacing` didSet to Regenerate Layout

**File:** `ViewModel/CollageViewModel.swift`

Currently `diagonalSliceAngle.didSet` (line 157-162) and `hexagonalSpacing.didSet` (line 164-170) only call `debouncedSave()`. They need to also regenerate the layout when changed:

```swift
    var diagonalSliceAngle: CGFloat = 45.0 {
        didSet {
            guard !isInitializing else { return }
            registerUndo(oldValue: oldValue, actionName: "Change Slice Angle") { $0.diagonalSliceAngle = oldValue }
            if layoutStyle == .diagonalSlices {
                regenerateLayout(preserveCrops: false)
            } else {
                debouncedSave()
            }
        }
    }

    var hexagonalSpacing: CGFloat = 8.0 {
        didSet {
            guard !isInitializing else { return }
            registerUndo(oldValue: oldValue, actionName: "Change Hex Spacing") { $0.hexagonalSpacing = oldValue }
            if layoutStyle == .hexagonal {
                regenerateLayout(preserveCrops: false)
            } else {
                debouncedSave()
            }
        }
    }
```

**Rationale:** Changing the angle/spacing should immediately update the layout when in the corresponding style. When in a different style, just persist the value for later use.

### 1.6 Verify Build + Tests

```bash
bash script/build_and_run.sh --verify
xcodebuild test -project CollageMaker/CollageMaker.xcodeproj -scheme CollageMaker -destination 'platform=macOS,arch=arm64' -only-testing:CollageMakerTests
```

**Expected:** All existing tests pass. Default parameter values mean no test changes needed.

---

## Phase 2: Diagonal Slices Strategy Implementation

**Goal:** Implement `DiagonalSlicesLayoutStrategy.generate()` to produce parallelogram panels with `CGPath` clip shapes.

### 2.1 Geometry Algorithm

**Visual:** Canvas divided into N parallel diagonal bands running top-left → bottom-right at `angle` degrees. Each band is a parallelogram. White gutters separate bands.

**Approach:** Shear-transform a uniform grid, then compute the intersection of each sheared cell with the canvas bounds.

**Algorithm:**
1. Start with a uniform grid of N columns (one per image)
2. Apply a shear transform `CGAffineTransform(a: 1, b: 0, c: tan(radians), d: 1, tx: 0, ty: 0)` where `radians = angle * .pi / 180`
3. For each sheared cell, compute its intersection with the canvas rect
4. Build a `CGPath` from the intersection polygon (will be a parallelogram or trapezoid at edges)
5. Return `ImagePanel` with `.path(cgPath: path, boundingRect: bounds)`

**Edge cases:**
- `numImages == 1`: Return full canvas as single parallelogram (or just rect)
- `angle == 0`: Degenerate to vertical strips (no shear)
- `angle >= 70`: Bands become very thin — may need to clamp or warn

### 2.2 Implementation

**File:** `Services/LayoutGenerator.swift`

Replace the stub `DiagonalSlicesLayoutStrategy.generate()` with:

```swift
func generate(numImages: Int, canvasSize: CGSize, gutter: CGFloat, imageOrder: [Int]?, mosaicSeed: UInt64?) -> [ImagePanel] {
    guard numImages > 0 else { return [] }

    if numImages == 1 {
        let imgIdx = imageOrder?[0] ?? 0
        return [ImagePanel(imageIndex: imgIdx, frame: CGRect(origin: .zero, size: canvasSize))]
    }

    let radians = angle * .pi / 180.0
    let shear = tan(radians)

    // Compute un-sheared column width (accounting for gutter between bands)
    let totalGutter = CGFloat(numImages - 1) * gutter
    let colWidth = (canvasSize.width + totalGutter) / CGFloat(numImages)

    var panels: [ImagePanel] = []

    for i in 0..<numImages {
        // Un-sheared rectangle for this column
        let unshearedX = CGFloat(i) * (colWidth + gutter)
        let unshearedRect = CGRect(x: unshearedX, y: 0, width: colWidth, height: canvasSize.height)

        // Shear the four corners: (x, y) -> (x + y * shear, y)
        let corners: [CGPoint] = [
            CGPoint(x: unshearedRect.origin.x + unshearedRect.origin.y * shear, y: unshearedRect.origin.y),
            CGPoint(x: unshearedRect.maxX + unshearedRect.origin.y * shear, y: unshearedRect.origin.y),
            CGPoint(x: unshearedRect.maxX + unshearedRect.maxY * shear, y: unshearedRect.maxY),
            CGPoint(x: unshearedRect.origin.x + unshearedRect.maxY * shear, y: unshearedRect.maxY)
        ]

        // Build CGPath from parallelogram vertices
        let path = CGPath { mutablePath, _ in
            mutablePath.move(to: corners[0])
            mutablePath.addLine(to: corners[1])
            mutablePath.addLine(to: corners[2])
            mutablePath.addLine(to: corners[3])
            mutablePath.closeSubpath()
        }

        let bounds = path.boundingRect
        let imgIdx = imageOrder?[i] ?? i
        panels.append(ImagePanel(imageIndex: imgIdx, geometry: .path(cgPath: path, boundingRect: bounds)))
    }

    return panels
}
```

**Note on gutter:** The gutter between diagonal bands is the perpendicular gap. The shear transform naturally creates the visual effect — the un-sheared gutter width translates to a perpendicular gap in the sheared result. May need adjustment based on visual testing.

### 2.3 Add Unit Tests

**File:** `CollageMakerTests/LayoutGeneratorTests.swift`

```swift
@Test func diagonalSlicesProducesPathGeometry() {
    let panels = LayoutGenerator.generate(numImages: 4, style: .diagonalSlices, sliceAngle: 45)
    #expect(panels.count == 4)
    for panel in panels {
        #expect(panel.geometry.cgPath != nil, "Panel should have CGPath geometry")
    }
}

@Test func diagonalSlicesCoversCanvas() {
    let panels = LayoutGenerator.generate(numImages: 3, style: .diagonalSlices, sliceAngle: 45)
    let canvas = CGRect(origin: .zero, size: SizeConstants.defaultCanvasSize)
    // All panel bounding rects should overlap with canvas
    for panel in panels {
        #expect(canvas.intersects(panel.frame))
    }
}

@Test func diagonalSlicesSingleImage() {
    let panels = LayoutGenerator.generate(numImages: 1, style: .diagonalSlices)
    #expect(panels.count == 1)
    #expect(panels[0].frame == CGRect(origin: .zero, size: SizeConstants.defaultCanvasSize))
}
```

### 2.4 Verify Build + Tests

```bash
bash script/build_and_run.sh --verify
xcodebuild test -project CollageMaker/CollageMaker.xcodeproj -scheme CollageMaker -destination 'platform=macOS,arch=arm64' -only-testing:CollageMakerTests
```

### 2.5 Manual Verification

- Select "Diagonal Slices" layout in the app
- Verify panels render as angled parallelogram strips
- Verify panel selection (tap) works via path hit testing
- Verify crop gestures work on diagonal panels
- Adjust `diagonalSliceAngle` and verify layout regenerates

---

## Phase 3: Hexagonal Strategy Implementation

**Goal:** Implement `HexagonalLayoutStrategy.generate()` to produce hexagonal panels in a honeycomb/radial pattern.

### 3.1 Geometry Algorithm

**Visual:** Center hexagon for image 0, surrounding ring of hexagons for remaining images.

**Approach:**
1. Compute hexagon size to fit the canvas with room for N images
2. Place center hexagon at canvas center
3. Place remaining hexagons in concentric rings using axial hex grid coordinates
4. Each hexagon is a regular hexagon (6 vertices) with `spacing` gap between neighbors

**Hexagon math:**
- Regular hexagon with radius R (center to vertex) has width `2*R` and height `sqrt(3)*R`
- Horizontal spacing between adjacent hex centers: `sqrt(3) * R + spacing`
- Vertical spacing between adjacent hex centers: `1.5 * R + spacing * 0.75`
- Vertices at angles 0°, 60°, 120°, 180°, 240°, 300° from center

**Ring placement:**
- Ring 0: 1 hexagon (center)
- Ring 1: 6 hexagons
- Ring 2: 12 hexagons
- Ring N: 6*N hexagons

For N images, place center + fill ring 1, ring 2, etc. until all images are placed.

### 3.2 Sizing

Compute hexagon radius so the honeycomb fits within the canvas:
- Estimate number of rings needed: `rings = ceil((sqrt(1 + 8*(numImages-1)) - 1) / 6)`
- Canvas width must accommodate `2 * rings + 1` hexagons horizontally
- `R = min(canvasWidth, canvasHeight) / (2 * rings + 1)` (rough approximation, refine with exact math)

### 3.3 Implementation

**File:** `Services/LayoutGenerator.swift`

Replace the stub `HexagonalLayoutStrategy.generate()` with:

```swift
func generate(numImages: Int, canvasSize: CGSize, gutter: CGFloat, imageOrder: [Int]?, mosaicSeed: UInt64?) -> [ImagePanel] {
    guard numImages > 0 else { return [] }

    if numImages == 1 {
        let imgIdx = imageOrder?[0] ?? 0
        return [ImagePanel(imageIndex: imgIdx, frame: CGRect(origin: .zero, size: canvasSize))]
    }

    let canvasCenter = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

    // Estimate rings needed
    let remaining = numImages - 1
    var ringsNeeded = 0
    var capacity = 0
    while capacity < remaining {
        ringsNeeded += 1
        capacity += 6 * ringsNeeded
    }

    // Compute hex radius to fit canvas
    let hexDiameter = 2.0 * sqrt(3.0) * CGFloat(ringsNeeded) + 1.0
    let R = min(canvasSize.width, canvasSize.height) / (hexDiameter + 2.0)

    let hexR = R
    let hexH = sqrt(3.0) * R
    let hSpacing = sqrt(3.0) * R + spacing
    let vSpacing = 1.5 * R + spacing * 0.5

    // Generate hexagon center positions
    var centers: [CGPoint] = [canvasCenter]

    // Ring placement using axial coordinates
    for ring in 1...ringsNeeded {
        // 6 directions for hexagonal grid
        let directions: [(Int, Int)] = [
            (ring, 0), (0, ring), (-ring, 0), (0, -ring),
            (ring, -ring), (-ring, ring)
        ]

        for (startQ, startR) in directions {
            var q = startQ
            var r = startR
            for _ in 0..<ring {
                let cx = canvasCenter.x + CGFloat(q) * hSpacing
                let cy = canvasCenter.y + CGFloat(r) * vSpacing
                centers.append(CGPoint(x: cx, y: cy))
                // Move to next direction
                switch directions.firstIndex(where: { $0 == (q, r) }) {
                case 0: (q, r) = (q - 1, r + 1)
                case 1: (q, r) = (q - 1, r)
                case 2: (q, r) = (q, r + 1)
                case 3: (q, r) = (q + 1, r)
                case 4: (q, r) = (q, r - 1)
                case 5: (q, r) = (q + 1, r - 1)
                default: break
                }
            }
        }
    }

    // Build panels
    var panels: [ImagePanel] = []
    for i in 0..<numImages {
        guard i < centers.count else { break }

        let center = centers[i]
        let path = createHexagonPath(center: center, radius: hexR)
        let bounds = path.boundingRect
        let imgIdx = imageOrder?[i] ?? i
        panels.append(ImagePanel(imageIndex: imgIdx, geometry: .path(cgPath: path, boundingRect: bounds)))
    }

    return panels
}

private func createHexagonPath(center: CGPoint, radius: CGFloat) -> CGPath {
    CGPath { mutablePath, _ in
        for i in 0..<6 {
            let angle = .pi / 6.0 + .pi / 3.0 * CGFloat(i)
            let x = center.x + radius * cos(angle)
            let y = center.y + radius * sin(angle)
            if i == 0 {
                mutablePath.move(to: CGPoint(x: x, y: y))
            } else {
                mutablePath.addLine(to: CGPoint(x: x, y: y))
            }
        }
        mutablePath.closeSubpath()
    }
}
```

**Note:** The axial coordinate traversal above is a starting point. The exact ring-filling algorithm may need refinement to produce a visually pleasing honeycomb. Alternative: use a simpler approach — center hex, then place remaining hexagons in a spiral or concentric rings with explicit angle computation.

**Simpler alternative algorithm:**
```swift
// Place center hex
centers.append(canvasCenter)

// Place remaining in rings
var angle = -Double.pi / 2.0 // Start from top
var ringRadius = hSpacing
var placed = 1

while placed < numImages {
    let hexesInRing = min(6 * Int(round(ringRadius / hSpacing)), numImages - placed)
    for _ in 0..<hexesInRing {
        if placed >= numImages { break }
        let x = canvasCenter.x + ringRadius * cos(angle)
        let y = canvasCenter.y + ringRadius * sin(angle)
        centers.append(CGPoint(x: x, y: y))
        angle += (2.0 * .pi) / Double(hexesInRing)
        placed += 1
    }
    ringRadius += hSpacing
}
```

**Recommendation:** Start with the simpler concentric ring approach, then refine to proper hex grid if needed.

### 3.4 Extract `createHexagonPath` as Helper

Move `createHexagonPath` to a file-level private function in `LayoutGenerator.swift` (or a `HexagonGeometry` helper struct) to keep the strategy clean.

### 3.5 Add Unit Tests

**File:** `CollageMakerTests/LayoutGeneratorTests.swift`

```swift
@Test func hexagonalProducesPathGeometry() {
    let panels = LayoutGenerator.generate(numImages: 7, style: .hexagonal, hexSpacing: 8)
    #expect(panels.count == 7)
    for panel in panels {
        #expect(panel.geometry.cgPath != nil)
    }
}

@Test func hexagonalFirstPanelIsCenter() {
    let canvas = CGRect(origin: .zero, size: SizeConstants.defaultCanvasSize)
    let center = CGPoint(x: canvas.midX, y: canvas.midY)
    let panels = LayoutGenerator.generate(numImages: 7, style: .hexagonal, hexSpacing: 8)
    let firstPanel = panels[0]
    #expect(abs(firstPanel.frame.midX - center.x) < 10)
    #expect(abs(firstPanel.frame.midY - center.y) < 10)
}

@Test func hexagonalSingleImage() {
    let panels = LayoutGenerator.generate(numImages: 1, style: .hexagonal)
    #expect(panels.count == 1)
    #expect(panels[0].frame == CGRect(origin: .zero, size: SizeConstants.defaultCanvasSize))
}
```

### 3.6 Verify Build + Tests

```bash
bash script/build_and_run.sh --verify
xcodebuild test -project CollageMaker/CollageMaker.xcodeproj -scheme CollageMaker -destination 'platform=macOS,arch=arm64' -only-testing:CollageMakerTests
```

### 3.7 Manual Verification

- Select "Hexagonal" layout
- Verify center hexagon + surrounding ring render correctly
- Verify panel selection works via path hit testing
- Adjust `hexagonalSpacing` and verify layout regenerates
- Test with 1, 2, 7, 13 images (1 center + ring 1, 1 center + 2 rings)

---

## Phase 4: Double Exposure Polish

**Goal:** Ensure double exposure works end-to-end. The layout strategy is already correct (uniform grid + canvas-wide overlay). Remaining work is mask image persistence and UI for mask selection.

### 4.1 Persist `doubleExposureMaskImage`

**File:** `Services/UserDefaultsPersistence.swift`

**Add key (line 49):**
```swift
static let doubleExposureMaskImagePath = "doubleExposureMaskImagePath"
```

**In `save()` (after line 87):**
```swift
if let path = viewModel.doubleExposureMaskImagePath {
    defaults.set(path, forKey: Keys.doubleExposureMaskImagePath)
} else {
    defaults.removeObject(forKey: Keys.doubleExposureMaskImagePath)
}
```

**In `load()` — add to `PersistenceBundle`:**
```swift
let doubleExposureMaskImagePath: String?
```

### 4.2 Add `doubleExposureMaskImagePath` Property to ViewModel

**File:** `ViewModel/CollageViewModel.swift`

Add computed property or stored property:
```swift
var doubleExposureMaskImagePath: String? {
    didSet {
        guard !isInitializing else { return }
        if let path = doubleExposureMaskImagePath {
            doubleExposureMaskImage = NSImage(contentsOfFile: path)
        } else {
            doubleExposureMaskImage = nil
        }
        updatePreview()
    }
}
```

### 4.3 Verify Build + Tests

```bash
bash script/build_and_run.sh --verify
```

---

## Phase 5: CropInfo Persistence Fix

**Goal:** Address the lossy `CropInfo` Codable that drops path geometry. Strategy: regenerate panel geometry from layout style + parameters on app load (Option A from review).

### 5.1 Verify Current Behavior

The ViewModel already calls `regenerateLayout()` during initialization after loading persisted state. This means:
1. `UserDefaultsPersistence.load()` returns style, params, etc.
2. ViewModel applies loaded values
3. `layoutStyle.didSet` → `regenerateLayout()` → `LayoutGenerator.generate(...)` → fresh panel geometry

**If this flow is already correct, no changes needed.** The `CropInfo` Codable lossiness is a non-issue because we regenerate panels on load anyway.

### 5.2 Verify the Load Flow

**File:** `ViewModel/CollageViewModel.swift`

Check the initialization flow:
1. `init()` loads `PersistenceBundle` from `persistence.load()`
2. Applies bundle values to properties
3. `layoutStyle = bundle.layoutStyle` triggers `didSet` → `regenerateLayout()`
4. `regenerateLayout()` calls `LayoutGenerator.generate()` with current style + params
5. Fresh panels with correct geometry are created

**If this is the existing flow, mark Phase 5 as "Verified — no changes needed."**

### 5.3 If Load Flow Needs Fixing

If `regenerateLayout()` is NOT called during init (e.g., `isInitializing` guard suppresses it), add explicit call:

```swift
// After loading all properties in init:
isInitializing = false
regenerateLayout()
```

### 5.4 Verify Build + Tests

```bash
bash script/build_and_run.sh --verify
xcodebuild test -project CollageMaker/CollageMaker.xcodeproj -scheme CollageMaker -destination 'platform=macOS,arch=arm64' -only-testing:CollageMakerTests
```

---

## Phase 6: Sidebar Panel Preview Path Clipping (Optional Polish)

**Goal:** Update `CollageAssembler.renderPanel()` to clip to path geometry, so sidebar crop preview shows the actual panel shape rather than a rectangle.

### 6.1 Update `renderPanel()`

**File:** `Services/CollageAssembler.swift`

**Current (line 364-392):**
```swift
func renderPanel(crop: CropInfo, cgImage: CGImage, panelSize: CGSize) async -> NSImage? {
    // ... clips to destRect only ...
}
```

**New:** Add path clipping from `crop.destination`:

```swift
    context.saveGState()

    if let clipPath = crop.destination.cgPath,
       case .path = crop.destination {
        // Translate path to preview origin
        var t = CGAffineTransform(translationX: -crop.destinationRect.origin.x, y: -crop.destinationRect.origin.y)
        if let translated = clipPath.copy(using: &t) {
            context.addPath(translated)
            context.clip()
        } else {
            context.clip(to: destRect)
        }
    } else {
        context.clip(to: destRect)
    }
```

**Design decision:** This is a polish item. The sidebar preview is small, and rectangular preview is functional. Only implement if time permits.

### 6.2 Verify Build + Tests

```bash
bash script/build_and_run.sh --verify
xcodebuild test -project CollageMaker/CollageMaker.xcodeproj -scheme CollageMaker -destination 'platform=macOS,arch=arm64' -only-testing:CollageMakerTests
```

---

## Verification Checklist

After all phases complete:

### Automated
- [ ] `xcodebuild build` — zero errors, zero warnings
- [ ] `xcodebuild test` — all existing tests pass + new strategy tests pass

### Manual — Diagonal Slices
- [ ] Select "Diagonal Slices" in sidebar — panels render as parallelogram strips
- [ ] Adjust slice angle slider — layout regenerates with new angle
- [ ] Tap a panel — selection highlight follows parallelogram shape
- [ ] Pinch/pan crop gesture — works on diagonal panels
- [ ] Export — PNG shows diagonal strip layout with proper clipping
- [ ] Add/remove images — layout adjusts correctly

### Manual — Hexagonal
- [ ] Select "Hexagonal" in sidebar — panels render as hexagons in honeycomb
- [ ] Center hex is image 0, surrounding hexes are remaining images
- [ ] Adjust hex spacing — layout regenerates with new spacing
- [ ] Tap a hexagon — selection highlight follows hex shape
- [ ] Pinch/pan crop gesture — works on hexagonal panels
- [ ] Export — PNG shows hexagonal layout with proper clipping
- [ ] Test with 1, 2, 7, 13 images

### Manual — Double Exposure
- [ ] Select "Double Exposure" — uniform grid renders
- [ ] Load mask image — overlay appears on top of panels
- [ ] Adjust mask opacity — overlay blends correctly
- [ ] Export — PNG includes overlay
- [ ] Close and reopen app — mask image persists

### Regression
- [ ] Uniform, Hero, Mosaic layouts render identically to before
- [ ] All crop gestures work for existing layouts
- [ ] Image drag-swap works for all layouts
- [ ] Undo/redo works for layout changes and style param changes
- [ ] Save/load cycle preserves all settings

---

## Files Changed Summary

| File | Phase | Changes |
|------|-------|---------|
| `Services/LayoutGenerator.swift` | 1, 2, 3 | Configured factory; diagonal + hexagonal algorithms; hexagon helper |
| `ViewModel/CollageViewModel.swift` | 1, 4 | Pass style params to generator; `didSet` regeneration; mask path property |
| `Services/UserDefaultsPersistence.swift` | 4 | Mask image path key, save/load |
| `CollageMakerTests/LayoutGeneratorTests.swift` | 2, 3 | Strategy tests for diagonal and hexagonal |

**Total:** 0 new files, 4 modified files.

---

## Rollback Plan

- Phase 1: Revert `makeStrategy()` to parameterless, revert `LayoutGenerator.generate()` signature, revert `CollageViewModel` call site
- Phase 2: Revert `DiagonalSlicesLayoutStrategy` to stub
- Phase 3: Revert `HexagonalLayoutStrategy` to stub, remove hexagon helper
- Phase 4: Remove mask path persistence
- Phase 5: No changes to revert (verification only)
- Phase 6: Revert `renderPanel()` to rect-only clipping

---

## Risks and Mitigations

| Risk | Phase | Mitigation |
|------|-------|------------|
| Shear transform produces panels outside canvas bounds | 2 | Clip parallelogram vertices to canvas rect; use `CGPath.boundingRect` for panel frame |
| Hexagonal ring placement produces overlapping hexagons | 3 | Use proper hex grid axial coordinates; verify with visual testing |
| `CGPath` coordinate system: CG bottom-left vs NSImage top-left | 2, 3 | `CollageAssembler` draws into CGContext (bottom-left origin). Verify diagonal/hex panels render upright |
| Panel hit testing misses edge clicks on thin diagonal bands | 2 | `cgPath.contains()` is exact — should work. May need to widen paths slightly for usability |
| Performance: many hexagons with complex hit testing | 3 | Two-pass hit testing (bounding rect first, then path) already in place |
| `diagonalSliceAngle` / `hexagonalSpacing` changes trigger expensive regeneration | 1 | Use `updatePreviewDebounced()` pattern for param changes, not immediate regeneration |
