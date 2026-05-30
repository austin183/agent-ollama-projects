# SwiftUI Text vs CG Font Metrics — Learnings

**Date:** 2026-05-29
**Purpose:** Document learnings from Round 19.1 — attempting to use SwiftUI `Text` as a live gesture overlay for CG-rendered content.

---

## What Worked

- **Debounced layer-only render during gesture** — Instead of the full collage composite (`updatePreview()`), debouncing only the changed layer (`updateTitleImage()`) at 150ms provides smooth visual feedback during drag. The existing pre-rendered `titleImage` is shown with correct font, size, background, and position. This extends the per-panel debounce pattern (Round 18) to other rendered layers.

- **`finishTitleDrag()` pattern** — Cancels pending debounce task before running the final full composite. Consistent with `finishOverlayCrop` and the existing pan/pinch gesture end handlers.

## What Didn't Work / Gaps

- **SwiftUI `Text` cannot match CG `NSAttributedString.draw` font metrics** — When trying to use a SwiftUI `Text` overlay as a live gesture preview for content that is normally rendered via CoreGraphics (`NSAttributedString.draw(in:)`), the font size appeared different despite using the exact same font family and size. Multiple approaches failed to match:
  - `Text(viewModel.title).font(.system(size: fontSize, weight: .bold))` — wrong size
  - `Text(viewModel.title).font(.custom(fontFamily, size: fontSize))` — wrong size
  - `AttributedString(NSAttributedString)` with `.font()` modifier — wrong size
  - `AttributedString.font = Font` property — wrong size

  The root cause is that SwiftUI and CoreGraphics use different font rendering engines with different metrics (ascent, descent, leading, em-square). Even with identical font descriptors, the rendered size will differ.

  **Solution:** When pixel-perfect rendering is required during a live gesture, use the same rendering pipeline (CoreGraphics) with debouncing, not a different renderer (SwiftUI). The debounced CG render at 150ms provides acceptable responsiveness.

## Key Pattern: Same Renderer, Debounced

When a gesture needs live visual feedback for content rendered via CoreGraphics:

1. **Don't switch renderers** — A SwiftUI overlay will not match CG output pixel-for-pixel
2. **Debounce the CG render** — 150ms debounce on the specific layer (not full composite) provides smooth feedback
3. **Show existing render during gap** — The pre-rendered `NSImage` from before the gesture remains visible, providing continuity
4. **Final composite on gesture end** — Full composite restores all layers for consistency

This applies to:
- Title repositioning/resizing
- Any CG-rendered overlay that needs to track a gesture
- Watermarks, annotations, or other non-panel content

---
**Status:** Closed
**Follow-up:** None
