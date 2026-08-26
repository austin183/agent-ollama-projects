# PointerEvents Migration and touch-action: none Trade-off

**Date:** 2026-07-30
**Context:** Phase 1 of Mobile Touch Enhancements — PointerEvents Migration

## 1. Pointer Capture Leak on Failed Gesture Start

**Problem:** When `setPointerCapture()` is called on every `pointerdown`, but the gesture fails to start (e.g., no selected panel), the capture is never released. This leaves stale pointer capture state on the canvas.

**Root cause:** The `_onPointerDown` handler captures the pointer immediately (before knowing if the gesture will start), but only releases capture in `_onPointerUp`/`_onPointerCancel`. If `startGesture()` returns false and the handler returns early, those release paths are never reached.

**Fix:** Release capture in the same handler when the gesture fails to start:

```javascript
function _onPointerDown(e) {
    activePointers.set(e.pointerId, { clientX: e.clientX, clientY: e.clientY });

    if (canvas && canvas.setPointerCapture) {
        try { canvas.setPointerCapture(e.pointerId); } catch (_) {}
    }

    if (activePointers.size === 2) {
        const pointers = [...activePointers.values()];
        if (!startGesture(pointers[0], pointers[1])) {
            // No selected panel — clean up and release capture
            const pids = [...activePointers.keys()]; // Save BEFORE clear
            activePointers.clear();
            if (canvas && canvas.releasePointerCapture) {
                for (const pid of pids) {
                    try { canvas.releasePointerCapture(pid); } catch (_) {}
                }
            }
            return;
        }
        e.preventDefault();
        pointerGestureActive = true;
    }
}
```

**Key ordering:** Save pointer IDs from `activePointers.keys()` BEFORE calling `activePointers.clear()`. Once cleared, the keys are gone.

**Testing:** Override `canvas.releasePointerCapture` to capture released IDs, then verify both pointers are released when the second `pointerdown` fires with no selected panel.

**Related:** Extends the pointer capture hygiene patterns from `2026-07-12-pointer-capture-hygiene.md`. That learning covers the happy path (capture → gesture → release). This covers the early-exit path.

## 2. 3+ Finger OS Gesture Guard

**Problem:** On iOS and Android, 3-finger or 4-finger touches trigger OS-level gestures (app switcher, screenshot, notification panel). If your PointerEvent handler doesn't call `preventDefault()` on the 3rd+ pointer, the OS may intercept the gesture mid-interaction.

**Fix:** Add a guard for 3+ pointers in `_onPointerDown`:

```javascript
if (activePointers.size === 2) {
    // ... start gesture
} else if (activePointers.size > 2) {
    // Prevent OS-level 3+ finger gestures
    e.preventDefault();
}
```

**Why this matters:** The old TouchEvent path had `if (e.touches.length !== 2) return;` which implicitly blocked 3+ fingers. The PointerEvent path needs an explicit guard because each pointer arrives as a separate event.

**Testing:** Fire three `pointerdown` events and verify the third calls `preventDefault()`.

## 3. touch-action: none as a Deliberate Trade-off

**Context:** The existing learning (`2026-07-22-touch-gesture-conventions-and-touch-action.md`) recommends `touch-action: pan-y` for selective gesture passthrough. However, for apps where the canvas fills the viewport and custom two-finger gestures are critical, `touch-action: none` may be the correct choice.

**When to use `touch-action: none`:**
- Canvas fills the viewport (no content below to scroll to)
- Custom two-finger pan/zoom is a core interaction
- Title drag or other single-finger canvas interactions must not be interrupted by browser gestures (pull-to-refresh, scroll)
- Alternative scroll targets exist (sidebars, bottom sheets with their own scroll containers)

**When to keep `touch-action: pan-y`:**
- Page has scrollable content outside the canvas
- One-finger vertical drag should scroll the page
- Two-finger gestures are secondary to page navigation

**Migration note:** Changing from `pan-y` to `none` is a behavioral change. Document it in the CSS with a comment explaining the trade-off:

```css
/* touch-action: none prevents browser gesture interference (pull-to-refresh,
   iOS back-swipe, scroll) during title drag and two-finger pan/zoom.
   Acceptable trade-off: canvas fills the viewport on mobile, so page
   scrolling is not needed. Sidebars and bottom sheet have their own scroll. */
touch-action: none;
```

## 4. Migrating TouchEvent Tests to PointerEvent

**Pattern:** When migrating from TouchEvent to PointerEvent for touch input, convert existing TouchEvent-based tests to use `PointerEvent` with `pointerType: 'touch'`:

```javascript
// OLD (TouchEvent):
const touches = makeTouchList([makeTouch(1, 100, 100), makeTouch(2, 200, 200)]);
canvas.dispatchEvent(createMockTouchEvent('touchstart', {
    touches: touches, targetTouches: touches, changedTouches: touches
}));

// NEW (PointerEvent):
canvas.dispatchEvent(new PointerEvent('pointerdown', {
    pointerId: 1, clientX: 100, clientY: 100, pointerType: 'touch'
}));
canvas.dispatchEvent(new PointerEvent('pointerdown', {
    pointerId: 2, clientX: 200, clientY: 200, pointerType: 'touch'
}));
```

**Key differences:**
- PointerEvent uses `pointerId` instead of `identifier`
- Two `pointerdown` events replace one `touchstart` with two touches
- `pointermove` replaces `touchmove`
- `pointerup`/`pointercancel` replace `touchend`/`touchcancel`
- No need for mock TouchList construction

**Benefit:** PointerEvent is a native browser constructor (unlike TouchEvent which requires mock objects), making tests simpler and more reliable.
