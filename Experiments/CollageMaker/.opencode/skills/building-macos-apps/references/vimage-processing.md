# vImage Processing

Accelerate framework techniques for fast pixel-level image operations: blurring, color extraction, and convolution.

## CGImage to vImage Buffer Conversion

```swift
// From CGImage to interleaved RGBA buffer
let sourceBuffer = vImage.PixelBuffer<vImage.Interleaved8x4>(cgImage: sourceImage)

// From vImage buffer back to CGImage
let resultImage = destinationBuffer.createCGImage()
```

For planar float buffers with external storage (required by k-means clustering):

```swift
let storage = UnsafeMutableBufferPointer<Float>.allocate(capacity: w * h)
let buffer = vImage.PixelBuffer<vImage.PlanarF>(
    data: storage.baseAddress!,
    width: w,
    height: h,
    byteCountPerRow: w * MemoryLayout<Float>.stride
)
```

**Row padding:** Default vImage buffers add padding bytes for alignment. Use external storage with explicit `byteCountPerRow` when doing manual pixel indexing to avoid corruption.

## Blurring

### Built-in High-Speed Filters (Recommended)

No kernel authoring needed. Work directly on interleaved buffers.

**Tent filter** — best balance of speed and quality:
```swift
let destination = vImage.PixelBuffer<vImage.Interleaved8x4>(size: sourceBuffer.size)
sourceBuffer.tentConvolve(
    kernelSize: vImage.PixelExtent2D(width: 31, height: 31),
    edgeMode: .extend,
    destination: destination
)
```

**Box filter** — fastest but produces rectangular artifacts:
```swift
sourceBuffer.boxConvolve(
    kernelSize: vImage.PixelExtent2D(width: 31, height: 31),
    edgeMode: .extend,
    destination: destination
)
```

Stack two box filter passes to approximate Gaussian quality.

### Separable 1D Kernel Convolution

For custom kernels, separable convolution is 3.5x faster than 2D (14 vs 49 ops/pixel for 7x7). Requires **planar** buffers:

```swift
let planarSource = vImage.PixelBuffer<vImage.Planar8x4>(size: sourceBuffer.size)
let planarDest = vImage.PixelBuffer<vImage.Planar8x4>(size: sourceBuffer.size)
sourceBuffer.deinterleave(destination: planarSource)

let kernel: [Float] = [0, 45, 136, 181, 136, 45, 0]
planarSource.separableConvolve(
    horizontalKernel: kernel,
    verticalKernel: kernel,
    edgeMode: .extend,
    destination: planarDest
)
```

### Custom 2D Kernel

```swift
let kernel: [Int16] = [
    0, 0, 0, 0, 0, 0, 0,
    0, 2025, 6120, 8145, 6120, 2025, 0,
    0, 6120, 18496, 24616, 18496, 6120, 0,
    0, 8145, 24616, 32761, 24616, 8145, 0,
    0, 6120, 18496, 24616, 18496, 6120, 0,
    0, 2025, 6120, 8145, 6120, 2025, 0,
    0, 0, 0, 0, 0, 0, 0
]
let divisor = kernel.map { Int32($0) }.reduce(0, +)

sourceBuffer.convolve(with: kernel, divisor: divisor, edgeMode: .extend, destination: destination)
```

**Rules:** Kernel dimensions must be odd. Integer kernels require normalization via `divisor`. Float kernels are self-normalizing.

## Dominant Color Extraction (k-means)

Extract `k` representative colors from an image using k-means clustering in RGB space.

### Algorithm Overview

1. Scale image to small dimension (64-256px) for fast processing
2. Extract R, G, B channels into separate planar float buffers
3. Seed `k` centroids using k-means++ (distance-weighted random selection)
4. Iterate: compute per-pixel distances to all centroids, assign nearest, re-center
5. Converge when centroid displacement falls below tolerance

### Distance Calculation

```swift
vImage.distanceSquared(
    x0: greenStorage.baseAddress!, x1: centroid.green,
    y0: blueStorage.baseAddress!, y1: centroid.blue,
    z0: redStorage.baseAddress!, z1: centroid.red,
    n: greenStorage.count,
    result: distances.baseAddress!
)
```

Squared Euclidean distance avoids sqrt overhead — only relative comparisons matter.

### Nearest Centroid Assignment (BNNS)

```swift
let descriptor = BNNSNDArrayDescriptor(
    data: distances,
    shape: .matrixRowMajor(pixelCount, k)
)!

let layer = BNNS.ReductionLayer(
    function: .argMin,
    input: descriptor,
    output: indicesDescriptor,
    weights: nil
)
try layer?.apply(batchSize: 1, input: descriptor, output: indicesDescriptor)
```

### Centroid Update (vDSP)

```swift
let indices = centroidIndices.enumerated()
    .filter { $0.element == centroidIndex }
    .map { UInt($0.offset + 1) }  // 1-based for vDSP

let gatheredRed = vDSP.gather(redStorage, indices: indices)
centroids[centroidIndex].red = vDSP.mean(gatheredRed)
```

### Selecting Background Color

After convergence, pick the centroid with the highest pixel count as the dominant background color:

```swift
let backgroundCentroid = centroids.max(by: { a, b in
    a.pixelCount < b.pixelCount
})!
```

### Simpler Alternative: Histogram Approach

For a single dominant color, vImage histogram + peak detection may be sufficient and avoids the iterative k-means loop. See Apple sample "Specifying histograms with vImage".

## Performance

| Operation | Time (Apple Silicon) | Notes |
|-----------|---------------------|-------|
| Tent blur 1920x1080, k=31 | ~5ms | Background queue |
| k-means 256x256, k=5 | ~10ms | 5-8 iterations typical |
| k-means 64x64, k=5 | ~1ms | Downscale aggressively |

### Optimization Checklist

- **Downscale before processing:** 64x64 produces visually identical dominant colors at 1/16th the computation
- **Run off-main-thread:** `Task { ... }` or `DispatchQueue.global(qos: .userInitiated)`
- **Cache per-image:** Store results in `[NSUUID: Color]` dictionary
- **Reuse buffers:** Allocate once, reuse across images of same dimension
- **Limit iterations:** Cap at 10-15 with tolerance `1e-4`

## Gotchas

- **`.truncateKernel` degrades performance** — Only use `vImage.EdgeMode.truncateKernel` on high-speed kernels when necessary. It significantly slows `boxConvolve`/`tentConvolve`.
- **Planar vs interleaved:** `separableConvolve` and multi-kernel require planar (`Planar8x4`). Standard convolution and high-speed filters work with interleaved (`Interleaved8x4`).
- **Thread safety:** vImage is thread-safe on separate buffers. BNNS is not reentrant on same descriptors.
- **Float precision:** Repeated `vDSP.mean` can accumulate small errors. Use tolerance `1e-4`, not `1e-10`.
- **BNNS error handling:** Wrap `try!` in `do-catch`. BNNS throws on incompatible shapes or memory allocation failure.
- **Color space:** k-means works in sRGB. For perceptually-uniform results, convert to CIELAB first.
- **macOS 13.3+** for Swift vImage API. macOS 14.0+ for BNNS Swift bindings.
