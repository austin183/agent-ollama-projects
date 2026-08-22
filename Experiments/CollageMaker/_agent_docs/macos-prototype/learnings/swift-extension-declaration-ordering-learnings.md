# Swift Extension Declaration Ordering — Learnings

**Date:** 2026-05-29
**Session:** 65
**Purpose:** Document gotcha discovered while implementing LayoutStrategy pattern.

---

## The Gotcha

When defining an extension on a type from another file (e.g., `extension LayoutStyle`) in a file that also defines new types the extension references (e.g., `UniformLayoutStrategy`), Swift's per-file compilation model requires the extension to appear **after** the types it references within the same file.

```swift
// LayoutGenerator.swift

// WRONG — extension appears before the types it references:
extension LayoutStyle {
    func makeStrategy() -> LayoutStrategy {
        switch self {
        case .uniform: return UniformLayoutStrategy() // ❌ cannot find in scope
        }
    }
}

struct UniformLayoutStrategy: LayoutStrategy { ... }

// CORRECT — extension appears after the types:
struct UniformLayoutStrategy: LayoutStrategy { ... }

extension LayoutStyle {
    func makeStrategy() -> LayoutStrategy {
        switch self {
        case .uniform: return UniformLayoutStrategy() // ✅ found
        }
    }
}
```

## Why It Happens

Swift compiles each `.swift` file as a separate compilation unit. Within a single compilation unit, declarations must be ordered so that forward references resolve. An extension defined early in the file cannot reference a struct defined later in the same file, even though both are in the same module.

This is different from cross-file references (where any file in the module can see any other file's public/internal declarations) — within a single file, top-to-bottom ordering matters.

## Alternatives

1. **Place extension after referenced types** (what we did) — simplest fix
2. **Place extension in the extended type's file** — `LayoutStyle.swift` can reference `LayoutGenerator.swift`'s types since cross-file references work freely
3. **Use a factory function** instead of an extension — `func makeStrategy(for style: LayoutStyle) -> LayoutStrategy`

## Skill Improvements

- `building-macos-apps` skill: Add a note under "Implementation Phases" or a new "Swift Compilation Gotchas" section about same-file declaration ordering for extensions

---
**Status:** Closed
**Follow-up:** None
