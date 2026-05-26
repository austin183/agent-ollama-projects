# @State + .onChange Staleness with UUID Collections — Debrief 2026-05-26

**Purpose:** Capture learnings from the panel selection staleness bug — `@State` cache invalidated by `regenerateLayout()` creating new panel UUIDs, causing a render gap where hit-testing and visual overlays failed.

## What Worked

- **On-the-fly `let` bindings in GeometryReader** — Computing `let panelFrames` and `let titleFrame` as local `let` bindings inside the `GeometryReader` closure eliminated all staleness. These recompute every render cycle from `viewModel.panels`, so they're always in sync with the current panel UUIDs.

- **Diagnosing via `.onAppear` logging** — The existing "Highlight: panel id NOT FOUND in panels" log in `CollageEditorView` was the key diagnostic. It printed when `selectedPanelId` was set but `scaledPanelFrames[selectedId]` returned `nil`, confirming the cache was stale.

## What Didn't Work / Gaps

- **`@State` cache + `.onChange` invalidation has a render gap** — `[UUID: CGRect]` cached in `@State` and updated via `.onChange(of: LayoutKey(...))` worked for size changes and crop updates. But when `regenerateLayout()` created new panels with fresh UUIDs:
  1. `viewModel.panels` is updated (new UUIDs)
  2. SwiftUI re-renders the body
  3. `@State scaledPanelFrames` still holds old UUIDs
  4. `.onChange` fires and updates `scaledPanelFrames` with new UUIDs
  5. SwiftUI re-renders again (now in sync)

  Steps 2–3 is the gap: the first render after layout regeneration has stale frames. Tap hit-testing (`panelAt`), the selected panel outline, `PanelHitArea` rendering, and drag overlays all failed in this window.

- **Switching layout "fixed" it** — Because switching layout triggered another `regenerateLayout()` + `.onChange` cycle, which re-synced the cache. This made the bug intermittent and harder to diagnose.

## What Was Confusing

- **Why it was intermittent** — The gap only existed for the first render after `regenerateLayout()`. If the user didn't tap immediately, `.onChange` would fire and sync the cache before the next interaction. Switching layout always worked because it forced a second regeneration cycle.

- **`guard let x = await MainActor.run { }` doesn't compile** — During the `addImages` fix, attempted `guard let (nsImage, cgImage) = await MainActor.run { ... }` which produced a parse error. Swift requires the `await` result to be assigned to a variable first, then guarded:
  ```swift
  let result = await MainActor.run { ... }
  guard let (a, b) = result else { return nil }
  ```

## Key Learnings

### @State Cache Staleness with UUID-based Collections

When `@State` caches a dictionary keyed by UUIDs (e.g., `[UUID: CGRect]`), and the source collection can be regenerated with new UUIDs, the cache becomes stale for one render cycle. The `.onChange` that updates the cache fires *after* the first re-render.

**Affected code paths:**
- Hit-testing in gesture closures (tap, drag start)
- Visual overlays that depend on the cache (selected outline, drag source/target highlights)
- `ForEach` conditional rendering that guards on cache lookup

**Fix pattern:** Compute the frames on-the-fly in the `GeometryReader` closure:
```swift
GeometryReader { geometry in
    let panelFrames = viewModel.panels.reduce(into: [UUID: CGRect]()) { dict, panel in
        dict[panel.id] = canvasToPreviewFrame(panel.frame, in: geometry.size)
    }
    // Use panelFrames everywhere — always fresh
}
```

**When @State caching is still valid:** For collections whose UUIDs are stable (e.g., panels that persist across layout changes, or frames that only change during resize). The staleness gap only occurs when UUIDs are replaced.

### Performance trade-off

Computing `panelFrames` on every render adds O(n) work. For typical collage sizes (≤20 panels), this is negligible. For large collections, consider keeping the `@State` cache but also computing fresh frames in gesture handlers (the hybrid approach used in this fix — on-the-fly `panelAt` with cached `ForEach` rendering).

---
**Status:** Closed
**Follow-up:** None — fix applied and verified.
