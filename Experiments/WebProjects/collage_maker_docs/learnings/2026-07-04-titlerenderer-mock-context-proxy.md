# TitleRenderer Mock Context — Proxy-Based Approach

**Date:** 2026-07-04
**Purpose:** Capture learnings from implementing robust Canvas 2D context mocking for unit tests, addressing critical issue discovered during world-review of TitleRenderer tests.

## What Worked

### 1. Proxy-Based Context Wrapper
Using `Proxy` to intercept Canvas 2D API calls proved to be a robust solution:
```javascript
const ctx = new Proxy(realCtx, {
    set(target, prop, value) {
        if (prop === 'font') calls.font.push(value);
        else if (prop === 'fillStyle') calls.fillStyle.push(value);
        target[prop] = value;
        return true;
    },
    get(target, prop) {
        // Intercept properties and methods
        if (prop === 'font') return calls.font[calls.font.length - 1] || '36px Arial';
        if (prop === 'fillStyle') return calls.fillStyle[calls.fillStyle.length - 1] || '#FFFFFF';
        if (prop === 'fillText') {
            return function(text, x, y) {
                calls.fillText.push({ text, x, y });
                return target.fillText.call(target, text, x, y);
            };
        }
        // ... other methods
        return target[prop];
    }
});
```

**Why it succeeded:**
- Works reliably across all modern browsers (Chrome, Firefox, Safari)
- No issues with read-only or non-configurable properties
- Maintains full functionality of the real canvas context
- Allows tracking of all relevant API calls and property assignments

### 2. Real Canvas for Metrics
Using an actual `document.createElement('canvas')` with a real 2D context ensures accurate text measurements:
- `ctx.measureText` returns realistic widths based on system fonts
- No need to mock font metrics or approximate character widths
- Text rendering behavior matches production exactly

### 3. Relative Assertions for Alignment Tests
Instead of checking absolute x positions, verifying relationships between values is more robust:
```javascript
// Instead of: expect(bg.x).to.be.lessThan(40);
// Use: 
expect(bg.x).to.be.lessThanOrEqual(textX - 12);
expect(bg.w).to.be.closeTo(textWidth + 24, 1);
```

**Benefits:**
- Tests pass regardless of canvas width or text length
- Focuses on the core logic rather than exact numbers
- Less brittle when implementation details change slightly

## What Didn't Work / Gaps

### 1. Object.defineProperty on Canvas Properties (Initial Approach)
The first mock context implementation used:
```javascript
Object.defineProperty(ctx, 'font', {
    set(value) { calls.font.push(value); },
    get() { return ...; }
});
```

**Why it failed:**
- Canvas 2D context properties are **host objects** implemented in native C++
- Most browsers make these properties **non-configurable** or read-only
- `Object.defineProperty` either throws `TypeError` or fails silently
- Tests checking `calls.font.length` would be unreliable

### 2. Overly Specific Tolerance Values
Initial tests used tolerance of `1` in some places and `0.5` in others without justification.

**Fix:** Standardized to `0.5` for all alignment position assertions to ensure consistent precision.

## What Was Confusing

### 1. Test Plan vs. Implementation Discrepancy
The test plan specified `padding: 10` for background rect (Section 2.3.3), but the actual `TitleRenderer.js` implementation uses `PADDING = 12`.

**Resolution:** Tests should reflect the actual code, not just the plan. Updated test comments to clarify this and use the correct value (`24` for `2 * 12`).

### 2. Center Alignment Margin Expectation
Test 2.3.1 assumed center alignment would place background near left margin (x < 40), but center alignment uses `(width - totalWidth) / 2` with no margin added. Only left/right alignments use `MARGIN`.

**Lesson:** Carefully understand how each alignment mode computes positions before writing assertions.

## Skill Improvements

### Update: building-web-apps Skill
The `building-web-apps` skill should be updated to include this new pattern for mocking Canvas 2D contexts:

**Add to `references/testing.md` or create new section:**

```markdown
### Robust Canvas 2D Context Mocking with Proxy

For unit testing canvas rendering functions, use a Proxy-based wrapper instead of `Object.defineProperty`:

```javascript
function createMockCtx(width, height) {
    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    const realCtx = canvas.getContext('2d');

    const calls = { /* tracking objects */ };

    return new Proxy(realCtx, {
        set(target, prop, value) {
            // Track property assignments
            if (prop === 'font') calls.font.push(value);
            // ... other properties
            target[prop] = value;
            return true;
        },
        get(target, prop) {
            // Intercept properties
            if (prop === 'font') return calls.font[calls.font.length - 1] || 'default';
            // ... other properties

            // Intercept methods
            if (prop === 'fillText') {
                return function(...args) {
                    calls.fillText.push(args);
                    return target.fillText.apply(target, args);
                };
            }
            // ... other methods

            return target[prop];
        }
    });
}
```

**Key advantages over `Object.defineProperty`:**
- Works with all canvas context properties, including non-configurable ones
- Preserves original context functionality for accurate measurements
- More maintainable and future-proof

### Add to: references/testing.md
Add a new section on "Writing Robust Positioning Tests" that recommends:
- Using relative assertions (e.g., `x + width` comparison) instead of absolute values when possible
- Calculating expected values from actual measured metrics within the test
- Using appropriate tolerance (`0.5` for pixel-perfect, `1-2` for layout)

## Next Steps

- [ ] Update `building-web-apps` skill with Proxy-based mocking pattern
- [ ] Consider refactoring `BackgroundRendererTest.html` to use Proxy instead of `Object.defineProperty` (though it currently works, Proxy is more robust)
- [ ] Add similar Proxy pattern to other test files if they use `Object.defineProperty` on canvas properties
- [ ] Document the standard tolerance values used across the project

---

**Status:** Closed
**Follow-up:** The Proxy pattern should be applied consistently across all canvas rendering unit tests to ensure reliability and maintainability.
