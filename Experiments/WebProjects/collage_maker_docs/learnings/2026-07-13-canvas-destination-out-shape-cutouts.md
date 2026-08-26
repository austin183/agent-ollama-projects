# Canvas `destination-out` Compositing for Shape Cutouts

## Date

2026-07-13

## Context

Implementing Phase 1 of the "Shaped Crop Overlay" feature for the CollageMaker crop preview. The goal: for non-rectangular panels (hexagonal, diagonal slices), the dark overlay in the crop preview should follow the panel's geometric shape instead of always being rectangular.

## Problem

The crop preview canvas shows a dark overlay outside the crop region to help users see what part of the image will be included. For rectangular panels, this is straightforward — 4 `fillRect` calls around the crop rectangle. But for shaped panels (hexagons, parallelograms), we need the dark overlay to have a shaped "hole" that matches the panel geometry.

## Solution: `destination-out` Compositing with Clip

Use `globalCompositeOperation = 'destination-out'` to cut a shaped hole in a full dark overlay, constrained to the crop rectangle via `ctx.clip()`:

```javascript
// 1. Fill entire canvas with dark overlay
ctx.fillStyle = 'rgba(0, 0, 0, 0.55)';
ctx.fillRect(0, 0, cssW, cssH);

// 2. Cut out the shape, clipped to crop rect
ctx.save();
try {
    ctx.globalCompositeOperation = 'destination-out';

    // Clip to crop rectangle first
    ctx.beginPath();
    ctx.rect(cropScreenX, cropScreenY, cropScreenW, cropScreenH);
    ctx.clip();

    // Draw the shape — this erases the dark overlay where the shape is
    beginPathFromPoints(ctx, shapePoints);
    ctx.fill();
} finally {
    ctx.restore();
}
```

### How It Works

1. **Full dark fill** — covers the entire canvas with the dark overlay color
2. **Clip to crop rect** — `ctx.clip()` restricts subsequent operations to the crop region
3. **destination-out fill** — `ctx.fill()` with `destination-out` erases existing pixels where the shape draws, creating a transparent "hole" in the dark overlay
4. **Restore** — `ctx.restore()` resets both the clip region and the composite operation

### Key Patterns

**Always use `try/finally` for save/restore safety.** If an exception occurs between `ctx.save()` and `ctx.restore()` (e.g., malformed points, invalid path), the canvas state leaks: `globalCompositeOperation` remains `'destination-out'` and the clip region stays active, corrupting all subsequent drawing. The `try/finally` guarantees restoration:

```javascript
ctx.save();
try {
    ctx.globalCompositeOperation = 'destination-out';
    // ... risky operations ...
} finally {
    ctx.restore();
}
```

**Clip before composite.** The clip region is persistent until `ctx.restore()`. Set it before the composite operation so the shape cutout is constrained to the crop rectangle.

**Compute shape points once.** When the same shape points are needed for multiple operations (cutout fill, border stroke, decorative overlay), compute them once and reuse:

```javascript
const shapePoints = computeShapeOverlayPoints(geometry, cropScreen, 0);
// Reuse for cutout, border, and overlay
```

### Anti-Aliasing Considerations

Canvas 2D anti-aliasing at the shape edges of a `destination-out` fill produces a semi-transparent fringe (the "halo effect"). This is usually visually acceptable and is further masked by the decorative shape overlay drawn on top with a solid stroke. If the halo is objectionable, slightly increase the shape size (negative padding) to compensate.

### Testing Strategy

Test the shaped overlay approach by wrapping canvas context methods to capture operations:

```javascript
// Capture clip() and globalCompositeOperation changes
ctx.clip = function () {
    captured.clip.push(true);
    return origClip();
};

Object.defineProperty(ctx, 'globalCompositeOperation', {
    get: function () { return this._gco || 'source-over'; },
    set: function (v) {
        captured.globalCompositeOperation.push(v);
        this._gco = v;
    },
    configurable: true
});
```

Verify:
- Shaped panels: `clip` called at least once, `globalCompositeOperation` includes `'destination-out'`
- Rect panels: no `clip` calls, no `'destination-out'` compositing
- save/restore counts are balanced

## When to Use This Pattern

- When you need to cut a shaped hole in a filled region on Canvas 2D
- When the shape is defined by polygon points (not a simple rectangle)
- When the cutout needs to be constrained to a rectangular region
- For crop previews, mask overlays, and any UI where a shape defines a "visible through" area

## Files Changed

- `MyESModules/App/createCropPreviewRenderer.js` — shaped dark overlay implementation
- `MyESModules/Layout/CropOverlayShape.js` — `beginPathFromPoints` helper
- `MyComponents/CropPreviewTest.html` — 8 new tests for shaped vs rect overlay behavior

## Related

- Skill reference: `building-web-apps/references/canvas-2d.md` — Canvas 2D rendering patterns
- Learning: `2026-07-08-canvas-compositing-and-ui-accessibility.md` — `globalAlpha` blending patterns
- Plan: `_agent_docs/plans/2026-07-12-crop-overlay-swap-all-layouts-plan.md` — Phase 1.1 specification
