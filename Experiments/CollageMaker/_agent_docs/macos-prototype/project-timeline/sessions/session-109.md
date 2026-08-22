# Session 109 — SRP Remediation Phase 6.1: Extract Crop Logic from PanelCropEditor

**Date:** 2026-06-17
**Plan:** `_agent_docs/plans/2026-06-15-srp-remediation-plan.md` § Phase 6.1

## Summary

Implemented Phase 6.1 of the SRP remediation plan — extracted ~185 lines of crop adjustment business logic from `PanelCropEditor` into thin gesture wrappers that delegate to pure static methods on `CropManager`. The view went from 593 to 470 lines.

## Changes

### CropManager: Extended handleResize with Path-Panel Compensation

**Signature change:**
```swift
// Before:
static func handleResize(cropBounds:edge:delta:image:crop:container:panelSize:) -> CGRect

// After:
static func handleResize(cropBounds:edge:delta:image:crop:container:panelSize:destRect:isPathPanel:) -> CGRect
```

The view's inline `handleResize` contained path-panel compensation logic (parallelogram edge anchoring) that was not present in the manager's method. Added `destRect: CGRect` and `isPathPanel: Bool = false` parameters to support this case. The compensation adjusts the source origin proportionally when source size changes, keeping the non-dragged parallelogram edge stable.

### PanelCropEditor: Thin Gesture Wrappers

**Before:** Two private methods (`adjustCropDuringDrag`, `handleResize`) totaling ~185 lines of inline math covering:
- Container-to-source coordinate transforms (FitMath fit + scale)
- Drag translation with visible offset/size for path panels
- Corner resize with aspect-ratio constraint, container clamping, source-space conversion, min/max bounds, path-panel compensation

**After:** Single `adjustCropDuringDrag` method (~55 lines) that:
- Switches on `overlayDragMode` to dispatch to `.drag` or resize
- Computes per-corner anchor points (already existed in the view)
- Constructs `dragBaseOrigin`-based `cropBounds` and cursor-to-anchor `delta`
- Calls `CropManager.adjustCropDuringDrag()` or `CropManager.handleResize()` and passes the result to `viewModel.applyOverlayCropLive()`

### Tests: Signature Update

Updated 7 `handleResize` test calls in `CropManagerTests.swift` to pass `destRect: .zero` (rect-panel default, no path compensation).

## Verification

- `xcodebuild build` — Succeeded, zero errors
- `xcodebuild test` — All tests passed, zero failures

## Files Changed

| File | Changes |
|------|---------|
| `ViewModel/CropManager.swift` | Extended `handleResize` with `destRect` + `isPathPanel` params, path-panel compensation |
| `Views/PanelCropEditor.swift` | Replaced ~185 lines of crop math with thin wrappers (593→470 lines) |
| `CropManagerTests.swift` | 7 test calls updated with `destRect: .zero` |

## New Learnings

None. The coordinate transforms, aspect-ratio resize, off-canvas clamping, and anchor patterns are all documented in existing learnings files.

---
**Status:** Complete
**Follow-up:** Phase 6.2 (Title logic extraction) from the same plan.
