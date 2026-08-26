# Fixed Element Z-Index Occlusion and Playwright Pointer Interception Diagnosis

**Date:** 2026-07-25
**Session:** 2026-07-25-002 (Mobile Bottom Sheet Phase 1)

## Summary

Discovered and fixed a z-index collision where `#themeToggle` (fixed, z-index 200) occluded the hamburger menu button in the toolbar. Learned a systematic Playwright diagnostic pattern for "element visible but unclickable" bugs.

---

## 1. Fixed Elements Occlude Flow Content via Z-Index Stacking

`position: fixed` elements are taken out of the document flow and painted on their own stacking context. If a fixed element has a high `z-index` and its coordinates overlap a flow element (like a toolbar button), the fixed element **always wins** regardless of DOM order.

### The Bug

`#themeToggle` is `position: fixed; right: 24px; z-index: 200`. The hamburger button was in `.toolbar-actions` on the right side of the toolbar. At 675px viewport, the hamburger's bounding box was at `x: 611` — right under where the theme toggle sits at `right: 24px` (which is `x: 675 - 24 - 44 = 607`). The theme toggle completely occluded the hamburger.

### Why It Wasn't Obvious

- The hamburger was `isVisible()` — Playwright and CSS both report it as visible
- It had `display: flex` and full opacity
- The occlusion only happens below the mobile breakpoint (~700px) where the hamburger becomes visible
- On desktop, the hamburger is `display: none` so there's no conflict

### The Fix

Move the hamburger to the **left** side of the toolbar (inside `.app-title-group`), far from the fixed theme toggle. This is also the conventional mobile pattern — menu button on the left, actions on the right.

### General Rule

> When placing mobile-only elements in a toolbar that also has `position: fixed` overlays (theme toggle, toast, etc.), always check the fixed element's bounding box at the mobile breakpoint. Place mobile elements on the **opposite side** of the toolbar from any fixed overlays.

### Prevention Checklist

When adding a new fixed-position element or a mobile-only toolbar element:

| Check | Command |
|-------|---------|
| What's the fixed element's right/left offset? | Read CSS `right:` or `left:` value |
| Where does the new element render at the mobile breakpoint? | Playwright `boundingBox()` at 675px |
| Do the bounding boxes overlap? | Compare x-coordinates |
| Does the fixed element have higher z-index? | Compare `z-index` values |

---

## 2. Diagnosing "Visible But Unclickable" with Playwright

When Playwright reports `element.isVisible() === true` but `element.click()` fails with **"intercepts pointer events"**, the element is visually present but another element is painted on top of it.

### Diagnostic Pattern

```javascript
// 1. Check the element is actually visible
const isVisible = await el.isVisible();
const box = await el.boundingBox();
console.log('isVisible:', isVisible, 'box:', JSON.stringify(box));

// 2. Check computed styles (display, visibility, opacity)
const display = await el.evaluate(e => getComputedStyle(e).display);
const visibility = await el.evaluate(e => getComputedStyle(e).visibility);
const opacity = await el.evaluate(e => getComputedStyle(e).opacity);

// 3. Walk the parent chain to find a hidden ancestor
const parentChain = await el.evaluate(e => {
    const chain = [];
    let node = e;
    while (node && node !== document.body) {
        const d = getComputedStyle(node).display;
        chain.push(`${node.tagName}${node.id ? '#' + node.id : ''} => display:${d}`);
        node = node.parentElement;
    }
    return chain;
});

// 4. If all checks pass but click still fails with "intercepts pointer events",
//    another element is overlapping. Check for fixed/absolute positioned elements
//    at similar coordinates with higher z-index.
```

### The Playwright Error Message Is Your Clue

```
- <button id="themeToggle"> intercepts pointer events
```

This tells you **exactly** which element is blocking the click. The element name in the error message is the occluder — not the target.

### Key Insight

`isVisible()` checks whether the element itself is rendered, not whether it's *accessible to pointer events*. An element can be fully visible but completely occluded by another element with a higher stacking context.

---

## File References

- `index.html` — Hamburger moved from `.toolbar-actions` (right) to `.app-title-group` (left)
- `Style.css` — `#themeToggle` at `position: fixed; right: var(--space-3); z-index: 200`
