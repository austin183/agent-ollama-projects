# Crop Preview Timing Issue

## Problem
When selecting a panel on the canvas, the Crop Editor sidebar showed a blank black screen instead of displaying the image with crop overlay.

## Root Cause
Two issues:
1. Missing render call - `selectPanel` only called `_scheduleRender()` for main canvas, never updated crop preview sidebar
2. DOM timing issue - The `#cropPreviewCanvas` element lives inside a `v-if="selectedPanelId && selectedCropInfo"` block. When `selectPanel` set `selectedPanelId`, Vue updates the DOM asynchronously. The crop preview render function was called immediately and tried to access the canvas before it existed in the DOM.

## Solution
1. Added call to `_scheduleCropPreviewRender()` in the `selectPanel` handler (`createCropHandlers.js`)
2. Wrapped the call in `this.$nextTick()` to ensure Vue has finished DOM updates before accessing the canvas element

```javascript
selectPanel(panelId, cropInteraction = null) {
    this.selectedPanelId = panelId;
    if (cropInteraction) {
        cropInteraction.setPanelId(panelId);
    }
    this._scheduleRender();
    // Delay until DOM is updated
    this.$nextTick(() => {
        this._scheduleCropPreviewRender();
    });
}
```

## Key Takeaways
- Always match Vue reactivity lifecycle: when state changes affect DOM elements, use `$nextTick()` to ensure those elements exist before accessing them
- Check that all related UI components are updated when a state change occurs (both main canvas AND sidebar)
- Use `v-if` conditionally rendered elements carefully - they don't exist until their condition is truthy and Vue has processed the update

## Related Files
- `MyESModules/App/createCropHandlers.js` - Handler for panel selection
- `MyESModules/App/createCollageMethods.js` - `_scheduleCropPreviewRender()` implementation
