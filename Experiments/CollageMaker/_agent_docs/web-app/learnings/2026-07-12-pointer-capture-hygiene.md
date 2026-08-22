# Pointer Capture Release Hygiene

**Date:** 2026-07-12
**Context:** Pre-Merge Review Fixes — Phase 3: Pointer Capture Hygiene (Issues #5, #6)

## Problem

When using `setPointerCapture()` to keep pointer events flowing even when the cursor leaves canvas bounds, failing to call `releasePointerCapture()` leaves stale capture state. This can cause subsequent clicks to be routed to the wrong element or behave unexpectedly.

## The Full Capture Lifecycle

Pointer capture has a symmetric lifecycle: capture at `pointerdown`, release at `pointerup`/`pointercancel`. Both sides must be handled.

### Capture: Each pointer independently on pointerdown

```javascript
function _onPointerDown(e) {
    if (e.pointerType === 'touch') return;

    activePointers.set(e.pointerId, { clientX: e.clientX, clientY: e.clientY });

    // Capture this pointer so events continue if cursor leaves canvas bounds.
    // Each pointer is captured at its own pointerdown event.
    if (canvas && canvas.setPointerCapture) {
        try {
            canvas.setPointerCapture(e.pointerId);
        } catch (_) { /* not all browsers support */ }
    }

    if (activePointers.size === 2) {
        // ... start gesture
    }
}
```

**Key:** Do NOT wait until `activePointers.size === 2` to capture. The first pointer needs capture too — if it drags off-canvas before the second pointer arrives, it loses events.

### Release: pointerup — release current pointer + remaining pointers on gesture end

```javascript
function _onPointerUp(e) {
    if (e.pointerType === 'touch') return;

    // Release capture for this pointer
    if (canvas && canvas.releasePointerCapture) {
        try { canvas.releasePointerCapture(e.pointerId); } catch (_) {}
    }

    activePointers.delete(e.pointerId);

    if (activePointers.size < 2) {
        if (gestureActive) {
            endGesture();
        }
        pointerGestureActive = false;
        // Release capture for any remaining pointer
        if (canvas && canvas.releasePointerCapture) {
            for (const pid of activePointers.keys()) {
                try { canvas.releasePointerCapture(pid); } catch (_) {}
            }
        }
        activePointers.clear();
    }
}
```

**Key ordering:** `activePointers.delete(e.pointerId)` MUST happen BEFORE the release loop. Otherwise the cancelled pointer appears in the loop and gets released twice (harmless due to try/catch, but inconsistent).

### Release: pointercancel — release all captures

```javascript
function _onPointerCancel(e) {
    if (e.pointerType === 'touch') return;

    // Release capture for this pointer
    if (canvas && canvas.releasePointerCapture) {
        try { canvas.releasePointerCapture(e.pointerId); } catch (_) {}
    }

    activePointers.delete(e.pointerId);

    if (gestureActive) {
        endGesture();
    }
    pointerGestureActive = false;
    // Release capture for any remaining pointers
    if (canvas && canvas.releasePointerCapture) {
        for (const pid of activePointers.keys()) {
            try { canvas.releasePointerCapture(pid); } catch (_) {}
        }
    }
    activePointers.clear();
}
```

## Gotchas

### 1. Browser auto-release is not reliable

The browser will auto-release pointer captures when the element loses focus or the page unloads. However, during normal interaction (e.g., user lifts one finger of a two-finger gesture), the browser does NOT auto-release the remaining capture. You must call `releasePointerCapture` explicitly.

### 2. releasePointerCapture throws on invalid states

Calling `releasePointerCapture` for a pointer that was never captured, already released, or whose capture was auto-released will throw a `DOMException`. Always wrap in try/catch — these are non-fatal hygiene operations.

### 3. Feature detection is required

Not all browsers support pointer capture. Always check for method existence before calling:
```javascript
if (canvas && canvas.releasePointerCapture) {
    try { canvas.releasePointerCapture(e.pointerId); } catch (_) {}
}
```

### 4. The release loop must iterate over activePointers, not captured IDs

When releasing remaining captures on gesture end, iterate over `activePointers.keys()` (the tracking data structure), not a separate list of captured pointer IDs. This ensures the loop only sees pointers that are still tracked, and `activePointers.delete(e.pointerId)` before the loop prevents double-release.

## Testing Pattern

Test capture and release by overriding the canvas methods:

```javascript
let capturedIds = [];
let releasedIds = [];
canvas.setPointerCapture = (pid) => { capturedIds.push(pid); };
canvas.releasePointerCapture = (pid) => { releasedIds.push(pid); };

// Fire pointerdown events
canvas.dispatchEvent(new PointerEvent('pointerdown', { pointerId: 1, ... }));
canvas.dispatchEvent(new PointerEvent('pointerdown', { pointerId: 2, ... }));

expect(capturedIds).to.include(1);
expect(capturedIds).to.include(2);

// Fire pointerup
canvas.dispatchEvent(new PointerEvent('pointerup', { pointerId: 1, ... }));

expect(releasedIds).to.include(1);
expect(releasedIds).to.include(2); // Remaining pointer also released
```

## When to Use This Pattern

Use explicit pointer capture release when:
- You capture pointers in a multi-pointer gesture handler
- The gesture can end before all pointers are released (e.g., one finger lifted)
- You need clean state for subsequent interactions
