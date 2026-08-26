# Multi-Touch Guard Consistency Across Event Handlers

**Date:** 2026-08-03
**Context:** Title Multi-Touch Intercept Fix — Phase 1 (CR: mobile multitouch title intercept)

## Problem

`TitleInteraction._onPointerDown` had a `_multiTouchGestureActive` guard (line 223), but `_onPointerMove` did not. This allowed the title to be dragged/resized during two-finger pinch-to-zoom or pan gestures when one finger was on the title area.

## Root Cause: Event Race Window

The bug exploits a specific event sequence:

1. **Finger 1 touches title** → `_onPointerDown` runs. `_multiTouchGestureActive` is `false`, so it proceeds. Sets `dragStartCoords`, `interactionType`, and `state.titleInteractionMode`.
2. **Finger 2 touches canvas** → `MultiTouchHandler._onPointerDown` sees `activePointers.size === 2`, calls `startGesture()` which sets `_multiTouchGestureActive = true`.
3. **Fingers move** → `_onPointerMove` receives pointermove events but **had no guard**. It computes delta from `dragStartCoords` to current position, crosses the 3px drag threshold, and activates title drag/resize.

The `_onPointerDown` guard prevents new interactions from starting when a gesture is already active. But it cannot prevent interactions that were **pending** (pointerdown happened, but drag threshold not yet crossed) when the gesture starts.

## Solution: Guard Both Handlers

Every pointer handler that coordinates with `MultiTouchHandler` via `_multiTouchGestureActive` needs guards in **both** `_onPointerDown` AND `_onPointerMove`:

```javascript
// _onPointerDown — prevents new interactions from starting during gesture
_onPointerDown(e) {
    if (state._multiTouchGestureActive) return;
    // ... set pending state (dragStartCoords, interactionType)
}

// _onPointerMove — prevents pending interactions from activating during gesture
_onPointerMove(e) {
    if (state._multiTouchGestureActive) return;
    // ... threshold check, drag/resize, hover feedback
}
```

## Guard Scope Decision

The `_onPointerMove` guard applies to **ALL** pointermove processing, including:
- Drag threshold check
- Active drag/resize application
- **Hover feedback updates** (cursor changes, hover target state)

This is intentional: hover state changes during a gesture cause unnecessary renders and visual flicker. The hover state will be restored when the gesture ends and the next `pointermove` fires (since `_multiTouchGestureActive` will be `false`).

## Checklist for New Handlers

When adding a new pointer event handler that shares a canvas with `MultiTouchHandler`:

- [ ] `_onPointerDown` checks `if (state._multiTouchGestureActive) return;`
- [ ] `_onPointerMove` checks `if (state._multiTouchGestureActive) return;`
- [ ] `_onPointerUp` / `_clearInteractionState` is idempotent (no guard needed — cleanup is always safe)
- [ ] Consider: does pending state from `_onPointerDown` need cleanup when gesture starts? (Phase 2: `cancelPendingInteraction()`)

## Existing Handlers Audit

| Handler | `_onPointerDown` guard | `_onPointerMove` guard |
|---------|----------------------|----------------------|
| `PanelSwap` | Yes (line 362) | Yes (line 395, added 2026-08-01) |
| `TitleInteraction` | Yes (line 223) | Yes (line 322, added 2026-08-03) |

## Related

- `2026-07-08-dual-pointer-handler-coordination.md` — original `_multiTouchGestureActive` flag pattern (documented `_onPointerDown` guards only)
- `2026-08-01-panel-swap-during-multitouch.md` — predecessor plan that added `_onPointerMove` guard to PanelSwap
- `2026-08-02-title-multitouch-intercept-fix.md` — plan that added `_onPointerMove` guard to TitleInteraction
