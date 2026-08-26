# Problem
When I select a panel, and I pinch to zoom or pan with two fingers, if one of my fingers landed on the title, it moves the title in addition to panning and zooming in the selected panel.

# Expected Behavior
I expected the panel to zoom and pan but the title to hold still.

# Root Cause Analysis

## Event Flow
1. **Finger 1 touches title area** → `TitleInteraction._onPointerDown` (line 221) runs. It correctly checks `state._multiTouchGestureActive` (line 223), but it is `false`, so it proceeds. Sets `dragStartCoords`, `interactionType`, and `state.titleInteractionMode`. Does NOT yet set `isInteracting = true` — that waits for the 3px drag threshold.
2. **Finger 2 touches canvas** → `MultiTouchHandler._onPointerDown` (line 214) sees `activePointers.size === 2`, calls `startGesture()` (line 140) which sets `state._multiTouchGestureActive = true` (line 145).
3. **Fingers move** → `TitleInteraction._onPointerMove` (line 318) receives pointermove events but **does NOT check `state._multiTouchGestureActive`**. It computes delta from `dragStartCoords` to current position. Since two fingers in a pinch gesture are typically 50-100px apart, this easily exceeds `DRAG_THRESHOLD = 3` (line 31), so `isInteracting` becomes `true` and the title begins dragging/resizing.

## Code Gap
- `TitleInteraction._onPointerDown` (line 223): **HAS** the guard `if (state._multiTouchGestureActive) return;`
- `TitleInteraction._onPointerMove` (line 318): **MISSING** the same guard

## Files Involved
- `MyESModules/Interaction/TitleInteraction.js` — missing guard in `_onPointerMove`
- `MyESModules/Interaction/MultiTouchHandler.js` — sets `state._multiTouchGestureActive` in `startGesture()` (line 145) and clears it in `endGesture()` (line 204)

# Recommended Fix

## Primary Fix: Add multi-touch guard to `_onPointerMove`
In `MyESModules/Interaction/TitleInteraction.js`, add the same guard at the top of `_onPointerMove` that already exists in `_onPointerDown`:

```javascript
_onPointerMove(e) {
    // Skip if multi-touch gesture is active
    if (state._multiTouchGestureActive) return;

    const canvas = document.getElementById(canvasId);
    // ... rest of method
}
```

## Secondary Fix: Clear pending title state when gesture starts
In `MultiTouchHandler.startGesture()`, after setting `state._multiTouchGestureActive = true`, also clear any pending title interaction state (`dragStartCoords`, `interactionType`) to prevent stale state from lingering if the gesture ends without the title handler ever getting a chance to clean up.

Alternatively, `TitleInteraction._onPointerMove` could reset `dragStartCoords` when it detects `state._multiTouchGestureActive` became true before the drag threshold was crossed.

# Edge Cases to Consider

1. **Single-finger title editing must still work** — the guard only fires during genuine two-finger gestures; single-finger drag/resize of the title box must be unaffected.
2. **Title movable when NOT in multi-touch mode** — single-finger drag-to-move and edge-drag-to-resize must continue working as expected.
3. **Pointer capture release on gesture end** — when `MultiTouchHandler.endGesture()` clears `state._multiTouchGestureActive`, ensure `TitleInteraction` properly clears its pending state.
4. **Trackpad wheel events** — `MultiTouchHandler._onWheel` does NOT set `state._multiTouchGestureActive`. If the cursor was over the title when a trackpad pinch occurs, title interaction state could still be stale. However, `_onWheel` doesn't produce pointermove events, so this path is not triggered.
5. **Race condition** — if finger 1's `pointerdown` on title fires before finger 2's `pointerdown` triggers the multi-touch guard, the guard in `_onPointerMove` handles this by preventing the drag from activating.

# Accessibility Considerations

- **Touch target sizing** — `EDGE_THRESHOLD_COARSE = 22px` for touch (WCAG 44px target / 2) must remain unchanged.
- **Reduced motion** — users with reduced motion preferences should not experience unexpected title movements during zoom/pan gestures. The fix aligns with this expectation.
- **Keyboard/screen reader** — this bug only affects touch/pointer events; keyboard-only users are unaffected.

# UX Severity: Medium-High

- **Frustrating & confusing** — breaks user mental model of two-finger gestures (should only affect image crop/zoom).
- **State corruption risk** — user may unintentionally reposition the title box, requiring extra undo steps.
- **Mobile impact amplified** — lower finger precision on small screens makes this bug more frequent.
