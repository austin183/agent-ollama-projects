# Flex Column Chain Requires `min-height: 0`

## The Problem

In a CSS flexbox layout with `flex-direction: column`, nested flex items that use `flex: 1` will **not** properly constrain their height to the parent's available space unless each item in the chain has `min-height: 0`.

## Why It Happens

The CSS spec defines `min-height: auto` as the default for flex items. For column flex containers, `min-height: auto` means "don't shrink below the content's intrinsic minimum height." This overrides the parent's `flex: 1` constraint, allowing the item to expand beyond its allocated space.

This cascades through the entire flex chain:

```
body (height: 100vh, flex column)
  └── #app (flex: 1)          ← min-height: auto = EXPANDS
      └── .main-layout (flex: 1)  ← min-height: auto = EXPANDS
          └── .canvas-area (flex: 1)  ← min-height: auto = EXPANDS
              └── .canvas-container (flex: 1)  ← min-height: auto = EXPANDS
```

Each item in the chain ignores its parent's height constraint, causing the entire layout to grow beyond the viewport.

## The Symptom

- `body` has `height: 100vh` but measures taller (e.g., 1666px instead of 1080px)
- Content is pushed off-screen and clipped by `overflow: hidden`
- The layout chain (body > app > main > area > container) is each taller than the one above it

## The Fix

Add `min-height: 0` to **every** flex item in the column chain:

```css
#app {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-height: 0; /* Critical */
}

.main-layout {
    display: flex;
    flex: 1;
    min-height: 0; /* Critical */
}

.canvas-area {
    flex: 1;
    display: flex;
    flex-direction: column;
    min-height: 0; /* Critical */
}

.canvas-container {
    flex: 1;
    min-height: 0; /* Critical */
}
```

## Universal Rule

**Any flex item with `flex: 1` (or `flex-grow: 1`) inside a `flex-direction: column` container needs `min-height: 0`** to properly respect the parent's height constraint.

The same applies horizontally: any flex item with `flex: 1` inside a `flex-direction: row` container needs `min-width: 0`.

## Reference

- [MDN: min-height on flex items](https://developer.mozilla.org/en-US/docs/Web/CSS/min-height)
- [CSS Tricks: Flexbox min-height: 0](https://css-tricks.com/setting-a-flexible-height/)
