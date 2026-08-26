# Mobile Bottom Sheet Adjustments — Implementation Plan

**Date:** 2026-07-26
**Source:** Change request `2026-07-26-01-mobile-bottom-sheet-adjustments.md`
**Priority:** P1 — Mobile usability improvement

---

## Overview

Two targeted adjustments to the mobile bottom sheet (already implemented per `2026-07-25-mobile-bottom-sheet-redesign.md`):

1. **Remove the crop preview canvas** from the Edit bottom sheet — corner handles fall below the 44×44px minimum touch target on a constrained bottom sheet (max-height: 70dvh, 50dvh in landscape). Retain the crop info readout (X, Y, W, H) and "Reset Crop" button.
2. **Reorder the Images bottom sheet** — move Layout Controls above the Image Library so high-frequency iterative controls sit in the prime "thumb reach" zone, matching the "settings > content" pattern used by Canva and Adobe Express.

Both changes are DOM-only (template reordering + element removal). No new JavaScript logic or state is needed. The crop preview canvas removal requires unwiring `bsCropPreviewCanvas` from the dual-canvas crop system (lifecycle + renderer + tests).

---

## Current State Analysis

### Edit Panel — Crop Section (index.html lines 279–300)

```html
<template v-if="selectedPanelId && selectedCropInfo">
    <div class="detail-section crop-preview-section">
        <canvas id="bsCropPreviewCanvas" class="crop-preview-canvas" ...></canvas>
        <div class="crop-info">
            <span class="crop-info-item">X: ...</span>
            <span class="crop-info-item">Y: ...</span>
            <span class="crop-info-item">W: ...</span>
            <span class="crop-info-item">H: ...</span>
        </div>
        <button class="pure-button reset-crop-btn" @click="resetSelectedCrop">...</button>
    </div>
</template>
```

The `.crop-preview-section` class (Style.css lines 459–465) provides `display: flex; flex-direction: column; gap; padding; border-bottom`. The canvas element is the only interactive crop control in the bottom sheet.

### Images Panel — Current Order (index.html lines 228–274)

1. **Image Library** (lines 230–250): Search bar + scrollable thumbnail list
2. **Layout Controls** (lines 252–274): Layout Style dropdown, Gutter slider, Slice Angle slider, Hex Spacing slider, Hex Size slider

### Dual Canvas Crop Wiring

| File | Location | Current State |
|------|----------|---------------|
| `createCollageLifecycle.js` | Line 145 | `canvasId: [ids.cropPreviewCanvas, ids.bsCropPreviewCanvas]` |
| `createCollageMethods.js` | Line 33 | `bsCropPreviewCanvas: 'bsCropPreviewCanvas'` in `DEFAULT_DOM_IDS` |
| `createCropPreviewRenderer.js` | Line 183 | `if (ids.bsCropPreviewCanvas) canvasIds.push(ids.bsCropPreviewCanvas)` |
| `index.html` | Line 699 | `bsCropPreviewCanvas: 'bsCropPreviewCanvas'` in app domIds |
| `CropPreviewDualCanvasTest.html` | Lines 116–358 | 8 tests for dual canvas crop preview/interaction |

### CSS

- `.crop-preview-section` (Style.css line 459–465): flex column, gap, padding, border-bottom
- `.crop-preview-canvas` (Style.css line 467–478): 100% width, 4:3 aspect ratio, max-height 180px, cursor, shadow
- `.crop-info` (Style.css line 481–487): flex row, space-between, mono font
- `.crop-info-item` (Style.css line 489+): individual item styling

---

## Desired End State

After this plan is complete:

1. **Edit bottom sheet**: No crop preview canvas. Crop info readout (X, Y, W, H) and "Reset Crop" button remain, styled as a standard `.detail-section`. The main canvas still shows the crop overlay with handles for visual feedback.
2. **Images bottom sheet**: Layout Controls appear first, followed by a visual section header, then the Image Library (with search bar).
3. **Crop wiring**: `bsCropPreviewCanvas` is removed from lifecycle, methods, renderer, and app domIds. The crop system operates on a single canvas (`cropPreviewCanvas` in the desktop sidebar).
4. **Tests**: `CropPreviewDualCanvasTest.html` updated — dual-canvas tests converted to single-canvas tests. No test references `bsCropPreviewCanvas`.
5. **Desktop**: No visible changes. The desktop sidebar crop preview canvas remains fully functional.

---

## Key Discoveries

- **`bsCropPreviewCanvas` wiring is already in place**: The previous plan (`2026-07-25-mobile-bottom-sheet-redesign.md`) Phase 3 migration wired the dual-canvas crop system. This change reverses that wiring for the mobile canvas only.
- **CropInteraction normalizes canvasId to array** (`CropInteraction.js` line 24): `const canvasIds = Array.isArray(canvasId) ? canvasId : [canvasId]`. Passing a single string is already supported — no changes needed to CropInteraction.
- **createCropPreviewRenderer guards hidden canvases** (`createCropPreviewRenderer.js` line 36): `if (!canvas.isConnected || canvas.offsetParent === null) return;`. Even with dual wiring, the hidden canvas was skipped at render time. Removing the wiring eliminates the DOM lookup overhead entirely.
- **`.crop-preview-section` styling is specific**: The class provides flex column layout, gap, padding, and border-bottom. Removing it means the crop info readout needs a different wrapper. Using `.detail-section` (the standard section class used throughout the bottom sheet) is the simplest approach.
- **No E2E tests reference `bsCropPreviewCanvas`**: The Playwright test suite has no tests targeting the mobile crop preview canvas. Only the unit test file `CropPreviewDualCanvasTest.html` needs updates.
- **World-review concern**: Five layout controls at the top of a 70dvh bottom sheet may consume significant vertical space. The change request explicitly does NOT make them collapsible. This is documented as a known behavior.

---

## What We're NOT Doing

- **No collapsible layout controls** — the change request places all five controls at the top. A future iteration could add an accordion if vertical space becomes problematic.
- **No full-screen crop editor** — the change request mentions this as a future consideration. Not in scope.
- **No desktop changes** — the desktop sidebar crop preview canvas (`cropPreviewCanvas`) remains fully functional.
- **No changes to CropInteraction.js** — it already supports single canvas IDs. No code changes needed in the interaction module.
- **No changes to createCropPreviewRenderer.js logic** — the renderer already handles missing canvas IDs gracefully. Removing `bsCropPreviewCanvas` from domIds is sufficient.
- **No CSS rule removal** — `.crop-preview-section` and `.crop-preview-canvas` CSS rules remain (they still apply to the desktop sidebar crop preview).

---

## Implementation Approach

Both problems are independent and can be implemented in a single phase. The changes are:

1. **Template changes** (index.html): Reorder DOM elements, remove canvas element
2. **Wiring changes** (createCollageLifecycle.js, createCollageMethods.js): Remove `bsCropPreviewCanvas` from DOM ID configs
3. **Test changes** (CropPreviewDualCanvasTest.html): Update dual-canvas tests to single-canvas tests

---

## Phase 1: Remove Crop Preview Canvas from Edit Bottom Sheet

### Overview

Remove the `bsCropPreviewCanvas` element and its `.crop-preview-section` wrapper from the Edit bottom sheet. Retain the crop info readout and Reset Crop button as a standard `.detail-section`. Unwire the mobile canvas from the crop system.

### Changes Required:

#### 1. Edit Panel Template — Remove Canvas, Keep Readout

**File**: `index.html`
**Lines**: 279–300 (Edit Panel Crop Section)

**Current:**
```html
<template v-if="selectedPanelId && selectedCropInfo">
    <div class="detail-section crop-preview-section">
        <canvas id="bsCropPreviewCanvas" class="crop-preview-canvas" role="application" aria-label="Crop editor — drag handles to adjust crop region"></canvas>
        <div class="crop-info">
            <span class="crop-info-item">X: {{ Math.round(selectedCropInfo.sourceRect.x) }}</span>
            <span class="crop-info-item">Y: {{ Math.round(selectedCropInfo.sourceRect.y) }}</span>
            <span class="crop-info-item">W: {{ Math.round(selectedCropInfo.sourceRect.width) }}</span>
            <span class="crop-info-item">H: {{ Math.round(selectedCropInfo.sourceRect.height) }}</span>
        </div>
        <button class="pure-button reset-crop-btn" @click="resetSelectedCrop">
            <span class="material-icons" style="font-size: 16px; vertical-align: middle; margin-right: 4px;">restart_alt</span>
            Reset Crop
        </button>
    </div>
</template>
```

**New:**
```html
<template v-if="selectedPanelId && selectedCropInfo">
    <div class="detail-section">
        <div class="crop-info">
            <span class="crop-info-item">X: {{ Math.round(selectedCropInfo.sourceRect.x) }}</span>
            <span class="crop-info-item">Y: {{ Math.round(selectedCropInfo.sourceRect.y) }}</span>
            <span class="crop-info-item">W: {{ Math.round(selectedCropInfo.sourceRect.width) }}</span>
            <span class="crop-info-item">H: {{ Math.round(selectedCropInfo.sourceRect.height) }}</span>
        </div>
        <button class="pure-button reset-crop-btn" @click="resetSelectedCrop">
            <span class="material-icons" style="font-size: 16px; vertical-align: middle; margin-right: 4px;">restart_alt</span>
            Reset Crop
        </button>
    </div>
</template>
```

**Changes:**
- Remove `<canvas id="bsCropPreviewCanvas">` element (line 282)
- Replace `class="detail-section crop-preview-section"` with `class="detail-section"` (line 281)
- Keep `.crop-info` and `reset-crop-btn` elements unchanged

#### 2. Lifecycle — Single Canvas for Crop Interaction

**File**: `MyESModules/App/createCollageLifecycle.js`
**Line**: 145

**Current:**
```javascript
canvasId: [ids.cropPreviewCanvas, ids.bsCropPreviewCanvas],
```

**New:**
```javascript
canvasId: ids.cropPreviewCanvas,
```

**Rationale**: CropInteraction normalizes single string to array internally. Passing a single ID is cleaner than a one-element array.

#### 3. Lifecycle — Remove bsCropPreviewCanvas from DOM IDs

**File**: `MyESModules/App/createCollageLifecycle.js`
**Lines**: 28–32

**Current:**
```javascript
const DEFAULT_DOM_IDS = {
    previewCanvas: 'previewCanvas',
    cropPreviewCanvas: 'cropPreviewCanvas',
    bsCropPreviewCanvas: 'bsCropPreviewCanvas'
};
```

**New:**
```javascript
const DEFAULT_DOM_IDS = {
    previewCanvas: 'previewCanvas',
    cropPreviewCanvas: 'cropPreviewCanvas'
};
```

#### 4. Methods — Remove bsCropPreviewCanvas from DOM IDs

**File**: `MyESModules/App/createCollageMethods.js`
**Lines**: 30–34

**Current:**
```javascript
const DEFAULT_DOM_IDS = {
    fileInput: 'fileInput',
    cropPreviewCanvas: 'cropPreviewCanvas',
    bsCropPreviewCanvas: 'bsCropPreviewCanvas'
};
```

**New:**
```javascript
const DEFAULT_DOM_IDS = {
    fileInput: 'fileInput',
    cropPreviewCanvas: 'cropPreviewCanvas'
};
```

#### 5. App domIds — Remove bsCropPreviewCanvas

**File**: `index.html`
**Line**: ~699 (in the app script module domIds config)

**Current:**
```javascript
bsCropPreviewCanvas: 'bsCropPreviewCanvas',
```

**New:** Remove this line entirely.

#### 6. Test File — Update Dual Canvas Tests

**File**: `MyComponents/CropPreviewDualCanvasTest.html`
**Lines**: 116–358

**Changes:**

| Test | Current | New |
|------|---------|-----|
| P3-CROP-01 | Renderer accepts multiple canvas IDs | Renderer works with single canvas ID |
| P3-CROP-02 | Renders to both canvases | Renders to single canvas |
| P3-CROP-03 | Backward compat with single canvas | (merge into P3-CROP-01, remove) |
| P3-CROP-07 | CropInteraction accepts multiple IDs | CropInteraction works with single ID |
| P3-CROP-08 | Attaches listeners to both canvases | Attaches listener to single canvas |
| P3-CROP-09 | Backward compat single canvas | (merge into P3-CROP-07, remove) |
| P3-CROP-10 | Detach removes from all canvases | Detach removes from single canvas |
| P3-DOM-01 | domIds includes bsCropPreviewCanvas | domIds does NOT include bsCropPreviewCanvas |

**Specific changes:**
- Remove `canvasMobile` mock canvas creation in `beforeEach`
- Remove `bsCropPreviewCanvas` from `mockGetElementById`
- P3-CROP-01: Assert renderer accepts single canvas ID (string, not array)
- P3-CROP-02: Assert renderer draws to `cropPreviewCanvas` only (assert `drawnCanvases` does NOT include `bsCropPreviewCanvas`)
- P3-CROP-03: Remove (merged into P3-CROP-01)
- P3-CROP-07: Assert CropInteraction accepts single canvas ID (string)
- P3-CROP-08: Assert listener attached to `cropPreviewCanvas` only (assert `mobileDownCount === 0`)
- P3-CROP-09: Remove (merged into P3-CROP-07)
- P3-CROP-10: Assert detach removes from `cropPreviewCanvas` only (assert `mobileRemoveCount === 0`)
- P3-DOM-01: Assert `bsCropPreviewCanvas` is NOT in index.html script text
- Update file title and description to reflect single-canvas scope
- Remove `canvasMobile` from `afterEach` cleanup

### Behavior Scenarios — Phase 1

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 1.1.1 | A panel is selected on the canvas, user opens bottom sheet Edit tab | User views the Edit panel | Crop info readout (X, Y, W, H) is visible, "Reset Crop" button is visible, no canvas element is present |
| 1.1.2 | Crop info readout is visible in Edit bottom sheet | User adjusts crop on the main canvas (via two-finger gesture) | Readout values update reactively to reflect new crop coordinates |
| 1.1.3 | Crop info readout is visible in Edit bottom sheet | User taps "Reset Crop" button | Crop resets to full image, readout values update to full image dimensions |
| 1.1.4 | No panel is selected, images are loaded, user opens Edit tab | User views the Edit panel | "Select a panel on the canvas to edit its crop" placeholder is shown (unchanged behavior) |
| 1.1.5 | Desktop viewport (1920px), a panel is selected | User views the right sidebar Crop section | Crop preview canvas renders with image, dark overlay, and corner handles (unchanged behavior) |
| 1.1.6 | Mobile viewport (375px), Edit tab open with crop readout | User scrolls the Edit panel content | Readout and reset button scroll naturally with content (no fixed positioning) |

#### Component Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 1.2.1 | `createCropInteraction` called with `canvasId: 'cropPreviewCanvas'` (single string) | `handler.attach()` called | Pointer listeners attached to `cropPreviewCanvas` only, no errors about missing `bsCropPreviewCanvas` |
| 1.2.2 | `createCropInteraction` called with `canvasId: 'cropPreviewCanvas'` | `handler.detach()` called | Pointer listeners removed from `cropPreviewCanvas` only |
| 1.2.3 | `createCropPreviewRenderer` called with domIds containing only `cropPreviewCanvas` | `_scheduleCropPreviewRender(vm)` called | Canvas renders to `cropPreviewCanvas` only, no DOM lookup for `bsCropPreviewCanvas` |
| 1.2.4 | `createCollageLifecycle` mounted with default domIds | `mounted()` executes | `createCropInteraction` receives single string `canvasId`, not an array |
| 1.2.5 | `selectedCropInfo.sourceRect` changes (via main canvas crop gesture) | Vue reactivity triggers re-render | `crop-info-item` span text updates with new rounded values |

#### Pure Function Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 1.3.1 | `Array.isArray('cropPreviewCanvas')` | Evaluated | Returns `false` (CropInteraction normalizes to `['cropPreviewCanvas']`) |
| 1.3.2 | `createCropInteraction` with `canvasId: 'cropPreviewCanvas'` | Internal normalization | `canvasIds` equals `['cropPreviewCanvas']` |

### Unit Test Scenarios

**Updated test file**: `MyComponents/CropPreviewDualCanvasTest.html`

| # | Test | Input | Expected |
|---|------|-------|----------|
| BS-ADJ-01 | Renderer works with single canvas ID | `domIds: { cropPreviewCanvas: 'cropPreviewCanvas' }` | No error, renders to `cropPreviewCanvas` |
| BS-ADJ-02 | Renderer does not look up `bsCropPreviewCanvas` | Single canvas config | `drawnCanvases` does NOT include `bsCropPreviewCanvas` |
| BS-ADJ-03 | CropInteraction accepts single canvas ID string | `canvasId: 'cropPreviewCanvas'` | No error, attaches to one canvas |
| BS-ADJ-04 | CropInteraction attaches to single canvas only | Single canvas config | `desktopDownCount === 1`, `mobileDownCount === 0` |
| BS-ADJ-05 | CropInteraction detach removes from single canvas | Single canvas config, attach then detach | `desktopRemoveCount === 1`, `mobileRemoveCount === 0` |
| BS-ADJ-06 | index.html does NOT reference `bsCropPreviewCanvas` | Parse index.html DOM | `bsCropPreviewCanvas` not found in script text |

**Updated test file**: `MyComponents/ResponsiveCSSValidationTest.html`

| # | Test | Expected |
|---|------|----------|
| BS-ADJ-CSS-01 | `.crop-preview-canvas` CSS rule still exists (desktop sidebar) | CSS contains `.crop-preview-canvas` |
| BS-ADJ-CSS-02 | `.crop-preview-section` CSS rule still exists (desktop sidebar) | CSS contains `.crop-preview-section` |

### E2E Test Scenarios (Playwright)

**Updated test file**: `test/e2e/bottom-sheet.spec.js` (if it exists with crop-related tests)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| BS-ADJ-E2E-01 | Edit tab has no crop canvas on mobile | Mobile viewport, open bottom sheet, switch to Edit tab | No `<canvas>` element in `#bs-panel-edit` |
| BS-ADJ-E2E-02 | Edit tab crop readout visible when panel selected | Mobile, load images, select panel, open Edit tab | `.crop-info` visible with X/Y/W/H values |
| BS-ADJ-E2E-03 | Reset Crop button functional in bottom sheet | Mobile, Edit tab, crop adjusted, tap Reset | Crop info values reset to full image dimensions |
| BS-ADJ-E2E-04 | Desktop crop canvas still functional | Desktop viewport, select panel, view right sidebar | `#cropPreviewCanvas` renders with image and handles |
| BS-ADJ-E2E-05 | Desktop crop handles interactive | Desktop, drag corner handle on crop preview | Crop region adjusts, canvas re-renders |

### Success Criteria:

#### Automated Verification:
- [ ] `node scripts/run-tests.js` — all existing tests pass (including updated CropPreviewDualCanvasTest.html)
- [ ] CropPreviewDualCanvasTest.html — 6 tests pass (BS-ADJ-01 through BS-ADJ-06)
- [ ] ResponsiveCSSValidationTest.html — existing CSS tests still pass (`.crop-preview-canvas` and `.crop-preview-section` rules still present)
- [ ] No file in the project references `bsCropPreviewCanvas` (grep verification)

#### Manual Verification:
- [ ] Edit bottom sheet shows crop info readout and Reset Crop button when a panel is selected
- [ ] Edit bottom sheet does NOT show a crop preview canvas
- [ ] Adjusting crop on main canvas updates the readout values in real time
- [ ] Tapping "Reset Crop" in bottom sheet resets the crop
- [ ] Desktop sidebar crop preview canvas still works (renders image, handles are interactive)
- [ ] No console errors about missing `bsCropPreviewCanvas` element
- [ ] No horizontal overflow in Edit panel at 320px viewport

---

## Phase 2: Reorder Images Bottom Sheet Sections

### Overview

Move Layout Controls above the Image Library in the Images bottom sheet tab. Add a visual section header to separate the two groups. The search bar stays with the Image Library.

### Changes Required:

#### 1. Images Panel Template — Swap Section Order

**File**: `index.html`
**Lines**: 228–274 (Images Panel content)

**Current order:**
1. Image Library (lines 230–250): search bar + thumbnails
2. Layout Controls (lines 252–274): dropdown + sliders

**New order:**
1. Layout Controls (moved to top, with section header)
2. Image Library (moved below, search bar stays with library)

**New template:**
```html
<div id="bs-panel-images" class="bottom-sheet-panel" role="tabpanel" aria-labelledby="bs-tab-images" v-show="activeBottomSheetTab === 'images'">
    <!-- Layout Controls -->
    <div class="bottom-sheet-section-header">Layout Settings</div>
    <div class="detail-section">
        <label for="bsLayoutStyleSelect">Layout Style</label>
        <select id="bsLayoutStyleSelect" v-model="layoutStyle" class="pure-input-rounded" @focus="snapshotLayoutStyle" @change="onLayoutStyleChange">
            <option v-for="style in layoutStyles" :key="style.value" :value="style.value">{{ style.label }}</option>
        </select>
    </div>
    <div class="detail-section" v-show="layoutStyle !== 'hexagonal'">
        <label for="bsGutterSlider">Gutter: {{ gutter }}px</label>
        <input type="range" id="bsGutterSlider" v-model.number="gutter" min="0" max="20" step="1" class="fullRange" @focus="snapshotLayoutOptions" @pointerdown="snapshotLayoutOptions" @input="onGutterChange" @blur="commitLayoutOptions">
    </div>
    <div class="detail-section" v-if="layoutStyle === 'diagonalSlices'">
        <label for="bsSliceAngleSlider">Slice Angle: {{ sliceAngle }}&deg;</label>
        <input type="range" id="bsSliceAngleSlider" v-model.number="sliceAngle" min="-75" max="75" step="1" class="fullRange" @focus="snapshotLayoutOptions" @pointerdown="snapshotLayoutOptions" @input="onSliceAngleChange" @blur="commitLayoutOptions">
    </div>
    <div class="detail-section" v-if="layoutStyle === 'hexagonal'">
        <label for="bsHexSpacingSlider">Hex Spacing: {{ hexSpacing }}px</label>
        <input type="range" id="bsHexSpacingSlider" v-model.number="hexSpacing" min="0" max="30" step="1" class="fullRange" @focus="snapshotLayoutOptions" @pointerdown="snapshotLayoutOptions" @input="onHexSpacingChange" @blur="commitLayoutOptions">
    </div>
    <div class="detail-section" v-if="layoutStyle === 'hexagonal'">
        <label for="bsHexSizeSlider">Hexagon Size: {{ Math.round(hexSizeMultiplier * 100) }}%</label>
        <input type="range" id="bsHexSizeSlider" v-model.number="hexSizeMultiplier" min="0.5" max="2" step="0.05" class="fullRange" @focus="snapshotLayoutOptions" @pointerdown="snapshotLayoutOptions" @input="onHexSizeMultiplierChange" @blur="commitLayoutOptions">
    </div>

    <!-- Image Library -->
    <div class="bottom-sheet-section-header">Image Library</div>
    <div class="library-search">
        <input type="text" v-model="searchQuery" placeholder="Search by filename..." class="pure-input-rounded">
    </div>
    <div class="image-library">
        <div v-if="filteredImages.length === 0" class="empty-library">
            <span class="material-icons" style="font-size: 48px; opacity: 0.4;">image</span>
            <p>No images yet</p>
            <p class="hint">Drag &amp; drop images here or click "Add Images"</p>
        </div>
        <div v-for="(image, index) in filteredImages" :key="'bs-img-' + image.id"
             class="image-item"
             :class="{ selected: selectedImageId === image.id }"
             @click="selectImage(index)">
            <div class="image-number">{{ index + 1 }}</div>
            <img :src="image.thumbnail" :alt="image.filename" class="image-thumb">
            <div class="image-name" :title="image.filename">{{ truncateFilename(image.filename) }}</div>
            <button class="remove-btn" @click.stop="removeImage(index)" title="Remove">
                <span class="material-icons">close</span>
            </button>
        </div>
    </div>
</div>
```

**Changes:**
- Move Layout Controls block (currently lines 252–274) above Image Library block (currently lines 230–250)
- Add `<div class="bottom-sheet-section-header">Layout Settings</div>` before Layout Controls
- Add `<div class="bottom-sheet-section-header">Image Library</div>` before Image Library
- Keep search bar with Image Library (not moved with layout controls)

#### 2. CSS — Section Header Styling

**File**: `Style.css`
**Changes**: Add new CSS rule for section headers inside the mobile media query block.

```css
.bottom-sheet-section-header {
    font-size: var(--font-size-xs);
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--color-text-secondary);
    padding: var(--space-2) var(--space-4);
    padding-top: var(--space-3);
    border-bottom: 1px solid var(--color-surface-variant);
    background-color: var(--color-surface);
    position: sticky;
    top: 0;
    z-index: 1;
}
```

**Rationale**: Sticky positioning ensures section headers remain visible when scrolling through a long image library. The uppercase, secondary-color styling matches common mobile section header patterns (iOS Settings, Spotify playlists).

### Behavior Scenarios — Phase 2

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 2.1.1 | Mobile viewport, bottom sheet Images tab open, no images loaded | User views the Images panel | Layout Controls (Layout Style dropdown, Gutter slider) appear at the top, "Layout Settings" header visible, empty library message below |
| 2.1.2 | Mobile viewport, Images tab open, 5 images loaded | User views the Images panel | Layout Controls at top, then "Image Library" header, then search bar, then 5 image thumbnails |
| 2.1.3 | Images tab open, layout set to "Uniform" | User changes Layout Style to "Hero" | Canvas re-renders with Hero layout, Gutter slider remains visible |
| 2.1.4 | Images tab open, layout set to "Diagonal Slices" | User changes Layout Style to "Diagonal Slices" | Slice Angle slider appears, Gutter slider hidden |
| 2.1.5 | Images tab open, layout set to "Hexagonal" | User views the panel | Hex Spacing and Hex Size sliders visible, Gutter slider hidden |
| 2.1.6 | Images tab open, 20 images loaded | User scrolls the image library | Layout Controls remain at top (not scrollable away), section header "Image Library" sticks to top while scrolling thumbnails |
| 2.1.7 | Images tab open, user types in search bar | User types "photo" | Image list filters to matching filenames, Layout Controls above remain visible and interactive |
| 2.1.8 | Desktop viewport (1920px) | User views the left sidebar | Sidebar order unchanged (Image Library above Layout Controls in desktop sidebar) |
| 2.1.9 | Images tab open, user adjusts Gutter slider | User drags slider from 0 to 10 | Canvas re-renders with updated gutter, value label updates from "Gutter: 0px" to "Gutter: 10px" |
| 2.1.10 | Images tab open, user taps on an image thumbnail | User taps thumbnail #3 | Image #3 selected (highlighted), selection state persists |

#### Component Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 2.2.1 | `#bs-panel-images` DOM structure | Panel rendered | First child is `.bottom-sheet-section-header` with text "Layout Settings" |
| 2.2.2 | `#bs-panel-images` DOM structure | Panel rendered | `.library-search` appears after all `.detail-section` layout controls |
| 2.2.3 | `#bs-panel-images` DOM structure | Panel rendered | `.image-library` appears after `.library-search` |
| 2.2.4 | `.bottom-sheet-section-header` CSS | Mobile viewport | Element has `position: sticky`, `top: 0`, uppercase text |
| 2.2.5 | `v-show="activeBottomSheetTab === 'images'"` | Tab switched to 'edit' | `#bs-panel-images` has `display: none` (v-show behavior) |
| 2.2.6 | Layout controls use same v-model bindings as before | Reorder applied | `layoutStyle`, `gutter`, `sliceAngle`, `hexSpacing`, `hexSizeMultiplier` still bound to same reactive properties |

#### Pure Function Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 2.3.1 | DOM order: Layout Controls before Image Library | Screen reader reads panel | Layout Controls announced first, then Image Library |
| 2.3.2 | Tab key navigation in Images panel | User presses Tab | Focus moves: Layout Style select → Gutter slider → (conditional sliders) → section header (skipped) → search input → image items |

### Unit Test Scenarios

**Updated test file**: `MyComponents/ResponsiveCSSValidationTest.html`

| # | Test | Expected |
|---|------|----------|
| BS-ADJ-CSS-03 | `.bottom-sheet-section-header` CSS rule exists | Mobile media query contains `.bottom-sheet-section-header` |
| BS-ADJ-CSS-04 | `.bottom-sheet-section-header` uses `position: sticky` | CSS contains `position: sticky` |
| BS-ADJ-CSS-05 | `.bottom-sheet-section-header` uses uppercase text | CSS contains `text-transform: uppercase` |

**New DOM structure test** (in CropPreviewDualCanvasTest.html or a new test section):

| # | Test | Input | Expected |
|---|------|-------|----------|
| BS-ADJ-DOM-01 | Layout Controls precede Image Library in DOM | Parse `#bs-panel-images` children | First `.detail-section` (Layout Style) comes before `.library-search` |
| BS-ADJ-DOM-02 | Section headers present in Images panel | Parse `#bs-panel-images` children | Two `.bottom-sheet-section-header` elements exist with texts "Layout Settings" and "Image Library" |
| BS-ADJ-DOM-03 | Search bar stays with Image Library | Parse `#bs-panel-images` children | `.library-search` is immediately before `.image-library` |

### E2E Test Scenarios (Playwright)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| BS-ADJ-E2E-06 | Layout Controls at top of Images panel | Mobile, open bottom sheet, Images tab | `#bsLayoutStyleSelect` visible above `.image-library` |
| BS-ADJ-E2E-07 | Section headers visible | Mobile, Images tab | "Layout Settings" and "Image Library" headers visible |
| BS-ADJ-E2E-08 | Layout change from bottom sheet affects canvas | Mobile, change Layout Style to Hero | Canvas re-renders with Hero layout |
| BS-ADJ-E2E-09 | Search bar filters images | Mobile, Images tab, type in search | Image list filters, Layout Controls remain visible |
| BS-ADJ-E2E-10 | Desktop sidebar order unchanged | Desktop viewport | Left sidebar: Image Library above Layout Controls |

### Success Criteria:

#### Automated Verification:
- [ ] `node scripts/run-tests.js` — all existing tests pass
- [ ] ResponsiveCSSValidationTest.html — 3 new CSS tests pass (BS-ADJ-CSS-03 through BS-ADJ-CSS-05)
- [ ] DOM structure tests pass (BS-ADJ-DOM-01 through BS-ADJ-DOM-03)
- [ ] No test references removed DOM structure

#### Manual Verification:
- [ ] Layout Controls appear at the top of Images bottom sheet tab
- [ ] "Layout Settings" section header visible above layout controls
- [ ] "Image Library" section header visible above image thumbnails
- [ ] Search bar is with the Image Library (not above layout controls)
- [ ] All layout controls (dropdown, sliders) are functional and affect the canvas
- [ ] Image selection, removal, and search work from the reordered panel
- [ ] Section headers stick to top when scrolling through long image lists
- [ ] Desktop left sidebar order is unchanged (Image Library above Layout Controls)
- [ ] All sliders and dropdowns maintain 44px+ touch targets
- [ ] No horizontal overflow at 320px viewport

---

## Testing Strategy

### Unit Tests

**Updated file**: `MyComponents/CropPreviewDualCanvasTest.html`
- Rename to reflect single-canvas scope (or update title/description)
- 6 tests: BS-ADJ-01 through BS-ADJ-06
- Follows existing mock canvas + RAF mocking pattern

**Updated file**: `MyComponents/ResponsiveCSSValidationTest.html`
- 5 new CSS validation tests: BS-ADJ-CSS-01 through BS-ADJ-CSS-05
- Follows existing CSS text parsing pattern

### E2E Tests (Playwright)

**Updated file**: `test/e2e/bottom-sheet.spec.js` (if existing tests need updates)
- 10 new/updated E2E tests: BS-ADJ-E2E-01 through BS-ADJ-E2E-10
- Mobile viewport (375×667) for bottom sheet tests
- Desktop viewport (1920×1080) for regression tests

### Manual Testing Steps

1. Start dev server: `bash start-server.sh`
2. Open `http://localhost:8000/CollageMaker/index.html`
3. Set viewport to 375×667 (mobile)
4. **Phase 1 verification:**
   a. Upload images, select a panel on canvas
   b. Open bottom sheet, tap Edit tab
   c. Verify crop info readout (X, Y, W, H) is visible
   d. Verify "Reset Crop" button is visible and functional
   e. Verify NO canvas element in Edit panel
   f. Adjust crop on main canvas — verify readout updates
   g. Tap Reset Crop — verify values reset
5. **Phase 2 verification:**
   a. Switch to Images tab
   b. Verify Layout Controls at top with "Layout Settings" header
   c. Verify Image Library below with "Image Library" header
   d. Verify search bar is with image library
   e. Change Layout Style — verify canvas updates
   f. Adjust Gutter slider — verify canvas updates
   g. Scroll image library (add many images) — verify section headers stick
6. **Desktop regression:**
   a. Set viewport to 1920×1080
   b. Verify left sidebar: Image Library above Layout Controls
   c. Verify right sidebar: Crop preview canvas functional
   d. Drag crop handles on desktop — verify crop adjusts

---

## Performance Considerations

- **Reduced DOM lookups**: Removing `bsCropPreviewCanvas` from the crop renderer eliminates one `document.getElementById()` call per render frame. On mobile with high-DPR screens, this reduces the render loop overhead.
- **Reduced template size**: Removing the canvas element and `.crop-preview-section` wrapper saves ~4 lines of HTML in the Edit panel.
- **Sticky headers**: `position: sticky` on section headers is CSS-only — no JavaScript scroll handlers needed.
- **No new JavaScript**: Both phases are purely template and CSS changes. No new methods, handlers, or state properties.

---

## Migration Notes

- **Rollback**: Revert the index.html template changes and the DOM ID config changes. The dual-canvas crop system code in CropInteraction.js and createCropPreviewRenderer.js already supports both single and multiple canvas IDs.
- **No data migration needed**: These are purely UI changes — no state or persistence changes.
- **Backward compatibility**: CropInteraction.js and createCropPreviewRenderer.js continue to support multiple canvas IDs. If a future feature re-adds the mobile crop canvas, only the DOM ID config and template need updating.

---

## Known Behaviors

| Behavior | Rationale |
|----------|-----------|
| Crop preview canvas removed from Edit bottom sheet | Corner handles (12px) fall below 44×44px minimum touch target on constrained bottom sheet. Main canvas provides visual feedback via crop overlay. |
| Crop info readout retained | Provides essential numeric feedback for crop position without requiring a visual canvas. |
| "Reset Crop" button retained | Quick way to undo crop without visual canvas. |
| Layout Controls above Image Library | Matches "settings > content" mobile pattern. Places high-frequency controls in thumb reach zone. |
| Five layout controls at top may consume vertical space | Acknowledged by world-review. Not made collapsible per change request scope. Future iteration could add accordion. |
| Section headers use `position: sticky` | Keeps headers visible during scroll. CSS-only, no JS overhead. |
| Desktop sidebar order unchanged | Image Library above Layout Controls in desktop sidebar (existing behavior preserved). |
| `.crop-preview-section` CSS rule retained | Still used by desktop sidebar crop preview. |
| `.crop-preview-canvas` CSS rule retained | Still used by desktop sidebar crop preview canvas. |
| `bsCropPreviewCanvas` removed from all DOM ID configs | Eliminates dead references. CropInteraction and renderer already handle missing IDs gracefully. |

---

## Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | BS-ADJ-01 through BS-ADJ-06, BS-ADJ-E2E-01 through BS-ADJ-E2E-05 | Core functionality — crop canvas removal and unwiring must work correctly |
| **P0** | BS-ADJ-E2E-06 through BS-ADJ-E2E-10 | Core functionality — section reordering must be correct |
| **P1** | BS-ADJ-CSS-01 through BS-ADJ-CSS-05 | Structural correctness — CSS rules for section headers |
| **P1** | BS-ADJ-DOM-01 through BS-ADJ-DOM-03 | Structural correctness — DOM order verification |
| **P2** | Manual verification of sticky headers, touch targets, scroll behavior | Polish and edge cases |

---

## References

- Change request: `_agent_docs/specifications/change-requests/2026-07-26-01-mobile-bottom-sheet-adjustments.md`
- Bottom sheet redesign plan: `_agent_docs/plans/2026-07-25-mobile-bottom-sheet-redesign.md`
- Dual canvas crop wiring session: `_agent_docs/project-timeline/sessions/2026-07-26-004-build-tdd-crop-preview-dual-canvas.json`
- World-review analysis: Inline analysis of UX implications (touch targets, vertical space, accessibility)
- Building web apps skill: `.opencode/skills/building-web-apps/SKILL.md`
- Writing plans skill: `.opencode/skills/writing-plans/SKILL.md`
