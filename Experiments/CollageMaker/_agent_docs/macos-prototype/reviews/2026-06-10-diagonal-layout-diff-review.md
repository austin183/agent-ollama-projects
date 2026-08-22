# 2026-06-10 Diagonal Layout Diff Review

**Date:** 2026-06-10
**Agents:** diff-review, diff-review-g31
**Focus:** Diagonal layout canvas coverage fix

---

## Summary of Changes

This diff addresses the **diagonal slices canvas coverage** bug — fixing an uncovered triangle in the Diagonal layout when shear transforms push panel content beyond canvas bounds.

| File | Change |
|---|---|
| `LayoutGenerator.swift` | Shear-aware panel width calculation, cos² gutter scaling, `centerOffset = -shearOffset` |
| `CollageEditorView.swift` | Canvas-level ZStack clipping for layered mode |
| `ContentView.swift` | Slider range `5...85` → `0...75` |
| `LayoutGeneratorTests.swift` | 4 new coverage tests at 0°/30°/45°/60°/75° |
| Skill/docs | Shear transform reference, clipping pitfall documentation, AGENTS.md reorg |

---

## Verified Correct (Both Agents Agree)

- **`LayoutGenerator.swift` shear math** (lines 240-249): The formula `centerOffset = -shearOffset`, `colWidth = (W + shearOffset - totalGutter) / N`, and `effectiveGutter = gutter * cos²(θ)` are mathematically correct. Verified algebraically and confirmed by all 4 new tests passing. User also confirmed visual correctness in the app.

- **Zero-angle edge case**: At angle 0, `shearOffset = 0`, `centerOffset = 0`, `effectiveGutter = gutter`, producing vertical strips starting at x=0 — identical to pre-change behavior.

- **`ContentView.swift` slider range** (line 206): `0...75` is a deliberate design choice. Angle 0 produces valid vertical strips; 75° is the practical upper bound before tan(θ) makes panels excessively wide.

- **Test assertions**: All new tests use appropriate assertions (`<= 0`, `>= canvasWidth`) with descriptive failure messages. No forced-unwraps on potentially empty collections.

---

## Issues Found

### MEDIUM: ZStack clipping affects gesture hit area and non-layered mode

**File:** `CollageEditorView.swift:136-138`
**Found by:** diff-review

The `.clipShape()`, `.frame()`, and `.position()` modifiers are applied to the **entire ZStack**, which means they affect **both** `isLayeredMode` and the `previewImage` (non-layered) branches.

**Consequence 1 — Gesture hit area shrinks.** The `.overlay` on line 139 and all subsequent `.simultaneousGesture` / `.onTapGesture` modifiers (lines 162-325) operate on a view whose size is now `canvasPreviewFrame.size` instead of `geometry.size`. In a GeometryReader where the editor area is larger than the fitted canvas (e.g., letterboxed), the area outside the canvas preview no longer responds to gestures. Previously, dragging from the letterbox area would initiate a panel drag; now it won't. Similarly, tapping outside the canvas to deselect a panel may not work.

**Consequence 2 — Non-layered mode preview is clipped.** In the `else if let previewImage` branch (line 74-80), the preview image was rendered at `geometry.size` filling the full editor. After the change, it's clipped to `canvasPreviewFrame.size`. If the preview NSImage is always the canvas size, the clipping may be visually harmless. But this is an implicit assumption — if the preview image is ever rendered at a different size, clipping would crop it unexpectedly.

**Suggested fix:** Scope the clipping to only the layered mode branch. Apply `.clipShape(Rectangle()).frame().position()` inside the `if viewModel.isLayeredMode` block rather than on the ZStack itself. Alternatively, wrap just the `ForEach(viewModel.panels)` in a clipped container.

---

### LOW: `RoundedRectangle(cornerRadius: 0)` is a no-op

**File:** `CollageEditorView.swift:136`
**Found by:** diff-review

`.clipShape(RoundedRectangle(cornerRadius: 0))` is functionally identical to `.clipShape(Rectangle())`. Use `.clipShape(Rectangle())` or `.clipped()` for clarity.

---

## Questions / Action Items

1. **Was the gesture area reduction intentional?** The clipping was motivated by layered mode panel overflow, but it also affects gesture handling. If the reduced gesture area is acceptable, consider adding a comment explaining the trade-off.

2. **Does the non-layered mode preview actually fill beyond the canvas?** If the preview NSImage is always rendered at canvas size and `contentMode: .fit` already constrains it, the clipping in non-layered mode may be visually invisible. Worth verifying in the app.

3. **Should the `ScrollPanView` overlay also be clipped?** Currently `ScrollPanView` inside `.overlay` is the same size as the canvas preview frame. If ScrollPanView has visual content that should be clipped, it would need its own clip modifier.

---

## Agents Discrepancy

`diff-review-g31` reported no issues. `diff-review` identified the ZStack clipping scope issue (medium) and the `RoundedRectangle(cornerRadius: 0)` style issue (low). The clipping scope issue is worth investigating — it may not be a practical problem if the editor area is never larger than the canvas in practice, but it's worth confirming.
