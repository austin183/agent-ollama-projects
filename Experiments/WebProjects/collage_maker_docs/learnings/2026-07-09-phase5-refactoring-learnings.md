# Phase 5 Refactoring Learnings

**Date:** 2026-07-09
**Context:** Phase 5 of Change Requests Implementation Plan — architectural refactoring for DIP compliance and testability.

## 1. Callback Injection Pattern for Vue Handler DIP

When refactoring Vue handler modules to achieve DIP compliance (replacing `this._scheduleRender()` calls with injected callbacks), the pattern that works cleanly is:

**Handler factory accepts callback that receives Vue instance:**
```javascript
export function createLayoutHandlers(getLayoutManager, onRenderScheduled) {
    return {
        onLayoutStyleChange() {
            const lm = getLayoutManager();
            if (lm) lm.setLayoutStyle(this.layoutStyle);
            onRenderScheduled(this); // Pass Vue instance to callback
        }
    };
}
```

**Factory wiring builds internal functions first, then handlers:**
```javascript
export function createCollageMethods(base) {
    // Internal function that accepts vm parameter
    function _scheduleRender(vm) {
        const renderer = base.getCanvasRenderer();
        // ... render logic using vm.state
    }

    // Handler receives callback that wraps internal function
    const layoutHandlers = createLayoutHandlers(
        () => base.getLayoutManager(),
        (vm) => _scheduleRender(vm)
    );

    // Vue method wraps internal function
    return {
        _scheduleRender() { _scheduleRender(this); },
        onLayoutStyleChange() { layoutHandlers.onLayoutStyleChange.call(this); }
    };
}
```

**Why this works:**
- Internal functions are pure closures over `base` (services) and accept `vm` (Vue state)
- No `this` dependency in internal functions — they use explicit `vm` parameter
- Callbacks are created at factory time, capturing the internal function reference
- Handlers are fully testable with mock callbacks — no Vue instance needed

**Why NOT to use `() => this._scheduleRender()` as callback:**
- At factory creation time, `this` is not the Vue instance
- The callback would be a closure over an undefined `this`
- The callback must accept `vm` and pass it through

## 2. DOM ID Injection as Factory Configuration

Hardcoded `document.getElementById('previewCanvas')` calls in factory functions prevent testability and multi-instance scenarios. The fix is to accept DOM IDs as factory configuration:

```javascript
const DEFAULT_DOM_IDS = {
    previewCanvas: 'previewCanvas',
    cropPreviewCanvas: 'cropPreviewCanvas'
};

export function createCollageLifecycle(base, domIds = {}) {
    const ids = { ...DEFAULT_DOM_IDS, ...domIds };
    // Use ids.previewCanvas instead of 'previewCanvas'
}
```

**Key insight:** Always provide sensible defaults so existing callers don't break. The entry point (index.html) passes the IDs, and factories use the merged config.

**Testability benefit:** Tests can supply mock IDs and verify `getElementById` is called with the correct ID, without needing real DOM elements.

## 3. Internal Function Extraction vs. Module Extraction

The original plan called for extracting render/crop/undo methods into separate files (`createRenderMethods.js`, `createCropPreviewRenderer.js`, `createUndoMethods.js`). After implementation, this was deferred because:

- The internal functions already achieve SRP separation within the factory
- Extracting to separate modules would create tight coupling to Vue internals (`vm` parameter)
- The callback injection (CR-14) already achieves the primary goal: handler modules are decoupled from render logic
- Separate modules would add import complexity without meaningful testability gains

**Rule of thumb:** If internal functions within a factory already have clear boundaries and accept explicit parameters (not `this`), module extraction may be unnecessary. The callback injection pattern is the stronger DIP improvement.

## 4. getLayoutOptions() for OCP-Compliant UI

Adding `getLayoutOptions(style)` to `LayoutGenerator` returns a descriptor of which options each layout uses:

```javascript
getLayoutOptions(style) {
    return {
        gutter: true/false,
        sliceAngle: true/false,
        hexSpacing: true/false,
        hexSizeMultiplier: true/false
    };
}
```

**Why this matters:** The UI can dynamically show/hide options based on layout type without hardcoded conditions scattered across templates. Adding a new layout type only requires registering the generator AND its options — no template changes needed.

**Current state:** The UI still uses `v-show` conditions directly. The `getLayoutOptions()` method is available for future use when the UI migrates to data-driven option rendering.

## 5. File Input Handler: DOM Read vs. Event Parameter

The `handleFileInputChange` method was changed from accepting an event parameter to reading files directly from the DOM element by ID:

```javascript
// Before: relied on event.target
handleFileInputChange(event) {
    const files = event.target.files;
}

// After: reads from DOM by injected ID
handleFileInputChange() {
    const input = document.getElementById(fileInputId);
    const files = input ? input.files : null;
}
```

**Why this is better:**
- Decouples the handler from the event object
- The Vue template `@change="handleFileInputChange"` still works (Vue passes event, handler ignores it)
- More testable — can mock `document.getElementById` instead of constructing events
- Follows the same pattern as the file input trigger (`triggerFilePicker`)

**World-review concern addressed:** The handler correctly reads `files` from the DOM element. The Vue template passes the event but the handler doesn't need it.
