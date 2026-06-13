# Session 101 — Round 99.5 Diff-Review Fixes & Pinch Zoom Anchor Bugs

**Date:** 2026-06-12
**Plan:** `_agent_docs/plans/2026-06-12-round-99.5-diff-review-fixes.md`
**CR:** `_agent_docs/change-requests/round-99.5.md`

## Summary

Implemented 6 diff-review findings from Round 99.4 (2 medium, 4 low) — all low-risk refactors with one behavioral fix (`applyPinch` effective-origin clamping for off-canvas `.path` panels). User then reported pinch gesture zoom causing the crop overlay to drift right on diagonal slices. Investigation revealed the zoom anchor was computed from the **new** visible bounds (post-zoom) instead of the **old** bounds (pre-zoom), creating a feedback loop where the anchor itself moved. Fixed by using old bounds for the anchor coordinate and new bounds for the offset.

## Phase 1 — Diff-Review Fixes (6 findings)

### Finding #6 — Remove unused `baseSourceRect` param (`PanelCropEditor.swift`)

Removed dead `baseSourceRect: CGRect` parameter from `handleResize` signature and all 4 call sites. Zero behavioral change.

### Finding #3 — Deduplicate visible bounds computation (`CropManager.swift`, `PanelCropEditor.swift`)

- `VisibleSourceBounds` struct: `struct` → `internal struct`
- `computeVisibleSourceBounds`: `private func` → `static func` (uses no instance state)
- Internal callers in `applyPan` and `applyPinch` updated to `Self.computeVisibleSourceBounds(...)`
- `PanelCropEditor` inline visible bounds math (18 lines) replaced with single `CropManager.computeVisibleSourceBounds(...)` call

### Finding #2 — Division-by-zero guards

Resolved by Finding #3 — `PanelCropEditor` now delegates to `CropManager.computeVisibleSourceBounds` which already guards `dw > 0` and `dh > 0`.

### Finding #4 — Align `maxEffX` clamping (`PanelCropEditor.swift`)

Added `max(0, ...)` to `maxEffX`/`maxEffY` in the drag handler to match `CropManager.applyPan`. No behavioral change — both `min(negative, negative)` and `max(0, negative)` converge to 0.

### Finding #1 — Fix `applyPinch` effective-origin clamping (`CropManager.swift`)

`applyPinch` previously used `crop.sourceRect.midX` (center of full source rect) for clamping. For off-canvas `.path` panels, this differs from the visible center by `(scaledW - visibleW)/2`, always positive, causing rightward drift. Fixed to use effective-origin clamping matching `applyPan`.

### Finding #5 — Extract `drawClampedCrop` helper (`CollageAssembler.swift`)

Extracted the 10-line "sourceRect beyond image bounds" clamping pattern into `drawClampedCrop(context:cgImage:sourceRect:destRect:)`. Replaced duplicate blocks in `drawPanels` and `renderPanel` with single calls.

## Phase 2 — Pinch Zoom Drift Bug

### Root Cause

After the Finding #1 fix, `applyPinch` computed:
```
currentEffCenterX = crop.sourceRect.origin.x + visBounds.offsetX + visBounds.visibleW / 2
```

But `visBounds` was computed with the **new** zoom level (`scaledW`, `scaledH`). As zoom changed, `visBounds.visibleW` changed, shifting the anchor itself. This created a feedback loop: the anchor moved, the computed new origin moved, and the crop drifted.

### Fix

Compute `oldVisBounds` from the **current** crop (`crop.sourceRect.width/height`), extract the anchor's effective source coordinate from that, then subtract the anchor's offset within the **new** visible region:

```swift
let visBounds = Self.computeVisibleSourceBounds(destRect: ..., sourceW: scaledW, sourceH: scaledH)
let oldVisBounds = Self.computeVisibleSourceBounds(destRect: ..., sourceW: crop.sourceRect.width, sourceH: crop.sourceRect.height)

// Anchor from old crop, offset from new bounds
let anchorEffX = crop.sourceRect.origin.x + oldVisBounds.offsetX + oldVisBounds.visibleW / 2
let anchorOffsetX = visBounds.visibleW / 2
let newEffX = clamp(anchorEffX - anchorOffsetX, min: 0, max: maxEffX)
```

### User Feedback — Anchor Position

User requested the anchor be the top-left corner of the visible region (matching the right-angle corner of clipped triangles) rather than the center, for all `.path` panels. Simplified the logic:
- Leftmost panel (`destRect.minX < 0`): anchor at top-left of visible region
- Rightmost panel (`destRect.maxX > canvasWidth`): anchor at bottom-right of visible region
- Middle panel (fully on-canvas): anchor at top-left of visible region

## Phase 3 — Triangle Corner Drag Jump

`handleResize` changed `sourceRect.size` without compensating the origin. Since the source rect maps to the parallelogram bounding box, a size change shifts all parallelogram edges, moving the visible triangle. Fixed by adjusting `sourceOrigin` by `deltaW * (-destRect.minX / destRect.width)` to keep the non-dragged parallelogram edge stable.

## Verification

- `xcodebuild build` — Succeeded
- `xcodebuild test` — All tests pass (including new `pinchZoomOffCanvasPathPanelUsesEffectiveOriginClamping` test)
- User verified: leftmost and rightmost panels zoom correctly, middle panel drift resolved at low angles

## Files Changed

| File | Changes |
|------|---------|
| `CropManager.swift` | `VisibleSourceBounds` → `internal`, `computeVisibleSourceBounds` → `static`, `applyPinch` old/new visBounds split, corner-based anchor for `.path` panels |
| `PanelCropEditor.swift` | Removed `baseSourceRect` param, replaced inline visible bounds with `CropManager.computeVisibleSourceBounds`, added `max(0,...)` to `maxEffX`, `handleResize` anchoring adjustment for `.path` panels |
| `CollageAssembler.swift` | Extracted `drawClampedCrop` helper, replaced 2 duplicate blocks |
| `PanelGeometry.swift` | Added `extractPathPoints` static method (moved from `CropPreviewView`) |
| `CropManagerTests.swift` | Added `pinchZoomOffCanvasPathPanelUsesEffectiveOriginClamping` test |

## New Learnings

Created `pinch-zoom-anchor-old-vs-new-bounds.md` — zoom anchor must be computed from pre-zoom bounds.

---
**Status:** Complete
**Follow-up:** Middle panel anchor still moves slightly at high shear angles (43°), deferred for now.
