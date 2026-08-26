# Canvas 2D vs CoreGraphics Mapping

**Date:** 2026-07-01
**Sessions:** 3-4 (Phase 1-2 implementation)

## Summary

The CoreGraphics rendering pipeline from the macOS app maps cleanly to Canvas 2D. The key pattern: `CGContext` operations translate 1:1 to `CanvasRenderingContext2D` methods.

## Mapping

| CoreGraphics | Canvas 2D | Notes |
|-------------|-----------|-------|
| `CGContext` | `CanvasRenderingContext2D` | Get via `canvas.getContext('2D')` |
| `CGContextClearRect` | `ctx.clearRect()` | Same parameters |
| `CGContextSetFillColor` | `ctx.fillStyle` | Property, not function |
| `CGContextFillRect` | `ctx.fillRect()` | Same parameters |
| `CGContextDrawImage` | `ctx.drawImage()` | Different param order |
| `CGContextBeginPath` | `ctx.beginPath()` | Same concept |
| `CGContextMoveTo` | `ctx.moveTo()` | Same parameters |
| `CGContextAddLineToPoint` | `ctx.lineTo()` | Same parameters |
| `CGContextClosePath` | `ctx.closePath()` | Same concept |
| `CGContextClip` | `ctx.clip()` | Same concept |
| `CGContextSetShadow` | `ctx.shadow*` properties | Split into 4 properties |
| `CGContextSetStrokeColor` | `ctx.strokeStyle` | Property, not function |
| `CGContextStrokePath` | `ctx.stroke()` | No path parameter |
| `CGContextSaveGState` | `ctx.save()` | Same concept |
| `CGContextRestoreGState` | `ctx.restore()` | Same concept |
| `CGContextScaleCTM` | `ctx.scale()` | Same parameters |
| `CGContextTranslateCTM` | `ctx.translate()` | Same parameters |
| `CGContextSetBlendMode` | `ctx.globalCompositeOperation` | Different value names |
| `CGContextSetAlpha` | `ctx.globalAlpha` | Property, not function |

## Key Differences

### Shadow Rendering
CoreGraphics uses a single `setShadow` call. Canvas 2D requires 4 separate properties:
```javascript
ctx.shadowColor = 'rgba(0, 0, 0, 0.3)';
ctx.shadowBlur = 8;
ctx.shadowOffsetX = 0;
ctx.shadowOffsetY = 2;
```

### DrawImage Parameter Order
CoreGraphics: `CGContextDrawImage(context, rect, image)`
Canvas 2D: `ctx.drawImage(image, sx, sy, sw, sh, dx, dy, dw, dh)`

### Blend Mode Names
CoreGraphics `CGBlendMode` values don't match Canvas 2D `globalCompositeOperation` values. For example:
- CoreGraphics: `kCGBlendModeMultiply`
- Canvas 2D: `'multiply'`

## Canvas Lifecycle Pattern

The project follows the Midiestro `ThreeJSRenderer` lifecycle pattern:

```javascript
createCanvasRenderer(canvasId) {
  init({ width, height })   // Get canvas, context, set size
  resize(width, height)     // Update dimensions with DPR scaling
  scheduleRender(drawFn)    // Debounced render via requestAnimationFrame
  render(drawFn)            // Immediate render
  dispose()                 // Cancel pending renders, null references
}
```

## DPR Scaling

Canvas 2D requires manual DPR (device pixel ratio) scaling for sharp rendering on Retina displays:

```javascript
const dpr = window.devicePixelRatio || 1;
canvas.width = width * dpr;
canvas.height = height * dpr;
canvas.style.width = width + 'px';
canvas.style.height = height + 'px';
ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
```

Without this, canvas content appears blurry on high-DPI displays.

## Gotchas

1. **Canvas coordinates are always in CSS pixels after DPR transform** — `ctx.setTransform(dpr, ...)` means you draw in CSS pixel coordinates, not physical pixels
2. **`ctx.save()`/`ctx.restore()` is stack-based** — like CoreGraphics GState, but easier to forget to restore
3. **Path clipping is persistent** — once `ctx.clip()` is called, all subsequent drawing is clipped until `ctx.restore()` or a new clipping path
4. **`drawImage` with source rect** — the 9-parameter form `drawImage(img, sx, sy, sw, sh, dx, dy, dw, dh)` is the workhorse for cropped image rendering
