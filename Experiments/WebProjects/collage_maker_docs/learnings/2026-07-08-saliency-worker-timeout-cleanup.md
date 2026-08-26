# Saliency Worker Timeout Cleanup Patterns

**Date:** 2026-07-08
**Context:** CR-11 — saliency inference timeout guard

## Problem

The `SaliencyAnalyzer` uses `setTimeout` to enforce a maximum inference duration. If the worker was disposed (e.g., user navigated away or new analysis started) before the timeout fired, the stale callback would attempt to update state on a disposed analyzer, causing errors or memory leaks.

## Solution

Clear `inferenceTimeoutId` on every termination path:

```javascript
// On ready
clearTimeout(this.inferenceTimeoutId);
this.inferenceTimeoutId = null;

// On failed
clearTimeout(this.inferenceTimeoutId);
this.inferenceTimeoutId = null;

// On dispose
clearTimeout(this.inferenceTimeoutId);
this.inferenceTimeoutId = null;
```

## Testing Pattern

To test timeout behavior without waiting 15 seconds (production `INFERENCE_TIMEOUT_MS`):

1. **Override the config** — set `SALIENCY_CONFIG.INFERENCE_TIMEOUT_MS = 50` before creating the analyzer
2. **Mock `window.Worker`** — use `Object.defineProperty` with a setter to capture `onmessage` assignment, then fire messages manually
3. **Test the happy path** — worker responds before timeout → timeout is cleared
4. **Test the failure path** — worker fails before timeout → timeout is cleared
5. **Test the dispose path** — dispose before timeout → timeout is cleared and callback is a no-op

### Mock Worker Pattern

```javascript
let capturedOnMessage = null;
Object.defineProperty(window, 'Worker', {
    configurable: true,
    value: class {
        constructor(url) {
            // Capture onmessage handler
        }
        set onMessage(fn) { capturedOnMessage = fn; }
        postMessage(msg) { /* no-op */ }
        terminate() { /* no-op */ }
    }
});
```

## Key Insight

**Always clear timeouts on every exit path.** The timeout is a safety net, not a primary flow. If the primary flow (worker message) completes first, the timeout should be cleaned up. If the timeout fires first, it should check that the analyzer is still alive before updating state.

## Gotchas

- Error message uses "timeout" (not "timed out") to match test assertion `.include('timeout')`
- The `dispose()` method should also null the timeout ID to prevent the callback from firing after disposal
- Worker `'error'` events (not just `'failed'` messages) can leave timeouts uncleared — consider adding a guard in the timeout callback itself: `if (this.isDisposed || !this.worker) return;`
