# Layout Math Porting: Swift → JavaScript

**Date:** 2026-07-01
**Session:** 3 (Phase 1 implementation)

## Summary

Porting the layout math from Swift `LayoutGenerator.swift` to JavaScript was straightforward because the math is pure computation with zero platform dependencies. The key insight: Swift `CGSize`/`CGRect` map directly to plain JS objects `{ width, height }` and `{ x, y, width, height }`.

## Patterns

### Swift → JS Type Mapping

| Swift | JavaScript | Notes |
|-------|-----------|-------|
| `CGSize` | `{ width: Number, height: Number }` | Plain object, no constructor |
| `CGRect` | `{ x: Number, y: Number, width: Number, height: Number }` | Plain object |
| `CGPoint` | `{ x: Number, y: Number }` | Plain object |
| `CGFloat` | `Number` | JS Numbers are doubles |
| `enum LayoutStyle` | `const LayoutStyle = { UNIFORM: 'uniform', ... }` | Object literal |

### Layout Strategies Are Pure Functions

All 5 layout strategies (`UniformLayout`, `HeroLayout`, `MosaicLayout`, `DiagonalSlicesLayout`, `HexagonalLayout`) are pure functions:
- Input: `{ numImages, canvasSize, gutter, imageOrder, ... }`
- Output: `Array<ImagePanel>`
- No side effects, no platform dependencies

This means they can be tested in complete isolation and are trivially portable between platforms.

### PanelGeometry Uses Tagged Union

JavaScript doesn't have Swift's `enum` with associated values, so `PanelGeometry` uses a tagged union:

```javascript
// Rect geometry
{ type: 'rect', rect: { x, y, width, height } }

// Path geometry (for diagonal slices, hexagonal)
{ type: 'path', points: [[x,y], ...], boundingRect: { x, y, width, height } }
```

The `geometryBoundingRect()` function extracts the bounding rect from either type.

## Gotchas

1. **Swift `max(3, min(numImages, 3))` → JS `Math.max(3, Math.min(numImages, 3))`** — same logic, different syntax
2. **Swift `CGFloat` precision** — JavaScript `Number` is always double-precision, so no precision loss
3. **Swift `enum` raw values** — use JS object literals with string values for persistence compatibility
