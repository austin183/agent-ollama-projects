# iOS Safe Area Complete Pattern: viewport-fit, 100dvh, and Fixed Elements

**Date:** 2026-07-23
**Session:** 2026-07-23-004 (Phase 3: Mobile Polish)

## Summary

Implemented the complete iOS safe area pattern for CollageMaker: body padding, viewport-fit, dynamic viewport height, and fixed-position element treatment. This document captures the full pattern and gotchas discovered during implementation and world-review.

---

## 1. `viewport-fit=cover` Is Mandatory for Safe Area Values

On iOS Safari, `env(safe-area-inset-*)` returns **0px for all values** unless the viewport meta tag includes `viewport-fit=cover`. Without it, the browser renders the page within the safe area by default, so the insets are meaningless.

```html
<!-- REQUIRED for env(safe-area-inset-*) to return non-zero values on iOS -->
<meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
```

**What it does:** Tells the browser to render the page edge-to-edge, covering the entire viewport including the areas behind the notch and home indicator. The safe area inset values then tell you how much space to leave clear.

**What it does NOT do:** It does not prevent user zoom. Keep `user-scalable=yes` (the default) for accessibility.

**Gotcha:** On non-iOS browsers (Chrome Android, desktop), `viewport-fit=cover` is ignored. The `env()` fallback values (`0px`) handle graceful degradation.

---

## 2. `100dvh` for iOS Safari Dynamic Address Bar

On iOS Safari, `100vh` includes the height of the browser's bottom toolbar (address bar). When the user scrolls and the address bar hides, `100vh` does NOT dynamically adjust — it retains the initial value including the hidden toolbar height.

**Symptoms:**
- Page content extends below visible area when address bar is hidden
- Layout shift when address bar appears/disappears
- Canvas area doesn't fill available viewport height

**Solution:** Use `100dvh` (dynamic viewport height) which adjusts when the browser toolbar shows/hides:

```css
body {
    height: 100vh;   /* Fallback for older browsers */
    height: 100dvh;  /* Modern browsers use dynamic value */
}
```

**Browser support:** iOS Safari 15+, Chrome 89+, Firefox 110+, Edge 89+. The `100vh` fallback ensures older browsers still work.

**Why the override pattern works:** CSS uses the last declared value. Older browsers skip `100dvh` (unrecognized) and use `100vh`. Modern browsers apply both, with `100dvh` winning.

---

## 3. Fixed-Positioned Elements Need Individual Safe Area Treatment

When you add `padding-top: env(safe-area-inset-top, 0px)` to `body`, it protects **flow content** (children in the normal document flow). It does NOT protect **fixed-positioned elements** because `position: fixed` is relative to the viewport, not the padded body.

### Elements at Risk

| Element | Position | Safe Area Risk | Fix |
|---------|----------|----------------|-----|
| `#themeToggle` | `fixed; top: var(--space-3)` | Dynamic island overlap | `calc(var(--space-3) + env(safe-area-inset-top, 0px))` |
| `.sidebar-left` (mobile) | `fixed; top: 0; height: 100vh` | Content behind notch | `top: env(safe-area-inset-top, 0px); height: calc(100vh - top - bottom)` |
| `.sidebar-right` (mobile) | `fixed; top: 0; height: 100vh` | Content behind notch | Same as sidebar-left |
| `.toast-notification` | `fixed; bottom: calc(...)` | Home indicator overlap | Already had `env(safe-area-inset-bottom)` ✓ |
| `#app` toolbar | Flow content | Protected by body padding ✓ | No change needed |

### Pattern for Fixed Elements

```css
/* Fixed element with top offset */
.fixed-top-element {
    position: fixed;
    top: calc(var(--offset) + env(safe-area-inset-top, 0px));
}

/* Fixed overlay panel spanning full height */
.fixed-overlay {
    position: fixed;
    top: env(safe-area-inset-top, 0px);
    height: calc(100vh - env(safe-area-inset-top, 0px) - env(safe-area-inset-bottom, 0px));
}
```

### Why `box-sizing: border-box` on Body Matters

When adding safe area padding to body, `box-sizing: border-box` prevents the padding from increasing the body's total height beyond `100vh` (or `100dvh`). Without it:

```
body height = 100vh + padding-top + padding-bottom
            = 100vh + 44px (on iPhone with notch)
            = overflow!
```

With `border-box`:
```
body height = 100vh (padding is included in the height)
```

---

## 4. CSS Content Validation Testing Pattern

CSS properties like safe area insets cannot be tested with computed styles in a headless browser (the browser doesn't know it's an iPhone). Instead, validate the CSS source directly:

```javascript
// Fetch and parse the CSS file
const css = await (await fetch('../Style.css')).text();

// Verify body has safe area padding with fallback
const bodyBlock = css.match(/body\s*\{[^}]*\}/);
expect(bodyBlock[0]).to.include('env(safe-area-inset-top, 0px)');

// Verify viewport meta tag
const doc = new DOMParser().parseFromString(html, 'text/html');
const viewport = doc.querySelector('meta[name="viewport"]');
expect(viewport.getAttribute('content')).to.include('viewport-fit=cover');

// Verify 100dvh comes after 100vh (override pattern)
const vhIndex = bodyRule.indexOf('height: 100vh');
const dvhIndex = bodyRule.lastIndexOf('height: 100dvh');
expect(dvhIndex).to.be.greaterThan(vhIndex);
```

**Why this works:** The CSS content is deterministic and version-controlled. Testing the source is more reliable than testing computed styles in an environment that doesn't match the target device.

---

## 5. Complete Safe Area Checklist

When implementing mobile safe areas, verify all five pieces are in place:

| # | Requirement | Location | Status |
|---|-------------|----------|--------|
| 1 | `viewport-fit=cover` in meta tag | `index.html` | ✓ |
| 2 | `padding-top: env(safe-area-inset-top, 0px)` on body | `Style.css` body rule | ✓ |
| 3 | `padding-bottom: env(safe-area-inset-bottom, 0px)` on body | `Style.css` body rule | ✓ |
| 4 | `box-sizing: border-box` on body | `Style.css` body rule | ✓ |
| 5 | Fixed elements use `calc(... + env(safe-area-inset-*))` | Each fixed element | ✓ |
| 6 | `height: 100dvh` with `100vh` fallback on body | `Style.css` body rule | ✓ |

---

## File References

- `Style.css` — Body safe area padding, 100dvh, fixed element overrides, mobile sidebar safe areas
- `index.html` — Viewport meta tag with `viewport-fit=cover`
- `MyComponents/MobilePolishTest.html` — CSS content validation tests (17 tests)
