# vImage Blurring — Apple Sample Code Research

> Source: [Blurring an image — Accelerate Framework](https://developer.apple.com/documentation/Accelerate/blurring-an-image)
> Availability: macOS 13.3+, Xcode 14.3+
> Download: [BlurringAnImage.zip](https://docs-assets.developer.apple.com/published/a8a4b9753f10/BlurringAnImage.zip)

---

## Summary

This Apple sample code project demonstrates a variety of convolution techniques for blurring images using the Accelerate framework's vImage library. It covers four distinct approaches, ranging from simple box blur to multi-kernel per-channel convolution, with increasing quality and complexity.

**Core concept:** Convolution transforms each pixel by combining it with its neighbors according to a kernel (a grid of weights). The sample builds a SwiftUI app with a `Picker` to switch between blur modes.

---

## Blur Techniques Covered

### 1. 2D Kernel Convolution (Box Blur / Custom Kernel)

A **box blur** kernel averages neighboring pixel values. A 3×3 box blur kernel divides each of nine neighbor values by 9.

**Key rules:**
- Kernel dimensions must be **odd** to center over the target pixel.
- Kernels should be **normalized** (sum of all values = 1). If sum > 1, output brightens; if < 1, output darkens.

**Custom 2D kernel (Hann window, 7×7, Int16):**
```swift
let kernel2D: [Int16] = [
    0, 0, 0, 0, 0, 0, 0,
    0, 2025, 6120, 8145, 6120, 2025, 0,
    0, 6120, 18496, 24616, 18496, 6120, 0,
    0, 8145, 24616, 32761, 24616, 8145, 0,
    0, 6120, 18496, 24616, 18496, 6120, 0,
    0, 2025, 6120, 8145, 6120, 2025, 0,
    0, 0, 0, 0, 0, 0, 0
]
```

**Normalization for integer kernels:**
```swift
let divisor = weights.map { Int32($0) }.reduce(0, +)
```

**Convolution call:**
```swift
sourceBuffer.convolve(with: kernel,
                      divisor: divisor,
                      edgeMode: .extend,
                      destination: destinationBuffer)
```

### 2. Separable 1D Kernel Convolution

A separable kernel is the **outer product** of two 1D vectors (horizontal × vertical). Instead of one 2D pass requiring `M × N` operations per pixel, two 1D passes each require only `M + N` operations — a significant speedup.

**1D kernel (Float, 7 elements):**
```swift
let kernel1D: [Float] = [0, 45, 136, 181, 136, 45, 0]
```

**Workflow:**
```swift
// Create planar buffers
let planarSourceBuffers = vImage.PixelBuffer<vImage.Planar8x4>(size: sourceBuffer.size)
let planarDestinationBuffers = vImage.PixelBuffer<vImage.Planar8x4>(size: sourceBuffer.size)

// Convert interleaved source to planar
sourceBuffer.deinterleave(destination: planarSourceBuffers)

// Apply separable convolution
planarSourceBuffers.separableConvolve(horizontalKernel: kernel,
                                       verticalKernel: kernel,
                                       edgeMode: .extend,
                                       destination: planarDestinationBuffers)
```

**Important:** Separable convolution requires **planar** buffers (`vImage.Planar8x4`), not interleaved. The sample converts using `deinterleave(_:)`. Single-precision `Float` values allow increased precision over `Int16`.

### 3. High-Speed Built-In Kernels

vImage provides two optimized built-in blur functions that do not require supplying a kernel:

#### Box Filter (`boxConvolve`)
- Returns the average pixel value in a rectangular region.
- **Fastest** blur option but produces rectangular artifacts.

```swift
sourceBuffer.boxConvolve(kernelSize: .init(width: kernelLength,
                                            height: kernelLength),
                          edgeMode: .extend,
                          destination: destinationBuffer)
```

#### Tent Filter (`tentConvolve`)
- Returns a **weighted average** in a circular region — pixels farther from center have less influence.
- Smoother result than box filter, slightly slower.

```swift
sourceBuffer.tentConvolve(kernelSize: .init(width: kernelLength,
                                             height: kernelLength),
                           edgeMode: .extend,
                           destination: destinationBuffer)
```

**Gotcha:** Passing `vImage.EdgeMode.truncateKernel` to high-speed kernels can **significantly impact performance**. Only use this flag when vImage must restrict calculations to the portion of the kernel overlapping the image.

### 4. Multi-Kernel Per-Channel Convolution

vImage can apply **four separate kernels** — one per channel (R, G, B, A) — in a single convolution pass. Available only for interleaved formats `vImage.Planar8x4` and `vImage.PlanarFx4`.

**Example: decreasing-radius circular kernels per channel:**
```swift
let radius = kernelLength / 2
let diameter = (radius * 2) + 1

let kernels: [vImage.ConvolutionKernel2D<Int16>] = (1 ... 4).map { index in
    let weights = [Int16](unsafeUninitializedCapacity: diameter * diameter) { buffer, initializedCount in
        for x in 0 ..< diameter {
            for y in 0 ..< diameter {
                if hypot(Float(radius - x), Float(radius - y)) < Float(radius / index) {
                    buffer[y * diameter + x] = 1
                } else {
                    buffer[y * diameter + x] = 0
                }
            }
        }
        initializedCount = diameter * diameter
    }
    return vImage.ConvolutionKernel2D(values: weights,
                                       size: .init(width: kernelLength, height: kernelLength))
}

let divisors = kernels.map { return Int32($0.values.reduce(0, +)) }

sourceBuffer.convolve(with: (kernels[0], kernels[1], kernels[2], kernels[3]),
                      divisors: (divisors[0], divisors[1], divisors[2], divisors[3]),
                      edgeMode: .extend,
                      destination: destinationBuffer)
```

**Effect:** Produces a color-fringing artifact because each channel is blurred with a different kernel radius. Useful for compensating RGB phosphor positioning, or creatively for chromatic aberration effects.

---

## Key Algorithms and Performance Considerations

| Technique | Speed | Quality | Buffer Format | Notes |
|---|---|---|---|---|
| Box filter | Fastest | Lowest (rectangular artifacts) | Interleaved | No kernel needed |
| Tent filter | Fast | Good (circular weighted avg) | Interleaved | No kernel needed |
| 2D custom kernel | Medium | High (Hann window) | Interleaved | Requires normalization |
| Separable 1D kernel | Fast | High | Planar | Must deinterleave first |
| Multi-kernel | Medium | Specialized | Planar 4-channel | Per-channel control |

**Performance math:** For kernel dimensions M×N:
- 2D convolution per pixel: `M × N` multiplications + additions
- Separable 1D per pixel: `M + N` multiplications + additions (two passes)

For a 7×7 kernel: 2D = 49 ops/pixel, separable = 14 ops/pixel — **3.5× faster**.

**Edge mode:** Use `.extend` to replicate edge pixels. Avoid `.truncateKernel` on high-speed kernels unless necessary — it degrades performance.

---

## Applicability to CollageMaker: Blurred Background Image Mode

For a collage maker app, the **blurred background** is a common feature where the canvas background is a blurred version of the user's photos or a solid gradient.

### Recommended Approach

**Tent filter** is the best balance for CollageMaker:
- No kernel authoring required — just specify kernel size.
- Smooth, natural-looking blur without rectangular artifacts.
- Fast enough for real-time preview on macOS.
- Works directly on interleaved buffers (no planar conversion needed).

```swift
sourceBuffer.tentConvolve(kernelSize: .init(width: 31, height: 31),
                           edgeMode: .extend,
                           destination: destinationBuffer)
```

A kernel size of 31–63 produces a strong background blur suitable for placing collage elements on top.

### Alternative: Box filter for performance

If performance is critical (e.g., live drag-and-drop with continuous blur updates), the **box filter** is faster. Stack two box filter passes to approximate Gaussian quality and reduce artifacts.

### Integration Notes

1. **Convert CGImage → vImage buffer** using `vImage.PixelBuffer<vImage.Interleaved8x4>(cgImage:)`
2. **Allocate destination buffer** of same size
3. **Apply blur** on a background queue (`DispatchQueue.global(qos: .userInitiated)`)
4. **Convert back** to CGImage via `destinationBuffer.createCGImage()`
5. **Cache** the blurred result if the source image hasn't changed

### Related Apple Docs to Explore

- [Converting bitmap data between Core Graphics images and vImage buffers](https://developer.apple.com/documentation/accelerate/converting-bitmap-data-between-core-graphics-images-and-vimage-buffers)
- [Creating and Populating Buffers from Core Graphics Images](https://developer.apple.com/documentation/accelerate/creating-and-populating-buffers-from-core-graphics-images)
- [Creating a Core Graphics Image from a vImage Buffer](https://developer.apple.com/documentation/accelerate/creating-a-core-graphics-image-from-a-vimage-buffer)
- [Optimizing image-processing performance](https://developer.apple.com/documentation/accelerate/optimizing-image-processing-performance)
- [Building a Basic Image-Processing Workflow](https://developer.apple.com/documentation/accelerate/building-a-basic-image-processing-workflow)

---

## Gotchas and macOS-Specific Considerations

1. **Integer kernel normalization:** When using `Int16` kernels, you must pass a `divisor` equal to the sum of all kernel elements. Floating-point kernels (`Float`) are self-normalizing.

2. **Planar vs. interleaved:** Separable convolution (`separableConvolve`) and multi-kernel convolution require **planar** buffers (`Planar8x4`). Standard convolution and high-speed filters work with **interleaved** buffers (`Interleaved8x4`). Use `deinterleave(_:)` and `interleave(_:)` to convert.

3. **Odd kernel dimensions:** Both dimensions of a convolution kernel must be odd numbers to center the kernel over the target pixel.

4. **`truncateKernel` edge mode penalty:** Passing `vImage.EdgeMode.truncateKernel` to `boxConvolve` or `tentConvolve` significantly degrades performance. Only use when you need vImage to skip kernel regions that fall outside the image bounds.

5. **Thread safety:** vImage operations are thread-safe but not reentrant on the same buffer. Run blurring on a background queue to avoid blocking the SwiftUI main thread.

6. **Memory allocation:** `vImage.PixelBuffer` allocates contiguous memory. For large images, pre-allocate and reuse buffers across multiple blur operations to avoid allocation overhead.

7. **Availability:** The Swift API for vImage (`vImage.PixelBuffer`, `convolve`, `boxConvolve`, `tentConvolve`, `separableConvolve`) requires **macOS 13.3+**. For earlier targets, use the C API from `<Accelerate/vImage.h>`.
