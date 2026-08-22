# Session 135 — Visual Validation Automation Phase 2: Export-Preview Consistency

**Date:** 2026-06-26
**Plan:** `2026-06-24-visual-validation-automation.md` Phase 2

## Summary

Implemented Phase 2 of the visual validation automation plan: `ExportConsistencyTests.swift` with 5 tests validating export-preview consistency and layout exports. Created helper methods for decoding Data → NSImage → CGImage → pixel buffer, then fixed critical bugs identified in diff-review-g31 review.

## Tests Implemented

1. **`exportMatchesPreviewAtFullResolution`** - Renders preview at full canvas size (1920x1080) and export at quality 1.0, validates both produce valid images with matching dimensions and compares pixel data within tolerance
2. **`exportQualityAffectsFileSize`** - Assembles same collage at quality 0.1 and 1.0, asserts quality 1.0 produces larger file than 0.1
3. **`exportWithTitleAndBackground`** - Exports collage with title text and solid background, verifies output has non-background pixels in title region
4. **`exportWithDiagonalSlicesLayout`** - Generates diagonal slices layout, exports and verifies valid JPEG data with correct dimensions
5. **`exportWithHexagonalLayout`** - Generates hexagonal layout, exports and verifies valid output with correct dimensions

## Critical Bugs Fixed from Diff-Review

### High Severity: `extractPixelData` unreliable data access
**Problem:** Original implementation used `cgImage.dataProvider?.data as? Data`, which is fragile and doesn't guarantee RGBA8 format bytes. The raw bytes in the data provider are not guaranteed to be in the RGBA8 format that the comparison logic assumes.

**Fix:** Replaced with `CGBitmapContext` drawing using `kCGImageAlphaPremultipliedLast` format:
```swift
func extractPixelData(from cgImage: CGImage) -> [UInt8]? {
    let width = cgImage.width
    let height = cgImage.height
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
    
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    
    guard let data = context.data else { return nil }
    let pointer = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
    return Array(UnsafeBufferPointer(start: pointer, count: bytesPerRow * height))
}
```

### High Severity: `exportMatchesPreviewAtFullResolution` missed pixel comparison
**Problem:** Test only verified both preview and export were non-nil and had correct dimensions, completely omitting the actual pixel comparison logic.

**Fix:** Restored actual pixel comparison using `extractPixelData` on both images, then calling `comparePixelData(pixels, tolerance: 10)`. Also changed background style from `.gradient` with `.systemBlue/.systemPurple` to `.solid` with `.black` to avoid false positives in gradient comparisons.

### Medium Severity: Indexing bug in `exportWithTitleAndBackground`
**Problem:** The nested loop intended to scan the title region had a bug where the vertical offset `dy` was never used to calculate `px`:
```swift
// Bug: dy is never used
let px = rowIndex + (titleX + dx) * 4
```

**Fix:** Updated index calculation to properly use `dy`:
```swift
let px = (titleY + dy) * width * 4 + (titleX + dx) * 4
```

### Medium Severity: Weak assertion in title region check
**Problem:** The check `if r > 50 || g > 50 || b > 50` was used to verify that the title is present, but the background was configured as a gradient from `.systemBlue` to `.systemPurple`. Both of these colors have high Blue and Red components, so the background pixels themselves would satisfy this condition.

**Fix:** Changed background style to `.solid` with `.black`, which has RGB values of (0, 0, 0), ensuring the title text pixels are the only ones that satisfy the `r > 50 || g > 50 || b > 50` check.

## Verification

- All 5 tests in `ExportConsistencyTests.swift` pass successfully
- Tests run with parallel execution (2 test runs) without failures
- Pixel comparison logic properly validates export-preview consistency at quality 1.0

## New Learnings

- `cgbitmapcontext-pixel-extraction-learnings.md` — reliable CGImage pixel extraction using CGBitmapContext instead of dataProvider?.data

---
**Status**: Complete
**Follow-up**: None - Phase 2 implementation complete and verified
