# Pre-Merge Review — Final Consolidated — 2026-07-12

## Summary

Consolidated findings from three independent reviews (Peter, Hugo, Tony) against the current staged changes. All issues have been verified against the actual source code.

---

## Confirmed Issues

### 1. `MultiTouchHandler._onWheel` — `preventDefault()` blocks all wheel scrolling unconditionally (Medium) ✅ CONFIRMED

**File:** `MyESModules/Interaction/MultiTouchHandler.js`, line 329

`e.preventDefault()` fires immediately after the `selectedPanelId` guard, before checking whether there are actual deltas to process. When a panel is selected, **every** wheel event on the canvas is consumed — including single-finger mouse scroll or trackpad scroll where the user intends to scroll the page.

**Fix:** Gate `preventDefault()` behind a check for actual deltas:

```javascript
const hasPan = e.deltaY !== 0 || e.deltaX !== 0;
const hasZoom = e.deltaZ !== 0 || (e.ctrlKey && e.deltaY !== 0);
if (!hasPan && !hasZoom) return;

e.preventDefault();
```

**Impact:** Blocks normal page scroll when a panel is selected. Most impactful issue for real users.

---

### 2. `CollageAssembler` — Hex drag target drawn after selection border (Minor) ✅ CONFIRMED

**File:** `MyESModules/Rendering/CollageAssembler.js`, lines 76-82

Render order: hover (4) → selection (5) → hex drag target (5b) → debug overlay (6). The hex drag target highlight draws **on top** of the selection border. If the drag target is the same panel as the selected panel, the dashed blue line obscures the white selection border.

**Fix:** Move hex drag target draw to step 4b (after hover, before selection) so the selection indicator remains the topmost UI chrome.

**Impact:** Visual — selection border obscured during hex drag-and-drop.

---

### 3. `HexPanelSwap` + `MultiTouchHandler` — PointerEvent conflict on canvas (Low-Medium) ✅ CONFIRMED

**Files:** `MyESModules/Interaction/HexPanelSwap.js`, `MyESModules/Interaction/MultiTouchHandler.js`

Both handlers attach `pointerdown`/`pointermove`/`pointerup`/`pointercancel` listeners to the same canvas element. `HexPanelSwap._onPointerDown` does NOT call `e.preventDefault()`, so the event propagates to `MultiTouchHandler`. If two non-touch pointers (e.g., dual stylus) arrive during a hex layout drag, `MultiTouchHandler` starts a gesture while `HexPanelSwap` is mid-drag and both handlers will compete.

Note: `HexPanelSwap` does guard activation with `state.layoutStyle !== LayoutStyle.HEXAGONAL` (line 152), so it only activates for hex layout. However, `MultiTouchHandler` does not check layout style and will activate regardless.

**Fix options:**
- Have `HexPanelSwap` call `e.preventDefault()` when it records a drag source.
- Have `MultiTouchHandler` check `state.layoutStyle === LayoutStyle.HEXAGONAL` and skip pointer gesture activation during hex layout.

**Impact:** Edge case — requires two-pointer non-touch input during hex layout drag.

---

### 4. `HexagonalLayout` — Comment accuracy for `R_grid` scaling (Low) ✅ CONFIRMED

**File:** `MyESModules/Layout/HexagonalLayout.js`, lines 55-56

The comment says "preventing overlap", but the actual effect is proportional spacing. The hexagon radius `R` is `(sqrt(3)/2 * R_eff - spacing/2) * hexSizeMultiplier`, while the center-to-center distance uses `R_grid = R_eff * hexSizeMultiplier`. These diverge as `spacing` grows, meaning larger multipliers create more space between hexagons rather than preventing overlap.

**Fix:** Update the comment to accurately describe the behavior:

> "Scale grid spacing by the same multiplier so center positions move apart proportionally with hexagon size, maintaining consistent relative spacing across multipliers."

**Impact:** Documentation only — the math is correct for the intended behavior.

---

### 5. `MultiTouchHandler._onPointerDown` — Incomplete pointer capture for multi-pointer gestures (Low-Medium) ✅ CONFIRMED

**File:** `MyESModules/Interaction/MultiTouchHandler.js`, lines 273-278

When `activePointers.size === 2`, `canvas.setPointerCapture(e.pointerId)` is only called for the *second* pointer (the one that fired the current event). The first pointer was added during its own `pointerdown` event when `activePointers.size === 1`, and was never captured.

If the first pointer moves outside the canvas bounds, the browser may stop sending `pointermove` events for that pointer ID to the canvas, causing the gesture to stall.

**Fix:** When the gesture starts, iterate over all active pointers and call `setPointerCapture` for each:

```javascript
for (const ptrId of activePointers.keys()) {
    canvas.setPointerCapture(ptrId);
}
```

**Impact:** Affects multi-pointer gestures on stylus+touch hybrid devices if the first pointer leaves the canvas.

---

### 6. `MultiTouchHandler` — Missing `releasePointerCapture` (Low) ✅ CONFIRMED

**File:** `MyESModules/Interaction/MultiTouchHandler.js`, lines 297-319

In `_onPointerUp` and `_onPointerCancel`, the handler clears state but does not call `canvas.releasePointerCapture(pointerId)` for any captured pointers.

**Fix:** In both cleanup paths, explicitly release pointer capture for all active pointers before clearing:

```javascript
if (canvas && canvas.releasePointerCapture) {
    try {
        for (const ptrId of activePointers.keys()) {
            canvas.releasePointerCapture(ptrId);
        }
    } catch (_) { /* not all browsers support */ }
}
```

**Impact:** Minor — browsers eventually release capture, but explicit release ensures cleaner state.

---

### 7. `createUndoMethods` — Potential stale render callbacks (Low) ⚠️ CONFIRMED (theoretical)

**File:** `MyESModules/App/createUndoMethods.js`, lines 13-14

The render callbacks (`onRenderScheduled`, `onCropPreviewRender`) are captured from the `callbacks` object at factory creation time. If the composition layer ever replaces these callbacks without recreating the undo methods, the undo manager will use stale references.

**Current status:** Not a live bug — `createCollageMethods` creates them in a fixed order and doesn't replace them dynamically. However, this is a fragility in the architecture.

**Fix:** Pass a callback provider function or look up callbacks from `base` at call time rather than capturing them as closure constants.

**Impact:** Theoretical — no current code path triggers this, but protects against future refactoring mistakes.

---

## Summary Table

| # | Issue | Severity | Action Required |
|---|-------|----------|-----------------|
| 1 | `_onWheel` unconditional `preventDefault()` | **Medium** | Gate `preventDefault()` behind delta checks |
| 2 | Hex drag target render order | **Minor** | Move to step 4b (before selection) |
| 3 | HexPanelSwap / MultiTouchHandler pointer conflict | **Low-Medium** | Add `e.preventDefault()` in HexPanelSwap or layout style check in MultiTouchHandler |
| 4 | `HexagonalLayout` comment accuracy | **Low** | Update comment to reflect "proportional spacing" |
| 5 | Incomplete pointer capture in `_onPointerDown` | **Low-Medium** | Capture all active pointers on gesture start |
| 6 | Missing `releasePointerCapture` | **Low** | Explicitly release capture on gesture end |
| 7 | Stale undo callbacks | **Low** | Use provider function for callbacks |

---

## Recommendation

**Block Merge** on Issue #1. The unconditional `preventDefault()` in `_onWheel` is a user-facing regression that blocks normal page scrolling when a panel is selected.

Issues #2 and #3 should also be resolved before merging — they affect visual correctness and interaction stability respectively.

Issues #4, #5, #6, and #7 are lower priority and can be addressed in follow-up commits, though #5 and #6 are related to the same gesture system and worth fixing together.
