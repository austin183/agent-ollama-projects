# Vue 3 Options API Factory Decomposition

**Date:** 2026-07-01
**Session:** 3 (Phase 1 implementation)

## Summary

The project follows the Midiestro3D pattern of decomposing Vue 3 Options API configuration into separate factory functions. This keeps the Vue app assembly clean and testable.

## Pattern

```javascript
// createCollageApp.js — Vue app factory
export function createCollageApp({
    createApp,
    dataConfig,       // from createCollageData.js
    methodsConfig,    // from createCollageMethods.js
    lifecycleConfig,  // from createCollageLifecycle.js
    servicesConfig    // from createCollageServices.js
}) {
    return createApp({
        data: dataConfig,
        computed: { ... },
        methods: methodsConfig,
        ...lifecycleConfig,
        ...servicesConfig
    });
}
```

### Why This Pattern Works

1. **Separation of concerns**: Data, methods, lifecycle, and services are in separate files
2. **Testability**: Factory functions can be tested without Vue
3. **Composition**: `CollageBase.js` provides shared services that all factories can access
4. **Lazy initialization**: Services that need reactive state are initialized in `mounted()`

### Key Files

| File | Responsibility |
|------|---------------|
| `CollageBase.js` | Base services (assembler, dropHandler, componentRegistry) |
| `createCollageData.js` | Reactive data factory (returns function for Vue `data`) |
| `createCollageMethods.js` | Instance methods (all `this`-aware operations) |
| `createCollageLifecycle.js` | `mounted()` and `beforeUnmount()` hooks |
| `createCollageServices.js` | `provide()` / `inject()` for dependency injection |
| `createCollageApp.js` | Assembles everything into Vue app config |

## Gotchas

1. **`data` must be a function** — Vue requires `data` to be a factory function, not an object. `createCollageData()` returns a function that returns the data object.
2. **`this` context** — Methods in `createCollageMethods.js` run with `this` pointing to the Vue instance, so they can access reactive data directly.
3. **Lifecycle hooks get `this`** — The `mounted()` function in `createCollageLifecycle.js` receives `this` as the Vue instance, so it can set properties like `this.canvasRenderer = renderer`.
4. **Spread operators for lifecycle/services** — `...lifecycleConfig` and `...servicesConfig` merge the hooks into the Vue config. This works because lifecycle hooks are just functions and services use `provide()` which is a special Vue option.

### Critical: Methods Must Be Inside `methods:` Block

In Vue 3 Options API, **functions defined at the root level of the component options object (not inside a `methods:` block) are NOT added to the instance's `this`**. Only lifecycle hooks (`mounted`, `beforeUnmount`, etc.) and functions inside `methods: { ... }` are properly bound.

```javascript
// WRONG — _applySavedSettings is undefined when called from mounted() via this._applySavedSettings()
export function createCollageLifecycle(base) {
    return {
        mounted() {
            this._applySavedSettings(savedSettings); // TypeError!
        },
        _applySavedSettings(settings) { /* ... */ }  // ← Root-level, NOT on `this`
    };
}

// CORRECT — methods inside a `methods:` block are bound to `this`
export function createCollageLifecycle(base) {
    return {
        mounted() {
            this._applySavedSettings(savedSettings); // Works!
        },
        methods: {
            _applySavedSettings(settings) { /* ... */ }  // ← Inside `methods`, on `this`
        }
    };
}
```

Vue's Options API merger only processes properties in the `data`, `computed`, `methods`, `watch`, and lifecycle hook slots. Any other function defined at root level is silently ignored — it becomes an extra property on the options object but never reaches the component instance. This manifests as:
- `TypeError: this._applySavedSettings is not a function` (uncaught, crashes mounted)
- `[Vue warn]: Property "X" was accessed during render but is not defined on instance.`

**Rule of thumb:** If a function needs to be called via `this.methodName()`, it MUST be inside a `methods:` block. Lifecycle hooks are the only exception — they're special-cased by Vue's options merger.

### Critical: Object Spread Order Silently Overwrites Properties

When merging Options API configs with spread, **later properties overwrite earlier ones**. If `lifecycleConfig` has a `methods:` property (e.g., for helper methods that need lifecycle context), it will silently replace the main `methods: methodsConfig`.

```javascript
// WRONG — ...lifecycleConfig overwrites methods if lifecycleConfig has a `methods` key
return createApp({
    methods: methodsConfig,           // ← All template-referenced methods here...
    ...lifecycleConfig,               // ← ...but this replaces them!
});
// Result: only _applySavedSettings and _handleKeyboard survive on `this`.
// triggerFilePicker, undo(), redo() etc. are gone → Vue render warnings + crashes.

// CORRECT — explicitly merge methods and reference lifecycle hooks by name
const allMethods = {
    ...methodsConfig,
    ...(lifecycleConfig.methods || {})  // ← Merge both method sources
};
return createApp({
    methods: allMethods,
    mounted: lifecycleConfig.mounted,        // ← Explicit, no overwrite risk
    beforeUnmount: lifecycleConfig.beforeUnmount,
});
```

This is a classic JavaScript object spread gotcha — property evaluation order matters. When building factory assemblies that merge multiple config objects, always be explicit about which keys come from where rather than relying on `...spread`.

## State Management

The project uses Vue 3 reactivity directly (no Pinia, no Vuex). The reactive state lives in the Vue instance's `data()` return value. State managers (`LayoutManager`, `CropManager`, etc.) receive a reference to the Vue instance (`this`) and mutate its reactive properties directly.

This is simpler than a dedicated state management library but requires discipline: all state mutations must go through the state managers to ensure undo/redo tracking.
