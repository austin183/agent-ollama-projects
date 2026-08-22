# Shared Offscreen Canvas for Text Measurement Hot Paths

**Date:** 2026-07-18
**Session:** 8 (Phase 1 code quality — TDD)

## Summary

When `CanvasRenderingContext2D.measureText()` is called in a hot path (e.g., pointermove during drag), creating a new offscreen canvas per call generates unnecessary garbage. The solution: create a single shared offscreen canvas at factory initialization and pass its context as `measureCtx` to measurement functions.

## The Problem

`computeMultiLineBounds()` in TitleRenderer.js accepts an optional `measureCtx` parameter. When omitted, it creates a new offscreen canvas:

```javascript
const ctx = measureCtx || (function () {
    const offscreen = document.createElement('canvas');
    return offscreen.getContext('2d');
})();
```

During a 1-second drag at 60fps, this creates 60 canvases and 60 2D contexts — all immediately garbage-collected. While modern JS engines handle short-lived allocations well, this is unnecessary work in an interaction hot path.

## The Solution

Create a shared offscreen canvas at factory init time and pass it to all measurement calls:

```javascript
// In createTitleInteraction() factory:
const measureCanvas = document.createElement('canvas');
measureCanvas.width = 1;
measureCanvas.height = 1;
const measureCtx = measureCanvas.getContext('2d');

// Pass to all computeMultiLineBounds calls:
const bounds = computeMultiLineBounds(style, runs, width, height, measureCtx);
```

## Key Details

- **Canvas sizing**: Set `width = 1; height = 1` to minimize surface allocation. `measureText()` only needs the context, not the drawing surface.
- **No race conditions**: JavaScript is single-threaded, so shared context is safe. Each `measureText()` call sets `ctx.font` before measuring, preventing state leakage.
- **Factory-scoped**: The shared canvas lives in the factory closure, not globally. Each handler instance gets its own canvas.
- **Backward compatible**: The `measureCtx` parameter is optional. Callers that don't pass it still work (they just create per-call canvases).

## Testing the Pattern

To verify the shared canvas eliminates allocations, wrap `document.createElement` to count canvas creations:

```javascript
let createCanvasCalls = 0;
const originalCreateElement = document.createElement.bind(document);
document.createElement = function(tagName) {
    if (tagName.toLowerCase() === 'canvas') createCanvasCalls++;
    return originalCreateElement(tagName);
};

// Create handler (factory creates shared canvas)
const handler = createTitleInteraction({...});

// Reset counter after factory init
createCanvasCalls = 0;

// Simulate drag — should create 0 new canvases
for (let i = 0; i < 20; i++) {
    canvas.dispatchEvent(new PointerEvent('pointermove', {...}));
}
expect(createCanvasCalls).to.equal(0);

// Restore
document.createElement = originalCreateElement;
```

## When to Apply

Use this pattern when:
1. A measurement function accepts an optional context parameter
2. The function is called in a hot path (pointermove, animation frame)
3. The caller has a stable factory scope to hold the shared resource

## Related

- `offscreen-canvas-export-and-vue-provide-timing.md` — Offscreen canvas for JPEG exports
- `building-web-apps` skill: Canvas 2D reference, factory testability patterns
