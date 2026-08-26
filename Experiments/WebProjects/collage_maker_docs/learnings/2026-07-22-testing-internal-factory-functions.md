# Testing Factory-Internal Functions via Return Object Exposure

**Date:** 2026-07-22
**Context:** Phase 1 of undo/redo review follow-ups (N-2: genericize error messages)

## Problem

`pushUndoCommand` was an internal function inside `createCollageMethods.js` that wrapped undo/redo commands with error handling. To test the error toast messages, we needed to invoke this function, but it wasn't exported or accessible from outside the factory.

## Solution

Expose the internal function as a method on the factory's return object:

```javascript
// Internal function (not exported, scoped to factory)
function pushUndoCommand(vm, cmd) {
    if (vm.undoManager) {
        vm.undoManager.push({
            label: cmd.label,
            undo: () => {
                try { cmd.undoFn(vm); } catch (e) {
                    console.error(`Undo error (${cmd.label}):`, e);
                    if (vm.showToast) {
                        vm.showToast('Undo failed. Please try again.', 'error', 5000);
                    }
                }
            },
            // ... redo wrapper
        });
        vm._updateUndoState();
    }
}

// Expose on return object for testability
return {
    // ... other methods
    pushUndoCommand(vm, cmd) {
        pushUndoCommand(vm, cmd);
    },
};
```

## Mock VM Construction Pattern

When testing a factory that returns many methods, construct the mock VM by spreading the factory methods first, then overriding specific methods with spies:

```javascript
function buildVm(undoManager) {
    const base = makeMockBase(undoManager);
    const methods = createCollageMethods(base);

    // Spread factory methods first
    const vm = { ...methods };

    // Override specific methods with spies (MUST come after spread)
    vm.showToast = (msg, type, duration) => {
        vm._toastCalls.push({ message: msg, type, duration });
    };

    return vm;
}
```

**Key insight:** `Object.assign(vm, methods)` or `{ ...methods }` overwrites any properties set before it. Always spread/assign the factory methods first, then override with spies.

## Why Not Export the Internal Function?

Exporting `pushUndoCommand` as a module-level named export would:
1. Break the factory encapsulation pattern
2. Require the function to accept all dependencies as parameters (losing closure benefits)
3. Create a new import dependency for test files

The return-object exposure pattern keeps the function scoped to the factory while making it accessible for testing.

## When to Use This Pattern

- The function is genuinely internal (not needed by other modules)
- The function has meaningful behavior worth testing (error handling, validation, etc.)
- The function relies on factory-scoped closures (dependencies, state)
- You don't want to extract the function to a separate module

## When NOT to Use This Pattern

- The function is already testable through the public API (prefer testing through public methods)
- The function is simple enough that testing through integration is sufficient
- The function should be extracted to its own module (consider SRP — if it's complex enough to need direct testing, it might belong in its own module)

## Related

- Skill: `building-web-apps` → Factory Testability Patterns → Callback Injection
- Learning: `2026-07-12-provider-function-callback-injection.md`
- Learning: `2026-07-09-phase5-refactoring-learnings.md` (method extraction)
