# Session 47 — 2026-05-25

### Round 14.5 CR: Proportional Resizing from Panel Editor

**Goal:** Constrain corner resize handles in the Panel Editor crop preview to maintain the panel's aspect ratio, preventing the image from looking out of proportion during resize.

**Source:** Round 14.5 change request — corner resize allows arbitrary aspect ratios.

**Investigation:**

The `handleResize` method in `PanelCropEditor.swift` computed width and height independently from the drag distance (`abs(value.location.x - anchor.x)` and `abs(value.location.y - anchor.y)`), allowing the user to resize the crop overlay to any shape regardless of the panel's aspect ratio.

**Changes Implemented:**

#### `PanelCropEditor.swift:218-278` — Aspect-ratio-constrained resize

Replaced the independent width/height computation with aspect-ratio enforcement:

```swift
let panelAspect = panel.frame.width / panel.frame.height

let rawW = abs(value.location.x - anchor.x)
let rawH = abs(value.location.y - anchor.y)

var newW: CGFloat
var newH: CGFloat
if rawW / rawH > panelAspect {
    newW = max(1, rawW)
    newH = newW / panelAspect
} else {
    newH = max(1, rawH)
    newW = newH * panelAspect
}
```

The dominant drag dimension (width vs height) determines the size, and the other dimension is derived from `panelAspect`. The bounding box origin still uses `min(anchor, cursor)` for all four corners, with container clamping applied afterward.

#### `PanelCropEditor.swift:111` — Updated hint text

Changed from `"Corner drag to zoom"` to `"Corner drag to zoom (proportional)"`.

**Build and Test Status:**
- **Build:** Succeeded — zero errors, zero warnings
- **Tests:** 100 tests passing — no new tests added (behavioral change in view-layer gesture handling, covered by manual testing)

**Session Status:** Complete — proportional resize working, build clean.
