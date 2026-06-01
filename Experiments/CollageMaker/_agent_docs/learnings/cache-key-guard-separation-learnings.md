# Cache Key & didSet Guard Separation — Learnings

**Date:** 2026-06-01
**Purpose:** Document learnings from implementing TitleMetrics cache key optimization and fixing two related bugs.

## What Worked

### `LayoutKey` struct for cache invalidation

A dedicated `Hashable` struct containing only the properties that affect a cached computation provides a clean, type-safe cache key. Compared to computing a hash or tuple manually, the struct:
- Synthesizes `Hashable` conformance from `let` properties
- Documents intent: only these properties affect layout
- Enables `oldValue.layoutKey != newValue.layoutKey` comparison in `didSet`

```swift
struct LayoutKey: Hashable {
    let fontFamily: String
    let fontSize: CGFloat
    let width: CGFloat
    let alignment: NSTextAlignment
}
```

### Tuple cache with key tracking

Storing `(metrics, layoutKey, titleHash)` instead of bare `TitleMetrics?` allows the getter to do a fast cache hit check without relying on the setter having invalidated. This is defensive against future code paths that might skip the setter.

### `NSAttributedString.isEqual(_:)` for attribute-aware comparison

When caching based on attributed string content, comparing only `.string` misses attribute changes (bold, italic, font swap). `isEqual(_:)` compares both string content and all attributes.

## What Didn't Work / Gaps

### `didSet` guard overreach — cache skip vs side effect skip

The initial implementation used a single guard:

```swift
// BUG: returns early for ALL non-layout changes
guard oldValue.layoutKey != titleStyle.layoutKey else {
    if isDraggingTitle { updateTitleImageLive() }
    return  // <-- skips undo, preview, save for color/background changes!
}
```

This caused color/background changes to silently do nothing — no preview update, no undo registration, no persistence. The guard conflated "should I invalidate the cache?" with "should I skip all side effects?"

**Fix:** Separate the two concerns:

```swift
var titleStyle: TitleStyle = .default {
    didSet {
        // Concern 1: cache invalidation (only for layout-affecting changes)
        if oldValue.layoutKey != titleStyle.layoutKey {
            cachedTitleMetrics = nil
        }

        // Concern 2: drag-specific fast path
        if isDraggingTitle {
            updateTitleImageLive()
            return
        }

        // Concern 3: full side effects for all non-drag changes
        undoManager.registerUndo(...)
        updatePreview()
        debouncedSave()
    }
}
```

### `.string` comparison misses attribute changes

```swift
// BUG: bolding "Hello" doesn't change the string
guard oldValue.string != titleAttrString.string else { return }

// FIX: isEqual compares both content and attributes
guard !oldValue.isEqual(titleAttrString) else { return }
```

### Drag position never persisted

The guard that skipped `debouncedSave()` during drag was correct for performance, but meant final drag positions were never saved. **Fix:** Added `debouncedSave()` to `finishTitleDrag()`.

## Key Patterns

### Three-way didSet decomposition

When a property setter has multiple responsibilities (cache, undo, preview, persistence), decompose into independent concerns rather than nesting guards:

1. **Cache invalidation** — conditional on what changed
2. **Fast path** — conditional on interaction context (drag, init, etc.)
3. **Full side effects** — everything else gets undo + preview + save

Each concern has its own guard, and the fast path `return`s early without executing concerns 2-3.

### Test strategy for cache invalidation

When testing cache behavior, use identity comparison (`===`) on the cached object to distinguish cache hits from misses. Each recomputation produces a new object instance, so identity is a reliable signal.

```swift
let first = vm.titleMetrics?.preparedString
vm.titleStyle.positionX = 0.25  // shouldn't invalidate
let second = vm.titleMetrics?.preparedString
#expect(first === second)  // same instance = cache hit
```

## Skill Improvements

### `building-macos-apps/SKILL.md` — State Management

Add to the `@Observable` / `didSet` patterns section:
- **Three-way didSet decomposition** — When a `didSet` observer has cache invalidation, undo registration, and preview rendering, decompose into independent concerns with separate guards. A single `guard ... else { return }` that skips all side effects for "non-important" changes will silently break color/background/attribute updates.

### `building-macos-apps/references/testing/testing-patterns.md`

Add:
- **Identity-based cache testing** — Use `===` on cached reference-type objects to verify cache hits vs misses. Each recomputation should produce a new instance.

## Next Steps

- Continue with Phase 2 (title setter side effects for layered mode) and Phase 3 (tight title render) from the editor performance plan

---
**Status:** Closed
**Follow-up:** Editor performance plan Phase 2
