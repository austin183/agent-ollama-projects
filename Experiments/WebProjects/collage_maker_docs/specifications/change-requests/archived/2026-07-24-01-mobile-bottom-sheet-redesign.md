# Mobile Bottom Sheet Redesign — Change Request

**Date:** 2026-07-24
**Status:** Draft
**Priority:** P1 — Mobile usability improvement

---

## Overview

The current mobile UI (below 700px breakpoint) uses two separate fixed-position overlay panels for sidebars. The left sidebar toggle button sits on the far right of the toolbar, requiring users to stretch across the screen. The right sidebar contains editing options (Crop, Background, Overlay, Title, Export) that are difficult to discover and access on mobile.

This spec defines a bottom sheet pattern with tabbed navigation to replace both sidebar overlays, providing a single unified access point for all controls in a thumb-friendly location.

---

## Current Mobile UI State

### Toolbar (left to right)
1. `CollageMaker` app title (h2) + home icon link
2. `Add Images` button (primary, with icon)
3. `Undo` button (icon only on mobile)
4. `Redo` button (icon only on mobile)
5. `Clear All` button
6. Left sidebar toggle (chevron icon) — opens Image Library + Layout
7. Right sidebar toggle (chevron icon) — opens Crop, Background, Overlay, Title, Export

### Sidebar behavior
- Both sidebars are fixed-position overlay panels (280px wide, max 85vw)
- Left sidebar slides from left, right sidebar slides from right
- Semi-transparent backdrop overlay when either sidebar is open
- Only one sidebar can be open at a time
- State: `leftSidebarMobileOpen` / `rightSidebarMobileOpen` (dual-state toggle pattern)

### Identified Problems

| # | Problem | Impact |
|---|---------|--------|
| 1 | Left sidebar toggle is on the far RIGHT of the toolbar | Users must reach across screen with thumb — physical fatigue, mis-taps |
| 2 | Two separate overlay panels | Cognitive dissonance — "Which panel has what?" — must close one to open the other |
| 3 | Right sidebar sections default collapsed | Editing options may not be discoverable at all |
| 4 | `CollageMaker` title occupies toolbar space | Wastes precious toolbar real estate (PWA manifest + browser tab already provide branding) |
| 5 | Export buried in right sidebar | Final action is hard to find on mobile |

---

## Proposed Solution

### 1. Bottom Sheet Panel

Replace both sidebar overlays with a single bottom sheet that slides up from the bottom of the screen.

**Behavior:**
- Slides up from bottom, occupying ~70-80% of viewport height in portrait mode
- In landscape mode, narrows to ~50% height to preserve canvas visibility
- Semi-transparent backdrop overlay (reuse existing `.sidebar-overlay` pattern)
- Tap backdrop or press Escape to dismiss
- Touch target sizes: minimum 44x44px (Apple HIG) / 48x48px (Material Design)

**CSS approach:**
- New class `.bottom-sheet` with `position: fixed`, `bottom: 0`, `left: 0`, `right: 0`
- `transform: translateY(100%)` for hidden state, `translateY(0)` for visible state
- CSS transition on `transform` for smooth slide animation
- `z-index: 150` (same as current sidebar overlays)
- `border-radius` on top corners for visual distinction
- Handle `env(safe-area-inset-bottom)` for devices with home indicator

### 2. Tabbed Navigation

Inside the bottom sheet, use a tab bar to organize content into three groups:

```
┌──────────────────────────────────────────────┐
│  ● Images & Layout   ○ Edit   ○ Export       │  ← Tab bar
├──────────────────────────────────────────────┤
│                                              │
│  [Tab content — scrollable]                  │
│                                              │
└──────────────────────────────────────────────┘
```

**Tab 1 — Images & Layout:**
- Image Library (search, thumbnails, remove buttons)
- Layout (style selector, gutter/slice angle/hex spacing sliders)

**Tab 2 — Edit:**
- Crop (crop preview canvas, reset button)
- Title (text input, formatting bar, font/size/color/alignment controls)
- Background (style selector, color/gradient/image options)
- Overlay (mask image, blend mode, opacity)

**Tab 3 — Export:**
- Format selector (JPEG/PNG)
- Quality slider (JPEG only)
- Export button

**Tab behavior:**
- First tab ("Images & Layout") active by default
- Tab switch does NOT close the bottom sheet
- Tab content area is independently scrollable
- Use the existing collapsible section pattern WITHIN each tab for sub-sections (e.g., Title sub-controls)

### 3. Toolbar Simplification

**Mobile toolbar (below 700px), left to right:**
1. **Menu toggle** (hamburger icon `menu`) — top-left, opens bottom sheet
2. `Add Images` button (primary, with icon)
3. `Undo` button (icon)
4. `Redo` button (icon)
5. `Clear All` button

**Changes:**
- Remove `CollageMaker` app title from mobile toolbar entirely (`display: none` in `@media (max-width: 699px)`)
- Remove right sidebar toggle button on mobile (`display: none` in media query)
- Repurpose left sidebar toggle button: change icon from chevron to hamburger (`menu`), keep `@click="toggleLeftSidebar"` wiring (will be updated to control bottom sheet instead)
- Home link icon remains accessible (keep as-is, or consider moving into bottom sheet header)

### 4. State Management

**New reactive properties** in `createCollageData.js`:
```javascript
bottomSheetOpen: false,
activeBottomSheetTab: 'images',  // 'images' | 'edit' | 'export'
```

**Updated method** in `createCollageMethods.js`:
- `toggleLeftSidebar()` — renamed or repurposed to `toggleBottomSheet()` on mobile
- On mobile: controls `bottomSheetOpen`, closes right sidebar state
- On desktop: no change (sidebars remain as-is)

**Tab switching method:**
```javascript
setBottomSheetTab(tabId) {
    this.activeBottomSheetTab = tabId;
}
```

### 5. Desktop Behavior

**No changes to desktop UI.** The bottom sheet only appears within the `@media (max-width: 699px)` breakpoint. Desktop retains the existing three-panel layout with left sidebar, canvas, and right sidebar.

---

## Implementation Notes

### CSS Architecture
- New styles scoped to `@media (max-width: 699px)`
- Bottom sheet uses `transform: translateY()` for GPU-accelerated animation (not `top`/`bottom` property transitions)
- Tab bar uses flexbox with `flex-shrink: 0` to prevent wrapping
- Tab content area uses `flex: 1` with `overflow-y: auto` for independent scrolling

### HTML Structure
The bottom sheet replaces the existing `#sidebar-left` and `#sidebar-right` elements on mobile. Two approaches:

**Option A — Conditional rendering:** Use `v-if`/`v-show` to swap between desktop sidebars and mobile bottom sheet. The bottom sheet is a separate DOM subtree.

**Option B — CSS-only swap:** Keep existing sidebar DOM, use CSS to reposition elements into a bottom sheet layout on mobile.

**Recommendation:** Option A. The bottom sheet has a fundamentally different structure (tabs, different content grouping). Conditional rendering keeps the template clean and avoids complex CSS gymnastics.

### Accessibility
- Bottom sheet: `role="dialog"`, `aria-modal="true"`, `aria-label="CollageMaker tools and settings"`
- Tab bar: `role="tablist"`, each tab `role="tab"` with `aria-selected`, each panel `role="tabpanel"`
- Trap focus within bottom sheet while open (or at minimum, Escape key dismisses)
- `aria-expanded` on the menu toggle button bound to `bottomSheetOpen`

### Touch Interactions
- Swipe down gesture to dismiss bottom sheet (nice-to-have, Phase 2)
- Pull-to-open gesture from bottom edge (nice-to-have, Phase 2)
- Phase 1: button toggle + backdrop tap + Escape key only

### File References
| File | Changes |
|------|---------|
| `index.html` | New bottom sheet template, updated toolbar for mobile |
| `Style.css` | Bottom sheet styles, tab bar styles, mobile toolbar adjustments |
| `MyESModules/App/createCollageData.js` | New reactive properties (`bottomSheetOpen`, `activeBottomSheetTab`) |
| `MyESModules/App/createCollageMethods.js` | `toggleBottomSheet()`, `setBottomSheetTab()`, updated `closeSidebars()` |

---

## Phased Rollout

### Phase 1 — Core Bottom Sheet
- Bottom sheet panel with slide-up animation
- Tab bar with three tabs (Images & Layout, Edit, Export)
- Menu toggle button in top-left (hamburger icon)
- Backdrop overlay + Escape key dismissal
- Remove app title and right sidebar toggle from mobile toolbar
- Basic accessibility (ARIA roles, Escape key)

### Phase 2 — Polish
- Swipe-down-to-dismiss gesture
- Smooth tab transitions
- Landscape orientation refinements
- Focus trapping within bottom sheet
- Safe area inset handling for notched devices

### Phase 3 — Migration
- Deprecate `leftSidebarMobileOpen` / `rightSidebarMobileOpen` dual-state pattern
- Remove mobile-specific sidebar CSS (`.sidebar-left.mobile-open`, `.sidebar-right.mobile-open`)
- Update mobile sidebar tests in `MobileSidebarTest.html`

---

## Testing Strategy

### Unit Tests (`MyComponents/MobileBottomSheetTest.html`)
1. `bottomSheetOpen` defaults to `false`
2. `toggleBottomSheet()` opens the bottom sheet
3. `toggleBottomSheet()` closes when already open
4. `activeBottomSheetTab` defaults to `'images'`
5. `setBottomSheetTab('edit')` switches tab
6. `closeSidebars()` closes bottom sheet
7. Tab switch does not close bottom sheet

### CSS Validation Tests (`MyComponents/ResponsiveCSSValidationTest.html`)
8. Bottom sheet has `position: fixed` in mobile media query
9. Tab bar uses `role="tablist"`
10. Menu toggle button exists in mobile toolbar
11. App title is hidden on mobile (`display: none`)
12. Right sidebar toggle is hidden on mobile

### E2E Tests (Playwright)
13. Tap menu toggle → bottom sheet slides up
14. Tap backdrop → bottom sheet closes
15. Switch tabs → content changes, sheet stays open
16. Swipe down → bottom sheet closes (Phase 2)
17. Escape key → bottom sheet closes

---

## Success Criteria

- Bottom sheet opens/closes smoothly with button tap
- All editing controls accessible from bottom sheet tabs
- Menu toggle is within easy thumb reach (top-left corner)
- Toolbar is uncluttered — only essential actions visible
- All existing tests continue to pass
- Desktop UI is completely unaffected
- Touch targets meet 44x44px minimum
- ARIA attributes correctly describe bottom sheet and tab structure
