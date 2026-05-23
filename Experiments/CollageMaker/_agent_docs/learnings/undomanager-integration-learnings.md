# UndoManager Integration — Learnings 2026-05-19

**Purpose:** Document learnings from implementing Phase 1 of the HIG Review plan — full undo/redo support across 11 properties and 5 mutating methods.

---

## What Worked

### `didSet` undo registration for @Observable properties

The `didSet` pattern for registering undo on every property change worked cleanly across all 11 configurable properties. The ordering within `didSet` matters:

```swift
var gutter: CGFloat = 0 {
    didSet {
        // 1. Register undo first (captures oldValue)
        undoManager.registerUndo(withTarget: self) { target in
            target.gutter = oldValue
        }
        undoManager.setActionName("Change Gutter")
        // 2. Persist second
        UserDefaults.standard.set(Double(gutter), forKey: "gutter")
        // 3. Side effects last
        regenerateLayout()
    }
}
```

This ordering ensures undo restores the old value, which then triggers `didSet` again — re-persisting the old value and re-running side effects. This is the correct behavior: undo should fully reverse the action, including persistence.

### Collection mutation undo patterns

Three distinct patterns emerged for undoing array mutations:

**Remove → Insert:**
```swift
func removeImage(at index: Int) {
    let removed = images[index]
    undoManager.registerUndo(withTarget: self) { target in
        target.images.insert(removed, at: index)
        target.regenerateLayout()
    }
    images.remove(at: index)
}
```

**Move → Restore permutation:**
```swift
func moveImages(from: IndexSet, to: Int) {
    let oldCustomOrder = customImageOrder
    // ... perform move ...
    undoManager.registerUndo(withTarget: self) { target in
        target.customImageOrder = oldCustomOrder
        target.regenerateLayout()
    }
}
```

**Clear all → Full state restore:**
```swift
func clearAll() {
    guard !images.isEmpty else { return }
    let oldImages = images, oldPanels = panels, oldCropMap = cropMap, oldCustomOrder = customImageOrder
    undoManager.registerUndo(withTarget: self) { target in
        target.images = oldImages
        target.panels = oldPanels
        target.cropMap = oldCropMap
        target.customImageOrder = oldCustomOrder
        target.regenerateLayout()
    }
}
```

The key insight: for complex mutations (move, swap, clear), capturing the pre-mutation state of the permutation array (`customImageOrder`) is simpler and more reliable than trying to reverse the individual operations.

### Guard for non-undoable state

`resetCrop` correctly returns early when there's no prior crop to restore:

```swift
func resetCrop(panelId: UUID) {
    guard let oldCrop = cropMap[panelId] else { return }
    // ... register undo ...
}
```

This prevents registering a no-op undo action when the panel was never cropped.

---

## What Didn't Work / Gaps

### `NSUndoManager` type name is stale

The skill reference `hig-undo-redo.md` uses `NSUndoManager()` in its code examples. On SDK 26.5 (and Swift 3+), this produces a compiler error: `'NSUndoManager' has been renamed to 'UndoManager'`. The correct instantiation is:

```swift
private let undoManager = UndoManager()
```

### `NSSavePanel.isEntireDirectoryVisible` removed

The plan specified `savePanel.isEntireDirectoryVisible = true` to accompany `savePanel.directoryURL`. This property no longer exists on SDK 26.5. It's not needed — setting `directoryURL` alone is sufficient to pre-populate the save panel's location.

### No undo for `addImages`

The plan didn't include undo for adding images (`addImages(from:)`). This is a deliberate gap — adding images is a high-frequency, low-cost operation during setup, and undoing additions would require tracking the full `ImageItem` (including `CGImage`) in the undo stack, which is memory-intensive. If needed later, a "Remove All Added" batch action would be more practical than per-image undo.

### Test target build failures

The test target has pre-existing build failures in `CollageAssemblerTests.swift` where the mock protocol uses `title: String` instead of `titleAttrString: NSAttributedString`. This blocks running the full test suite, including the `CollageViewModelTests` that would exercise the new undo code. The mock protocol needs to be updated to match the current assembler interface.

---

## Skill Improvements

### `hig-undo-redo.md` reference

The existing reference needs two updates:

1. **Type name:** Replace all `NSUndoManager` with `UndoManager` throughout the file
2. **Collection mutation patterns:** Add the three patterns documented above (remove→insert, move→restore permutation, clear→full state restore) as a new section. The current file only shows simple property assignment undo and a single `insert` example

### `hig-undo-redo.md` — `didSet` ordering note

Add a note that when `didSet` contains undo registration + persistence + side effects, the order should be: **undo registration → persist → side effects**. This ensures undo fully reverses the action, including re-persisting the old value.

---

## Next Steps

- Update `hig-undo-redo.md` with corrected type name and collection mutation patterns
- Fix `CollageAssemblerTests.swift` mock protocol to use `titleAttrString: NSAttributedString` so the test suite can run again
- Phase 2 (Settings & Commands) will exercise the undo system through the UI

---
**Status:** Closed
**Follow-up:** Phase 2 of HIG Review plan; test target mock fix
