# RAF Mocking for Unit Tests

## Context

When testing code that uses `requestAnimationFrame` (RAF), you need deterministic control over when callbacks fire. In the CollageMaker crop preview debounce (Phase 3), `_scheduleCropPreviewRender()` wraps canvas operations in RAF, and tests needed to verify coalescing behavior.

## Pattern

Replace `window.requestAnimationFrame` with a callback collector, and `window.cancelAnimationFrame` with an ID tracker:

```javascript
let rafCallbacks = [];
let canceledIds = new Set();
const originalRAF = window.requestAnimationFrame.bind(window);
const originalCancelRAF = window.cancelAnimationFrame.bind(window);

function mockRAF() {
    rafCallbacks = [];
    canceledIds = new Set();
    window.requestAnimationFrame = (cb) => {
        const id = rafCallbacks.length + 1;
        rafCallbacks.push(cb);
        return id;
    };
    window.cancelAnimationFrame = (id) => {
        canceledIds.add(id);
    };
}

function restoreRAF() {
    window.requestAnimationFrame = originalRAF;
    window.cancelAnimationFrame = originalCancelRAF;
}

function flushRAF() {
    const cbs = [...rafCallbacks];
    rafCallbacks = [];
    for (const cb of cbs) {
        cb();
    }
}
```

## Key Rules

1. **Always `bind()` the original** — `window.requestAnimationFrame.bind(window)` preserves `this` context. Without bind, the original may fail in strict mode.
2. **Always restore after tests** — Use `afterEach` to call `restoreRAF()`. A leaking mock breaks all subsequent tests.
3. **Flush synchronously** — `flushRAF()` executes all pending callbacks immediately, simulating the browser firing the next frame. This lets you verify coalescing: call the function 5 times, check `rafCallbacks.length === 1`, then flush.
4. **Return numeric IDs** — The mock returns incrementing IDs starting from 1, matching the browser's behavior. This allows `cancelAnimationFrame` tests to work correctly.

## Testing Debounce Coalescing

```javascript
// Call 5 times rapidly (before RAF fires)
fn(); fn(); fn(); fn(); fn();

// Only one RAF callback should have been queued
expect(rafCallbacks).to.have.lengthOf(1);

// Flush — the single callback executes
flushRAF();

// Verify render happened once
expect(drawCount).to.equal(1);
```

## Latest-Wins Pattern

When using RAF for debouncing, always read state **inside** the RAF callback, not at call time:

```javascript
// GOOD — reads current state at frame time
_scheduleRender() {
    if (this._pending) return;
    this._pending = true;
    requestAnimationFrame(() => {
        this._pending = false;
        const data = this.getData(); // Reads current state
        // ... render with data
    });
}

// BAD — captures stale state at call time
_scheduleRender() {
    const data = this.getData(); // Captures state at call time
    requestAnimationFrame(() => {
        // ... renders with stale data
    });
}
```

The "latest-wins" pattern ensures that rapid state changes (e.g., during drag) result in rendering the most recent state, not an intermediate one.

## Related

- `MyComponents/CropPreviewTest.html` — Full working examples
- `MyESModules/Rendering/CanvasRenderer.js` — Production RAF debounce pattern
- `MyESModules/App/createCollageMethods.js` — `_scheduleCropPreviewRender()` implementation
