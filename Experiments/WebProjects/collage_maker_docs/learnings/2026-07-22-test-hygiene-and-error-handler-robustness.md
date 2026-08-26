# Test Hygiene and Error Handler Robustness

**Date:** 2026-07-22
**Context:** World-review of Phase 1 (N-2) undo/redo error message genericization

## Two Issues Found by World-Review

### Issue 1: Mocked Globals Must Be Restored in afterEach

When stubbing global APIs like `console.error` in `beforeEach`, always restore them in `afterEach`. Failure to do so causes test pollution — subsequent tests or test files may receive the stubbed behavior instead of the real global.

**Before (broken):**
```javascript
beforeEach(() => {
    const originalConsoleError = console.error;  // Scope limited to beforeEach
    console.error = (...args) => { consoleErrors.push(args); };
});
// No afterEach — console.error stays stubbed
```

**After (fixed):**
```javascript
let originalConsoleError;

beforeEach(() => {
    originalConsoleError = console.error;  // Module-level variable
    console.error = (...args) => { consoleErrors.push(args); };
});

afterEach(() => {
    console.error = originalConsoleError;  // Always restore
});
```

**Key pattern:** Store the original in a variable that survives both `beforeEach` and `afterEach` (describe-level `let`, not `const` inside `beforeEach`).

### Issue 2: Defensive try/catch Around Side Effects in Error Handlers

When a `catch` block calls a side-effect function (like `showToast`), that function can itself throw. Since the call is inside a catch block, its error propagates outward and crashes the entire undo/redo flow — leaving the user with no feedback.

**Before (fragile):**
```javascript
try { cmd.undoFn(vm); } catch (e) {
    console.error(`Undo error (${cmd.label}):`, e);
    if (vm.showToast) {
        vm.showToast('Undo failed. Please try again.', 'error', 5000);
        // If showToast throws, error propagates and crashes undo flow
    }
}
```

**After (robust):**
```javascript
try { cmd.undoFn(vm); } catch (e) {
    console.error(`Undo error (${cmd.label}):`, e);
    if (vm.showToast) {
        try {
            vm.showToast('Undo failed. Please try again.', 'error', 5000);
        } catch (toastErr) {
            console.error('Toast notification failed:', toastErr);
        }
    }
}
```

**Rule of thumb:** Any side effect called from inside a `catch` block should itself be wrapped in try/catch. The error handler must never throw — it's the last line of defense.

### Issue 3: Test Edge Cases for Missing Services

When production code has optional service guards (`if (vm.showToast)`, `if (vm.undoManager)`), add tests that verify graceful degradation when those services are absent. These tests catch regressions where a future change might assume a service is always present.

**Tests added:**
- `showToast` is missing → no toast shown, console.error still fires
- `showToast` throws → caught by defensive wrapper, undo flow continues
- `undoManager` is null → `pushUndoCommand` is a no-op, no error

## When to Apply These Lessons

- **Mock restoration:** Every test that stubs a global (`console.*`, `window.*`, `document.*`) must restore in `afterEach`
- **Defensive catch:** Any `catch` block that calls more than `console.error` should wrap side effects in nested try/catch
- **Missing service tests:** Any guard like `if (service)` in production deserves a test with the service absent

## Related

- Skill: `building-web-apps` → Testing → Mock browser APIs
- Learning: `mocha-chai-browser-tests.md` (test infrastructure)
- Learning: `2026-07-22-testing-internal-factory-functions.md` (mock VM construction)
