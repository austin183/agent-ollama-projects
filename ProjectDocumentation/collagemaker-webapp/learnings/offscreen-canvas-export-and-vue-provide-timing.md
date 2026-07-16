# Offscreen Canvas Export and Vue provide() Timing

**Date:** 2026-07-02
**Session:** 12 (Phase 3 implementation)

## Summary

Two hard-won patterns from implementing high-resolution collage export and Vue dependency injection with lazy-initialized services.

---

## Offscreen Canvas Export Pattern

To export a collage at full 1080p resolution (1920x1080) without affecting the on-screen preview, use a detached (offscreen) canvas that is never appended to the DOM.

### Pattern

```javascript
export function exportToJpeg(assembler, state, quality) {
    return new Promise((resolve, reject) => {
        // 1. Create offscreen canvas (never appended to DOM)
        const canvas = document.createElement('canvas');
        canvas.width = 1920;
        canvas.height = 1080;

        // 2. Render at full resolution
        const ctx = canvas.getContext('2d');
        assembler.render(ctx, { ...state, canvasSize: { width: 1920, height: 1080 } });

        // 3. Generate blob and trigger download
        canvas.toBlob((blob) => {
            if (!blob) { reject('Failed'); return; }
            const url = URL.createObjectURL(blob);
            let a = null;
            try {
                a = document.createElement('a');
                a.href = url;
                a.download = 'collage.jpg';
                document.body.appendChild(a);
                a.click();
            } finally {
                if (a && document.body.contains(a)) {
                    document.body.removeChild(a);
                }
                URL.revokeObjectURL(url); // ← Critical: prevents memory leak
            }
            resolve('success');
        }, 'image/jpeg', quality);
    });
}
```

### Critical: try/finally for Object URL Cleanup

If `a.click()` throws (e.g., popup blocker), cleanup code after it never runs. The `URL.createObjectURL()` blob remains in memory indefinitely — a **memory leak**. Always wrap the download trigger in `try/finally`:

```javascript
// WRONG: click() failure skips cleanup
const url = URL.createObjectURL(blob);
const a = document.createElement('a');
a.href = url;
document.body.appendChild(a);
a.click(); // ← If this throws, cleanup never runs
document.body.removeChild(a);
URL.revokeObjectURL(url);

// CORRECT: try/finally guarantees cleanup
const url = URL.createObjectURL(blob);
let a = null;
try {
    a = document.createElement('a');
    a.href = url;
    a.download = 'collage.jpg';
    document.body.appendChild(a);
    a.click();
} finally {
    if (a && document.body.contains(a)) {
        document.body.removeChild(a);
    }
    URL.revokeObjectURL(url);
}
```

### Offscreen Canvas Is Auto-Collected

The offscreen canvas is created as a local variable and has no DOM attachment. After the `toBlob` callback completes, the canvas is eligible for garbage collection. No explicit cleanup needed.

---

## Vue provide() Timing Gotcha

`provide()` is called during Vue component initialization, **before** `mounted()`. Any services initialized in `mounted()` (like managers that need the reactive Vue instance) will be `null` when accessed via `provide()`.

```javascript
// WRONG: managers are null at provide() time
provide() {
    return {
        backgroundManager: base.getBackgroundManager(), // null!
        titleManager: base.getTitleManager()             // null!
    };
}
```

### Fix: Don't Provide Lazy-Initialized Services

If a service is initialized in `mounted()`, don't provide it via `provide()`. Components that need it can access it directly via `this.managerName` on the Vue instance (since the manager is set as a property on `this` during `mounted()`).

```javascript
// CORRECT: only provide services available at init time
provide() {
    return {
        componentRegistry: base.componentRegistry, // Available immediately
        assembler: base.assembler                   // Available immediately
    };
    // backgroundManager and titleManager are set on `this` in mounted()
    // Access via this.backgroundManager, not inject()
}
```

### Alternative: Provide Getter Functions

If child components absolutely need `inject()`, provide getter functions instead:

```javascript
provide() {
    return {
        getBackgroundManager: () => base.getBackgroundManager(),
        getTitleManager: () => base.getTitleManager()
    };
}
// Child component calls inject('getBackgroundManager')() after mounted
```

---

## @mousedown.prevent for Text Selection Preservation

When formatting buttons (B/I/U) interact with a text input's selection state, clicking a button causes the input to lose focus, which clears the selection. This makes it impossible to apply formatting to selected text.

```html
<!-- WRONG: button click steals focus, clearing selection -->
<button @click="toggleTitleBold">B</button>

<!-- CORRECT: @mousedown.prevent keeps focus on the input -->
<button @mousedown.prevent @click="toggleTitleBold">B</button>
```

The `@mousedown.prevent` stops the button from receiving focus on mousedown, allowing the text input to retain focus and its selection range. The `@click` handler still fires normally.

This pattern applies to any toolbar button that operates on a text input's current selection (bold, italic, underline, strikethrough, color pickers, etc.).

---

## File Reference

- `MyESModules/Export/ExportManager.js` — Offscreen canvas export
- `MyESModules/App/createCollageServices.js` — provide() timing fix
- `index.html` — @mousedown.prevent on format buttons
