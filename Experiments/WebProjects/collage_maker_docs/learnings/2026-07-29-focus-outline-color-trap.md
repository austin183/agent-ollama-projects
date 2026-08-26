# Focus Outline Color Trap: Same CSS Variable as Background

**Date:** 2026-07-29
**Session:** 2026-07-29-005 (Phase 3: Expander Icon Accessibility)

## Summary

When a button uses a CSS custom property for its background color (like `var(--color-primary)`), using the same variable for the `:focus-visible` outline color produces an **invisible focus ring** — the outline blends into the background.

---

## The Bug

```css
.mobile-fab {
    background-color: var(--color-primary);  /* e.g., #1976D2 blue */
    color: var(--color-on-primary);           /* e.g., #FFFFFF white */
}

/* BUG: outline color matches background — invisible */
.mobile-fab:focus-visible {
    outline: 2px solid var(--color-primary);  /* Same blue as background! */
    outline-offset: 2px;
}
```

The focus ring is drawn outside the button, but if the outline color matches the button's background color, it becomes visually indistinguishable from the button itself. On a light page background, you'd see a blue ring around a blue button — it looks like the button just got bigger, not focused.

## The Fix

Use the **text color** (on-primary) for the focus outline on solid-color buttons:

```css
/* CORRECT: outline uses contrasting color */
.mobile-fab:focus-visible {
    outline: 2px solid var(--color-on-primary);  /* White on blue = visible */
    outline-offset: 2px;
}
```

## General Rule

> **When a button has a solid background color, the focus outline must use the text/foreground color — not the background color.**

| Button Type | Background | Focus Outline Should Use |
|-------------|-----------|-------------------------|
| Primary (solid color) | `--color-primary` | `--color-on-primary` (text color) |
| Surface (neutral) | `--color-surface` | `--color-primary` (accent color) |
| Transparent | none | `--color-primary` (accent color) |

## Why This Happens

This is a common mistake when copy-pasting focus styles across different button types. A surface-colored button (like `.sidebar-float-btn`) uses `--color-primary` for the focus outline, which works perfectly because the background is neutral. When the same pattern is applied to a primary-colored button (like `.mobile-fab`), the outline becomes invisible.

## Testing

Verify focus outline visibility by:
1. Tabbing to the element in the browser
2. Checking that the outline is clearly visible against both the button background and the page background
3. Using a contrast checker: the focus outline should have at least 3:1 contrast ratio against the adjacent background (WCAG 2.1 SC 2.4.11)

## File Reference

- `Style.css` — `.mobile-fab:focus-visible` outline color fix
