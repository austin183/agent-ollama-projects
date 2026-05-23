# Session 41 — 2026-05-22

### Round 14.1 Change Request: Panel Editor Click-and-Drag Input with Overlay Resize

**Goal:** Replace scroll/pinch gestures in the Panel Editor with click-and-drag input. The overlay rectangle on the crop preview should be draggable to pan the crop, and corner handles should resize the overlay to control zoom level. Corner handles use the same semi-transparent orange visual style as the Title Image box edge handles.

**Source:** `_agent_docs/change-requests/round-14.1.md`

**Changes Implemented:**

#### 1. Replaced Scroll+Pinch with DragGesture

The Panel Editor previously used `ScrollPanView` (NSViewRepresentable scroll-wheel capture) and `MagnificationGesture` (pinch-to-zoom). Both were removed in favor of a single `DragGesture` inside a `GeometryReader` that uses `startLocation` hit-testing to determine the interaction mode.

**Implementation:** The gesture locks onto a mode (`.drag`, `.resizeBottomRight`, `.resizeTopRight`, `.resizeBottomLeft`) on the first `onChanged` tick, preventing re-locking mid-drag. Drag mode routes through the existing `beginPan`/`pan`/`applyPan` pipeline for panning. Resize mode computes the new overlay rectangle from anchor point and cursor position, converts container coordinates back to image pixel coordinates, and calls `applyOverlayCrop` on the ViewModel.

**Files:** `Views/PanelCropEditor.swift` (complete rewrite)

#### 2. Corner Resize Handles with Bolded Visual Feedback

Four 10x10pt semi-transparent orange squares (`Color.orange.opacity(0.3)`) are rendered at each corner of the visible crop overlay rectangle. The visual style matches the Title Image box edge handles (`CollageEditorView.swift:128-138`). Hit-test threshold is 16pt Euclidean distance from each corner, providing a comfortable grab area beyond the visual handle size.

**Implementation:** The `cornerHandles(for:)` method in `CropPreviewView` iterates `Corners.allCases` via `ForEach` to position handles. The `detectDragMode` static method checks Euclidean distance to each corner before falling back to `.drag` for interior hits.

**Files:** `Views/PanelCropEditor.swift:222-235` (corner handles), `Views/PanelCropEditor.swift:244-275` (detectDragMode)

#### 3. ViewModel Overlay Crop Support

Added three methods to `CollageViewModel` for undo-safe overlay crop manipulation:
- `beginOverlayCropUndo(panelId:)` — captures current crop state and registers undo target
- `endOverlayCropUndo()` — sets action name and ends undo grouping
- `applyOverlayCrop(panelId:sourceRect:)` — applies the new crop to both `cropMap` and `cropManager.cropMap`, then triggers preview update

**Files:** `ViewModel/CollageViewModel.swift:635-671`

**Build and Test Status:**
- **Build:** SUCCEEDED — zero errors, pre-existing warnings only
- **Tests:** All 106 unit tests passing (no new tests added; existing `PanelCropEditorTests` and `CropManagerTests` remain valid)
- **Manual testing:** Pending user verification.

**Session Status:** Complete — all items from round-14.1.md are resolved.
