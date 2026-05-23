# CGRect Equality and CGFloat Precision — Crop Lookup Strategies

## The Problem

`LayoutGenerator` produces panel frames with computed `CGFloat` values through division and arithmetic. `CGRect ==` compares all four components for exact equality. Floating-point precision errors cause lookups to fail:

```swift
// May return nil due to precision errors
let index = crops.firstIndex(where: { $0.destinationRect == panel.frame })
```

## Sources of Precision Error

### LayoutGenerator Division

```swift
let columnWidth = (canvasWidth - totalGutterWidth) / CGFloat(columns)
// columns = 7: 1920 / 7 = 274.2857142857143 (repeating decimal)
// Cumulative: 274.2857142857143 * 6 = 1653.7142857142858
// May differ from expected by 1 ULP
```

`CGFloat` is `Double` (64-bit) on macOS with ~15-17 significant digits. Errors accumulate through division of non-divisible numbers and multiplication followed by addition.

## Solutions

### Solution 1: Use `panelId` for Crop Lookup (Recommended)

Add `panelId: UUID` to `CropInfo`:

```swift
struct CropInfo: Codable, Equatable {
    let panelId: UUID          // Link to panel
    let sourceRect: CGRect     // Region within the original image
    let destinationRect: CGRect // Position on the canvas
}
```

Lookup with no precision issues:
```swift
let index = crops.firstIndex(where: { $0.panelId == panel.id })
```

**Pros:** No floating-point comparison, survives layout changes, O(n) reliable lookup.

### Solution 2: Dictionary-Based Crop Storage

Change `crops: [CropInfo]` to `cropMap: [UUID: CropInfo]`:

```swift
@Published private(set) var cropMap: [UUID: CropInfo] = [:]

func updateCrop(panelId: UUID, sourceRect: CGRect, destinationRect: CGRect) {
    cropMap[panelId] = CropInfo(
        panelId: panelId,
        sourceRect: sourceRect,
        destinationRect: destinationRect
    )
}

func crop(for panelId: UUID) -> CropInfo? {
    cropMap[panelId]  // O(1) lookup
}
```

**Pros:** O(1) lookup, clean API, `@Published` fires on dictionary assignment.

### Solution 3: Epsilon-Based Comparison (Fallback)

```swift
extension CGRect {
    func approximatelyEquals(_ other: CGRect, within epsilon: CGFloat = 0.01) -> Bool {
        abs(origin.x - other.origin.x) < epsilon
            && abs(origin.y - other.origin.y) < epsilon
            && abs(size.width - other.size.width) < epsilon
            && abs(size.height - other.size.height) < epsilon
    }
}
```

**Cons:** Epsilon is arbitrary, may match wrong panel if frames are close.

## Recommendation

**Use Solution 1 (panelId in CropInfo) combined with Solution 2 (Dictionary storage).**

```swift
// Models/ImagePanel.swift
struct CropInfo: Codable, Equatable {
    let panelId: UUID
    let sourceRect: CGRect
    let destinationRect: CGRect
}

// ViewModel
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
        x: clamp(crop.sourceRect.origin.x + delta.width, min: 0, max: maxSourceX(panelId)),
        y: clamp(crop.sourceRect.origin.y + delta.height, min: 0, max: maxSourceY(panelId))
    )
    cropMap[panelId] = CropInfo(
        panelId: panelId,
        sourceRect: CGRect(origin: newOrigin, size: crop.sourceRect.size),
        destinationRect: crop.destinationRect
    )
}
```

## CGRect Utility Methods

| Method | Purpose |
|---|---|
| `contains(_ point: CGPoint)` | Point-in-rect hit test |
| `contains(_ rect: CGRect)` | Rect containment |
| `intersects(_ rect: CGRect)` | Overlap detection |
| `intersection(_ rect: CGRect)` | Overlapping region |
| `insetBy(dx:dy:)` | Shrink/expand rect |
| `offsetBy(dx:dy:)` | Translate rect |

Use `contains(_:)` for panel hit testing with gesture locations.

## Pitfalls

- **`CGRect ==` exact equality fails with computed CGFloats** — layout division produces repeating decimals. Use `id` for lookups
- **`CGRect.approximatelyEquals` is fragile** — epsilon choice is arbitrary, may match wrong item. Prefer `id`-based lookup
- **Growing `LayoutKey` struct** — When using `@State` key paths (e.g., `.id($layoutKey)`) to invalidate canvas previews, adding each new overlay type (panels, title, ghost cursor) requires a new property on the key struct. This becomes a maintenance burden. Consider more targeted invalidation (e.g., separate `@State` flags per overlay type) when the key struct exceeds ~5 properties.
