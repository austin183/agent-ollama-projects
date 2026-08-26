# Mobile Responsiveness Implementation Plan

## Overview

CollageMaker works well on desktop but has significant usability issues on phones and narrow viewports (< 700px). This plan addresses five reported issues:

1. **Two-finger pan goes the opposite direction** on phone (crop panning feels inverted)
2. **One-finger scroll conflicts with panel swipe gestures** — can't scroll the page
3. **Canvas hangs off the bottom of the page** — not constrained to viewport
4. **Layout is cramped below 700px** — sidebars squeeze the canvas
5. **Landscape orientation helps but isn't enough** — no responsive adaptation

These issues stem from three root causes:
- `touch-action: none` on canvas blocks ALL browser default touch gestures
- No responsive CSS breakpoints — layout is always three-panel desktop mode
- Crop pan delta may not match mobile user expectations for "drag follows finger"

## Current State Analysis

### CSS Layout (`Style.css`)
- **No media queries** — the entire stylesheet is desktop-only
- Body: `height: 100vh; overflow: hidden;` — no page scrolling possible
- Sidebars: fixed `width: 260px; min-width: 200px` — always consume 520px+ horizontal space
- Canvas: `max-width: 100%; max-height: 100%; touch-action: none;` — fills available space but blocks all touch defaults
- Flex chain: `body > #app > .main-layout > [sidebar, canvas-area, sidebar]` — all inline at all widths
- `.sidebar-collapsed` class exists for right sidebar toggle, but no equivalent for left sidebar

### Touch Handling (`MultiTouchHandler.js`)
- Three input paths: TouchEvent (mobile), PointerEvent (hybrid), WheelEvent (macOS trackpad)
- Two-finger pan: `dx = currentMidpoint.x - initialMidpoint.x` passed to `cropManager.adjustCrop(panelId, { x: dx * imageScale, y: dy * imageScale })`
- `preventDefault()` called on `touchmove` when gesture is active
- Exactly 2 fingers required (`e.touches.length !== 2`)
- Gesture-active flag (`state._multiTouchGestureActive`) coordinates with PanelSwap handler

### Crop Pan Direction Analysis
When user drags two fingers **right** on the canvas:
1. `dx` is positive (fingers moved right in screen coordinates)
2. `adjustCrop(panelId, { x: positive, y: ... })` shifts `sourceRect.x` **right**
3. Shifting `sourceRect.x` right shows more of the image's **right** side
4. The visible content appears to shift **left**

This is "scrolling" behavior (like a scroll wheel), NOT "direct manipulation" behavior. On a phone, users expect **direct manipulation**: dragging right moves the image right. The WheelEvent path (macOS trackpad) correctly uses scrolling convention, but the TouchEvent path should use direct manipulation convention.

### Canvas Viewport
- Canvas initialized at `1920 x 1080` with DPR scaling (`CanvasRenderer.js:52-65`)
- CSS: `max-width: 100%; max-height: 100%` — scales down to fit container
- Container (`.canvas-container`) has `flex: 1; min-height: 0; overflow: hidden`
- But body has `overflow: hidden` so the page itself can't scroll
- On a 375px wide phone with two 260px sidebars, canvas area is negative width

### PanelSwap Handler (`PanelSwap.js`)
- Uses PointerEvent for drag-and-drop panel swapping
- Guards against multi-touch gesture via `state._multiTouchGestureActive`
- No mobile-specific behavior — works the same on all devices
- `touch-action: none` on canvas means one-finger pointer events still fire (pointer events are not blocked by touch-action), but the browser can't scroll

### Key Discoveries
- `Style.css:341` — `#previewCanvas { touch-action: none; }` blocks ALL default touch gestures
- `Style.css:4-12` — `body { height: 100vh; overflow: hidden; }` prevents page scrolling
- `Style.css:126-136` — `.sidebar { width: 260px; min-width: 200px; }` fixed at all widths
- `MultiTouchHandler.js:169-180` — TouchEvent pan delta is `currentMidpoint - initialMidpoint` (positive = fingers moved right)
- `MultiTouchHandler.js:364-368` — WheelEvent pan uses `e.deltaX * sensitivity` (standard scroll convention)
- `createCollageLifecycle.js:316-318` — resize handler only re-renders crop preview, does NOT resize canvas
- `createCollageLifecycle.js:362` — `.sidebar-collapsed` CSS class exists for right sidebar
- `index.html:56-122` — Left sidebar uses same collapsible section pattern as right sidebar
- `css-layout.md` — Documents `SIDEBAR_CONFIG.MOBILE.width = 0` semantics for stacked layouts

## Desired End State

### After P0 (Critical Touch Fixes)
- Two-finger pan on phone: dragging right moves the image right (direct manipulation)
- Two-finger pan on trackpad: scrolling down scrolls the image down (scrolling convention, unchanged)
- One-finger vertical drag on canvas: does not trigger panel swap, allows natural gesture passthrough
- Canvas does not hang off the bottom of the viewport

### After P1 (Responsive Layout)
- Below 700px: left sidebar collapses to a toggle button, right sidebar collapses fully, canvas takes full width
- Canvas fits within viewport height with room for toolbar
- All controls accessible via toolbar buttons that open overlay panels

### After P2 (Polish)
- Landscape phone mode: sidebars hidden by default, accessible via toolbar toggle
- Touch targets meet 44x44px minimum (already satisfied per existing CSS)
- `env(safe-area-inset-bottom)` applied to bottom-positioned elements

## What We're NOT Doing

- **Bottom sheet / slide-up panels** — Full mobile-native UI redesign is out of scope. We use CSS breakpoints to hide sidebars and expose them via existing toggle buttons.
- **Tap-to-select interaction model** — Current pointer-based panel selection and drag-swap remain unchanged. Mobile users can tap panels to select them.
- **Preview scale reduction** — Canvas renders at full resolution on mobile. Performance optimization is a separate concern.
- **OS gesture conflict resolution** — iOS Safari two-finger swipe-back may still conflict with our two-finger pan. Acceptable trade-off.
- **New Vue components** — All changes are CSS + existing handler modifications. No new components or templates.
- **Responsive canvas resolution** — Canvas remains 1920x1080 logical pixels at all viewport sizes. CSS scaling handles display.

## Implementation Approach

Phases are ordered by dependency and risk:
1. **P0: Touch Gesture Fixes** — Negate TouchEvent pan delta, fix touch-action, ensure canvas fits viewport
2. **P1: Responsive CSS Layout** — Media queries at 700px breakpoint, sidebar collapse, canvas full-width
3. **P2: Mobile Polish** — Landscape refinement, safe areas, edge cases

---

## Phase 1: Touch Gesture Fixes (P0)

### Overview

Fix the three critical touch issues: inverted pan direction, blocked scrolling, and canvas overflow. These changes are surgical and low-risk — they modify only the TouchEvent path in MultiTouchHandler and CSS properties on the canvas.

### Behavior Specifications

#### User Behavior: Two-Finger Pan Direction

**Given** images are loaded and a panel is selected on the canvas
**When** the user places two fingers on the canvas and drags them to the right
**Then** the visible image content moves to the right (direct manipulation)

| # | Given | When | Then |
|---|-------|------|------|
| 1.1.1 | Panel selected, crop at default position | User drags two fingers 50px right on canvas | `sourceRect.x` decreases by approximately `50 * imageScale` pixels |
| 1.1.2 | Panel selected, crop at default position | User drags two fingers 50px down on canvas | `sourceRect.y` decreases by approximately `50 * imageScale` pixels |
| 1.1.3 | Panel selected, user pinches outward | Crop zooms in (sourceRect shrinks toward center) | Behavior unchanged from current |
| 1.1.4 | No panel selected | User drags two fingers on canvas | No crop adjustment occurs (early return in `startGesture`) |

#### User Behavior: One-Finger Touch Does Not Block Page

**Given** the app is loaded on a mobile device
**When** the user performs a one-finger vertical drag on the canvas area
**Then** the gesture does not trigger panel swap or crop adjustment

| # | Given | When | Then |
|---|-------|------|------|
| 1.2.1 | Images loaded, canvas visible | User performs one-finger vertical drag on canvas | PanelSwap handler does not activate (single finger, not two) |
| 1.2.2 | Images loaded, canvas visible | User performs one-finger tap on a panel | Panel is selected (pointer event fires normally) |
| 1.2.3 | Images loaded, panel selected | User performs one-finger drag on canvas | MultiTouchHandler does not activate (requires exactly 2 fingers) |

#### User Behavior: Canvas Fits in Viewport

**Given** the app is loaded on any device
**When** the page renders
**Then** the canvas is fully visible within the viewport and does not extend below the fold

| # | Given | When | Then |
|---|-------|------|------|
| 1.3.1 | Any viewport size | Page loads | `#previewCanvas` CSS height does not exceed its container's height |
| 1.3.2 | Mobile viewport (375px wide) | Page loads | Canvas scales to fit available space via `max-width: 100%; max-height: 100%` |

### Component Behavior: MultiTouchHandler TouchEvent Path

| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.4.1 | TouchEvent pan delta negated | Two touches move +50px in X | `adjustCrop` receives `x: -50 * imageScale` (negated) |
| 1.4.2 | TouchEvent pan delta negated Y | Two touches move +30px in Y | `adjustCrop` receives `y: -30 * imageScale` (negated) |
| 1.4.3 | WheelEvent pan NOT negated | `wheel` event with `deltaX: 5` | `adjustCrop` receives `x: 5 * sensitivity * imageScale` (NOT negated) |
| 1.4.4 | Pinch zoom unchanged | Pinch distance ratio 1.5 | `zoomCrop` receives factor `1.5^0.15` (unchanged) |
| 1.4.5 | One-finger touch ignored | `touchstart` with 1 touch | `startGesture` not called, no `preventDefault()` |

### Changes Required

#### 1. Negate TouchEvent Pan Delta in MultiTouchHandler

**File**: `MyESModules/Interaction/MultiTouchHandler.js`
**Changes**: In `processGesture()`, negate the delta before passing to `adjustCrop`. This affects the TouchEvent and PointerEvent paths. The WheelEvent path (`_onWheel`) does NOT call `processGesture()` — it has its own inline delta calculation and is completely unaffected.

**Input path impact:**

| Path | Platform | Calls `processGesture()`? | Affected by negation? |
|---|---|---|---|
| **TouchEvent** | Phone touchscreen | Yes | **Yes** — this is the fix |
| **PointerEvent** | Windows precision touchpad, hybrid devices | Yes | Yes — also becomes direct manipulation |
| **WheelEvent** | macOS trackpad | **No** — inline logic in `_onWheel()` | **No** — scrolling convention preserved |

The key insight: TouchEvent and PointerEvent use **direct manipulation** convention (drag right → image moves right), while WheelEvent uses **scrolling** convention (scroll down → view moves down). These are opposite conventions. The WheelEvent path (`_onWheel`, lines 355-398) computes its own delta from `e.deltaX`/`e.deltaY` and never calls `processGesture()`, so your macOS trackpad behavior is unchanged.

```javascript
// In processGesture() — lines 169-180
// CURRENT:
const dx = currentMidpoint.x - initialMidpoint.x;
const dy = currentMidpoint.y - initialMidpoint.y;
// ...
cropManager.adjustCrop(panelId, {
    x: dx * imageScale,
    y: dy * imageScale
});

// CHANGED — negate for direct manipulation convention:
const dx = currentMidpoint.x - initialMidpoint.x;
const dy = currentMidpoint.y - initialMidpoint.y;
// ...
cropManager.adjustCrop(panelId, {
    x: -dx * imageScale,  // Negate: drag right → crop shifts left → image moves right
    y: -dy * imageScale   // Negate: drag down → crop shifts up → image moves down
});
```

**Rationale**: When `sourceRect.x` increases, the crop window shifts right in the source image, revealing more of the right side — the visible content shifts left. Negating the delta makes dragging right decrease `sourceRect.x`, revealing more of the left side — the visible content shifts right, matching the finger direction.

**Note**: The PointerEvent path (hybrid devices like Surface Pro) also calls `processGesture()` and will inherit the negation. This is correct — a two-finger drag gesture on any touch-capable surface should follow direct manipulation convention. The WheelEvent path (macOS trackpad) is unaffected because it uses `e.deltaX`/`e.deltaY` directly in `_onWheel()` and never calls `processGesture()`.

#### 2. Change Canvas touch-action from `none` to `pan-y`

**File**: `Style.css`
**Changes**: Line 341, change `touch-action: none` to `touch-action: pan-y`

```css
/* CURRENT (line 341) */
#previewCanvas {
    touch-action: none;
}

/* CHANGED */
#previewCanvas {
    touch-action: pan-y;
}
```

**Rationale**: `touch-action: pan-y` tells the browser:
- Allow one-finger vertical scrolling natively
- JavaScript can still intercept two-finger gestures via `preventDefault()` on `touchmove`
- Horizontal one-finger swipes are handled by JavaScript (PanelSwap)

The MultiTouchHandler already calls `e.preventDefault()` on `touchmove` when a two-finger gesture is active (line 242), so two-finger vertical drag won't scroll the page — it will pan the crop.

**Risk assessment**: 
- One-finger vertical drag on canvas: browser handles native scroll → no panel swap, no crop adjustment
- One-finger horizontal drag on canvas: JavaScript handles (PanelSwap pointer events still fire)
- Two-finger drag on canvas: JavaScript handles (MultiTouchHandler `preventDefault()` blocks scroll)
- Pinch-to-zoom on canvas: JavaScript handles (MultiTouchHandler `preventDefault()` blocks browser zoom)

#### 3. Ensure Canvas Fits in Viewport

**File**: `Style.css`
**Changes**: The canvas already has `max-width: 100%; max-height: 100%` (lines 336-337). The issue is that the flex container chain may not constrain properly on mobile. Add explicit height constraint to `.canvas-container`:

```css
/* ADD to .canvas-container (line 298) */
.canvas-container {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: center;
    flex: 1;
    border-radius: var(--radius-medium);
    overflow: hidden;
    min-height: 0;
    max-height: calc(100vh - var(--space-8)); /* Account for toolbar height */
}
```

Also ensure `.canvas-area` properly constrains:
```css
/* VERIFY .canvas-area already has (line 285-296) */
.canvas-area {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    background-color: var(--color-background);
    overflow: hidden;
    padding: var(--space-4);
    min-width: 0;
    min-height: 0;
}
```

This is already correct. The real issue is the sidebars consuming space. Phase 2 addresses this.

### Success Criteria

#### Automated Verification:
- [ ] Unit tests for `computeTouchMidpoint` and `computeTouchDistance` still pass (unchanged pure functions)
- [ ] New unit test: `processGesture` with positive delta produces negated `adjustCrop` call
- [ ] New unit test: `_onWheel` with positive delta produces non-negated `adjustCrop` call
- [ ] `node scripts/run-tests.js` passes with zero failures

#### Manual Verification:
- [ ] On phone: two-finger drag right moves image content right
- [ ] On phone: two-finger drag down moves image content down
- [ ] On phone: pinch-to-zoom still works correctly
- [ ] On phone: one-finger tap selects a panel
- [ ] On phone: one-finger drag does not trigger panel swap
- [ ] On macOS: trackpad two-finger pan direction unchanged (scrolling convention)
- [ ] Canvas fits within viewport without hanging off bottom

---

## Phase 2: Responsive CSS Layout (P1)

### Overview

Add CSS media queries at 700px breakpoint to transform the three-panel desktop layout into a single-column mobile layout. Sidebars are hidden by default and accessible via toolbar toggle buttons.

### Behavior Specifications

#### User Behavior: Mobile Layout (< 700px)

**Given** the viewport width is below 700px
**When** the page loads or the window is resized below 700px
**Then** the layout switches to mobile mode

| # | Given | When | Then |
|---|-------|------|------|
| 2.1.1 | Viewport width 375px (iPhone portrait) | Page loads | Left sidebar is hidden, right sidebar is hidden, canvas takes full width |
| 2.1.2 | Viewport width 699px | Page loads | Same mobile layout as 375px |
| 2.1.3 | Viewport width 700px | Page loads | Desktop three-panel layout (sidebars visible) |
| 2.1.4 | Viewport width 701px | Page loads | Desktop three-panel layout (sidebars visible) |
| 2.1.5 | Desktop layout, user resizes to 600px | Window resize | Layout transitions to mobile mode |
| 2.1.6 | Mobile layout, user resizes to 800px | Window resize | Layout transitions back to desktop mode |

#### User Behavior: Mobile Sidebar Access

**Given** the app is in mobile layout (viewport < 700px)
**When** the user taps the sidebar toggle button
**Then** the sidebar opens as an overlay panel

| # | Given | When | Then |
|---|-------|------|------|
| 2.2.1 | Mobile layout, left sidebar hidden | User taps "Left panel" toolbar button | Left sidebar slides in as a full-height overlay on the left |
| 2.2.2 | Left sidebar overlay open | User taps outside the sidebar | Sidebar closes |
| 2.2.3 | Mobile layout, right sidebar hidden | User taps existing right sidebar toggle | Right sidebar slides in as a full-height overlay on the right |
| 2.2.4 | Either sidebar overlay open | Canvas is visible behind the overlay | Canvas remains interactive behind the overlay |

### Changes Required

#### 1. Add Mobile Toolbar Button for Left Sidebar

**File**: `index.html`
**Changes**: Add a left sidebar toggle button to the toolbar. The right sidebar toggle already exists (`#sidebarToggleBtn`). Add a matching button for the left sidebar.

```html
<!-- Add before the existing sidebarToggleBtn in toolbar-actions -->
<button id="leftSidebarToggleBtn" class="pure-button toolbar-icon-btn" @click="toggleLeftSidebar" title="Toggle image panel">
    <span class="material-icons">{{ leftSidebarOpen ? 'chevron_left' : 'chevron_right' }}</span>
</button>
```

**File**: `MyESModules/App/createCollageData.js`
**Changes**: Add `leftSidebarOpen` reactive data property (default `false` on mobile, determined by CSS media query).

**File**: `MyESModules/App/createCollageMethods.js`
**Changes**: Add `toggleLeftSidebar()` method.

#### 2. Add Mobile Media Queries

**File**: `Style.css`
**Changes**: Add media query block at end of stylesheet.

```css
/* ========================
 * Mobile Responsive Layout
 * ======================== */

@media (max-width: 699px) {
    /* Hide sidebars by default — they become overlay panels */
    .sidebar-left {
        position: fixed;
        top: 0;
        left: -280px; /* Off-screen */
        width: 280px;
        max-width: 85vw;
        height: 100vh;
        z-index: 150;
        box-shadow: var(--elevation-2);
        transition: left 0.25s ease;
        border-right: 1px solid var(--color-surface-variant);
    }

    .sidebar-left.mobile-open {
        left: 0;
    }

    /* Right sidebar: same overlay treatment */
    .sidebar-right {
        position: fixed;
        top: 0;
        right: -280px; /* Off-screen */
        width: 280px;
        max-width: 85vw;
        height: 100vh;
        z-index: 150;
        box-shadow: var(--elevation-2);
        transition: right 0.25s ease;
        border-left: 1px solid var(--color-surface-variant);
    }

    .sidebar-right.mobile-open {
        right: 0;
    }

    /* When right sidebar is toggled open via existing toggle, also apply mobile-open */
    .sidebar-right:not(.sidebar-collapsed) {
        /* In mobile, the existing toggle controls visibility */
    }

    /* Canvas area takes full width */
    .canvas-area {
        width: 100%;
    }

    /* Overlay backdrop when sidebar is open */
    .sidebar-overlay {
        display: none;
        position: fixed;
        top: 0;
        left: 0;
        right: 0;
        bottom: 0;
        background-color: rgba(0, 0, 0, 0.4);
        z-index: 140;
    }

    .sidebar-overlay.visible {
        display: block;
    }

    /* Toolbar: compact button labels on mobile */
    .pure-button-primary span:not(.material-icons),
    .pure-button span:not(.material-icons) {
        display: none; /* Hide text labels, show icons only */
    }

    /* Keep "Export" button text visible */
    .export-btn span:not(.material-icons) {
        display: inline;
    }

    /* App title: shorter on mobile */
    .app-title {
        font-size: var(--font-size-base);
    }

    /* Theme toggle: adjust position for mobile toolbar */
    #themeToggle {
        top: var(--space-2);
        right: var(--space-2);
    }
}

/* Landscape phone refinement */
@media (max-width: 699px) and (orientation: landscape) {
    .sidebar-left,
    .sidebar-right {
        width: 240px;
        max-width: 50vw;
    }

    /* In landscape, sidebars are narrower to preserve canvas space */
}
```

#### 3. Add Overlay Backdrop Element

**File**: `index.html`
**Changes**: Add a backdrop div that shows when a sidebar is open on mobile.

```html
<!-- After the canvas-area div, before the closing main-layout div -->
<div id="sidebarOverlay" class="sidebar-overlay" :class="{ visible: leftSidebarMobileOpen || rightSidebarMobileOpen }" @click="closeSidebars"></div>
```

#### 4. Wire Up Mobile Sidebar State

**File**: `MyESModules/App/createCollageData.js`
**Changes**: Add mobile sidebar state:

```javascript
// Add to data() return value
leftSidebarOpen: false,
leftSidebarMobileOpen: false,
rightSidebarMobileOpen: false,
```

**File**: `MyESModules/App/createCollageMethods.js`
**Changes**: Add methods:

```javascript
toggleLeftSidebar() {
    this.leftSidebarMobileOpen = !this.leftSidebarMobileOpen;
    if (this.leftSidebarMobileOpen) {
        this.rightSidebarMobileOpen = false;
    }
},

closeSidebars() {
    this.leftSidebarMobileOpen = false;
    this.rightSidebarMobileOpen = false;
},
```

**File**: `index.html`
**Changes**: Update sidebar classes to use mobile-open:

```html
<div id="sidebar-left" class="sidebar sidebar-left"
     :class="{ 'mobile-open': leftSidebarMobileOpen }">
```

```html
<div id="sidebar-right" class="sidebar sidebar-right"
     :class="{ 'sidebar-collapsed': !rightSidebarOpen, 'mobile-open': rightSidebarMobileOpen }">
```

### Success Criteria

#### Automated Verification:
- [ ] `node scripts/run-tests.js` passes with zero failures
- [ ] No new test failures from existing test suite

#### Manual Verification:
- [ ] At 375px width: sidebars hidden, canvas takes full width
- [ ] At 699px width: same mobile layout
- [ ] At 700px width: desktop layout with both sidebars visible
- [ ] At 701px width: desktop layout
- [ ] Mobile: tap left sidebar toggle → sidebar slides in from left
- [ ] Mobile: tap overlay backdrop → sidebar closes
- [ ] Mobile: tap right sidebar toggle → sidebar slides in from right
- [ ] Mobile: both sidebars cannot be open simultaneously
- [ ] Mobile: canvas remains interactive behind sidebar overlay
- [ ] Landscape phone: sidebars are narrower (50vw max)
- [ ] Toolbar buttons show icons only on mobile (text hidden)
- [ ] Resize from desktop to mobile and back: layout transitions smoothly
- [ ] No horizontal scroll on page at any width

---

## Phase 3: Mobile Polish (P2)

### Overview

Refinements for mobile usability: safe area insets, touch target verification, and edge case handling.

### Behavior Specifications

#### User Behavior: Safe Areas on Notch Devices

**Given** the app is loaded on an iPhone with a notch or dynamic island
**When** the page renders
**Then** bottom-positioned elements (toast notifications) do not overlap the home indicator

| # | Given | When | Then |
|---|-------|------|------|
| 3.1.1 | iPhone with notch, toast visible | Toast displays | Toast bottom is at `16px + safe-area-inset-bottom` from viewport edge |
| 3.1.2 | Device without notch, toast visible | Toast displays | Toast bottom is at 16px from viewport edge (fallback) |

### Changes Required

#### 1. Safe Area Insets

**File**: `Style.css`
**Changes**: The toast notification already uses `env(safe-area-inset-bottom)` (line 835). Verify and add to body:

```css
body {
    margin: 0;
    padding: 0;
    max-width: none;
    height: 100vh;
    /* Add safe area padding */
    padding-top: env(safe-area-inset-top, 0px);
    padding-bottom: env(safe-area-inset-bottom, 0px);
    display: flex;
    flex-direction: column;
    overflow: hidden;
    box-sizing: border-box;
}
```

#### 2. Touch Target Verification

**File**: `Style.css`
**Changes**: Verify all interactive elements meet 44x44px minimum. Existing elements already have `min-height: 44px` and `min-width: 44px` for buttons. Verify:
- `.segment-btn`: `min-height: 44px` ✓ (line 578)
- `.format-btn`: `width: 44px; height: 44px` ✓ (line 631-632)
- `.remove-btn`: `min-width: 44px; min-height: 44px` ✓ (line 262-263)
- `.toolbar-icon-btn`: `min-width: 44px; min-height: 44px` ✓ (line 427-428)
- `.image-item`: Check if tap target is large enough on mobile

```css
/* ADD: Ensure image items have adequate touch target on mobile */
@media (max-width: 699px) {
    .image-item {
        min-height: 44px;
    }
}
```

#### 3. Prevent Zoom on Input Focus (iOS)

**File**: `index.html`
**Changes**: Add minimum font size to prevent iOS auto-zoom on input focus:

```html
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
```

**Note**: `user-scalable=no` is generally discouraged for accessibility, but for a canvas-based editor where pinch-to-zoom is handled by our gesture system, it prevents double-zoom conflicts. Alternative: keep `user-scalable=yes` and handle the conflict in JavaScript.

**Decision**: Keep `user-scalable=yes` (default). The `touch-action: pan-y` change in Phase 1 already prevents browser zoom conflicts on the canvas area. Input elements in sidebars can still trigger browser zoom, which is acceptable.

### Success Criteria

#### Automated Verification:
- [ ] `node scripts/run-tests.js` passes with zero failures

#### Manual Verification:
- [ ] iPhone with notch: toast notification visible above home indicator
- [ ] iPhone with notch: toolbar visible below dynamic island
- [ ] All touch targets are tappable without mis-taps
- [ ] No accidental browser zoom when interacting with canvas
- [ ] Input focus in sidebar does not trigger unwanted page zoom

---

## Testing Strategy

### Unit Tests

**MultiTouchHandler.js** — New tests for negated TouchEvent delta:
1. `processGesture` with positive dx produces negated adjustCrop x parameter
2. `processGesture` with positive dy produces negated adjustCrop y parameter
3. `_onWheel` with positive deltaX produces non-negated adjustCrop x parameter
4. `_onWheel` with positive deltaY produces non-negated adjustCrop y parameter
5. One-finger touchstart does not activate gesture (existing behavior, verify)
6. Pinch zoom factor unchanged (regression test)

**Pure functions** — No changes needed:
- `computeTouchMidpoint` — unchanged
- `computeTouchDistance` — unchanged
- `computePinchScale` — unchanged

### E2E Tests (Playwright)

1. **Mobile viewport pan direction**: Set viewport to 375x812, fire two-finger touchmove, verify crop adjusted in correct direction
2. **Mobile viewport layout**: Set viewport to 375x812, verify sidebars are hidden, canvas takes full width
3. **Desktop viewport layout**: Set viewport to 1280x720, verify sidebars are visible
4. **Breakpoint transition**: Resize from 800px to 600px, verify layout changes
5. **Sidebar toggle on mobile**: Tap toggle button, verify sidebar overlay appears
6. **Overlay backdrop dismiss**: Tap backdrop, verify sidebar closes

### Manual Testing Steps

1. Open app on iPhone (or Chrome DevTools device emulation at 375x812)
2. Load images, select a panel
3. Two-finger drag right → verify image moves right
4. Two-finger drag down → verify image moves down
5. Pinch outward → verify zoom in works
6. One-finger tap on panel → verify panel selection works
7. Verify sidebars are hidden, canvas takes full width
8. Tap left sidebar toggle → verify sidebar slides in
9. Tap backdrop → verify sidebar closes
10. Rotate to landscape → verify layout adapts
11. Resize browser from wide to narrow → verify smooth transition
12. Test on iPhone with notch → verify safe areas respected

---

## Performance Considerations

- **CSS media queries** are evaluated by the browser engine — zero JavaScript cost
- **Fixed position sidebars** on mobile avoid layout recalculations during slide animation
- **`transition` property** on sidebar `left`/`right` uses CSS transforms — GPU-accelerated
- **Canvas rendering** unchanged — same 1920x1080 resolution at all viewport sizes
- **No new JavaScript listeners** for resize — existing `window.addEventListener('resize', ...)` in lifecycle handles crop preview re-render

---

## Migration Notes

- **No breaking changes** — all changes are additive (new CSS, new methods, new UI elements)
- **Existing desktop behavior preserved** — media queries only activate below 700px
- **Existing toggle button** (`#sidebarToggleBtn`) continues to work for right sidebar on both desktop and mobile
- **Existing collapsible sections** in sidebars continue to work unchanged
- **Existing touch gestures** (two-finger pan, pinch-to-zoom) continue to work with corrected direction

---

## References

- World-review analysis of mobile UX issues (session context)
- `Style.css` — current stylesheet, no responsive breakpoints
- `MultiTouchHandler.js` — three-path touch handling (TouchEvent, PointerEvent, WheelEvent)
- `building-web-apps/references/interaction.md` — touch-action CSS, multi-touch patterns
- `building-web-apps/references/css-layout.md` — flex chain, mobile safe areas
- `building-web-apps/references/accessibility.md` — touch target sizing (WCAG 2.5.8, 44x44px)
