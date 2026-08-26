# Panel Swap During Multitouch — Bug Fix Plan

**Date:** 2026-08-01
**Source:** `_agent_docs/specifications/change-requests/2026-08-01-01-panel-swap-during-multitouch.md`
**Predecessor:** `2026-07-29-mobile-touch-enhancements.md` (PointerEvents migration + zoom sensitivity)

## Overview

After the mobile touch enhancements (PointerEvents migration + zoom sensitivity fix) were deployed, pinch-to-zoom pacing is correct. However, panels still swap unexpectedly when a two-finger pinch or pan gesture crosses panel boundaries. This plan fixes the incomplete coordination between `PanelSwap` and `MultiTouchHandler`: `dragSourceId` is set by the first finger's `pointerdown` (before a two-finger gesture exists), persists through the gesture, and causes an unintended swap when a finger lifts.

The fix moves `dragSourceId` from PanelSwap's local closure to `state.dragSourceId`, allowing MultiTouchHandler to clear it at gesture start. A complementary guard on `_onPointerMove` prevents `dragTargetId` from updating during active gestures.

## Current State Analysis

### Root Cause

The `_multiTouchGestureActive` guard in PanelSwap's `_onPointerDown` (line 364) prevents a **new** drag from starting when a gesture is active. But it does NOT clear the drag state established by the **first** finger's `pointerdown`, which fires **before** the two-finger gesture exists.

**Event trace:**
1. Finger 1 down on Panel A → MultiTouchHandler: `activePointers.size = 1` (no gesture). PanelSwap: `_multiTouchGestureActive` is false → sets `dragSourceId = 'panel-A'`.
2. Finger 2 down → MultiTouchHandler: `activePointers.size = 2` → `startGesture()` sets `_multiTouchGestureActive = true`. PanelSwap: `_multiTouchGestureActive` is now true → returns early. **But `dragSourceId` is still `'panel-A'`.**
3. Fingers move across panels → PanelSwap `_onPointerMove`: `dragSourceId` is set → updates `dragTargetId` to whichever panel the pointer is over. **No guard against active gesture.**
4. Finger 1 lifts → MultiTouchHandler: `activePointers.size < 2` → `endGesture()` sets `_multiTouchGestureActive = false`. PanelSwap `_onPointerUp`: `_multiTouchGestureActive` is now false (cleared by MultiTouchHandler in same synchronous event). `dragSourceId` is set. `isDragging` is true. Hit test returns current panel. If different from `dragSourceId` → **SWAP EXECUTES**.

### Key Discoveries

1. **`dragSourceId` is a local closure variable** in `createPanelSwapHandler` (PanelSwap.js line 261). MultiTouchHandler has no way to clear it.
2. **`state._multiTouchGestureActive` is shared state** — already used by PanelSwap (line 364) and TitleInteraction (line 223) as a guard.
3. **`state.dragTargetId` already exists** on shared state (createCollageData.js line 99). Moving `dragSourceId` alongside it is consistent with existing patterns.
4. **Handler attach order** in `createCollageLifecycle.js`: MultiTouchHandler (line 186-197) attaches before PanelSwap (line 260). MultiTouchHandler handlers fire BEFORE PanelSwap handlers for each event.
5. **`endGesture()` clears `_multiTouchGestureActive`** (MultiTouchHandler.js line 203) — this is why guarding `_onPointerUp` with the flag doesn't work (MultiTouchHandler clears it before PanelSwap's handler runs).
6. **`_onPointerCancel()` also clears `_multiTouchGestureActive`** (MultiTouchHandler.js line 295) — safety net for gesture cancellation.
7. **`_clearDragState()`** (PanelSwap.js lines 298-316) clears `dragSourceId`, `dragTargetId`, `isDragging`, `_dragStartCoords`, and releases pointer capture. Called on `_onPointerUp` and global `window.pointerup`.
8. **`startGesture()`** (MultiTouchHandler.js lines 140-149) is the exact insertion point — it runs synchronously in the second finger's `pointerdown` event, after `_multiTouchGestureActive` is set.
9. **No template bindings for `dragSourceId`** — it's only read/written by interaction handlers. No Vue reactivity concern.

### Why Other Approaches Don't Work

| Approach | Problem |
|----------|---------|
| Guard `_onPointerUp` with `_multiTouchGestureActive` | MultiTouchHandler clears the flag in its `_onPointerUp` BEFORE PanelSwap's `_onPointerUp` fires (same event, synchronous, registered first) |
| Guard only `_onPointerMove` | Prevents `dragTargetId` from updating, but doesn't prevent the swap on `pointerup` since `dragSourceId` persists |
| Callback-based cleanup (Solution B) | Works, but adds callback wiring. Shared state (Solution A) is simpler and consistent with existing patterns |
| Pointer capture conflict | Both handlers call `setPointerCapture()` on the same element — last caller wins, but no-op since same element |

## Desired End State

After this fix:
- Two-finger pinch/pan across panel boundaries does NOT trigger a panel swap
- Single-finger drag-to-swap continues to work correctly
- Single-finger click-to-select continues to work correctly
- `dragTargetId` is NOT updated during active multi-touch gestures (no incorrect visual feedback)
- `dragSourceId` is cleared when a two-finger gesture starts, and on gesture cancellation

## What We're NOT Doing

1. **NOT changing the handler attach order** — MultiTouchHandler before PanelSwap is correct and enables the fix.
2. **NOT adding a new callback parameter** — Shared state is sufficient and consistent with existing patterns.
3. **NOT modifying the crop swap logic** — `swapPanelAssignments` and `adaptCropToPanelAspect` are unaffected.
4. **NOT addressing the coordinate scaling discrepancy** noted in the change request (independent `scaleX`/`scaleY` vs `Math.min(scaleX, scaleY)`) — pre-existing issue, out of scope.
5. **NOT adding Playwright multi-touch simulation** — Playwright cannot reliably simulate two-finger gestures. Real-device validation required.
6. **NOT modifying TitleInteraction** — It already has its own `_multiTouchGestureActive` guard (line 223) and is unaffected by this bug.

## Implementation Approach

Single-phase, single-commit change. The modifications are tightly coupled (~20 lines across 3 files) and must be applied atomically — partial migration of `dragSourceId` from closure to state would leave the codebase in a broken state.

**Execution order:**
1. Add `dragSourceId: null` to initial state (createCollageData.js)
2. Replace local `dragSourceId` with `state.dragSourceId` in PanelSwap.js (~12 replacements)
3. Add `state.dragSourceId = null` in `startGesture()` (MultiTouchHandler.js)
4. Add `state.dragSourceId = null` in `_onPointerCancel()` (MultiTouchHandler.js)
5. Add `_multiTouchGestureActive` guard to `_onPointerMove` (PanelSwap.js)

## Phase 1: Fix Panel Swap During Multitouch (P0)

### Overview

Move `dragSourceId` from PanelSwap's closure to shared state, clear it at gesture start and cancellation, and guard `_onPointerMove` against active gestures. This eliminates the stale drag state that causes unintended swaps.

### Changes Required:

#### 1. createCollageData.js — Add `dragSourceId` to initial state

**File**: `MyESModules/App/createCollageData.js`

**Changes**: After line 99 (`dragTargetId: null,`), add:
```javascript
// Drag source (for panel swap coordination with MultiTouchHandler)
dragSourceId: null,
```

**Rationale**: `dragSourceId` needs to exist on the Vue instance so both PanelSwap and MultiTouchHandler can read/write it. Placing it next to `dragTargetId` maintains consistency.

#### 2. PanelSwap.js — Replace local `dragSourceId` with `state.dragSourceId`

**File**: `MyESModules/Interaction/PanelSwap.js`

**Changes**:

a. Remove local declaration (line 261):
```javascript
// REMOVE: let dragSourceId = null;
```

b. Replace all references to `dragSourceId` with `state.dragSourceId`:

| Line | Current | Replacement |
|------|---------|-------------|
| 390 | `dragSourceId = panelId;` | `state.dragSourceId = panelId;` |
| 396 | `if (!dragSourceId) return;` | `if (!state.dragSourceId) return;` |
| 435 | `if (!dragSourceId) return;` | `if (!state.dragSourceId) return;` |
| 447 | `targetId !== dragSourceId)` | `targetId !== state.dragSourceId)` |
| 449 | `p => p.id === dragSourceId)` | `p => p.id === state.dragSourceId)` |
| 452 | `swapPanelAssignments(state, dragSourceId, targetId, ...)` | `swapPanelAssignments(state, state.dragSourceId, targetId, ...)` |
| 456 | `sourceId: dragSourceId` | `sourceId: state.dragSourceId` |
| 473 | `onPanelSelected(dragSourceId)` | `onPanelSelected(state.dragSourceId)` |
| 487 | `if (isDragging || dragSourceId)` | `if (isDragging || state.dragSourceId)` |
| 313 | `dragSourceId = null;` (in `_clearDragState`) | `state.dragSourceId = null;` |

c. Add `_multiTouchGestureActive` guard to `_onPointerMove` (after line 396):
```javascript
_onPointerMove(e) {
    if (!state.dragSourceId) return;

    // Skip hit testing during active multi-touch gesture —
    // prevents dragTargetId from updating and triggering visual feedback
    // or setting up a wrong swap target.
    if (state._multiTouchGestureActive) return;

    // ... rest of handler (unchanged)
```

**Rationale**: Moving `dragSourceId` to state enables MultiTouchHandler to clear it. The `_onPointerMove` guard prevents `dragTargetId` from updating during gestures, eliminating incorrect visual feedback (panel highlight on wrong panel).

#### 3. MultiTouchHandler.js — Clear `state.dragSourceId` on gesture start and cancellation

**File**: `MyESModules/Interaction/MultiTouchHandler.js`

**Changes**:

a. In `startGesture()` (after line 145, after `state._multiTouchGestureActive = true;`):
```javascript
state._multiTouchGestureActive = true;
// Clear any drag state PanelSwap may have set on the first finger's
// pointerdown (which occurred before this two-finger gesture existed).
// Prevents PanelSwap from performing an unintended swap when a finger lifts.
state.dragSourceId = null;
```

b. In `_onPointerCancel()` (after line 295, after `state._multiTouchGestureActive = false;`):
```javascript
state._multiTouchGestureActive = false;
state.dragSourceId = null; // Safety net: clear drag state on gesture cancellation
```

**Rationale**: Clearing `dragSourceId` at gesture start ensures PanelSwap has no stale drag state. The cancellation cleanup is a safety net for `pointercancel` events (device rotation, system interrupt).

#### 4. createCollageLifecycle.js — No changes needed

PanelSwap and MultiTouchHandler both receive the same `state` reference (the Vue instance). No wiring changes needed.

### BDD Scenarios

#### User Behavior

| # | Given | When | Then |
|---|-------|------|------|
| 1.1.1 | Two images loaded in a 2-panel layout, panel selected | User performs two-finger pinch-to-zoom and one finger crosses into the other panel | No panel swap occurs; only zoom is applied |
| 1.1.2 | Two images loaded, panel selected | User performs two-finger pan across panel boundaries | No panel swap occurs; only pan is applied |
| 1.1.3 | Two images loaded, no gesture active | User drags from panel A to panel B with one finger | Panels swap correctly (regression check) |
| 1.1.4 | Two images loaded | User taps panel A without dragging | Panel A is selected, no swap occurs (regression check) |
| 1.1.5 | Two images loaded, panel selected, user starts single-finger drag on panel A | Before moving more than 10px, user places second finger down | Drag state is cancelled; no swap occurs when fingers lift |

#### Component Behavior — PanelSwap

| # | Given | When | Then |
|---|-------|------|------|
| 1.2.1 | `state.dragSourceId` is `'panel-0'` | External code sets `state.dragSourceId = null` | `_onPointerMove` returns early (no hit testing, no `dragTargetId` update) |
| 1.2.2 | `state.dragSourceId` is `'panel-0'` | External code sets `state.dragSourceId = null` | `_onPointerUp` returns early (no swap, no selection) |
| 1.2.3 | `state.dragSourceId` is `'panel-0'`, `state._multiTouchGestureActive` is `true` | `pointermove` fires over panel-1 | `dragTargetId` is NOT updated, `onTargetHovered` NOT called |
| 1.2.4 | `state.dragSourceId` is `'panel-0'`, `state._multiTouchGestureActive` is `false` | `pointermove` fires over panel-1 (after drag threshold) | `dragTargetId` updates to `'panel-1'`, `onTargetHovered` called with `'panel-1'` |
| 1.2.5 | `state.dragSourceId` is `'panel-0'` | `_clearDragState()` called | `state.dragSourceId` is `null` |
| 1.2.6 | `state.dragSourceId` is `'panel-0'`, drag in progress | `window.dispatchEvent(pointerup)` (outside canvas) | `state.dragSourceId` is `null` (global cleanup works) |
| 1.2.7 | `state.dragSourceId` set via `pointerdown`, `_multiTouchGestureActive` is `false` | Full drag: down → move (exceeds threshold) → move to panel-1 → up | Swap performed, `onSwapPerformed` called with correct IDs |
| 1.2.8 | No gesture active | `pointerdown` on panel → `pointerup` at same location | `onPanelSelected` called, no swap |

#### Component Behavior — MultiTouchHandler

| # | Given | When | Then |
|---|-------|------|------|
| 1.3.1 | `state.dragSourceId` is `'panel-0'`, `state._multiTouchGestureActive` is `false` | Two `pointerdown` events trigger `startGesture()` | `state.dragSourceId` is `null`, `state._multiTouchGestureActive` is `true` |
| 1.3.2 | `state.dragSourceId` is `null` | Two `pointerdown` events trigger `startGesture()` | No error, `state._multiTouchGestureActive` is `true` |
| 1.3.3 | Gesture active, `state.dragSourceId` is `null` | `pointercancel` fires | `state.dragSourceId` remains `null`, `state._multiTouchGestureActive` is `false` |
| 1.3.4 | Gesture active, `state.dragSourceId` is `null` | One pointer lifts, `endGesture()` called | `state.dragSourceId` remains `null` (no side effect) |

#### Integration — Cross-Handler Coordination

| # | Given | When | Then |
|---|-------|------|------|
| 1.4.1 | Both handlers attached to same canvas, same state, panels with images | `pointerdown(1)` on panel-A → `pointerdown(2)` → `pointermove` (fingers cross panels) → `pointerup(1)` → `pointerup(2)` | No swap performed. Image assignments unchanged. |
| 1.4.2 | Both handlers attached, `dragSourceId` not set before gesture | `pointerdown(1)` → `pointerdown(2)` → `pointermove` → `pointerup(1)` → `pointerup(2)` | No swap. No error. |
| 1.4.3 | Both handlers attached, PanelSwap sets `state.dragSourceId` on first finger | Second finger down triggers `startGesture()` | `state.dragSourceId` is immediately `null` |
| 1.4.4 | Two-finger gesture completes (both fingers lifted) | New single-finger drag from panel-A to panel-B | Swap performs correctly |
| 1.4.5 | Gesture active, fingers moving | `pointercancel` fires on one pointer | No swap on subsequent `pointerup`. State clean. |
| 1.4.6 | Both handlers attached | Two-finger gesture, fingers cross panel boundaries | `onTargetHovered` NOT called with new panel IDs (visual feedback suppressed) |

#### Pure Function Behavior

| # | Given | When | Then |
|---|-------|------|------|
| 1.5.1 | `swapPanelAssignments` called with valid state, sourceId, targetId | — | Swaps `imageIndex` and `panelAssignments` (unchanged — pure function) |
| 1.5.2 | `swapPanelAssignments` called with `sourceId === targetId` | — | Returns `false`, no state mutation (unchanged) |

### Success Criteria:

#### Automated Verification:
- [ ] `PanelSwapTest.html` — All existing tests pass (regression)
- [ ] `PanelSwapTest.html` — New test: `state.dragSourceId` used instead of local closure variable
- [ ] `PanelSwapTest.html` — New test: `_onPointerMove` returns early when `_multiTouchGestureActive` is `true`
- [ ] `PanelSwapTest.html` — New test: `_onPointerUp` returns early when `state.dragSourceId` is `null`
- [ ] `PanelSwapTest.html` — New test: `_clearDragState` clears `state.dragSourceId`
- [ ] `PanelSwapTest.html` — New test: global `window.pointerup` cleans up `state.dragSourceId`
- [ ] `PanelSwapTest.html` — New test: single-finger drag-to-swap still works (regression)
- [ ] `PanelSwapTest.html` — New test: click-to-select still works (regression)
- [ ] `MultiTouchHandlerTest.html` — All existing tests pass (regression)
- [ ] `MultiTouchHandlerTest.html` — New test: `startGesture()` clears `state.dragSourceId`
- [ ] `MultiTouchHandlerTest.html` — New test: `startGesture()` does not error when `dragSourceId` is already `null`
- [ ] `MultiTouchHandlerTest.html` — New test: `_onPointerCancel()` clears `state.dragSourceId`
- [ ] `PanelSwapMultiTouchIntegrationTest.html` — New file: two-finger gesture does NOT swap (the bug scenario)
- [ ] `PanelSwapMultiTouchIntegrationTest.html` — New file: gesture start clears pre-existing `dragSourceId`
- [ ] `PanelSwapMultiTouchIntegrationTest.html` — New file: gesture end restores normal swap behavior
- [ ] `PanelSwapMultiTouchIntegrationTest.html` — New file: `pointercancel` during gesture prevents swap
- [ ] `PanelSwapMultiTouchIntegrationTest.html` — New file: `dragTargetId` not updated during gesture
- [ ] Full test suite: `node scripts/run-tests.js` passes

#### Manual Verification:
- [ ] On real iOS device: two-finger pan across panel boundaries — no swap
- [ ] On real iOS device: pinch-to-zoom with one finger crossing panel boundary — no swap
- [ ] On real Android device: two-finger pan and pinch-to-zoom — no swap
- [ ] On desktop: single-finger drag-to-swap works correctly
- [ ] On desktop: single-finger click-to-select works correctly
- [ ] On desktop: no regression in panel selection, title drag, or trackpad gestures
- [ ] On desktop: no visual feedback glitch (panel highlight) during two-finger gestures

---

## Testing Strategy

### Unit Tests

**Existing test files to update:**

**`MyComponents/PanelSwapTest.html`** — Add new `describe` block:
```
describe('PanelSwap — dragSourceId state coordination', () => {
  // 8 new tests covering:
  // - state.dragSourceId used instead of local closure
  // - _onPointerMove guarded by _multiTouchGestureActive
  // - _onPointerUp returns early when state.dragSourceId is null
  // - _clearDragState clears state.dragSourceId
  // - global window.pointerup cleans up state.dragSourceId
  // - single-finger drag-to-swap regression
  // - click-to-select regression
})
```

**`MyComponents/MultiTouchHandlerTest.html`** — Add new `describe` block:
```
describe('MultiTouchHandler — dragSourceId coordination', () => {
  // 3 new tests covering:
  // - startGesture clears state.dragSourceId
  // - startGesture does not error when dragSourceId is null
  // - _onPointerCancel clears state.dragSourceId
})
```

**New test file: `MyComponents/PanelSwapMultiTouchIntegrationTest.html`** — Integration tests:
```
describe('PanelSwap + MultiTouchHandler — cross-handler coordination', () => {
  // 6 new tests covering:
  // - Two-finger gesture does NOT swap (the bug scenario)
  // - Two-finger gesture with no initial drag — no swap
  // - Gesture start clears pre-existing dragSourceId
  // - Gesture end restores normal swap behavior
  // - pointercancel during gesture prevents swap
  // - dragTargetId not updated during gesture (visual feedback suppressed)
})
```

**Test harness setup for integration tests:**
```javascript
// Both handlers share the same canvas and state
const canvas = document.createElement('canvas');
canvas.id = 'integration-canvas';
// ... mount to DOM ...

const state = {
    panels: [/* panels with rect geometry */],
    panelAssignments: new Map(),
    _multiTouchGestureActive: false,
    dragSourceId: null,
    crops: new Map(),
    images: [/* mock images */]
};

const swapHandler = createPanelSwapHandler({
    canvasId: 'integration-canvas',
    state: state,
    onSwapPerformed: () => { swapPerformed = true; },
    // ... other callbacks
});

const multiTouchHandler = createMultiTouchHandler({
    canvasId: 'integration-canvas',
    cropManager: { adjustCrop: () => {}, zoomCrop: () => {}, getPanelImage: () => ({ width: 1920, height: 1080 }) },
    state: state,
    onCropPreviewRender: () => {},
    onRenderScheduled: () => {}
});

// CRITICAL: MultiTouchHandler attaches FIRST (as in production)
multiTouchHandler.attach();
swapHandler.attach();
```

### E2E Tests (Playwright)

Playwright cannot reliably simulate two-finger touch gestures. An E2E test can verify the **state-level fix** via `page.evaluate()`:

**New test in `tests/e2e/workflow-tests.spec.cjs`** (or new spec file):
```javascript
test('panel swap not triggered during simulated two-finger gesture', async ({ page }) => {
    // Load page, upload images, then use page.evaluate() to:
    // 1. Record initial panel assignments
    // 2. Dispatch pointer event sequence on canvas:
    //    pointerdown(1) → pointerdown(2) → pointermove → pointerup(1) → pointerup(2)
    // 3. Assert panel assignments unchanged
});

test('single-finger drag-to-swap still works (regression)', async ({ page }) => {
    // Load page, upload images, use page.mouse to:
    // 1. Drag from panel A to panel B
    // 2. Assert swap occurred
});
```

### Manual Testing Steps

1. **iOS Safari (iPhone):**
   - Load page, upload 2+ images
   - Select a panel
   - Two-finger pan across panel boundaries → verify NO swap
   - Pinch-to-zoom with one finger crossing panel boundary → verify NO swap
   - Single-finger drag from panel A to panel B → verify swap works
   - Single-finger tap on panel → verify selection works

2. **Chrome for Android:**
   - Same steps as iOS

3. **Desktop browser (Chrome/Firefox/Safari):**
   - Single-finger drag-to-swap → verify works
   - Single-finger click-to-select → verify works
   - Trackpad two-finger pan/zoom → verify no regression
   - Title drag → verify no regression

### Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | Integration 1.4.1 (two-finger gesture does NOT swap), Unit 1.3.1 (startGesture clears dragSourceId), Unit 1.2.1 (PanelSwap respects state.dragSourceId) | Core bug fix — if these fail, the bug is not fixed |
| **P1** | Integration 1.4.4 (gesture end restores swap), Unit 1.2.7 (single-finger swap regression), Unit 1.2.8 (click regression) | Structural correctness — ensures existing behavior is preserved |
| **P2** | Integration 1.4.5 (pointercancel), Integration 1.4.6 (dragTargetId suppressed), Unit 1.2.3 (_onPointerMove guard), Unit 1.3.3 (pointercancel cleanup) | Robustness and polish — edge cases and visual feedback |

---

## Known Behaviors and Edge Cases

### dragSourceId on Shared State

1. **No Vue reactivity needed**: `dragSourceId` is not bound in the template. It's only read/written by interaction handlers. No reactivity dependency exists.
2. **No naming collision**: `dragSourceId` is not a common property name. No other module reads or writes it.
3. **No persistence concern**: `dragSourceId` is not part of `SettingsPersistence.js`. It's transient interaction state.
4. **Initial state**: Adding `dragSourceId: null` to `createCollageData.js` ensures the property exists from the start. Without it, `state.dragSourceId = null` in `startGesture()` would create the property dynamically, which is safe but less clean.

### Timing Edge Cases

5. **Rapid finger-down sequence**: Finger 1 down → PanelSwap sets `state.dragSourceId` → Finger 2 down → MultiTouchHandler's `startGesture` clears `state.dragSourceId`. All synchronous in the same event loop tick. **Works correctly.**
6. **Finger 2 down on different panel**: Finger 1 on panel-A, finger 2 on panel-B. PanelSwap's `_onPointerDown` for finger 2 returns early (gesture active). `dragSourceId` cleared by `startGesture`. **Correct behavior.**
7. **Finger lifted while over different panel**: During gesture, finger moves from panel-A to panel-B. Finger lifts. `_onPointerUp` sees `state.dragSourceId === null` → returns early. **Correct behavior.**

### State Edge Cases

8. **`dragSourceId` is `undefined` (not in state)**: Before the fix, `createCollageData.js` doesn't include `dragSourceId`. MultiTouchHandler's `state.dragSourceId = null` would create the property. **Safe**, but adding to initial state is cleaner.
9. **Multiple rapid gesture cycles**: Gesture starts → cleared → ends → new single-finger drag → swap. **Works** — `dragSourceId` is properly set/cleared through normal flow.
10. **TitleInteraction active during multi-touch**: `titleInteractionMode` is set, `_multiTouchGestureActive` becomes true, `dragSourceId` is cleared. All three handlers coordinate. **No regression** — each handler checks its own guard.

### Cleanup Edge Cases

11. **`pointercancel` fires on first pointer**: Gesture was active, `dragSourceId` was already cleared by `startGesture`. `_onPointerCancel` sets it to null again. **Idempotent — safe.**
12. **Handler detach during active drag**: `detach()` calls `_clearDragState()` which sets `state.dragSourceId = null`. **Correct.**
13. **Window blur during gesture**: MultiTouchHandler's blur handler calls `endGesture()` which sets `_multiTouchGestureActive = false` but does NOT clear `dragSourceId`. However, `dragSourceId` was already cleared by `startGesture`. **Safe.**

---

## Performance Considerations

1. **State property access vs closure variable**: `state.dragSourceId` is a property lookup on the Vue instance. Closure variable `dragSourceId` was a direct local reference. The difference is negligible — both are O(1) lookups.
2. **No additional render cycles**: The `_onPointerMove` guard prevents unnecessary `dragTargetId` updates during gestures, which actually reduces render calls.
3. **No memory impact**: One additional property on the Vue data object.

---

## Migration Notes

- The change is backward compatible — no public API changes. `createPanelSwapHandler` and `createMultiTouchHandler` accept the same parameters.
- The `dragSourceId` property on state is internal — not part of any documented API.
- Rollback: revert the 3 files. No data migration needed.

---

## References

- Change request: `_agent_docs/specifications/change-requests/2026-08-01-01-panel-swap-during-multitouch.md`
- Predecessor plan: `_agent_docs/plans/2026-07-29-mobile-touch-enhancements.md`
- Source files:
  - `MyESModules/Interaction/PanelSwap.js` (lines 258-493: `createPanelSwapHandler`)
  - `MyESModules/Interaction/MultiTouchHandler.js` (lines 140-149: `startGesture`, lines 283-303: `_onPointerCancel`)
  - `MyESModules/App/createCollageData.js` (line 99: `dragTargetId: null`)
  - `MyESModules/App/createCollageLifecycle.js` (lines 186-260: handler attach order)
- Test files:
  - `MyComponents/PanelSwapTest.html` (existing test patterns, lines 527-1018: DOM-based handler tests)
  - `MyComponents/MultiTouchHandlerTest.html` (existing test patterns, lines 615-808: two-pointer gesture tests)
- Skill references: `building-web-apps` skill — multi-touch gestures, pointer capture lifecycle, global pointerup cleanup, handler `.call(this)`, closure safety
