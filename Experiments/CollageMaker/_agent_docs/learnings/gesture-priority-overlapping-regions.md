# Gesture Priority — Overlapping Hit Regions — Learnings

**Date:** 2026-05-15
**Session:** 17
**Purpose:** Document learnings from fixing the round-4.1 bug where clicking on the title overlay also triggered the panel drag-to-reorder gesture underneath.

---

## What Worked

- **Preemptive region exclusion** — Adding a single `contains()` check at the top of each gesture handler is the simplest way to enforce priority between overlapping hit regions. No restructuring of the gesture hierarchy was needed.
- **Minimal change surface** — Two guard clauses (one in the panel drag `onChanged`, one in `onTapGesture`) resolved both reported issues. The existing title drag gesture required no changes since it already had its own locking mechanism.
- **Consistent with existing pattern** — The panel drag gesture already guarded against title drag with `guard !viewModel.isDraggingTitle else { return }`. The fix extended this pattern by checking the title frame *before* locking the panel, rather than relying on the `isDraggingTitle` flag (which only fires after the title drag's own `onChanged` runs).

## What Didn't Work / Gaps

- **`isDraggingTitle` guard fires too late** — The existing `guard !viewModel.isDraggingTitle` in the panel drag handler only prevents panel drag *after* the title drag has locked. But both `simultaneousGesture` DragGestures fire their `onChanged` in the same pass. The title drag sets `isDraggingTitle = true` in its `onChanged`, but the panel drag's `onChanged` also runs simultaneously with `isDraggingTitle` still `false`. The `@Observable` property update doesn't propagate until the next render cycle, so the guard doesn't help within the same gesture event.

- **ZStack ordering doesn't help** — The title overlay rectangle appears visually above the panel hit areas in the ZStack, but SwiftUI's `simultaneousGesture` attaches to the ZStack as a whole, not to individual children. ZStack visual stacking order has no effect on which gesture fires. Both gestures receive the same `startLocation` regardless of which visual element is "on top."

## Root Cause Analysis

The bug had two manifestations:

1. **Drag overlap**: Both `simultaneousGesture` DragGestures receive `startLocation` in their `onChanged`. The title drag checks `scaledTitleFrame.contains(startLocation)` and locks. The panel drag checks `panelAt(startLocation)` which returns the panel underneath the title. Both fire simultaneously, so the panel drag locks before `isDraggingTitle` is set.

2. **Tap overlap**: The `.onTapGesture` only checks `panelAt(location)`, never considering the title frame. Tapping the title selects the panel underneath.

## Key Pattern: Gesture Priority with Preemptive Exclusion

When multiple `simultaneousGesture` handlers on the same view have overlapping hit regions, use preemptive exclusion:

```swift
// Lower-priority gesture checks higher-priority region first
.simultaneousGesture(
    DragGesture(minimumDistance: 5)
        .onChanged { value in
            // Preemptive exclusion: bail if drag started on higher-priority region
            if let highPriorityFrame = highPriorityRegion,
               highPriorityFrame.contains(value.startLocation) {
                return
            }
            // Normal hit-test for this gesture's region
            if let id = hitTest(value.startLocation) {
                // ... lock and handle
            }
        }
)
```

**Why this works:** The check runs in the same closure before any state mutation. The higher-priority gesture's own handler still runs independently and locks normally. No timing issues, no render-cycle dependencies.

**Alternative considered but rejected:**
- `.highPriorityGesture` instead of `.simultaneousGesture` — would prevent both from firing, but we need them to coexist for non-overlapping regions (title drag on title, panel drag on panel).
- Separate ZStack layers with `.allowsHitTesting(false)` — would break the shared coordinate space and overlay rendering.
- Combining into a single DragGesture with if/else branching — works but loses the clean separation of concerns between gesture handlers.

## Tap Gesture Priority

The same preemptive exclusion pattern applies to `.onTapGesture`:

```swift
.onTapGesture { location in
    // Preemptive exclusion
    if let highPriorityFrame = highPriorityRegion,
       highPriorityFrame.contains(location) {
        return
    }
    // Normal tap handling
    if let id = hitTest(location) {
        select(id)
    }
}
```

## Skill Improvements

### `building-swiftui-macos-apps` main skill — Gesture section

Add a pitfall entry:

> **`isDragging` flag doesn't prevent simultaneous gesture conflict** — When two `simultaneousGesture` DragGestures fire on the same view, setting `isDraggingTitle = true` in one handler doesn't propagate to the other handler's `onChanged` until the next render cycle. Both handlers run in the same pass with stale state. Use preemptive region exclusion (`contains(startLocation)` check) in the lower-priority gesture instead.

### `building-swiftui-macos-apps/REFERENCES/swiftui-gestures.md`

Add a section on "Overlapping Hit Regions" covering:
- Why ZStack visual order doesn't affect simultaneous gestures
- Preemptive exclusion pattern with `contains(startLocation)`
- Why `isDragging` flags don't work within the same gesture event

## Next Steps

- Consider: hide title overlay stroke when not dragging (cleaner canvas appearance)
- Consider: adding a visual indicator that the title is the active drag target when hovering over it
- Consider: extending the preemptive exclusion pattern to the pinch gesture if future overlays overlap panel regions

---
**Status:** Closed
**Follow-up:** Round 4.1 bug is resolved. No further action needed unless user reports additional gesture conflicts.
