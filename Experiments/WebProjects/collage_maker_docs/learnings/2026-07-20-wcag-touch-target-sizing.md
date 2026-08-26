# WCAG 2.1 SC 2.5.8: Touch Target Sizing

**Date:** 2026-07-20
**Session:** 2026-07-20-005 (Pre-Merge Review Fixes — Phase 6: WCAG Touch Targets)

## Summary

Increased all interactive touch targets in CollageMaker to a minimum of 44x44 CSS pixels to comply with WCAG 2.1 Success Criterion 2.5.8 (Target Size: Minimum). This was a CSS-only change covering 11 selectors across the application.

---

## WCAG 2.1 SC 2.5.8 — Target Size (Minimum)

WCAG 2.1 SC 2.5.8 (Level AAA) requires that the size of a target for pointer input be at least **44 by 44 CSS pixels**, with limited exceptions. While Level AA compliance doesn't strictly require this, it's a best practice for touch-friendly interfaces and future-proofs against WCAG 2.2 which elevates this to Level AA.

### Exceptions (WCAG 2.5.8)

The following are exempt from the 44x44px requirement:
- **Equivalents** — if the same function is available via a target that meets the size requirement
- **Inline** — targets that are part of a text block (e.g., links within paragraph text)
- **Unavoidable** — targets whose size is determined by the rendering user agent and cannot be modified
- **Essential** — where a specific presentation is essential to the functionality (e.g., a pixel-precise drawing tool)
- **Largest content area** — targets larger than the viewport are exempt (rare)

**Standard native user-agent controls** (checkboxes, radio buttons, range sliders) generally fall under the "Unavoidable" exception since their hit areas are determined by the browser/OS. However, **custom-styled controls** (like `<input type="color">` with custom CSS) are NOT exempt.

---

## min-height vs height for Touch Targets

Choose the sizing property based on the button type:

### Text buttons — use `min-height`

For buttons with text content (`.pure-button`, `.segment-btn`, `.export-btn`), use `min-height: 44px` rather than `height: 44px`:

```css
.pure-button {
    padding: var(--space-2) var(--space-4);
    font-size: var(--font-size-sm);
    min-height: 44px; /* Lets button grow if content is taller */
}
```

**Why `min-height` over `height`:**
- If the font size increases (user zoom, high-DPI scaling, accessibility overrides), the button grows to accommodate content
- Prevents text overflow or clipping at larger zoom levels
- Works naturally with flex layout — the button takes only as much space as needed, up to the minimum

### Icon-only buttons — use `min-width` + `min-height`

For icon-only buttons (`.toolbar-icon-btn`, `#themeToggle`, `.remove-btn`), use both `min-width` and `min-height`:

```css
.toolbar-icon-btn {
    min-width: 44px;
    min-height: 44px;
    padding: var(--space-2);
    display: flex;
    align-items: center;
    justify-content: center;
}
```

**Why both:** Icon-only buttons have no text content to drive their size, so both dimensions need explicit minimums.

### Fixed-size buttons — use `width` + `height`

For buttons in a formatting bar where uniform sizing is critical (`.format-btn`), fixed dimensions ensure visual consistency:

```css
.format-btn {
    width: 44px;
    height: 44px;
    display: flex;
    align-items: center;
    justify-content: center;
}
```

**Why fixed:** In a row of formatting buttons (bold, italic, underline), any size variation would look broken. Fixed dimensions guarantee alignment.

---

## Circular Buttons with WCAG Sizing

When a button uses `border-radius: 50%` for a circular appearance, ensure equal `min-width` and `min-height`:

```css
.remove-btn {
    min-width: 44px;
    min-height: 44px; /* Equal to min-width = perfect circle */
    border-radius: 50%;
    padding: var(--space-2); /* Equal padding on all sides */
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0; /* Prevent squishing in flex container */
}
```

**Key properties for maintaining circular shape:**
- Equal `min-width` and `min-height` — ensures square aspect ratio
- Equal `padding` on all sides — prevents content from pushing one side more than another
- `flex-shrink: 0` — prevents the flex container from compressing the button into an oval
- `border-radius: 50%` on a square element always produces a perfect circle

---

## Native Form Controls That Need Custom Touch Areas

Some native form controls have browser-defined hit areas below 44px and are styled with custom CSS:

### `<input type="color">`

The native color picker input typically renders at 32-36px height. To meet WCAG 2.5.8:

```css
.color-picker-row input[type="color"] {
    height: 44px;
    min-height: 44px;
    padding: 0;
}
```

**Note:** Increasing the height of `<input type="color">` works consistently across modern browsers. The color swatch scales proportionally within the larger hit area.

### `<input type="file">` via `::-webkit-file-upload-button`

The file upload button is styled via pseudo-element and has limited CSS control. The WCAG review noted this as a potential issue but deferred it — the `::-webkit-file-upload-button` pseudo-element has limited height control and increasing it can cause rendering inconsistencies across browsers.

---

## Selectors Updated in CollageMaker

| Selector | Previous Size | New Size | Property Used |
|----------|--------------|----------|---------------|
| `#themeToggle` | 40x40px min | 44x44px min | `min-width`, `min-height` |
| `.toolbar-icon-btn` | 32x32px min | 44x44px min | `min-width`, `min-height` |
| `.format-btn` | 32x32px fixed | 44x44px fixed | `width`, `height` |
| `.remove-btn` | ~24px (padding: 2px) | 44x44px min | `min-width`, `min-height` + `padding: var(--space-2)` |
| `.pure-button` | ~30px (padding only) | 44px min | `min-height` |
| `.pure-button-primary` | ~30px (padding only) | 44px min | `min-height` |
| `.segment-btn` | ~30px (padding only) | 44px min | `min-height` |
| `.reset-crop-btn` | ~30px (padding only) | 44px min | `min-height` |
| `.export-btn` | ~30px (padding only) | 44px min | `min-height` |
| `.remove-bg-btn`, `.remove-overlay-btn` | ~22px (padding only) | 44px min | `min-height` |
| `input[type="color"]` | 36px | 44px | `height`, `min-height` |

---

## Testing Touch Target Sizes

WCAG touch target compliance is verified manually using browser DevTools:

1. Open DevTools → Elements panel
2. Select the interactive element
3. Check Computed tab for `width` and `height` (or `min-width`/`min-height`)
4. Verify both dimensions are >= 44px

**Automated testing option:** Playwright can verify computed styles:

```javascript
const btn = page.locator('#themeToggle');
const style = await btn.evaluate(el => getComputedStyle(el));
expect(parseInt(style.minWidth)).toBeGreaterThanOrEqual(44);
expect(parseInt(style.minHeight)).toBeGreaterThanOrEqual(44);
```

---

## File Reference

- `Style.css` — All touch target size updates
