# Atomic Undo Methods: Extracting Inline Template Expressions

**Date:** 2026-07-22
**Session:** 15 (undo/redo review follow-ups Phase 2)
**Severity:** Suggestion — inline expressions work but hinder testability

## The Problem: Inline Snapshot/Commit Is Hard to Test

The inline snapshot/commit pattern for segmented controls and checkboxes works correctly:

```html
<button @click="snapshotTitleStyle(); titleStyle.alignment = 'left'; onTitleAlignmentChange(); commitTitleStyle()">
    Left
</button>
```

However, this pattern makes the undo lifecycle difficult to test. To test it, you must simulate the exact Vue event sequence (snapshot → mutate → handler → commit) which couples tests to template implementation details.

## The Solution: Atomic Handler Methods

Extract the inline expression into a dedicated handler method:

```html
<button @click="setTitleAlignment('left')">Left</button>
```

```javascript
setTitleAlignment(alignment) {
    const preState = this.titleStyle.alignment;
    this.titleStyle.alignment = alignment;
    const titleManager = getTitleManager();
    if (titleManager) titleManager.setAlignment(alignment);
    onRenderScheduled(this);
    if (onUndoCommand && preState !== alignment) {
        const postState = this.titleStyle.alignment;
        onUndoCommand(this, {
            label: 'Change Title Style',
            undoFn: (v) => { /* ... */ },
            redoFn: (v) => { /* ... */ }
        });
    }
}
```

**Benefits:**
1. **Testability** — Call `handlers.setTitleAlignment.call(vm, 'left')` directly. No need to simulate Vue event ordering.
2. **API contract** — Method signature documents the interface. Consumer story is clear.
3. **Template clarity** — Single method call vs. multi-statement expression.
4. **IDE support** — Refactoring, navigation, and autocomplete work on method names.

## Design Rules for Atomic Methods

### Setters: Guard Against No-Op
Methods that SET a specific value should skip undo when value is unchanged:

```javascript
// setTitleAlignment — no-op guard
if (onUndoCommand && preState !== alignment) {
    onUndoCommand(this, { /* ... */ });
}
```

**Why?** Clicking "Center" when alignment is already "center" should not produce an undo command. This keeps the undo history clean.

### Toggles: Always Push Undo
Methods that TOGGLE a value should always push:

```javascript
// toggleTitleShowBackground — no guard needed
this.titleStyle.showBackground = !preState;
// ...
if (onUndoCommand) {
    onUndoCommand(this, { /* ... */ });
}
```

**Why?** A toggle always changes the value (false→true or true→false), so an undo command is always meaningful.

### Removals: Early Return Guard
Methods that REMOVE something should return early if there's nothing to remove:

```javascript
// removeBackgroundImageAtomic — early return
if (!preState.backgroundImage) {
    return;
}
```

**Why?** Prevents unnecessary state mutations and undo commands. The template typically guards with `v-if="backgroundImage"`, but the method-level guard provides defense-in-depth for programmatic calls.

## Refactoring Progression

This is a natural evolution of the undo snapshot pattern:

| Stage | Pattern | Testability |
|-------|---------|-------------|
| 1. Discovery | Inline snapshot/commit in template | Hard (simulate Vue events) |
| 2. Extraction | Atomic handler method | Easy (call method directly) |

**When to extract:** When you have 3+ inline expressions performing the same snapshot/mutate/commit cycle, or when you need to test the undo lifecycle in isolation.

## Testing Atomic Methods

```javascript
it('setTitleAlignment pushes undo command when value changes', () => {
    const handlers = createTitleHandlers(
        () => mockTitleManager,
        () => {},
        (vmRef, cmd) => undoCommands.push(cmd)
    );

    // Direct method call — no Vue event simulation needed
    handlers.setTitleAlignment.call(vm, 'left');

    expect(undoCommands.length).to.equal(1);
    expect(vm.titleStyle.alignment).to.equal('left');
});

it('setTitleAlignment no-op when value unchanged', () => {
    handlers.setTitleAlignment.call(vm, 'center'); // Already center
    expect(undoCommands.length).to.equal(0);
});
```

## Related

- `2026-07-21-undo-batching-segmented-controls.md` — Inline snapshot/commit pattern (Stage 1)
- `2026-07-21-vue-vmodel-timing-undo-snapshots.md` — v-model timing and pre-change snapshots
- `building-web-apps/references/undo-snapshots.md` — Undo snapshot patterns reference
