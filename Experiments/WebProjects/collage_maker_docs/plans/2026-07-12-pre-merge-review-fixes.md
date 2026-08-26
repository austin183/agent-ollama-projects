# Pre-Merge Review Bug Fixes Implementation Plan

## Overview

Addresses 7 confirmed issues from the consolidated pre-merge review (`2026-07-12-pre-merge-review-final.md`). Fixes span interaction handling (wheel events, pointer capture, handler coordination), render ordering, documentation accuracy, and callback architecture robustness.

**Block-merge item:** Issue #1 — unconditional `preventDefault()` in `_onWheel` blocks page scrolling when a panel is selected.

## Current State Analysis

| # | Issue | File | Lines | Severity |
|---|-------|------|-------|----------|
| 1 | `_onWheel` unconditional `preventDefault()` | `MultiTouchHandler.js` | 329 | **Medium** — blocks page scroll |
| 2 | Hex drag target drawn after selection border | `CollageAssembler.js` | 76-82 | **Minor** — visual layering |
| 3 | HexPanelSwap / MultiTouchHandler pointer conflict | `HexPanelSwap.js`, `MultiTouchHandler.js` | multiple | **Low-Medium** — handler competition |
| 4 | `HexagonalLayout` comment inaccuracy | `HexagonalLayout.js` | 55-56 | **Low** — docs only |
| 5 | Incomplete pointer capture in `_onPointerDown` | `MultiTouchHandler.js` | 273-278 | **Low-Medium** — off-canvas gesture loss |
| 6 | Missing `releasePointerCapture` | `MultiTouchHandler.js` | 297-319 | **Low** — stale capture state |
| 7 | Stale undo render callbacks | `createUndoMethods.js` | 13-14 | **Low** — theoretical fragility |

### Key Discoveries

- **D1**: `_onWheel` line 329 calls `e.preventDefault()` before any delta check. A wheel event with zero deltas (e.g., single-finger mouse scroll over canvas with panel selected) is consumed unconditionally.
- **D2**: CollageAssembler render order is: hover(4) → selection(5) → hex drag target(5b) → debug(6). The hex drag target draws on top of the selection border.
- **D3**: Both `HexPanelSwap` and `MultiTouchHandler` attach `pointerdown`/`pointermove`/`pointerup`/`pointercancel` to the same canvas. `HexPanelSwap` guards with `layoutStyle !== HEXAGONAL` but `MultiTouchHandler` does not. In hexagonal layout, both handlers fire for pointer events.
- **D4**: `setPointerCapture` is called only when `activePointers.size === 2` (the second pointer). The first pointer is never captured, so it loses events if dragged off-canvas.
- **D5**: `createUndoMethods` captures `onRenderScheduled` and `onCropPreviewRender` as closure constants at factory creation. If callers ever replace these references, undo uses stale callbacks. Currently only one caller (`createCollageMethods.js` line 46-49), so no live bug.

## Desired End State

1. Wheel events only call `preventDefault()` when there is actual pan or zoom delta to process
2. Hex drag target highlight renders before selection border (visually underneath)
3. MultiTouchHandler pointer path skips in hexagonal layout, avoiding conflict with HexPanelSwap
4. HexagonalLayout comment accurately describes proportional spacing behavior
5. Both pointers in a two-pointer gesture are captured at their respective `pointerdown` events
6. Pointer captures are explicitly released on gesture end and cancel
7. Undo callbacks use provider functions for service lookup at call time

### Key Discoveries:
- **D1** `MultiTouchHandler.js:329` — `preventDefault()` fires unconditionally after `selectedPanelId` guard
- **D2** `CollageAssembler.js:76-82` — hex drag target at step 5b, after selection at step 5
- **D3** `MultiTouchHandler.js:258` — `_onPointerDown` has no layout-style guard; `HexPanelSwap.js:152` does
- **D4** `MultiTouchHandler.js:273-278` — `setPointerCapture` inside `size === 2` block only
- **D5** `createUndoMethods.js:13-14` — callbacks captured as closure constants

## What We're NOT Doing

- NOT adding a new pointer event architecture (event bus, mediator pattern) — the existing layout-gated delegation is sufficient
- NOT modifying the TouchEvent path — it has no pointer capture concept and is unaffected
- NOT changing the WheelEvent path for pointer capture — wheel events have no pointer IDs
- NOT refactoring `createCollageLifecycle.js` — undo callback wiring there is out of scope
- NOT adding Playwright E2E tests — all 7 fixes have unit test coverage in existing test files
- NOT modifying `HexDragHandler` pointer event listener registration — only adding a guard in MultiTouchHandler

## Implementation Approach

Group fixes by coupling: wheel event isolation (Phase 1), visual + interaction correctness (Phase 2), pointer capture hygiene (Phase 3), documentation + architecture (Phase 4). Each phase is independently testable and reversible.

---

## Phase 1: Wheel Event `preventDefault()` Guard (Issue #1 — P0)

### Overview

Gate `preventDefault()` in `_onWheel` behind a check for actual pan or zoom deltas. If no deltas are present, the handler returns without consuming the event, allowing normal page scrolling.

### Changes Required:

#### 1. `MultiTouchHandler.js` — Conditional `preventDefault()`
**File**: `MyESModules/Interaction/MultiTouchHandler.js`
**Lines**: 325-363

Replace the `_onWheel` function. Move `preventDefault()` to fire only after confirming at least one action (pan or zoom) occurred:

```javascript
function _onWheel(e) {
    const panelId = state.selectedPanelId;
    if (!panelId) return;

    const imageScale = estimateImageScale(panelId);
    let needsRender = false;
    let hasAction = false;

    // --- Pan: two-finger drag produces deltaY/deltaX ---
    if (e.deltaY !== 0 || e.deltaX !== 0) {
        cropManager.adjustCrop(panelId, {
            x: e.deltaX * WHEEL_PAN_SENSITIVITY * imageScale,
            y: e.deltaY * WHEEL_PAN_SENSITIVITY * imageScale
        });
        needsRender = true;
        hasAction = true;
    }

    // --- Zoom: pinch-to-zoom produces deltaZ (macOS) or ctrlKey + deltaY ---
    let zoomDelta = 0;
    if (e.deltaZ !== 0) {
        zoomDelta = e.deltaZ;
    } else if (e.ctrlKey && e.deltaY !== 0) {
        zoomDelta = e.deltaY;
    }

    if (zoomDelta !== 0) {
        const factor = Math.exp(-zoomDelta * WHEEL_ZOOM_SENSITIVITY);
        cropManager.zoomCrop(panelId, factor);
        needsRender = true;
        hasAction = true;
    }

    // Only suppress browser default if we actually processed a gesture
    if (hasAction) {
        e.preventDefault();
    }

    if (needsRender) {
        onCropPreviewRender();
    }
}
```

### BDD Scenarios — Phase 1

#### User Behavior

| # | Given | When | Then |
|---|-------|------|------|
| 1.1.1 | A panel is selected, non-hex layout | User scrolls page with mouse wheel over canvas (single finger, no pinch) | Page scrolls normally; `preventDefault()` NOT called |
| 1.1.2 | A panel is selected, non-hex layout | User performs two-finger trackpad pan over canvas | Canvas crop adjusts; `preventDefault()` IS called |
| 1.1.3 | A panel is selected, non-hex layout | User performs pinch-to-zoom on trackpad over canvas | Canvas crop zooms; `preventDefault()` IS called |

#### Component Behavior (MultiTouchHandler)

| # | Given | When | Then |
|---|-------|------|------|
| 1.2.1 | `selectedPanelId` set, handler attached | `WheelEvent` with `deltaX=0, deltaY=0, deltaZ=0` dispatched | `preventDefault` NOT called, `adjustCrop` NOT called, `zoomCrop` NOT called |
| 1.2.2 | `selectedPanelId` set, handler attached | `WheelEvent` with `deltaY=10, deltaX=0, deltaZ=0` dispatched | `preventDefault` called, `adjustCrop` invoked with y-delta |
| 1.2.3 | `selectedPanelId` set, handler attached | `WheelEvent` with `deltaX=15, deltaY=0, deltaZ=0` dispatched | `preventDefault` called, `adjustCrop` invoked with x-delta |
| 1.2.4 | `selectedPanelId` set, handler attached | `WheelEvent` with `deltaZ=-10, deltaX=0, deltaY=0` dispatched | `preventDefault` called, `zoomCrop` invoked with factor > 1.0 |
| 1.2.5 | `selectedPanelId` set, handler attached | `WheelEvent` with `deltaY=10, deltaZ=-10` (both pan and zoom) | `preventDefault` called once, both `adjustCrop` and `zoomCrop` invoked |

### Success Criteria — Phase 1

#### Automated Verification:
- [ ] `MultiTouchHandlerTest.html` — new test: "wheel event with all zero deltas does not call preventDefault"
- [ ] `MultiTouchHandlerTest.html` — new test: "wheel event with pan delta calls preventDefault and adjustCrop"
- [ ] `MultiTouchHandlerTest.html` — new test: "wheel event with zoom delta calls preventDefault and zoomCrop"
- [ ] `MultiTouchHandlerTest.html` — new test: "wheel event with both pan and zoom deltas calls preventDefault once"
- [ ] All existing tests pass: `node scripts/run-tests.js`
- [ ] Existing test "wheel event with deltaY triggers pan" still asserts `preventDefault` was called (regression guard)

#### Manual Verification:
- [ ] Open app, load images, select a panel, scroll mouse wheel over canvas — page scrolls normally
- [ ] Two-finger trackpad pan over canvas — crop adjusts, page does not scroll
- [ ] Pinch-to-zoom on trackpad over canvas — crop zooms, page does not scroll
- [ ] No panel selected, scroll over canvas — page scrolls normally (existing behavior preserved)

---

## Phase 2: Render Order + Pointer Coordination (Issues #2, #3 — P1)

### Overview

Two independent fixes: correct the hex drag target render order so the selection border stays on top, and prevent MultiTouchHandler from competing with HexPanelSwap for pointer events in hexagonal layout.

### Changes Required:

#### 1. `CollageAssembler.js` — Move hex drag target to step 4b
**File**: `MyESModules/Rendering/CollageAssembler.js`
**Lines**: 57-82

Move the hex drag target block (currently step 5b, lines 76-82) to between hover (step 4) and selection (step 5):

```javascript
// 3. Panels
panelRenderer.drawPanels(ctx, panels, images, crops, panelAssignments);

// 4. Hover highlight (drawn before selection so selection is on top)
if (hoveredPanelId && panels && hoveredPanelId !== selectedPanelId) {
    const hoveredPanel = panels.find(p => p.id === hoveredPanelId);
    if (hoveredPanel) {
        panelRenderer.drawHoverBorder(ctx, hoveredPanel);
    }
}

// 4b. Hex drag target highlight (before selection so selection is on top)
if (hexDragTargetId && panels) {
    const targetPanel = panels.find(p => p.id === hexDragTargetId);
    if (targetPanel) {
        panelRenderer.drawHexDragTarget(ctx, targetPanel);
    }
}

// 5. Selection highlight
if (selectedPanelId && panels) {
    const selectedPanel = panels.find(p => p.id === selectedPanelId);
    if (selectedPanel) {
        panelRenderer.drawSelectionBorder(ctx, selectedPanel);
    }
}

// 6. Debug overlay (between selection and blend-mode overlay)
// ... rest unchanged
```

#### 2. `MultiTouchHandler.js` — Layout-style guard on pointer path
**File**: `MyESModules/Interaction/MultiTouchHandler.js`
**Lines**: 258-280

Add a layout-style guard at the top of `_onPointerDown` to skip pointer-based two-finger gestures in hexagonal layout. In hex layout, users can still use the TouchEvent path (touchscreen) or WheelEvent path (trackpad) for pan/zoom. The PointerEvent two-pointer path is primarily for Windows precision touchpads, and hex layout interactions are managed exclusively by HexPanelSwap.

```javascript
// At top of file, add import:
import { LayoutStyle } from '../Models/LayoutStyle.js';

// In _onPointerDown, after pointerType guard:
function _onPointerDown(e) {
    // Skip touch pointers — delegate to TouchEvent path
    if (e.pointerType === 'touch') return;

    // In hexagonal layout, skip pointer-based two-finger gestures to avoid
    // conflict with HexDragHandler. Users can still use wheel events (trackpad)
    // or touch events (touchscreen) for pan/zoom.
    if (state.layoutStyle === LayoutStyle.HEXAGONAL) return;

    // ... rest of existing code unchanged
}
```

### BDD Scenarios — Phase 2

#### User Behavior

| # | Given | When | Then |
|---|-------|------|------|
| 2.1.1 | Hex layout, panel B is selected, user drags from panel A toward panel B | Panel B becomes the hex drag target | Dashed blue drag target border visible on panel B, white selection border drawn on top |
| 2.1.2 | Hex layout, user puts two fingers on canvas | Two-finger gesture does NOT trigger hex drag | Hex drag handler remains idle; no `dragSourceId` set by MultiTouchHandler |

#### Component Behavior (CollageAssembler)

| # | Given | When | Then |
|---|-------|------|------|
| 2.2.1 | `hexDragTargetId` and `selectedPanelId` both set to same panel ID | `asm.render()` called | `drawHexDragTarget` called before `drawSelectionBorder` |
| 2.2.2 | `hexDragTargetId` set to panel-A, `selectedPanelId` set to panel-B | `asm.render()` called | Both borders drawn; selection border for panel-B is topmost |
| 2.2.3 | Only `hexDragTargetId` set, no `selectedPanelId` | `asm.render()` called | Only hex drag target border drawn |

#### Component Behavior (MultiTouchHandler pointer path)

| # | Given | When | Then |
|---|-------|------|------|
| 2.3.1 | `layoutStyle === LayoutStyle.HEXAGONAL`, handler attached | `PointerEvent` (pointerType='mouse') dispatched to canvas | Handler returns early; no state change, no `preventDefault` called |
| 2.3.2 | `layoutStyle === LayoutStyle.UNIFORM`, handler attached | `PointerEvent` (pointerType='mouse') dispatched | Handler processes normally (existing behavior preserved) |

### Success Criteria — Phase 2

#### Automated Verification:
- [ ] `RenderingTest.html` — new test: "hex drag target rendered before selection border" (verify call order via spy)
- [ ] `MultiTouchHandlerTest.html` — new test: "pointer events skipped in hexagonal layout"
- [ ] `MultiTouchHandlerTest.html` — new test: "pointer events processed normally in non-hex layout" (regression guard)
- [ ] All existing tests pass: `node scripts/run-tests.js`

#### Manual Verification:
- [ ] Hex layout, select a panel, drag from another panel — selection border visible on top of drag target border
- [ ] Hex layout, two-finger gesture does not interfere with hex drag-and-drop
- [ ] Non-hex layout, two-finger pointer gesture still works (regression check)

---

## Phase 3: Pointer Capture Hygiene (Issues #5, #6 — P2)

### Overview

Capture each pointer at its own `pointerdown` event (not just the second), and explicitly release captures on gesture end and cancel. This prevents gesture loss when pointers leave canvas bounds and avoids stale capture state.

### Changes Required:

#### 1. `MultiTouchHandler.js` — Capture each pointer on `pointerdown`
**File**: `MyESModules/Interaction/MultiTouchHandler.js`
**Lines**: 258-280

Move `setPointerCapture` outside the `size === 2` block. Capture every pointer when it goes down:

```javascript
function _onPointerDown(e) {
    if (e.pointerType === 'touch') return;
    if (state.layoutStyle === LayoutStyle.HEXAGONAL) return;

    activePointers.set(e.pointerId, { clientX: e.clientX, clientY: e.clientY });

    // Capture this pointer so events continue if cursor leaves canvas
    if (canvas && canvas.setPointerCapture) {
        try {
            canvas.setPointerCapture(e.pointerId);
        } catch (_) { /* not all browsers support */ }
    }

    if (activePointers.size === 2) {
        const pointers = [...activePointers.values()];
        if (!startGesture(pointers[0], pointers[1])) {
            activePointers.clear();
            return;
        }
        e.preventDefault();
        pointerGestureActive = true;
    }
}
```

#### 2. `MultiTouchHandler.js` — Release captures on gesture end
**File**: `MyESModules/Interaction/MultiTouchHandler.js`
**Lines**: 297-319

Add `releasePointerCapture` calls in `_onPointerUp` and `_onPointerCancel`:

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

function _onPointerCancel(e) {
    if (e.pointerType === 'touch') return;

    // Release capture for this pointer
    if (canvas && canvas.releasePointerCapture) {
        try { canvas.releasePointerCapture(e.pointerId); } catch (_) {}
    }

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

### BDD Scenarios — Phase 3

#### User Behavior

| # | Given | When | Then |
|---|-------|------|------|
| 3.1.1 | Two-finger gesture active, first finger drags off canvas edge | First pointer leaves canvas bounds | Gesture continues smoothly (pointer captured) |
| 3.1.2 | Two-finger gesture ends (one finger lifted) | User lifts one finger | No stale pointer capture; subsequent clicks work normally |

#### Component Behavior (MultiTouchHandler)

| # | Given | When | Then |
|---|-------|------|------|
| 3.2.1 | Handler attached, canvas supports `setPointerCapture` | First `pointerdown` (pointerId=1) dispatched | `setPointerCapture(1)` called on canvas |
| 3.2.2 | First pointer captured, second `pointerdown` (pointerId=2) dispatched | Second pointer goes down | `setPointerCapture(2)` called on canvas; both pointers captured |
| 3.2.3 | Two pointers captured, gesture active | `pointerup` for pointerId=1 | `releasePointerCapture(1)` called, gesture ends, remaining pointer released |
| 3.2.4 | Two pointers captured, gesture active | `pointercancel` dispatched | Both captures released, gesture state cleared |
| 3.2.5 | Canvas does NOT support `setPointerCapture` | `pointerdown` dispatched | No exception thrown (try/catch guard) |

### Success Criteria — Phase 3

#### Automated Verification:
- [x] `MultiTouchHandlerTest.html` — new test: "first pointer captured on pointerdown"
- [x] `MultiTouchHandlerTest.html` — new test: "pointer capture released on pointerup"
- [x] `MultiTouchHandlerTest.html` — new test: "pointer captures released on pointercancel"
- [x] `MultiTouchHandlerTest.html` — new test: "setPointerCapture failure does not throw"
- [x] `MultiTouchHandlerTest.html` — new test: "second pointer also captured on pointerdown (both pointers captured)"
- [x] `MultiTouchHandlerTest.html` — new test: "releasePointerCapture failure does not throw (try/catch guard)"
- [x] All existing tests pass: `node scripts/run-tests.js` (55/55 in MultiTouchHandlerTest)

#### Manual Verification:
- [ ] Two-finger gesture on canvas, drag first finger off canvas — gesture continues
- [ ] End gesture, click elsewhere on page — click works normally (no stale capture)
- [ ] Test on browser without `setPointerCapture` support — no console errors

---

## Phase 4: Documentation + Callback Architecture (Issues #4, #7 — P2)

### Overview

Two independent fixes: update the HexagonalLayout comment to accurately describe proportional spacing, and refactor undo callbacks to use provider functions for future-proofing.

### Changes Required:

#### 1. `HexagonalLayout.js` — Comment accuracy
**File**: `MyESModules/Layout/HexagonalLayout.js`
**Lines**: 55-57

Replace the comment above `R_grid`:

```javascript
    // R_eff is the base grid spacing derived from canvas size and ring count.
    // R_grid applies the size multiplier to R_eff so center positions move apart
    // proportionally with hexagon size, maintaining consistent relative spacing
    // across multipliers.
    const R_grid = R_eff * hexSizeMultiplier;
```

#### 2. `createUndoMethods.js` — Provider function callbacks
**File**: `MyESModules/App/createUndoMethods.js`
**Lines**: 12-54

Refactor to accept provider functions that return render callbacks at call time:

```javascript
export function createUndoMethods(base, callbacks = {}) {
    const getOnRenderScheduled = callbacks.getOnRenderScheduled || (() => () => {});
    const getOnCropPreviewRender = callbacks.getOnCropPreviewRender || (() => () => {});

    function _updateUndoState(vm) {
        if (!base.undoManager) return;
        vm.canUndo = base.undoManager.canUndo();
        vm.canRedo = base.undoManager.canRedo();
    }

    function _performUndo(vm) {
        if (!base.undoManager || !base.undoManager.canUndo()) return;

        const hadUndo = base.undoManager.undo();
        if (!hadUndo) return;

        _updateUndoState(vm);
        getOnRenderScheduled()(vm);
        getOnCropPreviewRender()(vm);
    }

    function _performRedo(vm) {
        if (!base.undoManager || !base.undoManager.canRedo()) return;

        const hadRedo = base.undoManager.redo();
        if (!hadRedo) return;

        _updateUndoState(vm);
        getOnRenderScheduled()(vm);
        getOnCropPreviewRender()(vm);
    }

    return {
        _updateUndoState,
        _performUndo,
        _performRedo
    };
}
```

#### 3. `createCollageMethods.js` — Update callback wiring
**File**: `MyESModules/App/createCollageMethods.js`
**Lines**: 46-49

Update the caller to pass provider functions:

```javascript
const undoMethods = createUndoMethods(base, {
    getOnRenderScheduled: () => (vm) => renderMethods._scheduleRender(vm),
    getOnCropPreviewRender: () => (vm) => cropPreviewMethods._scheduleCropPreviewRender(vm)
});
```

### BDD Scenarios — Phase 4

#### Pure Function Behavior (HexagonalLayout)

| # | Given | When | Then |
|---|-------|------|------|
| 4.1.1 | `hexSizeMultiplier = 2.0` | `generateHexagonalLayout` called with 7 images | Center-to-center distance of ring-1 hex is ~2x the distance at `hexSizeMultiplier = 1.0` |
| 4.1.2 | `hexSizeMultiplier = 0.5` | `generateHexagonalLayout` called with 7 images | Center-to-center distance of ring-1 hex is ~0.5x the distance at `hexSizeMultiplier = 1.0` |

> Note: These behaviors already exist and are covered by tests 1.8.15 and 1.8.16 in `LayoutMathTest.html`. The comment fix is documentation-only, so no new tests are needed for Issue #4.

#### Component Behavior (createUndoMethods)

| # | Given | When | Then |
|---|-------|------|------|
| 4.2.1 | Undo methods created with provider callbacks | `_performUndo` called | Provider function invoked to get render callback, callback called with vm |
| 4.2.2 | Provider returns a different callback on each call | `_performUndo` called twice | Each call uses the latest callback from the provider |
| 4.2.3 | No provider callbacks provided (defaults) | `_performUndo` called | No error; no-op callbacks used |

### Success Criteria — Phase 4

#### Automated Verification:
- [x] `UndoManagerTest.html` — new test: "undo uses provider function for render callback" (4.2.1)
- [x] `UndoManagerTest.html` — new test: "redo uses provider function for render callback" (4.2.4)
- [x] `UndoManagerTest.html` — new test: "default callbacks are no-op (no error)" (4.2.3)
- [x] `UndoManagerTest.html` — new test: "provider returns a different callback on each call" (4.2.2)
- [x] `UndoManagerTest.html` — new test: "provider callback receives vm parameter" (4.2.5)
- [x] `UndoManagerTest.html` — new test: "provider returning non-function does not throw" (4.2.6)
- [x] All existing tests pass: `node scripts/run-tests.js` (28/28 in UndoManagerTest, 60/60 in Phase5RefactoringTest)
- [x] No change in observable undo/redo behavior (characterization: existing undo/redo tests still pass)

#### Manual Verification:
- [x] Undo/redo still works correctly for all actions (crop, swap, layout change)
- [x] No console errors after Phase 4 changes

---

## Testing Strategy

### Unit Tests (Mocha/Chai) — New Tests by File

| Test File | New Tests | Issues Covered |
|-----------|-----------|----------------|
| `MultiTouchHandlerTest.html` | 9 | #1 (4), #3 (1), #5 (1), #6 (3) |
| `RenderingTest.html` | 3 | #2 |
| `UndoManagerTest.html` | 3 | #7 |
| `LayoutMathTest.html` | 0 | #4 (documentation only — existing tests 1.8.15, 1.8.16 cover the math) |

**Total new tests: 15**

### E2E Tests (Playwright)

No new E2E tests required. The existing test suite covers panel selection, drag-and-drop, and undo/redo. The fixes are internal behavior corrections verified by unit tests.

### Manual Testing Steps

1. **Issue #1**: Open app, load images, select a panel. Scroll mouse wheel over canvas — page should scroll. Two-finger trackpad pan — crop should adjust.
2. **Issue #2**: Switch to hex layout, select a panel, drag from another panel onto the selected panel — selection border should be visible on top of the drag target border.
3. **Issue #3**: In hex layout, put two fingers on canvas — hex drag should NOT activate. Single-finger drag should still work normally.
4. **Issues #5, #6**: Two-finger gesture, drag first finger off canvas — gesture continues. Lift fingers, click elsewhere — click works normally.
5. **Issue #7**: Perform several actions, undo/redo multiple times — no errors, correct state restored.

### Priority Ordering

| Priority | Issues | Tests | Rationale |
|----------|--------|-------|-----------|
| **P0** | #1 | 4 | Core functionality — blocks page scroll, most impactful user-facing bug |
| **P1** | #2, #3 | 4 | Structural correctness — visual layering and interaction stability |
| **P2** | #4, #5, #6, #7 | 7 | Robustness and polish — pointer capture hygiene, documentation, future-proofing |

---

## Performance Considerations

- **No performance impact**: All changes are guard clauses (O(1) checks), render reordering (no new operations), or callback pattern changes (same call count)
- **Pointer capture**: Adding `setPointerCapture` on each `pointerdown` is a native browser call with negligible overhead
- **Layout check**: `state.layoutStyle === LayoutStyle.HEXAGONAL` is a string comparison, O(1)

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Two-finger pointer gesture broken in non-hex layout | Low | High | Existing tests cover non-hex pointer path; layout guard is early-return only |
| Hex drag broken after pointer guard | Low | Medium | Existing tests cover hex drag; only adding early-return in MultiTouchHandler |
| Wheel `preventDefault` change breaks trackpad pan | Low | Medium | `hasAction` flag ensures `preventDefault` fires when there IS delta |
| Provider callback pattern breaks undo | Very Low | Medium | Behavior-identical change; existing undo tests serve as characterization tests |
| `LayoutStyle` import creates circular dependency | Very Low | Low | `LayoutStyle` is a plain object module with no imports from Interaction layer |

---

## Module Interface Changes

### MultiTouchHandler.js
- **New import**: `LayoutStyle` from `../Models/LayoutStyle.js` — needed for layout-style gate
- **No API change**: Factory signature `createMultiTouchHandler({ canvasId, cropManager, state, onCropPreviewRender, onRenderScheduled })` unchanged
- **Internal behavior**: `_onWheel` conditional `preventDefault()`, `_onPointerDown` layout guard, `_onPointerDown` captures each pointer, `_onPointerUp`/`_onPointerCancel` release captures
- **Test exposure**: `_onPointerDown`, `_onWheel`, `_onPointerUp`, `_onPointerCancel` already exposed on handler object

### CollageAssembler.js
- **No API change**: `render()` method signature unchanged, only internal ordering modified
- **Test exposure**: Render order verified by spying on `panelRenderer` methods

### HexPanelSwap.js
- **No changes**: The conflict resolution is handled entirely in MultiTouchHandler

### createUndoMethods.js
- **API change**: Callbacks parameter shape changes from `{ onRenderScheduled, onCropPreviewRender }` to `{ getOnRenderScheduled, getOnCropPreviewRender }`
- **Breaking**: Caller in `createCollageMethods.js` must update to use provider functions
- **Mitigation**: Only one caller exists (`createCollageMethods.js` line 46-49), change is contained

### createCollageMethods.js
- **Change**: Lines 46-49 updated to pass provider functions instead of direct callbacks

---

## References

- Change request: `_agent_docs/specifications/change-requests/2026-07-12-pre-merge-review-final.md`
- World-review UX analysis: Issues prioritized by user frequency and impact
- Skill references:
  - `building-web-apps` → `references/interaction.md` — Pointer handler coordination, `setPointerCapture` gotchas, `preventDefault` ordering, wheel event handling
  - `building-web-apps` → `references/canvas-2d.md` — Render pipeline ordering
  - `building-web-apps` → `references/testing-unit.md` — Characterization tests before refactor
  - `building-web-apps` → `references/vue-options-api.md` — Callback injection for handler DIP
