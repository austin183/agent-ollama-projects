# Multi-Touch Gesture Testing and Implementation Patterns

**Date:** 2026-07-08
**Context:** Phase 4 — CR-06 Multi-Touch Gestures (two-finger pan, pinch-to-zoom)

## TouchEvent Cannot Be Constructed with Mock Touch Objects

The browser's `TouchEvent` constructor requires real `Touch` objects for `touches`, `targetTouches`, and `changedTouches` properties. `Touch` instances cannot be created from JavaScript (the `Touch` constructor is not exposed).

**Failed approach:**
```javascript
// TypeError: Failed to convert value to 'Touch'
const evt = new TouchEvent('touchstart', {
    touches: [{ identifier: 1, clientX: 100, clientY: 100 }],
    targetTouches: [{ identifier: 1, clientX: 100, clientY: 100 }],
    changedTouches: [{ identifier: 1, clientX: 100, clientY: 100 }]
});
```

**Working approach — Object.defineProperty:**
```javascript
function createMockTouchEvent(type, { touches, targetTouches, changedTouches } = {}) {
    const evt = new Event(type, { bubbles: true, cancelable: true });
    const props = {};
    if (touches) props.touches = touches;
    if (targetTouches) props.targetTouches = targetTouches;
    if (changedTouches) props.changedTouches = changedTouches;

    for (const [key, value] of Object.entries(props)) {
        Object.defineProperty(evt, key, {
            get: () => value,
            configurable: true
        });
    }
    return evt;
}
```

**Key rules:**
1. Create a plain `Event` first (not `TouchEvent`)
2. Use `Object.defineProperty` with a `get` trap to set touch properties
3. Mark properties as `configurable: true` to allow the browser to override if needed
4. The mock TouchList needs `length`, indexed access (`list[0]`), `item(i)`, and `Symbol.iterator`

## TouchList Mock Requirements

A mock TouchList must satisfy multiple access patterns:
```javascript
function makeTouchList(touches) {
    const list = {
        length: touches.length,
        item: (i) => touches[i] || null
    };
    for (let i = 0; i < touches.length; i++) {
        list[i] = touches[i];
    }
    list[Symbol.iterator] = function* () {
        for (let i = 0; i < this.length; i++) {
            yield this[i];
        }
    };
    return list;
}
```

**Why all three access patterns?** Different code paths access TouchLists differently:
- `e.touches.length` — needs `length` property
- `e.touches[i]` — needs indexed access
- `e.touches.item(i)` — needs `item()` method
- `for (const t of e.touches)` — needs `Symbol.iterator`

## Multi-Touch: Exactly 2 Fingers, Not 2+

Mobile OSes reserve 3-finger and 4-finger gestures for system navigation:
- **iOS Safari:** 3-finger swipe for back/forward and app switcher
- **Android Chrome:** 3-finger swipe for split-screen and recent apps

**Anti-pattern:**
```javascript
// Activates on 3+ fingers — may conflict with OS gestures
if (e.touches.length < 2) return;
```

**Correct:**
```javascript
// Exactly 2 fingers only
if (e.touches.length !== 2) return;
```

Additionally, cancel the gesture if a 3rd finger appears mid-gesture:
```javascript
_onTouchMove(e) {
    if (!gestureActive) return;
    if (e.touches.length !== 2) {
        // Cancel gesture — 3rd finger added or 1st lifted
        gestureActive = false;
        return;
    }
    // ... gesture processing
}
```

## removeEventListener Must Match addEventListener Options

When event listeners are added with `{ passive: false }`, they must be removed with the same options. Without matching options, `removeEventListener` silently fails, causing memory leaks.

```javascript
// Attach
canvas.addEventListener('touchstart', handler, { passive: false });

// Detach — MUST include { passive: false }
canvas.removeEventListener('touchstart', handler, { passive: false });
```

This is the same pattern documented for pointer event handlers (`2026-07-08-dual-pointer-handler-coordination.md`), but applies equally to touch events.

## Consolidate Render Calls in Gesture Handlers

When a single `touchmove` event can trigger both pan and zoom operations, calling `onCropPreviewRender()` after each creates unnecessary double rendering. Use a flag to consolidate:

```javascript
let needsRender = false;

if (panThresholdExceeded) {
    cropManager.adjustCrop(panelId, delta);
    needsRender = true;
}

if (zoomThresholdExceeded) {
    cropManager.zoomCrop(panelId, factor);
    needsRender = true;
}

if (needsRender) {
    onCropPreviewRender(); // Called at most once per touchmove
}
```

## Incremental Pinch Scale Factor

The raw pinch distance ratio (e.g., 2.0 for doubling the distance) is too aggressive for a single `zoomCrop()` call. Apply a root to convert to a small incremental factor:

```javascript
const scaleRatio = currentDistance / initialDistance; // e.g., 2.0
const factor = Math.pow(scaleRatio, 0.15); // e.g., 2.0^0.15 ≈ 1.12
cropManager.zoomCrop(panelId, factor);
```

The exponent `0.15` was chosen empirically to produce smooth, responsive zooming without overshooting. After each successful zoom, reset the initial distance to avoid accumulating scale.
