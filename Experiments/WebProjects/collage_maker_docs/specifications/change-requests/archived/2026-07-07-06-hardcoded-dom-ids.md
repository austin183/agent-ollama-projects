# Remove Hardcoded DOM IDs

Several modules reference hardcoded DOM element IDs, reducing testability and portability.

## Affected Code

| File | Line | Hardcoded ID |
|------|------|-------------|
| `createCollageLifecycle.js` | 28 | `'previewCanvas'` |
| `createCollageLifecycle.js` | 96 | `'cropPreviewCanvas'` |
| `createFileHandlers.js` | 21 | `'fileInput'` |
| `createCollageMethods.js` | 363 | `'cropPreviewCanvas'` (in `_scheduleCropPreviewRender`) |

## Change

Pass DOM IDs as configuration to factory functions:

- `createCollageLifecycle` accepts `canvasIds: { preview: 'previewCanvas', cropPreview: 'cropPreviewCanvas' }`
- `createFileHandlers` accepts `fileInputId: 'fileInput'`
- `createCollageMethods` accepts `cropPreviewCanvasId: 'cropPreviewCanvas'` (or extract to `createCropPreviewRenderer`)

The Vue app assembly layer (e.g., `createCollageApp.js`) supplies the IDs. This enables unit testing with mock IDs and supports future multi-instance scenarios.
