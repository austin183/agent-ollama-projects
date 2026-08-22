# Bugs in Panel Editing in Main Image
## Reproduction Steps
- Open Application
- Add Images
- Select a Panel
- Pinch to Zoom Out
  - The Panel Zooms out as Expected
- Use Two fingers to scroll
  - Notice that while the image in the panel is moving, the rest of the panel images disappear
  - Sometimes after stopping, the rest of the panel images reappear, but other times they do not appear
  - Zooming again will also intermittently cause the rest of the panel images disappear
- Use the Panel Editor to click and drag to move the image in the panel
- Or Click and Drag a Corner
  - This will also cause the rest of the panel images to disappear

The Title also appears and disappears with panel editing activities.

The panel images should always be visible, even if they are not recomputed during the panel editing activity.  The Title should always appear when no panels are being panned or zoomed with any inputs.

---

## Agent Theories and Leads (from Round 18 implementation session)

### Root Cause: Rendering mode switch creates async gaps

`CollageEditorView` uses `viewModel.panelRenderedImages.isEmpty` to decide between two rendering modes:
- **Empty** → show full composite `previewImage` (includes title)
- **Non-empty** → show layered background + per-panel images (no title in composite)

**The problem:** Both `panelRenderedImages` and `previewImage` are populated asynchronously via `Task.detached`. Clearing one before the other is ready creates a window where neither rendering mode has content.

### Specific triggers

**1. Gesture end handlers clear `panelRenderedImages` synchronously, then call async `updatePreview()`:**

```swift
// CollageEditorView scroll pan ended:
viewModel.panelRenderedImages.removeAll()  // ← immediate, mode switches to full composite
viewModel.updatePreview()                   // ← async, previewImage not ready yet
```

Result: `panelRenderedImages` is empty (no layered view), `previewImage` is stale or nil (no composite). Blank panels.

**2. Panel editor operations (`applyOverlayCrop`) call both `updatePreview()` and `updatePanelPreview(panelId:)`:**

```swift
// CollageViewModel.applyOverlayCrop:
updatePreview()              // ← async, populates previewImage
updatePanelPreview(panelId:) // ← async, populates panelRenderedImages[one panel]
```

If `updatePanelPreview` completes before `updatePreview`, `panelRenderedImages` becomes non-empty → mode switches to layered → only ONE panel has an image → other panels disappear.

**3. Title flicker:** Title overlay visibility is gated on `!isLiveGesturing`. But `isLiveGesturing` is only set by scroll pan and pinch gestures, NOT by panel editor operations. When the rendering mode briefly switches to full composite (which contains the baked-in title), the title appears. When it switches back to layered, the title disappears.

### Proposed fixes

**Fix A — Don't clear `panelRenderedImages` on gesture end or crop operations.**

Instead of:
```swift
viewModel.panelRenderedImages.removeAll()
viewModel.updatePreview()
```

Use:
```swift
viewModel.updatePreview()
viewModel.updateAllPanelPreviews()  // repopulate in background
```

Stale per-panel images remain visible during the async gap. This is visually acceptable — the user just completed a gesture, stale images are one frame behind.

**Fix B — Change fallback condition from `panelRenderedImages.isEmpty` to `previewImage == nil && panelRenderedImages.isEmpty`.**

Only show full composite when we actually have one AND have nothing else to show. If `panelRenderedImages` has content, keep showing it even if it's partially stale.

**Fix C — Hide title overlay in layered mode regardless of `isLiveGesturing`.**

The title is already baked into `previewImage` (full composite). In layered mode there's no title. The overlay should only appear when showing the full composite:

```swift
// Only show title handles when showing full composite AND not live gesturing
if !viewModel.isLiveGesturing, viewModel.panelRenderedImages.isEmpty, let scaled = titleFrame {
```

**Fix D — Extend `isLiveGesturing` to cover panel editor operations.**

Set `isLiveGesturing = true` at the start of overlay crop drag, `false` on end. This prevents title flicker during panel editor interactions.

### Files to investigate
- `Views/CollageEditorView.swift:81` — `panelRenderedImages.isEmpty` fallback
- `Views/CollageEditorView.swift:218` — scroll pan ended handler
- `Views/CollageEditorView.swift:366` — pinch ended handler
- `ViewModel/CollageViewModel.swift:698` — `applyOverlayCrop` calls both update paths
- `Views/PanelCropEditor.swift` — overlay crop gesture handlers (may need `isLiveGesturing` wiring)