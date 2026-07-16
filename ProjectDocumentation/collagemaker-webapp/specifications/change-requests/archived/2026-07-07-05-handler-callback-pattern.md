# Consistent Handler Regeneration Pattern

Handler modules have an inconsistent approach to triggering layout regeneration and rendering after state mutations.

## Current State

- `createFileHandlers.js` receives an `onRegenerate` callback but `handleFileInputChange` calls `this._regenerateAndRender()` (Vue instance method) instead
- `createImagePanelHandlers.js`, `createLayoutHandlers.js`, `createCropHandlers.js`, etc. all call `this._scheduleRender()` directly
- `createBackgroundHandlers.js` calls `this._scheduleRender()` directly

This creates a pervasive implicit dependency on Vue instance methods across all handler modules.

## Options

**Option A — Callback pattern (preferred for DIP):** Pass `onRegenerate` and `onRenderScheduled` callbacks to every handler factory. Handlers invoke callbacks instead of `this._scheduleRender()`.

**Option B — Keep Vue method calls:** Document that handler methods are bound to the Vue instance via `.call(this, ...)` and `this._scheduleRender()` is an accepted dependency. Keep as-is.

## Recommendation

Adopt Option A for new modules. For existing handlers, the migration is low-risk since the callback wiring already exists in `createCollageMethods.js`. The `onRegenerate` callback in `createFileHandlers` is already wired — it just needs to be used.
