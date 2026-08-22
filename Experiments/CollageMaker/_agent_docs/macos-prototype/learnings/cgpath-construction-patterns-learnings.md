# CGPath Construction Patterns — Learnings 2026-06-06

**Purpose:** Document CGPath construction gotchas discovered during diagonal slices layout strategy implementation.

## What Worked

- **`CGMutablePath` with implicit `CGPath` coercion** — Creating a `CGMutablePath()`, building vertices with `move(to:)`/`addLine(to:)`/`closeSubpath()`, then passing it to a `CGPath`-typed parameter works via Swift's implicit bridging. No explicit conversion needed.

- **Manual bounding rect from corner extrema** — For convex polygons where all vertices are known, computing `minX`/`minY`/`maxX`/`maxY` across the corners is O(1) and exact. More efficient than iterating path elements or calling into CoreGraphics.

## What Didn't Work

- **`CGPath` closure initializer** — The Swift 6 pattern `CGPath { mutablePath, _ in ... }` (a closure-based factory that takes a `CGMutablePath` and returns nothing) does **not** exist in the macOS 26.5 SDK. Attempting to use it produces:

  ```
  error: no exact matches in call to initializer
      let path = CGPath { mutablePath, _ in
                 ^
  ```

  The only `CGPath` initializers available are `CGPath(rect:transform:)` and `CGPath(ellipseIn:transform:)`. The closure factory may be a newer Swift/SDK feature not yet shipped.

- **`CGMutablePath.boundingRect`** — `CGMutablePath` does not expose `boundingRect` in Swift. The underlying C type `CGMutablePathRef` has `CGPathGetBoundingBox()`, but this is not bridged to the Swift `CGMutablePath` struct. Must either coerce to `CGPath` first (roundabout) or compute manually.

## Key Patterns

### Building an arbitrary CGPath from vertices

```swift
let mutablePath = CGMutablePath()
mutablePath.move(to: corners[0])
for corner in corners[1...] {
    mutablePath.addLine(to: corner)
}
mutablePath.closeSubpath()
let path: CGPath = mutablePath  // implicit coercion
```

### Computing bounding rect from known vertices

```swift
let minX = corners.min(by: { $0.x < $1.x })!.x
let minY = corners.min(by: { $0.y < $1.y })!.y
let maxX = corners.max(by: { $0.x < $1.x })!.x
let maxY = corners.max(by: { $0.y < $1.y })!.y
let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
```

Or more concisely for small vertex sets:

```swift
let minX = min(corners[0].x, corners[1].x, corners[2].x, corners[3].x)
let minY = min(corners[0].y, corners[1].y, corners[2].y, corners[3].y)
let maxX = max(corners[0].x, corners[1].x, corners[2].x, corners[3].x)
let maxY = max(corners[0].y, corners[1].y, corners[2].y, corners[3].y)
let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
```

## When This Matters

Any time you need to create a non-rectangular `CGPath` for clipping, hit testing, or rendering — hexagonal panels, circular masks, star shapes, etc. — you'll hit these patterns. The existing `PanelGeometry.path(cgPath:boundingRect:)` enum case is designed for this use.

## Skill Improvements

### `building-macos-apps/references/graphics/coordinate-systems.md`

Add a "CGPath Construction" section documenting:
1. `CGMutablePath` as the only way to build arbitrary paths (closure factory unavailable)
2. Manual bounding rect computation from vertices
3. Implicit `CGMutablePath` -> `CGPath` coercion

---
**Status:** Closed
**Follow-up:** Update coordinate-systems.md skill reference
