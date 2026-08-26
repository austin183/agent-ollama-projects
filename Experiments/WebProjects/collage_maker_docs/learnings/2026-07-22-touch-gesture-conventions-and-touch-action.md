# Touch Gesture Conventions and Selective touch-action

**Date:** 2026-07-22
**Context:** Phase 1 (P0) — Mobile Responsiveness: Touch Gesture Fixes

## Dual Gesture Convention: Direct Manipulation vs. Scrolling

Touch-based gestures (TouchEvent, PointerEvent) and wheel-based gestures (WheelEvent) follow **opposite conventions** for pan direction:

| Input Path | Convention | Delta Sign | User Action → Content Movement |
|------------|-----------|------------|--------------------------------|
| **TouchEvent** (phone touchscreen) | Direct manipulation | Negate | Drag right → content moves right |
| **PointerEvent** (hybrid devices) | Direct manipulation | Negate | Drag right → content moves right |
| **WheelEvent** (macOS trackpad) | Scrolling | No negation | Scroll down → view moves down |

**Implementation pattern:**
```javascript
// TouchEvent / PointerEvent path — negate for direct manipulation
function processGesture(t1, t2) {
    const dx = currentMidpoint.x - initialMidpoint.x;
    const dy = currentMidpoint.y - initialMidpoint.y;
    cropManager.adjustCrop(panelId, {
        x: -dx * imageScale,  // Negated
        y: -dy * imageScale   // Negated
    });
}

// WheelEvent path — no negation (scrolling convention)
function _onWheel(e) {
    cropManager.adjustCrop(panelId, {
        x: e.deltaX * sensitivity * imageScale,  // NOT negated
        y: e.deltaY * sensitivity * imageScale   // NOT negated
    });
}
```

**Why this matters:** On mobile, users expect "drag follows finger" (direct manipulation). On trackpads, users expect scroll-wheel behavior. The same codebase must support both conventions because the browser exposes them as different event types.

**Key insight:** The WheelEvent path (`_onWheel`) never calls `processGesture()` — it computes its own delta inline. This natural separation makes it easy to apply different conventions to each path.

## `touch-action: pan-y` — Selective Gesture Passthrough

The CSS `touch-action` property controls which touch gestures the browser handles natively vs. which are passed to JavaScript:

| Value | Browser Handles | JavaScript Can Intercept |
|-------|----------------|-------------------------|
| `none` | Nothing | Everything (must call preventDefault) |
| `pan-y` | One-finger vertical scroll | Two-finger gestures, horizontal swipes |
| `manipulation` | Scroll and zoom | Nothing (default browser behavior) |

**Use `pan-y` when:**
- You want one-finger vertical drag to scroll the page (not trigger app gestures)
- You still want JavaScript to handle two-finger gestures (pan, pinch-to-zoom)
- You want JavaScript to handle horizontal one-finger swipes (e.g., panel swapping)

**Implementation:**
```css
#previewCanvas {
    touch-action: pan-y;
}
```

**Critical requirement:** Your JavaScript handler MUST call `e.preventDefault()` on `touchmove` when a two-finger gesture is active. Without it, `pan-y` allows the browser to scroll during two-finger drag.

```javascript
// MultiTouchHandler already does this correctly:
function _onTouchMove(e) {
    if (!gestureActive) return;  // One-finger → browser handles (pan-y)
    if (e.touches.length !== 2) { /* cancel */ return; }
    e.preventDefault();  // Two-finger → JavaScript handles, block browser scroll
    processGesture(touches[0], touches[1]);
}
```

**Anti-pattern:** Using `touch-action: none` blocks ALL browser gestures, including page scrolling. On mobile, this makes the app feel "stuck" — users cannot scroll to see content below the fold.

**iOS Safari note:** `pan-y` does NOT prevent the browser's edge-swipe back gesture. Two-finger horizontal swipe from the screen edge may still trigger browser navigation. This is an acceptable trade-off documented in the mobile responsiveness plan.

## Testing Gesture Direction

When testing gesture direction, verify the **sign** of the delta passed to the crop manager:

```javascript
// TouchEvent: drag RIGHT (positive dx) should produce NEGATIVE adjustCrop x
expect(adjustDelta.x).to.be.lessThan(0);

// WheelEvent: scroll RIGHT (positive deltaX) should produce POSITIVE adjustCrop x
expect(adjustDelta.x).to.be.greaterThan(0);
```

**Triangulation pattern:** Test both cardinal directions (right/left, up/down) and diagonal to ensure the negation is applied consistently across axes. Also test the threshold guard — sub-threshold movement should NOT trigger the crop adjustment at all.
