# Undo/Redo Expansion Implementation Plan

## Overview

Expand the undo/redo system from 3 actions (panel swap, crop drag, title move/resize) to ~20 user actions. The vast majority of edits (adding images, changing layout, editing title text, etc.) are currently not undoable. Additionally, the title move/resize undo command contains a closure bug that silently fails.

This plan follows the change request at `_agent_docs/specifications/change-requests/undo-redo-expansion.md` and incorporates UX review feedback from @world-review.

## Current State Analysis

### Existing Undo Infrastructure
- **UndoManager** (`MyESModules/State/UndoManager.js`): Command-pattern stack, max 60 levels, batching support
- **createUndoMethods** (`MyESModules/App/createUndoMethods.js`): Vue integration layer with `_updateUndoState`, `_performUndo`, `_performRedo`
- **createCollageMethods** (`MyESModules/App/createCollageMethods.js`): Composition point wiring all handler factories
- **CollageBase** (`MyESModules/App/CollageBase.js`): Lazy getter/setter for `undoManager`

### Currently Undoable Actions (3)
| # | Action | Location | Status |
|---|--------|----------|--------|
| 1 | Panel swap | `createCollageLifecycle.js:124-138` | Working |
| 2 | Crop drag | `createCollageLifecycle.js:142-182` | Working |
| 3 | Title move/resize | `createCollageLifecycle.js:200-246` | **Broken** (closure bug) |

### Actions Without Undo (~20)
All handler factory modules (`createFileHandlers`, `createImagePanelHandlers`, `createLayoutHandlers`, `createTitleHandlers`, `createBackgroundHandlers`, `createOverlayHandlers`) mutate state without pushing undo commands.

### Key Constraints
1. **Disposed images**: `ImageLibrary.disposeImage()` nulls `item.image` before splicing. Undoing a removal requires preserving the ImageItem reference.
2. **Handler decoupling**: Handler factories use callback injection (DIP). They don't have direct access to `this.undoManager`.
3. **Reactivity**: Vue reactive arrays must be mutated in-place (`splice`) not replaced, to maintain reactivity references.
4. **Layout regeneration**: Most undo operations need `_regenerateAndRender()` to update the canvas.

### Key Discoveries
- **Closure bug pattern** (`createCollageLifecycle.js:230-234`): `titleUndoSnapshot` is captured by reference in the undo closure, then set to `null` at line 244. The closure resolves to `null` when undo executes, causing a `TypeError`.
- **Safe patterns exist**: Crop drag (lines 164) and panel swap (lines 130-133) correctly copy values into local constants before building closures.
- **Reset crop undo is NOT wired**: `createCropHandlers.js:40-53` has a comment "We'll handle undo in the caller" but `createCollageMethods.js:163-165` doesn't push an undo command. This is a pre-existing gap.
- **TitleRuns deep copy**: `titleRuns` is an array of `{text, bold, italic, underline}` objects. Snapshot must deep-copy, not shallow-copy.

## Desired End State

After this plan is complete:
- All P0 actions (add images, remove image, clear all) are undoable via Cmd+Z/Ctrl+Z and toolbar buttons
- All P1 actions (layout style, layout options, title text, title formatting, title style, background, overlay) are undoable
- Title move/resize undo works correctly (closure bug fixed)
- Disposed-image guard shows a toast instead of crashing
- Layout options and title styles are batched per interaction to prevent undo fatigue
- Title text changes are captured on blur/Enter only (not per-keystroke)
- All existing tests continue to pass
- New tests cover each undoable action at unit level

### Key Discoveries:
- Handler factories need an `onUndoCommand` callback parameter (Option A from spec) to stay decoupled
- `ImageLibrary` needs a `removeImageAt(index)` method that returns the ImageItem without disposing it (for undo snapshot)
- Deep-copy utility needed for `titleRuns` arrays
- Batching state (pre-state snapshot) needs to be stored in the wiring layer, not in handler modules

## What We're NOT Doing

1. **History panel / undo list UI** — Users click undo step-by-step; no visual history browser
2. **Undo tooltips on buttons** — Nice-to-have for future iteration (identified by world-review)
3. **Image rotation/flip undo** — These actions don't exist in the UI yet
4. **Per-keystroke undo** — Title text changes captured on blur/Enter only
5. **Per-slider-tick undo** — Layout options batched per interaction
6. **Export undo** — Destructive action with no meaningful undo
7. **Multi-step undo jumping** — Step-by-step only

## Implementation Approach

### Architecture: Option A — Callback Injection

Handler factories receive an optional `onUndoCommand` callback. When a handler wants to make an action undoable, it calls:

```javascript
onUndoCommand({
    label: 'Action Name',
    preState: { /* snapshot of state before mutation */ },
    postState: { /* snapshot of state after mutation */ },
    undoFn: (vm) => { /* restore preState on vm */ },
    redoFn: (vm) => { /* restore postState on vm */ }
});
```

The wiring layer (`createCollageMethods.js`) provides the implementation that pushes to `this.undoManager` and calls `this._updateUndoState()`.

**Why Option A over Option B:**
- Keeps handler modules decoupled from UndoManager
- Preserves the callback injection pattern already used throughout the codebase
- Composition point (`createCollageMethods.js`) already knows about both handlers and undo manager
- Testable: handler modules can be tested with a mock `onUndoCommand` callback

### Batching Strategy

For actions that fire frequently (sliders, style controls), use a start/end pattern:
- **Start**: Snapshot pre-state, store in a module-level closure variable
- **End**: Capture post-state, call `onUndoCommand` if state changed

For title text changes:
- **Blur/Enter only**: Push command only when the title textarea loses focus or Enter is pressed

---

## Phase 1: Fix Title Undo Bug

### Overview
Fix the closure bug in `createCollageLifecycle.js` that prevents title move/resize undo from working. This is a surgical fix with minimal risk.

### Changes Required:

#### 1. Fix closure bug in title interaction
**File**: `MyESModules/App/createCollageLifecycle.js`
**Lines**: 216-244

Replace the `onInteractionEnd` callback to copy `titleUndoSnapshot` values into a local constant before building the closure:

```javascript
onInteractionEnd: () => {
    if (titleUndoSnapshot && this.undoManager) {
        const preState = {
            titleBoxX: titleUndoSnapshot.titleBoxX,
            titleBoxY: titleUndoSnapshot.titleBoxY,
            titleBoxWidth: titleUndoSnapshot.titleBoxWidth
        };
        const postState = {
            titleBoxX: this.titleStyle.titleBoxX,
            titleBoxY: this.titleStyle.titleBoxY,
            titleBoxWidth: this.titleStyle.titleBoxWidth
        };
        if (preState.titleBoxX !== postState.titleBoxX ||
            preState.titleBoxY !== postState.titleBoxY ||
            preState.titleBoxWidth !== postState.titleBoxWidth) {
            this.undoManager.push({
                label: 'Move/Resize Title',
                undo: () => {
                    this.titleStyle.titleBoxX = preState.titleBoxX;
                    this.titleStyle.titleBoxY = preState.titleBoxY;
                    this.titleStyle.titleBoxWidth = preState.titleBoxWidth;
                },
                redo: () => {
                    this.titleStyle.titleBoxX = postState.titleBoxX;
                    this.titleStyle.titleBoxY = postState.titleBoxY;
                    this.titleStyle.titleBoxWidth = postState.titleBoxWidth;
                }
            });
            this._updateUndoState();
        }
    }
    titleUndoSnapshot = null;
}
```

### Test Scenarios

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 1.1.1 | Images are loaded and title text is set | User drags the title box to a new position, releases, presses Cmd+Z | Title box returns to original position |
| 1.1.2 | Title box was just moved and undone | User presses Cmd+Shift+Z | Title box returns to the moved position |
| 1.1.3 | Title box is at default position | User drags title box edge to resize, releases, presses Cmd+Z | Title box width returns to original |
| 1.1.4 | Title move/resize command is on undo stack | User performs a different action (e.g., crop reset) | Redo stack is cleared (standard undo behavior) |

#### Unit Test Scenarios

| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.2.1 | Title undo closure captures correct values | Snapshot `{titleBoxX: 100, titleBoxY: 200, titleBoxWidth: 500}`, post-state `{titleBoxX: 300, titleBoxY: 400, titleBoxWidth: 600}` | Undo function restores `{100, 200, 500}`, redo restores `{300, 400, 600}` |
| 1.2.2 | Title undo does not crash when snapshot is null | `titleUndoSnapshot` is null after `onInteractionEnd` fires | No TypeError thrown |
| 1.2.3 | Title undo is not pushed when nothing changed | Pre-state equals post-state | No command pushed to undo manager |

### Success Criteria:

#### Automated Verification:
- [ ] All existing tests pass (1,382+)
- [ ] New unit test: title undo restores correct values
- [ ] New unit test: title undo does not crash with null snapshot
- [ ] New unit test: no command pushed when title unchanged

#### Manual Verification:
- [ ] Load images, set title, drag title box, Cmd+Z restores position
- [ ] Resize title box, Cmd+Z restores width
- [ ] Cmd+Shift+Z re-applies the move/resize
- [ ] No console errors during undo/redo

---

## Phase 2: Image Operations (P0 — Core)

### Overview
Add undo support for the three most user-facing image operations: add images, remove image, and clear all images. This phase introduces the `onUndoCommand` callback pattern and the disposed-image guard.

### Changes Required:

#### 1. Add `onUndoCommand` callback to handler factories
**File**: `MyESModules/App/createFileHandlers.js`

Add optional `onUndoCommand` parameter to `createFileHandlers`:
```javascript
export function createFileHandlers(getImageLibrary, onRegenerate, fileInputId = 'fileInput', onImageLoadingProgress = null, onImageFailures = null, onUndoCommand = null)
```

In `handleFileInputChange`, snapshot `images` and `crops` before `addImages()`, then after successful load, call `onUndoCommand`:
```javascript
// Before addImages:
const preImages = [...this.images];
const preCrops = JSON.parse(JSON.stringify(this.crops));

// After addImages resolves:
if (onUndoCommand && this.images.length > preImages.length) {
    const addedItems = this.images.slice(preImages.length);
    const addedImageIds = addedItems.map(item => item.id);
    onUndoCommand({
        label: 'Add Images',
        undoFn: (vm) => {
            // Remove added images (from end, in reverse order)
            for (let i = vm.images.length - 1; i >= 0; i--) {
                if (addedImageIds.includes(vm.images[i].id)) {
                    vm.imageLibrary.disposeImage(i);
                }
            }
            // Restore pre-state crops
            vm.crops.length = 0;
            vm.crops.push(...preCrops);
            vm._regenerateAndRender();
        },
        redoFn: (vm) => {
            // Re-adding images is not possible (File objects are gone)
            // Restore to post-state crops at minimum
            vm.crops.length = 0;
            vm.crops.push(...JSON.parse(JSON.stringify(this.crops)));
            vm._regenerateAndRender();
        }
    });
}
```

**Note**: The redo for "Add Images" cannot re-add the original File objects. The redo function restores the crop state but not the images themselves. This is acceptable — the user can re-add images manually.

#### 2. Add `onUndoCommand` callback to image panel handlers
**File**: `MyESModules/App/createImagePanelHandlers.js`

Add optional `onUndoCommand` parameter to `createImagePanelHandlers`:
```javascript
export function createImagePanelHandlers(getImageLibrary, getLayoutManager, getCanvasRenderer, onRenderScheduled, onUndoCommand = null)
```

In `removeImage(index)`:
```javascript
removeImage(index) {
    const imageLibrary = getImageLibrary();
    const layoutManager = getLayoutManager();
    
    // Snapshot before disposal
    const removedItem = this.images[index] ? { ...this.images[index] } : null;
    const removedIndex = index;
    const preImagesCount = this.images.length;
    const preCrops = JSON.parse(JSON.stringify(this.crops));
    
    if (imageLibrary) imageLibrary.disposeImage(index);
    if (layoutManager) layoutManager.regenerate();
    
    if (onUndoCommand && removedItem) {
        const postCrops = JSON.parse(JSON.stringify(this.crops));
        onUndoCommand({
            label: 'Remove Image',
            undoFn: (vm) => {
                if (!removedItem.image) {
                    // Image element was disposed — cannot restore
                    if (vm.showToast) {
                        vm.showToast('Cannot undo — image data no longer available', 'error', 5000);
                    }
                    return;
                }
                // Re-insert at original index
                vm.images.splice(removedIndex, 0, removedItem);
                vm.crops.length = 0;
                vm.crops.push(...preCrops);
                if (vm.layoutManager) vm.layoutManager.regenerate();
                vm._scheduleRender();
            },
            redoFn: (vm) => {
                // Re-remove the image
                const idx = vm.images.findIndex(img => img.id === removedItem.id);
                if (idx !== -1) {
                    vm.imageLibrary.disposeImage(idx);
                    vm.crops.length = 0;
                    vm.crops.push(...postCrops);
                    if (vm.layoutManager) vm.layoutManager.regenerate();
                    vm._scheduleRender();
                }
            }
        });
    }
    
    if (typeof onRenderScheduled === 'function') {
        onRenderScheduled(this);
    }
}
```

In `clearAllImages()`:
```javascript
clearAllImages() {
    const imageLibrary = getImageLibrary();
    const layoutManager = getLayoutManager();
    
    // Snapshot before clearing
    const savedItems = this.images.map(item => ({ ...item }));
    const preCrops = JSON.parse(JSON.stringify(this.crops));
    
    if (imageLibrary) imageLibrary.clearAll();
    if (layoutManager) layoutManager.regenerate();
    
    if (onUndoCommand && savedItems.length > 0) {
        const postCrops = JSON.parse(JSON.stringify(this.crops));
        onUndoCommand({
            label: 'Clear All Images',
            undoFn: (vm) => {
                const stillValid = savedItems.filter(item => item.image !== null);
                if (stillValid.length === 0) {
                    if (vm.showToast) {
                        vm.showToast('Cannot undo — image data no longer available', 'error', 5000);
                    }
                    return;
                }
                vm.images.push(...stillValid);
                vm.crops.length = 0;
                vm.crops.push(...preCrops);
                if (vm.layoutManager) vm.layoutManager.regenerate();
                vm._scheduleRender();
            },
            redoFn: (vm) => {
                // Re-clear
                const idsToRemove = savedItems.map(item => item.id);
                for (let i = vm.images.length - 1; i >= 0; i--) {
                    if (idsToRemove.includes(vm.images[i].id)) {
                        vm.imageLibrary.disposeImage(i);
                    }
                }
                vm.crops.length = 0;
                vm.crops.push(...postCrops);
                if (vm.layoutManager) vm.layoutManager.regenerate();
                vm._scheduleRender();
            }
        });
    }
    
    if (typeof onRenderScheduled === 'function') {
        onRenderScheduled(this);
    }
}
```

Apply the same pattern to `removeSelectedImage()`.

#### 3. Wire `onUndoCommand` in `createCollageMethods.js`
**File**: `MyESModules/App/createCollageMethods.js`

Create a shared `onUndoCommand` implementation:
```javascript
function pushUndoCommand({ label, undoFn, redoFn }) {
    if (this.undoManager) {
        this.undoManager.push({
            label,
            undo: () => {
                try { undoFn(this); } catch (e) {
                    console.error(`Undo error (${label}):`, e);
                    if (this.showToast) {
                        this.showToast('Undo failed: ' + e.message, 'error', 5000);
                    }
                }
            },
            redo: () => {
                try { redoFn(this); } catch (e) {
                    console.error(`Redo error (${label}):`, e);
                }
            }
        });
        this._updateUndoState();
    }
}
```

Pass it to handler factories:
```javascript
const fileHandlers = createFileHandlers(
    () => base.getImageLibrary(),
    (vm) => renderMethods._regenerateAndRender(vm),
    ids.fileInput,
    (vm, current, total) => vm._setImageLoadingProgress(current, total),
    (vm, failedCount, totalCount) => {
        vm.showToast(`${failedCount} of ${totalCount} image(s) failed to load`, 'error', 5000);
    },
    (cmd) => pushUndoCommand.call(this, cmd)  // NEW
);

const imagePanelHandlers = createImagePanelHandlers(
    () => base.getImageLibrary(),
    () => base.getLayoutManager(),
    () => base.getCanvasRenderer(),
    (vm) => renderMethods._scheduleRender(vm),
    (cmd) => pushUndoCommand.call(this, cmd)  // NEW
);
```

**Important**: `pushUndoCommand` uses `.call(this, cmd)` where `this` is the Vue instance. This is wired in the return object's wrapper functions, not at factory creation time. We need a different approach — use a closure that captures a getter for the undo manager:

```javascript
// In createCollageMethods.js, inside the function body:
const pushUndoCommand = (cmd) => {
    // This will be called with `this` bound to Vue instance via .call()
    // But since it's a factory-level function, we need to pass vm explicitly
};
```

Actually, the cleaner approach: the `onUndoCommand` callback receives the Vue instance as context. The handler calls `onUndoCommand(cmd)` and the wiring layer pushes:

```javascript
// In createCollageMethods.js wiring:
const fileHandlers = createFileHandlers(
    () => base.getImageLibrary(),
    (vm) => renderMethods._regenerateAndRender(vm),
    ids.fileInput,
    (vm, current, total) => vm._setImageLoadingProgress(current, total),
    (vm, failedCount, totalCount) => {
        vm.showToast(`${failedCount} of ${totalCount} image(s) failed to load`, 'error', 5000);
    },
    (vm, cmd) => {
        if (vm.undoManager) {
            vm.undoManager.push({
                label: cmd.label,
                undo: () => {
                    try { cmd.undoFn(vm); } catch (e) {
                        console.error(`Undo error (${cmd.label}):`, e);
                        if (vm.showToast) vm.showToast('Undo failed: ' + e.message, 'error', 5000);
                    }
                },
                redo: () => {
                    try { cmd.redoFn(vm); } catch (e) {
                        console.error(`Redo error (${cmd.label}):`, e);
                    }
                }
            });
            vm._updateUndoState();
        }
    }
);
```

Handler calls: `onUndoCommand(this, { label, undoFn, redoFn })`

### Test Scenarios

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 2.1.1 | No images loaded | User adds 3 images via file picker | Images appear, undo button enabled |
| 2.1.2 | 3 images loaded via file picker | User presses Cmd+Z | All 3 images removed, undo button disabled, redo button enabled |
| 2.1.3 | 5 images loaded | User removes image at index 2 via X button | Image removed, undo button enabled |
| 2.1.4 | Image was removed in 2.1.3 | User presses Cmd+Z | Image restored at original index |
| 2.1.5 | Image was removed, image element was nulled by browser | User presses Cmd+Z | Toast shows "Cannot undo — image data no longer available" |
| 2.1.6 | 5 images loaded | User clicks "Clear All" | All images removed, undo button enabled |
| 2.1.7 | Images were cleared in 2.1.6 | User presses Cmd+Z | All images restored |
| 2.1.8 | User adds images, then removes one, then adds more | User presses Cmd+Z repeatedly | Each undo reverses the most recent action |
| 2.1.9 | User adds images via drag-and-drop | User presses Cmd+Z | Dropped images removed (same as file picker) |

#### Unit Test Scenarios

| # | Test | Input | Expected |
|---|------|-------|----------|
| 2.2.1 | Add images pushes undo command | 3 images added | `onUndoCommand` called with label "Add Images" |
| 2.2.2 | Add images undo removes only added images | 2 existing + 3 added, undo | 2 existing remain, 3 added removed |
| 2.2.3 | Remove image pushes undo command | Image at index 1 removed | `onUndoCommand` called with label "Remove Image" |
| 2.2.4 | Remove image undo restores image | Image removed then undone | Image at original index, crops restored |
| 2.2.5 | Remove image undo with disposed element | `removedItem.image === null` | Toast shown, no crash |
| 2.2.6 | Clear all pushes undo command | 5 images cleared | `onUndoCommand` called with label "Clear All Images" |
| 2.2.7 | Clear all undo restores all images | 5 images cleared then undone | All 5 images restored |
| 2.2.8 | Clear all undo with all disposed | All `item.image === null` | Toast shown, no crash |
| 2.2.9 | Multiple adds grouped per batch | 2 separate file picker operations | 2 separate undo commands (not merged) |
| 2.2.10 | Redo stack cleared on new action | Undo, then new action | Redo button disabled |

#### E2E Test Scenarios

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 2.3.1 | Add images undo | Load app, add 3 images, Cmd+Z | Images gone, undo disabled |
| 2.3.2 | Remove image undo | Load app, add 3 images, remove middle, Cmd+Z | Middle image restored |
| 2.3.3 | Clear all undo | Load app, add 3 images, clear all, Cmd+Z | All images restored |

### Success Criteria:

#### Automated Verification:
- [ ] All existing tests pass
- [ ] New unit tests for add/remove/clear undo commands pass
- [ ] New unit tests for disposed-image guard pass
- [ ] No console errors during undo/redo

#### Manual Verification:
- [ ] Add images → Cmd+Z removes them → Cmd+Shift+Z (redo shows toast or no-ops since files are gone)
- [ ] Remove image → Cmd+Z restores it
- [ ] Clear all → Cmd+Z restores all
- [ ] Disposed image scenario: remove image, navigate away and back, try undo → toast shown

---

## Phase 3: Layout Changes (P1)

### Overview
Add undo support for layout style changes and layout options (gutter, slice angle, hex spacing, hex size multiplier). Layout options are batched per interaction to prevent undo fatigue.

### Changes Required:

#### 1. Add `onUndoCommand` to `createLayoutHandlers`
**File**: `MyESModules/App/createLayoutHandlers.js`

Add optional `onUndoCommand` parameter:
```javascript
export function createLayoutHandlers(getLayoutManager, onRenderScheduled, onUndoCommand = null)
```

**Layout style change** — straightforward, each change is a separate command:
```javascript
onLayoutStyleChange() {
    const preStyle = this.layoutStyle;
    const layoutManager = getLayoutManager();
    if (layoutManager) layoutManager.setLayoutStyle(this.layoutStyle);
    
    if (onUndoCommand && this.layoutStyle !== preStyle) {
        const postStyle = this.layoutStyle;
        onUndoCommand(this, {
            label: 'Change Layout',
            undoFn: (vm) => {
                vm.layoutStyle = preStyle;
                if (vm.layoutManager) vm.layoutManager.setLayoutStyle(preStyle);
                vm._scheduleRender();
            },
            redoFn: (vm) => {
                vm.layoutStyle = postStyle;
                if (vm.layoutManager) vm.layoutManager.setLayoutStyle(postStyle);
                vm._scheduleRender();
            }
        });
    }
    
    onRenderScheduled(this);
}
```

**Layout options** — batched per interaction. Since slider changes fire `input` events continuously, we need a start/end pattern. The handler module introduces a closure variable for the pre-state snapshot:

```javascript
export function createLayoutHandlers(getLayoutManager, onRenderScheduled, onUndoCommand = null) {
    let layoutOptionsSnapshot = null;
    let layoutOptionsPending = false;
    
    function snapshotLayoutOptions(vm) {
        if (!layoutOptionsSnapshot) {
            layoutOptionsSnapshot = {
                gutter: vm.gutter,
                sliceAngle: vm.sliceAngle,
                hexSpacing: vm.hexSpacing,
                hexSizeMultiplier: vm.hexSizeMultiplier
            };
            layoutOptionsPending = false;
        }
    }
    
    function pushLayoutOptionsUndo(vm) {
        if (layoutOptionsSnapshot && onUndoCommand) {
            const preState = { ...layoutOptionsSnapshot };
            const postState = {
                gutter: vm.gutter,
                sliceAngle: vm.sliceAngle,
                hexSpacing: vm.hexSpacing,
                hexSizeMultiplier: vm.hexSizeMultiplier
            };
            // Only push if something changed
            if (preState.gutter !== postState.gutter ||
                preState.sliceAngle !== postState.sliceAngle ||
                preState.hexSpacing !== postState.hexSpacing ||
                preState.hexSizeMultiplier !== postState.hexSizeMultiplier) {
                onUndoCommand(vm, {
                    label: 'Adjust Layout Options',
                    undoFn: (v) => {
                        v.gutter = preState.gutter;
                        v.sliceAngle = preState.sliceAngle;
                        v.hexSpacing = preState.hexSpacing;
                        v.hexSizeMultiplier = preState.hexSizeMultiplier;
                        if (v.layoutManager) {
                            v.layoutManager.setGutter(preState.gutter);
                            v.layoutManager.setSliceAngle(preState.sliceAngle);
                            v.layoutManager.setHexSpacing(preState.hexSpacing);
                            v.layoutManager.setHexSizeMultiplier(preState.hexSizeMultiplier);
                            v.layoutManager.regenerate();
                        }
                        v._scheduleRender();
                    },
                    redoFn: (v) => {
                        v.gutter = postState.gutter;
                        v.sliceAngle = postState.sliceAngle;
                        v.hexSpacing = postState.hexSpacing;
                        v.hexSizeMultiplier = postState.hexSizeMultiplier;
                        if (v.layoutManager) {
                            v.layoutManager.setGutter(postState.gutter);
                            v.layoutManager.setSliceAngle(postState.sliceAngle);
                            v.layoutManager.setHexSpacing(postState.hexSpacing);
                            v.layoutManager.setHexSizeMultiplier(postState.hexSizeMultiplier);
                            v.layoutManager.regenerate();
                        }
                        v._scheduleRender();
                    }
                });
            }
        }
        layoutOptionsSnapshot = null;
        layoutOptionsPending = false;
    }
    
    return {
        onLayoutStyleChange() { /* ... as above ... */ },
        
        onGutterChange() {
            snapshotLayoutOptions(this);
            const layoutManager = getLayoutManager();
            if (layoutManager) layoutManager.setGutter(this.gutter);
            onRenderScheduled(this);
        },
        
        onSliceAngleChange() {
            snapshotLayoutOptions(this);
            const layoutManager = getLayoutManager();
            if (layoutManager) layoutManager.setSliceAngle(this.sliceAngle);
            onRenderScheduled(this);
        },
        
        onHexSpacingChange() {
            snapshotLayoutOptions(this);
            const layoutManager = getLayoutManager();
            if (layoutManager) layoutManager.setHexSpacing(this.hexSpacing);
            onRenderScheduled(this);
        },
        
        onHexSizeMultiplierChange() {
            snapshotLayoutOptions(this);
            const layoutManager = getLayoutManager();
            if (layoutManager) layoutManager.setHexSizeMultiplier(this.hexSizeMultiplier);
            onRenderScheduled(this);
        },
        
        /**
         * Called when the user finishes interacting with layout option controls.
         * Commits the batched layout options change to the undo stack.
         */
        commitLayoutOptions() {
            pushLayoutOptionsUndo(this);
        }
    };
}
```

#### 2. Wire layout options batching in the template
**File**: `index.html`

Add `@blur` and `@change` handlers to layout option inputs to trigger `commitLayoutOptions()`:
```html
<!-- Gutter slider -->
<input type="range" v-model.number="gutter" @input="onGutterChange" @blur="commitLayoutOptions">

<!-- Slice angle slider -->
<input type="range" v-model.number="sliceAngle" @input="onSliceAngleChange" @blur="commitLayoutOptions">

<!-- Hex spacing slider -->
<input type="range" v-model.number="hexSpacing" @input="onHexSpacingChange" @blur="commitLayoutOptions">
```

**Note**: If the template uses `@change` instead of `@input` for sliders, the batching is automatic (change fires on release). If it uses `@input`, we need the `@blur` pattern. Check the current template binding.

#### 3. Wire `onUndoCommand` in `createCollageMethods.js`
```javascript
const layoutHandlers = createLayoutHandlers(
    () => base.getLayoutManager(),
    (vm) => renderMethods._scheduleRender(vm),
    (vm, cmd) => {
        if (vm.undoManager) {
            vm.undoManager.push({
                label: cmd.label,
                undo: () => { try { cmd.undoFn(vm); } catch (e) { console.error('Undo error:', e); } },
                redo: () => { try { cmd.redoFn(vm); } catch (e) { console.error('Redo error:', e); } }
            });
            vm._updateUndoState();
        }
    }
);
```

Expose `commitLayoutOptions` in the return object.

### Test Scenarios

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 3.1.1 | Images loaded, layout is "grid" | User changes layout to "hex" | Layout changes, undo button enabled |
| 3.1.2 | Layout changed to "hex" in 3.1.1 | User presses Cmd+Z | Layout reverts to "grid" |
| 3.1.3 | Gutter slider at default value | User drags gutter slider to new value, releases | Layout updates continuously during drag, single undo command on release |
| 3.1.4 | Gutter was adjusted in 3.1.3 | User presses Cmd+Z | Gutter reverts to previous value |
| 3.1.5 | User adjusts gutter, then slice angle, then hex spacing in one session | User presses Cmd+Z | All three options revert together (batched) |
| 3.1.6 | Layout options adjusted, then user changes layout style | User presses Cmd+Z | Only layout style reverts (options batch was already committed) |

#### Unit Test Scenarios

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.2.1 | Layout style change pushes undo | Style changed from "grid" to "hex" | Command with label "Change Layout" pushed |
| 3.2.2 | Layout style undo restores previous | Undo after style change | `layoutStyle` is previous value |
| 3.2.3 | Layout style redo restores new | Redo after undo | `layoutStyle` is new value |
| 3.2.4 | Gutter change snapshots pre-state | Gutter changed from 10 to 20 | Snapshot captures gutter=10 |
| 3.2.5 | Multiple option changes batch into one | Gutter + angle + spacing changed | Single "Adjust Layout Options" command |
| 3.2.6 | No command pushed when options unchanged | Slider moved but value didn't change | No undo command pushed |
| 3.2.7 | commitLayoutOptions pushes batched command | Options changed, commit called | Command pushed with correct pre/post states |
| 3.2.8 | commitLayoutOptions is idempotent | Called when no snapshot exists | No error, no command pushed |

### Success Criteria:

#### Automated Verification:
- [ ] All existing tests pass
- [ ] New unit tests for layout style undo pass
- [ ] New unit tests for layout options batching pass
- [ ] No console errors during undo/redo

#### Manual Verification:
- [ ] Change layout → Cmd+Z reverts → Cmd+Shift+Z re-applies
- [ ] Adjust gutter slider → release → Cmd+Z reverts gutter
- [ ] Adjust multiple options → Cmd+Z reverts all together
- [ ] Change layout after adjusting options → undo only reverts layout change

---

## Phase 4: Title & Styling (P1)

### Overview
Add undo support for title text (blur/Enter), title formatting, title style (batched), background changes, and overlay changes.

### Changes Required:

#### 1. Title handlers with undo
**File**: `MyESModules/App/createTitleHandlers.js`

Add `onUndoCommand` parameter:
```javascript
export function createTitleHandlers(getTitleManager, onRenderScheduled, onUndoCommand = null)
```

**Title text change** — captured on blur/Enter only. The handler module adds a new method `commitTitleText()`:

```javascript
let titleTextSnapshot = null;

// In onTitleTextChange():
onTitleTextChange() {
    if (!titleTextSnapshot) {
        titleTextSnapshot = {
            titleText: this.titleText,
            titleRuns: JSON.parse(JSON.stringify(this.titleRuns || []))
        };
    }
    const titleManager = getTitleManager();
    if (titleManager) {
        const result = titleManager.setText(this.titleText);
        if (result && result.truncated && this.showToast) {
            this.showToast('Title limited to 3 lines', 'info', 3000);
        }
    }
    onRenderScheduled(this);
}

commitTitleText() {
    if (titleTextSnapshot && onUndoCommand) {
        const preState = {
            titleText: titleTextSnapshot.titleText,
            titleRuns: JSON.parse(JSON.stringify(titleTextSnapshot.titleRuns))
        };
        const postState = {
            titleText: this.titleText,
            titleRuns: JSON.parse(JSON.stringify(this.titleRuns || []))
        };
        if (preState.titleText !== postState.titleText) {
            onUndoCommand(this, {
                label: 'Edit Title',
                undoFn: (vm) => {
                    vm.titleText = preState.titleText;
                    vm.titleRuns.length = 0;
                    vm.titleRuns.push(...preState.titleRuns);
                    vm._scheduleRender();
                },
                redoFn: (vm) => {
                    vm.titleText = postState.titleText;
                    vm.titleRuns.length = 0;
                    vm.titleRuns.push(...postState.titleRuns);
                    vm._scheduleRender();
                }
            });
        }
    }
    titleTextSnapshot = null;
}
```

**Title formatting** — each toggle is a separate command:
```javascript
toggleTitleBold() {
    const start = Math.min(this.titleSelectionStart, this.titleSelectionEnd);
    const end = Math.max(this.titleSelectionStart, this.titleSelectionEnd);
    const titleManager = getTitleManager();
    if (titleManager && start < end) {
        const preRuns = JSON.parse(JSON.stringify(this.titleRuns || []));
        const preText = this.titleText;
        titleManager.toggleBold(start, end);
        this.titleText = titleManager.getFullText();
        
        if (onUndoCommand) {
            const postRuns = JSON.parse(JSON.stringify(this.titleRuns || []));
            const postText = this.titleText;
            onUndoCommand(this, {
                label: 'Format Title',
                undoFn: (vm) => {
                    vm.titleText = preText;
                    vm.titleRuns.length = 0;
                    vm.titleRuns.push(...preRuns);
                    vm._scheduleRender();
                },
                redoFn: (vm) => {
                    vm.titleText = postText;
                    vm.titleRuns.length = 0;
                    vm.titleRuns.push(...postRuns);
                    vm._scheduleRender();
                }
            });
        }
        
        onRenderScheduled(this);
    }
}
```

Apply same pattern to `toggleTitleItalic` and `toggleTitleUnderline`.

**Title style changes** — batched per interaction:
```javascript
let titleStyleSnapshot = null;

function snapshotTitleStyle(vm) {
    if (!titleStyleSnapshot) {
        titleStyleSnapshot = { ...vm.titleStyle };
    }
}

function pushTitleStyleUndo(vm) {
    if (titleStyleSnapshot && onUndoCommand) {
        const preState = { ...titleStyleSnapshot };
        const postState = { ...vm.titleStyle };
        // Check if anything changed
        let changed = false;
        for (const key of Object.keys(preState)) {
            if (preState[key] !== postState[key]) { changed = true; break; }
        }
        if (changed) {
            onUndoCommand(vm, {
                label: 'Change Title Style',
                undoFn: (v) => {
                    for (const key of Object.keys(preState)) {
                        v.titleStyle[key] = preState[key];
                    }
                    v._scheduleRender();
                },
                redoFn: (v) => {
                    for (const key of Object.keys(postState)) {
                        v.titleStyle[key] = postState[key];
                    }
                    v._scheduleRender();
                }
            });
        }
    }
    titleStyleSnapshot = null;
}
```

Each style handler calls `snapshotTitleStyle(this)` before mutating. A new `commitTitleStyle()` method pushes the batched command.

#### 2. Background handlers with undo
**File**: `MyESModules/App/createBackgroundHandlers.js`

Add `onUndoCommand` parameter. Each background change pushes a command:

```javascript
export function createBackgroundHandlers(getBackgroundManager, onRenderScheduled, onUndoCommand = null)
```

For each method, snapshot the pre-state background config, perform the change, then push undo:
```javascript
onBackgroundStyleChange() {
    const preState = {
        backgroundStyle: this.backgroundStyle,
        backgroundColor: this.backgroundColor,
        gradientColors: this.gradientColors ? [...this.gradientColors] : null,
        gradientAngle: this.gradientAngle,
        backgroundImage: this.backgroundImage,
        backgroundOpacity: this.backgroundOpacity
    };
    
    const backgroundManager = getBackgroundManager();
    if (backgroundManager) backgroundManager.updateStyle(this.backgroundStyle);
    
    if (onUndoCommand) {
        const postState = {
            backgroundStyle: this.backgroundStyle,
            backgroundColor: this.backgroundColor,
            gradientColors: this.gradientColors ? [...this.gradientColors] : null,
            gradientAngle: this.gradientAngle,
            backgroundImage: this.backgroundImage,
            backgroundOpacity: this.backgroundOpacity
        };
        onUndoCommand(this, {
            label: 'Change Background',
            undoFn: (vm) => {
                vm.backgroundStyle = preState.backgroundStyle;
                vm.backgroundColor = preState.backgroundColor;
                vm.gradientColors = preState.gradientColors;
                vm.gradientAngle = preState.gradientAngle;
                vm.backgroundImage = preState.backgroundImage;
                vm.backgroundOpacity = preState.backgroundOpacity;
                const bm = vm.backgroundManager;
                if (bm) {
                    bm.updateStyle(preState.backgroundStyle);
                    bm.setColor(preState.backgroundColor);
                    if (preState.gradientColors) bm.setGradientColors(preState.gradientColors[0], preState.gradientColors[1]);
                    bm.setAngle(preState.gradientAngle);
                    bm.setImage(preState.backgroundImage);
                    bm.setOpacity(preState.backgroundOpacity);
                }
                vm._scheduleRender();
            },
            redoFn: (vm) => {
                // Same pattern with postState
            }
        });
    }
    
    onRenderScheduled(this);
}
```

**Simplification**: Since all background changes affect the same state, use a batching pattern similar to layout options. Snapshot on first change, push on interaction end (blur/change).

#### 3. Overlay handlers with undo
**File**: `MyESModules/App/createOverlayHandlers.js`

Add `onUndoCommand` parameter. Each overlay change pushes a command:

```javascript
export function createOverlayHandlers(onRenderScheduled, onUndoCommand = null)
```

```javascript
handleOverlayImageChange(file) {
    if (!file) return;
    const preOverlayImage = this.overlayImage;
    
    const img = await loadImageFromFile(file);
    if (img) {
        if (this.overlayImage) this.overlayImage = null;
        this.overlayImage = img;
        
        if (onUndoCommand) {
            const postOverlayImage = this.overlayImage;
            const preImg = preOverlayImage;
            onUndoCommand(this, {
                label: 'Change Overlay',
                undoFn: (vm) => {
                    vm.overlayImage = preImg;
                    vm._scheduleRender();
                },
                redoFn: (vm) => {
                    vm.overlayImage = postOverlayImage;
                    vm._scheduleRender();
                }
            });
        }
        
        onRenderScheduled(this);
    }
}
```

#### 4. Wire `onUndoCommand` in `createCollageMethods.js`
Pass the shared `pushUndoCommand` callback to title, background, and overlay handler factories. Expose `commitTitleText`, `commitTitleStyle`, and `commitLayoutOptions` as Vue methods.

#### 5. Template updates
**File**: `index.html`

- Title text input: add `@blur="commitTitleText"` and `@keydown.enter="commitTitleText"`
- Title style controls: add `@blur="commitTitleStyle"` to inputs
- Layout option controls: add `@blur="commitLayoutOptions"` to sliders

### Test Scenarios

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 4.1.1 | Title text is "Hello" | User types "World", clicks away (blur) | Title shows "World", undo button enabled |
| 4.1.2 | Title text changed in 4.1.1 | User presses Cmd+Z | Title reverts to "Hello" |
| 4.1.3 | Title text being typed | User types "Hello" but never blurs | No undo command pushed (per-keystroke not tracked) |
| 4.1.4 | Title text "Hello World" with "World" selected | User clicks Bold button | "World" becomes bold, undo button enabled |
| 4.1.5 | Bold applied in 4.1.4 | User presses Cmd+Z | "World" reverts to unbolded |
| 4.1.6 | Title font changed from Arial to Helvetica | User changes font size from 24 to 36 | Both changes batched into single "Change Title Style" command |
| 4.1.7 | Title style changed in 4.1.6 | User presses Cmd+Z | Both font and size revert together |
| 4.1.8 | Background is solid black | User changes to gradient | Background changes, undo button enabled |
| 4.1.9 | Background changed in 4.1.8 | User presses Cmd+Z | Background reverts to solid black |
| 4.1.10 | No overlay | User adds overlay image | Overlay appears, undo button enabled |
| 4.1.11 | Overlay added in 4.1.10 | User presses Cmd+Z | Overlay removed |

#### Unit Test Scenarios

| # | Test | Input | Expected |
|---|------|-------|----------|
| 4.2.1 | Title text change on blur pushes undo | Text changed, blur fires | Command with label "Edit Title" pushed |
| 4.2.2 | Title text change on Enter pushes undo | Text changed, Enter pressed | Command pushed |
| 4.2.3 | Title text typing without blur | Multiple keystrokes, no blur | No command pushed |
| 4.2.4 | Title bold toggle pushes undo | Bold toggled on selection | Command with label "Format Title" pushed |
| 4.2.5 | Title bold undo restores formatting | Bold undone | titleRuns restored to pre-state |
| 4.2.6 | Title style batching | Font + size changed | Single "Change Title Style" command |
| 4.2.7 | Background change pushes undo | Style changed | Command with label "Change Background" pushed |
| 4.2.8 | Background undo restores all properties | Background undone | All background properties restored |
| 4.2.9 | Overlay change pushes undo | Overlay image added | Command with label "Change Overlay" pushed |
| 4.2.10 | Overlay undo restores previous image | Overlay undone | Previous overlay image restored |
| 4.2.11 | TitleRuns deep copy | titleRuns with nested objects | Snapshot is independent of original |

### Success Criteria:

#### Automated Verification:
- [ ] All existing tests pass
- [ ] New unit tests for title text undo pass
- [ ] New unit tests for title formatting undo pass
- [ ] New unit tests for title style batching pass
- [ ] New unit tests for background undo pass
- [ ] New unit tests for overlay undo pass
- [ ] No console errors during undo/redo

#### Manual Verification:
- [ ] Type title text → blur → Cmd+Z reverts
- [ ] Bold selected text → Cmd+Z unbolds
- [ ] Change font + size → Cmd+Z reverts both
- [ ] Change background → Cmd+Z reverts
- [ ] Add overlay → Cmd+Z removes

---

## Testing Strategy

### Unit Tests

Each new undoable action requires:
1. **Command push test**: Verify `onUndoCommand` is called with correct label and state snapshots
2. **Undo function test**: Verify undo restores pre-state and triggers render
3. **Redo function test**: Verify redo restores post-state and triggers render
4. **Edge case test**: Verify disposed-image guard, null guards, empty state guards

New test file: `MyComponents/UndoExpansionTest.html`

### E2E Tests (Playwright)

New test file: `test/e2e/undo-expansion.spec.js`

Each new undoable action requires:
1. **Happy path**: Action → Cmd+Z → state restored → Cmd+Shift+Z → state re-applied
2. **Button state**: Undo/redo buttons reflect correct enabled/disabled state

### Manual Testing Steps

1. Load app with 5 images
2. Remove one → Cmd+Z → verify restored
3. Change layout → Cmd+Z → verify reverted
4. Adjust gutter slider → release → Cmd+Z → verify reverted
5. Type title text → blur → Cmd+Z → verify reverted
6. Bold title text → Cmd+Z → verify unbolded
7. Change background → Cmd+Z → verify reverted
8. Add overlay → Cmd+Z → verify removed
9. Clear all → Cmd+Z → verify all restored
10. Verify no console errors throughout

## Performance Considerations

- **Deep copy cost**: `JSON.parse(JSON.stringify(titleRuns))` is used for title runs snapshots. Title runs are small arrays (< 100 elements), so this is negligible.
- **Crops snapshot**: `JSON.parse(JSON.stringify(crops))` for image add/remove. Crops array is small (< 100 entries), acceptable cost.
- **Batching prevents bloat**: Layout options and title styles batched per interaction prevent excessive undo stack growth.
- **Max 60 levels**: UndoManager already enforces max 60 undo levels, preventing memory issues.

## Migration Notes

- No data migration needed — undo history is ephemeral (not persisted)
- Existing undo commands (panel swap, crop drag) continue to work unchanged
- The `onUndoCommand` callback is optional — handlers work without it (backward compatible)
- Template changes are additive (new `@blur` handlers) — existing `@input`/`@change` handlers remain

## References

- Change request: `_agent_docs/specifications/change-requests/undo-redo-expansion.md`
- World review: UX analysis from @world-review subagent
- Existing undo tests: `MyComponents/UndoManagerTest.html`, `MyComponents/UndoWiringTest.html`
- Existing E2E undo tests: `test/e2e/keyboard-shortcuts.spec.js`, `test/e2e/workflow-tests.spec.cjs`
- Session summary template: `.opencode/skills/analyzing-opencode-usage/references/session-summary.json`
