# try/finally for Async UI State Cleanup

**Date:** 2026-07-18
**Session:** Phase 3 — Progress Bar When Adding Images

## Problem

An async operation (loading images) shows a UI overlay at the start and hides it at the end. If the async operation throws (e.g., a corrupt image causes `Promise.all` to reject), the cleanup code after the `await` never runs, leaving the overlay permanently visible.

```javascript
// BROKEN — endImageLoading() never called on error
this.beginImageLoading(total);
await imageLibrary.addImages(files, onProgress); // May throw
this.endImageLoading(); // Never reached if addImages rejects
```

## Solution: try/finally Guarantees Cleanup

Wrap the async operation in try/finally to ensure the UI state is always restored, regardless of success or failure:

```javascript
this.beginImageLoading(total);
try {
    await imageLibrary.addImages(files, onProgress);
} finally {
    this.endImageLoading(); // Always runs — success, error, or early return
}
```

## Why This Differs from Timeout Cleanup

The existing "clear timeouts on every exit path" pattern (from saliency worker) handles **scheduled callbacks** — you explicitly clear a timer ID on each termination path. The try/finally pattern handles **paired state changes** — you guarantee the "end" state change always follows the "begin", even across async boundaries.

| Pattern | What it protects | Mechanism |
|---------|-----------------|-----------|
| Timeout cleanup | Stale callbacks on disposed objects | Explicit `clearTimeout()` on each path |
| try/finally | Paired UI state changes across async | `finally` block always executes |

## Key Details

1. **`finally` always runs** — Whether the `await` resolves, rejects, or the function returns early, the `finally` block executes. This is the only JavaScript construct that guarantees cleanup across all exit paths from a try block.

2. **Normal completion still works** — If the last image loads successfully, the progress callback fires with `(current === total)`, which triggers `endImageLoading()` via `_setImageLoadingProgress()`. The `finally` block then calls `endImageLoading()` again — idempotent, no harm.

3. **Error path is the key benefit** — If `addImages()` throws (e.g., all images are corrupt), the progress callback never reaches `(total, total)`. Without `finally`, the overlay stays visible forever. With `finally`, it's always hidden.

4. **Guard against double-signaling** — In the file handler, a `progressStarted` flag ensures the `finally` block only signals completion if progress was actually started:

   ```javascript
   let progressStarted = false;
   try {
       if (onImageLoadingProgress && imageFiles.length > 0) {
           onImageLoadingProgress(this, 0, imageFiles.length);
           progressStarted = true;
       }
       await imageLibrary.addImages(files, onProgress);
   } finally {
       if (progressStarted && onImageLoadingProgress) {
           onImageLoadingProgress(this, imageFiles.length, imageFiles.length);
       }
   }
   ```

   In the drop handler (simpler path), `endImageLoading()` is called unconditionally in `finally` — it's idempotent and harmless when `visible` is already `false`.

## Concurrency Guard

Pair try/finally with a simple guard in `beginImageLoading()` to prevent state corruption from rapid successive operations:

```javascript
beginImageLoading(total) {
    if (this.imageLoadingProgress.visible) return; // Already loading — skip
    this.imageLoadingProgress.visible = true;
    this.imageLoadingProgress.current = 0;
    this.imageLoadingProgress.total = total;
},
```

This prevents a second batch from overwriting the progress state while the first is still loading. It's a simple early-return guard — no locking, no queueing. If the user drops images while another batch is loading, the second batch is silently ignored for progress tracking (the images still load, just without a progress overlay).

## When to Use

- Any async operation that shows/hides a UI element (overlay, spinner, progress bar)
- Any paired begin/end state changes around async work
- Especially important when the async operation can throw

## File References

- `MyESModules/App/createFileHandlers.js` — try/finally in `handleFileInputChange()`
- `MyESModules/App/createCollageLifecycle.js` — try/finally in drop handler
- `MyESModules/App/createCollageMethods.js` — concurrency guard in `beginImageLoading()`
