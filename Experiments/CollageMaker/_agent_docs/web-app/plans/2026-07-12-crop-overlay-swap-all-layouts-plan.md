# Shaped Crop Overlay & Swap-in-All-Layouts Implementation Plan

## Overview

Two change requests to enhance CollageMaker's interaction model:

1. **Feature 1 — Shaped Crop Overlay** (CR from `2026-07-10-01`): Make the crop preview overlay match the exact geometric shape of each panel (triangles, trapezoids, hexagons, parallelograms) instead of always showing a rectangular crop box. Currently, a dashed shape hint is drawn on top of the rectangular crop rect, but the dark overlay, crop border, and handles are all rectangular.

2. **Feature 2 — Swap in All Layouts** (CR from `2026-07-12-02`): Extend the panel image swap (drag-and-drop) from the Hexagonal layout to all layouts. Currently, `HexPanelSwap.js` gates swap behind `LayoutStyle.HEXAGONAL`, and `GestureHandler` does not support drag-and-drop.

Per world-review analysis, **Feature 2 is lower risk** (state management + guard removal) and should be implemented before Feature 1 (Canvas 2D rendering changes with visual sensitivity).

## Current State Analysis

### Feature 1 — Crop Overlay Architecture

The crop preview canvas rendering pipeline (`createCropPreviewRenderer.js`):
1. Draws full image with "contain" scaling
2. Draws dark overlay (`rgba(0,0,0,0.55)`) as **4 rectangular rects** outside the crop rect (lines 92-100)
3. Draws white crop border via `ctx.strokeRect()` (lines 103-105)
4. Draws dashed shape overlay via `CropOverlayShape.drawShapeOverlay()` — semi-transparent fill + dashed stroke (lines 108-117)
5. Draws 4 white corner handle squares at crop rect corners (lines 120-130)

The crop data model (`CropInfo.js`) uses a **rectangular source rect** (`sourceRect: {x, y, width, height}`) regardless of panel shape. On the main canvas, `PanelRenderer._applyClip()` clips the image to the panel geometry. The crop rect is always rectangular in image space — the panel shape is a visual clip applied during rendering.

**Key files:**
- `MyESModules/App/createCropPreviewRenderer.js` — crop preview rendering (135 lines)
- `MyESModules/Layout/CropOverlayShape.js` — shape overlay math + drawing (87 lines)
- `MyESModules/Interaction/CropInteraction.js` — crop drag/resize interaction (376 lines)
- `MyESModules/Rendering/PanelRenderer.js` — main canvas panel rendering (196 lines)

### Feature 2 — Swap Architecture

The current pointer event coordination uses **layout-gated delegation**:

| Handler | Layout Gate | Events | Purpose |
|---------|-------------|--------|---------|
| `HexDragHandler` (`HexPanelSwap.js`) | `if (layoutStyle !== HEXAGONAL) return` (line 152) | pointerdown/move/up | Drag-to-swap + click-to-select |
| `GestureHandler` (`GestureHandler.js`) | `if (layoutStyle === HEXAGONAL) return` (line 140, pointerdown only) | pointerdown/move/leave | Click-to-select + hover |
| `MultiTouchHandler` (`MultiTouchHandler.js`) | `if (layoutStyle === HEXAGONAL) return` (line 267, pointerdown only) | pointerdown/move/up, touch, wheel | Two-finger pan/zoom |

**Key discovery:** `swapPanelAssignments()` at `HexPanelSwap.js:17-35` is **already layout-agnostic** — it operates on generic `state.panels` and `state.panelAssignments`. The `_hitTestPanel` and `_pointInPanel` methods handle both rect and path geometries.

The swap visual feedback chain:
- State: `hexDragTargetId` in `createCollageData.js:78`
- Render: `createRenderMethods.js:48` passes `hexDragTargetId` to assembler
- Assembler: `CollageAssembler.js:70-75` calls `panelRenderer.drawHexDragTarget()`
- Renderer: `PanelRenderer.js:102-110` draws blue dashed border

**Key files:**
- `MyESModules/Interaction/HexPanelSwap.js` — swap logic + drag handler (265 lines)
- `MyESModules/Interaction/GestureHandler.js` — panel selection + hover (187 lines)
- `MyESModules/Interaction/MultiTouchHandler.js` — two-finger gestures (491 lines)
- `MyESModules/App/createCollageLifecycle.js` — handler wiring (322 lines)
- `MyESModules/App/createCollageData.js` — reactive state (102 lines)
- `MyESModules/App/createRenderMethods.js` — render state building (105 lines)

### Key Discoveries

- `swapPanelAssignments()` is a pure function that works with any panel geometry — no changes needed to swap logic.
- `_pointInPanel` in both `HexPanelSwap.js:131-148` and `GestureHandler.js:112-120` already handles rect and path geometries via ray-casting.
- `PanelRenderer._drawPanelBorder()` already supports both rect and path geometries (lines 128-150).
- `PolygonClipper.js` exists but is unused — not needed for this plan.
- The `_multiTouchGestureActive` flag pattern (from world-review) is the cleanest way to coordinate swap vs. multi-touch without layout-specific guards.

## Desired End State

### Feature 1
- For shaped panels (hexagonal, diagonal slices): the dark overlay in crop preview follows the panel shape boundary within the crop region, using Canvas 2D clip + `destination-out` compositing.
- The crop border follows the shape outline (not a rectangle).
- The shape overlay is more prominent (solid stroke, brighter fill).
- Corner handles remain at crop rect corners (crop is always rectangular in image space).
- For rect panels: behavior is identical to current (no regression).

### Feature 2
- Swap drag-and-drop works in all layouts (uniform, hero, mosaic, diagonal slices, hexagonal).
- State property renamed: `hexDragTargetId` → `dragTargetId`.
- Method renamed: `drawHexDragTarget` → `drawDragTarget`.
- File renamed: `HexPanelSwap.js` → `PanelSwap.js`; function renamed: `createHexDragHandler` → `createPanelSwapHandler`.
- Pointer coordination: swap handler always active, GestureHandler provides hover-only, MultiTouchHandler always active with gesture-active coordination.

## What We're NOT Doing

- **Feature 1**: No perspective transforms for parallelogram image mapping (the current clip-based rendering in `PanelRenderer._applyClip` is correct and sufficient). No change to the crop data model (`sourceRect` remains rectangular). No vertex-based resize handles for shaped panels. No change to `CropInteraction.js` interaction logic.
- **Feature 2**: No new state properties beyond renaming. No changes to `swapPanelAssignments()` logic. No keyboard-based swap interaction (out of scope — spec mentions it as a future consideration). No swap animation (spec mentions it as nice-to-have).
- **Both**: No E2E test implementation (specification only — `build-tdd` writes tests). No accessibility keyboard swap shortcuts.

## Implementation Approach

Implement Feature 2 first (lower risk, well-scoped), then Feature 1 (Canvas 2D changes, visual verification needed).

| Priority | Phase | Risk | Rationale |
|----------|-------|------|-----------|
| **P0** | Phase 2.1: PanelSwap refactoring | Low | Pure rename + guard removal, existing tests cover swap logic |
| **P0** | Phase 2.2: Pointer coordination | Low-Medium | Pointer event restructuring, follows existing patterns |
| **P0** | Phase 2.3: State + rendering rename | Low | Mechanical rename across call sites |
| **P1** | Phase 1.1: Shaped dark overlay | Medium | Canvas clip path, visual verification needed |
| **P1** | Phase 1.2: Enhanced shape overlay + border | Low | Styling change + conditional border drawing |

---

## Behavior Specifications

### Feature 2 — Swap in All Layouts

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 2.UB.1 | Images are loaded in Hero layout (2+ panels) | User drags from hero panel to side panel | Images swap positions in both panels |
| 2.UB.2 | Images are loaded in Uniform layout (4+ panels) | User drags from one grid cell to another | Images swap positions |
| 2.UB.3 | Images are loaded in Diagonal Slices layout | User drags from one parallelogram panel to another | Images swap positions |
| 2.UB.4 | Images are loaded in Hexagonal layout | User drags from one hexagon to another | Images swap positions (no regression) |
| 2.UB.5 | User drags from panel A to panel B in any layout | Blue dashed highlight appears on panel B during drag | Highlight disappears after drag ends |
| 2.UB.6 | User clicks (no drag) on a panel in any layout | Panel is selected and crop preview updates | No swap occurs |
| 2.UB.7 | User performs a swap, then presses Cmd+Z | Swap is undone | Original image assignments restored |

#### Component Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 2.CB.1 | `createPanelSwapHandler` is created with non-hex layout | `pointerdown` fires on a panel | Handler records `dragSourceId` (no early return) |
| 2.CB.2 | `createPanelSwapHandler` is created | `pointermove` exceeds DRAG_THRESHOLD | `isDragging` becomes true, `onDragStart` fires |
| 2.CB.3 | Drag is in progress | `pointermove` enters a different panel | `onTargetHovered(targetId)` fires, re-render scheduled |
| 2.CB.4 | Drag ends over a different panel | `pointerup` fires | `swapPanelAssignments()` called, `onSwapPerformed` fires |
| 2.CB.5 | `pointerdown` fires while `_multiTouchGestureActive` is true | Swap handler `_onPointerDown` runs | Handler returns early (no drag state recorded) |
| 2.CB.6 | `GestureHandler` receives `pointermove` | Cursor moves over a panel | `onHoverChanged(panelId)` fires |
| 2.CB.7 | `GestureHandler` receives `pointerdown` | — | **No longer handles pointerdown** (removed) |

#### Pure Function Behavior Scenarios

`swapPanelAssignments()` — no changes from existing tests.

| # | Given | When | Then |
|---|-------|------|------|
| 2.PF.1 | State with rect geometry panels | `swapPanelAssignments(state, 'panel-0', 'panel-1')` | Both `imageIndex` and `panelAssignments` swapped |
| 2.PF.2 | State with path geometry panels | `swapPanelAssignments(state, 'panel-0', 'panel-1')` | Both `imageIndex` and `panelAssignments` swapped |
| 2.PF.3 | Source ID equals target ID | `swapPanelAssignments(state, 'panel-0', 'panel-0')` | Returns false, state unchanged |

### Feature 1 — Shaped Crop Overlay

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 1.UB.1 | User selects a hexagonal panel | Crop preview renders | Dark overlay follows hexagon shape within crop region |
| 1.UB.2 | User selects a Diagonal Slices panel | Crop preview renders | Dark overlay follows parallelogram shape within crop region |
| 1.UB.3 | User selects a rectangular panel (Hero, Uniform, Mosaic) | Crop preview renders | Dark overlay is rectangular (no change from current) |
| 1.UB.4 | User pans the crop on a shaped panel | Image moves within crop region | Dark overlay shape remains fixed, image moves behind it |
| 1.UB.5 | User resizes the crop on a shaped panel | Crop rect changes size | Shape overlay scales with crop region, handles at rect corners |

#### Component Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 1.CB.1 | `createCropPreviewRenderer` renders a hex panel crop | Render executes | Canvas has shaped dark overlay (not 4 rects) |
| 1.CB.2 | `createCropPreviewRenderer` renders a rect panel crop | Render executes | Canvas has rectangular dark overlay (4 rects, unchanged) |
| 1.CB.3 | Shape overlay is drawn | `drawShapeOverlay(ctx, points)` called | Solid stroke (no dash), brighter fill (`rgba(255,255,255,0.18)`) |
| 1.CB.4 | Crop border is drawn for shaped panel | Render executes | Border follows shape outline (not `strokeRect`) |
| 1.CB.5 | Crop border is drawn for rect panel | Render executes | Border is rectangular `strokeRect` (unchanged) |

#### Pure Function Behavior Scenarios

`computeShapeOverlayPoints()` — no changes from existing tests.

| # | Given | When | Then |
|---|-------|------|------|
| 1.PF.1 | Path geometry with 3+ points, valid crop screen | `computeShapeOverlayPoints(geometry, cropScreen, 8)` | Returns array of [x,y] points within crop screen bounds |
| 1.PF.2 | Rect geometry | `computeShapeOverlayPoints(rectGeometry, cropScreen)` | Returns null |

---

## Phase 2.1: PanelSwap Refactoring

### Overview

Remove the hex-only guard from the drag handler, rename the file and exports, and keep the pure `swapPanelAssignments` function unchanged.

### Behavior Scenarios

#### Component Behavior

| # | Given | When | Then |
|---|-------|------|------|
| 2.1.CB.1 | `createPanelSwapHandler` is called | Factory returns handler object | Handler has `attach()`, `detach()`, `_clearDragState()`, `_hitTestPanel()`, `_pointInPanel()` |
| 2.1.CB.2 | Handler is attached, layout is `uniform` | `pointerdown` fires on a panel | `dragSourceId` is set (no layout guard blocks it) |
| 2.1.CB.3 | Handler is attached, layout is `hexagonal` | `pointerdown` fires on a panel | `dragSourceId` is set (no regression) |

#### Unit Test Scenarios

| # | Test | Input | Expected |
|---|------|-------|----------|
| 2.1.UT.1 | `swapPanelAssignments` with rect geometry panels | State with `type: 'rect'` panels | `imageIndex` swapped on both panels |
| 2.1.UT.2 | `swapPanelAssignments` with path geometry panels | State with `type: 'path'` panels | `imageIndex` swapped on both panels |
| 2.1.UT.3 | `swapPanelAssignments` with mixed geometry | State with rect + path panels | Swap works regardless of geometry type |
| 2.1.UT.4 | `createPanelSwapHandler` factory returns handler | Valid options object | Returns object with expected methods |

### Changes Required:

#### 1. Rename `HexPanelSwap.js` → `PanelSwap.js`

**File:** `MyESModules/Interaction/HexPanelSwap.js` → `MyESModules/Interaction/PanelSwap.js`

**Changes:**
- Rename file
- Remove `import { LayoutStyle } from '../Models/LayoutStyle.js';` (line 6)
- Rename `createHexDragHandler` → `createPanelSwapHandler` (line 53)
- Remove layout guard from `_onPointerDown` (lines 151-152):

```javascript
// BEFORE (lines 150-152):
_onPointerDown(e) {
    // Only handle hexagonal layout
    if (state.layoutStyle !== LayoutStyle.HEXAGONAL) return;

// AFTER:
_onPointerDown(e) {
    // Skip if multi-touch gesture is active (two-finger pan/zoom)
    if (state._multiTouchGestureActive) return;
```

- Update JSDoc comments to reference "panel swap" instead of "hex panel swap"

### Success Criteria:

#### Automated Verification:
- [ ] `HexPanelSwapTest.html` passes with updated import path
- [ ] New test: `swapPanelAssignments` works with rect geometry panels
- [ ] No import errors on page load

#### Manual Verification:
- [ ] Drag-and-drop swap works in hexagonal layout (no regression)
- [ ] Drag-and-drop swap works in hero layout (new capability)
- [ ] Click-to-select still works in all layouts

---

## Phase 2.2: Pointer Event Coordination

### Overview

Restructure pointer event coordination so the swap handler is always active for click-and-drag, GestureHandler provides hover-only, and MultiTouchHandler always active with gesture-active coordination.

### Behavior Scenarios

#### Component Behavior

| # | Given | When | Then |
|---|-------|------|------|
| 2.2.CB.1 | Swap handler and GestureHandler both attached | `pointerdown` fires on a panel | Swap handler processes it (records dragSourceId), GestureHandler does nothing |
| 2.2.CB.2 | Swap handler and GestureHandler both attached | `pointermove` fires over a panel | GestureHandler fires `onHoverChanged`, swap handler tracks drag if active |
| 2.2.CB.3 | MultiTouchHandler starts two-finger gesture | `_multiTouchGestureActive` flag set on state | Swap handler `_onPointerDown` returns early |
| 2.2.CB.4 | MultiTouchHandler ends gesture | `_multiTouchGestureActive` flag cleared | Swap handler resumes normal operation |
| 2.2.CB.5 | Swap handler attached, no drag in progress | `pointerup` fires | Click-to-select fires (`onPanelSelected`) |

#### Unit Test Scenarios

| # | Test | Input | Expected |
|---|------|-------|----------|
| 2.2.UT.1 | GestureHandler does not handle pointerdown | pointerdown event | No `onPanelSelected` call from GestureHandler |
| 2.2.UT.2 | GestureHandler still handles pointermove for hover | pointermove event over panel | `onHoverChanged` fires with panel ID |
| 2.2.UT.3 | GestureHandler still handles pointerleave | pointerleave event | `onHoverChanged` fires with null |
| 2.2.UT.4 | MultiTouchHandler sets `_multiTouchGestureActive` on gesture start | Two-finger touch start | `state._multiTouchGestureActive === true` |
| 2.2.UT.5 | MultiTouchHandler clears `_multiTouchGestureActive` on gesture end | Two-finger touch end | `state._multiTouchGestureActive === false` |
| 2.2.UT.6 | MultiTouchHandler pointerdown no longer guards on hex layout | pointerdown in hex layout | Handler processes event (no early return) |
| 2.2.UT.7 | Swap handler skips pointerdown when multi-touch active | `_multiTouchGestureActive === true` | `_onPointerDown` returns without recording drag |

### Changes Required:

#### 1. GestureHandler — Remove pointerdown handling

**File:** `MyESModules/Interaction/GestureHandler.js`

**Changes:**
- Remove `canvas.addEventListener('pointerdown', onPointerDown)` from `attach()` (line 39)
- Remove `canvas.removeEventListener('pointerdown', onPointerDown)` from `detach()` (line 56)
- Remove `_onPointerDown` method entirely (lines 138-152)
- Remove `onPointerDown = (e) => handler._onPointerDown(e)` from event binding (line 182)
- Remove `import { LayoutStyle } from '../Models/LayoutStyle.js';` (line 9) — no longer needed
- Keep `hitTestPanel`, `_pointInPanel`, `_pointInPolygon` (used by pointermove for hover)
- Keep `_onPointerMove` and `_onPointerLeave` unchanged

**Rationale:** The swap handler's `_onPointerUp` already handles click-to-select (line 243-247: `if (!isDragging) { onPanelSelected(dragSourceId); }`). Removing GestureHandler's pointerdown eliminates the double-selection risk.

#### 2. MultiTouchHandler — Remove hex guard, add gesture-active flag

**File:** `MyESModules/Interaction/MultiTouchHandler.js`

**Changes:**

Remove hex-only guard from `_onPointerDown` (line 267):
```javascript
// REMOVE this line:
if (state.layoutStyle === LayoutStyle.HEXAGONAL) return;
```

Add gesture-active state flag in `startGesture()`:
```javascript
function startGesture(t1, t2) {
    const panelId = state.selectedPanelId;
    if (!panelId) return false;

    gestureActive = true;
    state._multiTouchGestureActive = true;  // NEW: signal to swap handler
    initialMidpoint = computeTouchMidpoint(t1, t2);
    initialDistance = computeTouchDistance(t1, t2);
    return true;
}
```

Clear flag in `endGesture()`:
```javascript
function endGesture() {
    gestureActive = false;
    state._multiTouchGestureActive = false;  // NEW
    activeTouchIds = null;
    initialMidpoint = null;
    initialDistance = 0;
    onRenderScheduled();
}
```

Also clear flag in `_onPointerCancel` (line 340):
```javascript
if (gestureActive) {
    endGesture();
}
pointerGestureActive = false;
state._multiTouchGestureActive = false;  // NEW
```

Remove `import { LayoutStyle } from '../Models/LayoutStyle.js';` (line 17) if no longer used.

#### 3. createCollageLifecycle.js — Update handler wiring

**File:** `MyESModules/App/createCollageLifecycle.js`

**Changes:**
- Update import (line 16): `import { createPanelSwapHandler, swapPanelAssignments } from '../Interaction/PanelSwap.js';`
- Update handler creation (line 107): `this._panelSwapHandler = createPanelSwapHandler({...})`
- Update `onTargetHovered` callback (line 117): `this.dragTargetId = targetId;`
- Update undo label (line 123): `label: 'Swap Panels'`
- Update `beforeUnmount` (lines 257-259): `if (this._panelSwapHandler) { this._panelSwapHandler.detach(); }`

### Pointer Event Coordination Matrix (After Changes)

| Event | Swap Handler | GestureHandler | MultiTouchHandler |
|-------|-------------|----------------|-------------------|
| pointerdown | Always active (skips if `_multiTouchGestureActive`) | **Removed** | Always active (two-pointer only) |
| pointermove | Drag tracking + target hover | Always active (hover only) | Gesture processing |
| pointerup | Click-or-swap decision | **Removed** | Gesture end |
| pointerleave | N/A | Hover clear | N/A |
| touchstart/move/end | N/A | N/A | Always active |
| wheel | N/A | N/A | Always active |

### Success Criteria:

#### Automated Verification:
- [ ] `HexPanelSwapTest.html` passes with updated imports
- [ ] `MultiTouchHandlerTest.html` passes with new gesture-active flag tests
- [ ] `Phase3FollowUpTest.html` passes with updated imports
- [ ] No console errors on page load

#### Manual Verification:
- [ ] Hover highlight works in all layouts (no regression)
- [ ] Click-to-select works in all layouts (handled by swap handler)
- [ ] Drag-to-swap works in all layouts
- [ ] Two-finger pan/zoom works in all layouts (no regression)
- [ ] No double-selection on click
- [ ] No stuck drag state after two-finger gesture
- [ ] Swap undo works (Cmd+Z restores previous assignment)

---

## Phase 2.3: State + Rendering Rename

### Overview

Rename `hexDragTargetId` → `dragTargetId` in state and all call sites. Rename `drawHexDragTarget` → `drawDragTarget` in PanelRenderer.

### Behavior Scenarios

#### Component Behavior

| # | Given | When | Then |
|---|-------|------|------|
| 2.3.CB.1 | `dragTargetId` is set during drag | Assembler renders | `drawDragTarget` called on target panel |
| 2.3.CB.2 | `dragTargetId` equals `selectedPanelId` | Assembler renders | `drawDragTarget` is skipped (same-panel overlap guard) |
| 2.3.CB.3 | `dragTargetId` is null | Assembler renders | No drag target border drawn |

#### Unit Test Scenarios

| # | Test | Input | Expected |
|---|------|-------|----------|
| 2.3.UT.1 | Reactive state has `dragTargetId` initialized to null | `createCollageData()` called | `state.dragTargetId === null` |
| 2.3.UT.2 | `PanelRenderer.drawDragTarget` exists | `createPanelRenderer()` called | Method exists and is a function |
| 2.3.UT.3 | `drawDragTarget` draws blue dashed border on rect panel | Rect panel passed | `strokeStyle: '#4285f4'`, `lineDash: [6,4]` |
| 2.3.UT.4 | `drawDragTarget` draws blue dashed border on path panel | Path panel passed | Same style applied via `_drawPanelBorder` |
| 2.3.UT.5 | Assembler passes `dragTargetId` option | `asm.render()` called | No error, drag target rendered |

### Changes Required:

#### 1. `createCollageData.js` — Rename state property

**File:** `MyESModules/App/createCollageData.js`

**Changes** (line 77-78):
```javascript
// BEFORE:
// Hex drag target (for visual feedback during hex panel swap)
hexDragTargetId: null,

// AFTER:
// Drag target (for visual feedback during panel swap)
dragTargetId: null,
```

#### 2. `createRenderMethods.js` — Rename render option

**File:** `MyESModules/App/createRenderMethods.js`

**Changes** (line 48):
```javascript
// BEFORE:
hexDragTargetId: vm.hexDragTargetId,

// AFTER:
dragTargetId: vm.dragTargetId,
```

#### 3. `CollageAssembler.js` — Rename option + method call

**File:** `MyESModules/Rendering/CollageAssembler.js`

**Changes** (JSDoc line 35, render signature line 43, render body lines 68-75):
```javascript
// BEFORE:
* @param {string} [options.hexDragTargetId] - Panel ID to highlight during hex drag-and-drop
render(ctx, { ..., hexDragTargetId, ... }) {
    // ...
    if (hexDragTargetId && panels && hexDragTargetId !== selectedPanelId) {
        const targetPanel = panels.find(p => p.id === hexDragTargetId);
        if (targetPanel) {
            panelRenderer.drawHexDragTarget(ctx, targetPanel);
        }
    }

// AFTER:
* @param {string} [options.dragTargetId] - Panel ID to highlight during drag-and-drop
render(ctx, { ..., dragTargetId, ... }) {
    // ...
    if (dragTargetId && panels && dragTargetId !== selectedPanelId) {
        const targetPanel = panels.find(p => p.id === dragTargetId);
        if (targetPanel) {
            panelRenderer.drawDragTarget(ctx, targetPanel);
        }
    }
```

#### 4. `PanelRenderer.js` — Rename method

**File:** `MyESModules/Rendering/PanelRenderer.js`

**Changes** (lines 96-110):
```javascript
// BEFORE:
/**
 * Draws a dashed blue highlight border on a panel during hex drag-and-drop.
 * Indicates the target panel that will receive the swapped image.
 */
drawHexDragTarget(ctx, panel) {

// AFTER:
/**
 * Draws a dashed blue highlight border on a panel during drag-and-drop.
 * Indicates the target panel that will receive the swapped image.
 */
drawDragTarget(ctx, panel) {
```

Also update JSDoc reference in `_drawPanelBorder` (line 116):
```javascript
// BEFORE: Shared by drawSelectionBorder, drawHoverBorder, and drawHexDragTarget.
// AFTER:  Shared by drawSelectionBorder, drawHoverBorder, and drawDragTarget.
```

#### 5. Update test files

**Files to update:**
- `MyComponents/HexPanelSwapTest.html` — rename to `PanelSwapTest.html`, update import
- `MyComponents/Phase3FollowUpTest.html` — update all `hexDragTargetId` → `dragTargetId`, `drawHexDragTarget` → `drawDragTarget`, `createHexDragHandler` → `createPanelSwapHandler`
- `MyComponents/RenderingTest.html` — update `hexDragTargetId` → `dragTargetId`
- `MyComponents/Phase5RefactoringTest.html` — update `hexDragTargetId` → `dragTargetId`

### Success Criteria:

#### Automated Verification:
- [ ] All unit tests pass
- [ ] No references to `hexDragTargetId` or `drawHexDragTarget` remain in source code
- [ ] No console errors on page load

#### Manual Verification:
- [ ] Drag target highlight renders correctly during swap in all layouts
- [ ] No visual regression in hexagonal layout

---

## Phase 1.1: Shaped Dark Overlay

### Overview

Replace the 4-rect dark overlay with a clip-based approach for shaped panels. For rectangular panels, behavior is identical. For shaped panels (hexagonal, diagonal slices), the dark overlay is cut out in the shape of the panel within the crop region.

### Behavior Scenarios

#### Component Behavior

| # | Given | When | Then |
|---|-------|------|------|
| 1.1.CB.1 | Crop preview renders for a hex panel | Render executes | Dark overlay covers everything except the hex shape within crop region |
| 1.1.CB.2 | Crop preview renders for a parallelogram panel | Render executes | Dark overlay covers everything except the parallelogram shape within crop region |
| 1.1.CB.3 | Crop preview renders for a rect panel | Render executes | Dark overlay is 4 rects (unchanged from current) |
| 1.1.CB.4 | Crop preview renders, no selected panel | Render executes | No crop overlay drawn (early return) |
| 1.1.CB.5 | User pans the crop on a shaped panel | Crop source rect changes | Shape overlay stays fixed, image moves behind dark overlay |

#### Unit Test Scenarios

| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.1.UT.1 | `computeShapeOverlayPoints` for hex geometry | 6-point hexagon, valid crop screen | Returns 6 points within crop bounds |
| 1.1.UT.2 | `computeShapeOverlayPoints` for rect geometry | Rect geometry | Returns null |
| 1.1.UT.3 | `computeShapeOverlayPoints` with zero-size crop | Valid geometry, zero-size cropScreen | Returns null |
| 1.1.UT.4 | `beginPathFromPoints` helper | Array of [x,y] points | Creates valid canvas path |

### Changes Required:

#### 1. `createCropPreviewRenderer.js` — Shaped dark overlay

**File:** `MyESModules/App/createCropPreviewRenderer.js`

**Changes:**

Add import:
```javascript
import { isRectGeometry } from '../Models/PanelGeometry.js';
```

Replace the dark overlay section (lines 86-100) with:
```javascript
// Draw dark overlay outside the crop region
const selectedPanel = vm.panels?.find(p => p.id === vm.selectedPanelId);
const isShaped = selectedPanel && selectedPanel.geometry && !isRectGeometry(selectedPanel.geometry);

if (isShaped) {
    // For shaped panels: fill full canvas dark, then cut out the shape
    // clipped to the crop rectangle using destination-out compositing
    ctx.fillStyle = 'rgba(0, 0, 0, 0.55)';
    ctx.fillRect(0, 0, cssW, cssH);

    // Cut out the visible region: shape clipped to crop rect
    ctx.save();
    ctx.globalCompositeOperation = 'destination-out';

    // First clip to crop rectangle
    ctx.beginPath();
    ctx.rect(cropScreenX, cropScreenY, cropScreenW, cropScreenH);
    ctx.clip();

    // Then draw the shape (cuts a hole in the dark overlay)
    const shapePoints = computeShapeOverlayPoints(
        selectedPanel.geometry,
        { x: cropScreenX, y: cropScreenY, width: cropScreenW, height: cropScreenH },
        0  // No padding for the cutout — shape fills the crop region
    );
    if (shapePoints) {
        ctx.beginPath();
        ctx.moveTo(shapePoints[0][0], shapePoints[0][1]);
        for (let i = 1; i < shapePoints.length; i++) {
            ctx.lineTo(shapePoints[i][0], shapePoints[i][1]);
        }
        ctx.closePath();
        ctx.fill();
    }

    ctx.restore();
} else {
    // For rect panels: existing 4-rect approach (unchanged)
    ctx.fillStyle = 'rgba(0, 0, 0, 0.55)';
    ctx.fillRect(0, 0, cssW, cropScreenY);
    ctx.fillRect(0, cropScreenY + cropScreenH, cssW, cssH - cropScreenY - cropScreenH);
    ctx.fillRect(0, cropScreenY, cropScreenX, cropScreenH);
    ctx.fillRect(cropScreenX + cropScreenW, cropScreenY, cssW - cropScreenX - cropScreenW, cropScreenH);
}
```

**Canvas 2D clip trap:** The `ctx.clip()` call is persistent until `ctx.restore()`. The `destination-out` composite operation must be properly isolated with save/restore. The save/restore pairing in the code above ensures the clip and composite operation don't leak into subsequent drawing (border, handles).

#### 2. `CropOverlayShape.js` — Add `beginPathFromPoints` helper

**File:** `MyESModules/Layout/CropOverlayShape.js`

**Changes:** Add helper function after `drawShapeOverlay`:

```javascript
/**
 * Begins a path from an array of [x, y] points.
 * @param {CanvasRenderingContext2D} ctx
 * @param {Array} points - Array of [x, y] points
 */
export function beginPathFromPoints(ctx, points) {
    if (!points || points.length < 3) return;
    ctx.beginPath();
    ctx.moveTo(points[0][0], points[0][1]);
    for (let i = 1; i < points.length; i++) {
        ctx.lineTo(points[i][0], points[i][1]);
    }
    ctx.closePath();
}
```

### Success Criteria:

#### Automated Verification:
- [ ] `CropOverlayShapeTest.html` passes
- [ ] New test: `beginPathFromPoints` creates correct path
- [ ] No console errors

#### Manual Verification:
- [ ] Rectangular panels: dark overlay unchanged (no regression)
- [ ] Hexagonal panels: dark overlay follows hexagon shape within crop rect
- [ ] Diagonal Slices: dark overlay follows parallelogram shape
- [ ] Crop border still renders correctly
- [ ] Corner handles still visible at crop rect corners
- [ ] No visual artifacts at shape edges (anti-aliasing)

---

## Phase 1.2: Enhanced Shape Overlay + Shaped Crop Border

### Overview

Make the shape overlay more prominent and draw the crop border along the shape outline for shaped panels.

### Behavior Scenarios

#### Component Behavior

| # | Given | When | Then |
|---|-------|------|------|
| 1.2.CB.1 | Shaped panel crop preview renders | Shape overlay drawn | Solid stroke (no dash), brighter fill |
| 1.2.CB.2 | Shaped panel crop preview renders | Crop border drawn | Border follows shape outline |
| 1.2.CB.3 | Rect panel crop preview renders | Crop border drawn | Border is rectangular `strokeRect` (unchanged) |

#### Unit Test Scenarios

| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.2.UT.1 | `drawShapeOverlay` uses solid stroke | Points array | `lineDash` is empty array (no dash) |
| 1.2.UT.2 | `drawShapeOverlay` uses brighter fill | Points array | Fill alpha is 0.18 (was 0.12) |
| 1.2.UT.3 | `drawShapeOverlay` uses brighter stroke | Points array | Stroke alpha is 0.85 (was 0.7) |

### Changes Required:

#### 1. `CropOverlayShape.js` — Update `drawShapeOverlay` styling

**File:** `MyESModules/Layout/CropOverlayShape.js`

**Changes** (lines 77-83):
```javascript
// BEFORE:
ctx.fillStyle = 'rgba(255, 255, 255, 0.12)';
ctx.fill();
ctx.strokeStyle = 'rgba(255, 255, 255, 0.7)';
ctx.lineWidth = 1.5;
ctx.setLineDash([4, 3]);

// AFTER:
ctx.fillStyle = 'rgba(255, 255, 255, 0.18)';
ctx.fill();
ctx.strokeStyle = 'rgba(255, 255, 255, 0.85)';
ctx.lineWidth = 2;
ctx.setLineDash([]);
```

#### 2. `createCropPreviewRenderer.js` — Shaped crop border

**File:** `MyESModules/App/createCropPreviewRenderer.js`

**Changes:** Replace the crop border section (lines 103-105) with:
```javascript
// Draw crop border
ctx.strokeStyle = '#ffffff';
ctx.lineWidth = 1.5;

if (isShaped && shapePoints) {
    // For shaped panels: draw border along shape outline
    beginPathFromPoints(ctx, shapePoints);
    ctx.stroke();
} else {
    // For rect panels: existing rect border
    ctx.strokeRect(cropScreenX, cropScreenY, cropScreenW, cropScreenH);
}
```

Note: `shapePoints` is already computed in Phase 1.1 for the dark overlay cutout. For the border, use `padding = 0` to make the border align with the shape cutout edge.

### Success Criteria:

#### Automated Verification:
- [ ] `CropOverlayShapeTest.html` passes with updated styling assertions
- [ ] No console errors

#### Manual Verification:
- [ ] Shape overlay is clearly visible on shaped panels
- [ ] Crop border follows shape outline for shaped panels
- [ ] Rectangular panels unchanged
- [ ] Shape overlay and crop border don't overlap visually (both at same edge)

---

## Testing Strategy

### Unit Tests — Feature 2 (Swap in All Layouts)

**File:** `MyComponents/HexPanelSwapTest.html` → rename to `MyComponents/PanelSwapTest.html`

**Changes:**
- Update import path from `HexPanelSwap.js` → `PanelSwap.js`
- Update import name from `createHexDragHandler` → `createPanelSwapHandler`
- Add test: `swapPanelAssignments` with rect geometry panels
- Add test: `swapPanelAssignments` with mixed geometry panels
- Add test: `createPanelSwapHandler` factory returns handler with expected methods

**File:** `MyComponents/MultiTouchHandlerTest.html`

**Changes:**
- Add test: `_multiTouchGestureActive` flag set on gesture start
- Add test: `_multiTouchGestureActive` flag cleared on gesture end
- Add test: pointerdown no longer guards on hex layout

**File:** `MyComponents/Phase3FollowUpTest.html`

**Changes:**
- Update all `hexDragTargetId` → `dragTargetId`
- Update all `drawHexDragTarget` → `drawDragTarget`
- Update all `createHexDragHandler` → `createPanelSwapHandler`
- Update import path

**File:** `MyComponents/RenderingTest.html`

**Changes:**
- Update `hexDragTargetId` → `dragTargetId` in test options

**File:** `MyComponents/Phase5RefactoringTest.html`

**Changes:**
- Update `hexDragTargetId` → `dragTargetId` in test state objects

### Unit Tests — Feature 1 (Shaped Crop Overlay)

**File:** `MyComponents/CropOverlayShapeTest.html`

**Changes:**
- Add test: `beginPathFromPoints` creates correct path
- Add test: `drawShapeOverlay` uses solid stroke (verify `lineDash` is `[]`)
- Add test: `drawShapeOverlay` uses updated fill/stroke colors

### E2E Test Scenarios (Playwright)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 2.e.1 | Swap in Hero layout | Load 3+ images, select Hero layout, drag hero panel to side panel | Images swap, blue highlight during drag |
| 2.e.2 | Swap in Uniform layout | Load 4+ images, select Uniform layout, drag panel A to panel B | Images swap |
| 2.e.3 | Swap in Diagonal Slices | Load 3+ images, select Diagonal Slices, drag panel A to panel B | Images swap |
| 2.e.4 | Click-to-select in all layouts | Click panel in each layout | Panel selected, crop preview updates |
| 2.e.5 | Hover highlight in all layouts | Hover over panels in each layout | Blue hover border appears |
| 2.e.6 | Swap undo | Perform swap, press Cmd+Z | Original assignment restored |
| 1.e.1 | Shaped overlay in Hexagonal | Load images, select Hexagonal layout, select a panel | Crop preview shows hex-shaped dark overlay |
| 1.e.2 | Shaped overlay in Diagonal Slices | Load images, select Diagonal Slices, select a panel | Crop preview shows parallelogram-shaped dark overlay |
| 1.e.3 | Rect overlay in Hero | Load images, select Hero layout, select a panel | Crop preview shows rectangular dark overlay (no regression) |

### Manual Testing Steps

1. Load 5+ images
2. For each layout (Uniform, Hero, Mosaic, Diagonal Slices, Hexagonal):
   a. Verify click-to-select works
   b. Verify drag-to-swap works
   c. Verify hover highlight works
   d. Verify two-finger pan/zoom works
   e. Verify swap undo works (Cmd+Z)
3. For shaped layouts (Hexagonal, Diagonal Slices):
   a. Select a panel and verify crop preview shows shaped dark overlay
   b. Pan the crop and verify shape stays fixed
   c. Resize the crop and verify shape scales with crop region
4. For rect layouts (Uniform, Hero, Mosaic):
   a. Verify crop preview shows rectangular dark overlay (no regression)
5. Verify no console errors in any layout

---

## Performance Considerations

- **Feature 2**: No performance impact. The swap handler's hit test is O(n) in panels (same as before). The layout check removal is O(1). The `_multiTouchGestureActive` flag is a simple boolean check.
- **Feature 1**: The clip-based dark overlay for shaped panels adds one `ctx.clip()` + one `ctx.fill()` per crop preview render. The `destination-out` composite operation is a standard Canvas 2D operation. Crop preview renders at most once per rAF cycle, so this is negligible.
- **Feature 1**: `computeShapeOverlayPoints` is called twice per shaped panel render (once for dark overlay cutout with `padding=0`, once for shape overlay with `padding=8`). This is O(n) in polygon vertices (typically 3-6 points) — negligible.

---

## Potential Challenges and Mitigations

### Feature 2

1. **Pointer event ordering**: Removing GestureHandler's pointerdown means the swap handler is the sole click handler. If swap handler's `_onPointerUp` doesn't fire (e.g., pointer captured by another element), selection breaks. **Mitigation**: The swap handler uses `setPointerCapture` implicitly via the canvas element. Test click-to-select thoroughly in all layouts.

2. **Multi-touch + swap interaction**: If user starts a two-finger gesture while a swap drag is in progress, the swap handler might misinterpret a pointerup as a click. **Mitigation**: The `_multiTouchGestureActive` flag prevents the swap handler from processing pointerdown during multi-touch. The swap handler's existing `isDragging` guard prevents click-to-select during drag.

3. **Test file updates**: Many test files reference `hexDragTargetId` and `drawHexDragTarget`. **Mitigation**: Use grep to find all references and update systematically. The rename is mechanical but touches ~87 locations.

4. **Touch interaction on mobile**: On touch devices, the swap handler uses PointerEvents (which include touch). The `pointerType` is `'touch'` for touch input. The swap handler doesn't filter by `pointerType`, so touch drags will trigger swap. **Mitigation**: This is consistent with existing Hexagon behavior — no change needed.

### Feature 1

1. **Canvas clip persistence**: `ctx.clip()` is persistent until `ctx.restore()`. If save/restore pairing is incorrect, subsequent drawing (border, handles) will be clipped. **Mitigation**: The save/restore in Phase 1.1 wraps only the `destination-out` section. Verify with manual testing.

2. **destination-out compositing**: The `globalCompositeOperation = 'destination-out'` must be properly isolated. **Mitigation**: Wrapped in `ctx.save()`/`ctx.restore()` — standard pattern.

3. **Shape overlay within crop rect**: `computeShapeOverlayPoints` uses `padding = 8` by default. For the dark overlay cutout, we pass `padding = 0` so the shape fills the crop region exactly. For the decorative shape overlay, `padding = 8` creates visual breathing room. **Mitigation**: Two separate calls with different padding values.

4. **Anti-aliasing at shape edges**: The `destination-out` cutout may show a thin dark line at the shape edge due to anti-aliasing. **Mitigation**: Acceptable — this is a known Canvas 2D behavior. If visually objectionable, increase the shape size slightly (negative padding) to compensate.

---

## Migration Notes

- `HexPanelSwap.js` is renamed to `PanelSwap.js`. Any external references (none expected — this is an internal module) would need updating.
- `hexDragTargetId` is renamed to `dragTargetId` in reactive state. This is an internal property with no persistence layer.
- `drawHexDragTarget` is renamed to `drawDragTarget`. This is an internal method with no external API surface.
- Test files need systematic updates. Run `grep -r "hexDragTargetId\|drawHexDragTarget\|createHexDragHandler\|HexPanelSwap"` to find all occurrences.

## References

- Change Request: `_agent_docs/specifications/change-requests/2026-07-10-01-crop-overlay-preview-panel-shape.md`
- Change Request: `_agent_docs/specifications/change-requests/2026-07-12-02-swap-in-all-layouts.md`
- Skill: `.opencode/skills/building-web-apps/references/interaction.md` — pointer handler coordination
- Skill: `.opencode/skills/building-web-apps/references/canvas-2d.md` — Canvas 2D clip persistence, DPR scaling
- Skill: `.opencode/skills/building-web-apps/references/testing-unit.md` — Mocha/Chai patterns, Proxy-based context mocking
- Skill: `.opencode/skills/writing-plans/SKILL.md` — plan formatting conventions
- Learning: `_agent_docs/learnings/2026-07-11-canvas-border-refactor-and-drag-cleanup.md` — characterization tests before refactor
- Learning: `_agent_docs/learnings/2026-07-12-canvas-render-order-testing.md` — same-panel overlap guard
