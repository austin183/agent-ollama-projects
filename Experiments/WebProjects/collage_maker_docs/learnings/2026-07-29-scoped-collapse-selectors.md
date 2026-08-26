# Scoped Collapse Selectors: Preventing Shared Class Collateral Damage

**Date:** 2026-07-29
**Session:** 2026-07-29-001 (Debug: floating toggle buttons invisible after collapse)

## Summary

A bare `.sidebar-collapsed` CSS selector with `width: 0 !important` was crushing floating toggle buttons to zero width because the same class name was applied to both sidebar `<div>`s and toggle `<button>`s via Vue `:class` bindings. The fix was to scope the selector to `div.sidebar.sidebar-collapsed`.

---

## The Problem

The `.sidebar-collapsed` class serves two purposes in CollageMaker:

1. **On sidebar `<div>`s** — collapses the panel to zero width (desired)
2. **On toggle `<button>`s** — indicates the collapsed state so CSS can reposition the button (desired) and so Vue can track state (desired)

The CSS rule was written as a bare class selector:

```css
.sidebar-collapsed {
    width: 0 !important;
    min-width: 0 !important;
    padding: 0 !important;
    border-left: none !important;
    overflow: hidden !important;
}
```

This matches **any** element with the `sidebar-collapsed` class, including the toggle buttons. The `!important` flag overrides the `.sidebar-float-btn` rule's `width: 40px`, rendering the buttons invisible (computed width: 0, collapsing to 1px due to flex shrink).

### Why It Wasn't Caught Earlier

- The toggle buttons were **added after** the `.sidebar-collapsed` rule existed
- The class name was reused for a different purpose (state tracking + positioning) without considering the existing `!important` properties
- The bare class selector has low specificity (0,0,1,0) but `!important` makes specificity irrelevant — it always wins over non-`!important` declarations regardless of specificity

### Why the Mobile Override Didn't Help

The mobile media query overrides (`.sidebar-left.sidebar-collapsed.mobile-open`, `.sidebar-right.sidebar-collapsed.mobile-open`) only apply inside `@media (max-width: 699px)`. On desktop, the bare `.sidebar-collapsed` rule was unopposed.

---

## The Fix

Scope the selector to only match sidebar `<div>` elements:

```css
/* Before — matches ANY element with sidebar-collapsed class */
.sidebar-collapsed {
    width: 0 !important;
    /* ... */
}

/* After — only matches <div class="sidebar sidebar-collapsed"> */
div.sidebar.sidebar-collapsed {
    width: 0 !important;
    /* ... */
}
```

**Why this works:**
- The toggle buttons have classes `sidebar-float-btn sidebar-float-left sidebar-collapsed` — they don't have the `sidebar` class, so the scoped selector doesn't match them
- The sidebar divs have classes `sidebar sidebar-left sidebar-collapsed` — they match both `div`, `.sidebar`, and `.sidebar-collapsed`
- The mobile overrides (`.sidebar-left.sidebar-collapsed.mobile-open`, etc.) still work because they're already more specific compound selectors

---

## General Rule

> **When a CSS class with `!important` properties is shared across different element types via framework bindings (Vue `:class`, React `className`, etc.), always scope the selector with an element type or parent class to prevent collateral damage.**

### Prevention Checklist

| Check | Action |
|-------|--------|
| Does the class have `!important` properties? | Scope with element type: `div.class-name` not `.class-name` |
| Is the class applied to multiple element types? | Use compound selectors: `div.parent.child` not `.child` |
| Will new elements reuse this class? | Document the class contract — what it's meant to style vs what it signals |
| Could `!important` be avoided? | Prefer higher specificity over `!important` when possible |

### When Bare Class Selectors Are Safe

A bare `.class-name` selector is safe when:
- The class is **only** applied to one element type
- The class has **no** `!important` properties
- The class is used purely for **state signaling** (e.g., `.sidebar-collapsed` on buttons for positioning) and the destructive styles live in a scoped selector

### Anti-Pattern: Shared Class with Destructive Styles

```css
/* BAD — class name reused for state tracking, but styles are destructive */
.sidebar-collapsed {
    width: 0 !important;  /* Destroys buttons that also have this class */
}
```

### Pattern: Separate State Class from Style Class

```css
/* GOOD — state class is bare, destructive styles are scoped */
.sidebar-collapsed {
    /* Only non-destructive properties, or none at all */
}

div.sidebar.sidebar-collapsed {
    width: 0 !important;  /* Only affects sidebar divs */
}

.sidebar-float-left.sidebar-collapsed {
    left: 8px;  /* Only affects left toggle buttons */
}
```

---

## Debugging Tips

When an element has unexpected zero dimensions:

1. **Check computed width/height** — `getComputedStyle(el).width` will show `0px` or `1px`
2. **Look for `!important` in matching rules** — DevTools shows `!important` rules crossed out if overridden, but if nothing overrides them, they win
3. **Check all classes on the element** — a shared class from a Vue `:class` binding might be applying unexpected styles
4. **Search for the class in CSS** — `grep .class-name Style.css` to find all rules that could match

---

## File References

- `Style.css` — `div.sidebar.sidebar-collapsed` (line 614), `.sidebar-float-left.sidebar-collapsed` (line 450), `.sidebar-float-right.sidebar-collapsed` (line 460)
- `index.html` — Vue `:class` bindings on sidebar divs and toggle buttons
