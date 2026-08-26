# Fix actions.js Outdated Documentation

`MyESModules/State/actions.js` has a JSDoc comment (lines 5–9) stating:

> "@todo WIREFUTURE: These functions are scaffolding for the DIP transition where state managers will depend on pure action functions instead of directly mutating Vue reactive state. Not yet wired into any manager."

This is no longer accurate. The actions **are** wired:

- `CropManager.js` imports and uses `setCropAction` and `resetCropAction`
- `LayoutManager.js` imports and uses `regenerateLayoutAction`

## Change

Update the JSDoc to reflect current usage:

```javascript
/**
 * State actions - Pure functions for mutating state.
 * Used by CropManager, LayoutManager, and other state managers
 * to provide testable, decoupled state mutation logic.
 *
 * Future: Additional managers (ImageLibrary, etc.) should migrate
 * to use action functions for full DIP compliance.
 */
```

No functional code changes needed.
