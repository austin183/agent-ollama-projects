# Synopsis

After the mobile touch enhancements (PointerEvents migration + zoom sensitivity fix) were deployed, pinch-to-zoom pacing is good on mobile. However, panels still swap unexpectedly when a two-finger pinch or pan gesture crosses panel boundaries.

# Canvas Changes

## Panels swap during two-finger pinch/pan when fingers cross panel boundaries

**Reported:** When I pinch to zoom or use two fingers to pan the image in a panel and I cross over to another panel, the panels swap. This happens consistently when one finger's touch point ends up on a different panel than where it started.

**Severity:** High

---

### Root Cause Analysis

The bug is caused by **incomplete coordination between PanelSwap and MultiTouchHandler**. The `_multiTouchGestureActive` guard was designed to prevent PanelSwap from starting a new drag when a two-finger gesture is active, but it has a critical gap: it only guards `_onPointerDown`, not the drag state that was already established by the first finger.

#### Detailed Event Trace

The handler attach order in `createCollageLifecycle.js` is:
1. GestureHandler (pointermove, pointerleave only — no pointerdown)
2. **MultiTouchHandler** (pointerdown, pointermove, pointerup, pointercancel)
3. TitleInteraction (pointerdown, pointermove, pointerup, pointercancel)
4. **PanelSwap** (pointerdown, pointermove, pointerup, pointercancel)

Because PanelSwap attaches AFTER MultiTouchHandler, MultiTouchHandler's handlers fire first for each event.

**Step 1 — Finger 1 down on Panel A:**
- MultiTouchHandler `_onPointerDown`: adds pointer 1 to `activePointers` (size=1), calls `setPointerCapture(1)`. No gesture starts (need 2 fingers).
- PanelSwap `_onPointerDown`: `state._multiTouchGestureActive` is **false** (no gesture yet) → proceeds. Sets local `dragSourceId = Panel A`, records `_dragStartCoords`, calls `setPointerCapture(1)`.

**Step 2 — Finger 2 down (two-finger gesture begins):**
- MultiTouchHandler `_onPointerDown`: adds pointer 2 (size=2), calls `setPointerCapture(2)`. `startGesture()` sets `state._multiTouchGestureActive = true` synchronously.
- PanelSwap `_onPointerDown`: `state._multiTouchGestureActive` is now **true** → **returns early** at line 364. **But `dragSourceId` from Step 1 is still set to Panel A.** This is the bug — the guard prevents a NEW drag from starting but does NOT clear the drag state already established by the first finger.

**Step 3 — During two-finger pan/zoom (pointermove):**
- MultiTouchHandler `_onPointerMove`: processes pan/zoom correctly.
- PanelSwap `_onPointerMove`: `dragSourceId` IS set (from Step 1), so it proceeds. As fingers move and cross panel boundaries, `_hitTestPanel` updates `dragTargetId` to whichever panel the moving pointer is over. **This handler does not check `_multiTouchGestureActive` at all** — it only checks `dragSourceId`.

**Step 4 — Finger 1 lifts:**
- MultiTouchHandler `_onPointerUp`: removes pointer 1 from `activePointers`, sees `activePointers.size < 2`, calls `endGesture()` which sets `state._multiTouchGestureActive = false`.
- PanelSwap `_onPointerUp`: `state._multiTouchGestureActive` is now **false** (cleared by MultiTouchHandler in the same synchronous event, which fired first). `dragSourceId` is set. `isDragging` is true (fingers moved ≥10 CSS pixels during the gesture). Hit test at pointer position returns whatever panel the finger is currently over. If `targetId !== dragSourceId` → **SWAP EXECUTES**.

#### Summary of the Gap

| Handler | Event | Guard Present? | Effect |
|---------|-------|---------------|--------|
| PanelSwap `_onPointerDown` | 2nd finger down | ✅ Checks `_multiTouchGestureActive` | Returns early — good |
| PanelSwap `_onPointerMove` | During gesture | ❌ No guard | Updates `dragTargetId` — bad |
| PanelSwap `_onPointerUp` | 1st finger lifts | ✅ Checks `_multiTouchGestureActive` | Flag already cleared by MultiTouchHandler — bad |

The fundamental problem: **`dragSourceId` is set in Step 1 (before the gesture exists) and is never cleared when the gesture starts in Step 2.** The guard in `_onPointerDown` prevents a second `dragSourceId` from being set, but the first one persists.

---

### Proposed Solutions

#### Solution A: Clear drag source on gesture start (Recommended)

Move `dragSourceId` from PanelSwap's local closure to the shared `state` object as `state.dragSourceId`. When MultiTouchHandler's `startGesture()` detects a two-finger gesture, it clears `state.dragSourceId = null`. This ensures PanelSwap has no stale drag state to act upon when either finger lifts.

**Changes:**
1. **PanelSwap.js** — Replace local `dragSourceId` with `state.dragSourceId`. All reads/writes of `dragSourceId` become `state.dragSourceId`.
2. **MultiTouchHandler.js** — In `startGesture()`, after setting `state._multiTouchGestureActive = true`, also set `state.dragSourceId = null`.
3. **MultiTouchHandler.js** — In `_onPointerCancel()`, also set `state.dragSourceId = null` (safety net for gesture cancellation).
4. **createCollageData.js** — Add `dragSourceId: null` to the initial state.

**Why this works:** When finger 2 goes down and `startGesture()` runs, `state.dragSourceId` is cleared. PanelSwap's subsequent `_onPointerMove` and `_onPointerUp` see `dragSourceId` as null and return early. No swap can occur.

**Risk:** Low. `dragSourceId` is only used by PanelSwap internally. Moving it to shared state is a mechanical change. The clearing in `startGesture()` is a one-line addition.

#### Solution B: Callback-based cleanup (Alternative)

Add an optional `onGestureStart` callback to PanelSwap's factory function. MultiTouchHandler calls this callback when `startGesture()` succeeds. The callback clears PanelSwap's internal `dragSourceId`.

**Changes:**
1. **PanelSwap.js** — Accept optional `onGestureStart` callback. Expose a `_cancelDrag()` method that clears `dragSourceId`, `isDragging`, `_dragStartCoords`, and releases pointer capture.
2. **MultiTouchHandler.js** — Accept optional `onGestureStart` callback. Call it in `startGesture()` after setting the flag.
3. **createCollageLifecycle.js** — Wire PanelSwap's `_cancelDrag` as MultiTouchHandler's `onGestureStart`.

**Why this works:** Same outcome as Solution A, but keeps `dragSourceId` encapsulated in PanelSwap's closure.

**Risk:** Low. Adds one callback parameter to each factory. No behavioral change to existing callers (callback is optional).

#### Solution C: Guard `_onPointerMove` and `_onPointerUp` (Insufficient alone)

Add `_multiTouchGestureActive` checks to PanelSwap's `_onPointerMove` and `_onPointerUp`.

**Problem:** This does NOT work for `_onPointerUp` because MultiTouchHandler clears `_multiTouchGestureActive` in its `_onPointerUp` BEFORE PanelSwap's `_onPointerUp` fires (same event, synchronous, MultiTouchHandler registered first). By the time PanelSwap checks the flag, it's already false.

**This guard IS useful for `_onPointerMove`** — it prevents `dragTargetId` from updating during the gesture, eliminating incorrect visual feedback. But it does NOT prevent the swap on pointerup.

**Recommendation:** Apply this guard to `_onPointerMove` as a complement to Solution A or B, but do NOT rely on it alone.

---

### Recommended Implementation (Solution A + `_onPointerMove` guard)

#### 1. PanelSwap.js — Use `state.dragSourceId` and add `_onPointerMove` guard

**File:** `MyESModules/Interaction/PanelSwap.js`

**Changes:**
- Remove local `let dragSourceId = null;` declaration (line 261).
- Replace all references to `dragSourceId` with `state.dragSourceId`:
  - Line 390: `dragSourceId = panelId;` → `state.dragSourceId = panelId;`
  - Line 396: `if (!dragSourceId) return;` → `if (!state.dragSourceId) return;`
  - Line 414: `if (!isDragging) return;` — keep as-is, but add guard above it
  - Line 422: `if (newTargetId !== dragTargetId)` — keep as-is (local `dragTargetId` is fine, it's only visual feedback)
  - Line 434: `if (!dragSourceId) return;` → `if (!state.dragSourceId) return;`
  - Line 437: `if (isDragging)` — keep as-is
  - Line 447: `if (targetId && targetId !== dragSourceId)` → `if (targetId && targetId !== state.dragSourceId)`
  - Line 449: `const prevSource = state.panels.find(p => p.id === dragSourceId)` → use `state.dragSourceId`
  - Line 452: `swapPanelAssignments(state, dragSourceId, targetId, ...)` → use `state.dragSourceId`
  - Line 456: `sourceId: dragSourceId` → use `state.dragSourceId`
  - Line 473: `onPanelSelected(dragSourceId)` → use `state.dragSourceId`
  - Line 487: `if (isDragging || dragSourceId)` → use `state.dragSourceId`
  - Line 314 (in `_clearDragState`): `dragSourceId = null` → `state.dragSourceId = null`

- Add guard to `_onPointerMove` (after line 396):
  ```javascript
  _onPointerMove(e) {
      if (!state.dragSourceId) return;

      // Skip hit testing during active multi-touch gesture —
      // prevents dragTargetId from updating and triggering visual feedback
      // or setting up a wrong swap target.
      if (state._multiTouchGestureActive) return;

      // ... rest of handler
  ```

#### 2. MultiTouchHandler.js — Clear `state.dragSourceId` on gesture start

**File:** `MyESModules/Interaction/MultiTouchHandler.js`

**Changes:**
- In `startGesture()` (line 145), after `state._multiTouchGestureActive = true;` add:
  ```javascript
  state._multiTouchGestureActive = true;
  // Clear any drag state PanelSwap may have set on the first finger's
  // pointerdown (which occurred before this two-finger gesture existed).
  // Prevents PanelSwap from performing an unintended swap when a finger lifts.
  state.dragSourceId = null;
  ```

- In `_onPointerCancel()` (line 283), after `state._multiTouchGestureActive = false;` add:
  ```javascript
  state._multiTouchGestureActive = false;
  state.dragSourceId = null; // Safety net: clear drag state on gesture cancellation
  ```

#### 3. createCollageData.js — Add `dragSourceId` to initial state

**File:** `MyESModules/App/createCollageData.js`

**Changes:** Add `dragSourceId: null` to the state object (near other interaction state fields like `_multiTouchGestureActive`).

#### 4. createCollageLifecycle.js — No changes needed

PanelSwap and MultiTouchHandler both receive the same `state` reference (the Vue instance). No wiring changes needed.

---

### Affected Files

| File | Change |
|------|--------|
| `MyESModules/Interaction/PanelSwap.js` | Replace local `dragSourceId` with `state.dragSourceId`; add `_multiTouchGestureActive` guard in `_onPointerMove` |
| `MyESModules/Interaction/MultiTouchHandler.js` | Clear `state.dragSourceId` in `startGesture()` and `_onPointerCancel()` |
| `MyESModules/App/createCollageData.js` | Add `dragSourceId: null` to initial state |

### Testability

- **Unit tests:** Verify `state.dragSourceId` is `null` after `startGesture()` with two touch pointers. Verify PanelSwap `_onPointerMove` returns early when `_multiTouchGestureActive` is true. Verify PanelSwap `_onPointerUp` returns early when `state.dragSourceId` is null.
- **Integration test:** Simulate two-finger gesture: pointerdown(1) → pointerdown(2) → pointermove → pointerup(1) → pointerup(2). Verify no swap occurs.
- **Playwright E2E:** Cannot reliably simulate two-finger touch gestures. Real-device validation required.
- **Regression:** Verify single-finger panel swap still works: pointerdown → drag to different panel → pointerup should swap.

### Manual Verification

- On real iOS/Android device: two-finger pan across panel boundaries — no swap should occur.
- On real iOS/Android device: pinch-to-zoom with one finger crossing panel boundary — no swap should occur.
- On desktop: single-finger drag-to-swap still works correctly.
- On desktop: no regression in panel selection (click), title drag, or trackpad gestures.

---

## Additional Investigation Notes

### Why the original fix was insufficient

The mobile touch enhancements plan (2026-07-29) correctly identified that `_multiTouchGestureActive` needed to be set synchronously at gesture start. This was implemented and works for preventing PanelSwap from starting a NEW drag on the second finger. However, the plan did not account for the drag state established by the FIRST finger's pointerdown, which occurs BEFORE the two-finger gesture exists.

### Why pointer capture doesn't help

Both handlers call `setPointerCapture()` on the same canvas for the same pointer (finger 1). The last caller wins, but since both are the same element (the canvas), this is a no-op. Pointer capture ensures events stay on the canvas even when fingers leave bounds — it does NOT prevent both handlers from receiving the same events.

### Why the `_onPointerUp` guard doesn't work

MultiTouchHandler's `_onPointerUp` clears `_multiTouchGestureActive` BEFORE PanelSwap's `_onPointerUp` fires (same event, synchronous, MultiTouchHandler registered first). By the time PanelSwap checks the flag, it's already false. The only way to prevent the swap is to ensure `dragSourceId` is null when `_onPointerUp` runs — which requires clearing it at gesture start, not at gesture end.

### Coordinate scaling discrepancy (not related to this bug)

GestureHandler uses `Math.min(scaleX, scaleY)` for aspect-ratio-preserving coordinate conversion, while PanelSwap uses independent `scaleX` and `scaleY`. This means hit testing in letterboxed areas could produce incorrect logical coordinates. This is a pre-existing issue unrelated to the swap-during-gesture bug, but worth noting for future coordinate consistency work.
