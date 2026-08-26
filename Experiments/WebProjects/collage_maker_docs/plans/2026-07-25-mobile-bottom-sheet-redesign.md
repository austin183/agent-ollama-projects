# Mobile Bottom Sheet Redesign — Implementation Plan

**Date:** 2026-07-25
**Source:** Change request `2026-07-24-01-mobile-bottom-sheet-redesign.md`
**Priority:** P1 — Mobile usability improvement

---

## Overview

Replace the current mobile sidebar overlay pattern (two separate fixed-position panels sliding from left/right) with a single bottom sheet that slides up from the bottom of the screen. The bottom sheet contains a tab bar with three groups: **Images**, **Edit**, **Export**. A hamburger menu icon in the top-left of the toolbar opens the sheet. Desktop behavior is completely unchanged.

This addresses five identified problems:
1. Left sidebar toggle on far RIGHT of toolbar (thumb reach problem)
2. Two separate overlay panels (cognitive dissonance)
3. Right sidebar sections default collapsed (discoverability)
4. App title wastes toolbar real estate on mobile
5. Export buried in right sidebar

---

## Current State Analysis

### Mobile UI (below 700px breakpoint)

| Element | Current Behavior | File |
|---------|-----------------|------|
| Left sidebar toggle | Chevron icon on far RIGHT of toolbar, opens left panel | `index.html` line 47-49 |
| Right sidebar toggle | Chevron icon, opens right panel | `index.html` line 50-52 |
| App title | Visible in toolbar (`h2.app-title`) | `index.html` line 24 |
| Left sidebar | Fixed overlay, 280px, slides from left | `Style.css` lines 934-950 |
| Right sidebar | Fixed overlay, 280px, slides from right | `Style.css` lines 953-977 |
| Backdrop | `#sidebarOverlay`, `display: none` / `.visible` | `index.html` lines 155-157 |
| Escape key | `@keydown.escape.window.prevent="closeSidebars"` | `index.html` line 20 |

### State (createCollageData.js)

| Property | Line | Default | Purpose |
|----------|------|---------|---------|
| `leftSidebarMobileOpen` | 87 | `false` | Mobile left overlay visibility |
| `rightSidebarMobileOpen` | 88 | `false` | Mobile right overlay visibility |

### Methods (createCollageMethods.js)

| Method | Lines | Behavior |
|--------|-------|----------|
| `toggleLeftSidebar()` | 442-447 | Toggles `leftSidebarMobileOpen`, closes right if opening left |
| `toggleRightSidebar()` | 431-441 | Toggles both `rightSidebarOpen` and `rightSidebarMobileOpen`, closes left if opening right |
| `toggleRightSidebarMobile()` | 448-453 | Toggles `rightSidebarMobileOpen`, closes left if opening right |
| `closeSidebars()` | 454-457 | Sets both mobile states to `false` |

### CSS (Style.css)

Mobile media query: `@media (max-width: 699px)` at lines 932-1032, with landscape refinement at lines 1035-1041.

### Existing Tests

| Test File | Purpose |
|-----------|---------|
| `MyComponents/MobileSidebarTest.html` | 11 tests for sidebar state/methods |
| `MyComponents/ResponsiveCSSValidationTest.html` | 32 tests for CSS rules and DOM structure |
| `test/e2e/responsive-design.spec.js` | 24 Playwright tests for viewport breakpoints |

---

## Desired End State

After this plan is complete:

1. **Mobile toolbar** (below 700px): Hamburger menu icon (top-left), Add Images, Undo, Redo, Clear All. No app title. No sidebar toggle buttons.
2. **Bottom sheet**: Slides up from bottom (~70vh portrait, ~50vh landscape), 3-tab interface (Images, Edit, Export), backdrop overlay, dismissible via backdrop tap or Escape.
3. **Desktop**: No visible changes. Sidebars, toggles, and app title remain exactly as-is.
4. **State**: New `bottomSheetOpen` and `activeBottomSheetTab` properties. Old sidebar state retained for backward compatibility (deprecated in Phase 3).
5. **Accessibility**: `role="dialog"`, `aria-modal="true"`, proper tab/tabpanel ARIA pattern, 44x44px minimum touch targets.
6. **All existing tests pass**, new tests cover bottom sheet behavior.

---

## Key Discoveries

- **Sidebar DOM reuse**: The sidebar content templates (image library, layout controls, crop, background, overlay, title, export) are complex and already well-structured. The bottom sheet panels must duplicate this content for Phase 1. Phase 3 can refactor to shared templates.
- **Backdrop reuse**: The existing `#sidebarOverlay` element can be reused — just extend its `:class` binding to include `bottomSheetOpen`.
- **Escape key reuse**: The existing `@keydown.escape.window.prevent="closeSidebars"` on `#app` works — just update `closeSidebars()` to also close the bottom sheet.
- **CSS `display: none` for sidebars on mobile**: The mobile media query can hide both sidebars with `.sidebar-left, .sidebar-right { display: none !important; }` and show the bottom sheet. No JavaScript viewport detection needed.
- **`dvh` units**: Use `70dvh` (dynamic viewport height) instead of `70vh` for the bottom sheet max-height to handle iOS Safari address bar behavior.
- **Body scroll lock**: When bottom sheet is open, prevent background page scrolling via `document.body.style.overflow = 'hidden'`.

---

## What We're NOT Doing

- **No swipe-to-dismiss in Phase 1** — deferred to Phase 2 (touch gesture conflicts with scroll need careful handling)
- **No focus trapping in Phase 1** — deferred to Phase 2 (requires dedicated focus-trap utility)
- **No ARIA tab keyboard navigation in Phase 1** — deferred to Phase 2 (arrow key cycling between tabs)
- **No crop preview wiring in bottom sheet** — `bsCropPreviewCanvas` is rendered in the template but not wired to the crop renderer/interaction. Deferred to Phase 3 (crop editing unavailable in bottom sheet until deduplication)
- **No template deduplication** — bottom sheet panels duplicate sidebar content in Phase 1; deduplication is Phase 3
- **No desktop changes** — the bottom sheet is purely a mobile replacement; desktop retains existing three-panel layout
- **No Vue `<Transition>` component** — the bottom sheet uses CSS class toggling (`:class="{ 'bottom-sheet-open': bottomSheetOpen }"`) with CSS transitions, consistent with existing sidebar patterns
- **No new handler module** — bottom sheet methods are simple state toggles added to `createCollageMethods.js` (under 400 lines threshold for extraction)

---

## Implementation Approach

### Architecture Decision: Conditional CSS Rendering (Option A refined)

The bottom sheet is a **separate DOM subtree** in `index.html` with its own tab panels. The sidebar DOM elements remain for desktop. CSS media queries handle the visibility swap:

- **Desktop (>700px)**: Sidebars visible, bottom sheet `display: none`
- **Mobile (<700px)**: Sidebars `display: none !important`, bottom sheet visible

This avoids JavaScript viewport detection and keeps the template DRY at the CSS level. The trade-off is content duplication in the template (bottom sheet panels mirror sidebar content), which is acceptable for Phase 1 and addressed in Phase 3.

### Architecture Decision: New Methods, Not Repurposed

`toggleBottomSheet()` is a **new method** — `toggleLeftSidebar()` and `toggleRightSidebar()` are preserved for backward compatibility. The toolbar template uses `mobile-only` / `desktop-only` CSS classes to show/hide the appropriate toggle button per viewport.

---

## Phase 1: Core Bottom Sheet

### Overview

Implement the bottom sheet panel with tabbed navigation, hamburger menu toggle, backdrop dismissal, and Escape key support. All editing controls are accessible from the three tabs. Desktop UI is completely unaffected.

### Changes Required:

#### 1. State Properties

**File**: `MyESModules/App/createCollageData.js`
**Changes**: Add two new reactive properties after line 88 (after `rightSidebarMobileOpen`).

```javascript
// Bottom sheet (mobile)
bottomSheetOpen: false,
activeBottomSheetTab: 'images',  // 'images' | 'edit' | 'export'
```

#### 2. Methods

**File**: `MyESModules/App/createCollageMethods.js`
**Changes**: Add three new methods after the existing sidebar methods (after line 457). Update `closeSidebars()` to also close bottom sheet.

```javascript
// Bottom sheet methods (mobile)
toggleBottomSheet() {
    this.bottomSheetOpen = !this.bottomSheetOpen;
    if (this.bottomSheetOpen) {
        this.leftSidebarMobileOpen = false;
        this.rightSidebarMobileOpen = false;
    }
},
setBottomSheetTab(tabId) {
    this.activeBottomSheetTab = tabId;
},
```

Replace `closeSidebars()` (lines 454-457) with:

```javascript
closeSidebars() {
    this.leftSidebarMobileOpen = false;
    this.rightSidebarMobileOpen = false;
    this.bottomSheetOpen = false;
},
```

#### 3. Toolbar Template

**File**: `index.html`
**Changes**: Add hamburger menu button (mobile only), add `desktop-only` class to existing sidebar toggles, add `mobile-only` class to new hamburger button.

Add new button in `.toolbar-actions` (before the existing sidebar toggle buttons, around line 46):

```html
<!-- Hamburger menu — visible only on mobile -->
<button id="bottomSheetToggleBtn" class="pure-button toolbar-icon-btn mobile-only"
        @click="toggleBottomSheet"
        :aria-expanded="bottomSheetOpen"
        aria-label="Menu">
    <span class="material-icons">menu</span>
</button>
```

Add `desktop-only` class to existing sidebar toggles (lines 47 and 50):

```html
<button id="leftSidebarToggleBtn" class="pure-button toolbar-icon-btn desktop-only" ...>
<button id="sidebarToggleBtn" class="pure-button toolbar-icon-btn desktop-only" ...>
```

#### 4. Backdrop Binding

**File**: `index.html`
**Changes**: Extend `#sidebarOverlay` visibility binding (line 156) to include `bottomSheetOpen`.

```html
<div id="sidebarOverlay" class="sidebar-overlay"
     :class="{ visible: leftSidebarMobileOpen || rightSidebarMobileOpen || bottomSheetOpen }"
     @click="closeSidebars"></div>
```

#### 5. Bottom Sheet Template

**File**: `index.html`
**Changes**: Insert bottom sheet template after the toast notification (after line 167, before right sidebar).

The bottom sheet contains:
- Tab bar with 3 tabs (Images, Edit, Export) using `role="tablist"` / `role="tab"` / `role="tabpanel"`
- Images panel: mirrors left sidebar content (image library + layout controls)
- Edit panel: mirrors right sidebar sections (crop, background, overlay, title)
- Export panel: mirrors right sidebar export section

Each tab panel uses `v-show="activeBottomSheetTab === '...'"` for visibility toggling.

Key structural attributes:
```html
<div id="bottomSheet" class="bottom-sheet"
     :class="{ 'bottom-sheet-open': bottomSheetOpen }"
     role="dialog" aria-label="Menu" aria-modal="true">
    <div class="bottom-sheet-tab-bar" role="tablist" aria-label="Menu sections">
        <!-- 3 tab buttons -->
    </div>
    <div class="bottom-sheet-content">
        <!-- 3 tab panels with role="tabpanel" -->
    </div>
</div>
```

**Note**: The tab panel content duplicates the sidebar templates. This is intentional for Phase 1. A comment marks each panel: `<!-- DUPLICATE of sidebar-left/sidebar-right content — see Phase 3 migration -->`.

#### 6. CSS

**File**: `Style.css`
**Changes**: Add new CSS rules inside `@media (max-width: 699px)` block (after line 1032). Also add desktop-level rules for the bottom sheet (hidden by default).

Desktop-level (outside media query, before mobile block):

```css
/* Bottom sheet — hidden on desktop */
.bottom-sheet {
    display: none;
}
```

Inside `@media (max-width: 699px)`:

```css
/* Hide desktop elements on mobile */
.app-title { display: none; }
.desktop-only { display: none !important; }
.mobile-only { display: flex !important; }

/* Hide sidebars on mobile (replaced by bottom sheet) */
.sidebar-left,
.sidebar-right { display: none !important; }

/* Bottom sheet container */
.bottom-sheet {
    display: flex;
    flex-direction: column;
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    max-height: 70dvh;
    background-color: var(--color-surface);
    border-top-left-radius: 16px;
    border-top-right-radius: 16px;
    box-shadow: 0 -4px 20px rgba(0, 0, 0, 0.15);
    z-index: 160;
    transform: translateY(100%);
    transition: transform 0.3s ease;
    padding-bottom: env(safe-area-inset-bottom, 0px);
}

.bottom-sheet-open {
    transform: translateY(0);
}

/* Tab bar */
.bottom-sheet-tab-bar {
    display: flex;
    border-bottom: 1px solid var(--color-surface-variant);
    flex-shrink: 0;
}

.bottom-sheet-tab {
    flex: 1;
    padding: var(--space-3) var(--space-2);
    font-size: var(--font-size-sm);
    background: none;
    border: none;
    cursor: pointer;
    color: var(--color-text-secondary);
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
    min-height: 44px;
    transition: color var(--transition-fast), background-color var(--transition-fast);
}

.bottom-sheet-tab .material-icons { font-size: 20px; }

.bottom-sheet-tab:hover {
    background-color: var(--color-surface-variant);
}

.bottom-sheet-tab.active {
    color: var(--color-primary);
    border-bottom: 2px solid var(--color-primary);
}

/* Content area */
.bottom-sheet-content {
    flex: 1;
    overflow-y: auto;
    min-height: 0;
}

.bottom-sheet-panel {
    display: flex;
    flex-direction: column;
}
```

Landscape refinement (extend existing landscape media query):

```css
@media (max-width: 699px) and (orientation: landscape) {
    .bottom-sheet {
        max-height: 50dvh;
    }
}
```

### Behavior Scenarios — Phase 1

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 1.1.1 | App loaded on mobile viewport (375px) | User taps hamburger menu button | Bottom sheet slides up from bottom |
| 1.1.2 | Bottom sheet is open | User taps "Edit" tab | Edit panel displays, "Edit" tab highlighted, "Images" tab no longer highlighted |
| 1.1.3 | Bottom sheet is open | User taps dark backdrop | Bottom sheet slides down and closes |
| 1.1.4 | Bottom sheet is open | User presses Escape key | Bottom sheet slides down and closes |
| 1.1.5 | App loaded on desktop viewport (1920px) | User views toolbar | Hamburger button NOT visible, sidebar toggles ARE visible, no bottom sheet rendered |
| 1.1.6 | Bottom sheet open on "Images" tab, user has images loaded | User clicks "Add Images" and selects files | New images appear in image library within bottom sheet, count badge updates |
| 1.1.7 | Left sidebar mobile overlay is open | User taps hamburger menu | Bottom sheet opens, left sidebar overlay closes |
| 1.1.8 | Bottom sheet is open on "Export" tab | User taps "Export JPEG" button | Export proceeds normally (same behavior as desktop) |
| 1.1.9 | Bottom sheet is open | User rotates device to landscape | Bottom sheet adjusts to ~50vh height, content remains accessible |
| 1.1.10 | App loaded on mobile, bottom sheet closed | User opens bottom sheet, then closes it | Active tab remains "Images" (default), no state loss |

#### Component Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 1.2.1 | `bottomSheetOpen` is `false` | `toggleBottomSheet()` called | `bottomSheetOpen` is `true`, `leftSidebarMobileOpen` is `false`, `rightSidebarMobileOpen` is `false` |
| 1.2.2 | `bottomSheetOpen` is `true` | `toggleBottomSheet()` called | `bottomSheetOpen` is `false` |
| 1.2.3 | `activeBottomSheetTab` is `'images'` | `setBottomSheetTab('edit')` called | `activeBottomSheetTab` is `'edit'`, `bottomSheetOpen` unchanged |
| 1.2.4 | All three overlays open (`leftSidebarMobileOpen`, `rightSidebarMobileOpen`, `bottomSheetOpen` all `true`) | `closeSidebars()` called | All three are `false` |
| 1.2.5 | `leftSidebarMobileOpen` is `true`, `bottomSheetOpen` is `false` | `toggleBottomSheet()` called | `bottomSheetOpen` is `true`, `leftSidebarMobileOpen` is `false` |
| 1.2.6 | Fresh data from `createCollageData()` | Data function called | `bottomSheetOpen` is `false`, `activeBottomSheetTab` is `'images'` |
| 1.2.7 | `bottomSheetOpen` is `false`, `rightSidebarOpen` is `true` (desktop) | `toggleBottomSheet()` called | `bottomSheetOpen` is `true`, `rightSidebarOpen` unchanged (desktop state not affected) |

#### Pure Function Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 1.3.1 | Valid tab IDs are `'images'`, `'edit'`, `'export'` | `setBottomSheetTab('export')` called | `activeBottomSheetTab` equals `'export'` |
| 1.3.2 | `bottomSheetOpen` is `false`, `leftSidebarMobileOpen` is `false`, `rightSidebarMobileOpen` is `false` | `closeSidebars()` called | All three remain `false` (idempotent) |

### Unit Test Scenarios

**New test file**: `MyComponents/BottomSheetTest.html`

| # | Test | Input | Expected |
|---|------|-------|----------|
| BS-01 | `bottomSheetOpen` defaults to `false` | Fresh data | `false` |
| BS-02 | `activeBottomSheetTab` defaults to `'images'` | Fresh data | `'images'` |
| BS-03 | `toggleBottomSheet()` opens bottom sheet | `bottomSheetOpen: false` | `bottomSheetOpen: true` |
| BS-04 | `toggleBottomSheet()` closes when already open | `bottomSheetOpen: true` | `bottomSheetOpen: false` |
| BS-05 | `toggleBottomSheet()` closes left sidebar | `leftSidebarMobileOpen: true`, `bottomSheetOpen: false` → toggle | `bottomSheetOpen: true`, `leftSidebarMobileOpen: false` |
| BS-06 | `toggleBottomSheet()` closes right sidebar | `rightSidebarMobileOpen: true`, `bottomSheetOpen: false` → toggle | `bottomSheetOpen: true`, `rightSidebarMobileOpen: false` |
| BS-07 | `setBottomSheetTab('edit')` changes active tab | `activeBottomSheetTab: 'images'` | `activeBottomSheetTab: 'edit'` |
| BS-08 | `setBottomSheetTab('export')` changes active tab | `activeBottomSheetTab: 'images'` | `activeBottomSheetTab: 'export'` |
| BS-09 | `setBottomSheetTab('images')` changes active tab | `activeBottomSheetTab: 'edit'` | `activeBottomSheetTab: 'images'` |
| BS-10 | `closeSidebars()` closes bottom sheet | `bottomSheetOpen: true` | `bottomSheetOpen: false` |
| BS-11 | `closeSidebars()` closes all three overlays | All three `true` | All three `false` |
| BS-12 | Opening bottom sheet does not affect `rightSidebarOpen` | `rightSidebarOpen: true` (desktop), toggle bottom sheet | `rightSidebarOpen` unchanged |

**Updated test file**: `MyComponents/MobileSidebarTest.html`

| # | Test | Input | Expected |
|---|------|-------|----------|
| Mobile-12 | `closeSidebars()` also closes bottom sheet | `bottomSheetOpen: true` | `bottomSheetOpen: false` |
| Mobile-13 | `toggleLeftSidebar()` does not open bottom sheet | `bottomSheetOpen: false` | `bottomSheetOpen: false` |
| Mobile-14 | `toggleRightSidebarMobile()` does not open bottom sheet | `bottomSheetOpen: false` | `bottomSheetOpen: false` |

**Updated test file**: `MyComponents/ResponsiveCSSValidationTest.html`

| # | Test | Expected |
|---|------|----------|
| BS-CSS-01 | `.bottom-sheet` class exists in mobile media query | CSS includes `.bottom-sheet` inside `@media (max-width: 699px)` |
| BS-CSS-02 | `.bottom-sheet` uses `position: fixed` | CSS rule contains `position: fixed` |
| BS-CSS-03 | `.bottom-sheet` uses `transform: translateY(100%)` for hidden | CSS rule contains `transform: translateY(100%)` |
| BS-CSS-04 | `.bottom-sheet-open` uses `transform: translateY(0)` | CSS rule contains `transform: translateY(0)` |
| BS-CSS-05 | `.bottom-sheet` accounts for safe area | CSS contains `env(safe-area-inset-bottom` |
| BS-CSS-06 | `.sidebar-left` and `.sidebar-right` hidden on mobile | Mobile media query contains `display: none` for both |
| BS-CSS-07 | `.desktop-only` hides elements on mobile | Mobile media query contains `.desktop-only { display: none }` |
| BS-CSS-08 | `.mobile-only` shows hamburger on mobile | Mobile media query contains `.mobile-only { display: flex }` |
| BS-CSS-09 | `.app-title` hidden on mobile | Mobile media query contains `.app-title { display: none }` |
| BS-CSS-10 | `.bottom-sheet-tab` has `min-height: 44px` | CSS rule contains `min-height: 44px` |
| BS-CSS-11 | `.bottom-sheet` uses `dvh` units | CSS contains `dvh` for max-height |
| BS-CSS-12 | Landscape media query sets 50dvh | `@media ... landscape` contains `max-height: 50dvh` |

### E2E Test Scenarios (Playwright)

**New test file**: `test/e2e/bottom-sheet.spec.js`

| # | Test | Steps | Expected |
|---|------|-------|----------|
| BS-E2E-01 | Hamburger visible on mobile | Load at 375px | `#bottomSheetToggleBtn` visible |
| BS-E2E-02 | Sidebar toggles hidden on mobile | Load at 375px | `#leftSidebarToggleBtn` and `#sidebarToggleBtn` not visible |
| BS-E2E-03 | App title hidden on mobile | Load at 375px | `.app-title` not visible |
| BS-E2E-04 | Bottom sheet opens on hamburger tap | Mobile, tap hamburger | `#bottomSheet` has `bottom-sheet-open` class |
| BS-E2E-05 | Bottom sheet closes on backdrop tap | Open sheet, tap backdrop | `#bottomSheet` no longer has `bottom-sheet-open` class |
| BS-E2E-06 | Bottom sheet closes on Escape | Open sheet, press Escape | `#bottomSheet` no longer has `bottom-sheet-open` class |
| BS-E2E-07 | Tab switching works | Open sheet, tap each tab | Active tab changes, content switches |
| BS-E2E-08 | Images tab shows image library | Open sheet, Images tab | `.image-library` visible in bottom sheet |
| BS-E2E-09 | Export tab shows export controls | Open sheet, tap Export | Export format selector and button visible |
| BS-E2E-10 | Bottom sheet NOT visible on desktop | Load at 1920px | `#bottomSheet` not in DOM or `display: none` |
| BS-E2E-11 | Sidebar toggles visible on desktop | Load at 1920px | Both sidebar toggle buttons visible |
| BS-E2E-12 | State preserved when sheet opens/closes | Upload images, open/close sheet | Images still present, canvas still renders |
| BS-E2E-13 | Backdrop overlay visible when sheet open | Open sheet | `.sidebar-overlay.visible` present |
| BS-E2E-14 | Hamburger `aria-expanded` reflects state | Toggle sheet open/closed | `aria-expanded` matches `bottomSheetOpen` |

### Success Criteria:

#### Automated Verification:
- [ ] `node scripts/run-tests.js` — all existing tests pass (MobileSidebarTest, ResponsiveCSSValidationTest, all unit tests)
- [ ] `BottomSheetTest.html` — all 12 new unit tests pass
- [ ] `MobileSidebarTest.html` — 3 new regression tests pass, all 11 existing tests still pass
- [ ] `ResponsiveCSSValidationTest.html` — all 12 new CSS validation tests pass
- [ ] `test/e2e/bottom-sheet.spec.js` — all 14 E2E tests pass (with dev server running)
- [ ] `test/e2e/responsive-design.spec.js` — all 24 existing tests still pass

#### Manual Verification:
- [ ] Bottom sheet slides up smoothly when hamburger is tapped (mobile viewport 375px)
- [ ] All three tabs display correct content (Images: library + layout, Edit: crop + background + overlay + title, Export: format + quality + button)
- [ ] Backdrop tap dismisses bottom sheet
- [ ] Escape key dismisses bottom sheet
- [ ] App title is hidden on mobile, visible on desktop
- [ ] Sidebar toggle buttons hidden on mobile, visible on desktop
- [ ] Hamburger button hidden on desktop, visible on mobile
- [ ] Bottom sheet respects `env(safe-area-inset-bottom)` on iOS (test on device or Safari simulator)
- [ ] Landscape orientation reduces bottom sheet height
- [ ] Export from bottom sheet produces same output as desktop export
- [ ] Image operations (add, remove, select) work from bottom sheet
- [ ] Layout controls in bottom sheet affect canvas rendering
- [ ] Crop preview canvas in bottom sheet is blank (expected — wired in Phase 3)
- [ ] No horizontal overflow at 320px viewport

---

## Phase 2: Polish

### Overview

Add swipe-to-dismiss gesture, focus trapping, reduced motion support, and refined landscape behavior.

### Changes Required:

#### 1. ARIA Tab Keyboard Navigation

**File**: `index.html` (bottom sheet tab bar)
**Changes**: Add `@keydown` handler to tab buttons for arrow key cycling (Left/Right/Home/End).

Behavior:
- Left/Up arrow: move focus to previous tab (wrap to last)
- Right/Down arrow: move focus to next tab (wrap to first)
- Home: move focus to first tab
- End: move focus to last tab
- Enter/Space on focused tab: activate tab (already handled by `@click`)

#### 2. Focus Trapping

**File**: `MyESModules/App/createCollageMethods.js`
**Changes**: When `toggleBottomSheet()` opens the sheet, focus the first focusable element in the bottom sheet. Add a `@keydown.tab` handler that cycles focus within the panel.

Behavior:
- On open: `document.querySelector('#bottomSheet :focusable:first-child').focus()`
- On close: Return focus to `#bottomSheetToggleBtn`
- Tab key: Cycle through focusable elements within `#bottomSheet` only

#### 3. Swipe-to-Dismiss Gesture

**File**: `index.html` (bottom sheet content area)
**Changes**: Add `@touchstart` and `@touchend` handlers to `.bottom-sheet-content`.

**File**: `MyESModules/App/createCollageMethods.js`
**Changes**: Add `_bottomSheetTouchStart` and `_bottomSheetTouchEnd` methods.

Behavior:
- Track `touchstartY` on touchstart
- On touchend, compute `deltaY = touchEndY - touchstartY`
- If `deltaY > 100` (swiped down more than 100px), close bottom sheet
- **Only activate when scroll position is at top** (`scrollTop === 0`) — prevents conflict with content scrolling
- Apply `transform: translateY(deltaY)` during drag for visual feedback (requires tracking touchmove)

#### 4. Reduced Motion

**File**: `Style.css`
**Changes**: Add `prefers-reduced-motion` media query inside mobile block.

```css
@media (max-width: 699px) and (prefers-reduced-motion: reduce) {
    .bottom-sheet {
        transition: none;
    }
}
```

#### 5. Body Scroll Lock

**File**: `MyESModules/App/createCollageMethods.js`
**Changes**: In `toggleBottomSheet()`, set `document.body.style.overflow = 'hidden'` when opening, restore to `''` when closing.

### Behavior Scenarios — Phase 2

| # | Given | When | Then |
|---|-------|------|------|
| 2.1.1 | Bottom sheet open, "Images" tab focused | User presses Right arrow | Focus moves to "Edit" tab, "Edit" tab activated |
| 2.1.2 | Bottom sheet open, "Export" tab focused | User presses Right arrow | Focus wraps to "Images" tab |
| 2.1.3 | Bottom sheet open, "Edit" tab focused | User presses Left arrow | Focus moves to "Images" tab |
| 2.1.4 | Bottom sheet open, user presses Tab | — | Focus cycles within bottom sheet elements only |
| 2.1.5 | Bottom sheet open, user closes via Escape | — | Focus returns to hamburger button |
| 2.1.6 | Bottom sheet open, content scrolled to top | User swipes down >100px | Bottom sheet closes |
| 2.1.7 | Bottom sheet open, content scrolled down | User swipes down >100px | Content scrolls, sheet does NOT close |
| 2.1.8 | User has `prefers-reduced-motion: reduce` | Opens bottom sheet | Sheet appears instantly (no animation) |
| 2.1.9 | Bottom sheet open | User scrolls background page | Background page does NOT scroll |

### Unit Test Scenarios — Phase 2

| # | Test | Input | Expected |
|---|------|-------|----------|
| BS-P2-01 | Right arrow on Images tab moves to Edit | `activeBottomSheetTab: 'images'`, keydown Right | `activeBottomSheetTab: 'edit'` |
| BS-P2-02 | Right arrow on Export tab wraps to Images | `activeBottomSheetTab: 'export'`, keydown Right | `activeBottomSheetTab: 'images'` |
| BS-P2-03 | Left arrow on Images tab wraps to Export | `activeBottomSheetTab: 'images'`, keydown Left | `activeBottomSheetTab: 'export'` |
| BS-P2-04 | Swipe down from top closes sheet | `scrollTop: 0`, `deltaY: 150` | `bottomSheetOpen: false` |
| BS-P2-05 | Swipe down from scrolled position does not close | `scrollTop: 50`, `deltaY: 150` | `bottomSheetOpen: true` (unchanged) |
| BS-P2-06 | Small swipe does not close | `scrollTop: 0`, `deltaY: 50` | `bottomSheetOpen: true` (unchanged) |

### E2E Test Scenarios — Phase 2

| # | Test | Steps | Expected |
|---|------|-------|----------|
| BS-E2E-15 | Arrow keys cycle tabs | Open sheet, press Right arrow twice | Focus moves Images → Edit → Export |
| BS-E2E-16 | Arrow keys wrap | On Export tab, press Right arrow | Focus wraps to Images tab |
| BS-E2E-17 | Escape returns focus to hamburger | Open sheet, press Escape | `#bottomSheetToggleBtn` has focus |
| BS-E2E-18 | Swipe down dismisses | Open sheet, swipe down from top | Sheet closes |
| BS-E2E-19 | Swipe down from scrolled content does not dismiss | Scroll down in sheet, swipe down | Content scrolls, sheet stays open |

### Success Criteria:

#### Automated Verification:
- [x] All Phase 1 tests still pass
- [x] Phase 2 unit tests pass (BS-P2-01 through BS-P2-13)
- [ ] Phase 2 E2E tests pass (BS-E2E-15 through BS-E2E-19)

#### Manual Verification:
- [ ] Arrow keys cycle between tabs (Right/Left/Home/End)
- [ ] Arrow keys wrap at boundaries (Right from Export → Images, Left from Images → Export)
- [ ] Tab key cycles focus within bottom sheet
- [ ] Escape key returns focus to hamburger button
- [ ] Swipe down from top of bottom sheet dismisses it
- [ ] Scrolling content in bottom sheet does not trigger dismiss
- [ ] Reduced motion preference eliminates animation
- [ ] Background page does not scroll when bottom sheet is open

---

## Phase 3: Migration

### Overview

Deprecate the old dual-sidebar mobile state, remove unused CSS, and update tests. This phase is cleanup-only — no new user-facing behavior.

### Changes Required:

#### 1. Wire Bottom Sheet Crop Preview

**File**: `index.html` (app root `domIds` binding)
**Changes**: Register `bsCropPreviewCanvas` in `domIds` so the crop preview renderer and interaction handler can find it.

**File**: `MyESModules/Rendering/createCropPreviewRenderer.js`
**File**: `MyESModules/Interaction/CropInteraction.js`
**Changes**: Update to support dual canvas IDs — render crop preview and attach drag handles to both `cropPreviewCanvas` (desktop sidebar) and `bsCropPreviewCanvas` (mobile bottom sheet).

**Approach**: The simplest path is to deduplicate the crop preview into a shared module that renders to both canvases on each update. This avoids maintaining two separate crop preview renderers.

#### 2. Deprecate Old State

**File**: `MyESModules/App/createCollageData.js`
**Changes**: Add JSDoc deprecation comments to `leftSidebarMobileOpen` and `rightSidebarMobileOpen`. Keep the properties for backward compatibility (existing code references them).

```javascript
/** @deprecated Use bottomSheetOpen instead. Kept for backward compatibility. */
leftSidebarMobileOpen: false,
/** @deprecated Use bottomSheetOpen instead. Kept for backward compatibility. */
rightSidebarMobileOpen: false,
```

#### 3. Remove Old Mobile Sidebar CSS

**File**: `Style.css`
**Changes**: Remove the old mobile sidebar CSS rules that are no longer needed since sidebars are hidden on mobile:
- `.sidebar-left.mobile-open` (line 948-950)
- `.sidebar-right.mobile-open` (line 967-969)
- `.sidebar-right.sidebar-collapsed.mobile-open` (line 972-977)

Keep the base mobile sidebar positioning rules (`position: fixed`, `left: -280px`, etc.) since they are still referenced by the `display: none !important` override.

#### 4. Update Tests

**File**: `MyComponents/MobileSidebarTest.html`
**Changes**: Update test descriptions to note deprecation. Add tests verifying `bottomSheetOpen` is not affected by old sidebar methods.

**File**: `test/e2e/responsive-design.spec.js`
**Changes**: Update mobile viewport tests that reference sidebar visibility — sidebars are now hidden on mobile and replaced by bottom sheet.

### Success Criteria:

#### Automated Verification:
- [ ] All Phase 1 and Phase 2 tests still pass
- [ ] No test references removed CSS selectors
- [ ] `node scripts/run-tests.js` passes cleanly

#### Manual Verification:
- [ ] Crop preview in bottom sheet renders and is interactive (drag handles work)
- [ ] Mobile UI behaves identically to Phase 2 (no regressions)
- [ ] Desktop UI behaves identically to pre-migration (no regressions)

---

## Testing Strategy

### Unit Tests

**New file**: `MyComponents/BottomSheetTest.html`
- Follows existing `MobileSidebarTest.html` pattern (Mocha/Chai, browser-based)
- Tests state defaults, toggle behavior, tab switching, mutual exclusion
- Uses mock base and spread-VM pattern consistent with existing tests

**Updated files**:
- `MyComponents/MobileSidebarTest.html` — 3 regression tests
- `MyComponents/ResponsiveCSSValidationTest.html` — 12 CSS validation tests

### E2E Tests (Playwright)

**New file**: `test/e2e/bottom-sheet.spec.js`
- Mobile viewport (375x667) for bottom sheet tests
- Desktop viewport (1920x1080) for regression tests
- Tests visibility, interactions, tab switching, dismissal methods

### Manual Testing Steps

1. Start dev server: `bash start-server.sh`
2. Open `http://localhost:8000/CollageMaker/index.html`
3. Set viewport to 375x667 (mobile)
4. Verify hamburger menu visible, sidebar toggles hidden, app title hidden
5. Tap hamburger — bottom sheet slides up with "Images" tab active
6. Tap "Edit" tab — edit controls appear
7. Tap "Export" tab — export controls appear
8. Tap backdrop — bottom sheet closes
9. Press Escape — bottom sheet closes
10. Upload images — verify they appear in bottom sheet image library
11. Set viewport to 1920x1080 (desktop) — verify no bottom sheet, sidebars visible
12. Test on iOS Safari simulator for safe area handling

---

## Performance Considerations

- **CSS `transform` animation**: Bottom sheet uses `transform: translateY()` for GPU-accelerated animation (not `top`/`bottom` property transitions)
- **`v-show` for tab panels**: Uses `display: none` toggle (no DOM re-creation). Tab content with form inputs preserves state across tab switches
- **No JavaScript viewport detection**: CSS media queries handle visibility — zero JS overhead for breakpoint detection
- **Backdrop reuse**: Existing `#sidebarOverlay` element reused — no additional DOM nodes

---

## Migration Notes

- **Backward compatibility**: Old `leftSidebarMobileOpen` / `rightSidebarMobileOpen` properties retained through Phase 2, deprecated in Phase 3
- **Rollback**: If issues arise, remove the mobile media query CSS additions and the bottom sheet template from `index.html`. The old sidebar behavior is fully preserved in the DOM and CSS.
- **z-index stack**: 140 (backdrop) < 150 (old sidebars, unused on mobile) < 160 (bottom sheet) < 200 (theme toggle) < 9999 (toast)

---

## Known Behaviors

| Behavior | Rationale |
|----------|-----------|
| Bottom sheet duplicates sidebar content in template | Phase 1 minimizes risk; Phase 3 deduplicates |
| `bsCropPreviewCanvas` renders but is non-functional | Crop renderer/interaction only wired to `cropPreviewCanvas`; wiring deferred to Phase 3 |
| Old sidebar state properties retained | Backward compatibility; existing code references them |
| `closeSidebars()` closes all three overlays | Single dismissal point for backdrop tap and Escape key |
| `toggleBottomSheet()` does not affect `rightSidebarOpen` (desktop) | Desktop and mobile state are independent |
| Tab switching uses `v-show` not `v-if` | Preserves form input state across tab switches |
| Bottom sheet uses `dvh` not `vh` | Handles iOS Safari dynamic address bar |
| Swipe-to-dismiss only at scroll top (Phase 2) | Prevents conflict with content scrolling |
| CSS `!important` for mobile sidebar hide | Wins against existing transition properties on sidebar classes |

---

## Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | BS-01 through BS-12, BS-E2E-01 through BS-E2E-14 | Core functionality — if these fail, the bottom sheet doesn't work |
| **P1** | BS-CSS-01 through BS-CSS-12, BS-E2E-15 through BS-E2E-17 | Structural correctness and UX safety |
| **P2** | Phase 3 migration tests, reduced motion, focus trapping | Robustness and polish |

---

## References

- Change request: `_agent_docs/specifications/change-requests/2026-07-24-01-mobile-bottom-sheet-redesign.md`
- Existing mobile plan: `_agent_docs/plans/2026-07-22-mobile-responsiveness-implementation.md`
- Building web apps skill: `.opencode/skills/building-web-apps/SKILL.md`
- Writing plans skill: `.opencode/skills/writing-plans/SKILL.md`
- Accessibility reference: `.opencode/skills/building-web-apps/references/accessibility.md`
- Mobile UI patterns: `.opencode/skills/building-web-apps/references/mobile-ui-patterns.md`
- CSS layout reference: `.opencode/skills/building-web-apps/references/css-layout.md`
