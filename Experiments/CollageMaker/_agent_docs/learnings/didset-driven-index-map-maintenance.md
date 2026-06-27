# didSet-Driven Index Map Maintenance

**Date:** 2026-06-27
**Session:** 139
**Purpose:** Pattern for keeping derived lookup dictionaries in sync with a source array, regardless of how the array is modified (direct assignment in tests, regeneration methods, etc.).

---

## The Problem

When you add cached lookup dictionaries (e.g., `[UUID: Element]`) alongside an array (`[Element]`), you need to keep them in sync. If consumers can modify the array directly (as tests do with `layoutManager.panels = panels`), manual cache updates become error-prone — easy to forget in one code path.

## The Pattern

```swift
@Observable
final class LayoutManager {
    var panels: [ImagePanel] = [] {
        didSet { rebuildIndexMaps() }
    }
    private(set) var panelById: [UUID: ImagePanel] = [:]
    private(set) var panelSlotById: [UUID: Int] = [:]

    private func rebuildIndexMaps() {
        panelById.removeAll(keepingCapacity: true)
        panelSlotById.removeAll(keepingCapacity: true)
        for (index, panel) in panels.enumerated() {
            panelById[panel.id] = panel
            panelSlotById[panel.id] = index
        }
    }
}
```

## Why It Works

- **`didSet` fires on any array modification**: assignment (`panels = ...`), `removeAll()`, subscript mutation (`panels[0] = ...`) — all trigger the observer because `ImagePanel` is a struct.
- **Single source of truth for cache invalidation**: no code path can modify `panels` without rebuilding the maps.
- **Tests bypassing production flow still work**: direct `layoutManager.panels = panels` in tests correctly populates dictionaries.

## Gotchas

- Use `private(set)` on the dictionaries so external code reads but never writes them directly.
- `removingAll(keepingCapacity: true)` preserves backing storage for repeated rebuilds (minor perf win when rebuilding frequently).
- If elements are reference types, subscript mutation won't trigger didSet — only full array reassignment will. In that case, wrap mutations in explicit cache invalidation calls.
