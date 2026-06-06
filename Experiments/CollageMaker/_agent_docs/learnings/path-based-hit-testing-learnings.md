# Path-Based Hit Testing — Learnings 2026-06-06

**Purpose:** Document learnings from Phase 4 of the non-rectangular panel geometry refactoring: updating `CropManager.hitTestPanel()` to support `CGPath` containment for non-rectangular panels.

## What Worked

- **Two-pass hit testing** — Fast `CGRect.contains()` filter (O(1) per panel) narrows candidates, then expensive `CGPath.contains()` (O(vertices)) only runs on bounding-box matches. Zero overhead for rectangular layouts, bounded cost for path panels.
- **`switch` exhaustiveness** — Using `switch geometry { case .rect: ... case .path: ... }` instead of `if case .path = geometry { ... }` ensured both enum cases were handled. The `case` guard pattern silently skipped `.rect` panels, causing incorrect fallback to arbitrary dict order.
- **Coordinate conversion at hit-test time** — `screenToCanvasPoint()` converts the SwiftUI tap (preview coordinates, top-left origin) to canvas coordinates (bottom-left origin) before `CGPath.contains()`. The `CGPath` lives in canvas space; the point must match.

## What Didn't Work / Gaps

- **`case` guard pattern for partial enum handling** — The plan document used `if let geometry = geometries[id], case .path(let cgPath, _) = geometry` which only matched `.path` and silently ignored `.rect`. When a `.path` panel's bounding box contained the tap but the actual path didn't, the function fell through to `candidates.first?.key` — returning an arbitrary panel by dict iteration order. This bug existed in the plan and was faithfully reproduced in code until diff-review caught it.

- **`Dictionary` iteration order is not guaranteed** — `[UUID: CGRect]` provides no ordering guarantee. `candidates.first?.key` returns an arbitrary element. When used as fallback after a path containment miss, it could return any bounding-box candidate, not necessarily the one the user tapped.

## Key Pattern: Two-Pass Hit Testing for Mixed Geometry

When panels may be rectangular or path-based, use a two-pass approach:

```swift
// Pass 1: fast bounding-box filter
let candidates = panelFrames.filter { $0.value.contains(location) }
guard !candidates.isEmpty else { return nil }

// Pass 2: precise containment per candidate
for (id, _) in candidates {
    guard let geometry = geometries[id] else { continue }
    switch geometry {
    case .rect:
        return id  // bounding box already validated
    case .path(let cgPath, _):
        if cgPath.contains(canvasPoint) {
            return id
        }
    }
}
return nil  // no match
```

**Why this works:**
- Rectangular panels: pass 1 validates containment, pass 2 returns immediately
- Path panels: pass 1 provides cheap rejection, pass 2 provides precise acceptance
- Mixed panels: `.rect` returns on first encounter, `.path` only runs expensive check when bounding box matches
- No fallback to arbitrary dict order: explicit `return nil` when no path candidate matches

**Why the `case` guard pattern fails:**

```swift
// DON'T: silently skips .rect panels
for (id, _) in candidates {
    if let geometry = geometries[id], case .path(let cgPath, _) = geometry {
        if cgPath.contains(canvasPoint) { return id }
    }
}
return candidates.first?.key  // arbitrary dict order!
```

This pattern has two defects:
1. `.rect` panels are never matched in pass 2 — they fall through
2. The fallback `candidates.first?.key` returns an arbitrary element (could be a `.path` that failed containment)

## Skill Improvements

### `building-macos-apps/references/gestures/gesture-targeting.md`

Add a section on "Path-Based Hit Testing" documenting the two-pass pattern (bounding-box filter + precise path containment) and the `switch` exhaustiveness requirement for mixed geometry.

### `building-macos-apps/SKILL.md` — Swift Compilation Gotchas

Add: "When iterating over enum values in a collection, prefer `switch` over `if case` for exhaustiveness. The `if case .specific = value` pattern silently skips unmatched cases, which is dangerous when the collection contains mixed enum cases that need different handling."

## Next Steps

- Update `gesture-targeting.md` skill reference with two-pass hit testing pattern
- Consider adding a unit test for `.path` geometry hit testing when diagonal/hexagonal strategies are implemented

---
**Status:** Closed
**Follow-up:** Update gesture-targeting.md skill reference when path-based layouts are active
