# Mobile Bottom Sheet Adjustments - Change Request

**Date:** 2026-07-26
**Status:** Draft
**Priority:** P1 — Mobile usability improvement

---

# Problem 1

It is difficult to interact with the crop preview under the Edit Bottom Sheet when switching panels on the canvas.

# Solution - Remove Crop Preview from Edit Bottom Sheet

The Crop Editor is not as necessary with the limited space, and it is hard to use the crop corners anyway. Corner handles fall below the 44x44px minimum touch target on a constrained bottom sheet (max-height: 70dvh, 50dvh in landscape).

**What to keep:**
- Crop info readout (X, Y, W, H values) — provides essential numeric feedback
- "Reset Crop" button — quick way to undo without visual canvas

**Implementation notes:**
- Remove the `<canvas id="bsCropPreviewCanvas">` element and its surrounding `.crop-preview-section` from `index.html` `#bs-panel-edit`
- Update `MyComponents/CropPreviewDualCanvasTest.html` tests that reference `bsCropPreviewCanvas`
- Update `createCollageLifecycle.js` — remove `ids.bsCropPreviewCanvas` from the `canvasId` array passed to `CropInteraction`

**Future consideration:** A dedicated "Open Full-Screen Crop" button could launch a full-screen crop overlay with touch-friendly corner handles, pinch-to-zoom, and pan gestures for users who need visual crop adjustments on mobile.

---

# Problem 2

The Images appear above the Layout Options under the Images Bottom Sheet.

# Solution - Reorder Images Bottom Sheet Sections

Put Layout Controls first so it is easy to change after adding several images. This places high-frequency iterative controls in the prime "thumb reach" zone and matches the common mobile pattern of "settings > content" (used by Canva, Adobe Express).

**New order:**
1. Layout Controls (Layout Style dropdown, Gutter slider, Slice Angle slider, Hex Spacing slider, Hex Size slider)
2. Image Library (search bar + scrollable list of image thumbnails)

**Implementation notes:**
- Move the `.detail-section` layout controls block (lines 252–274 in `index.html`) above the `.library-search` / `.image-library` block (lines 230–250)
- Add a visual section header or divider (e.g., "Layout Settings") to separate layout controls from the image library
- Keep the search bar with the image library — it is contextually tied to image management, not layout configuration
- Ensure all sliders and dropdowns maintain 44px+ touch targets
