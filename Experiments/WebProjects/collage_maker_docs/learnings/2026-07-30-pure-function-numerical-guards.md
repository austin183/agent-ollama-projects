# Pure Function Numerical Guards: NaN and Infinity Bypass Comparison Checks

**Date:** 2026-07-30
**Context:** Phase 2 — Pinch Zoom Sensitivity, `applyZoomExponent()` in MultiTouchHandler.js

## The Problem

A pure math function with a comparison guard like `if (ratio <= 0) return 1.0;` appears to protect against invalid inputs, but JavaScript's comparison semantics allow `NaN` and `Infinity` to bypass it:

| Input | `ratio <= 0` | `Math.pow(ratio, 0.3)` | Result |
|-------|-------------|----------------------|--------|
| `NaN` | `false` | `NaN` | **NaN propagates** |
| `Infinity` | `false` | `Infinity` | **Infinity propagates** |
| `undefined` | `false` | `NaN` | **NaN propagates** |
| `null` | `true` | — | Returns 1.0 (safe) |
| `-1` | `true` | — | Returns 1.0 (safe) |

The root cause: JavaScript comparisons with `NaN` always return `false` (even `NaN === NaN` is `false`), and `Infinity` is a valid positive number.

## The Fix

Use `Number.isFinite()` which returns `false` for `NaN`, `Infinity`, `-Infinity`, and `undefined`:

```javascript
export function applyZoomExponent(ratio) {
    if (!Number.isFinite(ratio) || ratio <= 0) return 1.0;
    return Math.pow(ratio, 0.3);
}
```

Now all invalid inputs are caught:

| Input | `!Number.isFinite(ratio)` | Result |
|-------|--------------------------|--------|
| `NaN` | `true` | Returns 1.0 |
| `Infinity` | `true` | Returns 1.0 |
| `undefined` | `true` | Returns 1.0 |
| `null` | `false`, then `null <= 0` is `true` | Returns 1.0 |
| `-1` | `false`, then `-1 <= 0` is `true` | Returns 1.0 |

## Why It Matters

When the return value of a pure math function feeds into Canvas 2D transforms, state mutation, or reactive data:

- **NaN in Canvas 2D:** `ctx.scale(NaN, NaN)` silently corrupts the transform matrix. Subsequent draws render nothing.
- **NaN in crop state:** `sourceRect.width / NaN = NaN` propagates through `CropManager.zoomCrop()`. Even though `Math.max(NaN, 1) = NaN`, the clamping does not recover from NaN.
- **NaN in Vue reactive state:** May cause rendering loops or silent failures.

## When to Apply

Apply `Number.isFinite()` guards in any pure math function that:
1. Accepts numeric parameters from potentially noisy sources (touch coordinates, computed ratios)
2. Returns values consumed by Canvas 2D, CSS transforms, or reactive state
3. Uses comparison operators (`<`, `>`, `<=`, `>=`) as guards — these do NOT catch NaN/Infinity

## When NOT to Apply

- If the function is only called with compile-time constants (no runtime noise)
- If the caller already guarantees finite, non-zero inputs AND the call chain is short and auditable
- If the function is a simple pass-through where NaN propagation is intentional (e.g., "garbage in, garbage out" design)

## Testing Pattern

Always test the edge cases explicitly:

```javascript
it('handles NaN ratio gracefully by returning 1.0', () => {
    const result = applyZoomExponent(NaN);
    expect(result).to.equal(1.0);
    expect(result).to.not.be.NaN;
});

it('handles Infinity ratio gracefully by returning 1.0', () => {
    expect(applyZoomExponent(Infinity)).to.equal(1.0);
});

it('handles undefined ratio gracefully by returning 1.0', () => {
    const result = applyZoomExponent(undefined);
    expect(result).to.equal(1.0);
    expect(result).to.not.be.NaN;
});
```

## Related

- World-review is the best mechanism for discovering these edge cases — unit tests verify specified behavior; world-review questions assumed behavior
- `computePinchScale()` in the same file uses `if (initialDistance <= 0)` which is safe because it guards the divisor (preventing division by zero), not the result of a comparison on the output
