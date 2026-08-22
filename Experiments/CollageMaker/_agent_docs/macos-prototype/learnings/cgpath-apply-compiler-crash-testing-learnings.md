# Testing CoreGraphics Transforms — Learnings

**Date:** 2026-06-09
**Context:** Phase D test implementation (Session 96), diff-review feedback

---

## Swift 6.3.2 Compiler Crash on CGPathApply Closure

The `path.apply(info: nil) { _, element in ... }` pattern crashes the swift-frontend compiler (Swift 6.3.2, macOS 26.5 SDK) when used in a test target. The crash occurs during compilation, not at runtime — it manifests as a "Please submit a bug report" stack dump from swift-frontend.

**Reproduction:** Any test file that imports `CoreGraphics` and uses `CGPath.apply(info:)` with a closure that accesses `element.pointee.type` triggers the crash.

**Workaround:** Test `CGAffineTransform` logic by applying the transform to known `CGPoint` coordinates via `CGPoint.applying(transform)`, then asserting on the resulting coordinates. This avoids CGPath element iteration entirely.

**Example:**
```swift
// Instead of iterating CGPath elements:
let transform = PanelGeometry.transformForPanel(boundingRect: boundingRect, targetRect: targetRect)
let mappedPoint = CGPoint(x: 50, y: 0).applying(transform)
#expect(mappedPoint.y == 100)
```

**Applicability:** This is a compiler bug, not a fundamental limitation. Future Swift versions may resolve it. Until then, avoid `CGPathApply` in test targets.

---

## Shadow Implementation Anti-Pattern

When testing a `private` type or method, it is tempting to duplicate the logic locally in the test file to verify correctness. This "shadow implementation" provides zero regression protection — if the actual code changes or introduces a bug, the shadow implementation continues to pass as long as it matches its own (stale) logic.

**Anti-pattern:**
```swift
// In test file — duplicates CollageEditorView logic:
private func applyPanelShapeTransform(...) {
    // Same math as in the actual code
}
// Tests verify the shadow, not the real code
```

**Fix:** Extract the testable unit into a non-private type or method. Options in order of preference:
1. Change visibility to `internal` (accessible via `@testable import`)
2. Extract the pure-function logic to a static method on a model type (e.g., `PanelGeometry.transformForPanel()`)
3. Create a test-only extension if the type is in the same module

**Rule of thumb:** If the test file contains more than a few lines of logic that mirrors the code under test, the test is checking itself, not the implementation.

---

## Weak Switch Assertions in Enum Round-Trip Tests

When testing Codable round-trips for enum types, a `switch` statement that ignores one case with `break` will pass silently even if the decoder returns the wrong case.

**Anti-pattern:**
```swift
switch decoded.destination {
case .rect:
    break  // Test passes even if .path was incorrectly decoded as .rect
case .path(_, let rect):
    #expect(rect == boundingRect)
}
```

**Fix:** Record an issue in the unexpected case:
```swift
switch decoded.destination {
case .rect:
    Issue.record("Expected .path geometry after round-trip")
case .path(_, let rect):
    #expect(rect == boundingRect)
}
```

**Broader principle:** Every branch of a `switch` in a test should either assert something or explain why that branch is acceptable. An empty branch is a latent bug — it means the test would pass even if the code produces the wrong result.

---

## Transform Extraction for Testability

When a SwiftUI `Shape` contains `CGAffineTransform` logic, the transformation math is inseparable from the SwiftUI `Path` type. The test target cannot import SwiftUI, so the transform logic is untestable.

**Pattern:** Extract the transform computation to a static method on a model type that only depends on `CoreGraphics`:

```swift
// In PanelGeometry.swift (model layer, no SwiftUI):
enum PanelGeometry {
    static func transformForPanel(boundingRect: CGRect, targetRect: CGRect) -> CGAffineTransform {
        // Pure CG math — testable without SwiftUI
    }
}

// In CollageEditorView.swift (view layer, uses SwiftUI):
struct PanelShape: Shape {
    func path(in rect: CGRect) -> Path {
        let transform = PanelGeometry.transformForPanel(...)
        return Path(cgPath.copy(using: &transform)!)
    }
}
```

This is a specific instance of the broader principle: **extract pure-function logic from UI types to make it testable**.

---
**Status:** Complete
**Follow-up:** Monitor for Swift compiler fix on CGPathApply crash
