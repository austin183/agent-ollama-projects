# Multi-Finger Trackpad Gestures

The multi-touch handler (`MultiTouchHandler.js`) currently uses `TouchEvent` (`touchstart`/`touchmove`/`touchend`), which only fires on touchscreens. Multi-finger gestures on trackpads (e.g., MacBook two-finger drag, pinch-to-zoom) are surfaced as `PointerEvent`, not `TouchEvent`, so they are not intercepted.

## Goal

Enable two-finger pan and pinch-to-zoom on the main preview canvas for both touchscreens **and** multi-finger trackpads.

## Approach

Extend `MultiTouchHandler` to track active pointers via `PointerEvent`:

- Maintain a `Map<pointerId, { clientX, clientY }>` of active pointers
- On `pointerdown`: add pointer to map; if 2 pointers active, begin gesture
- On `pointermove`: recompute midpoint/distance from map entries; dispatch pan/zoom
- On `pointerup`/`pointercancel`: remove pointer from map; if < 2 remain, end gesture

The existing pure math functions (`computeTouchMidpoint`, `computeTouchDistance`, `computePinchScale`) work unchanged — they operate on `{ clientX, clientY }` objects, not Touch-specific APIs.

**Reuse:** The TouchEvent path can coexist alongside the PointerEvent path. The handler activates on whichever event type arrives first with 2 active inputs.

## Testing

Add pointer-event-based tests to `MyComponents/MultiTouchHandlerTest.html` using `new PointerEvent()` with `pointerType: 'touch'` or `'mouse'`.
