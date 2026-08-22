# Slot-Index State Preservation — Learnings

**Date:** 2026-05-31
**Purpose:** Document learnings from preserving user crop adjustments and rendered images across panel UUID regeneration (Round 20).

## What Worked

### Slot-index extraction and reapplication

When a collection is regenerated with new identity values (UUIDs) but preserved positional semantics (slot index corresponds to the same image via `customImageOrder`), state keyed by identity can be preserved in three steps:

1. **Extract before regeneration** — Convert `[UUID: Value]` to `[Value]` by slot index
2. **Regenerate collection** — New UUIDs, same slot count
3. **Reapply by slot index** — Convert `[Value]` back to `[UUID: Value]` using new UUIDs

```swift
// Extract
let cropsBySlot = cropManager.cropsBySlot(panels)       // [CGRect]
let imagesBySlot = previewManager.panelRenderedImagesBySlot(panels)  // [NSImage?]

// Regenerate
panels = LayoutGenerator.generate(...)  // new UUIDs

// Reapply
cropManager.applyCropsBySlot(cropsBySlot, panels: panels)
previewManager.applyRenderedBySlot(imagesBySlot, panels: panels)
```

This avoids the alternative of trying to map old UUIDs to new UUIDs, which requires maintaining a separate old-to-new mapping. Slot index is the natural bridge when positional semantics are stable.

### Conditional state clearing

The `panelRenderedImages.removeAll()` that was unconditionally called in `regenerateLayout()` needed to become conditional:
- **Preserve path** (gutter change, same panel count): remap images to new UUIDs
- **Non-preserve path** (layout style change, image count change): clear and recompute

A single-line change (`removeAll()` removal) in the preserve path accidentally removed clearing for all callers, creating a memory leak of orphaned `NSImage` entries. The fix was to gate `removeAll()` in the non-preserve branch.

## What Didn't Work / Gaps

### Memory leak from blanket removal

Initial fix removed `panelRenderedImages.removeAll()` to fix the blank canvas during gutter drag. But `regenerateLayout()` is also called by layout style change, image add/remove, and undo handlers — all with `preserveCrops: false`. Without `removeAll()` in those paths, old `NSImage` entries keyed by old UUIDs accumulated indefinitely. **Fix:** `removeAll()` in the non-preserve branch only.

### Trivial test with debounced operations

`gutterChangeRegeneratesLayout` captured `panelsNoGutter` immediately after `vm.gutter = 0`, but `regenerateLayout` is now debounced (150ms). So `vm.panels` was still `[]`. The assertion `[] != [non-empty]` passed trivially. **Fix:** Await debounce before each capture.

### Preserving `sourceRect` only, not `destinationRect`

The crop's `sourceRect` (which portion of source image is visible) is the user's adjustment. The `destinationRect` (panel frame on canvas) is computed by layout. Preserving only `sourceRect` and recomputing `destinationRect` from new panel frames is correct — preserving `destinationRect` would draw the image at old panel coordinates.

## What Was Confusing

### When to preserve vs. recompute

Not all layout changes should preserve crops:
- **Gutter change** — Same panels, different frames. Preserve crops (user adjustments are still valid, just at different panel sizes).
- **Layout style change** — Different panel count, different structure. Recompute crops (old slot positions may not exist).
- **Image count change** — Different panels entirely. Recompute crops.

The `preserveCrops: Bool` parameter makes this explicit at the call site.

## Key Patterns

### Defer undo registration to debounce commit

For a continuous control (slider, color picker) that debounces its side effects, undo registration and persistence should happen in the debounced callback, not in `didSet`. Otherwise each slider tick (~30-60/sec) creates a spurious undo entry:

```swift
var gutter: CGFloat = 0 {
    didSet {
        guard !isInitializing else { return }
        gutterDidChange(oldValue: oldValue)  // no undo here
    }
}

private func gutterDidChange(oldValue: CGFloat) {
    gutterDebounceTask?.cancel()
    gutterDebounceTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard let self else { return }
        // Undo + persist only on final commit
        undoManager.registerUndo(withTarget: self) { $0.gutter = oldValue }
        undoManager.setActionName("Change Gutter")
        debouncedSave()
        regenerateLayout(preserveCrops: true)
    }
}
```

## Skill Improvements

### `building-macos-apps/SKILL.md` — State Management

Add to @Observable debugging section:
- **Slot-index preservation across identity changes** — When a collection is regenerated with new identity values (e.g., panel UUIDs on layout change) but preserved positional semantics, extract state by slot index before regeneration and reapply after. Avoids UUID mapping complexity.

### `building-macos-apps/SKILL.md` — HIG: Undo and Redo

Add:
- **Defer undo registration for debounced properties** — For continuous controls with debounced side effects, register undo in the debounced callback, not in `didSet`. Each slider tick would otherwise create a spurious undo entry.

## Next Steps

- Consider generalizing slot-index preservation as a reusable helper for other collection-regeneration scenarios

---
**Status:** Closed
**Follow-up:** None
