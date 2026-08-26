# Undo Snapshot Patterns for Image Operations

**Date:** 2026-07-21
**Session:** 10 (undo/redo expansion Phase 2)
**Severity:** Informational — prevents incorrect assumptions during code review

## Shallow Copy Preserves Object References

When snapshotting objects that contain references to DOM elements (like `HTMLImageElement`), the spread operator `{ ...item }` copies property **values** (which are references), not the properties themselves.

### The Pattern

```javascript
// Snapshot BEFORE disposal
const removedItem = { ...this.images[index] };
// removedItem.image === this.images[index].image (same reference)

// Dispose the original
imageLibrary.disposeImage(index);
// this.images[index].image is now null, but item was spliced from array
// removedItem.image STILL references the original HTMLImageElement
```

### Why This Matters

`disposeImage(index)` sets `state.images[index].image = null` and then splices the item from the array. The snapshot `{ ...item }` was created BEFORE this, so its `image` property holds the original reference. After disposal, `removedItem.image` is still valid.

**This means undo CAN restore the image** because the snapshot preserved the reference. The "Cannot undo — image data no longer available" toast only shows when the image reference is externally invalidated (e.g., user navigates away from the page and the browser GC collects the element).

### Common Misconception

During world-review of this implementation, it was claimed that `{ ...item }` creates a shared reference such that `disposeImage` nulling the original also nulls the snapshot. This is **incorrect** — the spread copies the value of each property at the time of the spread. The `image` property value is a reference to an `HTMLImageElement`, and that reference is copied into the snapshot. Setting `original.image = null` only changes `original.image`, not the snapshot's copy of the reference.

### Testing the Pattern

To test the disposed-image toast scenario, you cannot rely on the normal disposal flow (because the snapshot preserves the reference). Instead, create a test image item with `image: null` from the start:

```javascript
const disposedItem = { id: 'img-x', image: null, filename: 'test.jpg', width: 100, height: 100 };
const vm = makeVm([disposedItem], []);
// Now removeImage will capture removedItem.image === null
```

## onUndoCommand Callback Pattern

Handler factories use callback injection to push undo commands without knowing about the UndoManager:

```javascript
// Handler factory accepts optional onUndoCommand
export function createImagePanelHandlers(getImageLibrary, ..., onUndoCommand) {
    return {
        removeImage(index) {
            const removedItem = { ...this.images[index] };
            // ... perform mutation ...
            if (onUndoCommand) {
                onUndoCommand(this, {
                    label: 'Remove Image',
                    undoFn: (vm) => { /* restore */ },
                    redoFn: (vm) => { /* re-mutate */ }
                });
            }
        }
    };
}

// Wiring layer provides the implementation
const imagePanelHandlers = createImagePanelHandlers(
    () => base.getImageLibrary(),
    // ...
    (vm, cmd) => pushUndoCommand(vm, cmd)
);
```

### Key Design Decisions

- **`onUndoCommand(vm, cmd)`** — receives both the Vue instance and the command object
- **`cmd.undoFn(vm)` / `cmd.redoFn(vm)`** — undo/redo functions receive the Vue instance as a parameter (not `this`), enabling the wiring layer to bind the correct context
- **Optional parameter** — handlers work without undo support (backward compatible)
- **Wiring layer wraps in try/catch** — errors in undo/redo are caught and shown as toasts

## Add Images Redo Limitation

The "Add Images" action cannot be fully redone because `File` objects are not serializable and are lost after the file input is reset. The redo function restores crops state but cannot re-add the images:

```javascript
redoFn: (vm) => {
    // Re-adding images is not possible (File objects are gone)
    // Restore to post-state crops
    if (vm.crops) {
        vm.crops.length = 0;
        vm.crops.push(...JSON.parse(JSON.stringify(postCrops)));
    }
    if (vm._regenerateAndRender) vm._regenerateAndRender();
}
```

This is an acceptable UX trade-off — the user can re-add images manually if needed.

## Crops Deep Copy Pattern

Crops arrays are deep-copied using `JSON.parse(JSON.stringify(crops))` for undo snapshots. This is safe because crops are plain objects with numeric properties (`x`, `y`, `w`, `h`) — no DOM references or complex types.

### Guard Against Null

Always guard against null crops: `JSON.parse(JSON.stringify(this.crops || []))`. Without the guard, `JSON.stringify(null)` returns `"null"` and `JSON.parse("null")` returns `null`, which breaks array operations.

## Related

- `2026-07-21-undo-closure-reference-bug.md` — closure reference bug in undo commands
- `app-undo-history-scope.md` — documents which actions create undo history (now outdated after Phase 2)
- `undomanager-batch-bug.md` — UndoManager batch composition bug
