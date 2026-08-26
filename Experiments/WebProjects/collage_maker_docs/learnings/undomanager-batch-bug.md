# UndoManager Batch Undo/Redo Bug

**Date:** 2026-07-02
**Session:** 6 (P0 test follow-up)
**Severity:** Critical — blocks Phase 3

## Problem

The `beginBatch` / `endBatch` implementation in `MyESModules/State/UndoManager.js` is fundamentally broken in two ways:

### Bug 1: Snapshot Return vs Apply

`endBatch` creates undo/redo functions that **return** a snapshot instead of **applying** it:

```javascript
// BROKEN: endBatch creates functions that return snapshots
undoStack.push({
    label: label,
    undo: () => preSnapshot,   // Returns snapshot, doesn't apply it
    redo: () => postSnapshot   // Returns snapshot, doesn't apply it
});
```

But `undo()` and `redo()` call these functions and discard the return value:

```javascript
undo() {
    const command = undoStack.pop();
    command.undo();  // Return value is discarded!
    redoStack.push(command);
    return true;
}
```

**Result:** Batch undo/redo has zero effect on state.

### Bug 2: Batch Composition Overwrites

In `push()`, when a batch is active, it replaces `batchCommand.undo` with only the **latest** command's undo function:

```javascript
push(command) {
    if (isBatching) {
        if (batchCommand) {
            batchCommand.undo = command.undo;  // Only keeps the LAST undo
        }
        return;
    }
    // ...
}
```

**Result:** A batch only undoes the very last operation, not the entire group.

## Evidence

`UndoManagerTest.html` tests 3.1.11, 3.1.12, and 3.1.13 assert that state remains unchanged after a batch undo — effectively documenting the bug as intended behavior.

## Fix

### For Bug 1: Make undo/redo functions apply the snapshot

```javascript
// FIXED: endBatch creates functions that apply snapshots
undoStack.push({
    label: label,
    undo: () => { /* apply preSnapshot to state */ },
    redo: () => { /* apply postSnapshot to state */ }
});
```

The undo/redo functions must mutate the state object directly (e.g., `Object.assign(state, snapshot)` or set specific properties).

### For Bug 2: Accumulate all operations in batch

The batch should capture the pre-batch state once and the post-batch state once, not try to compose individual undo functions.

## Impact

Any feature that relies on batched undo (crop drag sessions, multi-image operations) will silently fail to restore state on undo/redo. This is a blocker for Phase 3.

## Fix Applied

**Fixed in commit `46da243` (2026-07-02).**

The fix replaced the snapshot-return approach with command accumulation:

```javascript
// beginBatch: just track label and accumulate commands
beginBatch(label) {
    isBatching = true;
    batchLabel = label;
    batchCommands = [];
}

// push during batch: accumulate
push(command) {
    if (isBatching) {
        batchCommands.push(command);
        return;
    }
    // ... normal push
}

// endBatch: compose combined undo/redo from accumulated commands
endBatch() {
    if (batchCommands.length > 0) {
        const commands = [...batchCommands];
        undoStack.push({
            label: batchLabel,
            undo: () => {
                for (let i = commands.length - 1; i >= 0; i--) {
                    commands[i].undo();  // reverse order
                }
            },
            redo: () => {
                for (const cmd of commands) {
                    cmd.redo();  // forward order
                }
            }
        });
    }
}
```

Key design decision: **executors (undo/redo functions) are closures over the accumulated commands**, not snapshot applicators. This matches how the rest of the UndoManager works — every command's undo/redo is a function that mutates state directly.

Tests 3.1.11-3.1.13 were rewritten to assert correct behavior. Two additional edge case tests were added (empty batch, batch clearing redo stack).

## Status

**Resolved.** All 22 UndoManager tests pass.
