# Undo Batching: Segmented Controls and Lifecycle Cleanup

**Date:** 2026-07-21
**Session:** 13 (undo/redo expansion Phase 4)
**Severity:** Warning — missing undo commands for common UI interactions

## The Problem: Segmented Controls Lack Natural Blur Events

The undo batching pattern relies on `@focus` (snapshot), `@input`/`@change` (update), and `@blur` (commit). This works for form inputs (range, select, color, textarea) because they naturally receive focus and blur events.

**Segmented control buttons and checkboxes do NOT follow this pattern.** A segmented control is a group of `<button>` elements:

```html
<div class="segmented-control">
    <button @click="titleStyle.alignment = 'left'; onTitleAlignmentChange()">Left</button>
    <button @click="titleStyle.alignment = 'center'; onTitleAlignmentChange()">Center</button>
    <button @click="titleStyle.alignment = 'right'; onTitleAlignmentChange()">Right</button>
</div>
```

Buttons fire `@click`, not `@focus`/`@blur`. The `@blur` handler on a parent element fires when the user clicks elsewhere, but by that time the user may have already clicked multiple buttons, and the blur would commit all changes as one batch — or worse, never commit if the user navigates to a different section.

## The Solution: Inline Snapshot/Commit

For buttons and checkboxes, capture the snapshot and commit the undo command inline in the `@click`/`@change` handler:

```html
<!-- Segmented control button -->
<button @click="snapshotTitleStyle(); titleStyle.alignment = 'left'; onTitleAlignmentChange(); commitTitleStyle()">
    Left
</button>

<!-- Checkbox -->
<input type="checkbox" v-model="titleStyle.showBackground"
       @change="snapshotTitleStyle(); onTitleShowBackgroundChange(); commitTitleStyle()">
```

**Why inline?** Each button click is a discrete, atomic action. The user expects each click to be individually undoable. There's no "interaction session" to batch — the click IS the interaction.

## Element-by-Element Pattern Reference

| Element | Snapshot | Update | Commit |
|---------|----------|--------|--------|
| `<select>` | `@focus` | `@change` | — (immediate) |
| `<input type="range">` | `@focus` + `@pointerdown` | `@input` | `@blur` |
| `<input type="color">` | `@focus` | `@input` | `@blur` |
| `<textarea>` | `@focus` | `@input` | `@blur` |
| `<button>` (segmented) | Inline `@click` | Inline `@click` | Inline `@click` |
| `<input type="checkbox">` | Inline `@change` | Inline `@change` | Inline `@change` |

**Key insight:** If the element doesn't have a natural blur event, use inline snapshot/commit.

## Lifecycle Cleanup: Commit Pending Snapshots on Unmount

When a user navigates away from the page (or the Vue app is destroyed), any pending undo snapshots are lost. This means the last edit before navigation won't be undoable.

**Fix:** Commit all pending snapshots in `beforeUnmount`:

```javascript
beforeUnmount() {
    // Commit any pending undo snapshots before destruction
    if (this.commitTitleText) this.commitTitleText();
    if (this.commitTitleStyle) this.commitTitleStyle();
    if (this.commitBackground) this.commitBackground();
    if (this.commitOverlay) this.commitOverlay();
    if (this.commitLayoutOptions) this.commitLayoutOptions();

    // ... rest of cleanup
}
```

**Why guard with `if (this.method)`?** The commit methods may not exist if the corresponding handler factory wasn't wired with an `onUndoCommand` callback. The guard prevents errors.

**Note:** This is a "best effort" cleanup. If the user navigates to a different page entirely (SPA route change or full page reload), the undo stack is ephemeral and will be lost regardless. This only helps within the same Vue instance lifecycle (e.g., component remount).

## Testing

Test segmented control undo by simulating the inline pattern:

```javascript
it('Alignment change pushes undo command', () => {
    const handlers = createTitleHandlers(
        () => mockTitleManager,
        () => {},
        (vmRef, cmd) => undoCommands.push(cmd)
    );

    // Simulate inline: snapshot -> change -> handler -> commit
    handlers.snapshotTitleStyle.call(vm);
    vm.titleStyle.alignment = 'left';
    handlers.onTitleAlignmentChange.call(vm);
    handlers.commitTitleStyle.call(vm);

    expect(undoCommands.length).to.equal(1);
});
```

## Related

- `2026-07-21-vue-vmodel-timing-undo-snapshots.md` — v-model timing and pre-change snapshot patterns
- `building-web-apps/references/undo-snapshots.md` — undo snapshot patterns reference
- `building-web-apps/references/vue-options-api.md` — Vue 3 Options API patterns
