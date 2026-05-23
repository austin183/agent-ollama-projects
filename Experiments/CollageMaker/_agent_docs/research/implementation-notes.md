# CollageMaker Implementation Notes — Apple APIs

## Summary of Findings

This document captures key implementation details discovered while researching Apple's developer documentation for the CollageMaker project.

## 1. Saliency Analysis — Two API Options

### Option A: Legacy API (Recommended for Compatibility)

```swift
import Vision

func analyzeSaliency(nsImage: NSImage) throws -> (center: CGPoint, radius: CGFloat, confidence: Float) {
    guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("No CGImage")
    }

    let width = cgImage.width
    let height = cgImage.height

    // Run both saliency and face detection in parallel
    let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
    let faceRequest = VNDetectFaceRectanglesRequest()

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try handler.perform([saliencyRequest, faceRequest])

    let observation = saliencyRequest.results?.first as? VNSaliencyImageObservation

    // Use salientObjects bounding boxes to find center of interest
    guard let salientObjects = observation?.salientObjects, !salientObjects.isEmpty else {
        // Default to center of image
        return (CGPoint(x: CGFloat(width) / 2, y: CGFloat(height) / 2), 0, 0)
    }

    // Find most confident salient region
    let mostSalient = salientObjects.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height })!
    let imageRect = VNImageRectForNormalizedRect(mostSalient.boundingBox, width, height)

    return (
        center: CGPoint(x: imageRect.midX, y: imageRect.midY),
        radius: max(imageRect.width, imageRect.height) / 2,
        confidence: mostSalient.boundingBox.width * mostSalient.boundingBox.height
    )
}
```

**Key insight:** The legacy `VNGenerateAttentionBasedSaliencyImageRequest` is the class name. The new Swift-only API uses `GenerateAttentionBasedSaliencyImageRequest` (without VN prefix).

### Coordinate System Note

Vision uses **normalized coordinates** with origin at **bottom-left** (0,0 = bottom-left, 1,1 = top-right). When converting to image coordinates:

```swift
let imageRect = VNImageRectForNormalizedRect(normalizedRect, Int(width), Int(height))
// Result is in image coordinates with origin at bottom-left
```

NSImage/CoreGraphics use origin at **top-left**. You may need to flip the Y coordinate:

```swift
let flippedY = CGFloat(height) - imageRect.origin.y - imageRect.height
```

## 2. Heat Map Analysis (Alternative Approach)

Instead of using bounding boxes, read the 68x68 heat map directly to find the maximum intensity point:

```swift
import CoreVideo

// From VNSaliencyImageObservation
let heatMap = observation.heatMap.buffer as! CVPixelBuffer
CVPixelBufferLockBaseAddress(heatMap, .readOnly)
defer { CVPixelBufferUnlockBaseAddress(heatMap, .readOnly) }

let mapWidth = CVPixelBufferGetWidth(heatMap)    // 68
let mapHeight = CVPixelBufferGetHeight(heatMap)  // 68
let bytesPerRow = CVPixelBufferGetBytesPerRow(heatMap)
let baseAddress = CVPixelBufferGetBaseAddress(heatMap)!

// Find max intensity pixel
var maxVal: Float = 0
var maxPoint = CGPoint(x: 0, y: 0)

for y in 0..<mapHeight {
    let rowPtr = baseAddress.advanced(by: y * bytesPerRow)
    let floatPtr = rowPtr.assumingMemoryBound(to: Float.self)
    for x in 0..<mapWidth {
        let val = floatPtr[x]
        if val > maxVal {
            maxVal = val
            maxPoint = CGPoint(x: CGFloat(x), y: CGFloat(y))
        }
    }
}

// Map back to image coordinates
let imageX = (maxPoint.x / CGFloat(mapWidth)) * CGFloat(width)
let imageY = (maxPoint.y / CGFloat(mapHeight)) * CGFloat(height)
```

## 3. Face Boost Strategy

If faces are detected, boost the saliency heat map in face regions:

```swift
let faceObservations = faceRequest.results as? [VNFaceObservation]

for face in faceObservations ?? [] {
    let faceRect = VNImageRectForNormalizedRect(face.boundingBox, width, height)
    // Map face rect to heat map coordinates
    let mapX1 = Int(faceRect.origin.x / CGFloat(width) * CGFloat(mapWidth))
    let mapY1 = Int(faceRect.origin.y / CGFloat(height) * CGFloat(mapHeight))
    let mapX2 = Int((faceRect.origin.x + faceRect.width) / CGFloat(width) * CGFloat(mapWidth))
    let mapY2 = Int((faceRect.origin.y + faceRect.height) / CGFloat(height) * CGFloat(mapHeight))

    // Boost saliency in face region
    for y in max(0, mapY1)..<min(mapHeight, mapY2) {
        let rowPtr = baseAddress.advanced(by: y * bytesPerRow)
        let floatPtr = rowPtr.assumingMemoryBound(to: Float.self)
        for x in max(0, mapX1)..<min(mapWidth, mapX2) {
            floatPtr.advanced(by: x).pointee = min(1.0, floatPtr.advanced(by: x).pointee * 1.5)
        }
    }
}
```

## 4. Collage Assembly with CoreGraphics

```swift
func assembleCollage(
    panels: [Panel],
    images: [NSImage],
    crops: [CropInfo],
    title: String,
    backgroundColor: NSColor = .black,
    quality: Double = 0.92
) -> Data {
    let canvasWidth = 1920
    let canvasHeight = 1080

    // Create bitmap context
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { fatalError() }
    guard let context = CGContext(
        data: nil,
        width: canvasWidth,
        height: canvasHeight,
        bitsPerComponent: 8,
        bytesPerRow: canvasWidth * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { fatalError() }

    // Flip coordinate system (CG uses bottom-left, we want top-left)
    context.translateBy(x: 0, y: CGFloat(canvasHeight))
    context.scaleBy(x: 1, y: -1)

    // Fill background
    context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))

    // Draw each panel
    context.interpolationQuality = .high
    for (index, panel) in panels.enumerated() {
        guard let nsImage = images[safe: panel.imageIndex] else { continue }
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }

        let crop = crops[index]
        let sourceRect = crop.sourceRect
        let destRect = crop.destinationRect

        // Crop and draw
        if let cropped = cgImage.cropping(to: sourceRect) {
            context.draw(cropped, in: destRect)
        }
    }

    // Draw title
    if !title.isEmpty {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 48),
            .foregroundColor: NSColor.white.withAlphaComponent(0.8)
        ]
        let attributedTitle = NSAttributedString(string: title, attributes: attributes)
        let titleRect = attributedTitle.boundingRect(
            with: CGSize(width: canvasWidth - 40, height: 60),
            options: [.usesLineFragmentOrigin]
        )
        attributedTitle.draw(at: CGPoint(x: 20, y: canvasHeight - titleRect.height - 20))
    }

    // Export
    guard let finalCGImage = context.makeImage() else { fatalError() }
    let nsImage = NSImage(cgImage: finalCGImage, size: NSSize(width: canvasWidth, height: canvasHeight))
    let bitmapRep = NSBitmapImageRep(cgImage: finalCGImage)
    guard let jpegData = bitmapRep.representation(
        using: .jpeg,
        properties: [.compressionFactor: quality]
    ) else { fatalError() }

    return jpegData
}
```

## 5. Actor-Based Saliency Analyzer

The `actor` pattern is good for thread-safe async analysis:

```swift
import Vision
import AppKit

actor SaliencyAnalyzer {
    func analyze(_ nsImage: NSImage) async throws -> SaliencyResult {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw SaliencyError.invalidImage
        }

        let width = cgImage.width
        let height = cgImage.height

        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
        let faceRequest = VNDetectFaceRectanglesRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([saliencyRequest, faceRequest])

        // Process results...
        let observation = saliencyRequest.results?.first as? VNSaliencyImageObservation
        // ... compute center, radius, confidence

        return SaliencyResult(
            center: center,
            radius: radius,
            confidence: confidence
        )
    }
}
```

## 6. Key Version Requirements

| Feature | Minimum macOS |
|---|---|
| `PhotosPicker` (SwiftUI) | 13.0 (Ventura) |
| `NavigationSplitView` | 13.0 (Ventura) |
| Vision legacy API (`VNGenerate...`) | 10.13 (High Sierra) |
| Vision new Swift API (`Generate...`) | 15.0 (Sequoia) |
| `.onDrop` | 11.0 (Big Sur) |
| `CGContext` bitmap | All versions |

**Recommendation:** Target macOS 13.0+ to use SwiftUI features, with legacy Vision API for broader compatibility.

## 7. Performance Considerations

- **Vision requests** run on background threads automatically — no need for manual dispatch
- **CGContext drawing** is fast for 1920x1080 — expect < 100ms per panel
- **JPEG export** at quality 0.92 for 1920x1080 produces ~500KB-2MB files
- **Saliency analysis** per image: 50-200ms depending on hardware (Neural Speed on Apple Silicon)
- Consider batching: analyze all images concurrently, then assemble

## 8. Image Orientation Handling

JPEG images may have EXIF orientation tags. Vision's `VNImageRequestHandler` handles orientation automatically when created from `CGImage`. For manual handling:

```swift
let handler = VNImageRequestHandler(
    cgImage: cgImage,
    orientation: cgImage.imageOrientation,  // Handle EXIF orientation
    options: [:]
)
```

Note: `CGImagePropertyOrientation` can be extracted from image metadata if needed.
