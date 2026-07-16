# Wheel Event `preventDefault()` — Stricter Conditional Guard

## Date
2026-07-12

## Context

Fixing Issue #1 from the pre-merge review: `_onWheel` in `MultiTouchHandler.js` called `preventDefault()` unconditionally after the `selectedPanelId` guard. This blocked page scrolling when a panel was selected but the wheel event had no actionable deltas (e.g., single-finger mouse scroll over canvas).

## What We Learned

### The Two-Level Conditional Pattern

Wheel event handlers need **two levels** of conditional `preventDefault()`, stricter than TouchEvent/PointerEvent handlers:

1. **Level 1 (activation):** Is there a selected panel? If not, return early (no interception).
2. **Level 2 (action):** Are there actual pan or zoom deltas? If not, return without calling `preventDefault()`.

The TouchEvent pattern only needs Level 1 because `startGesture()` returning false naturally prevents `preventDefault()`. But wheel events fire continuously (even with zero deltas), so Level 2 is mandatory.

```javascript
function _onWheel(e) {
    const panelId = state.selectedPanelId;
    if (!panelId) return;  // Level 1: no panel = no interception

    let hasAction = false;

    if (e.deltaY !== 0 || e.deltaX !== 0) {
        cropManager.adjustCrop(panelId, { ... });
        hasAction = true;
    }

    if (zoomDelta !== 0) {
        cropManager.zoomCrop(panelId, factor);
        hasAction = true;
    }

    if (hasAction) {  // Level 2: only suppress if we actually did something
        e.preventDefault();
    }
}
```

### The `ctrlKey + deltaY` Zoom Fallback

Not all platforms deliver pinch-to-zoom as `deltaZ`. Some (particularly Windows with certain mice) use `ctrlKey + deltaY` instead. The handler should check both:

```javascript
let zoomDelta = 0;
if (e.deltaZ !== 0) {
    zoomDelta = e.deltaZ;  // macOS trackpad
} else if (e.ctrlKey && e.deltaY !== 0) {
    zoomDelta = e.deltaY;  // Cross-platform fallback
}
```

### Edge Case: `ctrlKey` with Zero Deltas

When `ctrlKey` is true but all deltas (`deltaX`, `deltaY`, `deltaZ`) are zero, the handler should NOT call `preventDefault()`. Otherwise it would block the browser's default zoom behavior.

**Test case:** `WheelEvent { deltaX: 0, deltaY: 0, deltaZ: 0, ctrlKey: true }` → `preventDefault` NOT called, `zoomCrop` NOT called.

### `deltaMode` Consideration (Deferred)

Wheel events have a `deltaMode` property: `0` (pixels), `1` (lines), `2` (pages). A `DOM_DELTA_PAGE` event could theoretically slip through with non-zero values that represent page-scale scrolls rather than pixel-level pans. The current code doesn't guard against this, but in practice it's extremely rare on canvas elements. If observed, add a guard: `if (e.deltaMode > WheelEvent.DOM_DELTA_LINE) return;`

## Files Changed

- `MyESModules/Interaction/MultiTouchHandler.js` — `_onWheel` function
- `MyComponents/MultiTouchHandlerTest.html` — 5 new tests
- `.opencode/skills/building-web-apps/references/interaction.md` — updated wheel event example and preventDefault section

## Related

- Skill reference: `building-web-apps/references/interaction.md` — "Wheel Event Handling" and "preventDefault After Gesture Check" sections
- Plan: `_agent_docs/plans/2026-07-12-pre-merge-review-fixes.md` — Phase 1
