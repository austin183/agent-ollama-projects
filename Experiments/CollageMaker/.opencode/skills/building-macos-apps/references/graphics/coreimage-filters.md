# CoreImage — Filters and GPU Processing

## CIContext

```swift
// Create context for rendering
let context = CIContext(options: [.useSoftwareRenderer: false])

// Render CIImage to CGImage
let cgImage = context.createCGImage(ciImage, from: ciImage.extent)!
```

## Built-in Filters

Access via `CIFilter` or `CIFilterGenerator`:

| Category | Filters |
|---|---|
| Blur | `CIGaussianBlur`, `CIMotionBlur` |
| Color | `CIColorControls`, `CIToneCurve` |
| Geometry | `CIAffineTransform`, `CICrop` |
| Composite | `CISourceOverCompositing`, `CIBlendWithMask` |

## CIImage Operations

```swift
CIImage(contentsOf: url)           // From URL
CIImage(cgImage: cgImage)          // From CGImage
ciImage.cropping(to: CGRect)       // Crop
ciImage.applyingFilter("CIGaussianBlur", parameters: [:])  // Apply filter
```

## Custom Kernels

`CIKernel` is being deprecated in favor of Metal Shading Language (MSL) via `CIImageProcessorKernel`.

```swift
let kernel = CIKernel(source: """
    kernel vec4 process(__sample s) {
        return vec4(s.rgb * 2.0, 1.0);
    }
""")
```

## vImage (Accelerate Framework)

High-performance CPU image processing using vector instructions.

| Operation | Function | Purpose |
|---|---|---|
| Resize | `vImageScale_ARGB8888` | Scale image |
| Convert | `vImageConvert_BGRA8888toARGB8888` | Pixel format |
| Blend | `vImageBlend_ARGB8888` | Alpha blend |
| Convolution | `vImageConvolve3x3` | Kernel (blur, sharpen) |

### CVPixelBuffer Access

```swift
import CoreVideo

CVPixelBufferLockBaseAddress(buffer, .readOnly)
defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

let width = CVPixelBufferGetWidth(buffer)
let height = CVPixelBufferGetHeight(buffer)
let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
let baseAddress = CVPixelBufferGetBaseAddress(buffer)
```

## CoreGraphics Compositing Example

```swift
func assemble(panels: [Panel], cgImages: [CGImage?], crops: [CropInfo]) -> Data? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo: CGBitmapInfo = [.byteOrder32Big]

    guard let context = CGContext(
        data: nil, width: Int(width), height: Int(height),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: bitmapInfo.rawValue
    ) else { return nil }

    // Flip to top-left origin — IMPORTANT: Only flip when exporting to file
    // (JPEG/PNG). Do NOT flip when rendering to NSBitmapImageRep for display
    // via NSImage → SwiftUI Image(nsImage:), as the AppKit bridge handles
    // the bottom-left to top-left conversion automatically.
    context.translateBy(x: 0, y: height)
    context.scaleBy(x: 1, y: -1)

    context.setFillColor(backgroundColor.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    context.interpolationQuality = .high
    for panel in panels {
        guard let cg = cgImages[panel.imageIndex] else { continue }
        context.clip(to: panel.frame)
        let cropped = cg.cropping(to: sourceRect) ?? cg
        context.draw(cropped, in: panel.frame)
    }

    // Title: use NSAttributedString.draw(at:) — CGContext text API is deprecated
    guard let finalImage = context.makeImage() else { return nil }
    let bitmapRep = NSBitmapImageRep(cgImage: finalImage)
    return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
}
```

### Gradient Full-Coverage Line Length

When drawing a linear gradient from center that must cover all four corners at any angle, use the true diagonal half-length, not `min(w, h) / 2`:

```swift
let halfDiag = sqrt(w * w + h * h) / 2.0
let center = CGPoint(x: w / 2, y: h / 2)
let angleRad = gradientAngle * .pi / 180.0

let start = CGPoint(
    x: center.x - halfDiag * cos(angleRad),
    y: center.y - halfDiag * sin(angleRad)
)
let end = CGPoint(
    x: center.x + halfDiag * cos(angleRad),
    y: center.y + halfDiag * sin(angleRad)
)

context.drawLinearGradient(
    gradient!,
    start: start,
    end: end,
    options: []
)
```

Using `min(w, h) / 2` produces a line only as long as the smaller dimension's radius, leaving corners uncovered on non-square canvases.

**Key points:**
- `bytesPerRow: 0` lets system calculate it
- `[.byteOrder32Big]` = 32-bit RGBX, no alpha — fine for production, but `makeImage()` may return `nil` in tests
- `interpolationQuality = .high` for resize quality
- Use `NSAttributedString.draw(at:)` for text overlays (see `nsattributedstring-drawing.md`)

## NSGraphicsContext.current Thread Safety

Each `Task.detached` rendering call creates its own `NSBitmapImageRep` and sets `NSGraphicsContext.current`. Even though each task has an isolated bitmap, **concurrent tasks can interleave** between `saveGraphicsState()` and `NSGraphicsContext.current = ...`, causing one task's context to be clobbered by another.

**Fix: Serial DispatchQueue**

```swift
class RenderQueue {
    private let queue = DispatchQueue(label: "austin183.indie.CollageMaker.render")

    func render<T>(_ work: () -> T) -> T {
        queue.sync(execute: work)
    }
}
```

Wrap each rendering method's body with the serial queue:

```swift
func renderPreview() -> NSImage? {
    renderQueue.render {
        let bitmapRep = NSBitmapImageRep(...)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
        // ... drawing ...
        NSGraphicsContext.restoreGraphicsState()
        return NSImage(cgImage: bitmapRep.cgImage!, size: canvasSize)
    }
}
```

**Decision tree:**

| Scenario | Risk | Mitigation |
|---|---|---|
| Single rendering call per task | Low | `saveGraphicsState()` / `restoreGraphicsState()` sufficient |
| Multiple concurrent tasks, each with own bitmap | Medium | Serial `DispatchQueue` wraps each method |
| Shared bitmap across tasks | High | Must serialize + coordinate access |

A serial `DispatchQueue` is simpler than an actor (no async overhead) and sufficient since rendering is already off-main-actor via `Task.detached`.

### Async Protocol Methods with Serial Queue

When exposing rendering methods through a protocol for testability, the recommended pattern is `async` methods backed by `withCheckedContinuation` + `queue.async`. This gives callers clean `await` syntax while preserving serial queue thread safety:

```swift
protocol CollageAssembly {
    func renderPanel(crop: CropInfo, cgImage: CGImage, panelSize: CGSize) async -> NSImage?
    func renderPreview(panels: [ImagePanel], background: BackgroundConfig) async -> NSImage?
}

class CollageAssembler: CollageAssembly {
    private let renderQueue = DispatchQueue(label: "austin183.indie.CollageMaker.render")

    func renderPanel(crop: CropInfo, cgImage: CGImage, panelSize: CGSize) async -> NSImage? {
        await withCheckedContinuation { cont in
            renderQueue.async {
                let result = self.doRenderPanel(crop, cgImage, panelSize)
                cont.resume(returning: result)
            }
        }
    }
}
```

**Benefits over `queue.sync` + `Task.detached`:** Non-blocking queue entry, simpler call sites (`await` instead of `Task.detached { ... }.value`), preserved serial queue safety. See [references/state/swift-concurrency.md](references/state/swift-concurrency.md) for the full decision tree.

**Mocking in tests:** Mock implementations can be synchronous (no queue needed):
```swift
class MockAssembler: CollageAssembly {
    func renderPanel(...) async -> NSImage? {
        return mockImage  // No queue, just return directly
    }
}
```

## Pitfalls

- **CGContext `[.byteOrder32Big]` test failures** — `makeImage()` returns `nil` in test environment; use `NSBitmapImageRep` with RGBA
- **`NSColorSpaceName.sRGB`** — doesn't exist; use `.deviceRGB`
- **CGContext text** — `selectFont`/`showTextAtPoint` deprecated, use `NSAttributedString.draw(at:)`
- **CGContext Y-flip with NSBitmapImageRep display** — Do NOT flip the CGContext Y-axis (`translateBy` + `scaleBy`) when rendering to `NSBitmapImageRep` that will be displayed via `NSImage` → SwiftUI `Image(nsImage:)`. The AppKit/SwiftUI bridge handles the bottom-left to top-left conversion automatically. Flipping the CGContext will render images upside down. The flip IS correct for direct CGContext drawing in `NSView.draw(_:)` or when exporting to file (JPEG/PNG), where you want the output in top-left orientation.
- **Canvas-to-UI coordinate conversion** — When overlaying SwiftUI hit areas on top of a CoreGraphics-rendered image, the hit area coordinates must account for Y-axis inversion (CoreGraphics bottom-left vs SwiftUI top-left) AND aspect-ratio fitting (`.aspectRatio(contentMode: .fit)` scales down, not up). The fitted size formula: if canvas aspect > preview aspect, constrain by preview width (`fittedWidth = previewWidth, fittedHeight = previewWidth / canvasAspect`); otherwise constrain by preview height.
- **NSImage display size hint vs actual resolution** — `NSImage(cgImage:size:)` `size` parameter is a display hint for AppKit, not the actual pixel dimensions. The underlying bitmap retains its original resolution. SwiftUI's `Image(nsImage:)` ignores this hint and uses the bitmap's actual pixel dimensions, then scales via `.aspectRatio(contentMode: .fit)`. Coordinate conversion must use the actual canvas resolution, not the hint size.
- **EXIF coordinate mismatch with CGImage overlays** — `Image(nsImage:)` applies EXIF orientation corrections (rotation, flip) before display, but `sourceRect` coordinates from CGImage operations live in raw pixel space. The overlay appears shifted or rotated. Fix: create `NSImage(cgImage: image.cgImage, size: .zero)` to strip EXIF metadata, ensuring the displayed image matches the CGImage coordinate space.
- **CGBlendMode on empty CGContext produces black** — Multiply blend computes `source × destination`. On a fresh transparent context, every destination pixel is `(0,0,0,0)`, so the result is black regardless of source. Do NOT pre-render a blend operation into an isolated empty context expecting the blend to "stick" for later compositing. Instead, render the overlay without blend mode (just opacity) in CGContext, then apply the blend mode at the compositing layer where destination pixels exist:

```swift
// Render phase — no blend mode, just opacity
context.setAlpha(overlay.opacity)
context.draw(maskImage, in: rect)

// Compositing phase — SwiftUI ZStack
Image(nsImage: overlayImage)
    .blendMode(.multiply)  // blend against actual panel content
```

Blend mode requires non-zero destination pixels. A context that already contains drawn content (background + panels) is a valid destination.

- **CGContext implicit clipping vs SwiftUI ZStack** — A `CGContext` created at bitmap size `S` silently discards all drawing outside `[0, S]`. In a single-context rendering mode, this clips content automatically. In a layered mode (per-panel `NSImage`s placed in a SwiftUI `ZStack`), each panel renders to its own bitmap at its bounding rect size with no canvas-level clipping — panels extending beyond the canvas are visible. Fix: add `.clipShape(Rectangle())` + `.frame(width:, height:)` + `.position(x:, y:)` to the ZStack using the fitted canvas preview frame. When a rendering pipeline has multiple modes, verify clipping behavior is consistent — a visual discrepancy between modes usually means one mode is missing a clip that the other provides implicitly.
