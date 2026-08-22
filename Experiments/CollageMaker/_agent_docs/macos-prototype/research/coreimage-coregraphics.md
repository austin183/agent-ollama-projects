# CoreImage & CoreGraphics — Image Processing and Compositing

## CoreGraphics — Compositing and Export

CoreGraphics (Quartz 2D) is the primary framework for assembling the final collage image.

### CGContext — Drawing Environment

`CGContext` represents a 2D drawing destination. For collage assembly, we need a **bitmap context**:

```swift
// Create bitmap context for 1920x1080 output
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bytesPerRow = 1920 * 4
let context = CGContext(
    data: nil,
    width: 1920,
    height: 1080,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)
```

### Key CGContext Operations for Collage

| Operation | Method | Purpose |
|---|---|---|
| Fill background | `setFillColor()`, `fill(CGRect)` | Set canvas background color |
| Draw image into rect | `draw(CGImage, in: CGRect)` | Place cropped image into panel |
| Set interpolation | `interpolationQuality` | Control resize quality (.high, .medium, .low) |
| Draw text | `selectFont()`, `showTextAtPoint()` | Title overlay |
| Draw lines/rects | `addRect()`, `strokePath()` | Panel borders/gutters |
| Extract result | `makeImage()` → `CGImage` | Get final composited image |

### Drawing Images with Quality Control

```swift
context?.interpolationQuality = .high  // Best quality for resizing
context?.draw(sourceImage, in: destinationRect)
```

`CGInterpolationQuality` levels: `.none`, `.low`, `.medium`, `.high`, `.best`

### CGContext Coordinate System

- Origin (0,0) is at **bottom-left** by default
- For image drawing, may need to flip: `context?.translateBy(x: 0, y: height)` then `context?.scaleBy(x: 1, y: -1)`

### Text Drawing (Legacy API)

```swift
context?.selectFont("Helvetica-Bold", size: 48, textEncoding: .macRoman)
context?.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.8)
context?.showTextAtPoint(x: 960, y: 1040, string: "Title", length: 5)
```

**Note:** The CGContext text drawing API is deprecated. Consider using `NSAttributedString.draw(at:)` with `NSGraphicsContext` instead.

## NSImage → CGImage Pipeline

```swift
// Load image from file
let nsImage = NSImage(contentsOfFile: "/path/to/image.jpg")!

// Get CGImage from NSImage
let cgImage = nsImage.cgImage(
    forProposedRect: nil,
    context: NSGraphicsContext.current,
    hints: nil
)!

// Crop a CGImage
let cropped = cgImage.cropping(to: sourceRect)

// Draw into context
context.draw(cropped, in: destinationRect)
```

### NSImage Loading

- `init(contentsOfFile:)` — load from file path
- `init(contentsOf:)` — load from URL
- `init(data:)` — load from Data
- `init(cgImage:size:)` — create from CGImage

### NSImage Properties

- `size` → `NSSize` (width, height)
- `cgImage(forProposedRect:context:hints:)` → `CGImage?`

## NSBitmapImageRep — JPEG Export

```swift
// From CGImage to NSBitmapImageRep
let bitmapRep = NSBitmapImageRep(cgImage: finalCGImage)

// Export as JPEG with quality
let jpegData = bitmapRep.representation(
    using: .jpeg,
    properties: [NSBitmapImageRep.PropertyKey.compressionFactor: 0.92]
)

// Write to file
jpegData?.write(to: outputURL, options: .atomic)
```

### Export Properties

| Key | Type | Description |
|---|---|---|
| `.compressionFactor` | Float (0-1) | JPEG quality (1.0 = best) |
| `.colorSyncColorProfile` | Data | Color profile to embed |

### File Types

- `.jpeg` — JPEG format
- `.png` — PNG format
- `.tiff` — TIFF format
- `.gif` — GIF format

## CoreImage — Filters and Custom Kernels

CoreImage provides GPU-accelerated image processing.

### CIContext

```swift
// Create context for rendering
let context = CIContext(options: [.useSoftwareRenderer: false])

// Render CIImage to CGImage
let cgImage = context.createCGImage(ciImage, from: ciImage.extent)!
```

### Built-in Filters

Access via `CIFilter` or `CIFilterGenerator`:
- Blur: `CIGaussianBlur`, `CIMotionBlur`
- Color: `CIColorControls`, `CIToneCurve`
- Geometry: `CIAffineTransform`, `CICrop`
- Composite: `CISourceOverCompositing`, `CIBlendWithMask`

### Custom Kernels (CIKernel)

For custom saliency map processing:

```swift
// CIKernel — GPU-based custom image processing
let kernel = CIKernel(source: """
    kernel vec4 process(__sample s) {
        return vec4(s.rgb * 2.0, 1.0);
    }
""")
```

**Note:** CIKernel is being deprecated in favor of Metal Shading Language (MSL) kernels via `CIImageProcessorKernel`.

### CIImage

- `CIImage(contentsOf:)` — create from URL
- `CIImage(cgImage:)` — create from CGImage
- `ciImage.cropping(to: CGRect)` — crop
- `ciImage.applyingFilter("CIGaussianBlur", parameters:...)` — apply filter

## vImage (Accelerate Framework) — Pixel Buffer Operations

vImage provides high-performance image processing on CPU using vector instructions.

### CVPixelBuffer from Saliency Heat Map

The saliency heat map is returned as a `CVPixelBuffer`. To read pixel values:

```swift
import Accelerate
import CoreVideo

// Lock pixel buffer
CVPixelBufferLockBaseAddress(heatMap, .readOnly)
defer { CVPixelBufferUnlockBaseAddress(heatMap, .readOnly) }

// Get pointer to data
let width = CVPixelBufferGetWidth(heatMap)
let height = CVPixelBufferGetHeight(heatMap)
let bytesPerRow = CVPixelBufferGetBytesPerRow(heatMap)
let baseAddress = CVPixelBufferGetBaseAddress(heatMap)
```

### vImage Operations Relevant to Collage

| Operation | vImage Function | Purpose |
|---|---|---|
| Resize | `vImageScale_ARGB8888` | Scale image to panel size |
| Convert format | `vImageConvert_BGRA8888toARGB8888` | Pixel format conversion |
| Blend | `vImageBlend_ARGB8888` | Alpha blend two images |
| Convolution | `vImageConvolve3x3` | Apply kernel (blur, sharpen, edges) |

### CGImage ↔ vImage Buffer Conversion

```swift
// CGImage to vImage buffer
var buffer = vImage_Buffer()
// ... populate buffer from CGImage data

// vImage buffer to CGImage
let cgImage = vImageCreateCGImageFromBuffer(&buffer, ...)
```

## Recommended Pipeline for CollageMaker

1. **Load**: `NSImage(contentsOfFile:)` → `NSImage.cgImage(...)` → `CGImage`
2. **Saliency**: `CGImage` → `VNImageRequestHandler` → `VNSaliencyImageObservation`
3. **Crop**: `CGImage.cropping(to: CGRect)` based on saliency center
4. **Compose**: `CGContext` bitmap context → `draw(CGImage, in: CGRect)` per panel
5. **Title**: `NSAttributedString.draw(at:)` in CGContext
6. **Export**: `context.makeImage()` → `CGImage` → `NSBitmapImageRep` → JPEG `Data`
