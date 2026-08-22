# Session 42 — 2026-05-22

### Round 14.2 Change Request: Panel Editor Scroll and Corner Interaction Bug Fixes

**Goal:** Fix two bugs reported from the round 14.1 Panel Editor implementation: (1) scroll/drag on the crop preview moved the overlay in the opposite direction, and (2) clicking the top-left corner behaved inconsistently — sometimes acting like a scroll, sometimes causing the overlay to jump.

**Source:** `_agent_docs/change-requests/round-14.2.md`

**Changes Implemented:**

#### 1. Fixed Inverted Scroll Direction

The `ScrollPanView` NSViewRepresentable was manually negating `scrollingDeltaX` and `scrollingDeltaY` when `isDirectionInvertedFromDevice` was `false`, inverting the pan direction. The raw event deltas already produce the correct direction for indirect scrolling.

**Fix:** Removed the conditional negation, using `event.scrollingDeltaX` and `event.scrollingDeltaY` directly.

**Files:** `Views/ScrollPanView.swift:37-40`

#### 2. Added Missing Top-Left Corner Resize

`detectDragMode` only checked three corners (bottom-right, top-right, bottom-left). The top-left corner fell through to `.none` when clicked outside the visible rect, or to `.drag` when inside — causing the overlay to jump because `beginPan`/`applyPan` was invoked with near-zero translation.

**Fix:** Added `.resizeTopLeft` to `OverlayDragMode`, added Euclidean distance check for the top-left corner in `detectDragMode`, and added the corresponding `handleResize` case in `adjustCropDuringDrag` with the bottom-right corner as the anchor point.

**Files:** `Views/PanelCropEditor.swift:270` (enum), `Views/PanelCropEditor.swift:362-368` (detectDragMode), `Views/PanelCropEditor.swift:202-213` (adjustCropDuringDrag case)

#### 3. Fixed Drag Direction and Sensitivity

Two compounding issues in the `.drag` case of `adjustCropDuringDrag`:
- **Direction:** `applyPan` subtracts the pan delta (`baseOrigin - panDelta`), which is correct for indirect scroll but inverts direct drag. Negating the translation fixed direction but left sensitivity wrong.
- **Sensitivity:** `crop` was re-read from `viewModel.cropMap` on every `onChanged` tick, so the already-moved origin was being used as the base. Combined with the cumulative `value.translation`, this caused the crop to compound on each tick, making drag extremely sensitive.

**Fix:** Captured `crop.sourceRect.origin` at drag start into a new `@State` property `dragBaseSourceOrigin`. The drag case now computes `dragBaseSourceOrigin + translation * scale` directly, bypassing the `beginPan`/`pan`/`applyPan` pipeline entirely. This gives 1:1 cursor-to-overlay movement.

**Files:** `Views/PanelCropEditor.swift:9` (new state property), `Views/PanelCropEditor.swift:58` (capture at drag start), `Views/PanelCropEditor.swift:148-161` (direct source rect computation)

**Build and Test Status:**
- **Build:** SUCCEEDED — zero errors, pre-existing warnings only
- **Tests:** All 106 unit tests passing (no new tests added)
- **Manual testing:** Drag direction and sensitivity verified by user. Scroll direction verified by user.

**Session Status:** Complete — all items from round-14.2.md are resolved.
