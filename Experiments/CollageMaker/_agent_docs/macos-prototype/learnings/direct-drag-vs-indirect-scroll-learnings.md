# Direct Drag vs Indirect Scroll — Gesture Direction and Compounding

**Date:** 2026-05-22
**Purpose:** Document learnings from fixing Panel Editor crop drag direction, sensitivity, and scroll inversion in round 14.2.

## What Worked

- **`@State` base capture pattern** — Capturing the original state at drag start (e.g., `dragBaseSourceOrigin = crop.sourceRect.origin`) and computing `base + cumulativeTranslation` on each tick gives 1:1 cursor-to-overlay movement. This avoids both direction inversion and compounding.

## What Didn't Work / Gaps

- **Cumulative translation compounding with re-read state** — `DragGesture.Value.translation` is cumulative from drag start. When the target state is read from a `@Bindable` property inside `onChanged`, SwiftUI re-evaluates the binding on each tick, returning the already-moved state. Adding cumulative translation to the already-moved state compounds the movement exponentially. The fix is to capture the base state at drag start in a `@State` variable, never re-reading the live binding for the base.

- **Shared pan math inverts direct drag** — `CropManager.applyPan` subtracts the pan delta (`baseOrigin - panDelta`), which is correct for indirect scroll (scrolling down shows content from above). The same math inverts direct drag, where the user expects the overlay to follow the cursor. For direct drag, the translation must be negated before passing to `applyPan`, or the pan pipeline should be bypassed entirely.

- **Manual scroll delta negation** — Negating `event.scrollingDeltaX/Y` when `isDirectionInvertedFromDevice` is `false` inverts scroll direction. The raw deltas already produce the correct pan direction when passed through the subtraction-based `applyPan` math.

## Key Patterns

### Cumulative Translation with Live State — Capture Base

```swift
// WRONG — compounding: crop.sourceRect.origin is already moved on each tick
// because the binding was updated by the previous onChanged call
let newOX = crop.sourceRect.origin.x + value.translation.width * scale

// RIGHT — capture original at drag start, add cumulative translation to fixed base
@State private var dragBaseSourceOrigin: CGPoint = .zero

// On first onChanged:
dragBaseSourceOrigin = crop.sourceRect.origin

// On every onChanged:
let newOX = dragBaseSourceOrigin.x + value.translation.width * scale
```

### Direct Drag vs Indirect Scroll

When your pan manager subtracts the delta (`base - delta`), it implements indirect scrolling semantics. For direct drag, either negate the translation before passing to the manager, or bypass the manager and compute the new position directly from the captured base:

```swift
// Approach A: negate for shared manager
viewModel.pan(by: CGSize(width: -transX, height: -transY))

// Approach B: bypass manager, compute directly (preferred for simple cases)
let newOX = dragBaseSourceOrigin.x + transX
viewModel.applyCrop(sourceRect: CGRect(x: newOX, ...))
```

## Skill Improvements

### `building-macos-apps/references/swiftui-gestures.md` — Pitfalls

Add:
- **Cumulative translation compounds with live binding state** — `DragGesture.Value.translation` is cumulative from drag start. If the target state is read from a `@Bindable` property inside `onChanged`, the binding returns the already-updated state each tick, causing compounding. Capture the base state at drag start in a `@State` variable. Never re-read the live binding for the base during the gesture.
- **Pan manager subtraction inverts direct drag** — A pan method that computes `baseOrigin - panDelta` implements indirect scroll semantics. Direct drag requires negated translation or bypassing the pan pipeline entirely.

---
**Status**: Closed
**Follow-up**: None
