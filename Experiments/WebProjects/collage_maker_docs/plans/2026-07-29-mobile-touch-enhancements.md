# Mobile Touch Enhancements Implementation Plan

**Date:** 2026-07-29
**Source:** `_agent_docs/specifications/change-requests/2026-07-29-01-mobile-touch-enhancements.md`

## Overview

This plan addresses 5 reported mobile touch issues in CollageMaker's canvas interaction layer. The changes span four modules: `MultiTouchHandler.js` (PointerEvents migration + zoom sensitivity), `TitleRenderer.js` (touch handle rendering), `TitleInteraction.js` (pointercancel hardening + pointerType passthrough), `Style.css` (touch-action), and `index.html` (bottom sheet controls). The core architectural shift is migrating multi-touch from TouchEvents to PointerEvents with `setPointerCapture`, which resolves two issues simultaneously.

## Current State Analysis

### Key Discoveries

1. **MultiTouchHandler.js has three input paths** (lines 220-402): TouchEvent (220-259), PointerEvent (265-352), WheelEvent (358-402). The PointerEvent path has `if (e.pointerType === 'touch') return;` guards at lines 267, 293, 306, 331 that delegate touch pointers to the TouchEvent path.

2. **TouchEvent path lacks pointer capture** — TouchEvents are element-scoped. When a finger leaves the canvas bounds, `touchmove` stops firing. There is no `setPointerCapture` equivalent for TouchEvents.

3. **PointerEvent path already has pointer capture** — Lines 273-277 call `canvas.setPointerCapture(e.pointerId)` per-pointer in `_onPointerDown`. Lines 309, 334 call `releasePointerCapture` in `_onPointerUp` and `_onPointerCancel`.

4. **Shared gesture functions** (`startGesture`, `processGesture`, `endGesture`) at lines 146-214 are already shared between TouchEvent and PointerEvent paths.

5. **Zoom exponent** at line 194: `Math.pow(scaleRatio, 0.15)` converts a 2x pinch spread into `2^0.15 = 1.11` per step — very sluggish.

6. **`_multiTouchGestureActive` flag** is set in `startGesture()` at line 151, but with TouchEvents this runs asynchronously. A stray pointer event from a finger leaving the canvas can hit `PanelSwap.js` line 364 before the flag is set.

7. **`touch-action: pan-y`** on `#previewCanvas` (Style.css:345) allows browser default gestures (pull-to-refresh, iOS back-swipe) to fire and trigger `pointercancel` during title drag.

8. **TitleInteraction.js already uses PointerEvents with setPointerCapture** (lines 236-241) and handles `pointercancel` (line 55 maps to `_onPointerUp`).

9. **Bottom sheet Edit tab** (index.html lines 397-431) has 4 title controls (text, font, size, color, alignment). Desktop sidebar Title section (lines 472-549) has 11 controls. Missing: font opacity, bg color, bg opacity, show bg checkbox, width slider, reset position, bold/italic/underline bar.

10. **TitleRenderer.js `drawInteractionOutline`** (line 228) draws a dashed/solid outline. No resize handle indicators are drawn for touch mode.

11. **Interaction state flow**: Vue state (`titleHoverTarget`, `titleInteractionMode`) → `createRenderMethods.js` (lines 53-54) → `CollageAssembler.js` (lines 98-99, constructs `{hoverTarget, interactionMode}`) → `TitleRenderer.js` `render()` receives as `interactionState`.

### Key Discoveries:
- PointerEvent path in MultiTouchHandler.js is fully functional for non-touch pointers — just needs touch guards removed
- `setPointerCapture` is already used correctly in PointerEvent path (try/catch wrapped)
- TitleInteraction.js pointercancel handling is already correct — just needs CSS fix
- Bottom sheet controls are a straightforward template copy with `bs` ID prefixing
- Interaction state needs one new field (`pointerType`) threaded through the render pipeline for Phase 4

## Desired End State

After implementation:
- Two-finger pan continues smoothly even when fingers leave canvas bounds (PointerEvents with capture)
- Pinch-to-zoom feels responsive (exponent 0.3)
- No unintended panel swaps during pinch gestures (synchronous flag + pointer capture)
- Title drag never drops mid-gesture (touch-action: none prevents browser gesture interference)
- Touch users see visible resize handles on title edges
- Bottom sheet Edit tab has full title control parity with desktop sidebar

## What We're NOT Doing

1. **NOT adding haptic feedback** — No `navigator.vibrate()` calls. Out of scope.
2. **NOT adding gesture tutorials/tooltips** — Visual handles are sufficient discoverability.
3. **NOT changing the WheelEvent path** — Trackpad gestures on macOS work correctly and are unaffected by touch issues.
4. **NOT modifying the crop preview canvas** — Touch issues are specific to the main preview canvas.
5. **NOT adding a "mobile mode" toggle** — All changes are transparent and benefit all platforms.
6. **NOT changing the export pipeline** — Export is unaffected by touch interaction changes.
7. **NOT modifying the saliency system** — Focus point analysis is independent of touch interaction.
8. **NOT adding gesture recording/replay** — Playwright cannot reliably simulate multi-touch anyway.

## Implementation Approach

Four phases, ordered by user impact. Phase 1 is the foundational infrastructure change that enables Phases 2 and 3. Phase 4 is independent polish.

## Phase 1: PointerEvents Migration + touch-action Fix (P0)

### Overview
Migrate multi-touch gestures from TouchEvents to PointerEvents with `setPointerCapture`, and change `touch-action: pan-y` to `touch-action: none` on `#previewCanvas`. This resolves both the "two-finger pan stops" and "title drag drops" issues.

### Changes Required:

#### 1. MultiTouchHandler.js — Remove TouchEvent path, enable PointerEvent for touch

**File**: `MyESModules/Interaction/MultiTouchHandler.js`

**Changes**:
1. **Remove touch guards from PointerEvent handlers** — Delete `if (e.pointerType === 'touch') return;` from `_onPointerDown` (line 267), `_onPointerMove` (line 293), `_onPointerUp` (line 306), `_onPointerCancel` (line 331).

2. **Delete TouchEvent handler functions** — Remove `_onTouchStart` (lines 220-231), `_onTouchMove` (lines 233-250), `_onTouchEnd` (lines 252-259).

3. **Delete TouchEvent-specific state** — Remove `activeTouchIds` variable (line 78) and `findTwoTouches` helper (lines 103-111).

4. **Update `attach()`** — Remove TouchEvent listener registration (lines 413-416). Keep PointerEvent and WheelEvent listeners.

5. **Update `detach()`** — Remove TouchEvent listener removal (lines 455-458). Keep PointerEvent and WheelEvent removal.

6. **Update `endGesture()`** — Remove `activeTouchIds = null` from cleanup (line 210).

7. **Update handler return object** — Remove `_onTouchStart`, `_onTouchMove`, `_onTouchEnd` from exposed handlers (lines 473-475). Remove binding lines 484-486.

#### 2. Style.css — Change touch-action

**File**: `Style.css`

**Changes**: Line 345, change `touch-action: pan-y;` to `touch-action: none;`

#### 3. TitleInteraction.js — No code changes needed

**File**: `MyESModules/Interaction/TitleInteraction.js`

**Changes**: None. Line 55 already maps `pointercancel` to `onPointerUp`. `_clearInteractionState()` properly releases pointer capture (lines 96-101).

### BDD Scenarios

#### User Behavior

| # | Given | When | Then |
|---|-------|------|------|
| 1.1.1 | Two images loaded, panel selected, user places two fingers on canvas | User drags both fingers and one finger moves outside canvas bounds | Panning continues smoothly without interruption |
| 1.1.2 | Title text present on canvas, user taps title body on mobile | User drags title upward toward top of screen | Title follows finger without dropping, no browser pull-to-refresh fires |
| 1.1.3 | Two images loaded, user starts two-finger pinch on one panel | During pinch, one finger drifts over an adjacent panel | No panel swap occurs; only zoom/pan is applied |

#### Component Behavior — MultiTouchHandler

| # | Given | When | Then |
|---|-------|------|------|
| 1.2.1 | Handler created with canvasId, cropManager, state | `attach()` called | PointerEvent listeners registered, TouchEvent listeners NOT registered |
| 1.2.2 | PointerEvent with `pointerType === 'touch'` and `pointerId: 5` arrives | `_onPointerDown` processes event | Pointer added to `activePointers` Map; `setPointerCapture(5)` called; no early return |
| 1.2.3 | Two touch pointers captured, second pointerdown fires | `_onPointerDown` sees `activePointers.size === 2` | `startGesture()` called, `state._multiTouchGestureActive` set synchronously to `true` |
| 1.2.4 | Gesture active, one pointer moves outside canvas bounds | PointerEvent `pointermove` fires (via capture) | `processGesture()` still receives coordinates; gesture continues |
| 1.2.5 | Gesture active, one pointer lifted | `_onPointerUp` fires for that pointer | `activePointers.delete()` called; `endGesture()` called; `releasePointerCapture` called for remaining pointer |
| 1.2.6 | Gesture active, `pointercancel` fires | `_onPointerCancel` processes event | All captures released, `gestureActive` cleared, `state._multiTouchGestureActive` set to `false` |
| 1.2.7 | `detach()` called on attached handler | — | All PointerEvent listeners removed; TouchEvent listeners NOT removed (never attached) |
| 1.2.8 | No panel selected (`state.selectedPanelId === null`) | Two touch pointerdowns fire | `startGesture()` returns `false`; no gesture activated; `activePointers` cleared |

#### Component Behavior — TitleInteraction

| # | Given | When | Then |
|---|-------|------|------|
| 1.3.1 | Title present, `touch-action: none` on canvas | User starts dragging title on mobile | No `pointercancel` fires from browser gestures; drag continues |
| 1.3.2 | Title drag in progress | `pointercancel` event fires (e.g., device rotation) | `_clearInteractionState()` called; `state.titleInteractionMode` set to `null`; cursor reset |

#### Pure Function Behavior

| # | Given | When | Then |
|---|-------|------|------|
| 1.4.1 | `computeTouchMidpoint` called with `{clientX: 100, clientY: 200}` and `{clientX: 300, clientY: 400}` | — | Returns `{x: 200, y: 300}` (unchanged) |
| 1.4.2 | `computeTouchDistance` called with `{clientX: 0, clientY: 0}` and `{clientX: 300, clientY: 400}` | — | Returns `500` (unchanged) |

### Success Criteria:

#### Automated Verification:
- [ ] `MultiTouchHandlerTest.html` — All existing pure math tests pass (unchanged)
- [ ] `MultiTouchHandlerTest.html` — New test: PointerEvent with `pointerType === 'touch'` does NOT early-return in `_onPointerDown`
- [ ] `MultiTouchHandlerTest.html` — New test: `setPointerCapture` called for each pointer ID on touch pointers
- [ ] `MultiTouchHandlerTest.html` — New test: TouchEvent listeners NOT registered after attach
- [ ] `MultiTouchHandlerTest.html` — New test: `state._multiTouchGestureActive` set synchronously on gesture start with touch pointers
- [ ] `MultiTouchHandlerTest.html` — New test: `releasePointerCapture` called for all pointers on gesture end
- [ ] `MultiTouchHandlerTest.html` — New test: `pointercancel` clears all gesture state including `_multiTouchGestureActive`
- [ ] `TitleInteractionTest.html` — All existing tests pass (no behavioral change)
- [ ] Full test suite: `node scripts/run-tests.js` passes

#### Manual Verification:
- [ ] On real iOS device: two-finger pan continues when finger leaves canvas
- [ ] On real iOS device: title drag does not drop mid-gesture
- [ ] On real Android device: two-finger pan and pinch-to-zoom work
- [ ] Desktop browser: no regression in panel swap or title drag
- [ ] Desktop browser: trackpad two-finger pan/zoom still works (WheelEvent path unchanged)

---

## Phase 2: Pinch Zoom Sensitivity + Swap Prevention (P1)

### Overview
Increase zoom exponent from 0.15 to 0.3 for more responsive pinch-to-zoom. Verify that `_multiTouchGestureActive` is set synchronously at gesture start to prevent stray pointer events from triggering panel swaps.

### Changes Required:

#### 1. MultiTouchHandler.js — Increase zoom exponent

**File**: `MyESModules/Interaction/MultiTouchHandler.js`

**Changes**: Line 194, change `Math.pow(scaleRatio, 0.15)` to `Math.pow(scaleRatio, 0.3)`.

Update comment on lines 190-191:
```javascript
// Use a root to convert the total ratio into a small incremental factor
// e.g., ratio 2.0 -> factor 2.0^0.3 ≈ 1.23 (responsive zoom step)
```

#### 2. MultiTouchHandler.js — Verify synchronous flag setting

**File**: `MyESModules/Interaction/MultiTouchHandler.js`

**Changes**: No code change needed. `startGesture()` at line 151 sets `state._multiTouchGestureActive = true` synchronously. The PointerEvent migration in Phase 1 ensures this flag is set before any stray pointer event can reach PanelSwap, because PointerEvents with capture don't lose events when fingers leave the canvas.

### BDD Scenarios

#### User Behavior

| # | Given | When | Then |
|---|-------|------|------|
| 2.1.1 | Panel selected, user performs a moderate pinch-open gesture (fingers spread from 100px to 200px) | Gesture completes over 100ms | Image zooms in noticeably — approximately 1.23x total zoom (vs ~1.11x before) |
| 2.1.2 | Two images loaded, user starts pinch-to-zoom on panel A | One finger drifts over panel B during pinch | No panel swap occurs; only zoom is applied |
| 2.1.3 | User performs rapid pinch-in gesture | Gesture completes | Image zooms out responsively at same rate as zoom-in |

#### Component Behavior — MultiTouchHandler

| # | Given | When | Then |
|---|-------|------|------|
| 2.2.1 | `processGesture` called with initialDistance=100, currentDistance=200 | Scale ratio computed | `Math.pow(2.0, 0.3)` ≈ 1.23 factor passed to `zoomCrop()` |
| 2.2.2 | `processGesture` called with initialDistance=200, currentDistance=100 | Scale ratio computed | `Math.pow(0.5, 0.3)` ≈ 0.81 factor passed to `zoomCrop()` |
| 2.2.3 | `startGesture` called with valid panel | — | `state._multiTouchGestureActive` set to `true` before any other async operation |
| 2.2.4 | PanelSwap handler receives pointerdown while `_multiTouchGestureActive === true` | `_onPointerDown` in PanelSwap.js line 364 executes | Early return; no panel selection or swap initiated |

#### Component Behavior — PanelSwap

| # | Given | When | Then |
|---|-------|------|------|
| 2.3.1 | `state._multiTouchGestureActive === true` | PointerEvent `pointerdown` fires on canvas | `_onPointerDown` returns early at line 364; no drag started |
| 2.3.2 | `state._multiTouchGestureActive === false` | PointerEvent `pointerdown` fires on panel area | Normal panel selection/drag flow proceeds |

#### Pure Function Behavior

| # | Given | When | Then |
|---|-------|------|------|
| 2.4.1 | `computePinchScale(100, 200)` | — | Returns `2.0` (unchanged — pure math) |
| 2.4.2 | `computePinchScale(200, 100)` | — | Returns `0.5` (unchanged — pure math) |
| 2.4.3 | `computePinchScale(100, 100)` | — | Returns `1.0` (unchanged — pure math) |

### Success Criteria:

#### Automated Verification:
- [ ] `MultiTouchHandlerTest.html` — New test: zoom factor with exponent 0.3 for 2x spread is ~1.23
- [ ] `MultiTouchHandlerTest.html` — New test: zoom factor with exponent 0.3 for 0.5x squeeze is ~0.81
- [ ] `MultiTouchHandlerTest.html` — New test: `computePinchScale` returns unchanged values (pure math regression)
- [ ] `MultiTouchHandlerTest.html` — New test: `_multiTouchGestureActive` is `true` immediately after `startGesture` with touch pointers
- [ ] `TitleInteractionTest.html` — Existing test "6.2.6 — Pointer down skipped when _multiTouchGestureActive is true" still passes
- [ ] Full test suite: `node scripts/run-tests.js` passes

#### Manual Verification:
- [ ] On real iOS device: pinch-to-zoom feels responsive (comparable to native Photos app)
- [ ] On real iOS device: no panel swap during pinch gesture
- [ ] Desktop browser: no regression in trackpad pinch-to-zoom (WheelEvent path unchanged)

---

## Phase 3: Bottom Sheet Title Controls (P2)

### Overview
Add 7 missing title controls to the mobile bottom sheet Edit tab to achieve feature parity with the desktop sidebar. All IDs prefixed with `bs`.

### Changes Required:

#### 1. index.html — Add missing controls to bottom sheet Edit tab

**File**: `index.html`

**Changes**: After line 431 (closing `</div>` of Alignment segmented control in bottom sheet Edit tab), before line 432 (closing `</div>` of Edit panel), insert the following controls in this order:

1. **Bold/Italic/Underline formatting bar** — After alignment controls:
```html
<div class="detail-section">
    <div class="formatting-bar">
        <button class="format-btn" :class="{ active: isTitleFormatActive('bold') }" @mousedown.prevent @click="toggleTitleBold" title="Bold" :disabled="titleSelectionStart === titleSelectionEnd" :aria-pressed="isTitleFormatActive('bold')">
            <strong>B</strong>
        </button>
        <button class="format-btn" :class="{ active: isTitleFormatActive('italic') }" @mousedown.prevent @click="toggleTitleItalic" title="Italic" :disabled="titleSelectionStart === titleSelectionEnd" :aria-pressed="isTitleFormatActive('italic')">
            <em>I</em>
        </button>
        <button class="format-btn" :class="{ active: isTitleFormatActive('underline') }" @mousedown.prevent @click="toggleTitleUnderline" title="Underline" :disabled="titleSelectionStart === titleSelectionEnd" :aria-pressed="isTitleFormatActive('underline')">
            <u>U</u>
        </button>
    </div>
</div>
```

2. **Font Opacity slider**:
```html
<div class="detail-section">
    <label for="bsTitleFontOpacitySlider">Font Opacity: {{ Math.round(titleStyle.fontOpacity * 100) }}%</label>
    <input type="range" id="bsTitleFontOpacitySlider" v-model.number="titleStyle.fontOpacity" min="0" max="1" step="0.01" :aria-valuenow="Math.round(titleStyle.fontOpacity * 100) + '%'" aria-valuemin="0%" aria-valuemax="100%" class="fullRange" @focus="snapshotTitleStyle" @pointerdown="snapshotTitleStyle" @input="onTitleFontOpacityChange" @blur="commitTitleStyle">
</div>
```

3. **Background Color picker**:
```html
<div class="detail-section">
    <label for="bsTitleBgColorPicker">Background Color</label>
    <div class="color-picker-row">
        <input type="color" id="bsTitleBgColorPicker" v-model="titleStyle.backgroundColor" @focus="snapshotTitleStyle" @input="onTitleBackgroundColorChange" @blur="commitTitleStyle">
    </div>
</div>
```

4. **Background Opacity slider**:
```html
<div class="detail-section">
    <label for="bsTitleBgOpacitySlider">Bg Opacity: {{ Math.round(titleStyle.bgOpacity * 100) }}%</label>
    <input type="range" id="bsTitleBgOpacitySlider" v-model.number="titleStyle.bgOpacity" min="0" max="1" step="0.01" :aria-valuenow="Math.round(titleStyle.bgOpacity * 100) + '%'" aria-valuemin="0%" aria-valuemax="100%" class="fullRange" @focus="snapshotTitleStyle" @pointerdown="snapshotTitleStyle" @input="onTitleBgOpacityChange" @blur="commitTitleStyle">
</div>
```

5. **Show Background checkbox**:
```html
<div class="detail-section">
    <label>
        <input type="checkbox" :checked="titleStyle.showBackground" @change="toggleTitleShowBackground">
        Show Background
    </label>
</div>
```

6. **Width slider**:
```html
<div class="detail-section">
    <label for="bsTitleWidthSlider">Width: {{ titleStyle.titleBoxWidth ? Math.round(titleStyle.titleBoxWidth) : 'Auto' }}</label>
    <input type="range" id="bsTitleWidthSlider" v-model.number="titleStyle.titleBoxWidth" min="100" max="1920" step="1" :aria-valuenow="(titleStyle.titleBoxWidth ? Math.round(titleStyle.titleBoxWidth) + 'px' : 'Auto')" aria-valuemin="100px" aria-valuemax="1920px" class="fullRange" @focus="snapshotTitleStyle" @pointerdown="snapshotTitleStyle" @input="onTitleWidthChange" @blur="commitTitleStyle">
</div>
```

7. **Reset Position button**:
```html
<div class="detail-section">
    <button class="pure-button reset-title-btn" @click="resetTitlePosition">
        <span class="material-icons" style="font-size: 16px; vertical-align: middle; margin-right: 4px;" aria-hidden="true">restart_alt</span>
        Reset Position
    </button>
</div>
```

### BDD Scenarios

#### User Behavior

| # | Given | When | Then |
|---|-------|------|------|
| 3.1.1 | Mobile viewport (<700px), bottom sheet Edit tab open | User scrolls to bottom of Edit tab | All 11 title controls visible: text, bold/italic/underline, font, size, color, font opacity, bg color, bg opacity, show bg, alignment, width, reset position |
| 3.1.2 | Bottom sheet Edit tab open, title text present | User adjusts Font Opacity slider | Title text opacity updates in real-time on canvas |
| 3.1.3 | Bottom sheet Edit tab open | User toggles "Show Background" checkbox | Title background appears/disappears on canvas |
| 3.1.4 | Bottom sheet Edit tab open, title has custom position | User taps "Reset Position" button | Title returns to default centered position |
| 3.1.5 | Bottom sheet Edit tab open, text selected in textarea | User taps Bold button | Selected text becomes bold in title runs |

#### Component Behavior — HTML Template

| # | Given | When | Then |
|---|-------|------|------|
| 3.2.1 | `index.html` bottom sheet Edit tab parsed | Query for `#bsTitleFontOpacitySlider` | Element exists with `v-model="titleStyle.fontOpacity"` |
| 3.2.2 | `index.html` bottom sheet Edit tab parsed | Query for `#bsTitleBgColorPicker` | Element exists with `v-model="titleStyle.backgroundColor"` |
| 3.2.3 | `index.html` bottom sheet Edit tab parsed | Query for `#bsTitleBgOpacitySlider` | Element exists with `v-model="titleStyle.bgOpacity"` |
| 3.2.4 | `index.html` bottom sheet Edit tab parsed | Query for "Show Background" checkbox | Element exists with `@change="toggleTitleShowBackground"` |
| 3.2.5 | `index.html` bottom sheet Edit tab parsed | Query for `#bsTitleWidthSlider` | Element exists with `v-model="titleStyle.titleBoxWidth"` |
| 3.2.6 | `index.html` bottom sheet Edit tab parsed | Query for "Reset Position" button | Element exists with `@click="resetTitlePosition"` |
| 3.2.7 | `index.html` bottom sheet Edit tab parsed | Query for formatting bar (B/I/U) | Three buttons exist with `@click="toggleTitleBold/Italic/Underline"` |
| 3.2.8 | `index.html` bottom sheet Edit tab parsed | All new element IDs checked | All IDs prefixed with `bs` (no collision with desktop sidebar IDs) |

### Success Criteria:

#### Automated Verification:
- [ ] Playwright test: All 7 new controls present in bottom sheet Edit tab at mobile viewport
- [ ] Playwright test: All new element IDs have `bs` prefix
- [ ] Playwright test: Font Opacity slider interaction updates canvas
- [ ] Playwright test: Show Background checkbox toggles title background
- [ ] Playwright test: Reset Position button returns title to default position
- [ ] Full test suite: `node scripts/run-tests.js` passes

#### Manual Verification:
- [ ] On mobile viewport: all 11 title controls visible and functional in bottom sheet
- [ ] Font Opacity slider updates title text opacity in real-time
- [ ] Background Color picker changes title background color
- [ ] Show Background checkbox toggles background visibility
- [ ] Width slider adjusts title box width
- [ ] Reset Position button returns title to default position
- [ ] Bold/Italic/Underline buttons toggle formatting on selected text
- [ ] Desktop sidebar: no regression (unchanged)

---

## Phase 4: Title Resize Handle Discoverability (P3)

### Overview
Draw visible resize handle indicators on the canvas when in title interaction mode on touch devices. Render small circles at the left and right edges of the title bounding box. Thread `pointerType` through the interaction state pipeline so the renderer knows whether to draw touch handles.

### Changes Required:

#### 1. TitleRenderer.js — Add touch resize handle rendering

**File**: `MyESModules/Rendering/TitleRenderer.js`

**Changes**:

1. Add a new exported function `drawTouchResizeHandles`:
```javascript
/**
 * Draws visible resize handle indicators for touch devices.
 * Renders two small circles at the left and right edges of the title box.
 * @param {CanvasRenderingContext2D} ctx
 * @param {number} x - Box left edge (logical coords)
 * @param {number} y - Box top edge (logical coords)
 * @param {number} w - Box width
 * @param {number} h - Box height
 * @param {string|null} activeEdge - 'left-edge', 'right-edge', or null
 */
export function drawTouchResizeHandles(ctx, x, y, w, h, activeEdge) {
    const handleRadius = 8; // Logical pixels — visible at all DPRs
    const handleY = y + h / 2; // Centered vertically on box

    ctx.save();

    // Draw left handle
    ctx.beginPath();
    ctx.arc(x, handleY, handleRadius, 0, Math.PI * 2);
    ctx.fillStyle = activeEdge === 'left-edge' ? '#3b82f6' : 'rgba(59, 130, 246, 0.6)';
    ctx.fill();
    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = 2;
    ctx.stroke();

    // Draw right handle
    ctx.beginPath();
    ctx.arc(x + w, handleY, handleRadius, 0, Math.PI * 2);
    ctx.fillStyle = activeEdge === 'right-edge' ? '#3b82f6' : 'rgba(59, 130, 246, 0.6)';
    ctx.fill();
    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = 2;
    ctx.stroke();

    ctx.restore();
}
```

2. Modify `render()` function — after the `drawInteractionOutline` call (line 348), add:
```javascript
// Draw touch resize handles when in interaction mode on touch devices
if (interactionState && interactionState.pointerType === 'touch'
    && (interactionState.hoverTarget || interactionState.interactionMode)) {
    const outlineX = isLegacyMode ? boxLeft - PADDING : boxLeft;
    const activeEdge = interactionState.hoverTarget || interactionState.interactionMode;
    drawTouchResizeHandles(ctx, outlineX, bounds.y, boxWidth, bounds.height, activeEdge);
}
```

#### 2. TitleInteraction.js — Track and expose pointerType

**File**: `MyESModules/Interaction/TitleInteraction.js`

**Changes**:

1. Add `lastPointerType` variable near other state variables (after line 28):
```javascript
let lastPointerType = null; // 'mouse', 'touch', or 'pen'
```

2. In `_onPointerDown` (after line 232), capture the pointer type:
```javascript
lastPointerType = e.pointerType;
```

3. In `_clearInteractionState` (after line 87), reset it:
```javascript
lastPointerType = null;
```

4. In `_onPointerDown` (after line 294 where `state.titleInteractionMode` is set), also set:
```javascript
state.titleInteractionPointerType = lastPointerType;
```

5. In `_onPointerMove` hover section (after line 400 where `state.titleHoverTarget` is set), also set:
```javascript
state.titleInteractionPointerType = e.pointerType;
```

6. In `_clearInteractionState`, also clear:
```javascript
state.titleInteractionPointerType = null;
```

#### 3. createCollageData.js — Add new state property

**File**: `MyESModules/App/createCollageData.js`

**Changes**: After line 55 (`titleInteractionMode: null,`), add:
```javascript
titleInteractionPointerType: null,
```

#### 4. createRenderMethods.js — Pass pointerType to assembler

**File**: `MyESModules/App/createRenderMethods.js`

**Changes**: After line 54 (`titleInteractionMode: vm.titleInteractionMode || null`), add:
```javascript
titleInteractionPointerType: vm.titleInteractionPointerType || null
```

#### 5. CollageAssembler.js — Thread pointerType through to TitleRenderer

**File**: `MyESModules/Rendering/CollageAssembler.js`

**Changes**:

1. Add `titleInteractionPointerType` to the `render()` function signature (line 43).

2. In the interaction state object construction (lines 98-99), add:
```javascript
pointerType: titleInteractionPointerType || null
```

### BDD Scenarios

#### User Behavior

| # | Given | When | Then |
|---|-------|------|------|
| 4.1.1 | Title present on canvas, mobile viewport | User taps on title body | Interaction outline appears with visible resize handles at left and right edges |
| 4.1.2 | Title interaction active on touch device | User drags from title left edge | Left resize handle appears highlighted (solid blue); title width changes as user drags |
| 4.1.3 | Title interaction active on mouse device | User hovers over title edge | Cursor changes to `ew-resize`; no visible handles drawn (mouse uses cursor feedback) |

#### Component Behavior — TitleRenderer

| # | Given | When | Then |
|---|-------|------|------|
| 4.2.1 | `render()` called with `interactionState.interactionMode === 'drag'` and `interactionState.pointerType === 'touch'` | Title rendered | Interaction outline drawn; two resize handle indicators drawn at left and right edges |
| 4.2.2 | `render()` called with `interactionState.hoverTarget === 'left-edge'` and `pointerType === 'touch'` | Title rendered | Left resize handle highlighted (solid blue fill); right handle in default style |
| 4.2.3 | `render()` called with `interactionState.interactionMode === 'resize-left'` and `pointerType === 'touch'` | Title rendered | Left resize handle highlighted; right handle shown in default style |
| 4.2.4 | `render()` called with `interactionState` but `pointerType === 'mouse'` | Title rendered | Only interaction outline drawn; no resize handle indicators |
| 4.2.5 | `render()` called with `interactionState.pointerType === 'pen'` | Title rendered | Only interaction outline drawn; no resize handle indicators |

#### Component Behavior — TitleInteraction

| # | Given | When | Then |
|---|-------|------|------|
| 4.3.1 | Touch pointer enters edge threshold zone | `_onPointerMove` processes event | `state.titleHoverTarget` set to `'left-edge'` or `'right-edge'`; `state.titleInteractionPointerType` set to `'touch'`; render scheduled |
| 4.3.2 | Touch pointer in edge zone, pointerdown fires | `_onPointerDown` processes event | `state.titleInteractionMode` set to `'resize-left'` or `'resize-right'`; `state.titleInteractionPointerType` set to `'touch'`; render scheduled |
| 4.3.3 | Interaction ends (pointerup) | `_clearInteractionState()` called | `state.titleInteractionPointerType` set to `null` |

#### Pure Function Behavior

| # | Given | When | Then |
|---|-------|------|------|
| 4.4.1 | `drawTouchResizeHandles` called with ctx, x=500, y=900, w=400, h=60, activeEdge='left-edge' | — | Two circles drawn at (500, 930) and (900, 930); left circle has active style (solid blue fill) |
| 4.4.2 | `drawTouchResizeHandles` called with activeEdge=null | — | Two circles drawn in default (semi-transparent) style |
| 4.4.3 | `drawTouchResizeHandles` called with activeEdge='right-edge' | — | Right circle has active style; left circle in default style |
| 4.4.4 | `drawTouchResizeHandles` called with activeEdge='resize-left' | — | Left circle has active style (matching interaction mode string) |

### Success Criteria:

#### Automated Verification:
- [ ] `TitleRendererTest.html` — New test: `drawTouchResizeHandles` draws two circles at correct positions
- [ ] `TitleRendererTest.html` — New test: active edge handle has different fill color than inactive
- [ ] `TitleRendererTest.html` — New test: `render()` calls `drawTouchResizeHandles` when `interactionState.pointerType === 'touch'`
- [ ] `TitleRendererTest.html` — New test: `render()` does NOT call `drawTouchResizeHandles` when `pointerType === 'mouse'`
- [ ] `TitleRendererTest.html` — New test: `render()` does NOT call `drawTouchResizeHandles` when `pointerType === 'pen'`
- [ ] `TitleInteractionTest.html` — New test: `state.titleInteractionPointerType` set to `'touch'` on touch pointerdown
- [ ] `TitleInteractionTest.html` — New test: `state.titleInteractionPointerType` cleared on interaction end
- [ ] Full test suite: `node scripts/run-tests.js` passes

#### Manual Verification:
- [ ] On mobile: resize handles visible when title is tapped
- [ ] On mobile: active resize handle highlighted in solid blue
- [ ] On desktop: no resize handles drawn (cursor feedback sufficient)
- [ ] Handles visible at all DPRs (test on Retina display)
- [ ] Handle size adequate for touch (minimum 16px diameter = 8px radius × 2)

---

## Known Behaviors and Edge Cases

### PointerEvents Migration (Phase 1)

1. **Safari iOS pointer capture**: `setPointerCapture` is supported in iOS Safari 13.4+. For older versions, the try/catch block (lines 274-277) handles gracefully.
2. **PointerEvent and TouchEvent coexistence**: On some Android browsers, both TouchEvent and PointerEvent fire for the same touch. By removing TouchEvent listeners entirely, we eliminate double-processing.
3. **`pointercancel` on device rotation**: Fires when orientation changes. Both MultiTouchHandler and TitleInteraction handle this via `_onPointerCancel` / `_onPointerUp`.
4. **Multiple pointer types on hybrid devices**: A Surface device may fire both touch and pen pointers. The `activePointers` Map handles this by tracking individual pointer IDs.
5. **TouchEvents still fire on some platforms**: Even with TouchEvent listeners removed, the PointerEvent path will capture all touch input. Any stray TouchEvents will be handled by the browser default (which is fine since we're not preventing them).

### Zoom Sensitivity (Phase 2)

1. **Exponent choice**: 0.3 was chosen as a balance. `2.0^0.3 = 1.23` per step (vs `2.0^0.15 = 1.11`). This is comparable to native iOS Photos pinch rate.
2. **Zoom threshold**: `zoomThreshold = 1.02` (line 192) means small finger jitter (<2% distance change) doesn't trigger zoom. Unchanged.
3. **Accumulated scale**: Initial distance resets after each zoom step (line 198), preventing exponential accumulation.

### touch-action: none (Phase 1)

1. **Page scrolling**: With `touch-action: none`, one-finger vertical drag on canvas no longer scrolls the page. This is acceptable because:
   - On mobile, the canvas fills the viewport (no content below to scroll to)
   - The bottom sheet and sidebars have their own scroll containers
   - The `no-scroll` class on `document.body` during bottom sheet open already prevents scroll
2. **iOS pull-to-refresh**: Blocked by `touch-action: none`. Acceptable trade-off.
3. **iOS back-swipe**: `touch-action: none` does NOT prevent the edge-swipe back gesture on iOS Safari. This is a browser-level behavior that cannot be disabled via CSS.

### Bottom Sheet Controls (Phase 3)

1. **ID prefixing**: All new IDs use `bs` prefix per the mobile bottom sheet convention. This prevents collision with desktop sidebar IDs.
2. **Vue reactivity**: All controls bind to the same `titleStyle` object. Changes in bottom sheet are immediately reflected on canvas.
3. **Undo snapshots**: `@focus="snapshotTitleStyle"` and `@blur="commitTitleStyle"` pattern matches desktop sidebar. Ensures undo works correctly.
4. **Scroll within bottom sheet**: Adding more controls increases scroll height. The bottom sheet panel has `overflow-y: auto` to handle this.
5. **Bold/Italic/Underline buttons**: These call `toggleTitleBold/Italic/Underline` which require `titleSelectionStart` and `titleSelectionEnd` to be set. The textarea `@select`, `@click`, `@keyup` handlers already populate these. Buttons are disabled when no text is selected.

### Resize Handles (Phase 4)

1. **DPR scaling**: Handle radius is 8 logical pixels. Canvas rendering handles DPR scaling automatically — the handle appears as 16px diameter on 1x display, 32px on 2x display.
2. **Handle overlap with text**: Handles are drawn at the box edges (left/right), not overlapping text content. The box includes PADDING (12px) around text.
3. **Multi-line titles**: `bounds.height` from `computeMultiLineBounds` accounts for multi-line height. Handles are vertically centered on the full box height.
4. **Legacy mode offset**: `outlineX` uses the same legacy mode offset logic as `drawInteractionOutline` (`isLegacyMode ? boxLeft - PADDING : boxLeft`).
5. **Active edge determination**: Uses `interactionState.hoverTarget` when hovering (pre-interaction) and `interactionState.interactionMode` when actively dragging. Both map to `'left-edge'` / `'right-edge'` / `'drag'` / `'resize-left'` / `'resize-right'`. The active check uses string matching: `activeEdge === 'left-edge'` or `activeEdge === 'resize-left'`.

---

## Testing Strategy

### Unit Tests (Mocha/Chai, browser-based)

**Existing test files to update**:
- `MyComponents/MultiTouchHandlerTest.html` — Remove TouchEvent tests, add PointerEvent touch tests, add zoom sensitivity tests
- `MyComponents/TitleInteractionTest.html` — Add pointerType tracking tests
- `MyComponents/TitleRendererTest.html` — Add `drawTouchResizeHandles` tests, add touch handle rendering in `render()`

**New test file**: `MyComponents/MobileTouchEnhancementTest.html` — Integration tests for the combined behavior:
1. **PointerEvents Migration** (Phase 1): ~12 tests
   - PointerEvent with `pointerType === 'touch'` not early-returned
   - `setPointerCapture` called per pointer
   - TouchEvent listeners not registered
   - `state._multiTouchGestureActive` set synchronously
   - Pointer capture released on gesture end
   - pointercancel cleanup
2. **Zoom Sensitivity** (Phase 2): ~4 tests
   - Exponent 0.3 produces correct factors
   - Zoom in and zoom out factors
   - Pure math functions unchanged
3. **CSS touch-action** (Phase 1): 1 test
   - `#previewCanvas` has `touch-action: none`
4. **Bottom Sheet Controls** (Phase 3): ~8 tests
   - Each of 7 new controls present
   - All IDs have `bs` prefix
5. **Resize Handles** (Phase 4): ~6 tests
   - Handle drawing positions
   - Active edge highlighting
   - Mouse vs touch differentiation

**Total new tests**: ~31

### E2E Tests (Playwright)

**New test file**: `tests/mobile-touch-enhancements.spec.js`

**Scenarios**:
1. Bottom sheet control visibility at mobile viewport (< 700px)
2. Bottom sheet control interaction (slider, checkbox, color picker)
3. Canvas touch-action CSS validation
4. Desktop regression: panel swap, title drag, trackpad gestures

### Manual Testing

**Required on real devices**:
1. **iOS Safari (iPhone)**: Two-finger pan, pinch-to-zoom, title drag, title resize, bottom sheet controls
2. **Chrome for Android**: Two-finger pan, pinch-to-zoom, title drag, title resize, bottom sheet controls
3. **Desktop browser (Chrome/Firefox/Safari)**: No regression in panel swap, title drag, trackpad gestures

---

## Performance Considerations

1. **PointerEvents vs TouchEvents**: PointerEvents are slightly more expensive per event (additional properties like `pointerId`, `pointerType`). However, the event frequency is identical for two-finger gestures, so there is no measurable performance impact.
2. **Resize handle rendering**: Two additional `arc()` calls per render frame during interaction. Negligible impact — the canvas is already rendering panels, images, and text.
3. **`touch-action: none`**: No JavaScript performance impact. May affect browser rendering pipeline slightly (no gesture prediction), but this is imperceptible.
4. **Bottom sheet scroll height**: Adding 7 controls increases the scrollable content of the Edit tab. The `overflow-y: auto` container handles this gracefully.

---

## Migration Notes

- The TouchEvent path removal in Phase 1 is a breaking change for any code that directly references `_onTouchStart`, `_onTouchMove`, or `_onTouchEnd`. These are internal handlers not used by any other module. The existing test file references them — those tests need to be updated.
- The `touch-action: none` change is a one-line CSS modification with no migration needed.
- The bottom sheet controls are additive — no existing functionality is removed.
- The resize handle rendering is conditional on `pointerType === 'touch'` — desktop behavior is unchanged.

---

## References

- Change request: `_agent_docs/specifications/change-requests/2026-07-29-01-mobile-touch-enhancements.md`
- World review analysis: session `ses_04f420d0dffeenged4kC8XIp7y`
- Planner analysis: session `ses_04f3e45ddffe3o5hVRWnGqKddV`
- Skill references: `building-web-apps` skill — PointerEvent/TouchEvent dual path, pointerType guards, setPointerCapture lifecycle, touch-action, VISIBLE_MIN clamping, global pointerup cleanup, Vue input patterns (undo snapshots), DPR scaling
