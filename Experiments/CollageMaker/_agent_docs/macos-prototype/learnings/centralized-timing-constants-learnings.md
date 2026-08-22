# Centralized Timing Constants — Learnings

**Date:** 2026-06-21
**Purpose:** Document learnings from extracting render throttle and debounce timing constants into a centralized `FrameTempo` enum.

## What Worked

### Single source of truth for FPS tuning

Scattered `.milliseconds(N)` literals across 11 call sites made it impossible to reason about the overall FPS profile. A centralized `enum` with `static let` constants gives one file to adjust for global tuning. The reference table in the header documents the ms-to-fps mapping independently of actual values, so inline comments never go stale when values change.

```swift
enum FrameTempo {
    static let scrollRenderInterval: Duration = .milliseconds(20)
    static let panPreviewDebounce: Duration = .milliseconds(20)
    // ...
}
```

### Grouping by concern, not by caller

Constants are grouped by their role (gesture throttles, gesture debounces, post-interaction debounces) rather than by which manager uses them. This makes the file readable as a performance tuning document, not as an API reference.

## Key Patterns

### Reference table decoupled from values

Put the ms-to-fps lookup table in the header doc comment, not as inline comments on each constant. Inline comments like `// ~60fps` become misleading when the value changes from 16ms to 20ms. A decoupled table stays correct:

```swift
/// | ms  | fps  | Typical use                              |
/// |-----|------|------------------------------------------|
/// | 16  | ~60  | Display-native refresh rate              |
/// | 20  | ~50  | Smooth with reduced CPU load             |
```

### Enum over struct for constants

`enum` with no cases prevents instantiation. `struct` would allow `FrameTempo()` which is meaningless. This is the same pattern as `SizeConstants` and `CoordinateConverter` in this codebase.

## Next Steps

- Consider Phase 2 and 3 of the FPS consistency plan when ready

---
**Status:** Closed
**Follow-up:** FPS consistency plan Phases 2-3
