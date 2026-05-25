# New Layout Styles + Double Exposure Overlay Plan

## Change Request

Add three new layout capabilities:
1. **Double Exposure** — silhouette mask overlay on any existing layout
2. **Diagonal Slices** — parallelogram panels with angled clipping
3. **Hexagonal** — radial honeycomb panel arrangement with hex clipping

## Architecture Decisions

### PanelShape Enum (not CGPath on ImagePanel)

New `PanelShape` enum describes shapes declaratively. `CGPath` is derived at render time.

```swift
enum PanelShape: Codable, Equatable {
    case rectangle
    case hexagon
    case parallelogram(angle: CGFloat)

    func cgPath(in rect: CGRect) -> CGPath
}
```

Keeps `ImagePanel` Codable, decouples layout geometry from model, and makes shape testable.

### Double Exposure → Overlay Feature (not a LayoutStyle)

Double exposure is a toggle + mask picker next to the layout picker, not a layout style case. This lets the user apply a silhouette mask to any layout (uniform, hero, mosaic, or future styles).

```
Sidebar:
  Layout:  [ Hero ▼ ]
  [x] Double Exposure
      Mask: [ Choose Image... ]   ← appears when toggle is on
```

Mask composites with `.sourceIn` blend mode, drawing the mask image as the final layer.

### Diagonal Slice Angle

Fixed at 60 degrees for now. Can be parameterized later if needed.

### Hexagonal Density

Scales with number of images — center image + surrounding rings fill outward.

---

## Phase 1: Foundations (Shape-Aware Panels)

**Goal:** Enable non-rectangular panel clipping without changing anything visible.

### 1.1 `Models/PanelShape.swift` — New file

```swift
enum PanelShape: Codable, Equatable {
    case rectangle
    case hexagon
    case parallelogram(angle: CGFloat)

    func cgPath(in rect: CGRect) -> CGPath
}
```

- `rectangle` → `CGPath(rect:)`
- `hexagon` → 6-point polygon inscribed in rect
- `parallelogram(angle:)` → sheared 4-point polygon

### 1.2 `Models/ImagePanel.swift` — Add shape property

```swift
struct ImagePanel: Identifiable, Equatable {
    let id: UUID
    let imageIndex: Int
    let frame: CGRect
    var shape: PanelShape = .rectangle   // NEW
}
```

Default `.rectangle` ensures zero visual change for existing layouts.

### 1.3 `Services/CollageAssembler.swift` — Shape-aware clipping

In `drawPanels`, replace:

```swift
context.clip(to: destRect)
```

with:

```swift
context.clip(mask: panel.shape.cgPath(in: destRect))
```

For `.rectangle`, `cgPath(in:)` returns `CGPath(rect:)` — identical behavior.

### 1.4 `Services/LayoutGenerator.swift` — Emit `.rectangle` by default

Existing generators create panels with default `.rectangle` shape. No algorithm changes.

### 1.5 Tests

**New file: `CollageMakerTests/PanelShapeTests.swift`** (`@Suite(.serialized)`)

- `rectangle cgPath bounds`: `cgPath(in: rect)` bounding box equals the input rect
- `hexagon cgPath bounds`: bounding box fits within input rect, path has exactly 6 vertices
- `parallelogram cgPath bounds`: bounding box fits within input rect, path has exactly 4 vertices, shear angle is `.pi/3`

**Updated: `CollageMakerTests/CollageAssemblerTests.swift`**

- **Regression — clip isolation**: Assemble 2+ panels with different shapes; verify each panel's clip path doesn't leak into the next. (Bug: `saveGState`/`restoreGState` was once missing, causing clip state to propagate between panels.)
- **Regression — upright rendering**: Assemble panels with `.hexagon` and `.parallelogram` shapes using a known asymmetric test image; verify output image is not upside-down. (Bug: CGContext Y-flip was once applied manually, inverting rendered images.)
- **Regression — existing layouts unchanged**: Run existing uniform/hero/mosaic assembler tests; assert non-nil output, correct preview dimensions, and non-zero byte count (no change expected since default shape is `.rectangle`).
- **Mock protocol sync**: Update `MockAssembler` / `TrackingAssembler` to accept `panelAssignments` and any new `AssemblyConfig` fields. (Bug: mock previously used `title: String` instead of `titleAttrString: NSAttributedString`, blocking the full suite.)

### Verification

Build, run, confirm all existing layouts (uniform/hero/mosaic) look identical. All existing assembler tests pass.

---

## Phase 2: Double Exposure Overlay

**Goal:** User can toggle a silhouette mask overlay on any layout.

### 2.1 `CollageViewModel` — New state

```swift
var doubleExposure: Bool = false {
    didSet { persist + regenerate preview }
}

var maskImage: NSImage? {
    didSet { persist path + regenerate preview }
}
```

UserDefaults keys: `doubleExposure`, `maskImagePath` (same persistence pattern as `backgroundImage`).

### 2.2 `Models/AssemblyConfig.swift` — Add mask field

```swift
let maskImage: CGImage?
```

### 2.3 `Services/CollageAssembler.swift` — Mask compositing layer

After drawing all panels:

```swift
if let mask = config.maskImage {
    context.setBlendMode(.sourceIn)
    context.draw(mask, in: canvasRect)
    context.setBlendMode(.normal)
}
```

### 2.4 `ContentView.swift` sidebar — Toggle + picker

Below the layout picker, add:

- `Toggle("Double Exposure", isOn: $viewModel.doubleExposure)`
- When on: file picker button to choose mask image (same pattern as background image picker in `ExportPanel`)

### 2.5 `CollageCommands.swift` — No new command

It's a sidebar toggle, not a layout switch.

### 2.6 Tests

**Updated: `CollageMakerTests/CollageViewModelTests.swift`**

- **Regression — UserDefaults safe defaults**: Create a fresh `CollageViewModel` with clean `UserDefaults` (no prior keys). Verify `doubleExposure == false` and `maskImage == nil`. (Bug: `UserDefaults.bool(forKey:)` returns `false` and `.double(forKey:)` returns `0.0` for missing keys — the safe pattern is `UserDefaults.standard.object(forKey:) != nil` before reading.)
- **Preview refresh on toggle**: Set `doubleExposure = true` with a mock assembler; verify `TrackingAssembler.previewCalls` incremented. (Bug: `backgroundOpacity`'s `didSet` once persisted but never called `updatePreview()`, leaving the preview stale.)
- **Preview refresh on mask change**: Set `maskImage` to a test image; verify `TrackingAssembler.previewCalls` incremented.
- **Mask image CGImage extraction**: Verify that `AssemblyConfig.maskImage` passed to the assembler is a non-nil `CGImage` when a mask is set. (Bug: `NSImage.cgImage(forProposedRect:)` called on a background thread silently returns `nil`.)

**New file: `CollageMakerTests/DoubleExposureTests.swift`** (`@Suite(.serialized)`)

- **Mask compositing produces output**: Assemble with a mask image; verify non-nil, non-empty output data.
- **Blend mode restored after mask**: Assemble with a mask followed by panels; verify subsequent draw operations use `.normal` blend mode (no `.sourceIn` leakage).

### Verification

Build, run, pick any layout, toggle double exposure, choose mask image, verify silhouette composites correctly. All Phase 2 tests pass.

---

## Phase 3: Diagonal Slices Layout

**Goal:** Angled parallelogram panels with gutter gaps.

### 3.1 `LayoutStyle` — New case

```swift
case diagonalSlices

// title: "Diagonal Slices"
// icon: "line.3.horizontal.decrease"
```

### 3.2 `LayoutGenerator.generateDiagonalSlices`

- Fixed angle: 60 degrees (π/3 radians)
- Divide canvas into N diagonal strips based on image count
- Each panel gets bounding `CGRect` + `.parallelogram(angle: .pi/3)` shape
- Gutter: parallel gaps between slices

### 3.3 `Views/PanelCropEditor.swift` — Parallelogram preview

Update crop preview to render the parallelogram shape path instead of a rect. Use the eoFill cutout pattern from `swiftui-overlays.md`.

### 3.4 `CollageCommands.swift` — Menu item

```swift
Button("Diagonal Slices") { viewModel.layoutStyle = .diagonalSlices }
    .keyboardShortcut("4", modifiers: .command)
```

### 3.5 Tests

**Updated: `CollageMakerTests/LayoutGeneratorTests.swift`**

- `diagonalSlices panel count`: For N images, `generateDiagonalSlices` returns exactly N panels (no silent drop). (Bug: `generateMosaic` once capped at 12 panels, silently discarding remaining images.)
- `diagonalSlices shape assignment`: Every returned panel has `shape == .parallelogram(angle: .pi/3)`.
- `diagonalSlices bounds`: Every panel frame is within `CanvasConfig.defaultCanvasSize` (with small tolerance for gutter rounding).
- `diagonalSlices gutter impact`: Panels shrink when gutter increases (same pattern as existing mosaic test).
- `diagonalSlices single image`: Generate with 1 image; verify 1 panel is returned without crash. (Bug: `buildMoveMapping` once fataled on single-element closed range `(a+1)...a`.)

**Updated: `CollageMakerTests/CollageViewModelTests.swift`**

- `setLayoutStyle(.diagonalSlices)` triggers preview: Set layout to `.diagonalSlices`; verify `TrackingAssembler.previewCalls` incremented and `lastPreviewPanels` all have `.parallelogram` shape. (Bug: Picker binding once bypassed `setLayoutStyle(_:)` which calls `regenerateLayout()`.)

**Updated: `CollageMakerTests/CollageAssemblerTests.swift`**

- **Regression — parallelogram clip isolation**: Assemble 2+ parallelogram panels; verify each panel's output is clipped independently. (Bug: `saveGState`/`restoreGState` was once missing.)
- **Regression — parallelogram upright rendering**: Assemble parallelogram panels with an asymmetric test image; verify output is not upside-down. (Bug: manual CGContext Y-flip inverted images.)

### Verification

Build, run, verify angled panels render with correct clipping and gutters. All Phase 3 tests pass.

---

## Phase 4: Hexagonal Layout

**Goal:** Radial honeycomb arrangement with hexagonal panel clipping.

### 4.1 `LayoutStyle` — New case

```swift
case hexagonal

// title: "Hexagonal"
// icon: "hexagon.fill"
```

### 4.2 `LayoutGenerator.generateHexagonal`

- Image 0 centered on canvas
- Remaining images positioned using trigonometry in concentric rings
- Ring count scales with number of images
- Each panel gets `.hexagon` shape
- Gutter: gaps between hexagons

### 4.3 `Views/PanelCropEditor.swift` — Hexagon preview

Update crop preview to render the hexagon shape path.

### 4.4 `CollageCommands.swift` — Menu item

```swift
Button("Hexagonal") { viewModel.layoutStyle = .hexagonal }
    .keyboardShortcut("5", modifiers: .command)
```

### 4.5 Tests

**Updated: `CollageMakerTests/LayoutGeneratorTests.swift`**

- `hexagonal panel count`: For N images (1, 2, 7, 19, 37), `generateHexagonal` returns exactly N panels (no silent drop). (Bug: `generateMosaic` once capped at 12 panels, silently discarding remaining images.)
- `hexagonal shape assignment`: Every returned panel has `shape == .hexagon`.
- `hexagonal center panel`: Image 0 is centered on canvas (frame origin + half-width ≈ canvas center, within tolerance).
- `hexagonal ring placement`: For 7 images, verify 1 center + 6 surrounding panels. For 19 images, verify 1 + 6 + 12 ring structure.
- `hexagonal bounds`: Every panel frame is within `CanvasConfig.defaultCanvasSize` (with tolerance for overlap). (Risk: hexagonal layout overflows canvas for large image counts.)
- `hexagonal gutter impact`: Panel spacing increases when gutter increases.
- `hexagonal single image`: Generate with 1 image; verify 1 centered panel is returned without crash. (Bug: `buildMoveMapping` once fataled on single-element moves.)

**Updated: `CollageMakerTests/CollageViewModelTests.swift`**

- `setLayoutStyle(.hexagonal)` triggers preview: Set layout to `.hexagonal`; verify `TrackingAssembler.previewCalls` incremented and `lastPreviewPanels` all have `.hexagon` shape. (Bug: Picker binding once bypassed `setLayoutStyle(_:)`.)

**Updated: `CollageMakerTests/CollageAssemblerTests.swift`**

- **Regression — hexagon clip isolation**: Assemble 2+ hexagon panels; verify each panel's output is clipped independently. (Bug: `saveGState`/`restoreGState` was once missing.)
- **Regression — hexagon upright rendering**: Assemble hexagon panels with an asymmetric test image; verify output is not upside-down. (Bug: manual CGContext Y-flip inverted images.)

### Verification

Build, run, verify hexagonal panels arrange radially with correct clipping. All Phase 4 tests pass.

---

## Files Affected Summary

| File | Phase | Change |
|------|-------|--------|
| `Models/PanelShape.swift` | 1 | **New file** |
| `Models/ImagePanel.swift` | 1 | Add `shape` property |
| `Models/LayoutStyle.swift` | 3, 4 | Add `.diagonalSlices`, `.hexagonal` |
| `Models/AssemblyConfig.swift` | 2 | Add `maskImage` field |
| `ViewModel/CollageViewModel.swift` | 2 | Add `doubleExposure`, `maskImage` state |
| `Services/CollageAssembler.swift` | 1, 2 | Shape clipping + mask layer |
| `Services/LayoutGenerator.swift` | 1, 3, 4 | Emit shapes, new algorithms |
| `Views/PanelCropEditor.swift` | 3, 4 | Shape-aware crop preview |
| `ContentView.swift` | 2 | Toggle + mask picker |
| `Views/CollageCommands.swift` | 3, 4 | Menu items |
| `Tests/PanelShapeTests.swift` | 1 | **New file** |
| `Tests/DoubleExposureTests.swift` | 2 | **New file** |
| `Tests/CollageAssemblerTests.swift` | 1, 2, 3, 4 | Regression tests (clip isolation, upright rendering) |
| `Tests/CollageViewModelTests.swift` | 2, 3, 4 | UserDefaults defaults, preview refresh, layout triggers |
| `Tests/LayoutGeneratorTests.swift` | 3, 4 | Panel count, shape assignment, bounds, edge cases |

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| `CGPath` for parallelogram clips too aggressively | Verify with debug rendering, adjust bounding box math |
| Double exposure mask blend mode doesn't match expected look | Start with `.sourceIn`, iterate based on visual feedback |
| Hexagonal layout overflows canvas for large image counts | Clamp panel frames to canvas bounds, allow slight overlap |
| Crop editor shape preview is complex for non-rect shapes | Start with shape outline overlay, refine interaction later |
| New tests create CGImages and race on `NSGraphicsContext.current` | Annotate new test suites with `@Suite(.serialized)` |
| Mock assembler protocol drifts from real interface | Update `MockAssembler`/`TrackingAssembler` in each phase before running tests |
