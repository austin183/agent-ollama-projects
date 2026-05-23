# Session 43 — 2026-05-22

### Round 14.3 Change Request: Panel Editor Corner Resize Overlay Jump Fix

**Goal:** Fix the overlay box jump that occurs when clicking a corner handle to resize the crop overlay. When the user clicks a corner, the cursor should stay at the corner during the resize, but instead the overlay box jumps so the cursor ends up somewhere in the middle of the overlay.

**Source:** `_agent_docs/change-requests/round-14.3.md`

**Root Cause:**

The `handleResize` function computed the new overlay rectangle in container coordinates, then converted to source image coordinates using `newRect.origin.x * scaleX`. This conversion did not account for the letterboxing offset (`offsetX`, `offsetY`) introduced by `.aspectRatio(contentMode: .fit)` when the image aspect ratio differs from the container. When `sourceRectInContainer` converted the source rect back to container coordinates for rendering, it added the offset a second time, shifting the visible rect away from the cursor position.

**Changes Implemented:**

#### 1. Captured Full Base Source Rect at Drag Start

Changed `dragBaseSourceOrigin: CGPoint` to `dragBaseSourceRect: CGRect` to capture the complete source rectangle at drag start, not just the origin. This is needed for both drag and resize modes.

**Files:** `Views/PanelCropEditor.swift:9`

#### 2. Fixed Container-to-Source Coordinate Conversion in handleResize

The `handleResize` function now uses the proper inverse of `sourceRectInContainer`'s transformation:
- Computes `offsetX` and `offsetY` from the fitted image dimensions
- Subtracts the offset before scaling: `sourceX = (containerX - offsetX) / fittedW * imageW`
- Scales dimensions directly: `sourceW = containerW / fittedW * imageW`

This ensures the container→source→container round-trip is identity, keeping the visible rect corner aligned with the cursor during resize.

**Files:** `Views/PanelCropEditor.swift:218-264`

#### 3. Updated Resize Case Calls

Simplified the four resize case calls by passing `fittedW`, `fittedH`, and `baseSourceRect` directly, removing the `anchorX`/`anchorY` closures and `scaleX`/`scaleY` parameters that were used by the old (broken) conversion.

**Files:** `Views/PanelCropEditor.swift:165-211`

**Build and Test Status:**
- **Build:** SUCCEEDED — zero errors, pre-existing warnings only
- **Tests:** All 31 unit tests passing (no new tests added)

**Session Status:** Complete — all items from round-14.3.md are resolved.
