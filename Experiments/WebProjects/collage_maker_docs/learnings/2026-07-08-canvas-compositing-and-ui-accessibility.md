# Canvas Compositing Order and UI Accessibility Patterns

**Date:** 2026-07-08
**Session:** 54 (Phase 2: UI/UX Polish & Bug Fixes)

## Summary

Two patterns discovered during Phase 2 implementation: Canvas 2D compositing order for semi-transparent images, and ARIA patterns for accessible segmented controls and decorative indicators.

---

## Canvas 2D Compositing Order for Semi-Transparent Images

When drawing a semi-transparent image on Canvas 2D using `globalAlpha`, the image pixels are blended against whatever is already on the canvas. Unlike CSS `opacity` (which creates an isolated compositing layer), Canvas 2D `globalAlpha` blends directly against the existing canvas pixels.

### The Problem

If the canvas background is white (default) or transparent, and you draw a semi-transparent PNG with `globalAlpha = 0.5`, the transparent areas of the PNG show the white canvas — not the user's configured background color.

### The Fix

**Always pre-fill the canvas with the configured background color or gradient before drawing the semi-transparent image:**

```javascript
function renderImage(ctx, width, height, state) {
    // Step 1: Fill background so it shows through transparent image areas
    ctx.fillStyle = state.color1 || '#000000';
    ctx.fillRect(0, 0, width, height);

    // Step 2: Draw image with opacity on top
    if (state.image) {
        ctx.save();
        ctx.globalAlpha = state.opacity ?? 1.0;
        ctx.drawImage(state.image, 0, 0, width, height);
        ctx.restore();
    }
}
```

### Key Points

- **`ctx.save()`/`ctx.restore()` isolates `globalAlpha`** — prevents alpha leakage to subsequent render pipeline stages
- **Always pre-fill even at 100% opacity** — defensive coding; if opacity changes, the background is already there
- **Null image handling** — if no image is provided, the background fill alone is sufficient; skip the drawImage call
- **Test with Proxy-based context mocking** — verify both `fillStyle`/`fillRect` calls (background) AND `globalAlpha`/`drawImage` calls (foreground)

### Testing Strategy

Use the existing `createMockCtx()` pattern from BackgroundRendererTest.html to verify:
1. Background fill is called before image draw
2. `globalAlpha` is set to the correct opacity value
3. `ctx.save()`/`ctx.restore()` are called to isolate alpha state
4. Null image skips drawImage but still fills background

### File Reference

- `MyESModules/Rendering/BackgroundRenderer.js` — `renderImage()` function
- `MyComponents/BackgroundRendererTest.html` — Section 1.5 tests

---

## ARIA Patterns for Vue Segmented Controls

When building segmented controls (toggle groups) in Vue templates, use proper ARIA roles for keyboard and screen reader accessibility.

### Segmented Control with Radiogroup

For mutually exclusive options (like JPEG/PNG format selector):

```html
<label id="exportFormatLabel">Format</label>
<div class="segmented-control" role="radiogroup" aria-labelledby="exportFormatLabel">
    <button class="segment-btn"
            :class="{ active: exportFormat === 'jpeg' }"
            role="radio"
            :aria-checked="exportFormat === 'jpeg'"
            @click="exportFormat = 'jpeg'">
        JPEG
    </button>
    <button class="segment-btn"
            :class="{ active: exportFormat === 'png' }"
            role="radio"
            :aria-checked="exportFormat === 'png'"
            @click="exportFormat = 'png'">
        PNG
    </button>
</div>
```

### Key Points

- **`role="radiogroup"`** on the container groups the buttons as a radio group
- **`aria-labelledby`** associates the group with its label
- **`role="radio"`** on each button exposes it as a radio option to screen readers
- **`:aria-checked`** dynamically reflects the selected state
- **`<button>` elements** are natively keyboard-focusable and activatable (Enter/Space)

### Decorative Visual Indicators

When a visual indicator (like a color swatch) duplicates information already available from an adjacent control, use `aria-hidden="true"` to prevent screen reader confusion:

```html
<div class="color-picker-row">
    <input type="color" id="bgColorPicker" v-model="backgroundColor" @input="onBackgroundColorChange">
    <span class="color-swatch" :style="{ backgroundColor: backgroundColor }" aria-hidden="true"></span>
</div>
```

**Why:** The `<input type="color">` already announces its value to screen readers. A separate `aria-label` on the swatch would duplicate the announcement, confusing users who hear the color value twice.

### File Reference

- `index.html` — Export format selector and color swatches
- `Style.css` — `.color-swatch` styles
