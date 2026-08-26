# Expander Icon and Positions Implementation Plan

## Overview

Move sidebar toggle buttons from the top toolbar to floating edge icons (desktop), and replace the mobile hamburger menu with a floating action button (FAB) at the bottom of the screen. This change visually couples the toggle controls with their associated panels and animations, improving discoverability and reducing toolbar clutter.

**Source change request:** `_agent_docs/specifications/change-requests/2026-07-28-01-expander-icon-and-positions.md`

## Current State Analysis

### Desktop Sidebar Toggles (in toolbar)

- **Left sidebar toggle** (`#leftSidebarToggleBtn`, `index.html:54-56`): Shows `chevron_right` when open, `chevron_left` when closed. **BUG: This logic is inverted** — when open, clicking should collapse (arrow should point left = `chevron_left`), when closed, clicking should expand (arrow should point right = `chevron_right`).
- **Right sidebar toggle** (`#sidebarToggleBtn`, `index.html:57-59`): Shows `chevron_right` when open, `chevron_left` when closed. Same template logic, but for the right sidebar `chevron_right` when open is correct (points right = away from sidebar = collapse).
- Both use `.toolbar-icon-btn` + `.desktop-only` classes, inheriting z-index 100 from `.collage-toolbar`.

### Mobile Hamburger (in toolbar)

- **Bottom sheet toggle** (`#bottomSheetToggleBtn`, `index.html:25-30`): Static `menu` icon, `.mobile-only` class, inherits z-index 100 from toolbar. `aria-label="Menu"` (static).

### CSS Positioning

- Floating elements already exist: `#themeToggle` at `z-index: 200`, `position: fixed` (Style.css:372-398).
- Mobile media query: `@media (max-width: 699px)` (Style.css:942).
- Bottom sheet: `z-index: 160`, `position: fixed`, `bottom: 0`, `transform: translateY(100%)` (Style.css:1060-1081).
- Sidebars (mobile overlay): `z-index: 150` (Style.css:952, 978).
- Overlay backdrop: `z-index: 140` (Style.css:1012).

### Toggle Logic

- `toggleLeftSidebar()` / `toggleRightSidebar()` in `createCollageMethods.js:504-525` — toggle desktop + mobile state, mutually exclusive.
- `toggleBottomSheet()` in `createCollageMethods.js:549-581` — opens/closes bottom sheet, manages focus trap, scroll lock.
- `closeSidebars()` in `createCollageMethods.js:532-546` — closes all overlays, returns focus to `#bottomSheetToggleBtn`.

## Desired End State

### Desktop
- Left sidebar toggle: Floating icon on the **right edge** of the left sidebar (or left edge of viewport when collapsed). 40x40px minimum, rounded circle container, solid background. `chevron_right` when collapsed (expand → point into canvas), `chevron_left` when open (collapse → point out of canvas).
- Right sidebar toggle: Floating icon on the **left edge** of the right sidebar (or right edge of viewport when collapsed). Same styling. `chevron_left` when collapsed (expand → point into canvas), `chevron_right` when open (collapse → point out of canvas).
- Both at `z-index: 200` (above sidebars at 150, bottom sheet at 160).
- Hover states: background color change, subtle box-shadow.
- Tooltips via `title` attribute.
- `aria-controls` linking to `sidebar-left` / `sidebar-right`.
- Dynamic `aria-label`: "Expand left sidebar" / "Collapse left sidebar" (and right equivalents).

### Mobile
- FAB at bottom-center (or bottom-right to avoid center conflict with bottom sheet handle). 48x48px minimum touch target.
- Icon: `keyboard_arrow_up` when bottom sheet is closed, `keyboard_arrow_down` when open.
- Semi-transparent or solid brand-color background.
- `z-index: 200` (above bottom sheet at 160).
- Uses `env(safe-area-inset-bottom)` for iOS safe area.
- `aria-controls="bottomSheet"`.
- Dynamic `aria-label`: "Open menu" / "Close menu".

### Accessibility (all three toggles)
- `<button>` elements with `aria-expanded="true|false"`.
- `aria-controls` linking to target panel.
- Dynamic `aria-label` reflecting current action.
- Enter/Space key operability (inherited from `<button>`).

## What We're NOT Doing

- **No floating edge toggles for mobile sidebars** — the bottom sheet serves as the mobile navigation hub per world-review recommendation.
- **No JavaScript viewport detection** — mobile vs desktop is handled purely via CSS media queries and `.desktop-only` / `.mobile-only` classes.
- **No focus management on panel expand** — the spec says "consider" moving focus to first interactive element. This is deferred to a future iteration. Focus return on close is already handled.
- **No toolbar reorganization** — the freed toolbar space is left as-is. No centering or rearranging of remaining toolbar items.
- **No tooltip component** — standard HTML `title` attribute for discoverability, not a custom tooltip system.

## Implementation Approach

Three phases, each independently testable:

1. **Phase 1: Desktop floating edge icons** — Remove sidebar toggles from toolbar, add floating edge-positioned buttons with correct icon logic.
2. **Phase 2: Mobile FAB** — Remove hamburger from toolbar, add floating action button at bottom with dynamic chevron icon.
3. **Phase 3: Accessibility and polish** — Add aria-controls, dynamic aria-labels, hover states, tooltips, z-index adjustments.

## Phase 1: Desktop Floating Edge Icons

### Overview
Move left and right sidebar toggle buttons out of the toolbar and into floating positions on the viewport edges. Fix the inverted left-sidebar icon logic.

### Changes Required:

#### 1. HTML Template Changes
**File**: `index.html`

**Left sidebar toggle** (lines 54-56): Remove from toolbar. Add as a floating button outside the toolbar, positioned on the right edge of the left sidebar when open, or on the left edge of the viewport when collapsed.

```html
<!-- Left sidebar floating toggle — outside toolbar, positioned on viewport edge -->
<button id="leftSidebarToggleBtn" class="sidebar-float-btn sidebar-float-left desktop-only"
        @click="toggleLeftSidebar"
        :title="leftSidebarOpen ? 'Collapse image panel' : 'Expand image panel'"
        :aria-expanded="leftSidebarOpen"
        aria-controls="sidebar-left"
        :aria-label="leftSidebarOpen ? 'Collapse image panel' : 'Expand image panel'">
    <span class="material-icons">{{ leftSidebarOpen ? 'chevron_left' : 'chevron_right' }}</span>
</button>
```

**Right sidebar toggle** (lines 57-59): Remove from toolbar. Add as a floating button positioned on the left edge of the right sidebar when open, or on the right edge of the viewport when collapsed.

```html
<!-- Right sidebar floating toggle — outside toolbar, positioned on viewport edge -->
<button id="sidebarToggleBtn" class="sidebar-float-btn sidebar-float-right desktop-only"
        @click="toggleRightSidebar"
        :title="rightSidebarOpen ? 'Collapse editor panel' : 'Expand editor panel'"
        :aria-expanded="rightSidebarOpen"
        aria-controls="sidebar-right"
        :aria-label="rightSidebarOpen ? 'Collapse editor panel' : 'Expand editor panel'">
    <span class="material-icons">{{ rightSidebarOpen ? 'chevron_right' : 'chevron_left' }}</span>
</button>
```

**Placement in DOM**: Both buttons should be placed as direct children of `#app` (after the toolbar div, before `#mainLayout`) so they are positioned relative to the viewport via `position: fixed`.

#### 2. CSS Changes
**File**: `Style.css`

Add new classes for floating sidebar toggles:

```css
/* Floating sidebar toggle buttons — positioned on viewport edges */
.sidebar-float-btn {
    position: fixed;
    top: 50%;
    transform: translateY(-50%);
    z-index: 200;
    width: 40px;
    height: 40px;
    border-radius: 50%;
    background-color: var(--color-surface);
    border: 1px solid var(--color-surface-variant);
    color: var(--color-text-primary);
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    box-shadow: var(--elevation-1);
    transition: background-color var(--transition-fast),
                box-shadow var(--transition-fast),
                left var(--transition-normal, 0.25s) ease,
                right var(--transition-normal, 0.25s) ease;
    pointer-events: auto;
}

.sidebar-float-btn:hover {
    background-color: var(--color-primary);
    color: var(--color-on-primary);
    box-shadow: var(--elevation-2);
}

.sidebar-float-btn .material-icons {
    font-size: 20px;
}

/* Left sidebar toggle — positioned on right edge of left sidebar */
.sidebar-float-left {
    left: 260px; /* Matches .sidebar width */
}

/* When left sidebar is collapsed, move to left edge of viewport */
.sidebar-collapsed ~ .sidebar-float-left,
.main-layout:has(.sidebar-left.sidebar-collapsed) .sidebar-float-left {
    left: 0;
}

/* Right sidebar toggle — positioned on left edge of right sidebar */
.sidebar-float-right {
    right: 260px; /* Matches .sidebar width */
}

/* When right sidebar is collapsed, move to right edge of viewport */
.sidebar-collapsed ~ .sidebar-float-right,
.main-layout:has(.sidebar-right.sidebar-collapsed) .sidebar-float-right {
    right: 0;
}
```

**NOTE on positioning**: Since the sidebar width transitions (260px → 0px), using CSS `:has()` selector or a computed style approach is needed to position the toggle button at the correct edge. An alternative approach: use `position: fixed` with the button always at a fixed offset from the viewport edge, and animate its position with CSS transitions.

**Revised positioning approach** (simpler, no `:has()` dependency):

The floating buttons use `position: fixed` and their horizontal position is controlled by a Vue-computed CSS class or inline style. However, since we're using Vue 3 Options API and plain CSS, the cleanest approach is:

```css
/* Left toggle: when sidebar is open (260px wide), it sits at left: 260px */
/* When sidebar is collapsed (0px wide), it sits at left: 0 */
/* We use a CSS custom property set by Vue to control this */
.sidebar-float-left {
    left: var(--left-sidebar-width, 260px);
}

.sidebar-float-right {
    right: var(--right-sidebar-width, 260px);
}
```

Then in the Vue template, set the CSS custom property on `#app` or the button itself:

```html
<button id="leftSidebarToggleBtn" class="sidebar-float-btn sidebar-float-left desktop-only"
        :style="{ '--left-sidebar-width': leftSidebarOpen ? '260px' : '0px' }"
        ...>
```

**Simpler alternative**: Since the sidebar width transitions from 260px to 0px, we can use a simpler approach — the button is always at a fixed position relative to the viewport, and we use a CSS class bound to the sidebar state:

```css
.sidebar-float-left {
    left: 260px;
    transition: left 0.25s ease;
}

.sidebar-float-left.sidebar-collapsed {
    left: 0;
}

.sidebar-float-right {
    right: 260px;
    transition: right 0.25s ease;
}

.sidebar-float-right.sidebar-collapsed {
    right: 0;
}
```

With Vue binding:
```html
<button :class="{ 'sidebar-collapsed': !leftSidebarOpen }">
```

This is the cleanest approach — no JS positioning, pure CSS transitions.

#### 3. Icon Logic Fix
**File**: `index.html`

The left sidebar icon logic is inverted. The fix:
- Left sidebar open → `chevron_left` (point left = collapse the left panel)
- Left sidebar closed → `chevron_right` (point right = expand the left panel)
- Right sidebar open → `chevron_right` (point right = collapse the right panel)
- Right sidebar closed → `chevron_left` (point left = expand the right panel)

### Success Criteria:

#### Automated Verification:
- [ ] `node scripts/run-tests.js` — all existing tests pass (no regressions)
- [ ] `npx playwright test --config=playwright.config.cjs` — all existing E2E tests pass
- [ ] No console errors when toggling sidebars
- [ ] CSS custom properties / class bindings don't cause Vue warnings

#### Manual Verification:
- [ ] Left toggle icon shows `chevron_left` when sidebar is open, `chevron_right` when closed
- [ ] Right toggle icon shows `chevron_right` when sidebar is open, `chevron_left` when closed
- [ ] Left toggle button slides with sidebar edge during collapse/expand animation
- [ ] Right toggle button slides with sidebar edge during collapse/expand animation
- [ ] Buttons are visible and clickable when sidebars are collapsed (at viewport edges)
- [ ] Buttons have hover states (background color change)
- [ ] Buttons are hidden on mobile (max-width: 699px)
- [ ] Buttons don't interfere with canvas drag-and-drop interactions
- [ ] Z-index is correct — buttons appear above sidebars and canvas content

### Behavior Scenarios:

#### User Behavior — Desktop Sidebar Toggles

| # | Given | When | Then |
|---|-------|------|------|
| 1.1.1 | Left sidebar is open (260px wide) | User clicks the floating toggle on the right edge of the left sidebar | Left sidebar collapses to 0px, toggle slides to left viewport edge |
| 1.1.2 | Left sidebar is collapsed (0px wide) | User clicks the floating toggle on the left viewport edge | Left sidebar expands to 260px, toggle slides to right edge of sidebar |
| 1.1.3 | Right sidebar is open (260px wide) | User clicks the floating toggle on the left edge of the right sidebar | Right sidebar collapses to 0px, toggle slides to right viewport edge |
| 1.1.4 | Right sidebar is collapsed (0px wide) | User clicks the floating toggle on the right viewport edge | Right sidebar expands to 260px, toggle slides to left edge of sidebar |
| 1.1.5 | Both sidebars are open | User clicks left sidebar toggle | Left sidebar collapses, right sidebar remains open, left toggle moves to viewport edge |
| 1.1.6 | Both sidebars are collapsed | User clicks right sidebar toggle | Right sidebar expands, left sidebar remains collapsed, right toggle moves to sidebar edge |
| 1.1.7 | Left sidebar is open | User hovers over the floating toggle | Button background changes to primary color, icon changes to on-primary color, subtle shadow appears |
| 1.1.8 | Left sidebar is open | User presses Tab to focus the toggle, then Enter | Left sidebar collapses (same as click) |
| 1.1.9 | Left sidebar is open | User hovers over the toggle | Tooltip "Collapse image panel" appears |
| 1.1.10 | Left sidebar is collapsed | User hovers over the toggle | Tooltip "Expand image panel" appears |

#### Component Behavior — Icon Logic

| # | Given | When | Then |
|---|-------|------|------|
| 1.2.1 | `leftSidebarOpen` is `true` | Vue renders the left toggle button | Icon is `chevron_left` |
| 1.2.2 | `leftSidebarOpen` is `false` | Vue renders the left toggle button | Icon is `chevron_right` |
| 1.2.3 | `rightSidebarOpen` is `true` | Vue renders the right toggle button | Icon is `chevron_right` |
| 1.2.4 | `rightSidebarOpen` is `false` | Vue renders the right toggle button | Icon is `chevron_left` |

#### Component Behavior — Positioning

| # | Given | When | Then |
|---|-------|------|------|
| 1.3.1 | `leftSidebarOpen` is `true` | Vue renders the left toggle | Button has class `sidebar-collapsed` absent, CSS `left: 260px` |
| 1.3.2 | `leftSidebarOpen` is `false` | Vue renders the left toggle | Button has class `sidebar-collapsed` present, CSS `left: 0` |
| 1.3.3 | `rightSidebarOpen` is `true` | Vue renders the right toggle | Button has class `sidebar-collapsed` absent, CSS `right: 260px` |
| 1.3.4 | `rightSidebarOpen` is `false` | Vue renders the right toggle | Button has class `sidebar-collapsed` present, CSS `right: 0` |

#### E2E Test Scenarios (Playwright)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 1.4.e.1 | Left toggle visible and clickable at desktop | Desktop viewport (1400px), load app, verify toggle exists | `#leftSidebarToggleBtn` is visible, has `sidebar-float-btn` class |
| 1.4.e.2 | Left toggle slides with sidebar | Desktop, click left toggle twice | Toggle position changes from `left: 260px` to `left: 0` and back |
| 1.4.e.3 | Right toggle slides with sidebar | Desktop, click right toggle twice | Toggle position changes from `right: 260px` to `right: 0` and back |
| 1.4.e.4 | Left toggle hidden on mobile | Mobile viewport (375px), load app | `#leftSidebarToggleBtn` is not visible |
| 1.4.e.5 | Right toggle hidden on mobile | Mobile viewport (375px), load app | `#sidebarToggleBtn` is not visible |
| 1.4.e.6 | Icon logic correct for left sidebar | Desktop, verify icon when open, click, verify icon when closed | Open: `chevron_left`, Closed: `chevron_right` |
| 1.4.e.7 | Icon logic correct for right sidebar | Desktop, verify icon when open, click, verify icon when closed | Open: `chevron_right`, Closed: `chevron_left` |
| 1.4.e.8 | Toggle doesn't intercept canvas events | Desktop, click on canvas area (not on toggle) | Canvas click is registered, toggle state unchanged |

### Priority Ordering

| Priority | Scenarios | Rationale |
|----------|-----------|-----------|
| **P0** | 1.1.1-1.1.6, 1.2.1-1.2.4, 1.4.e.1-1.4.e.7 | Core functionality — toggles must work with correct icons |
| **P1** | 1.3.1-1.3.4, 1.4.e.2-1.4.e.5 | Positioning correctness — visual coupling with sidebar edges |
| **P2** | 1.1.7-1.1.10, 1.4.e.8 | Polish — hover states, tooltips, non-interference |

---

## Phase 2: Mobile FAB

### Overview
Replace the hamburger menu button in the toolbar with a floating action button (FAB) at the bottom of the screen. The FAB uses a dynamic chevron icon that couples with the bottom sheet animation.

### Changes Required:

#### 1. HTML Template Changes
**File**: `index.html`

**Remove** the hamburger button from the toolbar (lines 25-30):
```html
<!-- REMOVED: Hamburger menu from toolbar -->
<!-- <button id="bottomSheetToggleBtn" class="pure-button toolbar-icon-btn mobile-only" ...> -->
```

**Add** the FAB as a direct child of `#app` (after `#mainLayout`, before the bottom sheet):
```html
<!-- Mobile FAB — floating action button for bottom sheet -->
<button id="bottomSheetToggleBtn" class="mobile-fab mobile-only"
        @click="toggleBottomSheet"
        :aria-expanded="bottomSheetOpen"
        aria-controls="bottomSheet"
        :aria-label="bottomSheetOpen ? 'Close menu' : 'Open menu'">
    <span class="material-icons">{{ bottomSheetOpen ? 'keyboard_arrow_down' : 'keyboard_arrow_up' }}</span>
</button>
```

#### 2. CSS Changes
**File**: `Style.css`

Add new FAB styles. The FAB sits at the bottom-right of the viewport to avoid conflicting with the bottom sheet's center drag handle:

```css
/* Mobile FAB — floating action button for bottom sheet */
.mobile-fab {
    position: fixed;
    bottom: calc(var(--space-3) + env(safe-area-inset-bottom, 0px));
    right: var(--space-3);
    z-index: 200;
    width: 48px;
    height: 48px;
    border-radius: 50%;
    background-color: var(--color-primary);
    color: var(--color-on-primary);
    border: none;
    cursor: pointer;
    display: flex;
    align-items: center;
    justify-content: center;
    box-shadow: var(--elevation-2);
    transition: transform var(--transition-fast),
                background-color var(--transition-fast);
    pointer-events: auto;
}

.mobile-fab:hover {
    transform: scale(1.05);
}

.mobile-fab:active {
    transform: scale(0.95);
}

.mobile-fab .material-icons {
    font-size: 24px;
}

/* Hidden on desktop */
.mobile-fab {
    display: none;
}

/* Visible on mobile */
@media (max-width: 699px) {
    .mobile-fab {
        display: flex;
    }
}

/* Reduced motion */
@media (prefers-reduced-motion: reduce) {
    .mobile-fab {
        transition: none;
    }
}
```

#### 3. JS Changes
**File**: `MyESModules/App/createCollageMethods.js`

Update `closeSidebars()` (lines 532-546) — the focus return target is still `#bottomSheetToggleBtn` (same ID), so no change needed there.

Update `toggleBottomSheet()` (lines 549-581) — the focus return target is still `#bottomSheetToggleBtn`, no change needed.

Update `bsTouchEnd()` (lines 620-636) — focus return to `#bottomSheetToggleBtn`, no change needed.

**No JS changes required** — the ID remains the same, and the click handler is the same. The only behavioral difference is the icon change (handled in template) and the positioning (handled in CSS).

#### 4. Bottom Sheet Content Padding
**File**: `Style.css`

The bottom sheet needs padding at the bottom to avoid content being obscured by the FAB. The FAB is at `bottom: calc(var(--space-3) + env(safe-area-inset-bottom, 0px))` with height 48px. The bottom sheet already has `padding-bottom: env(safe-area-inset-bottom, 0px)` (line 1076). We need to add extra padding to account for the FAB:

```css
@media (max-width: 699px) {
    .bottom-sheet {
        /* ... existing styles ... */
        padding-bottom: calc(var(--space-3) + 48px + env(safe-area-inset-bottom, 0px));
    }
}
```

### Success Criteria:

#### Automated Verification:
- [ ] `node scripts/run-tests.js` — all existing tests pass
- [ ] `npx playwright test --config=playwright.config.cjs` — all existing E2E tests pass, including bottom-sheet.spec.js
- [ ] No console errors when toggling bottom sheet
- [ ] FAB element is queryable by `#bottomSheetToggleBtn` in tests

#### Manual Verification:
- [ ] FAB is visible on mobile (375px viewport) at bottom-right
- [ ] FAB is hidden on desktop (1400px viewport)
- [ ] FAB icon is `keyboard_arrow_up` when bottom sheet is closed
- [ ] FAB icon is `keyboard_arrow_down` when bottom sheet is open
- [ ] Clicking FAB opens bottom sheet, clicking again closes it
- [ ] FAB doesn't overlap bottom sheet content (padding adjustment)
- [ ] FAB is above bottom sheet in z-index (z-index: 200 > 160)
- [ ] FAB respects iOS safe area inset
- [ ] FAB is not visible when bottom sheet is hidden on desktop
- [ ] Hover/active states work on FAB
- [ ] Swipe-to-dismiss still works (focus returns to FAB)
- [ ] Escape key dismisses bottom sheet (focus returns to FAB)
- [ ] Backdrop click dismisses bottom sheet (focus returns to FAB)

### Behavior Scenarios:

#### User Behavior — Mobile FAB

| # | Given | When | Then |
|---|-------|------|------|
| 2.1.1 | Mobile viewport (375px), bottom sheet is closed | User taps the FAB at bottom-right | Bottom sheet slides up from bottom, FAB icon changes to `keyboard_arrow_down` |
| 2.1.2 | Mobile viewport, bottom sheet is open | User taps the FAB | Bottom sheet slides down, FAB icon changes to `keyboard_arrow_up` |
| 2.1.3 | Mobile viewport, bottom sheet is closed | User taps the FAB, then taps it again rapidly | Bottom sheet toggles correctly without state corruption |
| 2.1.4 | Mobile viewport, bottom sheet is open | User swipes down to dismiss | Bottom sheet closes, focus returns to FAB |
| 2.1.5 | Mobile viewport, bottom sheet is open | User presses Escape | Bottom sheet closes, focus returns to FAB |
| 2.1.6 | Mobile viewport, bottom sheet is open | User taps the backdrop overlay | Bottom sheet closes, focus returns to FAB |
| 2.1.7 | Desktop viewport (1400px) | User loads the app | FAB is not visible |
| 2.1.8 | Mobile viewport | User resizes to desktop | FAB disappears, sidebar toggles appear |
| 2.1.9 | Desktop viewport | User resizes to mobile | FAB appears, sidebar toggles disappear |
| 2.1.10 | Mobile viewport, bottom sheet is closed | User focuses FAB with Tab, presses Enter | Bottom sheet opens (same as tap) |
| 2.1.11 | Mobile viewport, bottom sheet is closed | User focuses FAB with Tab, presses Space | Bottom sheet opens (same as tap) |
| 2.1.12 | Mobile viewport, bottom sheet is open | User focuses FAB with Tab, presses Enter | Bottom sheet closes, focus stays on FAB |

#### Component Behavior — FAB Icon

| # | Given | When | Then |
|---|-------|------|------|
| 2.2.1 | `bottomSheetOpen` is `false` | Vue renders the FAB | Icon is `keyboard_arrow_up` |
| 2.2.2 | `bottomSheetOpen` is `true` | Vue renders the FAB | Icon is `keyboard_arrow_down` |

#### Component Behavior — FAB Positioning

| # | Given | When | Then |
|---|-------|------|------|
| 2.3.1 | Mobile viewport | FAB is rendered | `position: fixed`, `bottom` accounts for safe area, `right: var(--space-3)`, `z-index: 200` |
| 2.3.2 | Desktop viewport | FAB is rendered | `display: none` |

#### E2E Test Scenarios (Playwright)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 2.4.e.1 | FAB visible on mobile | Mobile viewport, load app | `#bottomSheetToggleBtn` is visible, has `mobile-fab` class |
| 2.4.e.2 | FAB hidden on desktop | Desktop viewport, load app | `#bottomSheetToggleBtn` is not visible |
| 2.4.e.3 | FAB opens bottom sheet | Mobile, click FAB | Bottom sheet is visible, FAB icon is `keyboard_arrow_down` |
| 2.4.e.4 | FAB closes bottom sheet | Mobile, open sheet, click FAB | Bottom sheet is hidden, FAB icon is `keyboard_arrow_up` |
| 2.4.e.5 | FAB doesn't block bottom sheet content | Mobile, open sheet, scroll content | Content is scrollable, not obscured by FAB |
| 2.4.e.6 | FAB respects safe area | Mobile with safe area inset | FAB bottom position includes safe area inset |
| 2.4.e.7 | Existing bottom sheet tests still pass | Run bottom-sheet.spec.js | All 7 existing tests pass |

### Priority Ordering

| Priority | Scenarios | Rationale |
|----------|-----------|-----------|
| **P0** | 2.1.1-2.1.2, 2.2.1-2.2.2, 2.4.e.1-2.4.e.4 | Core functionality — FAB must toggle bottom sheet with correct icons |
| **P1** | 2.1.4-2.1.6, 2.3.1-2.3.2, 2.4.e.5-2.4.e.7 | Dismissal paths and positioning — existing behavior preserved |
| **P2** | 2.1.3, 2.1.7-2.1.12 | Edge cases, resize transitions, keyboard operability |

---

## Phase 3: Accessibility and Polish

### Overview
Add accessibility attributes, hover states, tooltips, and verify z-index stacking. This phase ensures the floating controls meet WCAG requirements and feel polished.

### Changes Required:

#### 1. Accessibility Attributes
**File**: `index.html`

All three toggles already have:
- `aria-expanded` (bound to reactive state)
- `aria-controls` (added in Phase 1 for sidebars, Phase 2 for FAB)
- Dynamic `aria-label` (added in Phase 1 and Phase 2)

**Verification checklist:**
- [ ] Left sidebar toggle: `aria-expanded="leftSidebarOpen"`, `aria-controls="sidebar-left"`, dynamic `aria-label`
- [ ] Right sidebar toggle: `aria-expanded="rightSidebarOpen"`, `aria-controls="sidebar-right"`, dynamic `aria-label`
- [ ] FAB: `aria-expanded="bottomSheetOpen"`, `aria-controls="bottomSheet"`, dynamic `aria-label`

#### 2. Hover States (Desktop)
**File**: `Style.css`

The `.sidebar-float-btn:hover` styles are already defined in Phase 1. Verify:
- Background color transitions to primary
- Icon color transitions to on-primary
- Box-shadow increases (elevation-2)
- Transition is smooth (uses `--transition-fast`)

#### 3. Z-Index Verification
**File**: `Style.css`

Updated z-index stack:
| Element | z-index | Notes |
|---------|---------|-------|
| `.progress-overlay` | 10 | Canvas loading indicator |
| `.collage-toolbar` | 100 | Top toolbar |
| `.sidebar-overlay` | 140 | Backdrop for mobile overlays |
| `.sidebar-left` / `.sidebar-right` (mobile) | 150 | Mobile overlay panels |
| `.bottom-sheet` | 160 | Mobile bottom sheet |
| `.sidebar-float-btn` | 200 | Desktop floating toggles |
| `#themeToggle` | 200 | Theme toggle (existing) |
| `.mobile-fab` | 200 | Mobile FAB |
| `.toast-notification` | 9999 | Toast notifications |

The floating toggles at z-index 200 sit above all panels and overlays, ensuring they remain clickable even when sidebars or bottom sheet are open.

#### 4. Tooltip Text
**File**: `index.html`

Dynamic `title` attributes on desktop toggles:
- Left sidebar: `:title="leftSidebarOpen ? 'Collapse image panel' : 'Expand image panel'"`
- Right sidebar: `:title="rightSidebarOpen ? 'Collapse editor panel' : 'Expand editor panel'"`

The FAB doesn't need a `title` attribute (mobile context, screen readers use `aria-label`).

#### 5. Focus Return Update
**File**: `MyESModules/App/createCollageMethods.js`

The `closeSidebars()` method (line 542-544) returns focus to `#bottomSheetToggleBtn`. This still works since the FAB retains the same ID. No changes needed.

### Success Criteria:

#### Automated Verification:
- [ ] `node scripts/run-tests.js` — all tests pass
- [ ] `npx playwright test --config=playwright.config.cjs` — all E2E tests pass
- [ ] Accessibility audit: all three toggles have `aria-expanded`, `aria-controls`, and `aria-label`
- [ ] No axe-core violations for keyboard operability

#### Manual Verification:
- [ ] Screen reader announces correct label for each toggle state
- [ ] Tab navigation reaches all three toggles in correct order
- [ ] Enter/Space activates all three toggles
- [ ] Hover states are smooth and visually clear on desktop toggles
- [ ] Tooltips appear on hover for desktop toggles
- [ ] FAB is tappable with adequate touch target (48x48px)
- [ ] Desktop toggles have adequate touch target (40x40px)
- [ ] Z-index stacking is correct — toggles are always clickable above panels

### Behavior Scenarios:

#### User Behavior — Accessibility

| # | Given | When | Then |
|---|-------|------|------|
| 3.1.1 | Left sidebar is open | Screen reader focuses left toggle | Announces "Collapse image panel, button, expanded" |
| 3.1.2 | Left sidebar is closed | Screen reader focuses left toggle | Announces "Expand image panel, button, collapsed" |
| 3.1.3 | Right sidebar is open | Screen reader focuses right toggle | Announces "Collapse editor panel, button, expanded" |
| 3.1.4 | Right sidebar is closed | Screen reader focuses right toggle | Announces "Expand editor panel, button, collapsed" |
| 3.1.5 | Bottom sheet is closed | Screen reader focuses FAB | Announces "Open menu, button, collapsed" |
| 3.1.6 | Bottom sheet is open | Screen reader focuses FAB | Announces "Close menu, button, expanded" |
| 3.1.7 | Left toggle is focused | User presses Enter | Left sidebar toggles (same as click) |
| 3.1.8 | Left toggle is focused | User presses Space | Left sidebar toggles (same as click) |
| 3.1.9 | FAB is focused | User presses Enter | Bottom sheet toggles (same as tap) |
| 3.1.10 | FAB is focused | User presses Space | Bottom sheet toggles (same as tap) |

#### Component Behavior — ARIA Attributes

| # | Given | When | Then |
|---|-------|------|------|
| 3.2.1 | `leftSidebarOpen` is `true` | Vue renders left toggle | `aria-expanded="true"`, `aria-label="Collapse image panel"` |
| 3.2.2 | `leftSidebarOpen` is `false` | Vue renders left toggle | `aria-expanded="false"`, `aria-label="Expand image panel"` |
| 3.2.3 | `rightSidebarOpen` is `true` | Vue renders right toggle | `aria-expanded="true"`, `aria-label="Collapse editor panel"` |
| 3.2.4 | `rightSidebarOpen` is `false` | Vue renders right toggle | `aria-expanded="false"`, `aria-label="Expand editor panel"` |
| 3.2.5 | `bottomSheetOpen` is `true` | Vue renders FAB | `aria-expanded="true"`, `aria-label="Close menu"` |
| 3.2.6 | `bottomSheetOpen` is `false` | Vue renders FAB | `aria-expanded="false"`, `aria-label="Open menu"` |

#### E2E Test Scenarios (Playwright)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.3.e.1 | Left toggle aria-expanded updates | Desktop, toggle left sidebar | `aria-expanded` flips between "true" and "false" |
| 3.3.e.2 | Right toggle aria-expanded updates | Desktop, toggle right sidebar | `aria-expanded` flips between "true" and "false" |
| 3.3.e.3 | FAB aria-expanded updates | Mobile, toggle bottom sheet | `aria-expanded` flips between "true" and "false" |
| 3.3.e.4 | Left toggle aria-label is dynamic | Desktop, toggle left sidebar | Label changes between "Collapse" and "Expand" |
| 3.3.e.5 | FAB aria-label is dynamic | Mobile, toggle bottom sheet | Label changes between "Open menu" and "Close menu" |
| 3.3.e.6 | Enter key activates left toggle | Desktop, focus toggle, press Enter | Sidebar toggles |
| 3.3.e.7 | Space key activates left toggle | Desktop, focus toggle, press Space | Sidebar toggles |
| 3.3.e.8 | Enter key activates FAB | Mobile, focus FAB, press Enter | Bottom sheet toggles |
| 3.3.e.9 | Space key activates FAB | Mobile, focus FAB, press Space | Bottom sheet toggles |

### Priority Ordering

| Priority | Scenarios | Rationale |
|----------|-----------|-----------|
| **P0** | 3.2.1-3.2.6, 3.3.e.1-3.3.e.5 | ARIA attributes — critical for accessibility |
| **P1** | 3.1.7-3.1.10, 3.3.e.6-3.3.e.9 | Keyboard operability — required for WCAG |
| **P2** | 3.1.1-3.1.6 | Screen reader labels — important but secondary to keyboard |

---

## Testing Strategy

### Unit Tests (Mocha/Chai)
- Verify icon logic: given a state value, the template renders the correct icon name
- Verify aria attributes: given a state value, the button has the correct `aria-expanded` and `aria-label`
- Verify positioning classes: given a state value, the button has the correct CSS class for positioning
- These can be tested by mounting the Vue app in a test context and querying the DOM

### E2E Tests (Playwright)
- New test file: `test/e2e/expander-icons.spec.js`
- Covers all E2E scenarios from all three phases
- Desktop viewport (1400px) for sidebar toggle tests
- Mobile viewport (375px) for FAB tests
- Resize tests for transition between desktop and mobile
- All existing tests must continue to pass

### Manual Testing Steps
1. Open app at desktop viewport (1400x900)
2. Verify left toggle is on right edge of left sidebar, right toggle is on left edge of right sidebar
3. Click left toggle — verify sidebar collapses, toggle slides to left edge
4. Click left toggle again — verify sidebar expands, toggle slides back
5. Repeat for right toggle
6. Hover over toggles — verify hover states and tooltips
7. Resize to mobile (375x667)
8. Verify FAB is at bottom-right, sidebar toggles are hidden
9. Tap FAB — verify bottom sheet opens, icon changes
10. Tap FAB again — verify bottom sheet closes, icon changes
11. Swipe to dismiss — verify bottom sheet closes
12. Press Escape — verify bottom sheet closes
13. Resize back to desktop — verify FAB disappears, sidebar toggles reappear

## Performance Considerations

- CSS transitions for toggle positioning use `left`/`right` properties which trigger layout. For smoother animation, consider using `transform: translateX()` instead. However, since the sidebar itself uses `width` transitions (which also trigger layout), the performance impact is consistent with existing behavior.
- The FAB and floating toggles use `position: fixed` which is GPU-composited in modern browsers.
- No new JavaScript computation — positioning is handled entirely by CSS class bindings.

## Migration Notes

- The `#bottomSheetToggleBtn` ID is preserved, so existing test selectors and focus return logic continue to work.
- The `#leftSidebarToggleBtn` and `#sidebarToggleBtn` IDs are preserved.
- Existing E2E tests that reference `#bottomSheetToggleBtn` (bottom-sheet.spec.js) will need to be updated for the mobile viewport since the button is no longer in the toolbar. The button is still queryable by ID, but its position in the DOM changes.
- The `closeSidebars()` method's focus return to `#bottomSheetToggleBtn` continues to work without modification.

## References

- Change request: `_agent_docs/specifications/change-requests/2026-07-28-01-expander-icon-and-positions.md`
- World review: Inline analysis in this plan
- Existing bottom sheet plan: `_agent_docs/plans/2026-07-25-mobile-bottom-sheet-redesign.md`
- Existing bottom sheet review followups: `_agent_docs/plans/2026-07-27-mobile-bottom-sheet-review-followups.md`
- Building-web-apps skill: Mobile sidebar overlays, ARIA patterns, focus traps
- E2E test patterns: `test/e2e/bottom-sheet.spec.js`, `test/e2e/responsive-design.spec.js`
