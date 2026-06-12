# Round 99.5 — diff-review Findings from Round 99.4

**Date:** 2026-06-11
**Source:** `diff-review` and `diff-review-g31` agents

## Overview

Two diff-review agents reviewed all changes from Round 99.4 (crop overlay fixes + off-canvas drag clamping). `diff-review` returned 4 findings. `diff-review-g31` initially returned no results, then returned 2 additional findings on re-run.

---

## Findings

### 1. Medium — Unused `visBounds` variable in `applyPinch`

- **File:** `CollageMaker/CollageMaker/ViewModel/CropManager.swift`
- **Line:** 223
- **Description:** `applyPinch` computes `visBounds` via `computeVisibleSourceBounds` but **never uses it**. The subsequent clamping logic still uses the old full-image clamping (`max(0, image.size.width - scaledW)`). This is dead code from a partial refactor — `applyPan` was updated to use effective-origin clamping but `applyPinch` was not. As a result, pinch-to-zoom on `.path` panels does not benefit from the effective-origin clamping, producing inconsistent behavior between pan and pinch for off-canvas parallelogram panels.

### 2. Medium — Missing division-by-zero guards in `PanelCropEditor` visible bounds computation

- **File:** `CollageMaker/CollageMaker/Views/PanelCropEditor.swift`
- **Lines:** 105-114
- **Description:** The `.path` case computes `dragVisibleOffset` and `dragVisibleSize` by dividing by `bw` and `bh` (the destination rect's width and height) **without guards**. The equivalent code in `CropManager.computeVisibleSourceBounds` **does** guard against zero (`dw > 0 ? ... : 0`). If `crop.destinationRect` ever has zero width or height, this would produce `NaN` or `inf` values. Inconsistent with the guarded version in CropManager.

### 3. Low — Duplicated visible bounds computation logic

- **Files:** `PanelCropEditor.swift` (lines 97-114) and `CropManager.swift` (lines 337-353)
- **Description:** The visible source bounds computation (clamping destRect to canvas, computing off-canvas offset, scaling to source coordinates) is duplicated in two places. The logic is mathematically identical but implemented independently. If the clamping algorithm ever needs to change, both locations must be updated in sync. Consider extracting into a shared utility or having `PanelCropEditor` call `CropManager.computeVisibleSourceBounds`.

### 4. Low — Inconsistent `maxEffX` clamping between `adjustCropDuringDrag` and `applyPan`

- **Files:** `PanelCropEditor.swift` line 214 vs `CropManager.swift` line 168
- **Description:** `adjustCropDuringDrag` computes `maxEffX = image.size.width - visSize.width` (can be negative), while `CropManager.applyPan` uses `maxEffX = max(0, image.size.width - visBounds.visibleW)` (clamped to 0). In practice the behavior converges (`PanelCropEditor` uses `max(0, min(..., negative))` → always 0; `CropManager`'s `clamp` returns input when `max < min`). But the inconsistency is unnecessary and makes the code harder to reason about.

### 5. Low — Duplicate rendering clamping in `CollageAssembler` (from `diff-review-g31`)

- **File:** `CollageMaker/CollageMaker/Services/CollageAssembler.swift`
- **Lines:** 346-353, 414-421
- **Description:** The logic for clamping `sourceRect` to image bounds and calculating the mapped destination rectangle is identical in both `drawPanels` and `renderPanel`. This could be extracted into a helper method to avoid duplication.

### 6. Low — Unused `baseSourceRect` parameter in `handleResize` (from `diff-review-g31`)

- **File:** `CollageMaker/CollageMaker/Views/PanelCropEditor.swift`
- **Lines:** 285, 294
- **Description:** The `baseSourceRect` parameter passed to `handleResize` is never used within the function body. This parameter was used in the original implementation but is no longer referenced after the refactor. It can be safely removed along with all call sites that pass it.

---

## Items Verified as NOT Issues

- **CollageAssembler rendering clamping division by zero** — The guard `if clamped.width > 0, clamped.height > 0` implicitly protects subsequent divisions. Safe.
- **`sourceRect` fully outside image bounds** — When entirely outside, `clamped` has zero width/height, guard fails, nothing is drawn. Correct behavior.
- **Force unwraps on `vertices.min()`/`.max()`** — Protected by `vertices.count >= 3` guard. Safe.
- **`canvasClipInPanel` → `CGRect(origin: .zero, size: canvasSize)`** — Verified correct per updated comment.
- **`detectDragMode` bounding box center classification** — Correctly classifies vertices by position relative to bounding box center.
- **`CropManager` concurrency** — Correctly marked `@MainActor`, all UI state updates on main thread. Safe.
- **`CollageAssembler` concurrency** — Changes operate only on local variables and immutable image data, maintaining thread safety. Safe.
- **Effective-origin clamping consistency** — Both `CropManager.applyPan` and `PanelCropEditor.adjustCropDuringDrag` use the same mathematical pattern (modulo minor `max(0, ...)` differences noted above). Safe.

---

**Status:** Open
**Follow-up:** Address in next session
