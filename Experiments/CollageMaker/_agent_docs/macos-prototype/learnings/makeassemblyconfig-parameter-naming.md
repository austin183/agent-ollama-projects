# makeAssemblyConfig Parameter Naming and Background Style Rendering

**Date:** 2026-06-27
**Source:** Phase 5 fitness function test implementation (session-138)
**Purpose:** Document the `makeAssemblyConfig` parameter-to-background-style mapping and pixel-sampling patterns for background verification in tests.

---

## Background Style Color Parameters

`makeAssemblyConfig()` has separate parameters for different background styles. Using the wrong one produces silent black output:

| Parameter | Used by `.solid` | Used by `.gradient` | Used by `.image` |
|---|---|---|---|
| `backgroundColor:` | **Yes** → `BackgroundConfig.color.cgColor` | No (ignored) | **Yes** → `BackgroundConfig.color.cgColor` |
| `gradientStartColor:` | No (ignored) | **Yes** → start of linear gradient | No (ignored) |
| `gradientEndColor:` | No (ignored) | **Yes** → end of linear gradient | No (ignored) |
| `gradientAngle:` | No (ignored) | **Yes** → gradient direction | No (ignored) |

**Rule:** For `.solid` or `.image` styles, pass the fill color as `backgroundColor:`. Only use `gradientStartColor:`/`gradientEndColor:` when `backgroundStyle: .gradient`.

### Example: Correct Usage

```swift
// Solid red background — use backgroundColor:
makeAssemblyConfig(
    panels: panels, crops: crops,
    backgroundColor: .red,           // ← correct for .solid and .image
    backgroundStyle: .solid,
    gradientStartColor: .black,      // ← ignored, but must be present
    gradientEndColor: .darkGray,     // ← ignored
    gradientAngle: 0,                // ← ignored
    canvasSize: canvasSize
)

// Gradient from red to blue — use gradient colors
makeAssemblyConfig(
    panels: [], crops: [:],
    backgroundColor: .black,         // ← ignored for .gradient
    backgroundStyle: .gradient,
    gradientStartColor: .red,        // ← correct for .gradient
    gradientEndColor: .blue,         // ← correct for .gradient
    gradientAngle: 45,               // ← correct for .gradient
    canvasSize: canvasSize
)
```

### Example: The Bug (Silent Black Output)

```swift
// WRONG — passes red as gradientStartColor but style is .solid
makeAssemblyConfig(
    panels: panels, crops: crops,
    backgroundStyle: .solid,
    gradientStartColor: .red,        // ← IGNORED by drawSolidBackground!
    backgroundColor: .black,         // ← default, produces black fill
    ...
)
// Result: full-canvas black fill instead of red
```

## Pixel Sampling for Background Verification in Tests

When verifying background colors render correctly in headless test environment:

1. **Don't sample panel centers** — they show panel content (white from `createTestImageItem`), not background.
2. **Don't use full-canvas solid fill with no panels** — produces all-black output in headless JPEG roundtrip via `NSImage(data:)`.
3. **Use gutter-region sampling** — create a layout with multiple small panels and large gutters (e.g., 4 images, gutter=20), then sample the canvas center which falls in the gap between panels.

```swift
// Pattern that works:
let panels = LayoutGenerator.generate(
    numImages: 4, canvasSize: canvasSize, gutter: 20, style: .uniform
)
// ... set up crops with small source rects (50x50) ...
// Sample center pixel — falls in gutter between the 2×2 panel grid

let width = Int(canvasSize.width)
let height = Int(canvasSize.height)
let idx = ((height / 2) * width + width / 2) * 4
let r = Int(pixels[idx])
let g = Int(pixels[idx + 1])
let b = Int(pixels[idx + 2])
// Verify color matches expected background
```

## ImageItem.cgImage Is a Stored Property, Not a Method

`createTestImageItem(...)` returns `ImageItem`, which has `let cgImage: CGImage` as a stored property. Do NOT call it as a method:

```swift
// ❌ WRONG — "cannot call value of non-function type 'CGImage'"
let cg = createTestImageItem(color: .white).cgImage(forProposedRect: nil, context: nil, hints: nil)

// ✅ CORRECT — cgImage is already a CGImage property
let cg = createTestImageItem(color: .white).cgImage
```

## Canvas Coverage Thresholds by Layout Style

Sum-of-bounding-boxes coverage varies significantly by layout geometry. Use these relaxed thresholds for fitness functions:

| Layout | Typical Coverage (10 images) | Recommended Minimum | Reason |
|---|---|---|---|
| `.uniform` | 65–99% | ≥25% | Empty grid cells when N ≠ C×R |
| `.hero` | 70–95% | ≥25% | Hero panel + side strip leaves gaps |
| `.mosaic` | 60–90% | ≥25% | Random split ratios leave unused space |
| `.diagonalSlices` | 40–80% | ≥10% | Shear-transformed parallelograms don't fill corners |
| `.hexagonal` | 10–60% | ≥10% | Circle-packed hexagons have inherent spacing gaps |

**Rule:** Coverage thresholds should be fitness-function level (catch total regressions), not precision requirements. The plan's "≥95%" is unrealistic for most layouts.

---

## Related Patterns

- **`BackgroundRenderer.drawSolidBackground`** reads `config.color.cgColor`, never gradient colors
- **`ContextFactory.createBitmap`** uses `premultipliedFirst` alpha info — solid fills may render differently than gradients in headless mode due to premultilication interaction with JPEG encoder
- **`NSImage(data:)` → CGImage roundtrip** can silently lose color information for full-canvas solid fills in test environment

---

**Status:** Open
**Follow-up:** Consider adding a `@precondition` or debug assertion in `makeAssemblyConfig` that warns when gradient colors are passed with non-gradient style.
