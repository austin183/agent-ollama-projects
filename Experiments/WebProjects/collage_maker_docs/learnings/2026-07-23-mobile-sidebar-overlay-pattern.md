# Mobile Sidebar Overlay Pattern: Dual-State Toggles and CSS `!important` Cascade

**Date:** 2026-07-23
**Session:** 2026-07-23-002 (Phase 2: Responsive CSS Layout)

## Summary

Implemented mobile sidebar overlay panels for CollageMaker using a dual-state toggle pattern and CSS media query overrides. This document captures the patterns and gotchas discovered during implementation and world-review.

---

## 1. Dual-State Toggle Pattern

When a UI element (like a sidebar) has different visibility mechanisms on desktop vs mobile, use **two independent reactive state properties** toggled by a single method. CSS media queries determine which state has visual effect.

### The Problem

Desktop sidebar visibility uses a CSS class (`.sidebar-collapsed`) bound to `rightSidebarOpen`. Mobile sidebar visibility uses a different CSS class (`.mobile-open`) bound to `rightSidebarMobileOpen`. A single toggle button needs to work in both contexts.

### Anti-Pattern: Viewport Detection in JavaScript

```javascript
// BAD — couples JS to CSS breakpoint values
toggleRightSidebar() {
    if (window.innerWidth <= 699) {
        this.rightSidebarMobileOpen = !this.rightSidebarMobileOpen;
    } else {
        this.rightSidebarOpen = !this.rightSidebarOpen;
    }
}
```

**Problems:**
- Duplicates the breakpoint value (699px) in two places
- Breaks if CSS breakpoint changes
- Requires runtime viewport measurement
- Doesn't handle rapid resize during open state

### Solution: Toggle Both States

```javascript
// GOOD — CSS media queries determine which state matters
toggleRightSidebar() {
    this.rightSidebarOpen = !this.rightSidebarOpen;
    this.rightSidebarMobileOpen = !this.rightSidebarMobileOpen;
    if (this.rightSidebarMobileOpen) {
        this.leftSidebarMobileOpen = false; // mutual exclusion
    }
}
```

**Why it works:**
- On desktop (>= 700px): `rightSidebarOpen` controls `sidebar-collapsed` class; `rightSidebarMobileOpen` has no CSS effect (media query inactive)
- On mobile (< 700px): `rightSidebarMobileOpen` controls `mobile-open` class; `rightSidebarOpen` has no visual effect (sidebar is fixed off-screen)
- Both states stay in sync — toggling one toggles the other
- Zero JavaScript viewport detection needed

### Template Binding

```html
<div class="sidebar sidebar-right"
     :class="{ 'sidebar-collapsed': !rightSidebarOpen, 'mobile-open': rightSidebarMobileOpen }">
```

---

## 2. CSS `!important` Cascade in Media Queries

When a desktop CSS class uses `!important` declarations, mobile media query overrides need **equally specific selectors with `!important`** to win the cascade.

### The Problem

Desktop `.sidebar-collapsed` uses `!important` to force collapse:

```css
.sidebar-collapsed {
    width: 0 !important;
    min-width: 0 !important;
    padding: 0 !important;
    border-left: none !important;
    overflow: hidden !important;
}
```

Mobile media query tries to show the sidebar:

```css
@media (max-width: 699px) {
    .sidebar-right.mobile-open {
        right: 0;
        width: 280px;  /* LOSES to .sidebar-collapsed width: 0 !important */
    }
}
```

When both classes are present (`.sidebar-right.sidebar-collapsed.mobile-open`), the `!important` rules from `.sidebar-collapsed` override the mobile styles.

### Solution: Match Specificity with `!important`

```css
@media (max-width: 699px) {
    .sidebar-right.sidebar-collapsed.mobile-open {
        width: 280px !important;
        min-width: 0 !important;
        border-left: 1px solid var(--color-surface-variant) !important;
        overflow: visible !important;
    }
}
```

**Key rules:**
1. **Match specificity** — `.sidebar-right.sidebar-collapsed.mobile-open` (3 classes) matches `.sidebar-collapsed` (1 class) in specificity context within the media query
2. **Use `!important` to beat `!important`** — without it, the desktop `!important` wins regardless of media query
3. **Only override conflicting properties** — don't repeat all properties, only the ones that conflict
4. **Keep the media query wrapper** — these overrides only apply when the media query is active

### When to Avoid `!important`

If you control both the desktop and mobile CSS, prefer avoiding `!important` entirely:

```css
/* Desktop — no !important */
.sidebar-collapsed {
    width: 0;
    min-width: 0;
    overflow: hidden;
}

/* Mobile — wins by specificity + source order */
@media (max-width: 699px) {
    .sidebar-right.mobile-open {
        width: 280px;
        overflow: visible;
    }
}
```

However, when desktop CSS is established and uses `!important` (like a shared component library or legacy code), the `!important` cascade pattern is the pragmatic fix.

---

## 3. Vue `.window` Modifier for Global Escape Key

Use `@keydown.escape.window.prevent` on the app root to catch Escape key globally, regardless of which element has focus.

```html
<div id="app" @keydown.escape.window.prevent="closeSidebars">
```

**Why `.window`:** A bare `@keydown.escape` on a div only fires when that div has focus. The `.window` modifier attaches the listener to `window`, ensuring Escape is caught regardless of focus state.

**Why `.prevent`:** Prevents browser default Escape behavior (closing dialogs, canceling operations) when a sidebar is open.

---

## 4. `display: none` for Overlay Backdrops

Use `display: none` (not `opacity: 0`) for overlay backdrops that should not intercept pointer events when hidden.

```css
/* GOOD — completely removed from rendering and event flow */
.sidebar-overlay {
    display: none;
}
.sidebar-overlay.visible {
    display: block;
}

/* BAD — invisible but still intercepts clicks */
.sidebar-overlay {
    opacity: 0;
    pointer-events: none; /* extra property needed */
}
.sidebar-overlay.visible {
    opacity: 1;
    pointer-events: auto; /* must remember to set this too */
}
```

**Trade-off:** `display: none` cannot be CSS-transitioned (no fade animation). For a backdrop overlay that appears/disappears with sidebar slides, instant show/hide is acceptable.

---

## 5. ARIA `aria-expanded` on Mobile Toggle Buttons

Bind `:aria-expanded` to the mobile sidebar state so screen readers announce the open/closed state:

```html
<button @click="toggleLeftSidebar"
        :aria-expanded="leftSidebarMobileOpen"
        aria-label="Toggle image panel">
    <span class="material-icons">{{ leftSidebarMobileOpen ? 'chevron_left' : 'chevron_right' }}</span>
</button>
```

**Note:** When using dual-state toggles, bind `aria-expanded` to the **mobile** state property, since that's what controls the overlay visibility on mobile devices. On desktop, the sidebar is always inline and `aria-expanded` is less relevant.

---

## File References

- `Style.css` — Mobile media queries with `!important` cascade overrides
- `MyESModules/App/createCollageData.js` — Dual-state reactive properties
- `MyESModules/App/createCollageMethods.js` — Dual-state toggle method
- `index.html` — Template bindings, ARIA attributes, Escape key handler
