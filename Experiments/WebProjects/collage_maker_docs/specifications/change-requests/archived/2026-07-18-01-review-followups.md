# Review Follow-ups — Title Changes (Phases 1-4)

Source: `_agent_docs/reviews/2026-07-18-title-changes-review.md`

---

## Code Quality

### Duplicate MARGIN Constant

`TitleInteraction.js` declares `const MARGIN = 40;` in two places (`_hitTestTitle` line 150, `_onPointerDown` line 255) that duplicates the `MARGIN` constant in `TitleRenderer.js` line 7. Since `PADDING` was already exported from `TitleRenderer.js`, `MARGIN` should follow the same pattern.

**Options:**
- Export `MARGIN` from `TitleRenderer.js` and import it in `TitleInteraction.js` (consistent with `PADDING`)
- Move both `MARGIN` and `PADDING` to `SizeConstants.js` for a single source of truth

### Offscreen Canvas in Interaction Hot Path

`TitleInteraction.js` calls `computeMultiLineBounds` 3–4 times per `pointermove` event (drag handler, resize-right, resize-left) without passing a `measureCtx`. Each call creates a new offscreen canvas via `document.createElement('canvas')`. For 3 lines this is negligible, but the pattern is wasteful.

**Suggested fix:** Create a shared offscreen canvas context at handler initialization and pass it as `measureCtx` to `computeMultiLineBounds` calls in the interaction hot path.

### computeBounds Import in TitleInteractionTest

`TitleInteractionTest.html` imports `computeBounds` (single-line) for self-calibrating hit test coordinates, while production code uses `computeMultiLineBounds`. For single-line tests the results are identical, but using `computeMultiLineBounds` would keep tests aligned with production.

---

## UX Improvements

### Enter Key Flicker

When a user has 3 lines of title text and presses Enter, the native `<textarea>` may visually insert a 4th line for a brief frame before Vue's reactive update clamps the state back to 3 lines. This creates a visual flicker that users will perceive as a bug.

**Suggested fix:** Add `@keydown.enter.prevent` on the textarea (with a line-count guard so Enter still works on lines 1 and 2), or check line count in the `@input` handler before updating state to prevent the textarea from ever rendering a 4th line.

### Silent Truncation Feedback

Pasting multi-line text (e.g., a 5-line quote) silently truncates to 3 lines via `setText` → `split('\n')` → `slice(0, 3)`. Users receive no feedback that their content was trimmed.

**Suggested fix:** Show a toast notification (e.g., "Title truncated to 3 lines") when `setText` discards lines. Alternatively, add a subtle visual indicator (border color change, ellipsis) on the textarea when content is truncated.

### Leading Newline Stripping

`splitRunsByNewline` silently strips leading empty lines (lines 114–116 of `TitleRenderer.js`). If a user types `\n\nHello`, the rendered title shows `Hello` on a single line with no visual indication that leading newlines were consumed.

**Suggested fix:** Document this behavior in a comment. Alternatively, preserve leading empty lines as blank rendered lines (the renderer already handles empty runs via the `parts[i].length > 0` guard — removing this guard would render empty lines with line-height spacing).

---

## Accessibility

### Formatting Button ARIA States

The Bold, Italic, and Underline buttons toggle formatting independently (fixed in Phase 1). For screen reader users, these buttons should use `aria-pressed="true"` or `role="switch"` with `aria-checked` to communicate their active state.

**Suggested fix:** Bind `aria-pressed` on each formatting button to the current formatting state of the selected range.

### Textarea Labeling

The `<textarea>` replaced the `<input type="text">` for title entry. Ensure the textarea has a proper associated `<label>` or `aria-label` so screen readers announce its purpose (e.g., "Collage Title").

**Note:** The existing `<label for="titleInput">Text</label>` should still associate with the textarea via the matching `id="titleInput"`. Verify this association is intact.

### Mobile Touch Targets

When a title expands to 3 lines, its height increases significantly (potentially 60–100px). The resize handles (8px edge threshold) may be difficult to target on mobile devices. WCAG recommends minimum 44x44px touch targets.

**Suggested fix:** Increase `EDGE_THRESHOLD` from 8 CSS pixels to a larger value (e.g., 16–20px) for touch devices, or detect `pointerType === 'touch'` and use a wider hit area.
