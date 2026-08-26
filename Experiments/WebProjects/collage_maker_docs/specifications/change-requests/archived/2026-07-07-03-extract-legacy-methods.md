# Extract Legacy Methods from createCollageMethods

`MyESModules/App/createCollageMethods.js` is 482 lines despite handler decomposition. Lines 258–480 contain a "Legacy Methods" section with rendering, crop preview, and undo/redo logic that belongs in dedicated modules.

## Extract Into

1. **`createRenderMethods.js`** — `_scheduleRender()`, `_buildBackgroundState()`, `_buildOverlayState()`, `_regenerateAndRender()`
2. **`createCropPreviewRenderer.js`** — `_scheduleCropPreviewRender()` (92 lines of inline canvas rendering including DPR scaling, image contain math, dark overlay, border, and corner handles)
3. **`createUndoMethods.js`** — `_updateUndoState()`, `_performUndo()`, `_performRedo()`

## Requirements

- Each new module follows the existing factory pattern (exported function accepting base/service getters)
- Methods are composed into the main methods object in `createCollageMethods()` via spread or merge
- Existing Vue template bindings remain unchanged (method names stay the same)
- Barrel exports in `MyESModules/index.js` updated if needed
