# Dual Pointer Handler Coordination

**Date:** 2026-07-08 (updated 2026-07-12)
**Context:** Phase 3 — Hexagonal Panel Drag-and-Drop (CR-04c), Phase 2 — Swap in All Layouts

## Problem

When two pointer event handlers (GestureHandler for panel selection/hover, PanelSwapHandler for drag-and-drop swap) both attach listeners to the same canvas, pointer events fire on both handlers simultaneously. This causes:
- Double panel selection on click
- Conflicting drag/click interpretation
- Unexpected state mutations

## Evolution of Solutions

### Phase 1: Layout-Gated Delegation (deprecated)

The original approach used layout-specific guards:

```javascript
// GestureHandler — general-purpose, skips hexagonal layout
_onPointerDown(e) {
    if (state.layoutStyle === LayoutStyle.HEXAGONAL) return;
    // ... rest of handler
}

// HexDragHandler — hex-specific, skips non-hexagonal layouts
_onPointerDown(e) {
    if (state.layoutStyle !== LayoutStyle.HEXAGONAL) return;
    // ... hex-specific handling
}
```

**Limitation:** This pattern requires a layout check in every handler. Adding a new layout-specific interaction means editing every existing handler to add a new guard. Violates OCP.

### Phase 2: Gesture-Active Flag Coordination (current)

The current approach uses a shared state flag to coordinate between handlers:

```javascript
// PanelSwapHandler — always active for all layouts, skips if multi-touch gesture active
_onPointerDown(e) {
    if (state._multiTouchGestureActive) return;
    // ... panel swap handling (works in all layouts)
}

// MultiTouchHandler — sets flag on gesture start/end
function startGesture(t1, t2) {
    gestureActive = true;
    state._multiTouchGestureActive = true;  // Signal to swap handler
    // ...
}

function endGesture() {
    gestureActive = false;
    state._multiTouchGestureActive = false;  // Clear signal
    // ...
}
```

**GestureHandler no longer handles pointerdown** — the swap handler's `_onPointerUp` handles click-to-select. GestureHandler provides hover-only (pointermove/pointerleave).

## Key Design Decisions

1. **PanelSwapHandler is always active** — no layout check needed. The `_multiTouchGestureActive` guard is O(1) and happens at pointerdown time.

2. **Drag threshold distinguishes click from drag** — 10 CSS pixels of movement triggers drag mode. Below threshold, the interaction is treated as a click.

3. **Both handlers share the same canvas** — no need to detach/reattach on layout change.

4. **Flag cleared on every exit path** — gesture end, pointer cancel, window blur, visibility change, and detach. This prevents the flag from persisting and blocking swap interactions.

## Pointer Capture in Swap Handler

The swap handler uses `setPointerCapture` to ensure pointer events remain bound to the canvas even when the user drags outside canvas bounds:

```javascript
_onPointerDown(e) {
    if (state._multiTouchGestureActive) return;
    const canvas = document.getElementById(canvasId);
    if (!canvas) return;

    // Capture pointer so events continue if cursor leaves canvas bounds
    if (canvas.setPointerCapture) {
        try {
            canvas.setPointerCapture(e.pointerId);
            this._capturedPointerId = e.pointerId;
        } catch (_) {}
    }
    // ... hit test and record drag start
}

_clearDragState() {
    const canvas = document.getElementById(canvasId);
    if (canvas && canvas.releasePointerCapture && this._capturedPointerId !== undefined) {
        try { canvas.releasePointerCapture(this._capturedPointerId); } catch (_) {}
        this._capturedPointerId = undefined;
    }
    // ... clear drag state
}
```

## Gotchas

- **Flag must be cleared on detach** — if the handler is detached while a gesture is active, the flag persists on state and blocks subsequent swap interactions. Always clear in `detach()`.

- **Drag threshold is in CSS pixels** — on high-DPR displays, the threshold feels the same regardless of physical pixel density because CSS pixels are device-independent.

- **Panel geometry type matters** — the hit test handles both `rect` and `path` geometries via `geometry.type === 'rect'` check.

- **pointercancel handling** — the swap handler maps `pointercancel` to the same handler as `pointerup` to handle iOS Safari system gesture interruptions.

## When to Use This Pattern

Use gesture-active flag coordination when:
- Multiple handlers need to interact with the same DOM element
- One handler is gesture-specific (multi-touch pan/zoom) and another is general-purpose (click/drag)
- You want to avoid layout-specific guards that violate OCP
- You need clean coordination without attach/detach cycles
