# Multi-Field Cache Invalidation — Learnings

**Date:** 2026-06-03
**Session:** 80
**Purpose:** Document learnings from implementing cached title layout in ViewModel and debugging the clear-restore stale nil bug.

---

## Multi-Field Cache Must Clear All Fields on Invalidation

When a cache stores multiple fields (result + key + input), clearing only the result field on one condition while leaving key fields stale causes the cache to return stale `nil` on restore.

**Scenario:**
```swift
private var cachedBounds: TitleBoundsCache?
private var cachedKey: LayoutKey?
private var cachedString: NSAttributedString?

private func ensureBounds() -> TitleBoundsCache? {
    guard !titleAttrString.string.isEmpty else {
        cachedBounds = nil  // BUG: only clears result, leaves key + string stale
        return nil
    }
    let currentKey = titleStyle.layoutKey
    if let cachedStr = cachedString, cachedStr.isEqual(titleAttrString),
       cachedKey == currentKey {
        return cachedBounds  // returns stale nil!
    }
    // ... compute and cache ...
}
```

**Trace:**
1. Title set to "Hello" → cache populated: `cachedBounds` = bounds, `cachedKey` = key, `cachedString` = "Hello"
2. Title cleared (`""`) → guard fires: `cachedBounds = nil`. But `cachedKey` and `cachedString` retain stale values.
3. Title restored to "Hello" → guard passes (not empty). `cachedStr.isEqual(titleAttrString)` → `true`. `cachedKey == currentKey` → `true`. Returns `cachedBounds` which is `nil`.

**Symptom:** Title frame disappears after undo of a title clear. The value is `nil` even though the title is populated.

**Fix — Clear all fields:**
```swift
guard !titleAttrString.string.isEmpty else {
    cachedBounds = nil
    cachedString = nil
    cachedKey = nil
    return nil
}
```

**Defensive alternative — Guard the result:**
```swift
if let cachedBounds = cachedBounds,
   let cachedStr = cachedString, cachedStr.isEqual(titleAttrString),
   cachedKey == currentKey {
    return cachedBounds
}
```

This second approach catches the stale nil regardless of whether all fields were cleared — if `cachedBounds` is nil, the cache always misses and recomputes.

**General rule:** Every code path that clears a cache result must also clear its key fields. Prefer the defensive guard pattern as it catches missed clears.

---

## Behavioral Tests Over Identity for Cache Verification

When testing cache behavior with `@Observable` classes, identity comparison (`===`, `ObjectIdentifier`) on cached objects is fragile. The `@Observable` macro may re-create underlying objects, and test ordering can affect identity.

**Fragile approach:**
```swift
let cache1 = vm.cachedTitleBounds
vm.titleStyle.positionX = 0.75
#expect(vm.cachedTitleBounds === cache1)  // fragile: test ordering, @Observable re-creation
```

**Robust approach:**
```swift
let minWidthBefore = vm.cachedTitleMinWidth
let frameBefore = vm.cachedTitleCanvasFrame
vm.titleStyle.positionX = 0.75
#expect(vm.cachedTitleMinWidth == minWidthBefore)  // bounds unchanged = cache hit
#expect(vm.cachedTitleCanvasFrame?.origin.x != frameBefore?.origin.x)  // frame math changed = position updated
```

Behavioral tests verify the *outcome* of caching (expensive computation skipped, cheap math still runs) without depending on object identity. They are more resilient to `@Observable` internals and test ordering.

---

## Computed Property Caching in ViewModel for Gesture Hot Paths

When `@Observable` has no path-based granularity for computed properties, any tracked property change triggers full view body re-evaluation. Moving expensive computation (CoreText layout, image processing) from view computed properties to a cached ViewModel method eliminates per-frame work.

**Pattern:**
```swift
// ViewModel — caches expensive computation
private var cachedResult: ExpensiveType?
private var cachedKey: CacheKey?

func ensureResult() -> ExpensiveType? {
    if cachedKey == currentKey { return cachedResult }
    cachedResult = computeExpensive(currentKey)
    cachedKey = currentKey
    return cachedResult
}

var cachedFrame: CGRect? {
    guard let result = ensureResult() else { return nil }
    // Cheap math using cached result + current position
    return computeFrame(from: result, position: currentPosition)
}

// View — thin delegator
private var titleFrame: CGRect? { viewModel.cachedFrame }
```

**Key insight:** Position changes during drag recompute the CGRect (cheap math) but reuse the cached expensive result. Layout changes invalidate the cache and trigger fresh computation.

**Existing precedent:** Session 65 introduced `TitleMetrics` caching in the ViewModel for title drag. This session extended the pattern to `TitleBoundsCT` for the gesture hot path where `cropMapVersion` drives 33fps body re-evaluation.

---

**Status:** Closed
**Follow-up:** None
