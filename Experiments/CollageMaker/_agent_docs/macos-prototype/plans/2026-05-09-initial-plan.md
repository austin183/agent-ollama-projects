# Collage Maker - SwiftUI macOS Implementation Plan

## Overview
macOS SwiftUI app that converts a folder of 1920x1080 photos into a 1920x1080 collage. Uses Vision/CoreImage for saliency detection, algorithmic layout generation, and an interactive visual editor for crop adjustments before final export.

## Source & Reference
- **Source images**: `/Users/austin/Pictures/VideoPictures/OuterWorlds2/Session18/` (9 JPGs, all 1920x1080)
- **Reference collage**: `/Users/austin/Pictures/VideoPictures/OuterWorlds2/Session14/Cover.jpg`

## Apple Core Library Mappings
| Python | Apple Framework | Purpose |
|---|---|---|
| Pillow | `CoreGraphics` / `AppKit.NSImage` | Image loading, resizing, compositing |
| OpenCV edges | `CoreImage.CIKernel` / `CIEDges` | Edge detection (note: `CIKernel` deprecated, use `CIImageProcessorKernel` / MSL for new code) |
| OpenCV color | `CoreImage` custom kernel | Color variance in sliding windows |
| OpenCV faces | `Vision.VNDetectFaceRectanglesRequest` | Face detection |
| NumPy | `vImage` / `CoreImage` pixel buffers | Numerical image ops |
| CLI args | `PhotosPicker` / `NSOpenPanel` | Folder/image selection |
| Terminal review | `SwiftUI` visual editor | Interactive crop adjustment |

## Design Decisions
| Decision | Choice |
|---|---|
| Approach | Interactive GUI: app suggests crops, user adjusts visually |
| Layout | Algorithmic mosaic based on image count |
| Hero image | User selects in UI |
| Title overlay | Text field in UI |
| Image input | Drag-and-drop + folder browse + PhotosPicker |
| Export | Save dialog, JPEG with quality slider |

## Architecture

### File Structure
```
CollageMaker/
  CollageMakerApp.swift          # @main entry point
  ContentView.swift              # Main view with tab/navigation layout

  Models/
    ImagePanel.swift             # Panel(x,y,w,h, imageIndex) + CropInfo
    SaliencyResult.swift         # Center of interest + confidence

  Services/
    SaliencyAnalyzer.swift       # Vision + CoreImage saliency detection
    LayoutGenerator.swift        # Algorithmic mosaic layout
    CollageAssembler.swift       # CoreGraphics compositing + export

  Views/
    ImagePickerView.swift        # Drag-drop + folder browse + PhotosPicker
    CollageEditorView.swift      # Main editor: layout preview + crop controls
    PanelCropEditor.swift        # Per-panel crop offset/scale sliders
    ExportPanel.swift            # Title, quality, output path controls
```

### Module Details

#### `SaliencyResult.swift` - Data Model
```swift
struct SaliencyResult {
    let center: CGPoint      // Center of interest in image coordinates
    let radius: CGFloat      // Spread of prominent region
    let confidence: Float    // 0.0...1.0
}
```

#### `ImagePanel.swift` - Data Model
```swift
struct Panel: Identifiable, Equatable {
    let id: UUID
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var imageIndex: Int
    var isHero: Bool
}

struct CropInfo {
    var sourceRect: CGRect   // Crop rect in source image coordinates
    var destinationRect: CGRect  // Panel position on canvas
    var imageIndex: Int
}
```

#### `SaliencyAnalyzer.swift` - Prominent Region Detection
Uses Vision framework for saliency + face detection.

**Algorithm:**
1. **Primary saliency**: `VNGenerateAttentionBasedSaliencyImageRequest` — Apple's built-in ML saliency (trained on eye-tracking data), returns 68x68 `CVPixelBuffer` heat map + `salientObjects` bounding boxes
2. **Face boost**: `VNDetectFaceRectanglesRequest` — if faces found, boost their region in the saliency map
3. **Find max**: Scan combined saliency map for highest-intensity pixel
4. **Coordinate flip**: Vision uses bottom-left origin; flip Y to match NSImage's top-left origin: `flippedY = height - imageRect.origin.y - imageRect.height`
5. **EXIF orientation**: Pass `orientation: cgImage.imageOrientation` to `VNImageRequestHandler` for correct handling of rotated images
6. **Result**: `SaliencyResult(center, radius, confidence)`

```swift
import Vision
import AppKit

actor SaliencyAnalyzer {
    func analyze(_ nsImage: NSImage) async throws -> SaliencyResult {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw SaliencyError.invalidImage
        }

        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
        let faceRequest = VNDetectFaceRectanglesRequest()

        // Handle EXIF orientation
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgImage.imageOrientation, options: [:])
        try handler.perform([saliencyRequest, faceRequest])

        // Get 68x68 heat map and salient objects
        let observation = saliencyRequest.results?.first as? VNSaliencyImageObservation
        let heatMap = observation?.heatMap.buffer as! CVPixelBuffer

        // Boost face regions in heat map, find max intensity
        // Flip Y coordinate from Vision (bottom-left) to NSImage (top-left)
        // Return SaliencyResult
    }
}
```

#### `LayoutGenerator.swift` - Algorithmic Layout Generation
Pure computation, no framework dependencies.

**Layout strategies by image count:**
- 4-5 images: 2-row layout with hero spanning both rows
- 6-9 images: 3x3 grid with hero taking 2 cells
- 10+ images: Dynamic grid calculation

```swift
struct LayoutGenerator {
    static func generate(
        numImages: Int,
        heroIndex: Int?,
        canvasSize: CGSize,
        gutter: CGFloat
    ) -> [Panel] {
        // Returns list of Panel(x, y, w, h, imageIndex)
    }
}
```

#### `CollageAssembler.swift` - Final Compositing & Export
Uses `CoreGraphics` context drawing for pixel-perfect assembly.

**Algorithm:**
1. Create `CGContext` with 1920x1080 size, sRGB color space (`CGColorSpace(name: CGColorSpace.sRGB)`)
2. Flip coordinate system: `translateBy(x: 0, y: height)` + `scaleBy(x: 1, y: -1)` for top-left origin
3. Fill background (configurable color)
4. For each panel: draw cropped/resized image into panel rectangle
5. Draw gutter borders
6. Add title text with `NSAttributedString.draw(at:)` (CoreGraphics `selectFont`/`showTextAtPoint` is deprecated)
7. Export `context.makeImage()` -> `NSBitmapImageRep` -> JPEG data -> file

```swift
class CollageAssembler {
    func assemble(
        panels: [Panel],
        images: [NSImage],
        crops: [CropInfo],
        title: String,
        backgroundColor: NSColor,
        quality: Double
    ) -> Data {
        // Returns JPEG Data
    }
}
```

#### `ImagePickerView.swift` - Image Input
Three ways to add images:
1. **Drag and drop**: `.onDrop` modifier for JPG/PNG files
2. **Folder browse**: `NSOpenPanel` via custom NSViewController hosting
3. **PhotosPicker**: `PhotosPicker` from SwiftUI (macOS 13+) — load as `Data` (not `Image`) since `Image` Transferable only supports PNG; create `NSImage(data:)` for JPEG support

#### `CollageEditorView.swift` - Main Editor
The core interactive workspace:
- Live collage preview at scaled-down size
- Thumbnail strip showing assigned images
- Per-panel crop controls (offset X/Y, zoom sliders)
- Hero image selector
- Gutter width slider
- Title text field
- Export button with save dialog

#### `CollageViewModel.swift` - State Management
`ObservableObject` that orchestrates the pipeline:

```swift
@MainActor
class CollageViewModel: ObservableObject {
    @Published var images: [ImageItem] = []
    @Published var panels: [Panel] = []
    @Published var crops: [CropInfo] = []
    @Published var saliencyResults: [UUID: SaliencyResult] = [:]
    @Published var heroIndex: Int?
    @Published var title: String = ""
    @Published var gutter: CGFloat = 4
    @Published var previewImage: NSImage?
    @Published var isProcessing: Bool = false

    func analyzeSaliency() async
    func generateLayout()
    func computeCrops()
    func updatePreview()
    func exportCollage() async
}
```

## User Workflow
1. Open app -> drag images or browse folder
2. App analyzes images (saliency detection, shown with progress)
3. Layout generated automatically
4. User sees live preview with crop overlays
5. User can:
   - Adjust crop per panel (sliders for offset/zoom)
   - Reassign images to panels (drag thumbnails)
   - Set hero image
   - Adjust gutter, title
6. Click "Export" -> save dialog -> Cover.jpg saved

## Key SwiftUI Features Used
- `PhotosPicker` for system photo library access (load as `Data` for JPEG)
- `.onDrop` for drag-and-drop file import
- `@MainActor` + `async/await` for non-blocking analysis
- `NSImage` rendering in SwiftUI via `Image(nsImage:)`
- Save dialog via `.fileExporter` or custom `NSSavePanel`
- `NavigationSplitView` for sidebar + editor layout

## Version Requirements
| Feature | Minimum macOS |
|---|---|
| `PhotosPicker`, `NavigationSplitView` | 13.0 (Ventura) |
| Vision legacy API (`VNGenerate...`) | 10.13 (High Sierra) |
| Vision new Swift API (`Generate...`) | 15.0 (Sequoia) |
| `.onDrop` | 11.0 (Big Sur) |

**Target:** macOS 13.0+ with legacy Vision API for compatibility.

## Performance Notes
- Saliency analysis per image: 50-200ms (faster on Apple Silicon)
- CGContext drawing at 1920x1080: < 100ms per panel
- JPEG export at quality 0.92: ~500KB-2MB output
- Analyze all images concurrently, then assemble

## Testing Strategy
- **Unit tests**: `LayoutGenerator` algorithms for various image counts
- **Unit tests**: `SaliencyAnalyzer` with mock images (small test fixtures)
- **Unit tests**: `CollageAssembler` round-trip (assemble -> verify dimensions)
- **Test fixtures**: Small test images in `CollageMakerTests/Resources/`

## Limitations
1. **No artistic overlap** — same limitation as original Python plan
2. **No rotation/flipping** of individual panels
3. **Title font** depends on system-available fonts
4. Saliency is ML-heuristic — not perfect at identifying "the subject"

## Future Enhancements
- Multiple layout presets to choose from
- Automatic color harmonization across panels
- Shadow/overlap effects between panels
- Deep learning saliency fine-tuning with custom Vision models
