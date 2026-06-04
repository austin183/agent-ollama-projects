# Computed Property Evaluation After Actor Boundary Crossing — Learnings

**Date:** 2026-06-04
**Context:** Refactoring `BackgroundConfig` CGColor properties from stored to computed during architectural review Phase 2. Caught by diff-review.

## Problem

A struct containing `NSColor` properties was given computed `CGColor` properties to avoid storing derived values:

```swift
struct BackgroundConfig: @unchecked Sendable {
    let color: NSColor
    // ...
    var backgroundColor: CGColor { color.cgColor }
}
```

The safety comment claimed: *"CGColor computed properties are captured before crossing actor boundaries."*

**This was wrong.** The `NSColor` stored values cross the boundary when the struct is captured by a `Task.detached` closure. The computed property evaluates `.cgColor` lazily — on whatever thread accesses it. In this case, `RenderScheduler` executes rendering on a background `DispatchQueue`, so `.cgColor` was called off the main thread.

`NSColor` is MainActor-only — calling `.cgColor` from a background thread is undefined behavior that can crash or produce corrupted colors.

## Why It Wasn't Obvious

The existing skill guidance says: *"Extract CGImage/CGColor on main thread before Task.detached"* — which is correct for explicit extraction. But computed properties create a false sense of safety:

- The struct is constructed on MainActor (correct)
- The `@unchecked Sendable` conformance documents thread safety (plausible)
- The computed property looks like a "view" into the data, not an operation
- **But the computation happens at access time, not construction time**

## The Fix

Store the `CGColor` values at init time (on MainActor), so the thread-safe `CGColor` values cross the boundary instead of the `NSColor` source:

```swift
struct BackgroundConfig: @unchecked Sendable {
    let color: NSColor
    let backgroundColor: CGColor  // captured at init time on MainActor
    // ...
    init(color: NSColor, ...) {
        self.color = color
        self.backgroundColor = color.cgColor  // .cgColor called on MainActor here
        // ...
    }
}
```

## General Rule

**Computed properties on structs that cross actor boundaries evaluate on the destination thread, not the source thread.** If the computation involves MainActor-only types (`NSColor`, `NSAttributedString`, etc.), the computed property will execute on the wrong thread.

**Safe alternatives:**
1. Store the derived value (computed in `init` on the source actor)
2. Use `let` properties that capture the result before crossing the boundary
3. Never use computed properties to access MainActor-only types from non-main contexts

## Related Swift Gotcha: Memberwise Init Conflict

When a struct has all `let` stored properties, Swift synthesizes a memberwise init. If you add computed properties AND define a custom init in an extension, you get *"invalid redeclaration of synthesized memberwise init"* — because the synthesized init and your extension init have the same signature.

**Fix:** Move the init into the struct body (or use `var` on at least one stored property to suppress synthesis).

---
**Status:** Closed
**Follow-up:** None — pattern documented, fix applied
