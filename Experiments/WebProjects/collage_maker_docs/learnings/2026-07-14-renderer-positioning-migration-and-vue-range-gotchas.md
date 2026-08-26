# 2026-07-14 — Renderer Positioning Model Migration and Vue Range Input Gotchas

## Context

During Phase 4 implementation (Title Width and Alignment Within Width), the TitleRenderer needed to support a new "box-based" positioning model where text aligns within a configurable width box, while preserving the existing "canvas-relative" positioning behavior for backward compatibility.

## Learnings

### 1. Legacy Mode Detection in Renderers

When adding a new positioning/layout model to an existing renderer, preserve backward compatibility by detecting "legacy mode" and applying the original behavior:

```javascript
// Detect legacy mode: no custom width or position set
const isLegacyMode = (titleStyle.titleBoxWidth === null || titleStyle.titleBoxWidth === undefined)
    && (titleStyle.titleBoxX === null || titleStyle.titleBoxX === undefined);

if (isLegacyMode) {
    // Original canvas-relative positioning
    switch (alignment) {
        case 'left': effectiveBoxX = MARGIN; break;
        case 'right': effectiveBoxX = width - MARGIN - totalWidth; break;
        default: effectiveBoxX = (width - totalWidth) / 2; break;
    }
} else {
    // New box-based positioning
    effectiveBoxX = (width - boxWidth) / 2; // Center box in canvas
}
```

**Key insight**: The legacy mode check must use `=== null || === undefined` (not truthy/falsy) because `0` could be a valid value in some contexts. Also, the check should be computed once and reused across multiple rendering decisions (position, background, outline).

### 2. Vue Range Input with Null Default

`v-model.number` on `<input type="range">` coerces `null` to the `min` attribute value, which is unexpected when `null` represents "auto/unset":

```html
<!-- WRONG: null coerces to min (100), slider shows 100 when value is "Auto" -->
<input type="range" v-model.number="titleStyle.titleBoxWidth" min="100" max="1920">

<!-- CORRECT: :value with fallback, @input with explicit value -->
<input type="range"
    :value="titleStyle.titleBoxWidth || 1920"
    min="100" max="1920"
    @input="onTitleWidthChange($event.target.value)">
```

**Why this matters**: The range input DOM element requires a numeric value within `[min, max]`. When Vue binds `null` via `v-model.number`, it coerces to the minimum, making the UI show an incorrect value. Using `:value` with a fallback gives full control over the displayed value, and `@input` with `$event.target.value` passes the raw slider value to the handler.

### 3. Optional Context Parameter for Measurement Functions

Pure measurement functions that need a Canvas 2D context should accept an optional context parameter to avoid offscreen canvas creation in hot paths:

```javascript
export function computeBounds(titleStyle, titleRuns, width, height, measureCtx) {
    // Use provided context if available, otherwise create offscreen canvas
    const ctx = measureCtx || (() => {
        const offscreen = document.createElement('canvas');
        return offscreen.getContext('2d');
    })();
    // ... measurement using ctx.measureText()
}
```

**Why this matters**: Creating offscreen canvases during `pointermove` events causes GC pressure and frame drops. Callers in hot paths (interaction handlers) should pass the render context. Callers in cold paths (initial layout) can omit it and let the function create one.

### 4. Destructured Parameter Scoping in ES Modules

When a function destructures its parameter object, the original variable name is not accessible inside the function body:

```javascript
// WRONG: `options` is not defined inside the function
render(ctx, { panels, images, titleStyle, titleRuns }) {
    renderTitle(ctx, w, h, titleStyle, titleRuns, {
        hoverTarget: options.titleHoverTarget  // ReferenceError!
    });
}

// CORRECT: Destructure the new properties too
render(ctx, { panels, images, titleStyle, titleRuns, titleHoverTarget }) {
    renderTitle(ctx, w, h, titleStyle, titleRuns, {
        hoverTarget: titleHoverTarget || null  // Works
    });
}
```

**Why this matters**: JavaScript destructuring creates new bindings for each destructured property. The original parameter name (`options`, `params`, etc.) is not preserved. This is a common gotcha when adding new properties to an existing destructured signature.

### 5. Background Rendering in Mixed Positioning Modes

When a renderer supports both legacy and box-based positioning, the background rect positioning must account for the difference:

- **Legacy mode**: `boxLeft` is at text start, `boxWidth` already includes padding → background at `boxLeft - PADDING` with width `boxWidth`
- **Box mode**: `boxLeft` is at box edge, `boxWidth` is user-set → background at `boxLeft` with width `boxWidth`

The `isLegacyMode` flag computed once at the top of the render function drives both positioning and background decisions consistently.

## Related

- Phase 4 plan: `_agent_docs/plans/2026-07-13-title-sidebar-home-implementation.md`
- TitleRenderer: `MyESModules/Rendering/TitleRenderer.js`
- Vue Options API reference: `.opencode/skills/building-web-apps/references/vue-options-api.md`
