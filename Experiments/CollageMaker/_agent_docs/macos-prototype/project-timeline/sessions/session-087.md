# Session 87 — Round-99 Prep: Non-Rectangular Panel Geometry (Phase 4)

**Date:** 2026-06-06
**Status:** Complete

## What Was Done

Implemented Phase 4 from `_agent_docs/plans/2026-06-05-round99-prep-refactoring.md`: path-aware hit testing for non-rectangular panels.

### 4.1 CropManager.hitTestPanel() — Two-Pass Hit Testing

Updated `hitTestPanel()` with a two-pass design:
- **Pass 1 (fast):** `CGRect.contains()` filters to bounding-box candidates — O(1) per panel
- **Pass 2 (precise):** `CGPath.contains()` on canvas-converted point for `.path` panels — O(vertices) per candidate
- `.rect` panels return immediately in pass 2 (bounding box already validated)
- Added `panelGeometries: [UUID: PanelGeometry]?` and `previewSize: CGSize` parameters
- Uses `screenToCanvasPoint()` to convert preview tap coordinates to canvas coordinates for `CGPath.contains()`

### 4.2 CollageEditorView — Geometry Map & Call Sites

- Built `panelGeometries` dictionary alongside `panelFrames` in the GeometryReader closure
- Updated `panelAt()` signature to accept `panelGeometries` and `previewSize`
- Updated all 4 call sites (drag start, drag change, drag end, tap gesture)

### 4.3 Test Updates

- Updated 4 existing `hitTestPanel` tests in `CropManagerTests.swift` with `previewSize` parameter
- All 180+ tests pass

## Design Decisions

- **Two-pass over single-pass:** Fast CGRect filter limits expensive `CGPath.contains()` to bounding-box candidates only. Preserves performance for rectangular layouts (zero path overhead).
- **Coordinate conversion at hit-test time:** `screenToCanvasPoint()` converts preview tap to canvas coordinates. `CGPath` lives in canvas space, so the point must match.
- **`switch` on `PanelGeometry`:** Exhaustive `switch` handles both `.rect` and `.path` cases, avoiding silent skips.

## Files Changed

| File | Changes |
|------|---------|
| `ViewModel/CropManager.swift` | Two-pass `hitTestPanel()` with path containment, coordinate conversion |
| `Views/CollageEditorView.swift` | `panelGeometries` dict, `panelAt()` signature + 4 call sites |
| `CropManagerTests.swift` | `previewSize` parameter on 4 test calls |

## Verification

- `xcodebuild build` — succeeded, zero errors, zero warnings
- `xcodebuild test` — all 180+ tests pass

## Issues Encountered

1. **Plan document bug: `.rect` panels skipped in second pass** — The original plan used `case .path(let cgPath, _) = geometry` with an `if let`, which silently skipped `.rect` panels. When a `.path` panel's bounding box contained the tap but the path didn't, the function fell through to `candidates.first?.key` (arbitrary dict order), potentially returning the wrong panel. Caught by diff-review subagent. Fixed by switching to exhaustive `switch` that returns `.rect` immediately and returns `nil` when no path candidate matches.

---
**Status**: Complete
**Follow-up**: Phases 5-6 remain (SwiftUI shape rendering, style-specific config in ViewModel)
