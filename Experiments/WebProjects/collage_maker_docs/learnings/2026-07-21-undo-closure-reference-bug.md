# Undo Command Closure Reference Bug

**Date:** 2026-07-21
**Session:** 9 (undo/redo expansion Phase 1)
**Severity:** Critical — silent crash on undo

## Problem

When building undo/redo commands as closures over a mutable outer variable, the closure captures the variable **by reference**, not by value. If the outer variable is later reassigned (e.g., set to `null`), the closure sees the new value when it executes — not the value at closure creation time.

### The Bug Pattern

```javascript
let titleUndoSnapshot = null;

// onInteractionStart captures snapshot
titleUndoSnapshot = {
    titleBoxX: this.titleStyle.titleBoxX,
    titleBoxY: this.titleStyle.titleBoxY,
    titleBoxWidth: this.titleStyle.titleBoxWidth
};

// onInteractionEnd builds undo command
this.undoManager.push({
    label: 'Move/Resize Title',
    undo: () => {
        // BUG: titleUndoSnapshot is captured by reference.
        // By the time undo executes, titleUndoSnapshot is null (see below).
        this.titleStyle.titleBoxX = titleUndoSnapshot.titleBoxX;
        // → TypeError: Cannot read properties of null
    },
    redo: () => { /* ... */ }
});

// This nulls the variable AFTER closures capture it
titleUndoSnapshot = null;
```

### Why It Fails

JavaScript closures capture variables from their enclosing scope by reference. The `undo` function doesn't store a copy of `titleUndoSnapshot` — it holds a reference to the variable. When `titleUndoSnapshot = null` executes, the closure's reference now points to `null`.

### The Fix

Copy the snapshot values into a **local constant** before building the closure:

```javascript
const preState = {
    titleBoxX: titleUndoSnapshot.titleBoxX,
    titleBoxY: titleUndoSnapshot.titleBoxY,
    titleBoxWidth: titleUndoSnapshot.titleBoxWidth
};

this.undoManager.push({
    label: 'Move/Resize Title',
    undo: () => {
        // preState is a const — its values are captured at closure creation time
        this.titleStyle.titleBoxX = preState.titleBoxX;
        this.titleStyle.titleBoxY = preState.titleBoxY;
        this.titleStyle.titleBoxWidth = preState.titleBoxWidth;
    },
    redo: () => { /* ... */ }
});

titleUndoSnapshot = null; // No longer affects the closure
```

### Existing Safe Pattern (Crop Drag)

The crop drag undo in the same file (`createCollageLifecycle.js:164`) already uses the correct pattern:

```javascript
const preState = { ...cropUndoSnapshot };  // Local copy
// ... build closures over preState ...
cropUndoSnapshot = null;                    // Safe — closures don't see this
```

### When This Bug Appears

This pattern is common in interaction handlers that:
1. Capture a pre-state snapshot at interaction start
2. Build an undo command at interaction end
3. Null the snapshot variable after building the command

Any code that builds closures over a mutable outer variable and later reassigns that variable is vulnerable.

### Detection

- **Code review**: Look for closures that reference outer variables later reassigned to `null` or a different value
- **Runtime**: `TypeError: Cannot read properties of null` when the undo function executes
- **Test**: Write a test that simulates the full lifecycle: capture → build closure → null variable → execute closure

### Related

- `undomanager-batch-bug.md` — different UndoManager bug (batch composition)
- `app-undo-history-scope.md` — documents which actions create undo history
