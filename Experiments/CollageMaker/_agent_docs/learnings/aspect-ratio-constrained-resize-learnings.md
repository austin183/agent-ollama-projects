# Aspect-Ratio-Constrained Resize — Learnings 2026-05-25

**Purpose:** Document learnings from Round 14.5: constraining Panel Editor corner resize to maintain panel aspect ratio.

## What Worked

- **Dominant-dimension pattern** — To constrain a free-form drag to a fixed aspect ratio, compare the drag ratio to the target aspect ratio: if `rawW / rawH > targetAspect`, width is dominant — use `rawW` and derive `newH = newW / targetAspect`. Otherwise height is dominant — use `rawH` and derive `newW = newH * targetAspect`. This produces smooth, predictable resizing that follows the user's drag direction while maintaining proportions.

- **Uniform bounding box for all corners** — Using `min(anchor.x, cursor.x)` and `min(anchor.y, cursor.y)` for the bounding box origin, combined with `abs(cursor - anchor)` for dimensions, works uniformly for all four corners without branching on corner type or drag direction.

## What Didn't Work / Gaps

- **Contraction/expansion branching** — An initial attempt branched on whether `delta.width <= 0 && delta.height <= 0` to handle "shrinking" vs "expanding" differently. This is fundamentally broken: for bottom-left and top-right corners, one delta component is positive and the other negative during a valid resize, causing the branch to take the wrong path. The `min`/`abs` approach eliminates the need for this branch entirely.

## Key Pattern: Aspect-Ratio-Constrained Resize

```swift
let targetAspect = panel.frame.width / panel.frame.height

let rawW = abs(value.location.x - anchor.x)
let rawH = abs(value.location.y - anchor.y)

var newW: CGFloat
var newH: CGFloat
if rawW / rawH > targetAspect {
    newW = max(1, rawW)
    newH = newW / targetAspect
} else {
    newH = max(1, rawH)
    newW = newH * targetAspect
}

let originX = min(anchor.x, value.location.x)
let originY = min(anchor.y, value.location.y)
```

**Why it works:** The `rawW / rawH` comparison determines which drag dimension the user is moving more strongly. That dimension becomes the driver; the other is derived from the target aspect ratio. This feels natural — dragging mostly horizontally expands width primarily, dragging mostly vertically expands height primarily — while always preserving proportions.

## Relation to Existing Learnings

- **Inverse coordinate transform** (`inverse-coordinate-transform-learnings.md`): The container-to-source conversion after computing the constrained rect is the same offset-aware inverse transform documented there. The new learning is the constraint logic applied *before* the coordinate conversion.

- **Title resize** (`title-resizable-box-learnings.md`): The title resize is single-dimension (width only, height is fixed). This pattern is two-dimensional with a coupling constraint, making it a different class of resize gesture.

---
**Status:** Closed
**Follow-up:** None
