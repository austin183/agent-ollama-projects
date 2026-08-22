# Dynamic Zoom Limits — Learnings 2026-05-25

**Purpose:** Document learnings from Round 15.1: replacing hardcoded zoom limits with dynamic limits based on image and panel size ratios.

## What Worked

- **Dynamic zoom-out limit** — The maximum zoom-out factor that keeps the source rect within the image is `min(imageW/panelW, imageH/panelH)`. Using `min` across both dimensions ensures the source rect never exceeds the image boundary on either axis. A single-dimension check (e.g., `imageW/panelW` alone) would allow the source rect to exceed the image height on non-square images.

- **Zoom factor as source/panel ratio** — The zoom factor `sourceW / panelW` is the natural unit: 1.0 means the source rect matches the panel size, >1.0 means zoomed in (showing a smaller portion of the image), <1.0 means zoomed out (showing a larger area). The max zoom-out is the value where the source rect equals the largest panel-aspect-matched rect that fits inside the image.

- **Fixed zoom-in floor** — A minimum zoom of 0.5 (source rect = half panel size) provides a consistent 2x zoom-in across all image/panel combinations. This is a content-independent constant, unlike the zoom-out limit which depends on the image.

## What Didn't Work / Gaps

- **Hardcoded limits don't scale** — The original `clamp(min: 0.5, max: 3.0)` assumed a fixed relationship between image and panel sizes. When the image (e.g., 4000x4000) was much larger than the panel (e.g., 960x540), the 3.0 max prevented the user from zooming out enough to see the full image. The fix is to compute the limit from the actual sizes.

- **Aspect-ratio-aware limit requires both dimensions** — An initial attempt used aspect-ratio branching (`if imageAspect > panelAspect` → use one formula, else use another). This is unnecessary and error-prone. The `min(imageW/panelW, imageH/panelH)` formula works for all aspect ratio combinations without branching.

- **Test design for zoom-out** — When testing that "zoom-out increases crop size," the initial best-fit crop may already be at the maximum zoom-out extent (full image visible), so a single zoom-out gesture produces no change. The fix is to zoom in first, then zoom out, and compare against the zoomed-in state.

## Key Pattern: Dynamic Zoom Bounds

```swift
// In pinch-to-zoom handler:
let maxZoomOut = Swift.min(image.size.width / panelSize.width,
                           image.size.height / panelSize.height)
let newZoom = clamp(baseZoom / zoomDelta, min: 0.5, max: maxZoomOut)
```

**Why `min` on both axes:** The source rect has the panel's aspect ratio. If `imageW/panelW > imageH/panelH`, then the height is the constraining axis — the source rect would exceed the image height before it exceeds the image width. `min` picks the tighter constraint automatically.

**Zoom-in floor is constant:** Unlike zoom-out (which depends on content), zoom-in has a fixed semantic floor: 0.5 means the source rect is half the panel size, i.e., 2x magnification. This is independent of image dimensions.

## Relation to Existing Learnings

- **Gesture patterns** (`swiftui-gestures.md` skill ref): Documents the division semantics (`baseZoom / magnification`) and cumulative values. This learning adds the bounds layer on top of that foundation.

- **Corner resize** (`aspect-ratio-constrained-resize-learnings.md`): The corner-drag zoom in PanelCropEditor uses the same aspect-ratio awareness — the source rect must maintain the panel's aspect ratio. The zoom limit clamps are applied after the aspect-constrained resize computes the target size.

- **Crop preview overlay** (`crop-preview-overlay-learnings.md`): The coordinate conversion formulas are unchanged. The zoom limits are a constraint layer applied before the coordinate transforms.

---
**Status:** Closed
**Follow-up:** None
