# Title Multi-Touch Intercept — Bug Fix Plan

**Date:** 2026-08-02
**Source:** `_agent_docs/specifications/change-requests/2026-08-02-01-mobile-multitouch-title-intercept.md`
**Predecessor:** `2026-08-01-panel-swap-during-multitouch.md` (PanelSwap + MultiTouch coordination)

## Overview

When a panel is selected and the user performs a two-finger pinch-to-zoom or pan gesture, if one finger lands on the title area, the title moves or resizes in addition to the expected zoom/pan behavior. The user expects the title to hold still during multi-touch gestures.

The root cause is a missing guard in `TitleInteraction._onPointerMove`: the method does not check `state._multiTouchGestureActive` before processing pointer movement. The guard exists in `_onPointerDown` (line 223) but is absent from `_onPointerMove` (line 318). Additionally, pending title interaction state (`dragStartCoords`, `interactionType`) set by `_onPointerDown` is not cleared when a multi-touch gesture starts, creating a risk of stale state resuming interaction after the gesture ends.

This plan adds the missing guard and introduces a cleanup mechanism to clear pending title state when a multi-touch gesture begins.

## Current State Analysis

### Root Cause

The `_onPointerDown` guard prevents title interaction from starting when a gesture is already active. But the sequence that triggers the bug is:

**Event trace:**
1. **Finger 1 touches title area** → `TitleInteraction._onPointerDown` (line 221) runs. `state._multiTouchGestureActive` is `false`, so it proceeds. Sets `dragStartCoords`, `interactionType`, and `state.titleInteractionMode`. Does NOT yet set `isInteracting = true` — that waits for the 3px drag threshold.
2. **Finger 2 touches canvas** → `MultiTouchHandler._onPointerDown` (line 214) sees `activePointers.size === 2`, calls `startGesture()` (line 140) which sets `state._multiTouchGestureActive = true` (line 145).
3. **Fingers move** → `TitleInteraction._onPointerMove` (line 318) receives pointermove events but **does NOT check `state._multiTouchGestureActive`**. It computes delta from `dragStartCoords` to current position. Since two fingers in a pinch gesture are typically 50-100px apart, this easily exceeds `DRAG_THRESHOLD = 3` (line 31), so `isInteracting` becomes `true` and the title begins dragging/resizing.

### Code Gap

| Handler | Method | Guard Present? | Line |
|---------|--------|---------------|------|
| `TitleInteraction` | `_onPointerDown` | Yes: `if (state._multiTouchGestureActive) return;` | 223 |
| `TitleInteraction` | `_onPointerMove` | **No** | 318 |
| `PanelSwap` | `_onPointerDown` | Yes | 364 |
| `PanelSwap` | `_onPointerMove` | Yes (added in predecessor plan) | 397 |

### Key Discoveries

1. **`state._multiTouchGestureActive` is shared state** — already used by PanelSwap (line 364) and TitleInteraction `_onPointerDown` (line 223) as a guard.
2. **TitleInteraction closure state** — `dragStartCoords`, `interactionType`, `isInteracting` are local closure variables. MultiTouchHandler has no way to clear them.
3. **`_clearInteractionState()` already exists** (TitleInteraction.js lines 81-108) — it clears ALL interaction state including `isInteracting`, `interactionType`, `dragStartCoords`, and reactive state properties. This method is called on `_onPointerUp`.
4. **Pending state vs active state** — `_onPointerDown` sets `dragStartCoords` and `interactionType` but does NOT set `isInteracting = true`. The `isInteracting` flag is set later in `_onPointerMove` when the drag threshold is crossed. We need to clear the pending state BEFORE the threshold check.
5. **Handler attach order** in `createCollageLifecycle.js`: MultiTouchHandler (line 186-197) attaches before TitleInteraction (line 201-254). MultiTouchHandler handlers fire BEFORE TitleInteraction handlers for each event.
6. **`startGesture()`** (MultiTouchHandler.js lines 140-149) is the exact insertion point — it runs synchronously in the second finger's `pointerdown` event, after `_multiTouchGestureActive` is set.
7. **TitleInteraction has no public method** for canceling pending interaction. A new method is needed.
8. **No template bindings for title interaction closure state** — `dragStartCoords`, `interactionType`, `isInteracting` are only read/written by the handler. No Vue reactivity concern.
9. **`_onPointerLeave` already guards against active interaction** (line 435: `if (isInteracting) return`) — clears hover state only when not actively dragging.

### Why Other Approaches Don't Work

| Approach | Problem |
|----------|---------|
| Guard only in `_onPointerMove` threshold check | Prevents drag activation during gesture, but pending state lingers. If gesture ends and pointer moves again, stale `dragStartCoords` could trigger a drag from wrong position. |
| Reset `dragStartCoords` in `_onPointerMove` when gesture detected | Works for the threshold case, but doesn't clear `interactionType` or reactive state (`titleInteractionMode`). Partial cleanup. |
| Callback-based cleanup (app wires TitleInteraction to MultiTouchHandler) | Adds wiring complexity. A public method on TitleInteraction is simpler. |
| Exposing closure state through handler API | Overly invasive — changes the handler interface. A single `cancelPendingInteraction()` method is minimal. |

## Desired End State

After this fix:
- Two-finger pinch/pan with one finger on the title area does NOT move or resize the title
- Single-finger title drag-to-move continues to work correctly
- Single-finger title edge-drag-to-resize continues to work correctly
- Title hover feedback (cursor changes, outline) continues to work correctly
- Pending title interaction state is cleared when a multi-touch gesture starts
- No stale title interaction state persists after a gesture ends

## What We're NOT Doing

1. **NOT changing handler attach order** — MultiTouchHandler before TitleInteraction is correct and consistent with PanelSwap coordination.
2. **NOT modifying `_onPointerDown`** — Its guard is already correct.
3. **NOT modifying `_onPointerUp`** — Its cleanup via `_clearInteractionState()` is already correct.
4. **NOT modifying `_onPointerLeave`** — Its guard against active interaction is already correct.
5. **NOT modifying MultiTouchHandler's core gesture logic** — Only adding a cleanup callback invocation.
6. **NOT modifying hover feedback in `_onPointerMove`** — The guard applies only to the interaction portion (threshold check + drag/resize), not to the hover feedback portion. Hover should still work during gestures to avoid visual artifacts.
7. **NOT adding Playwright multi-touch simulation** — Playwright cannot reliably simulate two-finger gestures. Real-device validation required.
8. **NOT modifying the title hit test logic** — `_hitTestTitle` is unaffected by this bug.

## Implementation Approach

Two-phase change. Phase 1 is the primary fix (guard in `_onPointerMove`). Phase 2 is the secondary fix (pending state cleanup). Both phases are small and low-risk, but separated for incremental verification.

**Execution order:**
1. Phase 1: Add guard to `_onPointerMove` in TitleInteraction.js
2. Phase 2: Add `cancelPendingInteraction()` method to TitleInteraction, call from `startGesture()` via callback

## Phase 1: Add Multi-Touch Guard to `_onPointerMove` (P0)

**Status: COMPLETE** (2026-08-03)

### Overview

Add the same `state._multiTouchGestureActive` guard at the top of `_onPointerMove` that already exists in `_onPointerDown`. This is the primary fix that prevents the title from being dragged/resized during two-finger gestures.

### Changes Required:

#### 1. TitleInteraction.js — Add guard to `_onPointerMove`

**File**: `MyESModules/Interaction/TitleInteraction.js`

**Changes**: Add guard at the top of `_onPointerMove` (line 318), matching the pattern in `_onPointerDown` (line 223):

```javascript
_onPointerMove(e) {
    // Skip if multi-touch gesture is active — prevents title from
    // being dragged/resized when one finger is on the title during
    // a two-finger pinch or pan gesture.
    if (state._multiTouchGestureActive) return;

    const canvas = document.getElementById(canvasId);
    // ... rest of method (unchanged)
```

**Rationale**: This is a direct mirror of the guard in `_onPointerDown` (line 223). The same shared state flag (`_multiTouchGestureActive`) is already set by MultiTouchHandler's `startGesture()` and cleared by `endGesture()`. The guard prevents ALL `_onPointerMove` processing during active gestures, including threshold checks, drag/resize application, AND hover feedback updates. This is intentional — hover state changes during a gesture would cause unnecessary renders and visual flicker.

### BDD Scenarios

#### User Behavior

| # | Given | When | Then |
|---|-------|------|------|
| 1.1.1 | Images loaded, title set, panel selected | User performs two-finger pinch-to-zoom with one finger on the title area | Title does NOT move or resize; only zoom is applied to the selected panel |
| 1.1.2 | Images loaded, title set, panel selected | User performs two-finger pan with one finger on the title area | Title does NOT move; only pan is applied to the selected panel |
| 1.1.3 | Images loaded, title set, no gesture active | User drags the title with one finger | Title moves correctly (regression check) |
| 1.1.4 | Images loaded, title set, no gesture active | User drags the title edge with one finger | Title resizes correctly (regression check) |
| 1.1.5 | Images loaded, title set, no gesture active | User hovers over the title area with one finger | Cursor changes to grab/ew-resize, hover outline appears (regression check) |

#### Component Behavior — TitleInteraction

| # | Given | When | Then |
|---|-------|------|------|
| 1.2.1 | `state._multiTouchGestureActive` is `true` | `pointermove` fires on title body | `_onPointerMove` returns immediately; no threshold check, no drag, no hover update |
| 1.2.2 | `state._multiTouchGestureActive` is `false` | `pointermove` fires on title body | Normal processing: threshold check, hover feedback, drag/resize if active |
| 1.2.3 | `dragStartCoords` set, `isInteracting` is `false`, `state._multiTouchGestureActive` becomes `true` | `pointermove` fires with delta exceeding `DRAG_THRESHOLD` | `isInteracting` remains `false`; drag does NOT activate |
| 1.2.4 | `isInteracting` is `true`, `state._multiTouchGestureActive` becomes `true` | `pointermove` fires | Drag/resize does NOT continue; `_onPointerMove` returns immediately |
| 1.2.5 | `state._multiTouchGestureActive` is `true` | `pointermove` fires outside title area | No hover state change (guard returns before hover logic) |
| 1.2.6 | `state._multiTouchGestureActive` is `false` | `pointermove` fires outside title area | Hover state cleared (regression check) |

#### Pure Function Behavior

| # | Given | When | Then |
|---|-------|------|------|
| 1.3.1 | `_onPointerMove` called with `state._multiTouchGestureActive = true` | — | Method returns before any canvas DOM lookup or coordinate computation |

### Success Criteria:

#### Automated Verification:
- [ ] `TitleInteractionTest.html` — All existing tests pass (regression)
- [ ] `TitleInteractionTest.html` — New test: `_onPointerMove` returns early when `_multiTouchGestureActive` is `true`
- [ ] `TitleInteractionTest.html` — New test: drag threshold NOT crossed during active gesture
- [ ] `TitleInteractionTest.html` — New test: active drag/resize halted during gesture
- [ ] `TitleInteractionTest.html` — New test: hover feedback NOT updated during gesture
- [ ] `TitleInteractionTest.html` — New test: single-finger drag still works when gesture is NOT active (regression)
- [ ] `TitleInteractionTest.html` — New test: single-finger resize still works when gesture is NOT active (regression)
- [ ] `TitleInteractionTest.html` — New test: single-finger hover still works when gesture is NOT active (regression)
- [ ] `MultiTouchHandlerTest.html` — All existing tests pass (regression)
- [ ] Full test suite: `node scripts/run-tests.js` passes

#### Manual Verification:
- [ ] On real iOS device: two-finger pinch with one finger on title — title holds still
- [ ] On real iOS device: two-finger pan with one finger on title — title holds still
- [ ] On real Android device: same tests
- [ ] On desktop: single-finger title drag works
- [ ] On desktop: single-finger title resize works
- [ ] On desktop: title hover feedback works

---

## Phase 2: Clear Pending Title State on Gesture Start (P1)

### Overview

When `_onPointerDown` sets pending state (`dragStartCoords`, `interactionType`, `state.titleInteractionMode`) and then a multi-touch gesture starts, the Phase 1 guard prevents the drag from activating. However, the pending state remains set. If the gesture ends and the user continues moving their finger, the stale `dragStartCoords` could trigger a drag from the wrong position.

This phase adds a `cancelPendingInteraction()` method to TitleInteraction and wires it to be called from `startGesture()` via an optional callback.

### Changes Required:

#### 1. TitleInteraction.js — Add `cancelPendingInteraction()` method

**File**: `MyESModules/Interaction/TitleInteraction.js`

**Changes**: Add a new public method to the handler object (after `_clearInteractionState`, around line 108):

```javascript
/**
 * Clears pending interaction state (dragStartCoords, interactionType)
 * without calling onInteractionEnd. Used when a multi-touch gesture
 * starts and we need to abandon the title interaction that was
 * initiated by the first finger's pointerdown.
 * Does NOT clear active interaction (isInteracting === true) —
 * that is handled by _clearInteractionState on pointerup.
 * @private
 */
cancelPendingInteraction() {
    // Only clear if we have pending state (pointerdown happened but
    // drag threshold hasn't been crossed yet)
    if (dragStartCoords && !isInteracting) {
        dragStartCoords = null;
        interactionType = null;
        dragStartBoxX = null;
        dragStartBoxY = null;
        dragStartBoxWidth = null;

        // Clear reactive state set by _onPointerDown
        state.titleInteractionMode = null;
        state.titleHoverTarget = null;
        state.titleInteractionPointerType = null;
        lastPointerType = null;

        const canvas = document.getElementById(canvasId);
        if (canvas) {
            canvas.style.cursor = '';
            // Release pointer capture if held (set by _onPointerDown)
            if (canvas.releasePointerCapture && capturedPointerId !== undefined) {
                try { canvas.releasePointerCapture(capturedPointerId); } catch (_) {}
                capturedPointerId = undefined;
            }
        }

        if (onRenderScheduled) {
            onRenderScheduled();
        }
    }
},
```

**Rationale**: This method clears only the PENDING state (set by `_onPointerDown` but not yet activated by threshold crossing). It does NOT call `onInteractionEnd` because the interaction never started. It releases pointer capture set by `_onPointerDown` and schedules a render to clear any visual feedback (cursor, interaction outline).

#### 2. TitleInteraction.js — Add optional `onGestureStart` callback parameter

**File**: `MyESModules/Interaction/TitleInteraction.js`

**Changes**: Add `onGestureStart` as an optional parameter to the factory function signature:

```javascript
export function createTitleInteraction({ canvasId, state, titleManager, onRenderScheduled, onInteractionStart, onInteractionEnd, onGestureStart }) {
```

**Rationale**: The `onGestureStart` callback is invoked by the caller (app lifecycle) when a multi-touch gesture starts. It provides a hook for the caller to coordinate with other handlers. This is optional — existing callers that don't pass it will continue to work.

#### 3. createCollageLifecycle.js — Wire `cancelPendingInteraction` to gesture start

**File**: `MyESModules/App/createCollageLifecycle.js`

**Changes**: In the `createMultiTouchHandler` call (around line 186), add a custom `onCropPreviewRender` wrapper or use the existing callback infrastructure to call `titleInteraction.cancelPendingInteraction()` when a gesture starts.

The cleanest approach: after creating both handlers, modify the `startGesture` flow by wrapping the `onRenderScheduled` callback or by adding a one-time setup. Since `startGesture()` is a closure inside `createMultiTouchHandler`, we can't directly inject into it. Instead, we use the `onGestureStart` callback pattern:

**Alternative approach (simpler)**: Instead of modifying MultiTouchHandler's interface, call `cancelPendingInteraction()` from the app lifecycle at the point where we know a gesture started. Since `state._multiTouchGestureActive` is set synchronously in the second finger's `pointerdown`, we can use a reactive watcher or a shared callback.

**Best approach**: Add `onGestureStart` as an optional callback parameter to `createMultiTouchHandler`. This is the most explicit and testable approach.

**File**: `MyESModules/Interaction/MultiTouchHandler.js`

**Changes**:

a. Add `onGestureStart` to factory parameters (line 83):
```javascript
export function createMultiTouchHandler({ canvasId, cropManager, state, onCropPreviewRender, onRenderScheduled, onGestureStart }) {
```

b. Call `onGestureStart()` in `startGesture()` (after line 148):
```javascript
function startGesture(t1, t2) {
    const panelId = state.selectedPanelId;
    if (!panelId) return false;

    gestureActive = true;
    state._multiTouchGestureActive = true;
    state.dragSourceId = null;

    if (onGestureStart) {
        onGestureStart();
    }

    initialMidpoint = computeTouchMidpoint(t1, t2);
    initialDistance = computeTouchDistance(t1, t2);
    return true;
}
```

**File**: `MyESModules/App/createCollageLifecycle.js`

**Changes**: Wire the callback in the `createMultiTouchHandler` call:

```javascript
// Initialize multi-touch gesture handler (two-finger pan + pinch-to-zoom on main canvas)
this._multiTouchHandler = createMultiTouchHandler({
    canvasId: ids.previewCanvas,
    cropManager: this.cropManager,
    state: this,
    onCropPreviewRender: () => {
        this._scheduleCropPreviewRender();
    },
    onRenderScheduled: () => {
        this._scheduleRender();
    },
    onGestureStart: () => {
        // Cancel any pending title interaction when a multi-touch gesture starts.
        // This prevents stale dragStartCoords from triggering a title drag
        // after the gesture ends.
        if (this._titleInteraction && this._titleInteraction.cancelPendingInteraction) {
            this._titleInteraction.cancelPendingInteraction();
        }
    }
});
```

**Note**: The `_titleInteraction` handler is created AFTER `_multiTouchHandler` in the current code (line 201). The `onGestureStart` callback is called from `startGesture()` which runs synchronously on the second finger's `pointerdown`. At that point, `_titleInteraction` is already created (since creation is synchronous). This is safe.

### BDD Scenarios

#### User Behavior

| # | Given | When | Then |
|---|-------|------|------|
| 2.1.1 | Images loaded, title set, panel selected | User touches title with one finger, then places second finger down (gesture starts) | Title interaction state is cancelled; title does NOT move when fingers move |
| 2.1.2 | Images loaded, title set, panel selected | User touches title with one finger, places second finger down, lifts second finger (gesture ends), continues moving first finger | Title does NOT start dragging from stale coordinates |
| 2.1.3 | Images loaded, title set, panel selected | User touches title with one finger, places second finger down, lifts both fingers, then touches title again with one finger | New single-finger title interaction works correctly |

#### Component Behavior — TitleInteraction

| # | Given | When | Then |
|---|-------|------|------|
| 2.2.1 | `dragStartCoords` set, `isInteracting` is `false` | `cancelPendingInteraction()` called | `dragStartCoords` is `null`, `interactionType` is `null`, `state.titleInteractionMode` is `null` |
| 2.2.2 | `dragStartCoords` is `null`, `isInteracting` is `false` | `cancelPendingInteraction()` called | No-op (no state changes, no errors) |
| 2.2.3 | `isInteracting` is `true` (drag active) | `cancelPendingInteraction()` called | No-op (active interaction is NOT cleared; only pending state is cleared) |
| 2.2.4 | `dragStartCoords` set, pointer capture held | `cancelPendingInteraction()` called | Pointer capture is released |
| 2.2.5 | `dragStartCoords` set, cursor set to 'grab' | `cancelPendingInteraction()` called | Cursor is reset to empty string |
| 2.2.6 | `dragStartCoords` set | `cancelPendingInteraction()` called | `onRenderScheduled` is called (to clear interaction outline) |

#### Component Behavior — MultiTouchHandler

| # | Given | When | Then |
|---|-------|------|------|
| 2.3.1 | `onGestureStart` callback provided | Two `pointerdown` events trigger `startGesture()` | `onGestureStart()` is called synchronously |
| 2.3.2 | `onGestureStart` is `undefined` | Two `pointerdown` events trigger `startGesture()` | No error; gesture starts normally |
| 2.3.3 | `onGestureStart` callback provided, no selected panel | Two `pointerdown` events | `onGestureStart()` is NOT called (startGesture returns false) |

#### Integration — Cross-Handler Coordination

| # | Given | When | Then |
|---|-------|------|------|
| 2.4.1 | Both handlers attached, same canvas, same state, `onGestureStart` wired to `cancelPendingInteraction` | `pointerdown(1)` on title → `pointerdown(2)` anywhere → `pointermove` (fingers spread 100px) | Title does NOT move. `state.titleInteractionMode` is `null`. `dragStartCoords` cleared. |
| 2.4.2 | Both handlers attached, `onGestureStart` wired | `pointerdown(1)` on title → `pointerdown(2)` → `pointerup(2)` (gesture ends) → `pointermove(1)` (finger moves 50px) | Title does NOT start dragging (stale state was cleared) |
| 2.4.3 | Both handlers attached, `onGestureStart` wired | Gesture completes, new single-finger `pointerdown` on title → drag | Title interaction works normally |

### Success Criteria:

#### Automated Verification:
- [ ] `TitleInteractionTest.html` — All existing tests pass (regression)
- [ ] `TitleInteractionTest.html` — New test: `cancelPendingInteraction()` clears pending state
- [ ] `TitleInteractionTest.html` — New test: `cancelPendingInteraction()` is no-op when no pending state
- [ ] `TitleInteractionTest.html` — New test: `cancelPendingInteraction()` does NOT clear active interaction
- [ ] `TitleInteractionTest.html` — New test: `cancelPendingInteraction()` releases pointer capture
- [ ] `TitleInteractionTest.html` — New test: `cancelPendingInteraction()` resets cursor
- [ ] `TitleInteractionTest.html` — New test: `cancelPendingInteraction()` schedules render
- [ ] `MultiTouchHandlerTest.html` — All existing tests pass (regression)
- [ ] `MultiTouchHandlerTest.html` — New test: `onGestureStart` callback called on gesture start
- [ ] `MultiTouchHandlerTest.html` — New test: missing `onGestureStart` does not cause error
- [ ] `MultiTouchHandlerTest.html` — New test: `onGestureStart` NOT called when startGesture fails
- [ ] `TitleInteractionMultiTouchIntegrationTest.html` — New file: full two-finger gesture with finger on title does NOT move title
- [ ] `TitleInteractionMultiTouchIntegrationTest.html` — New file: gesture start clears pending title state
- [ ] `TitleInteractionMultiTouchIntegrationTest.html` — New file: after gesture ends, single-finger title interaction works
- [ ] Full test suite: `node scripts/run-tests.js` passes

#### Manual Verification:
- [ ] On real iOS device: touch title → second finger down → pinch/pan → title holds still
- [ ] On real iOS device: touch title → second finger down → lift second finger → move first finger → title does NOT drag
- [ ] On real iOS device: after gesture ends, single-finger title drag works
- [ ] On real Android device: same tests
- [ ] On desktop: single-finger title drag/resize/hover all work
- [ ] On desktop: no visual artifacts (cursor stuck, outline persisting) after gesture

---

## Testing Strategy

### Unit Tests

**Existing test file to update:**

**`MyComponents/TitleInteractionTest.html`** — Add new `describe` blocks:

```
describe('TitleInteraction — Multi-touch Guard in _onPointerMove', () => {
  // 8 new tests covering:
  // - _onPointerMove returns early when _multiTouchGestureActive is true
  // - drag threshold NOT crossed during active gesture
  // - active drag/resize halted during gesture
  // - hover feedback NOT updated during gesture
  // - single-finger drag regression
  // - single-finger resize regression
  // - single-finger hover regression
  // - guard does not affect _onPointerDown behavior
})

describe('TitleInteraction — cancelPendingInteraction', () => {
  // 7 new tests covering:
  // - Clears pending state (dragStartCoords, interactionType, reactive state)
  // - No-op when no pending state
  // - No-op when interaction is active (isInteracting === true)
  // - Releases pointer capture
  // - Resets cursor
  // - Schedules render
  // - Clears dragStartBoxX/Y/Width
})
```

**`MyComponents/MultiTouchHandlerTest.html`** — Add new `describe` block:

```
describe('MultiTouchHandler — onGestureStart callback', () => {
  // 3 new tests covering:
  // - onGestureStart called on gesture start
  // - Missing onGestureStart does not cause error
  // - onGestureStart NOT called when startGesture fails (no selected panel)
})
```

**New test file: `MyComponents/TitleInteractionMultiTouchIntegrationTest.html`** — Integration tests:

```
describe('TitleInteraction + MultiTouchHandler — cross-handler coordination', () => {
  // 3+ new tests covering:
  // - Full two-finger gesture with finger on title does NOT move title
  // - Gesture start clears pending title state
  // - After gesture ends, single-finger title interaction works
  // - Gesture end (pointerup) followed by pointermove does NOT resume title drag
})
```

**Test harness setup for integration tests:**

```javascript
// Both handlers share the same canvas and state
const canvas = document.createElement('canvas');
canvas.id = 'title-integration-canvas';
// ... mount to DOM ...

const state = {
    titleStyle: { titleBoxX: 500, titleBoxY: 900, titleBoxWidth: 400, fontSize: 36, fontFamily: 'Arial', alignment: 'center' },
    titleRuns: [{ text: 'Hello World' }],
    panels: [],
    panelAssignments: new Map(),
    _multiTouchGestureActive: false,
    titleInteractionMode: null,
    titleHoverTarget: null,
    titleInteractionPointerType: null,
    selectedPanelId: 'panel-0'
};

let gestureStartCalled = false;
let positionCalls = [];
const titleManager = {
    setPosition: (x, y) => { positionCalls.push({ x, y }); },
    setWidth: () => {},
    getRuns: () => state.titleRuns
};

const titleHandler = createTitleInteraction({
    canvasId: 'title-integration-canvas',
    state: state,
    titleManager: titleManager,
    onRenderScheduled: () => {},
    onInteractionStart: () => {},
    onInteractionEnd: () => {}
});

const multiTouchHandler = createMultiTouchHandler({
    canvasId: 'title-integration-canvas',
    cropManager: {
        adjustCrop: () => {},
        zoomCrop: () => {},
        getPanelImage: () => ({ width: 1920, height: 1080 })
    },
    state: state,
    onCropPreviewRender: () => {},
    onRenderScheduled: () => {},
    onGestureStart: () => {
        gestureStartCalled = true;
        titleHandler.cancelPendingInteraction();
    }
});

// CRITICAL: MultiTouchHandler attaches FIRST (as in production)
multiTouchHandler.attach();
titleHandler.attach();
```

### E2E Tests (Playwright)

Playwright cannot reliably simulate two-finger touch gestures. An E2E test can verify the **state-level fix** via `page.evaluate()`:

```javascript
test('title not moved during simulated two-finger gesture', async ({ page }) => {
    // Load page, set up title, then use page.evaluate() to:
    // 1. Record initial title position
    // 2. Dispatch pointer event sequence on canvas:
    //    pointerdown(touch, on title) → pointerdown(touch, elsewhere) → pointermove (fingers spread) → pointerup → pointerup
    // 3. Assert title position unchanged
});

test('single-finger title drag still works (regression)', async ({ page }) => {
    // Load page, set up title, use page.mouse to:
    // 1. Drag title from one position to another
    // 2. Assert title position changed
});
```

### Manual Testing Steps

1. **iOS Safari (iPhone):**
   - Load page, upload images, set a title
   - Select a panel
   - Touch title area with one finger → place second finger down → pinch/pan → verify title holds still
   - Touch title → second finger down → lift second finger → move first finger → verify title does NOT drag
   - After gesture ends, single-finger title drag → verify works
   - Single-finger title resize → verify works

2. **Chrome for Android:**
   - Same steps as iOS

3. **Desktop browser (Chrome/Firefox/Safari):**
   - Single-finger title drag → verify works
   - Single-finger title resize → verify works
   - Title hover feedback → verify works
   - Trackpad two-finger pan/zoom → verify no regression in title behavior

### Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | Phase 1.2.1 (_onPointerMove guard), Phase 1.2.3 (threshold not crossed), Integration 1.1.1 (two-finger pinch with finger on title) | Core bug fix — if these fail, the bug is not fixed |
| **P1** | Phase 2.2.1 (cancelPendingInteraction clears state), Phase 2.4.1 (integration: gesture clears pending state), Phase 2.4.2 (no stale drag after gesture) | Structural correctness — prevents stale state issues |
| **P2** | Phase 1.2.5 (hover not updated), Phase 2.2.2 (no-op when no pending), Phase 2.2.3 (no-op when active), Phase 2.4.3 (regression: single-finger after gesture) | Robustness and polish — edge cases and regression safety |

---

## Known Behaviors and Intentional Design Decisions

### Guard Scope in `_onPointerMove`

1. **Guard applies to ALL `_onPointerMove` processing** — including threshold check, drag/resize application, AND hover feedback. This is intentional: hover state changes during a gesture would cause unnecessary renders and visual flicker. The hover state will be restored when the gesture ends and the next `pointermove` fires (since `_multiTouchGestureActive` will be `false`).

2. **Guard does NOT apply to `_onPointerDown`** — the existing guard in `_onPointerDown` is sufficient. It prevents new title interactions from starting when a gesture is already active.

3. **Guard does NOT apply to `_onPointerLeave`** — `_onPointerLeave` already has its own guard (`if (isInteracting) return`). It only clears hover state when not actively dragging, which is correct behavior during gestures.

### `cancelPendingInteraction()` Design

4. **Only clears PENDING state** — if `isInteracting` is `true` (drag is active), `cancelPendingInteraction()` is a no-op. Active interaction is cleaned up by `_clearInteractionState()` on `pointerup`. This distinction prevents accidentally canceling a legitimate single-finger drag that happens to coincide with a brief gesture flag flicker.

5. **Releases pointer capture** — `_onPointerDown` calls `setPointerCapture()`. If the gesture starts before the drag threshold is crossed, the capture needs to be released so the remaining finger's events go to MultiTouchHandler.

6. **Schedules a render** — clearing `state.titleInteractionMode` and `state.titleHoverTarget` may change the rendered interaction outline. A render is scheduled to update the visual state.

7. **Does NOT call `onInteractionEnd`** — the interaction never started (threshold not crossed), so the end callback should not fire. Calling it would incorrectly trigger undo snapshot cleanup.

### Timing Edge Cases

8. **Rapid finger-down sequence**: Finger 1 on title → `_onPointerDown` sets pending state → Finger 2 anywhere → `startGesture()` sets `_multiTouchGestureActive = true` → `onGestureStart()` calls `cancelPendingInteraction()`. All synchronous in the same event loop tick. **Works correctly.**

9. **Gesture starts, then ends, then pointer moves**: Gesture clears pending state → gesture ends → `pointermove` fires → `_onPointerMove` sees no `dragStartCoords` → falls through to hover logic (no drag). **Correct behavior.**

10. **Finger lifted from title during gesture**: `pointerup` on title finger → `_onPointerUp` calls `_clearInteractionState()` → state already cleared by `cancelPendingInteraction()` → idempotent. **Safe.**

11. **`onGestureStart` callback is optional**: If a caller doesn't provide `onGestureStart`, MultiTouchHandler works normally. The guard in `_onPointerMove` (Phase 1) still protects against the main bug. The cleanup (Phase 2) is an enhancement for edge case robustness.

### Cleanup Edge Cases

12. **`pointercancel` fires**: MultiTouchHandler's `_onPointerCancel` clears `_multiTouchGestureActive` and calls `endGesture()`. TitleInteraction's `_onPointerUp` (which handles `pointercancel`) calls `_clearInteractionState()`. If `cancelPendingInteraction()` already ran, `_clearInteractionState()` is idempotent. **Safe.**

13. **Handler detach during pending state**: `detach()` does not call `_clearInteractionState()`. If pending state exists when `detach()` is called, it persists in the closure. This is acceptable — the handler is being destroyed and the state is inaccessible.

14. **Window blur during gesture**: MultiTouchHandler's blur handler calls `endGesture()` which sets `_multiTouchGestureActive = false`. TitleInteraction's pending state was already cleared by `cancelPendingInteraction()`. **Safe.**

---

## Performance Considerations

1. **Guard is a single boolean check**: `if (state._multiTouchGestureActive) return;` is O(1) and adds negligible overhead to `_onPointerMove`.
2. **`cancelPendingInteraction()` runs once per gesture**: Called only when `startGesture()` succeeds. Not called on every `pointermove`.
3. **No additional render cycles**: The guard in `_onPointerMove` actually REDUCES render calls by preventing hover feedback updates during gestures.
4. **`onGestureStart` callback is optional**: Callers that don't use it incur zero overhead (simple `if (onGestureStart)` check).

---

## Migration Notes

- The changes are backward compatible:
  - `createTitleInteraction` accepts the same parameters (no new required parameters)
  - `createMultiTouchHandler` accepts the same parameters (`onGestureStart` is optional)
  - Existing callers that don't pass `onGestureStart` continue to work
- The `cancelPendingInteraction()` method is a new public method on the TitleInteraction handler. It is safe to call at any time.
- Rollback: revert the 3 files (TitleInteraction.js, MultiTouchHandler.js, createCollageLifecycle.js). No data migration needed.

---

## References

- Change request: `_agent_docs/specifications/change-requests/2026-08-02-01-mobile-multitouch-title-intercept.md`
- Predecessor plan: `_agent_docs/plans/2026-08-01-panel-swap-during-multitouch.md`
- Source files:
  - `MyESModules/Interaction/TitleInteraction.js` (lines 318-422: `_onPointerMove`, lines 81-108: `_clearInteractionState`, lines 221-311: `_onPointerDown`)
  - `MyESModules/Interaction/MultiTouchHandler.js` (lines 140-149: `startGesture`, lines 202-208: `endGesture`, lines 283-305: `_onPointerCancel`)
  - `MyESModules/App/createCollageLifecycle.js` (lines 186-254: handler creation and attach order)
- Test files:
  - `MyComponents/TitleInteractionTest.html` (existing test patterns, lines 908-961: multi-touch guard tests)
  - `MyComponents/MultiTouchHandlerTest.html` (existing test patterns, lines 176-400: factory tests)
  - `MyComponents/PanelSwapMultiTouchIntegrationTest.html` (integration test pattern, lines 35-348)
- Skill references: `building-web-apps` skill — multi-touch gestures, pointer capture lifecycle, handler `.call(this)`, closure safety
