# Round 99.4 — Remaining Crop Overlay Bugs

1. In Diagonal Slices Layout with 3 images, the crop overlay for the first (leftmost) panel renders as an hourglass instead of the clipped triangle shape.

2. In Hexagonal Layout, the crop overlay drag-to-pan gesture works, but clicking on corner vertices does not trigger a resize/zoom gesture like the scroll/pinch magnification gesture does.

3. **`canvasClipInPanel` width/height math is wrong** (High severity) — `PanelCropEditor.swift:450-455`. Both `diff-review` and `diff-review-g31` flagged this. The `canvasClipInPanel` rect uses `width: canvasSize.width + panelFrame.origin.x` and `height: canvasSize.height + panelFrame.origin.y`, which produces incorrect clip bounds. The `extractPathPoints(cgPath)` call returns points in **canvas coordinates** (verified: `LayoutGenerator` creates paths in canvas coordinates — e.g., `DiagonalSlicesLayoutStrategy` uses `unshearedRect.origin.x`, `HexagonalLayoutStrategy` uses `canvasCenter.x + ...`). Two possible fixes:
   - **Simplest**: Set `width: canvasSize.width, height: canvasSize.height` (the origin offset is already accounted for by `x: -panelFrame.origin.x`).
   - **Cleanest**: Since the path points are already in canvas coordinates, skip the panel-local transform entirely and use `CGRect(origin: .zero, size: canvasSize)` as the clip rect. The current coordinate-space conversion is unnecessary and error-prone.

4. **Dead `clipEdge` function** (Low severity) — `PanelCropEditor.swift:481-508`. Both reviewers flagged this. The `clipEdge` inner function is defined inside `clipPolygon` but never called — only `clipEdgeCorrect` (lines 511-535) is used. Additionally, `clipEdge` has a bug: `prev` is declared as `let` and never updated in the `for` loop, so every iteration compares against the same last point. Remove the dead function to avoid confusion and accidental reuse.
