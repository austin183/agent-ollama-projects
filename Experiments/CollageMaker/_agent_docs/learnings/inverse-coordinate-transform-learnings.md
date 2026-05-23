# Inverse Coordinate Transform — Learnings 2026-05-22

**Purpose:** Document learnings from Round 14.3: fixing the overlay jump during corner resize in the Panel Editor crop preview.

## What Worked

- **Tracing the round-trip** — The bug was diagnosed by mentally tracing the container→source→container conversion chain. The forward transform (`sourceRectInContainer`) adds an offset: `offsetX + sourceX / imageW * fittedW`. The old inverse used `containerX * scaleX` which omits the offset subtraction, causing the offset to be applied twice in the round-trip.
- **Using the explicit inverse formula** — The fix is straightforward algebra: reverse each step of the forward transform. Given `containerX = offsetX + sourceX / imageW * fittedW`, the inverse is `sourceX = (containerX - offsetX) / fittedW * imageW`.

## What Didn't Work / Gaps

- **Naive scale factor conversion** — The original `handleResize` computed `scaleX = imageW / fittedW` then used `containerX * scaleX` to convert container coordinates to source coordinates. This is equivalent to `containerX * imageW / fittedW`, which expands the offset as well as the coordinate. The correct formula must subtract the offset first: `(containerX - offsetX) / fittedW * imageW`. These two formulas are only equivalent when `offsetX == 0` (matching aspect ratios).

- **Letterboxing makes the bug invisible in some cases** — When the image and container have matching aspect ratios, `fittedW == containerWidth` and `offsetX == 0`, so both formulas produce identical results. The bug only manifests when the image is letterboxed or pillarboxed within the container, which is the common case for arbitrary images in a fixed-height preview.

## Key Pattern: Inverting the aspectRatio(.fit) Transform

When an image is rendered with `.aspectRatio(contentMode: .fit)` in a container, the forward transform from source image coordinates to container coordinates is:

```swift
// Forward: source → container
let fittedW = ... // computed from aspect ratio comparison
let offsetX = (containerWidth - fittedW) / 2
let containerX = offsetX + sourceX / imageWidth * fittedW
```

The inverse transform from container coordinates back to source coordinates must reverse each step:

```swift
// Inverse: container → source
let fittedW = ... // same computation as forward
let offsetX = (containerWidth - fittedW) / 2
let sourceX = (containerX - offsetX) / fittedW * imageWidth
```

**Critical:** You cannot use a simple scale factor (`containerX * imageW / fittedW`) because it doesn't undo the offset. The offset must be subtracted before the division.

### Why `* scaleX` Fails

```
Naive:   containerX * scaleX
        = (offsetX + sourceX/imageW * fittedW) * imageW/fittedW
        = offsetX * imageW/fittedW + sourceX
        ≠ sourceX  (when offsetX ≠ 0)

Correct: (containerX - offsetX) / fittedW * imageW
        = (offsetX + sourceX/imageW * fittedW - offsetX) / fittedW * imageW
        = (sourceX/imageW * fittedW) / fittedW * imageW
        = sourceX  ✓
```

## Skill Improvements

### `building-macos-apps/references/coordinate-systems.md`

Add a section on inverting the `aspectRatio(.fit)` transform, with the algebraic proof showing why `* scaleX` is incorrect when offset is non-zero. This complements the existing "Source Rect to Fitted Container Mapping" section which only documents the forward direction.

### `building-macos-apps/references/swiftui-gestures.md`

Add a pitfall: "When a gesture modifies a rect in container coordinates that were derived from a `.aspectRatio(.fit)` image, converting back to source coordinates requires subtracting the letterboxing offset before scaling. Using `containerX * scaleX` double-applies the offset, causing the visual element to jump away from the cursor."

## Next Steps

- Update `coordinate-systems.md` with inverse transform section
- Consider adding a test that verifies the round-trip: `sourceRectInContainer(inverse(sourceRectInContainer(crop))) == crop.sourceRect`

---
**Status:** Closed
**Follow-up:** Update coordinate-systems.md skill reference
