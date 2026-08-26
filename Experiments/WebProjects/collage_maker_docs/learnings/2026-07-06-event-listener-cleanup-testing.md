# Event Listener Cleanup Testing — 2026-07-06

**Context**: Phase 2 of pre-commit review fixes — implementing cleanup functions for global drop handlers and verifying them with tests.

## Key Findings

### 1. DragEvent.dataTransfer Cannot Be Mocked in Constructor

In Chromium (headless or not), you cannot pass a custom `dataTransfer` object to the `DragEvent` constructor:

```javascript
// FAILS in all browsers:
const event = new DragEvent('drop', {
    dataTransfer: { files: [mockFile] }
});
// TypeError: Failed to convert value to 'DataTransfer'
```

**Workaround**: Test listener removal by tracking `preventDefault()` calls rather than simulating file drops:

```javascript
const evt = new DragEvent('drop', { bubbles: true, cancelable: true });
let prevented = false;
evt.preventDefault = () => { prevented = true; };
document.dispatchEvent(evt);
expect(prevented).to.be.true; // Listener was active

cleanup();

const evt2 = new DragEvent('drop', { bubbles: true, cancelable: true });
prevented = false;
evt2.preventDefault = () => { prevented = true; };
document.dispatchEvent(evt2);
expect(prevented).to.be.false; // Listener was removed
```

### 2. Document-Level Event Listener Test Isolation

Event listeners attached to `document` persist across Mocha tests. Each test that adds listeners MUST clean them up, and tests that verify "after cleanup" behavior need full isolation:

```javascript
// PATTERN: Use a describe-level variable for cleanup
describe('Drop handler cleanup', () => {
    let cleanup;

    afterEach(() => {
        if (cleanup) { cleanup(); cleanup = null; }
    });

    it('listener is removed after cleanup', () => {
        // Setup handler in test body, not beforeEach
        const { cleanup: c } = setupHandler();
        cleanup = c; // Register for afterEach

        // Verify active
        dispatchEvent();
        expect(prevented).to.be.true;

        // Verify removed
        c();
        dispatchEvent();
        expect(prevented).to.be.false;
    });
});
```

**Anti-pattern**: Using `beforeEach` to set up a handler AND having tests create their own handlers. This creates listener accumulation that makes "after cleanup" assertions false-positive (old listeners still active).

### 3. Lifecycle Cleanup Ordering Prevents Race Conditions

When `beforeUnmount()` disposes resources, the ORDER matters if interaction handlers are async:

```javascript
// WRONG — async drop handler may fire after canvas disposal:
beforeUnmount() {
    this.canvasRenderer.dispose();    // canvas = null
    this._dropCleanup();              // too late — drop promise already pending
}

// CORRECT — stop interactions first:
beforeUnmount() {
    this._dropCleanup();              // no new drops can start
    this._keyboardHandler.detach();
    this._gestureHandler.detach();
    this.canvasRenderer.dispose();    // safe — no pending interactions
}
```

**Rule**: Remove all interaction listeners (drop, keyboard, gesture, crop) BEFORE disposing renderers and state managers.

### 4. Cleanup Functions Should Clean Visual State Too

A cleanup function that only removes event listeners leaves the UI in an inconsistent state:

```javascript
// INCOMPLETE — removes listeners but leaves visual state:
return function cleanup() {
    document.removeEventListener('dragenter', onDragEnter);
    // ... other listeners
};

// COMPLETE — also clears visual feedback:
return function cleanup() {
    document.removeEventListener('dragenter', onDragEnter);
    // ... other listeners
    document.body.classList.remove('drag-over'); // Clear visual state
};
```

**Rule**: A cleanup function should leave the system in the same state as before setup — including DOM classes, counters, and any other side effects.

### 5. Canvas GPU Memory Release Pattern

Setting canvas dimensions to zero forces context loss and GPU memory release across all modern browsers:

```javascript
dispose() {
    if (canvas) {
        canvas.width = 0;
        canvas.height = 0;
    }
    canvas = null;
    ctx = null;
}
```

This is more reliable than just nulling the JS reference, which may leave GPU-backed buffer memory allocated (especially in Safari/WebKit).

## What Was Already Known

- Mock browser APIs with `bind()` and restore after (from testing.md)
- Use Proxy for Canvas 2D context mocking (from testing.md)
- Memory management patterns for ImageElement disposal (from memory-management.md)

## What's New

- DragEvent.dataTransfer constructor limitation (browser-specific)
- Document-level listener test isolation pattern
- Lifecycle cleanup ordering for async handlers
- Visual state cleanup in teardown functions
