# Vision Framework — Saliency & Face Detection

## Overview

The Vision framework provides ML-based image analysis. For the CollageMaker project, two request types are critical:
- **Saliency analysis** — identifies the most visually important/prominent regions
- **Face detection** — locates faces to boost their importance in saliency scoring

## API Versions

Vision has **two API surfaces**:

| API | Availability | Style |
|---|---|---|
| **Swift-only (new)** | iOS 18+, macOS 15+ | `struct GenerateAttentionBasedSaliencyImageRequest`, `perform(on:)` async |
| **Legacy (Obj-C + Swift)** | iOS 11+, macOS 10.13+ | `class VNGenerateAttentionBasedSaliencyImageRequest`, `VNImageRequestHandler.perform(_:)` |

For maximum compatibility, the legacy API is the safer choice since it supports older macOS versions.

## Saliency Types

### Attention-Based Saliency
- Trained on **eye-tracking data** from human subjects
- Highlights what people are **likely to look at**
- Best for: deciding what to keep in a thumbnail/crop
- Returns: single bounding box at center of attention

### Objectness-Based Saliency
- Trained on **foreground objects segmented from background**
- Highlights **foreground objects**, provides coarse segmentation
- Returns: up to 3 bounding boxes with scores
- Best for: identifying distinct objects in the image

**Recommendation:** Use **attention-based** saliency for collage cropping, since we want to preserve what draws the eye.

## Saliency Request (Legacy API)

```swift
import Vision

// Create request
let request = VNGenerateAttentionBasedSaliencyImageRequest()

// Create handler from CGImage (from NSImage)
let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

// Execute
try handler.perform([request])

// Get result
let observation = request.results?.first as? VNSaliencyImageObservation
```

### `VNSaliencyImageObservation` Result

- **`heatMap`** (`CVPixelBuffer`): 68x68 pixel buffer of floating-point saliency values [0, 1]
- **`salientObjects`** (`[VNRectangleObservation]`): bounding boxes for distinct salient areas
  - Each has `boundingBox` (normalized CGRect) and `confidence`

### Converting Normalized Coordinates to Image Coordinates

```swift
// Convert normalized rect to image coordinates
let imageRect = VNImageRectForNormalizedRect(
    normalizedRect,
    Int(imageWidth),
    Int(imageHeight)
)

// Convert normalized point to image point
let imagePoint = VNImagePointForNormalizedPoint(
    normalizedPoint,
    Int(imageWidth),
    Int(imageHeight)
)
```

## New Swift-Only API (macOS 15+)

```swift
import Vision

let request = GenerateAttentionBasedSaliencyImageRequest()

// Direct async call — no handler needed
let observations = try await request.perform(on: cgImage)
// observations: SaliencyImageObservation
// - heatMap: PixelBufferObservation
// - salientObjects: [RectangleObservation]
```

The new API supports `perform(on:)` directly on: `URL`, `Data`, `CGImage`, `CVPixelBuffer`, `CMSampleBuffer`, `CIImage`.

## Face Detection

### `VNDetectFaceRectanglesRequest` (Legacy)

```swift
let request = VNDetectFaceRectanglesRequest()
let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
try handler.perform([request])

let faceObservations = request.results as? [VNFaceObservation]
for face in faceObservations ?? [] {
    let boundingBox = face.boundingBox // Normalized CGRect
    let imageRect = VNImageRectForNormalizedRect(boundingBox, Int(w), Int(h))
}
```

### `FaceObservation` (New API, macOS 15+)

```swift
let request = DetectFaceRectanglesRequest()
let results = try await request.perform(on: cgImage)
// results: [FaceObservation]
```

Each `VNFaceObservation` / `FaceObservation` provides:
- `boundingBox`: NormalizedRect — face location
- `yaw`, `pitch`, `roll`: face orientation angles
- `landmarks`: facial feature points (eyes, mouth, nose)
- `captureQuality`: quality indicator

## Combining Saliency + Face Boost

The CollageMaker plan calls for boosting face regions in the saliency map. Approach:

1. Run `VNGenerateAttentionBasedSaliencyImageRequest` → get heat map
2. Run `VNDetectFaceRectanglesRequest` → get face bounding boxes
3. For each face bounding box, increase saliency values in the corresponding heat map region
4. Find the maximum intensity point in the combined heat map → center of interest

Alternatively, use the `salientObjects` bounding boxes directly without manual face boosting, since attention-based saliency already weights faces heavily.

## Key Considerations

- Saliency heat map is **68x68** — low resolution, needs upsampling for overlay
- Normalized coordinates use origin (0,0) at **bottom-left** (not top-left)
- If nothing is salient, attention-based saliency defaults to the **center of the image**
- Both requests can run in parallel on the same `VNImageRequestHandler`
- Vision requests are thread-safe; run on background queue
