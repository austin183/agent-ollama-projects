# Mobile Bottom Sheet Accessibility and Scroll Lock Patterns

**Date:** 2026-07-25
**Session:** 2026-07-25-001 (Phase 1: Core Bottom Sheet)

## Summary

Implemented the Phase 1 mobile bottom sheet redesign using TDD. During implementation and world-review, two patterns emerged that complement existing documentation but aren't fully covered in prior learnings: reactive `aria-labelledby` for dialog accessibility with a visually-hidden title element, and body scroll lock via CSS class on `document.body`. This document captures these specific techniques.

---

## 1. Reactive `aria-labelledby` with Visually-Hidden Title Element

When implementing an ARIA dialog (`role="dialog" aria-modal="true"`), screen readers need a label to announce the dialog's purpose. The standard approach is `aria-labelledby` pointing to a visible heading, but for mobile bottom sheets where the tab bar serves as the primary navigation and there's no dedicated visible title, use a visually-hidden element with reactive binding.

### Pattern

```html
<!-- Bottom sheet container -->
<div id="bottomSheet" class="bottom-sheet"
     :class="{ 'bottom-sheet-open': bottomSheetOpen }"
     role="dialog" aria-label="Menu" aria-modal="true"
     :aria-labelledby="bottomSheetOpen ? 'bottomSheetTitle' : null">

    <!-- Visually-hidden title — announced by screen readers, not visible on screen -->
    <div id="bottomSheetTitle" class="bottom-sheet-title" style="display:none;">
        Collage Options Menu
    </div>

    <!-- Tab bar and panels follow... -->
</div>
```

### Why Reactive `:aria-labelledby` Binding?

Binding `:aria-labelledby` to `null` when the sheet is closed prevents screen readers from announcing a label for content that isn't visible. When open, it points to the hidden title element so the dialog's purpose is announced immediately upon focus entering the sheet.

**Alternative considered:** Using only `aria-label="Menu"` (static). This works but doesn't allow dynamic labeling if the active tab changes the context. The reactive pattern supports future enhancement where the label could change based on the active tab.

### CSS for Visually-Hidden Element

Use `display: none` rather than clip/absolute positioning when the element should never be visible to sighted users — it's purely for screen reader announcement via `aria-labelledby`. Since `aria-labelledby` references the element by ID, the element exists in the DOM but is not rendered.

```css
.bottom-sheet-title {
    display: none; /* Not visible — only referenced by aria-labelledby */
}
```

### File References

- `index.html` — Bottom sheet template with reactive `:aria-labelledby` and hidden title div
- `.opencode/skills/building-web-apps/references/accessibility.md` — General ARIA dialog guidance (this pattern extends it for mobile bottom sheets)

---

## 2. Body Scroll Lock via CSS Class on `document.body`

When a mobile overlay (sidebar or bottom sheet) is open, the background page should not be scrollable via touch gestures. This prevents accidental scrolling of the canvas/collage while interacting with overlay controls.

### Pattern

```javascript
// In Vue methods — add/remove class on document.body when overlays toggle
toggleBottomSheet() {
    if (!this.bottomSheetOpen) {
        this.leftSidebarMobileOpen = false;
        this.rightSidebarMobileOpen = false;
        this.bottomSheetOpen = true;
        document.body.classList.add('no-scroll');  // Lock scroll on open
    } else {
        this.bottomSheetOpen = false;
        document.body.classList.remove('no-scroll'); // Unlock on close
    }
}

closeSidebars() {
    this.leftSidebarMobileOpen = false;
    this.rightSidebarMobileOpen = false;
    this.bottomSheetOpen = false;
    document.body.classList.remove('no-scroll');  // Always release on close-all
}
```

```css
/* CSS class applied to <body> — prevents all scroll */
.no-scroll {
    overflow: hidden;
    touch-action: none; /* Prevents touch scrolling AND double-tap zoom on iOS/Android */
}
```

### Why `touch-action: none` in Addition to `overflow: hidden`?

- **`overflow: hidden`** prevents mouse/trackpad wheel and scrollbar-based scrolling.
- **`touch-action: none`** is required for mobile touch devices — it prevents the browser's default touch behaviors (scrolling, pinch-zoom) on the locked element. Without it, iOS Safari may still allow one-finger vertical drag to scroll the page behind the overlay, even with `overflow: hidden`.

### Why Apply to `document.body` Instead of a Vue-Managed Wrapper?

Vue 3 Options API manages reactive state within its mounted root (`#app`), but `<body>` is outside Vue's template scope. Direct `document.body.classList.add/remove()` is the standard approach for body-level classes in Vue 3 apps without additional libraries. The class is always cleaned up:
- In `closeSidebars()` (covers Escape key, backdrop tap)
- In each toggle method's close branch

### Consistency Across All Overlay Toggles

All overlay-opening methods must add the `no-scroll` class, and all closing methods must remove it. This was applied consistently to:
- `toggleBottomSheet()` — adds on open, removes on close
- `closeSidebars()` — always removes (covers all dismissal paths)
- `toggleLeftSidebar()` — toggles based on resulting state
- `toggleRightSidebarMobile()` — toggles based on resulting state  
- `toggleRightSidebar()` — toggles based on mobile overlay state

### File References

- `MyESModules/App/createCollageMethods.js` — Body scroll lock logic in toggle/close methods
- `Style.css` — `.no-scroll` CSS class definition
- `index.html` — No template changes needed (class applied imperatively via JS)

---

## 3. Keyboard Navigation for ARIA Tab Panel Pattern

The bottom sheet tab bar uses the WAI-ARIA tabs pattern (`role="tablist"`, `role="tab"`, `role="tabpanel"`). In addition to click handlers, keyboard arrow key navigation is required per WAI-ARIA Authoring Practices.

### Pattern

```html
<div class="bottom-sheet-tab-bar" role="tablist" aria-label="Menu sections"
     @keydown.arrow-left.prevent="switchBottomSheetTab(-1)"
     @keydown.arrow-right.prevent="switchBottomSheetTab(1)">
    <button role="tab" :aria-selected="activeBottomSheetTab === 'images'"
            :tabindex="activeBottomSheetTab === 'images' ? 0 : -1">
        Images
    </button>
    <!-- ... more tabs -->
</div>
```

```javascript
// Method that wraps tab switching with circular navigation
switchBottomSheetTab(delta) {
    const validTabs = ['images', 'edit', 'export'];
    let idx = validTabs.indexOf(this.activeBottomSheetTab);
    if (idx === -1) idx = 0; // Fallback for invalid state
    idx = (idx + delta + validTabs.length) % validTabs.length;
    this.setBottomSheetTab(validTabs[idx]);
}
```

### Key Details

- **`@keydown.arrow-left.prevent` / `@keydown.arrow-right.prevent`** on the `role="tablist"` container — handles arrow key navigation between tabs per WAI-ARIA practices. The `.prevent` modifier blocks page scroll when arrows are pressed with a tab focused.
- **Dynamic `:tabindex`** — Only the active tab has `tabindex="0"` (focusable in tab order); inactive tabs have `tabindex="-1"` (focusable only programmatically, e.g., via arrow keys). This prevents all three tabs from appearing as separate Tab stops.
- **`switchBottomSheetTab(delta)`** uses modular arithmetic `(idx + delta + length) % length` for wrap-around navigation — pressing Left on the first tab wraps to the last, and vice versa.

### File References

- `index.html` — Bottom sheet tab bar with keyboard handlers and dynamic tabindex
- `MyESModules/App/createCollageMethods.js` — `switchBottomSheetTab()` method
