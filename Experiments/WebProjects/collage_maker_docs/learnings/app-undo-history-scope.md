# App Undo History Scope

**Date:** 2026-07-02
**Session:** 8 (P0 test follow-up)

## Summary

The CollageMaker app only creates undo/redo history for **crop operations**. Image removal, layout changes, gutter adjustments, and other actions do NOT push undo commands.

## What Creates Undo History

| Action | Creates Undo? | Source |
|--------|--------------|--------|
| Reset Crop (`resetSelectedCrop`) | Yes | `createCollageMethods.js:129` |
| Drag crop end (`onDragEnd`) | Yes | `createCollageLifecycle.js:97` |
| Remove image | **No** | `createCollageMethods.js:60` |
| Clear all images | **No** | `createCollageMethods.js:68` |
| Layout style change | **No** | `createCollageMethods.js:76` |
| Gutter change | **No** | `createCollageMethods.js:84` |
| Slice angle change | **No** | `createCollageMethods.js:92` |
| Hex spacing change | **No** | `createCollageMethods.js:100` |

## Impact on E2E Testing

This constraint means E2E tests that need to verify undo/redo button states MUST use crop operations to create undo history:

```javascript
// WRONG: removing an image does NOT enable the undo button
await removeBtns[0].click();
await page.click('#undoBtn'); // TIMEOUT — button is still disabled!

// CORRECT: reset crop creates undo history
await page.click('#previewCanvas'); // select a panel
await page.click('.reset-crop-btn'); // creates undo command
await page.click('#undoBtn'); // works — button is enabled
```

## Why This Matters

The `#undoBtn` and `#redoBtn` have `:disabled="!canUndo"` / `:disabled="!canRedo"` bindings. If no undo commands exist on the stack, these buttons remain disabled and Playwright will timeout trying to click them.

## Future Consideration

If undo history is desired for image removal or layout changes, the corresponding methods in `createCollageMethods.js` need to be updated to push undo commands before mutating state. This would be a feature addition, not a bug fix.
