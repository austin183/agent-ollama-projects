# 2026-07-11 — Canvas Border Refactoring and Drag Cleanup Patterns

## Context
Phase 3 follow-up: hex panel swap visual feedback, sidebar reorder, ARIA accessibility. Refactored PanelRenderer to extract shared border-drawing logic and added global drag cleanup.

## Learnings

### 1. Config-based extraction for Canvas 2D rendering helpers
When multiple Canvas 2D methods share the same save/restore + property-setting + geometry-branching pattern, extract a shared helper that accepts a style config object. This eliminates DRY violations while keeping each public method as a thin, readable wrapper.

**Pattern:**
```js
_drawPanelBorder(ctx, panel, config) {
    ctx.save();
    ctx.strokeStyle = config.strokeStyle;
    ctx.lineWidth = config.lineWidth;
    if (config.shadowColor !== undefined) ctx.shadowColor = config.shadowColor;
    // ... optional properties guarded by !== undefined
    // Geometry branching
    ctx.restore();
}

drawSelectionBorder(ctx, panel) {
    this._drawPanelBorder(ctx, panel, {
        strokeStyle: '#ffffff', lineWidth: 3, shadowColor: '...', inset: 1.5
    });
}
```

**Key insight:** Optional config properties must be guarded with `!== undefined` checks, not truthy checks, because values like `0` or `''` are valid canvas property values.

### 2. Global pointerup listener for drag-and-drop cleanup
When implementing drag-and-drop on a specific element (e.g., a canvas), always add a global `window.addEventListener('pointerup', ...)` listener to clean up drag state. If the user releases the pointer outside the element (drags off-screen, switches tabs, window loses focus), the element-level `pointerup` never fires and drag state gets stuck (cursor stuck as 'grabbing', visual highlights persisting).

**Pattern:**
```js
attach() {
    canvas.addEventListener('pointerup', onPointerUp);
    window.addEventListener('pointerup', onGlobalPointerUp);
}
detach() {
    canvas.removeEventListener('pointerup', onPointerUp);
    window.removeEventListener('pointerup', onGlobalPointerUp);
}
onGlobalPointerUp = () => {
    if (isDragging || dragSourceId) {
        handler._clearDragState();
    }
};
```

### 3. ARIA role selection for interactive canvases
- `role="img"` is for **static, non-interactive** images. It tells screen readers to treat the element as a decorative or content image.
- `role="application"` is appropriate for **complex interactive widgets** where standard widget semantics don't apply (canvas-based editors, games, drag-and-drop surfaces).
- Always pair `role="application"` with a descriptive `aria-label` that explains what the user can do.

**Anti-pattern:** Using `role="img"` on a canvas that accepts pointer interactions. This misleads screen reader users into thinking the element is static content.

### 4. Characterization tests before refactor
Before refactoring shared code, add characterization tests that capture the current observable behavior. This gives confidence that the refactor doesn't change behavior. In this session, adding tests for `lineWidth` and `globalAlpha` on `drawHexDragTarget` before extracting the shared helper ensured the refactored config-based approach preserved all style properties.

## Related Files
- `MyESModules/Rendering/PanelRenderer.js` — `_drawPanelBorder` extraction
- `MyESModules/Interaction/HexPanelSwap.js` — global pointerup cleanup
- `index.html` — ARIA role fixes
