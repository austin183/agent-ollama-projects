# Provider Function Pattern for Callback Injection

**Date:** 2026-07-12
**Session:** Phase 4 — Pre-merge review fixes (Issue #7)

## Problem

When a factory function accepts callback references as parameters, those references are captured at factory creation time. If the caller later replaces the underlying function, the factory holds a **stale reference** to the old callback.

```javascript
// STALE — callback captured at factory creation time
const undoMethods = createUndoMethods(base, {
    onRenderScheduled: (vm) => renderMethods._scheduleRender(vm)
    // If renderMethods is later reassigned, undo still calls the OLD _scheduleRender
});
```

## Solution: Provider Functions

Accept provider functions that return the callback at call time, ensuring fresh references:

```javascript
// FRESH — provider returns callback at call time
const undoMethods = createUndoMethods(base, {
    getOnRenderScheduled: () => (vm) => renderMethods._scheduleRender(vm)
    // Each undo/redo call gets the current renderMethods reference
});
```

Inside the factory:
```javascript
const getOnRenderScheduled = callbacks.getOnRenderScheduled || (() => () => {});
// ...
getOnRenderScheduled()(vm);  // Provider called at undo/redo time, not factory time
```

## Defensive Guard

Add a helper that guards against providers returning non-callable values:

```javascript
function _invokeProvider(provider, vm) {
    const callback = provider();
    if (typeof callback === 'function') {
        callback(vm);
    }
}
```

This prevents `TypeError` if a future caller provides a malformed provider (e.g., `() => null`).

## Testing Strategy

**Test that provider is called at call time (not factory time):**

```javascript
let callCount = 0;
const methods = createUndoMethods(base, {
    getOnRenderScheduled: () => (vm) => { callCount++; }
});
methods._performUndo({});
methods._performUndo({});
expect(callCount).to.equal(2);  // Provider called twice, not once
```

**Test that default no-op works:**

```javascript
const methods = createUndoMethods(base);  // No callbacks
expect(() => methods._performUndo({})).to.not.throw();
```

**Test that non-callable return value is guarded:**

```javascript
const methods = createUndoMethods(base, {
    getOnRenderScheduled: () => null  // Invalid
});
expect(() => methods._performUndo({})).to.not.throw();
```

## When to Use

- **Use provider functions** when callbacks reference objects that may be replaced after factory creation
- **Use direct callbacks** when the referenced objects are stable for the factory's lifetime (simpler, less indirection)
- **Always add a defensive guard** (`typeof callback === 'function'`) when using provider functions — it costs virtually nothing and prevents cryptic TypeErrors from future callers

## Relation to Existing Patterns

This is a specific application of the **"Look up services inside callbacks, not outside"** rule documented in the `building-web-apps` skill. The provider function pattern formalizes this principle for callback injection: instead of capturing a function reference at factory time, you capture a provider function that resolves the reference at call time.

## File Reference

- `MyESModules/App/createUndoMethods.js` — Provider function implementation
- `MyESModules/App/createCollageMethods.js` — Caller using provider functions
- `MyComponents/UndoManagerTest.html` — Tests 4.2.1–4.2.6
