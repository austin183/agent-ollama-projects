# Pre-Merge Review Fixes — Implementation Plan

**Date:** 2026-07-19
**Source:** `_agent_docs/reviews/2026-07-19-pre-merge-final-review-barbara.md`
**Branch:** `prototype/collage-maker`
**Verdict:** REQUEST CHANGES — 1 critical blocking issue + 7 high-priority issues

---

## Overview

This plan addresses all issues from the final consolidated pre-merge review (Barbara, 12 parallel subagents). The review discovered one critical blocking issue that renders the undo/redo system completely non-functional, plus seven high-priority issues spanning interaction safety, callback patterns, and user feedback.

## Current State Analysis

### CR-1: Undo/Redo Completely Broken

`createUndoMethods.js` accesses `base.undoManager` (lines 23, 24, 25, 45, 47, 60, 62) but `CollageBase.js` has no `undoManager` property. The undo manager is created in `createCollageLifecycle.js:54` and stored only on the Vue instance as `this.undoManager`. Every undo/redo operation silently does nothing because the guard `if (!base.undoManager) return;` always returns early.

### H-4: createImagePanelHandlers bypasses callback pattern

`createImagePanelHandlers.js` calls `this._scheduleRender()` directly (lines 34, 45, 71) instead of accepting a render callback like all other handler modules. This makes it untestable in isolation and violates the established DIP pattern.

### H-5/H-6: CropInteraction pointer capture issues

- `setPointerCapture` at line 193 is unprotected by try-catch (can throw on unsupported browsers)
- `_onPointerUp` (line 263) never calls `releasePointerCapture` — all other handlers (PanelSwap, MultiTouchHandler, TitleInteraction) properly release capture

### H-2: Image load failures not reported

`ImageLibrary.js:41` logs `console.warn` when images fail to load, but provides no user-facing feedback.

### H-3: Storage full not handled

`SettingsPersistence.js:42-43` catches `QuotaExceededError` but only logs `console.warn`. No user notification.

### H-1: WCAG touch targets below 44x44px

Multiple interactive elements below the 44x44px WCAG minimum:
- `#themeToggle`: 40x40px (Style.css:369-370)
- `.toolbar-icon-btn`: 32x32px (Style.css:423-424)
- `.format-btn`: 32x32px (Style.css:624-626)
- `.remove-btn`: ~20x20px (Style.css:248-260)

### H-7: Deprecated removeImage() left in production

`ImageLibrary.js:70-75` — deprecated method still callable. No callers exist in the codebase (all use `disposeImage`), but it's a latent memory leak vector.

## Desired End State

After this plan is complete:
1. Undo/redo fully functional via keyboard shortcuts (Cmd+Z / Cmd+Shift+Z) and programmatic calls
2. All handler modules follow the callback injection pattern uniformly
3. CropInteraction properly manages pointer capture with error protection
4. Image load failures and storage quota issues produce user-visible toast notifications
5. Touch targets meet WCAG 44x44px minimum
6. Deprecated `removeImage()` removed from ImageLibrary

### Key Discoveries:
- `CollageBase.js` uses getter/setter pattern for all lazy services (lines 33-73) — undo manager should follow same pattern
- `createCollageLifecycle.js:54` creates `this.undoManager` but never calls `base.setUndoManager()`
- All other interaction handlers (PanelSwap, MultiTouchHandler, TitleInteraction) wrap `setPointerCapture` in try-catch and call `releasePointerCapture` in cleanup — CropInteraction is the sole outlier
- `createImagePanelHandlers` is the only handler module that doesn't accept a render callback
- `ImageLibrary.addImages` already has a `failedCount` variable (line 39) — just needs a callback to surface it
- `SettingsPersistence.save` already returns `false` on failure — the caller just needs to check the return value

## What We're NOT Doing

- **PWA features** (manifest.json, service worker) — explicitly deferred in review
- **Responsive breakpoints** — no mobile/tablet media queries (deferred)
- **Export DPR scaling** (M-4) — medium priority, follow-up
- **LayoutManager empty path** (M-2) — medium priority, follow-up
- **Lifecycle undo callbacks using actions.js** (M-3) — medium priority, follow-up
- **Dead `createDebugOverlay` factory** (M-5) — medium priority, follow-up
- **Incompatible `saliencyCrop` signatures** (M-7) — medium priority, follow-up
- **CropInfo.js layer dependency** (M-8) — medium priority, follow-up
- **generateThumbnail() in Models** (M-9) — medium priority, follow-up
- **validateManifest recommended fields** (M-10) — medium priority, follow-up
- **All nits (N-1 through N-34)** — optional polish, follow-up

---

## Phase 1: Wire up UndoManager (CR-1)

**Priority: P0 — BLOCKS MERGE**

### Overview

Add `getUndoManager()`/`setUndoManager()` to `CollageBase.js`, register the undo manager in `createCollageLifecycle.js`, and update `createUndoMethods.js` to use the getter pattern. This restores the entire undo/redo system.

### Changes Required:

#### 1. CollageBase.js — Add undo manager getter/setter

**File**: `MyESModules/App/CollageBase.js`

Add `undoManager` to the lazy service pattern alongside the other managers:

```javascript
// In the closure variables (after line 26):
let undoManager = null;

// In the return object (after setTitleManager, before layoutStyleOptions):
getUndoManager() {
    return undoManager;
},
setUndoManager(manager) {
    undoManager = manager;
},
```

**Line references**: Add closure variable after line 26 (`let titleManager = null;`). Add getters/setters after line 73 (`setTitleManager` block), before line 75 (`// Static data`).

#### 2. createCollageLifecycle.js — Register undo manager on base

**File**: `MyESModules/App/createCollageLifecycle.js`

After line 54 (`this.undoManager = createUndoManager();`), add:

```javascript
// Initialize undo manager
this.undoManager = createUndoManager();
base.setUndoManager(this.undoManager);
```

#### 3. createUndoMethods.js — Use getter instead of direct property access

**File**: `MyESModules/App/createUndoMethods.js`

Replace all 7 occurrences of `base.undoManager` with `base.getUndoManager()`:

- Line 23: `if (!base.undoManager) return;` → `if (!base.getUndoManager()) return;`
- Line 24: `vm.canUndo = base.undoManager.canUndo();` → `vm.canUndo = base.getUndoManager().canUndo();`
- Line 25: `vm.canRedo = base.undoManager.canRedo();` → `vm.canRedo = base.getUndoManager().canRedo();`
- Line 45: `if (!base.undoManager || !base.undoManager.canUndo()) return;` → `const um = base.getUndoManager(); if (!um || !um.canUndo()) return;`
- Line 47: `const hadUndo = base.undoManager.undo();` → `const hadUndo = um.undo();`
- Line 60: `if (!base.undoManager || !base.undoManager.canRedo()) return;` → `const um = base.getUndoManager(); if (!um || !um.canRedo()) return;`
- Line 62: `const hadRedo = base.undoManager.redo();` → `const hadRedo = um.redo();`

Using a local `um` variable avoids redundant getter calls and is consistent with the existing code style.

### Behavior Scenarios

#### User Behavior Level

| # | Given | When | Then |
|---|-------|------|------|
| 1.1.1 | Images are loaded and a panel is selected | User presses Cmd+Z after dragging a crop | The crop returns to its pre-drag position and the canvas re-renders |
| 1.1.2 | An undo is available | User presses Cmd+Shift+Z | The last undone action is re-applied and the canvas re-renders |
| 1.1.3 | No actions have been taken | User presses Cmd+Z | Nothing happens (no error, no visual change) |
| 1.1.4 | User swaps two panels via drag-and-drop | User presses Cmd+Z | The panels return to their pre-swap image assignments |
| 1.1.5 | User moves/resizes the title box | User presses Cmd+Z | The title box returns to its pre-interaction position and size |

#### Component Behavior Level

| # | Given | When | Then |
|---|-------|------|------|
| 1.2.1 | `base.setUndoManager(um)` has been called | `base.getUndoManager()` is called | Returns the same `um` instance |
| 1.2.2 | `base.getUndoManager()` is called before `setUndoManager` | — | Returns `null` |
| 1.2.3 | `createUndoMethods` is called with a base that has a registered undo manager | `_performUndo(vm)` is called with a command on the stack | The command's undo function executes, render callbacks fire, and `vm.canUndo`/`vm.canRedo` are updated |
| 1.2.4 | `base.getUndoManager()` returns `null` | `_performUndo(vm)` is called | Returns immediately without error |

#### Pure Function Level

| # | Given | When | Then |
|---|-------|------|------|
| 1.3.1 | `base` has `getUndoManager()` returning an `UndoManager` with 1 command | `createUndoMethods(base, callbacks)` → `_updateUndoState(vm)` | `vm.canUndo` is `true`, `vm.canRedo` is `false` |
| 1.3.2 | `base.getUndoManager()` returns `null` | `_updateUndoState(vm)` | No error thrown, `vm` properties unchanged |

### Test Scenarios

#### Unit Tests (existing + new)

| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.T.1 | `createUndoMethods` with `base.getUndoManager()` returning real UndoManager | UndoManager with 1 command | `_performUndo` executes undo, callbacks fire |
| 1.T.2 | `createUndoMethods` with `base.getUndoManager()` returning `null` | No undo manager | `_performUndo` returns silently |
| 1.T.3 | `createUndoMethods` redo path with `base.getUndoManager()` | UndoManager with 1 redo | `_performRedo` executes redo, callbacks fire |
| 1.T.4 | `CollageBase.getUndoManager()` before set | Fresh base | Returns `null` |
| 1.T.5 | `CollageBase.getUndoManager()` after set | Base with manager set | Returns the manager instance |

#### E2E Test Scenarios (Playwright)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 1.E.1 | Undo crop adjustment | 1. Load images, 2. Select panel, 3. Drag crop, 4. Press Cmd+Z | Crop returns to original position |
| 1.E.2 | Redo crop adjustment | 1. Load images, 2. Select panel, 3. Drag crop, 4. Cmd+Z, 5. Cmd+Shift+Z | Crop returns to dragged position |
| 1.E.3 | Undo panel swap | 1. Load 2+ images, 2. Drag panel to swap, 3. Cmd+Z | Panel assignments restored |
| 1.E.4 | Undo title move | 1. Enable title, 2. Drag title box, 3. Cmd+Z | Title box returns to original position |
| 1.E.5 | Undo with no history | 1. Fresh page, 2. Cmd+Z | No error, no visual change |

### Success Criteria:

#### Automated Verification:
- [ ] All 1,399 existing unit tests still pass
- [ ] New unit tests for `createUndoMethods` with getter pattern pass
- [ ] New unit tests for `CollageBase.getUndoManager()`/`setUndoManager()` pass
- [ ] Existing `UndoManagerTest.html` tests still pass (26 tests)

#### Manual Verification:
- [ ] Cmd+Z undoes crop drag on loaded images
- [ ] Cmd+Shift+Z redoes the undone crop
- [ ] Cmd+Z undoes panel swap
- [ ] Cmd+Z undoes title box move/resize
- [ ] Cmd+Z on fresh page does nothing (no error in console)
- [ ] Undo/redo button states update correctly in UI

---

## Phase 2: CropInteraction Pointer Capture (H-5, H-6)

**Priority: P1 — Interaction safety**

### Overview

Bring `CropInteraction` into alignment with the other three interaction handlers (PanelSwap, MultiTouchHandler, TitleInteraction) by wrapping `setPointerCapture` in try-catch and adding `releasePointerCapture` in `_onPointerUp`.

### Changes Required:

#### 1. CropInteraction.js — Protect setPointerCapture

**File**: `MyESModules/Interaction/CropInteraction.js`

Line 193 — replace:
```javascript
canvas.setPointerCapture(e.pointerId);
```
With:
```javascript
if (canvas.setPointerCapture) {
    try {
        canvas.setPointerCapture(e.pointerId);
    } catch (_) {
        // setPointerCapture not supported — pointer events still work
    }
}
```

#### 2. CropInteraction.js — Add releasePointerCapture

**File**: `MyESModules/Interaction/CropInteraction.js`

In `_onPointerUp` (line 263), add release before the existing logic:
```javascript
_onPointerUp(e) {
    // Release pointer capture to prevent stuck pointer state
    if (canvas && canvas.releasePointerCapture) {
        try { canvas.releasePointerCapture(e.pointerId); } catch (_) {}
    }

    if (isDragging || isResizing) {
        if (onDragEnd) onDragEnd();
        onRenderScheduled();
    }
    isDragging = false;
    isResizing = false;
    resizeCorner = null;
},
```

Also add release to `detach()` for cleanup safety:
```javascript
detach() {
    if (!handlerAttached) return;
    handlerAttached = false;

    // Release any captured pointer on detach
    if (canvas && canvas.releasePointerCapture) {
        try { canvas.releasePointerCapture(lastPointerId); } catch (_) {}
    }

    if (canvas) {
        canvas.removeEventListener('pointerdown', onPointerDown);
        // ... rest unchanged
    }
},
```

Track the last pointer ID in `_onPointerDown`:
```javascript
// Add near top of module:
let lastPointerId = undefined;

// In _onPointerDown, after setPointerCapture block:
lastPointerId = e.pointerId;
```

### Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 2.1.1 | Browser supports `setPointerCapture` | User starts a crop drag | Pointer is captured, drag continues outside canvas bounds |
| 2.1.2 | Browser does NOT support `setPointerCapture` | User starts a crop drag | No error thrown, drag works within canvas bounds |
| 2.1.3 | User completes a crop drag | Pointer up fires | Pointer capture is released |
| 2.1.4 | CropInteraction is detached while pointer is captured | `detach()` is called | Pointer capture is released, no stuck pointer state |

### Test Scenarios

| # | Test | Input | Expected |
|---|------|-------|----------|
| 2.T.1 | `_onPointerDown` with `setPointerCapture` supported | Canvas with `setPointerCapture` | Capture succeeds, no error |
| 2.T.2 | `_onPointerDown` without `setPointerCapture` | Canvas without `setPointerCapture` | No error, drag state still set |
| 2.T.3 | `_onPointerUp` releases capture | Canvas with capture | `releasePointerCapture` called once |
| 2.T.4 | `detach()` releases capture | Active handler with captured pointer | `releasePointerCapture` called on canvas |

### Success Criteria:

#### Automated Verification:
- [ ] All existing unit tests pass
- [ ] New CropInteraction pointer capture tests pass

#### Manual Verification:
- [ ] Crop drag works when pointer moves outside crop canvas
- [ ] No console errors on browsers without `setPointerCapture` support
- [ ] Detaching crop interaction doesn't leave pointer stuck

---

## Phase 3: createImagePanelHandlers Callback Pattern (H-4)

**Priority: P1 — Architectural consistency**

### Overview

Refactor `createImagePanelHandlers` to accept a render callback provider, matching the pattern used by all other handler modules (`createLayoutHandlers`, `createCropHandlers`, `createBackgroundHandlers`, etc.). This enables isolated unit testing and DIP compliance.

### Changes Required:

#### 1. createImagePanelHandlers.js — Accept render callback

**File**: `MyESModules/App/createImagePanelHandlers.js`

Change the factory signature to accept `onRenderScheduled`:

```javascript
export function createImagePanelHandlers(getImageLibrary, getLayoutManager, getCanvasRenderer, onRenderScheduled) {
```

Replace all `this._scheduleRender()` calls with callback invocation:

```javascript
// In removeImage (line 34):
onRenderScheduled(this);

// In clearAllImages (line 45):
onRenderScheduled(this);

// In removeSelectedImage (line 71):
onRenderScheduled(this);
```

Guard against missing callback:
```javascript
if (typeof onRenderScheduled === 'function') {
    onRenderScheduled(this);
}
```

#### 2. createCollageMethods.js — Pass render callback

**File**: `MyESModules/App/createCollageMethods.js`

Lines 62-66 — update the `createImagePanelHandlers` call:

```javascript
const imagePanelHandlers = createImagePanelHandlers(
    () => base.getImageLibrary(),
    () => base.getLayoutManager(),
    () => base.getCanvasRenderer(),
    (vm) => renderMethods._scheduleRender(vm)
);
```

### Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 3.1.1 | `createImagePanelHandlers` is called with a render callback | `removeImage(0)` is called | Image is removed, layout regenerated, render callback fires |
| 3.1.2 | `createImagePanelHandlers` is called without a render callback | `removeImage(0)` is called | Image is removed, layout regenerated, no error |
| 3.1.3 | `createImagePanelHandlers` is called with a render callback | `clearAllImages()` is called | All images cleared, layout regenerated, render callback fires |
| 3.1.4 | `createImagePanelHandlers` is called with a render callback | `removeSelectedImage()` is called with a selected panel | Image removed, selection cleared, layout regenerated, render callback fires |

### Test Scenarios

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.T.1 | `removeImage` fires render callback | Mock library, mock layout, callback spy | Callback called once after dispose + regenerate |
| 3.T.2 | `clearAllImages` fires render callback | Mock library, mock layout, callback spy | Callback called once after clear + regenerate |
| 3.T.3 | `removeSelectedImage` fires render callback | Mock library, mock layout, callback spy, selected panel | Callback called once after dispose + regenerate |
| 3.T.4 | `removeImage` without render callback | No callback provided | No error thrown |
| 3.T.5 | `selectImage` unchanged | Valid index | `selectedImageId` set correctly (no render callback needed) |

### Success Criteria:

#### Automated Verification:
- [ ] All existing unit tests pass
- [ ] New tests for `createImagePanelHandlers` with callback pattern pass

#### Manual Verification:
- [ ] Removing an image from the library triggers a canvas re-render
- [ ] Clearing all images triggers a canvas re-render
- [ ] Delete/Backspace on selected panel triggers a canvas re-render

---

## Phase 4: Image Load Failure Feedback (H-2)

**Priority: P1 — User experience**

### Overview

Surface image load failures to the user via a toast notification. `ImageLibrary.addImages` already tracks `failedCount` (line 39) but only logs to console. The caller (`createCollageLifecycle.js` and `createFileHandlers.js`) needs to receive failure information.

### Changes Required:

#### 1. ImageLibrary.js — Add onFailures callback

**File**: `MyESModules/State/ImageLibrary.js`

Update `addImages` signature to accept an optional `onFailures` callback:

```javascript
async addImages(files, onProgress, onFailures) {
```

After the existing `console.warn` (line 41), call the callback:

```javascript
if (failedCount > 0) {
    console.warn(`ImageLibrary: ${failedCount} of ${newItems.length} image(s) failed to load`);
    if (typeof onFailures === 'function') {
        onFailures(failedCount, newItems.length);
    }
}
```

#### 2. createCollageLifecycle.js — Wire failure callback in global drop

**File**: `MyESModules/App/createCollageLifecycle.js`

In the global drop handler (lines 261-274), add failure handling:

```javascript
await imageLibrary.addImages(files,
    (current, total) => {
        this.updateImageLoadingProgress(current, total);
    },
    (failedCount, totalCount) => {
        this.showToast(`${failedCount} of ${totalCount} image(s) failed to load`, 'error', 5000);
    }
);
```

#### 3. createFileHandlers.js — Wire failure callback in file input

**File**: `MyESModules/App/createFileHandlers.js`

Add the `onFailures` callback to the `addImages` call. The file handler factory needs a new parameter `onImageFailures`:

```javascript
export function createFileHandlers(getImageLibrary, onRegenerateAndRender, fileInputId, onProgress, onImageFailures) {
```

In `handleFileInputChange`, pass the callback:

```javascript
await imageLibrary.addImages(files,
    (current, total) => onProgress(this, current, total),
    (failedCount, totalCount) => {
        if (typeof onImageFailures === 'function') {
            onImageFailures(this, failedCount, totalCount);
        }
    }
);
```

#### 4. createCollageMethods.js — Pass failure callback to file handlers

**File**: `MyESModules/App/createCollageMethods.js`

Update the `createFileHandlers` call (lines 55-60):

```javascript
const fileHandlers = createFileHandlers(
    () => base.getImageLibrary(),
    (vm) => renderMethods._regenerateAndRender(vm),
    ids.fileInput,
    (vm, current, total) => vm._setImageLoadingProgress(current, total),
    (vm, failedCount, totalCount) => {
        vm.showToast(`${failedCount} of ${totalCount} image(s) failed to load`, 'error', 5000);
    }
);
```

### Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 4.1.1 | User drops a mix of valid and invalid image files | `addImages` processes the files | Valid images are added, a toast shows the failure count |
| 4.1.2 | User drops only invalid image files | `addImages` processes the files | No images added, toast shows all files failed |
| 4.1.3 | User selects files via file picker, some fail | `handleFileInputChange` runs | Valid images added, toast shows failure count |
| 4.1.4 | All images load successfully | `addImages` processes files | No toast shown |

### Test Scenarios

| # | Test | Input | Expected |
|---|------|-------|----------|
| 4.T.1 | `addImages` calls `onFailures` when some images fail | 3 files, 1 fails, `onFailures` spy | `onFailures(1, 3)` called |
| 4.T.2 | `addImages` does not call `onFailures` when all succeed | 3 files, all succeed | `onFailures` not called |
| 4.T.3 | `addImages` without `onFailures` callback | 3 files, 1 fails, no callback | No error thrown |
| 4.T.4 | `addImages` with all files failing | 3 files, all fail | `onFailures(3, 3)` called, no images added |

### Success Criteria:

#### Automated Verification:
- [ ] All existing unit tests pass
- [ ] New ImageLibrary failure callback tests pass

#### Manual Verification:
- [ ] Dropping a corrupted image file shows an error toast
- [ ] Dropping a non-image file (e.g., .txt) shows an error toast
- [ ] All valid images load without spurious error toasts

---

## Phase 5: Storage Full Handling (H-3)

**Priority: P1 — User experience**

### Overview

When `localStorage` quota is exceeded, show a user-visible toast notification instead of silently failing. The `save()` function already returns `false` on failure — the caller just needs to check the return value.

### Changes Required:

#### 1. createSettingsHandlers.js — Check save return value

**File**: `MyESModules/App/createSettingsHandlers.js`

In `_saveSettings` (line 17-44), check the return value of `saveSettings`:

```javascript
_saveSettings(state) {
    try {
        const success = saveSettings({
            layoutStyle: state.layoutStyle,
            // ... all existing fields ...
            exportQuality: state.exportQuality
        });
        if (!success && state.showToast) {
            state.showToast('Settings not saved — storage full', 'error', 5000);
        }
    } catch (e) {
        console.warn('Failed to save settings:', e);
    }
},
```

### Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 5.1.1 | localStorage has available space | Settings are saved | Save succeeds silently |
| 5.1.2 | localStorage quota is exceeded | Settings are saved | Error toast: "Settings not saved — storage full" |
| 5.1.3 | `showToast` is not available on state | Storage full | No error thrown, warning logged to console |

### Test Scenarios

| # | Test | Input | Expected |
|---|------|-------|----------|
| 5.T.1 | `_saveSettings` with `save` returning `true` | Normal save | No toast shown |
| 5.T.2 | `_saveSettings` with `save` returning `false` | Storage full | Error toast shown |
| 5.T.3 | `_saveSettings` with no `showToast` on state | Storage full | No error thrown |

### Success Criteria:

#### Automated Verification:
- [x] All existing unit tests pass
- [x] New settings handler tests for storage full scenario pass (5.T.1, 5.T.2, 5.T.3)

#### Manual Verification:
- [ ] (Hard to test manually — requires filling localStorage) Toast appears when quota exceeded

### Implementation Notes

- Factory refactored to accept `saveFn` parameter (DIP) for testability, with default fallback to imported `save`
- Uses explicit `success === false` check (not `!success`) for defensive boolean checking
- `typeof state.showToast === 'function'` guard prevents errors when state lacks toast capability
- Toast message, type ('error'), and duration (5000ms) consistent with image load failure toasts

---

## Phase 6: WCAG Touch Targets (H-1)

**Priority: P1 — Accessibility compliance**

### Overview

Increase minimum touch target sizes to meet WCAG 2.1 SC 2.5.8 (Target Size: Minimum 44x44 CSS pixels). This is a CSS-only change.

### Changes Required:

#### 1. Style.css — Increase touch target sizes

**File**: `Style.css`

**`#themeToggle`** (lines 364-381): Change from 40x40 to 44x44:
```css
#themeToggle {
    /* ... existing properties ... */
    min-width: 44px;
    min-height: 44px;
    /* ... */
}
```

**`.toolbar-icon-btn`** (lines 422-448): Change from 32x32 to 44x44:
```css
.toolbar-icon-btn {
    /* ... */
    min-width: 44px;
    min-height: 44px;
    /* ... */
}
```

**`.format-btn`** (lines 619-652): Change from 32x32 to 44x44:
```css
.format-btn {
    width: 44px;
    height: 44px;
    /* ... existing properties ... */
}
```

**`.remove-btn`** (lines 248-270): Increase padding to achieve 44x44 effective target:
```css
.remove-btn {
    /* ... existing properties ... */
    min-width: 44px;
    min-height: 44px;
    padding: var(--space-2);
    /* ... */
}
```

### Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 6.1.1 | User on a touch device | Taps theme toggle | Tap target is at least 44x44px |
| 6.1.2 | User on a touch device | Taps undo/redo toolbar buttons | Tap target is at least 44x44px |
| 6.1.3 | User on a touch device | Taps title format buttons (bold/italic/underline) | Tap target is at least 44x44px |
| 6.1.4 | User on a touch device | Taps remove button on an image | Tap target is at least 44x44px |

### Success Criteria:

#### Automated Verification:
- [ ] All existing unit tests pass (CSS changes don't affect JS tests)

#### Manual Verification:
- [ ] Theme toggle is at least 44x44px in browser dev tools
- [ ] Toolbar icon buttons are at least 44x44px
- [ ] Format buttons (bold/italic/underline) are at least 44x44px
- [ ] Remove buttons are at least 44x44px effective click area
- [ ] Layout doesn't break with larger touch targets

---

## Phase 7: Remove Deprecated `removeImage()` (H-7)

**Priority: P1 — Code hygiene**

### Overview

Remove the deprecated `removeImage()` method from `ImageLibrary.js`. No callers exist in the codebase (all use `disposeImage`).

### Changes Required:

#### 1. ImageLibrary.js — Remove deprecated method

**File**: `MyESModules/State/ImageLibrary.js`

Delete lines 65-75 (the `removeImage` method and its JSDoc):

```javascript
// DELETE THIS BLOCK:
/**
  * Removes an image at the given index (legacy, no cleanup).
  * @param {number} index
  * @deprecated Use disposeImage instead for proper cleanup
  */
removeImage(index) {
    console.warn('ImageLibrary.removeImage() is deprecated. Use disposeImage() for proper memory cleanup.');
    if (index < 0 || index >= state.images.length) return;
    state.images.splice(index, 1);
    onImagesChanged();
},
```

### Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 7.1.1 | `ImageLibrary.disposeImage(0)` is called | Valid index | Image disposed and removed (unchanged behavior) |
| 7.1.2 | Code attempts to call `ImageLibrary.removeImage()` | — | `TypeError: removeImage is not a function` (acceptable — no callers exist) |

### Success Criteria:

#### Automated Verification:
- [x] All existing unit tests pass (1,532 total, 0 failures)
- [x] New tests P7.1-P7.3 pass: `removeImage` is undefined, `disposeImage` removes + disposes, guard against out-of-range

#### Manual Verification:
- [x] Removing images from the library still works (via disposeImage path — verified by test P7.2)

---

## Testing Strategy

### Unit Tests

Each phase introduces new test scenarios. Tests follow the existing Mocha/Chai pattern in `MyComponents/`:

1. **Phase 1**: Update `UndoManagerTest.html` — add tests for `createUndoMethods` with getter pattern, add tests for `CollageBase` undo manager wiring
2. **Phase 2**: Add `CropInteractionPointerTest.html` — pointer capture/release tests
3. **Phase 3**: Add `ImagePanelHandlersTest.html` — callback injection tests
4. **Phase 4**: Add `ImageLibraryFailuresTest.html` — failure callback tests
5. **Phase 5**: Add `SettingsHandlersTest.html` — storage full toast tests
6. **Phase 6**: CSS-only — no unit tests needed
7. **Phase 7**: 3 new tests in `Phase4CodeQualityTest.html` (P7.1-P7.3): `removeImage` is undefined, `disposeImage` removes + disposes (with disposal verification), guard against out-of-range indices

### E2E Tests (Playwright)

Add to existing E2E spec files:
- **undo-redo.spec.js**: New file covering Cmd+Z / Cmd+Shift+Z for crop, swap, and title
- **image-loading.spec.js**: New file covering image load failure feedback

### Manual Testing Steps

1. Load images, drag a crop, press Cmd+Z — crop returns to original
2. Press Cmd+Shift+Z — crop returns to dragged position
3. Swap two panels, press Cmd+Z — panels restore
4. Move title box, press Cmd+Z — title restores
5. Drop a corrupted image file — error toast appears
6. Verify all touch targets are at least 44x44px in dev tools

## Performance Considerations

- **Phase 1**: Zero performance impact — getter/setter indirection is negligible
- **Phase 2**: Zero performance impact — try-catch only on pointer down/up (rare events)
- **Phase 3**: Zero performance impact — callback pattern is identical to existing handlers
- **Phase 4**: Minimal — one additional callback invocation per image batch
- **Phase 5**: Zero — one boolean check per save
- **Phase 6**: Zero — CSS-only changes
- **Phase 7**: Zero — dead code removal

## Migration Notes

All changes are additive or surgical. No data migration needed. The `removeImage()` removal (Phase 7) is the only breaking change, but no internal callers exist.

## References

- Review document: `_agent_docs/reviews/2026-07-19-pre-merge-final-review-barbara.md`
- Review plan: `_agent_docs/plans/2026-07-19-pre-merge-review-plan.md`
- Building-web-apps skill: `.opencode/skills/building-web-apps/SKILL.md` (factory testability patterns, pointer capture patterns)
- Existing pointer capture pattern: `PanelSwap.js:306-307,372-376`, `MultiTouchHandler.js:270-273,306-320,331-345`, `TitleInteraction.js:98-99,236-240`
