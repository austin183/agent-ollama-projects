# Vue v-model Timing and Undo Snapshot Patterns

**Date:** 2026-07-21
**Session:** 12 (undo/redo expansion Phase 3)
**Severity:** Critical — prevents silent no-op undo commands

## The Problem

In Vue 3, `v-model` updates the reactive data **before** `@change` (for select) or `@input` (for range/text) fires. This means by the time your change handler runs, `this.someValue` is already the NEW value — you cannot capture the pre-change state inside the handler.

```javascript
// THIS DOES NOT WORK for undo snapshots:
// v-model updates data, THEN @change fires
<select v-model="layoutStyle" @change="onChange">
onChange() {
    const pre = this.layoutStyle;  // Already the NEW value!
    this.layoutStyle = 'hex';      // pre === 'hex', not the old value
    // Cannot create a meaningful undo command
}
```

## The Solution: Pre-Change Snapshot Events

Capture the pre-state on an event that fires BEFORE v-model updates:

### For `<select>` elements: Use `@focus`
```html
<select v-model="layoutStyle" @focus="snapshotLayoutStyle" @change="onLayoutStyleChange">
```
```javascript
// Captures pre-state when user opens the dropdown
snapshotLayoutStyle() {
    layoutStyleSnapshot = this.layoutStyle;  // Old value
}

// Compares snapshot to current value (which is now the new value)
onLayoutStyleChange() {
    if (layoutStyleSnapshot !== null && this.layoutStyle !== layoutStyleSnapshot) {
        // Push undo command with layoutStyleSnapshot as pre-state
    }
}
```

### For `<input type="range">` elements: Use `@focus` + `@pointerdown`
```html
<input type="range" v-model.number="gutter"
       @focus="snapshotLayoutOptions"
       @pointerdown="snapshotLayoutOptions"
       @input="onGutterChange"
       @blur="commitLayoutOptions">
```

**Why both `@focus` AND `@pointerdown`?**
- `@focus` — captures snapshot when user tabs to the slider (keyboard navigation)
- `@pointerdown` — captures snapshot when user clicks/touches the slider (mouse/touch)
- `@mousedown` alone is insufficient — it does NOT fire on touch devices for form elements

### Why `@pointerdown` instead of `@mousedown`?

`@mousedown` does not fire on touch devices (iOS/Android) for form elements like range inputs. The browser fires `touchstart` instead. `@pointerdown` is the modern, cross-platform standard that unifies mouse, touch, and pen input.

## Batching Pattern for Sliders

Range inputs fire `@input` continuously during drag. To batch multiple slider changes into a single undo command:

1. **Snapshot on interaction start**: `@focus` or `@pointerdown` captures pre-state
2. **Update on every input**: `@input` handler updates the layout manager and renders
3. **Commit on interaction end**: `@blur` pushes the batched undo command

```javascript
let layoutOptionsSnapshot = null;

snapshotLayoutOptions() {
    if (!layoutOptionsSnapshot) {
        layoutOptionsSnapshot = {
            gutter: this.gutter,
            sliceAngle: this.sliceAngle,
            hexSpacing: this.hexSpacing,
            hexSizeMultiplier: this.hexSizeMultiplier
        };
    }
}

commitLayoutOptions() {
    if (layoutOptionsSnapshot) {
        const preState = { ...layoutOptionsSnapshot };
        const postState = { /* current values */ };
        // Push undo command if anything changed
        layoutOptionsSnapshot = null;  // Reset for next interaction
    }
}
```

## Testing the Pattern

In unit tests, simulate the Vue event order:

```javascript
// Test: snapshot first (simulates @focus/@pointerdown), then change value, then call handler
handlers.snapshotLayoutStyle.call(vm);
vm.layoutStyle = 'hex';  // v-model updates
handlers.onLayoutStyleChange.call(vm);  // @change fires
```

## Related

- `2026-07-18-phase2-ux-accessibility.md` — mentions @input fires after model update (for Enter key prevention)
- `2026-07-14-renderer-positioning-migration-and-vue-range-gotchas.md` — v-model.number coercion on range inputs
- `2026-07-21-undo-snapshot-patterns-image-operations.md` — undo snapshot patterns for image operations
- `building-web-apps/references/vue-options-api.md` — Vue 3 Options API patterns
