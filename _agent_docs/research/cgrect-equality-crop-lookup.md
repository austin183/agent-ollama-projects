# CGRect Equality and CGFloat Precision — Crop Lookup Strategies

## The Problem

`LayoutGenerator` produces panel frames with computed `CGFloat` values through division and arithmetic. When looking up a crop by `destinationRect`, floating-point precision errors can cause `CGRect` equality checks to fail:

```swift
// This may return nil due to precision errors
let index = crops.firstIndex(where: { $0.destinationRect == panel.frame })
```

## CGRect Equality

### `==` Operator

`CGRect` conforms to `Equatable` via Swift's auto-synthesis. The `==` operator compares all four `CGFloat` components (`origin.x`, `origin.y`, `width`, `height`) for exact equality.

### `equalTo(_:)` Method

`CGRect.equalTo(CGRect) -> Bool` performs the same exact equality check. There is no tolerance-based comparison in the standard API.

### `integral` Property

`CGRect.integral` returns a new rect with rounded origin and expanded size to whole numbers:

```swift
let precise = CGRect(x: 10.333333, y: 20.666667, width: 100.5, height: 200.3)
let rounded = precise.integral  // CGRect(x: 10, y: 20, width: 101, height: 201)
```

**Not suitable for crop lookup** — rounding changes the actual frame dimensions.

## Sources of Precision Error

### LayoutGenerator Division

```swift
let columnWidth = (canvasWidth - totalGutterWidth) / CGFloat(columns)
let rowHeight = (canvasHeight - totalGutterHeight) / CGFloat(rows)
```

When `canvasWidth = 1920` and `columns = 3`:
- `columnWidth = 640.0` (exact)

When `columns = 7`:
- `columnWidth = 1920 / 7 = 274.2857142857143` (repeating decimal)

Cumulative errors when computing positions:
```swift
let x = gutter + columnWidth * CGFloat(colIndex)
// For colIndex = 6: 8 + 274.2857142857143 * 6 = 1653.7142857142858
// May differ from expected 1653.7142857142857 by 1 ULP
```

### CGFloat Representation

`CGFloat` is `Double` (64-bit) on macOS. Double precision has ~15-17 significant decimal digits. Errors accumulate through:
- Division of non-divisible numbers
- Addition of values with different magnitudes
- Multiplication followed by addition

## Solutions

### Solution 1: Use `panel.id` for Crop Lookup (Recommended)

Add `panelId` to `CropInfo`:

```swift
struct CropInfo: Codable, Equatable {
    let panelId: UUID          // <-- Link to panel
    let sourceRect: CGRect     // Region within the original image
    let destinationRect: CGRect // Position on the canvas
}
```

Lookup becomes O(1) with no precision issues:
```swift
let index = crops.firstIndex(where: { $0.panelId == panel.id })
```

**Pros:**
- No floating-point comparison
- O(1) lookup (or O(n) with `firstIndex`, but reliable)
- Survives layout changes (panel.frame may change, but panel.id doesn't)

**Cons:**
- Requires modifying `CropInfo` struct
- Need to update all crop creation code to include `panelId`

### Solution 2: Epsilon-Based CGRect Comparison

```swift
extension CGRect {
    func approximatelyEquals(_ other: CGRect, within epsilon: CGFloat = 0.01) -> Bool {
        return abs(origin.x - other.origin.x) < epsilon
            && abs(origin.y - other.origin.y) < epsilon
            && abs(size.width - other.size.width) < epsilon
            && abs(size.height - other.size.height) < epsilon
    }
}
```

Usage:
```swift
let index = crops.firstIndex(where: {
    $0.destinationRect.approximatelyEquals(panel.frame, within: 0.01)
})
```

**Pros:**
- No model changes needed
- Configurable tolerance

**Cons:**
- Epsilon choice is arbitrary (0.01? 0.1?)
- O(n) linear search
- May match wrong panel if frames are close
- Doesn't help when panels are reordered

### Solution 3: Round CGRect Values in LayoutGenerator

```swift
// In LayoutGenerator.generate()
let frame = CGRect(
    x: roundToNearestPixel(x),
    y: roundToNearestPixel(y),
    width: roundToNearestPixel(width),
    height: roundToNearestPixel(height)
)

private func roundToNearestPixel(_ value: CGFloat) -> CGFloat {
    return round(value * 100) / 100  // Round to 2 decimal places
}
```

**Pros:**
- Ensures consistent precision across all generated frames
- `==` comparison works after rounding

**Cons:**
- Rounding introduces visual artifacts if not careful
- 2 decimal places may not be enough for all layouts
- Need to round both in generation and in crop creation

### Solution 4: Dictionary-Based Crop Storage

Change `crops: [CropInfo]` to `cropMap: [UUID: CropInfo]`:

```swift
@Published private(set) var cropMap: [UUID: CropInfo] = [:]

func updateCrop(panelId: UUID, sourceRect: CGRect, destinationRect: CGRect) {
    cropMap[panelId] = CropInfo(
        panelId: panelId,
        sourceRect: sourceRect,
        destinationRect: destinationRect
    )
    objectWillChange.send()
}

func crop(for panelId: UUID) -> CropInfo? {
    return cropMap[panelId]
}
```

**Pros:**
- O(1) lookup by panel ID
- Clean API
- No precision issues

**Cons:**
- Breaking change to existing code
- Need to iterate values for assembly (minor)

## Recommendation

**Use Solution 1 (panelId in CropInfo) combined with Solution 4 (Dictionary storage).**

This is the most robust approach:
1. Add `panelId: UUID` to `CropInfo`
2. Change `crops: [CropInfo]` to `cropMap: [UUID: CropInfo]` in `CollageViewModel`
3. All crop operations use `panelId` as the key
4. No floating-point comparison needed

### Implementation Sketch

```swift
// Models/ImagePanel.swift — add to CropInfo
struct CropInfo: Codable, Equatable {
    let panelId: UUID
    let sourceRect: CGRect
    let destinationRect: CGRect
}

// ViewModel/CollageViewModel.swift
@Published private(set) var cropMap: [UUID: CropInfo] = [:]

func applyDefaultCrops() {
    for panel in panels {
        let saliency = saliencyResults[panel.id]
        cropMap[panel.id] = CropInfo(
            panelId: panel.id,
            sourceRect: saliency?.cropRect ?? defaultCropRect,
            destinationRect: panel.frame
        )
    }
}

func panCrop(panelId: UUID, by delta: CGSize) {
    guard var crop = cropMap[panelId] else { return }
    let newOrigin = CGPoint(
        x: clamp(crop.sourceRect.origin.x + delta.width,
                 min: 0, max: maxSourceX(panelId)),
        y: clamp(crop.sourceRect.origin.y + delta.height,
                 min: 0, max: maxSourceY(panelId))
    )
    cropMap[panelId] = CropInfo(
        panelId: panelId,
        sourceRect: CGRect(origin: newOrigin, size: crop.sourceRect.size),
        destinationRect: crop.destinationRect
    )
    updatePreview()
}
```

## CGRect Utility Methods (Reference)

| Method | Purpose |
|---|---|
| `contains(_ point: CGPoint) -> Bool` | Point-in-rect test |
| `contains(_ rect: CGRect) -> Bool` | Rect containment |
| `intersects(_ rect: CGRect) -> Bool` | Overlap detection |
| `intersection(_ rect: CGRect) -> CGRect` | Overlapping region |
| `insetBy(dx:dy:) -> CGRect` | Shrink/expand rect |
| `offsetBy(dx:dy:) -> CGRect` | Translate rect |

These are useful for panel hit testing and overlap detection in tests.
