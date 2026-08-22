# Layout Round-Trip Tests - Learnings 2026-06-26

**Purpose**: Capture insights from implementing Phase 4 Layout Style Round-Trip tests (`LayoutRoundTripTests.swift`) including floating point precision handling and test utility naming accuracy.

## What Worked

### Floating Point Precision Handling for CGRect Comparison
When comparing `CGRect` values from layout calculations involving trigonometry (angles) and division, using a custom `.approximatelyEqual(to:tolerance:)` helper prevents flaky tests due to infinitesimal floating-point errors. The diagonal slices layout angle round-trip test specifically benefits from this pattern:

```swift
private extension CGRect {
    func approximatelyEqual(to other: CGRect, tolerance: CGFloat = 1e-6) -> Bool {
        let dx = abs(origin.x - other.origin.x)
        let dy = abs(origin.y - other.origin.y)
        let dw = abs(width - other.width)
        let dh = abs(height - other.height)
        return dx <= tolerance && dy <= tolerance && dw <= tolerance && dh <= tolerance
    }
}
```

This pattern was already defined in the test file and used successfully in `singleImageAllStyles()`, but was initially missed when comparing bounding rects in `diagonalAngleRoundTrip()`. The diff-review caught this issue and the fix prevented potential flakiness.

### Accurate Test Utility Function Naming
Renaming `assertNonOverlappingPanels(_:)` to `assertPanelsHavePositiveArea(_:)` accurately reflected what the function actually does (verifies positive bounding rect dimensions, not actual overlap intersection checks). This prevents misleading future developers who might assume the function performs geometric intersection tests.

## What Didn't Work / Gaps

### Initial CGRect Comparison with `==` Operator
The initial implementation of `diagonalAngleRoundTrip()` used `==` for `CGRect` comparison:
```swift
#expect(originalPanel.geometry.boundingRect == finalPanel.geometry.boundingRect)
```

This pattern is problematic because layout calculations involving trigonometry (angles) and division frequently introduce infinitesimal floating-point errors. The test file already defined a helper `approximatelyEqual(to:tolerance:)` on line 180 specifically to handle this, but it was not used in the diagonal angle round-trip comparison.

## What Was Confusing

None identified - the diff-review process clearly highlighted both issues (misleading function name and floating point precision error) with specific recommendations for fixes.

## Skill Improvements

### Testing Patterns Documentation
The testing patterns documentation should emphasize:
1. **CGRect comparisons in layout tests**: Always use `.approximatelyEqual(to:)` or similar tolerance-based comparison when comparing `CGRect` values from calculations involving trigonometry, division, or coordinate transformations. Never use `==` for `CGRect` comparison in layout math tests.

2. **Test utility function naming**: Test utility functions should have names that accurately reflect their actual behavior. If a function only checks positive dimensions and not actual geometric overlap, the name should reflect this (e.g., `assertPanelsHavePositiveArea(_:)` instead of `assertNonOverlappingPanels(_:)`).

## Next Steps

- Consider adding `.approximatelyEqual(to:)` helper to a shared test utilities file if it becomes a common pattern across multiple test files
- Review existing layout tests for similar `CGRect ==` comparisons that might be vulnerable to floating-point precision issues

---
**Status**: Closed
**Follow-up**: Layout Round-Trip Tests implementation, diff-review findings addressed
