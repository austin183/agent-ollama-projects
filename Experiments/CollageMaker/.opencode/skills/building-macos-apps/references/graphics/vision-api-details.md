# Vision Framework — Saliency and Face Detection Details

## API Versions

| API | Availability | Style |
|---|---|---|
| **Swift-only (new)** | macOS 15+ | `GenerateAttentionBasedSaliencyImageRequest`, async `perform(on:)` |
| **Legacy** | macOS 10.13+ | `VNGenerateAttentionBasedSaliencyImageRequest`, `VNImageRequestHandler` |

**Target macOS 13.0+ with legacy API** for maximum compatibility.

## Saliency Types

### Attention-Based (Recommended for Cropping)
- Trained on **eye-tracking data** from human subjects
- Highlights what people are **likely to look at**
- Returns: `salientObjects` bounding boxes + 68x68 heat map

### Objectness-Based
- Trained on **foreground objects segmented from background**
- Returns: up to 3 bounding boxes with scores
- Best for: identifying distinct objects

## Saliency Request (Legacy API)

```swift
let request = VNGenerateAttentionBasedSaliencyImageRequest()
let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgImage.imageOrientation, options: [:])
try handler.perform([request])

let observation = request.results?.first as? VNSaliencyImageObservation
```

### `VNSaliencyImageObservation` Result
- **`heatMap`**: 68x68 `CVPixelBuffer` of `Float` values [0, 1]
- **`salientObjects`**: `[VNRectangleObservation]` with normalized bounding boxes

## New Swift-Only API (macOS 15+)

```swift
let request = GenerateAttentionBasedSaliencyImageRequest()
let observations = try await request.perform(on: cgImage)
// Supports: URL, Data, CGImage, CVPixelBuffer, CMSampleBuffer, CIImage
```

## Face Detection

### Legacy
```swift
let request = VNDetectFaceRectanglesRequest()
let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
try handler.perform([request])

let faces = request.results as? [VNFaceObservation]
for face in faces ?? [] {
    let box = face.boundingBox  // Normalized CGRect
    let imageRect = VNImageRectForNormalizedRect(box, Int(w), Int(h))
}
```

Each `VNFaceObservation` provides: `boundingBox`, `yaw`, `pitch`, `roll`, `landmarks`, `captureQuality`.

## Coordinate Conversion

```swift
// Normalized rect to image coordinates
let imageRect = VNImageRectForNormalizedRect(normalizedRect, Int(width), Int(height))

// Normalized point to image point
let imagePoint = VNImagePointForNormalizedPoint(normalizedPoint, Int(width), Int(height))
```

**Remember:** Vision uses bottom-left origin. Flip Y for top-left: `flippedY = height - rect.origin.y - rect.height`.

## Heat Map Analysis (Alternative to Bounding Boxes)

```swift
let heatMap = observation.heatMap.buffer as! CVPixelBuffer
CVPixelBufferLockBaseAddress(heatMap, .readOnly)
defer { CVPixelBufferUnlockBaseAddress(heatMap, .readOnly) }

let mapW = CVPixelBufferGetWidth(heatMap)    // 68
let mapH = CVPixelBufferGetHeight(heatMap)   // 68
let bytesPerRow = CVPixelBufferGetBytesPerRow(heatMap)
let baseAddress = CVPixelBufferGetBaseAddress(heatMap)!

var maxVal: Float = 0
var maxPoint = CGPoint.zero
for y in 0..<mapH {
    let rowPtr = baseAddress.advanced(by: y * bytesPerRow)
    let floatPtr = rowPtr.assumingMemoryBound(to: Float.self)
    for x in 0..<mapW {
        if floatPtr[x] > maxVal {
            maxVal = floatPtr[x]
            maxPoint = CGPoint(x: CGFloat(x), y: CGFloat(y))
        }
    }
}

// Map to image coordinates
let imageX = (maxPoint.x / CGFloat(mapW)) * CGFloat(imageWidth)
let imageY = (maxPoint.y / CGFloat(mapH)) * CGFloat(imageHeight)
```

## Key Considerations

- Both saliency and face requests can run in parallel on the same handler
- Vision requests are thread-safe; run on background queue (or in an `actor`)
- Always pass `cgImage.imageOrientation` for EXIF handling
- If nothing is salient, attention-based defaults to center of image

## Complete SaliencyAnalyzer Actor Example

```swift
actor SaliencyAnalyzer {
    // MARK: - nonisolated for genuine parallelism in withThrowingTaskGroup
    // analyze accesses no actor-stored state — only local vars + Vision API.
    // Without nonisolated, each task's await self.analyze() serializes through
    // the actor's single-threaded executor, eliminating all parallelism.
    nonisolated func analyze(_ cgImage: CGImage) async throws -> SaliencyResult {
        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
        let faceRequest = VNDetectFaceRectanglesRequest()

        // Pass EXIF orientation for correct handling
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: cgImage.imageOrientation, options: [:])
        try handler.perform([saliencyRequest, faceRequest])

        // Process salientObjects bounding boxes (normalized, bottom-left origin)
        // Flip Y: flippedY = height - (box.minY + box.maxY)/2 * height
        // Return SaliencyResult(center, radius, confidence)
    }

    func analyzeAll(_ cgImages: [CGImage]) async throws -> [SaliencyResult] {
        try await withThrowingTaskGroup(of: (Int, SaliencyResult).self) { group in
            var results: [Int: SaliencyResult] = [:]
            for (index, image) in cgImages.enumerated() {
                group.addTask {
                    let result = try await self.analyze(image)  // Genuine parallelism
                    return (index, result)
                }
            }
            for try await (index, result) in group {
                results[index] = result
            }
            return (0..<cgImages.count).compactMap { results[$0] }
        }
    }
}
```

**Key points:**
- `actor` provides thread-safe async isolation
- **`nonisolated` on `analyze`** is required for genuine parallelism — without it, `withThrowingTaskGroup` tasks serialize through the actor executor. Caller extracts `CGImage` from `NSImage` on main thread before passing in.
- `withThrowingTaskGroup` for concurrent batch analysis
- Saliency heat map is 68x68 `CVPixelBuffer` of `Float` values
- `salientObjects` are `VNRectangleObservation` with normalized bounding boxes
- Vision coordinates: bottom-left origin, flip Y for top-left
- Always pass `cgImage.imageOrientation` to `VNImageRequestHandler`

## Pitfalls

- **Vision Y coordinates** — bottom-left origin, flip for top-left
- **EXIF orientation** — pass `cgImage.imageOrientation` to `VNImageRequestHandler`
