# Saliency Model Failure — User-Visible Feedback

The saliency timeout guard (CR-11) correctly transitions to `state === 'failed'` and fires `onModelsFailed`. However, the Vue app may not surface this failure to the user. If the saliency model fails to load (slow network, CORS, ad-blocker), the user should see a non-blocking notification and the app should fall back to center-crop behavior.

## Current State

`createSaliencyAnalyzer` fires `cb.onModelsFailed(message)` on timeout. The callback is wired in `createCollageLifecycle.js` (or wherever the saliency analyzer is instantiated). If the callback only sets an internal flag without UI feedback, the user has no indication that AI-powered cropping is unavailable.

## Change

In the Vue app's `onModelsFailed` callback, display a non-blocking notification:

- **UI:** Toast or subtle banner: *"AI features unavailable — using default focus"*
- **Behavior:** Ensure the app continues normally with center-crop fallback (already implemented in `SaliencyAnalyzer.js` lines 423-438)
- **Dismissal:** Auto-dismiss after 5 seconds, or dismissible by user

## Files

- `MyESModules/App/createCollageLifecycle.js` — verify `onModelsFailed` callback shows notification
- `index.html` — add toast/banner template if needed
- `Style.css` — styles for notification element

## Testing

Add a test to `MyComponents/SaliencyTest.html` that verifies `onModelsFailed` is called with the timeout message. Manual test: block TF.js network requests and verify the notification appears.

---

# Hex Panel Swap — Visual Feedback During Drag

The hex drag-and-drop handler (`HexPanelSwap.js`) correctly detects drag start, tracks movement threshold, and performs swap on pointer up. However, there is no visual feedback during the drag operation. Users won't know which hexagon they're targeting, especially on mobile with imprecise touch.   Also after some swaps, part of the panel of one of the swapped images disappears.

## Current State

`createHexDragHandler` tracks `dragSourceId` and `isDragging` during the drag, but emits no hover events or visual cues during `_onPointerMove`.

## Change

Add visual feedback during hex panel drags:

1. **Target highlighting:** During `_onPointerMove`, perform hit test and emit a "hovering target" event. The handler should call a new `onTargetHovered(panelId)` callback that highlights the target hexagon (e.g., semi-transparent overlay or glowing border via the canvas renderer).
2. **Cursor feedback:** Change cursor to `grabbing` or `move` during drag.
3. **Revert on outside drop:** If pointer is released outside a valid hex cell, the drag should silently revert (already implemented — `targetId` check at line ~180).

## Files

- `MyESModules/Interaction/HexPanelSwap.js` — add `onTargetHovered` callback, hit test in `_onPointerMove`
- `MyESModules/Rendering/` — add hover highlight rendering for hex panels (or reuse existing hover infrastructure from `GestureHandler`)
- `MyESModules/App/createCollageLifecycle.js` — wire `onTargetHovered` callback

## Testing

Add visual test to `MyComponents/HexPanelSwapTest.html` verifying `onTargetHovered` is called during drag. Manual test: drag between hex panels and verify target highlights.  Verify full swapped panel images still appear.

---

# Keyboard Shortcut Discoverability

The new shortcuts (`meta+e` for export, `alt+[1-5]` for layouts) are functionally correct but undiscoverable. Users won't know about these shortcuts unless they see them somewhere in the UI.

## Current State

`KEYBOARD_SHORTCUTS` in `KeyboardHandler.js` defines the shortcuts. The toolbar buttons in `index.html` may show tooltip text, but the new shortcuts need to be reflected there.

## Change

Add shortcut hints to the UI:

1. **Layout buttons:** Add tooltip or label showing the shortcut key (e.g., "Uniform [Alt+1]", "Hero [Alt+2]", etc.)
2. **Export button:** Add tooltip: "Export [Cmd+E]" (or "Export [Ctrl+E]" on Windows)
3. **Help modal (optional):** Add a "Keyboard Shortcuts" help dialog accessible via a footer link or menu item, listing all shortcuts

## Files

- `index.html` — update tooltip text on layout and export buttons
- `Style.css` — styles for tooltip if needed

## Testing

Visual verification. Update `test/e2e/keyboard-shortcuts.spec.js` if E2E tests check tooltip content.

---

# Collapsible Sidebar — ARIA Accessibility

The collapsible sidebar sections (CR-08) use `expandedSections` reactive state and `toggleSection()` method. For screen reader users, the sections need proper ARIA attributes.

## Current State

The sidebar section headers are clickable elements that toggle `expandedSections[sectionId]`. Without ARIA attributes, screen readers cannot communicate the expanded/collapsed state to users.

## Change

Add ARIA attributes to sidebar section headers:

```html
<button
  class="sidebar-section-header"
  @click="toggleSection(section.id)"
  :aria-expanded="expandedSections[section.id]"
  :aria-controls="'section-' + section.id"
>
```

And add corresponding `id` to the content containers:

```html
<div
  class="sidebar-section-content"
  :id="'section-' + section.id"
  v-show="expandedSections[section.id]"
>
```

## Files

- `index.html` — add `aria-expanded`, `aria-controls`, and `id` attributes

## Testing

Manual accessibility test with VoiceOver (macOS) or NVDA (Windows). Verify screen reader announces "collapsed" / "expanded" state on section headers.

---

# PNG Export — Transparent Background Interaction

The background compositing fix (CR-03) in `BackgroundRenderer.js` pre-fills the canvas with a solid/gradient color before drawing the image background with `globalAlpha`. This prevents white show-through for JPEG exports. However, if users later want transparent PNG exports, the pre-fill destroys transparency.

## Current State

`renderImage()` in `BackgroundRenderer.js` always fills the canvas with a background color before drawing the image. The export format selector (CR-07) supports PNG, but the rendering pipeline doesn't distinguish between opaque and transparent export targets.

## Assessment

**Low risk for current functionality.** The UI always has a background color configured, so users exporting as PNG will get a PNG with that background color — which is the expected behavior for the current feature set.

## Future Consideration

If transparent PNG exports are added as a feature:

1. Add a `transparentBackground` boolean to background state
2. In `renderImage()`, skip the background fill when `transparentBackground` is true
3. In `ExportManager`, clear the canvas with transparent black before rendering when exporting PNG with transparent background

No action needed for current commit. Document this interaction for future reference.

## Files (future)

- `MyESModules/Rendering/BackgroundRenderer.js` — conditional background fill
- `MyESModules/App/createExportHandlers.js` — pass transparency flag to render pipeline

---

# Complete Method Extraction from createCollageMethods

`createCollageMethods.js` (558 lines) still contains core rendering, crop preview, and undo/redo methods as closure functions. Per the Phase 5 plan (CR-12), these should be extracted into dedicated modules for better separation of concerns and testability.

## Current State

Lines 38-232 define closure functions:
- `_scheduleRender(vm)` — 36 lines of render orchestration
- `_buildBackgroundState(vm)` — 9 lines
- `_buildOverlayState(vm)` — 6 lines
- `_scheduleCropPreviewRender(vm)` — 104 lines of inline canvas rendering (DPR scaling, image contain math, dark overlay, border, corner handles, shaped overlay)
- `_updateUndoState(vm)` — 4 lines
- `_performUndo(vm)` — 8 lines
- `_performRedo(vm)` — 8 lines
- `_regenerateAndRender(vm)` — 5 lines

## Extract Into

1. **`MyESModules/App/createRenderMethods.js`** — `_scheduleRender`, `_buildBackgroundState`, `_buildOverlayState`, `_regenerateAndRender`
2. **`MyESModules/App/createCropPreviewRenderer.js`** — `_scheduleCropPreviewRender` (the ~104 line crop preview renderer)
3. **`MyESModules/App/createUndoMethods.js`** — `_updateUndoState`, `_performUndo`, `_performRedo`

## Requirements

- Each new module follows the existing factory pattern (exported function accepting `base` and any needed getters)
- Methods are composed into the main methods object in `createCollageMethods()` via spread or merge
- Existing Vue template bindings remain unchanged (method names stay the same)
- Barrel exports in `MyESModules/index.js` updated if needed
- All existing tests pass without modification

## Testing

`MyComponents/Phase5RefactoringTest.html` already tests method composition (Section 5.4). Add tests for the new individual modules.

---

# Export Progress — Loading Indicator

When users export large canvases, the `toBlob()` or `toDataURL()` process can take a second or two. Users may think the app has frozen if there is no visual feedback.

## Current State

`createExportHandlers.js` sets `this.isExporting = true` and `this.exportStatus = 'Exporting...'` before the export, and clears them in the `finally` block. The `index.html` template should reflect these states.

## Change

Ensure the UI reflects export progress:

1. **Button state:** Disable the Export button and show "Exporting..." while `isExporting` is true
2. **Success feedback:** Show a brief toast or status message: *"Collage exported!"* after successful export
3. **Error feedback:** Show a clear error message if export fails (e.g., canvas size limits, browser restrictions)

## Files

- `index.html` — bind `:disabled="isExporting"` on export button, add success/error toast elements
- `Style.css` — styles for disabled button and toast notifications
- `MyESModules/App/createExportHandlers.js` — verify `isExporting` and `exportStatus` are set correctly

## Testing

Manual test: export a collage with multiple images and verify loading state is visible. Add E2E test to `test/e2e/` verifying button is disabled during export.
