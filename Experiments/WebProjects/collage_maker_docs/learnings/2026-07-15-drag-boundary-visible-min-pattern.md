# Drag Boundary VISIBLE_MIN Pattern: Preventing Stranded UI

**Date:** 2026-07-15
**Session:** 2026-07-15-003 (Review Fixes Phase 2: Code Quality & UX Polish)

## Summary

Implemented the VISIBLE_MIN drag boundary pattern for the title box interaction. Instead of clamping draggable elements to stay fully within canvas bounds, the pattern allows partial off-canvas visibility with a minimum visible threshold. This prevents the "stranded UI" scenario where a user drags an element completely off-screen with no way to recover it.

---

## The Problem: Stranded UI

When a draggable UI element is clamped to stay fully within its container, users can accidentally drag it to the exact edge where it becomes hard to grab again. Worse, if the clamp allows the element to go fully off-screen (e.g., `Math.max(0, Math.min(x, canvasWidth - elementWidth))`), the user can drag the element past the right edge where its grab handle is no longer accessible.

### Before (old clamping):
```javascript
// Old: element must stay fully within canvas
newX = Math.max(0, Math.min(newX, CANVAS_WIDTH - elementWidth));
```

**Problem:** If the user drags the title box to `x = CANVAS_WIDTH - elementWidth`, the right edge of the box sits exactly at the canvas edge. The resize handle and body grab area are at or beyond the canvas boundary, making it difficult or impossible to re-grab.

---

## The Solution: VISIBLE_MIN Threshold

Allow the element to extend partially off-screen, but require at least `VISIBLE_MIN` pixels to remain visible at all times.

```javascript
const VISIBLE_MIN = 50; // px of box that must remain visible at edges
newX = Math.max(
    -elementWidth + VISIBLE_MIN,
    Math.min(newX, CANVAS_WIDTH - VISIBLE_MIN)
);
```

### How it works:

| Direction | Clamp Formula | Result |
|-----------|--------------|--------|
| **Left edge** | `Math.max(-elementWidth + VISIBLE_MIN, ...)` | Box can extend left up to `VISIBLE_MIN` pixels visible |
| **Right edge** | `Math.min(..., CANVAS_WIDTH - VISIBLE_MIN)` | Box's left edge can go right up to `CANVAS_WIDTH - VISIBLE_MIN` |

### Concrete example (title box width = 400px, canvas = 1920px):

| Before | After (VISIBLE_MIN = 50) |
|--------|-------------------------|
| Left clamp: `x >= 0` | Left clamp: `x >= -350` (50px of 400px box visible) |
| Right clamp: `x <= 1520` (1920-400) | Right clamp: `x <= 1870` (1920-50, 50px visible) |

---

## Why 50px?

The `VISIBLE_MIN = 50` value was chosen as a balance between:
- **Enough to grab:** 50px provides sufficient area for the user to re-acquire the element with mouse or touch
- **Not too much:** Allows meaningful off-screen positioning for creative layouts
- **Consistent with EDGE_THRESHOLD:** The resize handle hit area is 8px (`EDGE_THRESHOLD = 8`), so 50px provides ~6x the minimum grab area

---

## Testing the Pattern

The VISIBLE_MIN pattern is ideal for TDD because it's a pure math function with concrete input/output pairs:

```javascript
// Test: drag left clamped to -boxWidth + VISIBLE_MIN
it('Drag left: clamped to -boxWidth + VISIBLE_MIN', () => {
    // Setup: box at x=100, width=400, drag far left
    // Expected: x = -350 (not -400 or 0)
    expect(lastPosition.x).to.equal(-350);
});

// Test: drag right clamped to canvasWidth - VISIBLE_MIN
it('Drag right: clamped to canvasWidth - VISIBLE_MIN', () => {
    // Setup: box at x=1300, width=400, drag far right
    // Expected: x = 1870 (not 1520)
    expect(lastPosition.x).to.equal(1870);
});

// Test: within bounds — no clamping
it('Drag within bounds: no clamping applied', () => {
    // Setup: box at x=960, drag 100px left
    // Expected: x = 760 (no clamping)
    expect(lastPosition.x).to.equal(760);
});
```

---

## Edge Cases

### Element width < VISIBLE_MIN
If `elementWidth < VISIBLE_MIN` (e.g., a very narrow 30px element), the left clamp becomes `-30 + 50 = 20`. The element is forced to start at x=20, keeping it fully visible. This is correct behavior — small elements don't need partial visibility because they fit entirely on-screen.

### Element width = 0 or negative
Guard against this with a fallback: `const actualWidth = elementWidth ?? 400;`. A zero or negative width would produce nonsensical clamping results.

### Asymmetric axes
The VISIBLE_MIN pattern was applied only to the X-axis in this implementation. The Y-axis uses a different positioning model (baseline-based, not box-edge-based) with its own clamping: `Math.max(fontSize + 12, Math.min(newY, CANVAS_HEIGHT - 12))`. This is intentional — the Y-axis clamp ensures the text baseline stays readable, not that the box stays visible.

---

## When to Use This Pattern

Use VISIBLE_MIN clamping when:
1. **The draggable element has a grab handle** — users need to be able to re-acquire it
2. **The element can be wider/taller than the container** — full containment would restrict positioning
3. **Creative positioning is desired** — users may want elements partially off-screen for artistic layouts
4. **Recovery is impossible otherwise** — if the element goes fully off-screen, there's no way to drag it back

Do NOT use when:
- The element must always be fully visible (e.g., form fields, critical controls)
- The container has scroll/pan behavior (scrolling provides recovery)
- Keyboard navigation is the primary interaction (keyboard focus provides recovery)

---

## File Reference

- `MyESModules/Interaction/TitleInteraction.js` — VISIBLE_MIN in `_onPointerMove` drag handler
- `MyComponents/TitleInteractionTest.html` — Phase 2 drag VISIBLE_MIN clamping tests (2.T.1 through 2.T.4b)
