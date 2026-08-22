# CGImage Pixel Extraction via CGBitmapContext

**Date:** 2026-06-26

## Problem

When extracting pixel data from a `CGImage` for comparison or analysis, the naive approach of casting `cgImage.dataProvider?.data as? Data` is unreliable:

```swift
// ❌ UNRELIABLE APPROACH
func extractPixelData(from cgImage: CGImage) -> [UInt8]? {
    let width = cgImage.width
    let height = cgImage.height
    let bytesPerRow = cgImage.bytesPerRow
    
    guard let providerData = cgImage.dataProvider?.data as? Data else { return nil }
    
    var pixelData = [UInt8](repeating: 0, count: height * bytesPerRow)
    providerData.copyBytes(to: &pixelData, count: height * bytesPerRow)
    return pixelData
}
```

**Issues with this approach:**
1. `cgImage.dataProvider?.data` returns a `CFData` (or similar) object, and casting it directly to `Data` is fragile
2. The raw bytes in the data provider are **not guaranteed** to be in the RGBA8 format that comparison logic assumes
3. Images may use different color spaces or pixel formats (e.g., YCbCr, grayscale, 16-bit per component)
4. This causes `extractPixelData` to return `nil` or contain bytes in a format that causes comparison logic to produce wrong results or crash

## Solution: CGBitmapContext with Known Format

Draw the `CGImage` into a `CGBitmapContext` with a known format (e.g., `kCGImageAlphaPremultipliedLast`) to extract a guaranteed RGBA pixel buffer:

```swift
// ✅ RELIABLE APPROACH
func extractPixelData(from cgImage: CGImage) -> [UInt8]? {
    let width = cgImage.width
    let height = cgImage.height
    // Align bytesPerRow to 32-bit boundary
    let bytesPerRow = (width * 4 + 31) / 32 * 32
    
    guard let context = CGContext(data: nil,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    
    // Draw the image into the context
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    
    guard let data = context.data else { return nil }
    let pointer = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
    return Array(UnsafeBufferPointer(start: pointer, count: bytesPerRow * height))
}
```

## Key Details

### Bytes Per Row Alignment
CoreGraphics requires `bytesPerRow` to be aligned to a 32-bit (4-byte) boundary. The formula `(width * 4 + 31) / 32 * 32` ensures proper alignment for RGBA8 images:
- `width * 4` = bytes per row without alignment
- `+ 31 / 32 * 32` = round up to nearest multiple of 32

### Color Space and Alpha Info
- **Color Space:** `CGColorSpaceCreateDeviceRGB()` ensures RGB color space
- **Alpha Info:** `CGImageAlphaInfo.premultipliedLast.rawValue` ensures the alpha channel is the last component (RGBA format), which matches the comparison logic expecting `[r, g, b, a]` per pixel

### Memory Safety
- `context.data` returns an `UnsafeMutableRawPointer`
- `bindMemory(to:UInt8.self,capacity:)` converts it to an `UnsafeMutablePointer<UInt8>`
- `UnsafeBufferPointer(start:count:)` creates a safe buffer view
- `Array(...)` copies the data into a Swift `[UInt8]` array

## When to Use

Use this approach when:
- You need to compare pixel data between two images (e.g., export vs preview consistency tests)
- You need to sample specific pixels from a `CGImage` for validation
- You need guaranteed RGBA8 format regardless of the source image's original color space or pixel format

## Related Patterns

- **Pixel comparison tolerance:** Use mean absolute error per channel with tolerance (e.g., `tolerance: 5` for near-lossless JPEG at quality 1.0, `tolerance: 10` for preview vs export)
- **NSImage to CGImage conversion:** Use `nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)` before extracting pixel data
