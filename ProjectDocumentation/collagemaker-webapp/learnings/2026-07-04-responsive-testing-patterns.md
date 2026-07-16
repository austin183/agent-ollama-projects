# Responsive Testing Patterns

**Date:** 2026-07-04
**Session:** 32 (Section 3.5 Responsive Design tests)

## Summary

Implementing tests for deferred responsive design features revealed several patterns for testing browser interaction handlers, deferred CSS features, and E2E viewport emulation.

## 1. PointerEvent Testing with Hit Testing

When testing pointer event handlers that use `getBoundingClientRect()` for coordinate conversion (like `GestureHandler.hitTestPanel`), the test canvas must have rendered dimensions that match the expected layout.

### Problem

In a test HTML page, a canvas with `style.width = '960px'` may not render at exactly 960px in `getBoundingClientRect()` depending on the test environment. Absolute pixel coordinates (e.g., `clientX: 480`) will fail hit testing if the actual rendered size differs.

### Solution

Use **proportional coordinates** relative to the actual bounding rect:

```javascript
// BAD — assumes exact dimensions
const event = new PointerEvent('pointerdown', {
    clientX: 480,  // assumes canvas is 960px wide
    clientY: 270,
});

// GOOD — works regardless of actual rendered size
const rect = canvas.getBoundingClientRect();
const event = new PointerEvent('pointerdown', {
    clientX: rect.left + rect.width * 0.25,  // 25% into canvas
    clientY: rect.top + rect.height * 0.25,
});
```

Also verify `hitTestPanel` directly with the same proportional coordinates before dispatching events, to isolate coordinate issues from handler issues.

### Gotcha: Boundary Points

For a 2x2 uniform grid, the exact center point (50%, 50%) lands on the boundary of all four panels. Use 25% or 75% offsets to clearly land inside a single panel.

## 2. Deferred Feature Test Strategy

For CSS features that are deferred (media queries, `touch-action`, responsive overrides), tests should document requirements without failing.

### Pattern

```javascript
it('3.5.3.1 — Style.css: @media rules (deferred — documents requirement)', () => {
    // Responsive media queries are a deferred feature.
    // This test documents the requirement: @media rules should be added
    // for mobile (<768px) and tablet (<1200px) breakpoints.
    // Currently no @media rules — verify CSS is loadable.
    expect(css).to.be.a('string');
    expect(css.length).to.be.greaterThan(100);
});

it('3.5.3.29 — #previewCanvas touch-action check (deferred)', () => {
    // TODO (deferred): When responsive CSS is implemented, assert:
    //   expect(css).to.match(/#previewCanvas[^{]*touch-action[^}]*none/);
    expect(css).to.include('#previewCanvas');
});
```

### Rules

1. **Label tests as "deferred"** in the test name
2. **Verify base selectors exist** (`.main-layout`, `.sidebar`, `#previewCanvas`)
3. **Comment with TODO** for the future assertion
4. **Never assert on features that don't exist yet** — this causes CI failures

## 3. E2E Resize Testing

When testing viewport resize transitions in Playwright, use state-based waits instead of `waitForTimeout()`.

### Pattern

```javascript
// BAD — fragile timing
await page.setViewportSize({ width: 375, height: 667 });
await page.waitForTimeout(300);

// GOOD — waits for Vue re-render
await page.setViewportSize({ width: 375, height: 667 });
await page.waitForSelector('#app', { state: 'visible' });
```

### Why

The Vue app re-renders on window resize. `waitForSelector('#app', { state: 'visible' })` waits for the re-render to complete, which is more reliable than a fixed timeout.

## 4. Naming Clarity for CSS-Related Computed Values

When returning computed values that will be used as CSS properties, name them explicitly to prevent implementation bugs.

### Example

```javascript
// BAD — "padding" is ambiguous (per-side? total?)
return { padding: 12, finalWidth: 44, finalHeight: 44 };

// GOOD — explicit about what the value represents
return { totalPaddingIncrease: 12, finalWidth: 44, finalHeight: 44 };
// Comment: To apply as CSS padding, use totalPaddingIncrease / 2 on each side.
```

A developer implementing responsive CSS might see `padding: 12` and apply `padding: 12px` on each side (left/right), effectively doubling the intended size.

## 5. Sidebar Config for Stacked Layouts

In a stacked mobile layout, `SIDEBAR_CONFIG.MOBILE.width = 0` means "sidebar is not inline" — not "sidebar is invisible". The actual sidebar width is determined by CSS (full viewport width minus padding).

### Documentation

Always document what `width: 0` means in context:

```javascript
// Note: MOBILE width=0 means sidebar is not inline; in stacked mode,
// sidebars render as full-width sections below the canvas (CSS-driven).
export const SIDEBAR_CONFIG = {
    MOBILE: { width: 0, min: 0, max: 0, mode: 'stacked' },
};
```

## 6. PointerEvent Constructor in Browser Tests

Modern browsers support `new PointerEvent(type, options)` with `pointerType: 'touch'` and `isPrimary` properties. This works in Mocha/Chai browser tests without any polyfills.

```javascript
const event = new PointerEvent('pointerdown', {
    bubbles: true,
    cancelable: true,
    clientX: 100,
    clientY: 100,
    pointerType: 'touch',
    isPrimary: true,
    pointerId: 1,
});
```

This is sufficient for testing that existing pointer event handlers (which already handle both mouse and touch) work correctly with touch input. No separate `touchstart`/`touchmove` handlers are needed in modern browsers.
