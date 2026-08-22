# Self-Calibrating Hit Test Coordinates

## Problem

When testing pointer interactions on elements with **computed layout** (auto-fit widths, dynamic positioning), hardcoding hit test coordinates breaks across browser environments because text measurement (`ctx.measureText()`) varies by font renderer, DPR, and platform.

## Example

Testing title resize interaction where the title box uses auto-fit width:

```javascript
// BAD — hardcoded coordinates break across environments
canvas.dispatchEvent(new PointerEvent('pointerdown', {
    clientX: 533, clientY: 456, // Assumes "Hello World" measures exactly 200px
    button: 0, bubbles: true
}));
```

## Solution

Use the same computation function (`computeBounds`) to derive test coordinates. This makes the test self-calibrating to the actual measurement in the test environment:

```javascript
// GOOD — coordinates derived from actual measurement
const bounds = computeBounds(titleStyle, runs, 1920, 1080);
const cssBoxRight = 250 + bounds.boxWidth / 2;
const hitX = cssBoxRight - 3; // 3px inside right edge

canvas.dispatchEvent(new PointerEvent('pointerdown', {
    clientX: hitX, clientY: 441,
    button: 0, bubbles: true
}));
```

## Key Insight

The test imports `computeBounds` from the production module and calls it with the same parameters the interaction handler uses internally. This ensures the test coordinates match whatever the production code computes, regardless of font rendering differences.

## When to Use

- Testing hit testing on elements with computed/auto-fit dimensions
- Testing pointer interactions where the target position depends on text measurement
- Any interaction test where the bounding box is computed at runtime rather than fixed

## Related

- `TitleInteractionTest.html` — Phase 2 auto-fit resize tests
- `computeBounds()` in `TitleRenderer.js` — pure function for title bounds computation
