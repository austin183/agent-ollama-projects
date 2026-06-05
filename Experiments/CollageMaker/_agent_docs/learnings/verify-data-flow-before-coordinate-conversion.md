# Verify Data Flow Before Adding Coordinate Conversions

**Date:** 2026-06-05
**Session:** 84

## What Happened

Phase 4 plan item S-15 called for splitting `SaliencyResult.cropOrigin` into `cropOrigin` + `toImageSpace`. The plan described `center` as "normalized Vision center" and `toImageSpace` was to multiply by `imageSize` to convert to pixel coordinates.

After implementation, all image crops appeared anchored at the bottom corner instead of centered on salient content.

## Root Cause

`SaliencyResult.center` is **already in pixel coordinates**, not normalized (0-1). The producer (`SaliencyAnalyzer.analyze`) computes:

```swift
let cx = box.midX * CGFloat(width)  // pixel space
let cy = (1.0 - box.midY) * CGFloat(height)  // pixel space
return SaliencyResult(center: CGPoint(x: centerX, y: centerY), ...)
```

The `toImageSpace` method multiplied pixel values by `imageSize` again, producing numbers in the millions that clamped to image edges via `max(0, min(...))`.

## What Went Wrong

The plan's description of `center` as "normalized" was incorrect. I trusted the plan's characterization rather than tracing through the producer to verify what coordinate space the value actually lived in.

## Learning

**When a plan describes adding a coordinate conversion, trace the value to its producer before writing the conversion.** The producer's code is the source of truth for what coordinate space a value is in. Plan descriptions can be wrong about intermediate representations.

Specifically:
1. Find where the struct is instantiated
2. Check the arithmetic used to compute each coordinate field
3. Verify against the consumer's expected coordinate space
4. Only then write the conversion method

## Related

- `collagemaker-prototype-2-coordinate-systems-learnings.md` — covers Vision/CG/NSImage origin differences
- Skill reference: `references/graphics/coordinate-systems.md` — documents the three coordinate systems but not this verification pattern
