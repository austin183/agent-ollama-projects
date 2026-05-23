# vImage Dominant Colors — Research Document

> **Source:** [Apple Developer — Calculating the dominant colors in an image](https://developer.apple.com/documentation/Accelerate/calculating-the-dominant-colors-in-an-image)
> **Sample code download:** `CalculatingTheDominantColorsInAnImage.zip`
> **Availability:** macOS 14.0+, Xcode 15.2+

---

## Summary

Apple's Accelerate framework sample implements **k-means clustering** to extract `k` dominant (average) colors from an image. The algorithm works in 3D RGB space: it seeds `k` random centroids, iteratively assigns each pixel to its nearest centroid, then re-centers each centroid at the mean of its assigned pixels. The process repeats until centroid movement falls below a convergence tolerance.

The approach leverages three sub-libraries within Accelerate:
- **vImage** — pixel buffer management and `distanceSquared` computation
- **vDSP** — `gather` (indexed sample collection) and `mean` (average)
- **BNNS** (Brain Neural Network Suite) — `ReductionLayer` with `.argMin` for nearest-centroid assignment, and `scatter` for quantization

---

## Architecture and Data Flow

### Pixel Storage (vImage.PixelBuffer with External Storage)

The sample stores R, G, and B channels as **separate planar float buffers** using externally-allocated storage. This avoids vImage row-padding, which would corrupt pixel indexing during clustering.

```swift
let redStorage = UnsafeMutableBufferPointer<Float>.allocate(
    capacity: dimension * dimension)
let redBuffer: vImage.PixelBuffer<vImage.PlanarF>

// Initialized in init():
redBuffer = vImage.PixelBuffer<vImage.PlanarF>(
    data: redStorage.baseAddress!,
    width: dimension,
    height: dimension,
    byteCountPerRow: dimension * MemoryLayout<Float>.stride)
```

Repeat for `greenStorage`/`greenBuffer` and `blueStorage`/`blueBuffer`.

**Key design decision:** All images are scaled to `dimension * dimension` pixels before processing. This simplifies indexing (linear `row * width + col` into a flat array) and keeps memory predictable.

### Centroid Initialization (k-means++)

The first centroid is a random pixel. Subsequent centroids use **distance-weighted random selection** so that centroids spread across the color space rather than clustering together:

```swift
// First centroid: random pixel
let randomIndex = Int.random(in: 0 ..< dimension * dimension)
centroids.append(Centroid(
    red: redStorage[randomIndex],
    green: greenStorage[randomIndex],
    blue: blueStorage[randomIndex]))

// Subsequent centroids: weighted by distance from nearest existing centroid
for i in 1 ..< k {
    vImage.distanceSquared(
        x0: greenStorage.baseAddress!, x1: centroids[i - 1].green,
        y0: blueStorage.baseAddress!, y1: centroids[i - 1].blue,
        z0: redStorage.baseAddress!, z1: centroids[i - 1].red,
        n: greenStorage.count,
        result: tmp.baseAddress!)

    let randomIndex = weightedRandomIndex(tmp)
    centroids.append(Centroid(
        red: redStorage[randomIndex],
        green: greenStorage[randomIndex],
        blue: blueStorage[randomIndex]))
}
```

### Distance Calculation (vImage.distanceSquared)

For each iteration, compute squared Euclidean distance from every pixel to every centroid in 3D RGB space. Uses squared distance (not actual distance) to avoid sqrt overhead — only relative comparisons matter.

```swift
for centroid in centroids.enumerated() {
    vImage.distanceSquared(
        x0: greenStorage.baseAddress!, x1: centroid.element.green,
        y0: blueStorage.baseAddress!, y1: centroid.element.blue,
        z0: redStorage.baseAddress!, z1: centroid.element.red,
        n: greenStorage.count,
        result: distances.baseAddress!
            .advanced(by: dimension * dimension * centroid.offset))
}
```

The `distances` buffer is shaped as `[numPixels][k]` — one row per pixel, one column per centroid.

### Nearest Centroid Assignment (BNNS ReductionLayer)

Uses `BNNS.ReductionLayer` with `.argMin` to find, for each pixel, the index of the closest centroid:

```swift
func makeCentroidIndices() -> [Int32] {
    let distancesDescriptor = BNNSNDArrayDescriptor(
        data: distances,
        shape: .matrixRowMajor(dimension * dimension, k))!

    let reductionLayer = BNNS.ReductionLayer(
        function: .argMin,
        input: distancesDescriptor,
        output: centroidIndicesDescriptor,
        weights: nil)

    try! reductionLayer?.apply(
        batchSize: 1,
        input: distancesDescriptor,
        output: centroidIndicesDescriptor)

    return centroidIndicesDescriptor.makeArray(of: Int32.self)!
}
```

Result: `[Int32]` array where each element is the centroid index (0..k-1) for the corresponding pixel.

### Color Gathering and Centroid Update (vDSP)

For each centroid, filter the indices array to find pixels assigned to that centroid, then use `vDSP.gather` to collect those pixel values, and `vDSP.mean` to compute the new centroid position:

```swift
// Indices of pixels assigned to this centroid (1-based for vDSP)
let indices = centroidIndices.enumerated()
    .filter { $0.element == centroid.offset }
    .map { UInt($0.offset + 1) }

// Gather color values for assigned pixels
let gatheredRed = vDSP.gather(redStorage, indices: indices)
let gatheredGreen = vDSP.gather(greenStorage, indices: indices)
let gatheredBlue = vDSP.gather(blueStorage, indices: indices)

// Update centroid to mean of assigned pixels
centroids[centroid.offset].red = vDSP.mean(gatheredRed)
centroids[centroid.offset].green = vDSP.mean(gatheredGreen)
centroids[centroid.offset].blue = vDSP.mean(gatheredBlue)
```

### Convergence

The k-means loop repeats the distance → argMin → gather → mean cycle until the maximum centroid displacement per iteration falls below a tolerance threshold.

### Quantization (BNNS.scatter)

After convergence, the sample demonstrates quantizing the image by replacing each pixel with its nearest centroid's color. Uses `BNNS.scatter`, the inverse of `gather`:

```swift
func scatter(value: Float, to destination: UnsafeMutableBufferPointer<Float>) {
    let indicesDescriptor = BNNSNDArrayDescriptor.allocate(
        initializingFrom: indices,
        shape: .vector(indices.count))
    defer { indicesDescriptor.deallocate() }

    let srcDescriptor = BNNSNDArrayDescriptor.allocate(
        repeating: value,
        shape: .vector(indices.count))
    let dstDescriptor = BNNSNDArrayDescriptor(
        data: destination,
        shape: .vector(dimension * dimension))!

    try! BNNS.scatter(
        input: srcDescriptor,
        indices: indicesDescriptor,
        output: dstDescriptor,
        axis: 0,
        reductionFunction: .sum)
    srcDescriptor.deallocate()
}

// Apply per-channel:
scatter(value: centroid.element.red, to: redQuantizedStorage)
scatter(value: centroid.element.green, to: greenQuantizedStorage)
scatter(value: centroid.element.blue, to: blueQuantizedStorage)
```

---

## Key Algorithms and Data Structures

| Component | Type | Purpose |
|-----------|------|---------|
| `Centroid` | struct `(red: Float, green: Float, blue: Float)` | Represents a cluster center in RGB space |
| `distances` | `UnsafeMutableBufferPointer<Float>` | `[numPixels * k]` squared distances |
| `centroidIndices` | `[Int32]` | `[numPixels]` nearest centroid index per pixel |
| `indices` | `[UInt]` | 1-based pixel indices for one centroid's cluster |
| `vImage.PixelBuffer<vImage.PlanarF>` | struct | Planar float pixel buffer with external storage |
| `BNNSNDArrayDescriptor` | class | Describes multi-dimensional array shape for BNNS ops |

---

## Applicability to CollageMaker: "Auto-Match Background Color to Image"

### How This Maps to the Feature

The CollageMaker "auto-match background color" feature needs to extract a representative background color from each image in a collage. The k-means approach is directly applicable:

1. **Set `k = 5`** (or similar small number) to extract the 5 dominant colors.
2. **Compute color frequencies** — multiply each centroid's pixel count by the centroid's color to get a weighted average, or simply pick the centroid with the most assigned pixels as the "background" color.
3. **Apply as `CanvasView` background** — the dominant color becomes the canvas background color behind the collage layout.

### Simplification for CollageMaker

The full k-means implementation is overkill if you only need **one** dominant background color. Consider these lighter alternatives:

| Approach | Complexity | Quality |
|----------|-----------|---------|
| Full k-means (Apple sample) | High | Best color representation |
| Histogram-based dominant color | Medium | Good, faster |
| Corner pixel sampling | Low | Fast, may miss dominant colors |
| vImage histogram + peak detection | Medium | Good balance (see related Apple sample: "Specifying histograms with vImage") |

For CollageMaker, the **histogram approach** from the related Apple sample "Specifying histograms with vImage" may be more appropriate if you only need a single background color, since it avoids the iterative k-means loop. However, k-means produces more semantically meaningful colors (actual averages of color regions rather than histogram bins).

### Recommended Integration Path

1. **Download the Apple sample code** and extract the `KMeansCalculator` struct.
2. **Adapt the pixel extraction** to work with `CGImage` → `vImage.PixelBuffer` conversion (the sample handles this).
3. **Scale input images** to a small dimension (e.g., 64x64) for fast processing — the sample already does this.
4. **Run k-means with k=5**, then select the centroid with the highest pixel count as the background color.
5. **Cache the result** per image to avoid recomputation on every layout change.

---

## Performance Considerations

### Memory

- Each channel uses `dimension * dimension * MemoryLayout<Float>.stride` bytes.
- For a 256×256 image: 3 channels × 256 × 256 × 4 bytes = **~768 KB** for pixel storage.
- The `distances` buffer: `dimension * dimension * k * 4` bytes. For 256×256, k=5: **~1.3 MB**.
- Total working memory: **~2-3 MB** for a 256×256 image. Very manageable.

### Speed

- `vImage.distanceSquared` is vectorized (SIMD) and runs in C — extremely fast.
- `BNNS.ReductionLayer` with `.argMin` is hardware-accelerated on Apple Silicon.
- `vDSP.gather` and `vDSP.mean` are also vectorized.
- The iterative nature of k-means means 5-20 iterations typical. Each iteration is O(n×k) where n = pixel count.
- Scaling images to small dimensions (64-256px) before processing keeps n small.

### Optimization Tips

- **Downscale aggressively:** A 64×64 thumbnail produces visually identical dominant colors at 1/16th the computation.
- **Limit iterations:** Cap at 10-15 iterations with a reasonable tolerance. Most images converge in 5-8 iterations.
- **Run off-main-thread:** Wrap in `Task { ... }` or `DispatchQueue.global().async` to avoid UI jank.
- **Cache per-image:** Store the dominant color in a `[NSUUID: Color]` dictionary keyed by image identifier.
- **Reuse buffers:** Allocate storage buffers once and reuse across images of the same dimension.

---

## Gotchas and macOS-Specific Considerations

### vImage Row Padding

vImage traditionally adds padding bytes to row ends for alignment. The sample avoids this by using **external storage** (`UnsafeMutableBufferPointer` + `vImage.PixelBuffer` with explicit `byteCountPerRow`). If you use the default vImage buffer allocation, row padding will cause incorrect pixel indexing during k-means.

### Float Precision

All color values are `Float` (32-bit). This is sufficient for color representation but be aware that repeated mean operations can accumulate small floating-point errors. The convergence tolerance should account for this (e.g., `1e-4` rather than `1e-10`).

### BNNS Error Handling

The sample uses `try!` for BNNS operations. In production code, wrap these in proper `do-catch` blocks. BNNS can throw if:
- Array descriptors have incompatible shapes.
- Memory allocation fails for large images.
- The device lacks BNNS support (unlikely on macOS 14+).

### Thread Safety

- `vImage` functions are thread-safe when operating on separate buffers.
- `BNNS` operations should not be called concurrently on the same descriptors.
- Use a dedicated serial queue or `Task` isolation for the k-means computation.

### CGImage → PixelBuffer Conversion

The sample includes code to extract pixel data from a `CGImage` into the planar float buffers. Key steps:
1. Create a `CGContext` with `CGImage` and 32-bit RGBA color space.
2. Draw the image into the context.
3. Copy the data provider's bytes into the R, G, B storage buffers.
4. Normalize byte values (0-255) to float range (0.0-1.0).

### macOS 14.0+ Requirement

The `vImage.PixelBuffer` Swift API and BNNS Swift bindings require macOS 14.0+. If CollageMaker targets an earlier deployment target, you'll need to use the C APIs (`vImage_Buffer`, `vImageDistance_ARGB8888`, etc.) with `@available` guards.

### Color Space

The sample works in **sRGB** space. For perceptually-uniform color matching, consider converting to **CIELAB** or **OKLAB** before clustering. The related Apple sample "Adjusting the hue of an image" demonstrates L*a*b* conversion with vImage, which could be combined with this k-means approach for better perceptual results.

---

## Related Apple Samples

| Sample | Relevance |
|--------|-----------|
| [Specifying histograms with vImage](https://developer.apple.com/documentation/accelerate/specifying-histograms-with-vimage) | Alternative histogram-based approach for dominant color |
| [Enhancing image contrast with histogram manipulation](https://developer.apple.com/documentation/accelerate/enhancing-image-contrast-with-histogram-manipulation) | Histogram techniques for color analysis |
| [Adjusting the hue of an image](https://developer.apple.com/documentation/accelerate/adjusting-the-hue-of-an-image) | L*a*b* color space conversion with vImage |
| [Core Graphics interoperability](https://developer.apple.com/documentation/accelerate/core-graphics-interoperability) | CGImage ↔ vImage buffer conversion patterns |
| [Optimizing image-processing performance](https://developer.apple.com/documentation/accelerate/optimizing-image-processing-performance) | Performance tips for vImage pipelines |
