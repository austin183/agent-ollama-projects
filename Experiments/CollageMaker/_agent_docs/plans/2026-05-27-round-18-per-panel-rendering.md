# Round 18: Composite Rendering — Per-Panel Incremental Rendering

**Date**: 2026-05-27
**Change Request**: `_agent_docs/change-requests/round-18.md`

## Problem

Every pan/zoom gesture triggers `updatePreview()`, which composites the **entire 1920x1080 canvas** (background + all panels + title) into a single `NSImage`, then scales it to 960x540 for display. This is wasteful because only one panel's `sourceRect` changed.

The scroll pan path (`scrollPanDelta`) calls `updatePreview()` synchronously with **no debounce**, making this the hottest code path during interaction.

## Current Architecture (Baseline)

```
Gesture → CollageViewModel → updatePreview()
  → Task.detached → CollageAssembler.assemblePreviewWithCGImages()
    → 1920x1080 NSBitmapImageRep + CGContext
    → draw background (solid/gradient/image)
    → draw ALL panels (clip → crop source → draw to dest)
    → draw title (NSAttributedString)
    → return CGImage → NSImage at 960x540
  → @MainActor: self.previewImage = result
  → SwiftUI re-renders CollageEditorView.body
    → Image(nsImage: previewImage)  ← single composited image
    → overlay: PanelHitArea clear rects (hit-testing only)
```

## Target Architecture

```
Gesture → CollageViewModel → updatePanelPreview(panelId:)
  → Task.detached → CollageAssembler.renderPanel()
    → Panel-sized NSBitmapImageRep + CGContext
    → crop source image → draw to panel rect
    → return NSImage at panel size
  → @MainActor: self.panelRenderedImages[panelId] = result
  → SwiftUI re-renders only that panel's Image view

On gesture end → updatePreview() (full composite, restores title)
```

## Rendering Layers (CollageEditorView ZStack)

| Layer | Content | Re-renders when |
|---|---|---|
| 1. Background | Solid/gradient/image | Background settings change |
| 2. Per-panel images | Each panel's cropped image | That panel's `sourceRect` changes |
| 3. Title | NSAttributedString | Shown only in full composite, **hidden during live gestures** |
| 4. Title edit handles | Orange border rectangles (SwiftUI) | Always visible (not part of composite) |
| 5. Selection highlights | White stroke rectangles (SwiftUI) | Always visible |
| 6. PanelHitArea | Clear rectangles for gestures | Always visible |

**Title during live gestures**: Hidden intentionally so the image underneath is clearer to see while panning/zooming. Title reappears on gesture end when full composite runs.

## Files to Modify

### 1. `Services/CollageAssembler.swift`

Add to `CollageAssembly` protocol:

```swift
func renderPanel(
    panel: ImagePanel,
    crop: CropInfo,
    cgImage: CGImage,
    panelSize: CGSize
) -> NSImage?

func renderBackground(
    config: BackgroundConfig,
    canvasSize: CGSize,
    backgroundImage: CGImage?,
    previewSize: CGSize
) -> NSImage?
```

- `renderPanel`: Creates a CGContext at the panel's `destinationRect` size, crops the source image to `sourceRect`, draws it into the destination rect, returns `NSImage`. This is the hot path — called on every pan/zoom for the affected panel only.
- `renderBackground`: Draws just the background (solid/gradient/image) at canvas size, returns scaled `NSImage`. Called only when background settings change.

Extract the existing per-panel drawing logic from `drawPanels` (clip → crop → draw) into `renderPanel` so both export and incremental preview share the same code.

### 2. `ViewModel/CollageViewModel.swift`

New stored properties:

```swift
var previewBackgroundImage: NSImage?
var panelRenderedImages: [UUID: NSImage] = [:]
var isLiveGesturing: Bool = false
private var previousCropMap: [UUID: CropInfo] = [:]
```

New methods:

- **`updateBackground()`** — Renders background via `assembler.renderBackground()` on a detached task. Called from `didSet` of all background-related properties. Currently these all call `updatePreview()`; redirect them to `updateBackground()` + `updatePreview()` (to also refresh panels).

- **`updatePanelPreview(panelId: UUID)`** — New incremental method:
  1. Resolve effective image index via `panelAssignments`
  2. Get `CropInfo` from `cropMap[panelId]`
  3. Call `assembler.renderPanel()` on a detached task
  4. Dispatch result back to MainActor to update `panelRenderedImages[panelId]`
  5. Update `previousCropMap[panelId]`

Modified methods:

- **`applyPanLive()`** — Call `updatePanelPreview(panelId:)` instead of `updatePreview()`. Add 150ms debounce (same pattern as existing).
- **`applyPinchLive()`** — Call `updatePanelPreview(panelId:)` instead of `updatePreview()`. Add 150ms debounce.
- **`scrollPanDelta` applyLive closure** — Call `updatePanelPreview(panelId:)` instead of `updatePreview()`. Add 150ms debounce (currently has none).

Set `isLiveGesturing = true` at gesture start, `isLiveGesturing = false` at gesture end.

On gesture end (existing `onEnded` handlers), run full `updatePreview()` to restore title + all panels for consistency.

Keep `updatePreview()` for operations that affect the whole canvas:
- Layout changes, gutter changes
- Image additions/removals, swaps
- Saliency analysis completion
- Reset crop, overlay crop
- Initial load, gesture end

### 3. `Views/CollageEditorView.swift`

Replace the single `Image(nsImage: previewImage)` with a layered composition:

```swift
ZStack {
    // Background layer
    if let bg = viewModel.previewBackgroundImage {
        Image(nsImage: bg)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: geometry.size.width, height: geometry.size.height)
    }

    // Per-panel layers
    ForEach(viewModel.panels) { panel in
        if let renderedImage = viewModel.panelRenderedImages[panel.id],
           let scaledFrame = panelFrames[panel.id] {
            Image(nsImage: renderedImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: scaledFrame.width, height: scaledFrame.height)
                .position(x: scaledFrame.midX, y: scaledFrame.midY)
        }
    }

    // Title overlay — only visible when NOT live gesturing
    if !viewModel.isLiveGesturing, let scaled = titleFrame, !viewModel.title.isEmpty {
        // (existing title handle rectangles)
    }

    // Selection highlights (existing, unchanged)
    // PanelHitArea overlays (existing, unchanged)
    // Drag indicators (existing, unchanged)
}
```

**Fallback**: During initial load, if `panelRenderedImages` is empty, fall back to the full `previewImage` to avoid a blank canvas.

## Behavioral Matrix

| Operation | Before | After |
|---|---|---|
| Scroll pan (live) | Full 1920x1080 composite, no debounce | Single panel render, 150ms debounce, no title |
| Pinch zoom (live) | Full 1920x1080 composite, no debounce | Single panel render, 150ms debounce, no title |
| Gesture end | — | Full composite (restores title) |
| Layout change | Full composite | Full composite (unchanged) |
| Gutter change | Full composite | Full composite (unchanged) |
| Background color change | Full composite | Background-only + full composite |
| Image swap / add / remove | Full composite | Full composite (unchanged) |
| Reset crop | Full composite | Full composite (unchanged) |
| Saliency complete | Full composite | Full composite (unchanged) |
| Export | Full composite | Full composite (unchanged) |

## Implementation Order

1. Add `renderPanel()` and `renderBackground()` to `CollageAssembly` protocol + `CollageAssembler`
2. Add new state properties to `CollageViewModel` (`panelRenderedImages`, `previewBackgroundImage`, `isLiveGesturing`, `previousCropMap`)
3. Add `updatePanelPreview(panelId:)` and `updateBackground()` methods
4. Modify gesture handlers to use incremental rendering + debounce
5. Update `CollageEditorView` to render layered composition
6. Add fallback logic for initial load / transition states
7. Build and verify
8. Test: scroll pan, pinch zoom, layout change, export, title visibility

## Risks and Mitigations

1. **Coordinate system mismatches**: Panel rendering uses CG bottom-left origin, SwiftUI uses top-left. The existing `canvasToPreviewFrame` handles the canvas→preview scaling. The per-panel image is drawn at panel `destinationRect` size, then positioned by SwiftUI using the scaled frame.

2. **Stale panel images on layout change**: `panelRenderedImages` must be cleared in `regenerateLayout()` and repopulated via `updatePreview()`.

3. **Debounce + panel selection**: Hit-testing uses static `panel.frame` (canvas coordinates), NOT rendered images. Debouncing preview rendering is orthogonal to selection. The perceived "breakage" from prior debounce attempts was likely visual lag, not actual selection failure. Per-panel rendering is much faster than full composite, so visual lag should be minimal.

4. **Title edit handles during live gestures**: The orange border rectangles are SwiftUI overlays, not part of the composite. They should remain visible during live gestures for title repositioning. Only the rendered title text (NSAttributedString) is hidden.

5. **Aspect ratio of panel images**: The rendered panel image is at `destinationRect` size (canvas coords). SwiftUI scales it to `scaledFrame` size (preview coords). The `aspectRatio(contentMode: .fit)` ensures correct scaling.
