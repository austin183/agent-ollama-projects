# Title Alignment Rendering — Learnings

**Date:** 2026-05-16
**Session:** 21 — Round 4, Items 4–5 + alignment behavior fix

---

## SF Symbol Name Lookup

- SF Symbol names don't always follow intuitive patterns. `text.align.left` doesn't exist — the correct names are `text.alignleft`, `text.aligncenter`, `text.alignright` (no dot between "align" and direction).
- Invalid SF Symbol names render as empty placeholders with no click response, making them hard to diagnose visually.
- Use `playwright-cli` to navigate `developer.apple.com/design/human-interface-guidelines/icons` and search for symbols when unsure. The page renders as a JS SPA — `webfetch` returns only noscript placeholders.

## NSAttributedString boundingRect() Returns Tight Bounds

- `attributedString.boundingRect(with:options:)` returns the tight bounding box of the rendered text, not its position within the constrained rect.
- `boundingBox.origin.x` is always ~0 (left edge of the text), regardless of paragraph alignment. Cannot use it to compute where aligned text will appear within a wider draw rect.
- To position a background around aligned text, either:
  - Make the background span the full draw width (simplest, box stays fixed)
  - Compute text offset manually from alignment: left = 0, center = `(drawWidth - textWidth) / 2`, right = `drawWidth - textWidth`

## draw(at:) vs draw(in:) Baseline Semantics

- `draw(at:point)` draws the text with `point` as the baseline. Combined with `boundingRect()`, the baseline Y is `anchorY - boundingBox.height` where `anchorY` is the desired text top.
- `draw(in:rect)` treats `rect.y` as the baseline, not the top of the text. This caused text to appear above the background box when switching from `draw(at:)` to `draw(in:)`.
- `draw(in:)` does respect paragraph alignment (left/center/right), but `draw(at:)` with a manually computed X offset gives the same visual result with more predictable vertical positioning.
- For title rendering where you need a tight background pill around text, `draw(at:)` with manual offset is simpler and less error-prone.

## Alignment Should Move Text Within a Fixed Box

- When the user changes text alignment, the visual expectation is that the text box stays put and the text inside it repositions.
- The original code shifted the entire box (background + text) based on alignment, so the user saw the whole title move across the canvas.
- Fix: background spans full draw width and stays centered at `positionX`. Text offset is computed from alignment and applied only to the draw position.

---
**Status:** Closed
**Follow-up:** None
