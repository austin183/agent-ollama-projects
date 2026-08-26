# PointerEvent Trackpad Gestures and Dual-Input Path Patterns

**Date:** 2026-07-11
**Context:** Phase 4 Follow-Up — CR-FU-02 Multi-Finger Trackpad Gestures (PointerEvent)

## PointerEvent pointerType Guard Prevents Double-Firing on Hybrid Devices

On devices with both touchscreens and trackpads (e.g., Surface Pro, iPad with Magic Trackpad), the browser fires **both** TouchEvents and PointerEvents for touch input. If a handler processes both, every gesture fires twice.

**The guard:**
```javascript
function _onPointerDown(e) {
    // Skip touch pointers — delegate to TouchEvent path
    if (e.pointerType === 'touch') return;
    // ... handle mouse/pen pointers
}
```

**PointerType values:**
- `'mouse'` — mouse or trackpad pointer
- `'touch'` — touchscreen contact
- `'pen'` — stylus/pen

**Key insight:** The PointerEvent path handles `'mouse'` and `'pen'` pointers (trackpad gestures), while the TouchEvent path handles `'touch'` pointers (touchscreen). The guard in the PointerEvent handler ensures no overlap.

**Anti-pattern:** Using `pointerType !== 'touch'` to gate the TouchEvent path. The TouchEvent path has no `pointerType` property — it simply fires for all touch input. The guard belongs only in the PointerEvent handler.

## setPointerCapture Only Works for the Current Pointer

`canvas.setPointerCapture(pointerId)` only succeeds for the pointer that fired the current event. Attempting to capture a different pointer's ID during a different pointer's event silently throws.

**Anti-pattern — trying to capture all pointers at once:**
```javascript
// BUG: setPointerCapture(pid) throws for the first pointer's ID
// because this code runs during the SECOND pointer's pointerdown event
if (activePointers.size === 2) {
    for (const pid of activePointers.keys()) {
        canvas.setPointerCapture(pid);
    }
}
```

**Correct — only capture the current pointer:**
```javascript
if (activePointers.size === 2) {
    try {
        canvas.setPointerCapture(e.pointerId); // Only the current pointer
    } catch (_) { /* not supported */ }
}
```

**If you need both pointers captured:** Capture the first one during its own `pointerdown`, and the second one during its `pointerdown`. For the wheel event path (macOS trackpad), pointer capture is irrelevant since wheel events don't use pointer IDs.

**Gotcha:** `setPointerCapture` may throw on some browsers. Always wrap in try/catch.

## Window Blur and Visibility Change as Gesture Safety Net

If the user switches tabs, minimizes the browser, or the window loses focus during an active gesture, the browser may pause or silently cancel pointer/touch events. The gesture state (`gestureActive`, `activePointers`) remains set, causing subsequent interactions to be misinterpreted.

**Safety net pattern:**
```javascript
// In attach():
const handleBlur = () => {
    if (gestureActive || pointerGestureActive) {
        endGesture();
        pointerGestureActive = false;
        activePointers.clear();
    }
};
window.addEventListener('blur', handleBlur);
document.addEventListener('visibilitychange', () => {
    if (document.hidden) handleBlur();
});

// In detach():
window.removeEventListener('blur', handleBlur);
document.removeEventListener('visibilitychange', handleVisibilityChange);
```

**Why both `blur` and `visibilitychange`?**
- `blur` fires when the window loses focus (clicking another window, Alt+Tab)
- `visibilitychange` fires when the tab is hidden (switching tabs, minimizing)
- Some browsers may fire one but not the other depending on the trigger

**Key rule:** Always guard the cleanup with a state check (`if (gestureActive)`) to avoid unnecessary work on every blur event.

## Unified Gesture Functions Across Input Paths

When a handler supports multiple input paths (TouchEvent + PointerEvent), extract shared gesture logic into functions that both paths call. This eliminates duplication and ensures consistent behavior.

**Pattern:**
```javascript
// Shared functions (called by both paths)
function startGesture(t1, t2) {
    if (!state.selectedPanelId) return false;
    gestureActive = true;
    initialMidpoint = computeTouchMidpoint(t1, t2);
    initialDistance = computeTouchDistance(t1, t2);
    return true;
}

function processGesture(t1, t2) {
    if (!gestureActive) return;
    // ... pan and zoom logic
}

function endGesture() {
    gestureActive = false;
    initialMidpoint = null;
    initialDistance = 0;
    onRenderScheduled();
}

// TouchEvent path
function _onTouchStart(e) {
    if (e.touches.length !== 2) return;
    if (startGesture(e.touches[0], e.touches[1])) {
        e.preventDefault();
    }
}

// PointerEvent path
function _onPointerDown(e) {
    if (e.pointerType === 'touch') return;
    activePointers.set(e.pointerId, { clientX: e.clientX, clientY: e.clientY });
    if (activePointers.size === 2) {
        const pointers = [...activePointers.values()];
        if (startGesture(pointers[0], pointers[1])) {
            e.preventDefault();
        }
    }
}
```

**Benefits:**
- Both paths use identical gesture math and state management
- Adding a third input path (e.g., keyboard-driven gestures) only requires wiring to the shared functions
- Testing the shared functions in isolation is straightforward

## preventDefault After Gesture Check, Not Before

For gesture handlers that conditionally activate (e.g., only when a panel is selected), call `preventDefault()` **after** confirming the gesture should activate, not before.

**Anti-pattern:**
```javascript
function _onTouchStart(e) {
    if (e.touches.length !== 2) return;
    e.preventDefault(); // Called even when no panel is selected
    if (startGesture(e.touches[0], e.touches[1])) {
        // ...
    }
}
```

When no panel is selected, `preventDefault()` still fires — blocking browser defaults like page scrolling.

**Correct:**
```javascript
function _onTouchStart(e) {
    if (e.touches.length !== 2) return;
    if (startGesture(e.touches[0], e.touches[1])) {
        e.preventDefault(); // Only suppress when gesture activates
    }
}
```

This pattern applies equally to TouchEvent and PointerEvent paths.

## touch-action: none for Custom Gesture Canvases

When implementing custom multi-touch or pointer gestures on a canvas element, add `touch-action: none` to prevent the browser from handling default gestures (scroll, zoom, double-tap zoom).

```css
#previewCanvas {
    touch-action: none;
}
```

**Without this CSS property:**
- Two-finger drag on trackpad scrolls the page instead of panning the image
- Pinch gesture on touchscreen zooms the page instead of zooming the image
- The browser consumes the events before your handlers see them

**Accessibility consideration:** `touch-action: none` disables all default touch gestures. Ensure users have alternative input methods (mouse, keyboard) for any functionality that relies on gestures.

## macOS Trackpad Gestures Are Wheel Events, Not PointerEvents

**Critical discovery:** On macOS, two-finger trackpad gestures are **not** delivered as two separate `pointerdown` events with different `pointerId` values. The browser synthesizes them as a single `wheel` event:

| Gesture | Wheel event property |
|---------|---------------------|
| Two-finger drag (pan) | `deltaY` (vertical), `deltaX` (horizontal) |
| Pinch-to-zoom | `deltaZ` |

**The anti-pattern that caused the bug:**
```javascript
// This NEVER activates on macOS trackpad
function _onPointerDown(e) {
    activePointers.set(e.pointerId, { clientX: e.clientX, clientY: e.clientY });
    if (activePointers.size === 2) {
        // macOS trackpad only ever fires ONE pointerdown, not two
        startGesture(...); // Never reached
    }
}
```

**The fix — add a wheel event handler:**
```javascript
function _onWheel(e) {
    const panelId = state.selectedPanelId;
    if (!panelId) return;
    e.preventDefault();

    // Pan: two-finger drag
    if (e.deltaY !== 0 || e.deltaX !== 0) {
        cropManager.adjustCrop(panelId, {
            x: e.deltaX * sensitivity * imageScale,
            y: e.deltaY * sensitivity * imageScale
        });
    }

    // Zoom: pinch-to-zoom
    if (e.deltaZ !== 0) {
        const factor = Math.exp(-e.deltaZ * zoomSensitivity);
        cropManager.zoomCrop(panelId, factor);
    }
}
```

**Key details:**
- `deltaZ` is negative for pinch-open (zoom in), positive for pinch-close (zoom out)
- `deltaY`/`deltaX` direction depends on browser/platform — **always test manually and be prepared to flip signs**
- Use `{ passive: false }` when attaching the wheel listener, otherwise `preventDefault()` is silently ignored
- Wheel events fire at high frequency during gestures — ensure your crop/render pipeline is efficient

**Why this matters:** The PointerEvent path (two `pointerdown` events) works for some platforms (Windows precision touchpads, some Linux setups) but **not macOS**. The wheel event path is the universal solution for trackpad gestures.

## setPointerCapture Only Works for the Current Pointer

`canvas.setPointerCapture(pointerId)` only succeeds for the pointer that fired the current event. Attempting to capture a different pointer's ID during a different pointer's event silently throws.

**Anti-pattern — trying to capture all pointers at once:**
```javascript
// BUG: setPointerCapture(pid) throws for the first pointer's ID
// because this code runs during the SECOND pointer's pointerdown event
for (const pid of activePointers.keys()) {
    canvas.setPointerCapture(pid);
}
```

**Correct — only capture the current pointer:**
```javascript
try {
    canvas.setPointerCapture(e.pointerId); // Only the current pointer
} catch (_) { /* not supported */ }
```

**Practical impact:** If you need both pointers captured, capture the first one during its own `pointerdown`, and the second one during its `pointerdown`. For the wheel event path, pointer capture is irrelevant since wheel events don't use pointer IDs.

## Wheel Event Sensitivity Requires Empirical Tuning

Wheel event deltas are platform-dependent and vary by device. Hardcoded sensitivity constants must be tuned by manual testing on real hardware.

**Pattern:**
```javascript
const WHEEL_PAN_SENSITIVITY = 2;     // CSS pixels per wheel delta unit
const WHEEL_ZOOM_SENSITIVITY = 0.005; // Exponential factor per deltaZ unit
```

**Tuning tips:**
- Start conservative — it's easier to increase sensitivity than decrease it
- Pan sensitivity should feel 1:1 with finger movement
- Zoom uses `Math.exp(-deltaZ * sensitivity)` for smooth exponential scaling
- Test on the target platform (macOS trackpad deltas differ from Windows touchpad)
