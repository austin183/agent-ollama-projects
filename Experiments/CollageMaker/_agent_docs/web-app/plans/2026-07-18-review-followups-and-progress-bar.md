# Review Follow-ups & Progress Bar Implementation Plan

## Overview

This plan addresses two change requests:

1. **Review Follow-ups (CR1)** — 9 items from `_agent_docs/reviews/2026-07-18-title-changes-review.md`: code quality fixes, UX polish, and accessibility improvements for the title editing system.
2. **Progress Bar When Adding Images (CR2)** — New feature to show a progress overlay on the canvas while images are loading, preventing the "is the app broken?" user experience.

Phases are ordered by dependency and risk: Phase 1 (code quality) is isolated refactoring; Phase 2 (UX + accessibility) touches the title UI; Phase 3 (progress bar) is a new feature with coordinated changes across state, library, handlers, template, and CSS.

## Current State Analysis

### CR1 — Code Quality Items

**1. Duplicate MARGIN Constant**
- `TitleRenderer.js:7` — `const MARGIN = 40;` (module-scoped, not exported)
- `TitleInteraction.js:150` — `const MARGIN = 40;` (inside `_hitTestTitle`)
- `TitleInteraction.js:255` — `const MARGIN = 40;` (inside `_onPointerDown`)
- `PADDING` is already exported from `TitleRenderer.js:8` and imported in `TitleInteraction.js:16`
- `SizeConstants.js` exists but is for canvas dimensions only (width, height, aspect)

**2. Offscreen Canvas in Interaction Hot Path**
- `TitleInteraction.js:347` — drag handler calls `computeMultiLineBounds(...)` without `measureCtx`
- `TitleInteraction.js:359` — resize-right calls `computeMultiLineBounds(...)` without `measureCtx`
- `TitleInteraction.js:370` — resize-left calls `computeMultiLineBounds(...)` without `measureCtx`
- Each call triggers `document.createElement('canvas')` inside `computeMultiLineBounds` (line 147-150 of `TitleRenderer.js`)
- The `measureCtx` parameter already exists on both `computeBounds` and `computeMultiLineBounds`

**3. Test Import Mismatch**
- `TitleInteractionTest.html:25` — imports `computeBounds` from `TitleRenderer.js`
- Production code exclusively uses `computeMultiLineBounds`
- For single-line tests the results are identical, but alignment is cleaner

### CR1 — UX Items

**4. Enter Key Flicker**
- `index.html:160` — `<textarea id="titleInput" v-model="titleText" @input="onTitleTextChange" ... rows="3">`
- User has 3 lines, presses Enter → textarea renders 4th line → Vue reactivity calls `onTitleTextChange` → `TitleManager.setText` clamps to 3 lines → `titleText` updates → textarea re-renders to 3 lines
- The intermediate 4-line frame is visible as a flicker

**5. Silent Truncation**
- `TitleManager.js:126-138` — `setText` clamps to 3 lines via `lines.slice(0, 3)` with no return value or notification
- User pastes 5-line quote → only first 3 lines appear → no feedback

**6. Leading Newline Stripping**
- `TitleRenderer.js:113-116` — `splitRunsByNewline` removes leading empty lines via `while (lines[0].length === 0) lines.shift()`
- User types `\n\nHello` → renders as single line "Hello" with no indication

**7. Formatting Button ARIA**
- `index.html:164-171` — Bold/Italic/Underline buttons have `:class="{ active: ... }"` but no `aria-pressed`
- Screen readers cannot determine toggle state

**8. Textarea Labeling**
- `index.html:159` — `<label for="titleInput">Text</label>` exists
- `index.html:160` — `<textarea id="titleInput" ...>` matches the label's `for` attribute
- Association is intact, but the label text "Text" is not descriptive

**9. Mobile Touch Targets**
- `TitleInteraction.js:31` — `const EDGE_THRESHOLD = 8;` (CSS pixels)
- WCAG recommends minimum 44x44px touch targets
- 8px edge threshold is too small for reliable touch interaction

### CR2 — Progress Bar

- `ImageLibrary.js:21-38` — `addImages` loads all images via `Promise.all` then pushes to state
- No progress callback mechanism exists
- `createFileHandlers.js:31-41` — `handleFileInputChange` calls `imageLibrary.addImages(files)` then `onRegenerate`
- `createCollageLifecycle.js:261-264` — drop handler calls `imageLibrary.addImages(files)` then `_regenerateAndRender`
- `createCollageData.js` — no image loading progress state
- `index.html:126-133` — `.canvas-container` has `position: relative` (good for absolute overlay)

### Key Discoveries

- `TitleRenderer.js:7` — MARGIN is module-scoped, not exported (unlike PADDING on line 8)
- `TitleInteraction.js:16` — already imports `PADDING` from TitleRenderer
- `TitleRenderer.js:138-150` — `computeMultiLineBounds` accepts optional `measureCtx` parameter
- `TitleManager.js:126-138` — `setText` returns nothing; truncation is silent
- `index.html:160` — textarea has `rows="3"` but no `@keydown.enter` guard
- `ImageLibrary.js:25-26` — `Promise.all` with `map` — each image resolves independently, enabling per-image progress counting
- `Style.css:294-303` — `.canvas-container` is `position: relative` with `overflow: hidden`
- `Style.css:825-843` — toast notification system already exists with `showToast` method

## Desired End State

### Phase 1: Code Quality
- `MARGIN` exported from `TitleRenderer.js`, imported by `TitleInteraction.js`, no local declarations
- Single shared offscreen canvas created at handler init, passed as `measureCtx` to all `computeMultiLineBounds` calls
- `TitleInteractionTest.html` imports `computeMultiLineBounds` instead of `computeBounds`

### Phase 2: UX + Accessibility
- Pressing Enter on a 3-line title is prevented (no flicker)
- Pasting text exceeding 3 lines shows a toast: "Title limited to 3 lines"
- Leading newline stripping is documented in code comment
- Bold/Italic/Underline buttons have `aria-pressed` bound to active state
- Textarea label reads "Title" instead of "Text"
- Touch devices get wider EDGE_THRESHOLD (16px vs 8px)

### Phase 3: Progress Bar
- When adding images via file picker or drag-drop, a progress overlay appears on the canvas
- Overlay shows: "Loading images... N / M" with a progress bar fill
- Existing canvas content remains visible (frozen) underneath
- Overlay disappears when all images are loaded
- Overlay is accessible via `role="progressbar"` with ARIA attributes

## What We're NOT Doing

- **Automatic word wrapping** in title textarea — lines are explicit `\n` only (unchanged)
- **Per-line formatting** — Bold/Italic/Underline still apply to character ranges across all lines
- **Byte-level progress** — FileReader for local files doesn't fire progress events; we use per-image counting
- **Indeterminate spinner** — we use a determinate counter (N/M images) since we know the total
- **Blocking the UI** — overlay uses `pointer-events: none` so clicks pass through; the canvas is visually frozen but not interaction-blocked
- **MARGIN in SizeConstants.js** — MARGIN is a title-rendering constant, not a canvas dimension constant. It belongs with PADDING in TitleRenderer.js.
- **Preserving leading newlines** — the stripping behavior is intentional and will be documented, not changed

## Implementation Approach

### Phase 1: Code Quality (P1 — structural correctness)

Three isolated, low-risk changes. No user-visible behavior changes. Can be implemented in any order.

### Phase 2: UX + Accessibility (P0 — core user behavior)

Six changes to the title editing experience. Items 4 and 5 both modify the textarea in `index.html` and `createTitleHandlers.js`, so they should be coordinated. Items 7 and 8 are simple template attribute additions. Item 9 requires a runtime pointer-type check in `TitleInteraction.js`.

### Phase 3: Progress Bar (P0 — core user behavior)

Requires coordinated changes across 5 files: state shape, ImageLibrary callback, file handler wiring, lifecycle wiring, and template + CSS. Implement in dependency order: state → library → handlers → template/CSS.

---

## Phase 1: Code Quality

### Overview
Deduplicate MARGIN constant, share offscreen canvas in interaction hot path, align test imports. No user-visible changes.

### Changes Required:

#### 1. Export MARGIN from TitleRenderer.js
**File**: `MyESModules/Rendering/TitleRenderer.js`
**Changes**: Change `const MARGIN = 40;` to `export const MARGIN = 40;` on line 7.

```javascript
// BEFORE (line 7)
const MARGIN = 40;

// AFTER
export const MARGIN = 40;
```

#### 2. Import and use MARGIN in TitleInteraction.js
**File**: `MyESModules/Interaction/TitleInteraction.js`
**Changes**:
- Line 16: Add `MARGIN` to import from `TitleRenderer.js`
- Line 150: Remove `const MARGIN = 40;` declaration, use imported `MARGIN`
- Line 255: Remove `const MARGIN = 40;` declaration, use imported `MARGIN`

```javascript
// Line 16 — BEFORE
import { computeMultiLineBounds, PADDING } from '../Rendering/TitleRenderer.js';

// Line 16 — AFTER
import { computeMultiLineBounds, PADDING, MARGIN } from '../Rendering/TitleRenderer.js';
```

#### 3. Shared offscreen canvas in TitleInteraction.js
**File**: `MyESModules/Interaction/TitleInteraction.js`
**Changes**: Create a shared offscreen canvas at factory init time, pass `measureCtx` to all `computeMultiLineBounds` calls.

```javascript
// Inside createTitleInteraction(), after const declarations (~line 31):
const measureCanvas = document.createElement('canvas');
const measureCtx = measureCanvas.getContext('2d');
```

Then pass `measureCtx` to every `computeMultiLineBounds` call:

- Line 134 (`_hitTestTitle`): add `measureCtx` as 5th argument
- Line 239 (`_onPointerDown`): add `measureCtx` as 5th argument
- Line 347 (drag handler): add `measureCtx` as 5th argument
- Line 359 (resize-right): add `measureCtx` as 5th argument
- Line 370 (resize-left): add `measureCtx` as 5th argument

#### 4. Fix test import
**File**: `MyComponents/TitleInteractionTest.html`
**Changes**: Line 25 — change import from `computeBounds` to `computeMultiLineBounds`.

```javascript
// BEFORE (line 25)
import { computeBounds } from '../MyESModules/Rendering/TitleRenderer.js';

// AFTER
import { computeMultiLineBounds } from '../MyESModules/Rendering/TitleRenderer.js';
```

### Behavior Scenarios

#### MARGIN Constant Deduplication

| # | Given | When | Then |
|---|-------|------|------|
| 1.1.1 | MARGIN is exported from TitleRenderer.js | TitleInteraction.js imports MARGIN | Both files reference the same value (40) |
| 1.1.2 | MARGIN is imported in TitleInteraction.js | `_hitTestTitle` computes legacy-mode box position | It uses the imported MARGIN, not a local constant |
| 1.1.3 | MARGIN is imported in TitleInteraction.js | `_onPointerDown` computes legacy-mode drag start position | It uses the imported MARGIN, not a local constant |

#### Shared Offscreen Canvas

| # | Given | When | Then |
|---|-------|------|------|
| 1.2.1 | TitleInteraction handler is created | A shared offscreen canvas is created at init | Exactly 1 offscreen canvas exists (not created per pointermove) |
| 1.2.2 | computeMultiLineBounds is called with measureCtx | It measures text width | It uses the provided context, not `document.createElement('canvas')` |
| 1.2.3 | 100 pointermove events fire during drag | computeMultiLineBounds is called each time | No new canvases are created (uses shared measureCtx) |

#### Test Import Alignment

| # | Given | When | Then |
|---|-------|------|------|
| 1.3.1 | TitleInteractionTest.html imports computeMultiLineBounds | Test suite loads | No unused `computeBounds` import exists |

### Success Criteria:

#### Automated Verification:
- [ ] `node scripts/run-tests.js` passes — all existing TitleInteraction tests still pass
- [ ] No `const MARGIN = 40` declarations remain in `TitleInteraction.js`
- [ ] `MARGIN` appears in the import statement of `TitleInteraction.js`
- [ ] `computeMultiLineBounds` (not `computeBounds`) is imported in `TitleInteractionTest.html`

#### Manual Verification:
- [ ] Title drag and resize interaction works identically before and after changes
- [ ] No console errors on page load or during interaction

---

## Phase 2: UX + Accessibility

### Overview
Six user-facing improvements: Enter key guard, truncation toast, newline documentation, ARIA states, label text, and touch target sizing.

### Changes Required:

#### 1. Enter Key Flicker Prevention
**File**: `index.html`
**Changes**: Add `@keydown.enter.prevent` handler to the textarea that only prevents when 3+ lines exist.

```html
<!-- BEFORE (line 160) -->
<textarea id="titleInput" v-model="titleText" @input="onTitleTextChange" @select="onTitleSelectionChange" @click="onTitleSelectionChange" @keyup="onTitleSelectionChange" placeholder="Enter title text (up to 3 lines)..." rows="3" maxlength="200" class="pure-input-rounded title-textarea"></textarea>

<!-- AFTER -->
<textarea id="titleInput" v-model="titleText" @input="onTitleTextChange" @select="onTitleSelectionChange" @click="onTitleSelectionChange" @keyup="onTitleSelectionChange" @keydown.enter="onTitleEnterKey" placeholder="Enter title text (up to 3 lines)..." rows="3" maxlength="200" class="pure-input-rounded title-textarea"></textarea>
```

**File**: `MyESModules/App/createTitleHandlers.js`
**Changes**: Add `onTitleEnterKey` method that prevents Enter when text already has 3+ lines.

```javascript
/**
 * Prevents Enter key from creating a 4th line.
 * @param {KeyboardEvent} event
 */
onTitleEnterKey(event) {
    const lineCount = (this.titleText || '').split('\n').length;
    if (lineCount >= 3) {
        event.preventDefault();
    }
}
```

**File**: `MyESModules/App/createCollageMethods.js`
**Changes**: Add `onTitleEnterKey` delegation in the title handlers section (~line 209).

```javascript
onTitleEnterKey(event) {
    titleHandlers.onTitleEnterKey.call(this, event);
},
```

#### 2. Silent Truncation Toast
**File**: `MyESModules/State/TitleManager.js`
**Changes**: `setText` returns a result object indicating whether truncation occurred.

```javascript
// BEFORE (lines 126-139)
setText(text) {
    const t = String(text || '');
    const lines = t.split('\n');
    const clampedText = lines.length > 3 ? lines.slice(0, 3).join('\n') : t;
    state.titleText = clampedText;
    if (clampedText.length === 0) {
        state.titleRuns = [];
    } else {
        state.titleRuns = [createTitleRun(clampedText, false, false, false)];
    }
    notify();
}

// AFTER
setText(text) {
    const t = String(text || '');
    const lines = t.split('\n');
    const wasTruncated = lines.length > 3;
    const clampedText = lines.length > 3 ? lines.slice(0, 3).join('\n') : t;
    state.titleText = clampedText;
    if (clampedText.length === 0) {
        state.titleRuns = [];
    } else {
        state.titleRuns = [createTitleRun(clampedText, false, false, false)];
    }
    notify();
    return { truncated: wasTruncated };
}
```

**File**: `MyESModules/App/createTitleHandlers.js`
**Changes**: `onTitleTextChange` checks return value and shows toast.

```javascript
// BEFORE
onTitleTextChange() {
    const titleManager = getTitleManager();
    if (titleManager) {
        titleManager.setText(this.titleText);
    }
    onRenderScheduled(this);
},

// AFTER
onTitleTextChange() {
    const titleManager = getTitleManager();
    if (titleManager) {
        const result = titleManager.setText(this.titleText);
        if (result && result.truncated && this.showToast) {
            this.showToast('Title limited to 3 lines', 'info', 3000);
        }
    }
    onRenderScheduled(this);
},
```

#### 3. Leading Newline Documentation
**File**: `MyESModules/Rendering/TitleRenderer.js`
**Changes**: Add JSDoc comment above lines 113-116 documenting the intentional behavior.

```javascript
    // Remove empty leading lines — leading \n characters are silently
    // consumed. This matches the design intent: title text should not
    // have invisible blank lines at the top.
    while (lines.length > 1 && lines[0].length === 0) {
        lines.shift();
    }
```

#### 4. Formatting Button ARIA States
**File**: `index.html`
**Changes**: Add `aria-pressed` binding to Bold, Italic, and Underline buttons (lines 164-171).

```html
<!-- BEFORE -->
<button class="format-btn" :class="{ active: isTitleFormatActive('bold') }" @mousedown.prevent @click="toggleTitleBold" title="Bold" :disabled="titleSelectionStart === titleSelectionEnd">
    <strong>B</strong>
</button>

<!-- AFTER -->
<button class="format-btn" :class="{ active: isTitleFormatActive('bold') }" @mousedown.prevent @click="toggleTitleBold" title="Bold" :disabled="titleSelectionStart === titleSelectionEnd" :aria-pressed="isTitleFormatActive('bold')">
    <strong>B</strong>
</button>
```

Apply same `:aria-pressed="isTitleFormatActive('...')"` to Italic and Underline buttons.

#### 5. Textarea Label Text
**File**: `index.html`
**Changes**: Line 159 — change label text from "Text" to "Title".

```html
<!-- BEFORE -->
<label for="titleInput">Text</label>

<!-- AFTER -->
<label for="titleInput">Title</label>
```

#### 6. Mobile Touch Target Sizing
**File**: `MyESModules/Interaction/TitleInteraction.js`
**Changes**: Use pointer type to determine EDGE_THRESHOLD at pointer-down time instead of a fixed constant. Replace the constant with a function.

```javascript
// BEFORE (line 31)
const EDGE_THRESHOLD = 8;   // CSS pixels — resize handle hit area

// AFTER
const EDGE_THRESHOLD_FINE = 8;    // CSS pixels — mouse resize handle hit area
const EDGE_THRESHOLD_COARSE = 16; // CSS pixels — touch resize handle hit area
```

In `_hitTestTitle`, accept an optional `pointerType` parameter:
```javascript
// Change signature from:
_hitTestTitle(cssX, cssY, canvasWidth, canvasHeight) {
// To:
_hitTestTitle(cssX, cssY, canvasWidth, canvasHeight, pointerType) {
```

Replace `EDGE_THRESHOLD` usage with dynamic threshold:
```javascript
const edgeThreshold = pointerType === 'touch' ? EDGE_THRESHOLD_COARSE : EDGE_THRESHOLD_FINE;

// Replace:
if (distToLeft <= EDGE_THRESHOLD) {
// With:
if (distToLeft <= edgeThreshold) {

// Replace:
if (distToRight <= EDGE_THRESHOLD) {
// With:
if (distToRight <= edgeThreshold) {
```

Update callers to pass `e.pointerType`:
- `_onPointerDown` line 223: `this._hitTestTitle(coords.x, coords.y, canvasWidth, canvasHeight, e.pointerType)`
- `_onPointerMove` line 390: `this._hitTestTitle(coords.x, coords.y, canvasWidth, canvasHeight, e.pointerType)`

### Behavior Scenarios

#### Enter Key Flicker (P0)

| # | Given | When | Then |
|---|-------|------|------|
| 2.1.1 | Title textarea has 3 lines of text ("Line1\nLine2\nLine3") | User presses Enter at cursor position | Enter is prevented; no 4th line appears; text remains 3 lines |
| 2.1.2 | Title textarea has 2 lines of text ("Line1\nLine2") | User presses Enter at end of line 2 | Enter is allowed; text becomes 3 lines ("Line1\nLine2\n") |
| 2.1.3 | Title textarea has 1 line of text ("Line1") | User presses Enter | Enter is allowed; text becomes 2 lines ("Line1\n") |
| 2.1.4 | Title textarea is empty | User presses Enter | Enter is allowed; text becomes 1 empty line |

#### Truncation Toast (P0)

| # | Given | When | Then |
|---|-------|------|------|
| 2.2.1 | User pastes 5 lines of text into the title textarea | `onTitleTextChange` processes the input | Toast appears: "Title limited to 3 lines" (info type, 3s duration); textarea shows only first 3 lines |
| 2.2.2 | User types text with exactly 3 lines | `onTitleTextChange` processes the input | No toast appears; text is preserved |
| 2.2.3 | User types text with 2 lines | `onTitleTextChange` processes the input | No toast appears; text is preserved |
| 2.2.4 | User pastes 10 lines into the title textarea | `onTitleTextChange` processes the input | Toast appears once; textarea shows only first 3 lines |

#### Formatting Button ARIA (P1)

| # | Given | When | Then |
|---|-------|------|------|
| 2.4.1 | Bold button is active (selection includes bold text) | Button is inspected by screen reader | `aria-pressed="true"` is present |
| 2.4.2 | Bold button is inactive (selection has no bold text) | Button is inspected by screen reader | `aria-pressed="false"` is present |
| 2.4.3 | Italic button is active | Button is inspected | `aria-pressed="true"` is present |
| 2.4.4 | Underline button is active | Button is inspected | `aria-pressed="true"` is present |

#### Textarea Label (P1)

| # | Given | When | Then |
|---|-------|------|------|
| 2.5.1 | Title section is visible | Screen reader focuses the textarea | Label "Title" is announced (not "Text") |

#### Mobile Touch Targets (P1)

| # | Given | When | Then |
|---|-------|------|------|
| 2.6.1 | Device has coarse pointer (touchscreen, `pointerType === 'touch'`) | User hovers over title box edge | EDGE_THRESHOLD is 16px (not 8px) |
| 2.6.2 | Device has fine pointer (mouse, `pointerType === 'mouse'`) | User hovers over title box edge | EDGE_THRESHOLD is 8px (unchanged) |
| 2.6.3 | Device has pen pointer (`pointerType === 'pen'`) | User hovers over title box edge | EDGE_THRESHOLD is 8px (fine pointer) |

### Success Criteria:

#### Automated Verification:
- [ ] `node scripts/run-tests.js` passes — all existing tests still pass
- [ ] `MARGIN` is exported from `TitleRenderer.js`
- [ ] No local `const MARGIN` declarations in `TitleInteraction.js`
- [ ] `computeMultiLineBounds` imported in `TitleInteractionTest.html` (not `computeBounds`)

#### Manual Verification:
- [ ] Pressing Enter on 3-line title does not cause visual flicker
- [ ] Pasting 5+ lines of text shows "Title limited to 3 lines" toast
- [ ] Typing 3 or fewer lines does NOT show toast
- [ ] Bold/Italic/Underline buttons have `aria-pressed` attribute in DOM
- [ ] Textarea label reads "Title" (not "Text")
- [ ] Touch device resize handles are wider (16px threshold)
- [ ] Mouse device resize handles unchanged (8px threshold)
- [ ] Title drag and resize interaction works identically before and after

---

## Phase 3: Progress Bar When Adding Images

### Overview
Add a determinate progress overlay on the canvas during image loading. Uses per-image completion counting (N/M images) since FileReader for local files doesn't fire progress events.

### Changes Required:

#### 1. Progress State
**File**: `MyESModules/App/createCollageData.js`
**Changes**: Add `imageLoadingProgress` to data return value.

```javascript
// Add after "images: []" (~line 13):
imageLoadingProgress: {
    visible: false,
    current: 0,
    total: 0
},
```

#### 2. ImageLibrary Progress Callback
**File**: `MyESModules/State/ImageLibrary.js`
**Changes**: `addImages` accepts optional `onProgress` callback. Progress fires per-image as each image resolves.

```javascript
// BEFORE
async addImages(files) {
    const imageFiles = Array.from(files).filter(f => f.type.startsWith('image/'));
    if (imageFiles.length === 0) return;

    const newItems = await Promise.all(
        imageFiles.map(file => this._loadImage(file))
    );
    // ...
}

// AFTER
async addImages(files, onProgress) {
    const imageFiles = Array.from(files).filter(f => f.type.startsWith('image/'));
    if (imageFiles.length === 0) return;

    let loaded = 0;
    const newItems = await Promise.all(
        imageFiles.map(async (file) => {
            const item = await this._loadImage(file);
            loaded++;
            if (typeof onProgress === 'function') {
                onProgress(loaded, imageFiles.length);
            }
            return item;
        })
    );
    // ... rest unchanged
}
```

#### 3. File Handler Progress Wiring
**File**: `MyESModules/App/createFileHandlers.js`
**Changes**: Accept optional `onImageLoadingProgress` callback parameter and wire it through.

```javascript
// BEFORE
export function createFileHandlers(getImageLibrary, onRegenerate, fileInputId = 'fileInput') {

// AFTER
export function createFileHandlers(getImageLibrary, onRegenerate, fileInputId = 'fileInput', onImageLoadingProgress = null) {
```

In `handleFileInputChange`:
```javascript
async handleFileInputChange() {
    const input = document.getElementById(fileInputId);
    const files = input ? input.files : null;
    if (files && files.length > 0) {
        const imageLibrary = getImageLibrary();
        const imageFiles = Array.from(files).filter(f => f.type.startsWith('image/'));

        if (onImageLoadingProgress) {
            onImageLoadingProgress(0, imageFiles.length);
        }

        await imageLibrary.addImages(files, (current, total) => {
            if (onImageLoadingProgress) {
                onImageLoadingProgress(current, total);
            }
        });

        onRegenerate(this);
        if (input) input.value = '';
    }
}
```

#### 4. CollageMethods Progress Wiring
**File**: `MyESModules/App/createCollageMethods.js`
**Changes**: Wire progress callback from `createFileHandlers` and add progress control methods.

```javascript
// In fileHandlers creation (~line 55):
const fileHandlers = createFileHandlers(
    () => base.getImageLibrary(),
    (vm) => renderMethods._regenerateAndRender(vm),
    ids.fileInput,
    (vm, current, total) => vm._setImageLoadingProgress(current, total)
);
```

Add progress control methods to the returned methods object:
```javascript
// Add after showToast method (~line 297):
beginImageLoading(total) {
    this.imageLoadingProgress.visible = true;
    this.imageLoadingProgress.current = 0;
    this.imageLoadingProgress.total = total;
},
updateImageLoadingProgress(current, total) {
    this.imageLoadingProgress.current = current;
    this.imageLoadingProgress.total = total;
},
endImageLoading() {
    this.imageLoadingProgress.visible = false;
    this.imageLoadingProgress.current = 0;
    this.imageLoadingProgress.total = 0;
},
/**
 * @private
 * Called by file handler progress callback.
 */
_setImageLoadingProgress(current, total) {
    if (current === 0) {
        this.beginImageLoading(total);
    } else {
        this.updateImageLoadingProgress(current, total);
        if (current >= total) {
            this.endImageLoading();
        }
    }
},
```

#### 5. Lifecycle Drop Handler Progress
**File**: `MyESModules/App/createCollageLifecycle.js`
**Changes**: Wire progress in the global drop handler (lines 261-264).

```javascript
// BEFORE
this._dropCleanup = base.dropHandler.setupGlobalDrop(async (files) => {
    await imageLibrary.addImages(files);
    this._regenerateAndRender();
});

// AFTER
this._dropCleanup = base.dropHandler.setupGlobalDrop(async (files) => {
    const imageFiles = files.filter(f => f.type.startsWith('image/'));
    if (imageFiles.length > 0) {
        this.beginImageLoading(imageFiles.length);
    }
    await imageLibrary.addImages(files, (current, total) => {
        this.updateImageLoadingProgress(current, total);
    });
    this.endImageLoading();
    this._regenerateAndRender();
});
```

#### 6. Template Overlay
**File**: `index.html`
**Changes**: Add progress overlay inside `.canvas-container` after the canvas element.

```html
<!-- Add after line 132 (the canvas element), before the closing </div> of canvasContainer -->
<!-- Progress overlay for image loading -->
<div class="progress-overlay" v-show="imageLoadingProgress.visible"
     role="progressbar"
     :aria-valuenow="imageLoadingProgress.current"
     :aria-valuemax="imageLoadingProgress.total"
     aria-label="Loading images">
    <div class="progress-bar-track">
        <div class="progress-bar-fill"
             :style="{ width: (imageLoadingProgress.total > 0
                ? (imageLoadingProgress.current / imageLoadingProgress.total) * 100
                : 0) + '%' }">
        </div>
    </div>
    <span class="progress-label">{{ imageLoadingProgress.current }} / {{ imageLoadingProgress.total }} images</span>
</div>
```

#### 7. Progress Bar CSS
**File**: `Style.css`
**Changes**: Add progress overlay styles at the end of the file.

```css
/* ========================
 * Image Loading Progress Overlay
 * ======================== */

.progress-overlay {
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    background-color: rgba(0, 0, 0, 0.4);
    border-radius: var(--radius-small);
    z-index: 10;
    gap: 12px;
    pointer-events: none;
}

.progress-bar-track {
    width: 200px;
    height: 6px;
    background-color: rgba(255, 255, 255, 0.3);
    border-radius: 3px;
    overflow: hidden;
}

.progress-bar-fill {
    height: 100%;
    background-color: var(--color-primary);
    border-radius: 3px;
    transition: width 0.2s ease;
}

.progress-label {
    color: white;
    font-size: var(--font-size-sm);
    text-shadow: 0 1px 2px rgba(0, 0, 0, 0.5);
}
```

### Behavior Scenarios

#### Progress Overlay Display (P0)

| # | Given | When | Then |
|---|-------|------|------|
| 3.1.1 | Canvas shows an existing collage with 3 images | User adds 5 new images via file picker | Progress overlay appears: "0 / 5 images" with empty progress bar |
| 3.1.2 | 5 images are loading; 3 have completed | Progress callback fires with (3, 5) | Progress bar fill is 60% wide; label reads "3 / 5 images" |
| 3.1.3 | All 5 images have loaded | `addImages` resolves | Progress overlay disappears; canvas shows updated collage |
| 3.1.4 | Canvas has no images (placeholder visible) | User adds 2 images | Progress overlay appears on canvas area; placeholder remains visible underneath |

#### Progress via File Picker (P0)

| # | Given | When | Then |
|---|-------|------|------|
| 3.2.1 | User clicks "Add Images" and selects 3 image files | `handleFileInputChange` processes the files | Progress overlay shows "0 / 3" → "1 / 3" → "2 / 3" → "3 / 3" → disappears |
| 3.2.2 | User selects only non-image files | `handleFileInputChange` filters them out | No progress overlay appears (0 image files) |

#### Progress via Drag-Drop (P0)

| # | Given | When | Then |
|---|-------|------|------|
| 3.3.1 | User drops 4 image files onto the page | Global drop handler processes the files | Progress overlay shows loading progress for all 4 files |
| 3.3.2 | User drops a mix of image and non-image files | Drop handler filters to image files only | Progress total reflects only image file count |

#### Frozen Background (P1)

| # | Given | When | Then |
|---|-------|------|------|
| 3.4.1 | Canvas displays an existing collage | User adds new images | Existing collage remains visible (frozen) underneath the semi-transparent overlay until all new images load |
| 3.4.2 | Progress overlay is visible | User clicks on the canvas area | Click passes through (pointer-events: none) to the canvas underneath |

#### Accessibility (P1)

| # | Given | When | Then |
|---|-------|------|------|
| 3.5.1 | Progress overlay is visible | Screen reader focuses the overlay | It announces as a progress bar with current/max values |
| 3.5.2 | Progress overlay is visible | DOM is inspected | Element has `role="progressbar"`, `aria-valuenow`, `aria-valuemax`, and `aria-label` |

### Success Criteria:

#### Automated Verification:
- [ ] `node scripts/run-tests.js` passes — all existing tests still pass
- [ ] `imageLoadingProgress` property exists in `createCollageData.js` data return
- [ ] `addImages` in `ImageLibrary.js` accepts optional `onProgress` callback
- [ ] `createFileHandlers` accepts optional 4th parameter `onImageLoadingProgress`

#### Manual Verification:
- [ ] Adding images via file picker shows progress overlay with N/M counter
- [ ] Adding images via drag-drop shows progress overlay with N/M counter
- [ ] Progress bar fill width matches percentage (e.g., 2/5 = 40%)
- [ ] Progress overlay disappears when all images are loaded
- [ ] Existing collage content is visible (frozen) under semi-transparent overlay
- [ ] Overlay has `role="progressbar"` with ARIA attributes
- [ ] No progress overlay appears when adding non-image files
- [ ] No progress overlay appears when no files are added

---

## Testing Strategy

### Unit Tests (existing + new)

**Phase 1:**
- Existing `TitleInteractionTest.html` tests continue to pass with MARGIN import and shared canvas
- No new tests needed — behavior is unchanged

**Phase 2:**
- `TitleManagerTest.html`: Add test for `setText` return value when text exceeds 3 lines
- `TitleManagerTest.html`: Add test for `setText` return value when text is within 3 lines
- `TitleInteractionTest.html`: Update import from `computeBounds` to `computeMultiLineBounds`

**Phase 3:**
- No new unit tests — progress bar is a UI/state feature best validated by E2E

### E2E Tests (Playwright)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| E.1 | Enter key prevented on 3-line title | 1. Load app 2. Add images 3. Enter 3 lines in title textarea 4. Press Enter | Textarea remains 3 lines, no flicker |
| E.2 | Truncation toast on paste | 1. Load app 2. Paste 5-line text into title textarea | Toast "Title limited to 3 lines" appears |
| E.3 | aria-pressed on format buttons | 1. Load app 2. Select title text 3. Click Bold | Bold button has `aria-pressed="true"` |
| E.4 | Progress overlay on file add | 1. Load app 2. Click "Add Images" 3. Select multiple images | Progress overlay appears with N/M counter |
| E.5 | Progress overlay disappears after load | 1. Add images via file picker | Overlay disappears when all images loaded |
| E.6 | Progress overlay on drag-drop | 1. Load app 2. Drag-drop image files | Progress overlay appears during loading |

### Manual Testing Steps
1. **MARGIN dedup**: Verify title drag/resize works identically after removing local MARGIN constants
2. **Enter key**: Type 3 lines in title, press Enter — no 4th line appears
3. **Truncation toast**: Paste a 10-line quote — toast appears, only 3 lines shown
4. **ARIA**: Use browser dev tools to verify `aria-pressed` on format buttons
5. **Label**: Verify "Title" label (not "Text") on textarea
6. **Touch targets**: On mobile device, verify resize handles are easier to target
7. **Progress bar (file picker)**: Add 5+ images — watch progress counter increment
8. **Progress bar (drag-drop)**: Drop 3 images — watch progress counter increment
9. **Progress bar (no images)**: Drop non-image files — no progress overlay
10. **Progress bar (accessibility)**: Use screen reader to verify progress bar announcement

## Performance Considerations

- **Shared offscreen canvas** (Phase 1): Eliminates per-pointermove canvas creation. For a typical drag with 60fps × 1s = 60 pointermove events, this prevents 60 unnecessary canvas allocations.
- **Progress overlay** (Phase 3): Uses `v-show` (not `v-if`) for instant show/hide. CSS `pointer-events: none` prevents event handling overhead. The overlay is lightweight (3 DOM elements).
- **Toast notification** (Phase 2): Reuses existing toast system. 3-second auto-dismiss prevents notification accumulation.

## Migration Notes

- No data migration needed
- No breaking changes to public APIs
- `ImageLibrary.addImages` accepts optional `onProgress` — existing callers without it work unchanged
- `TitleManager.setText` returns a result object — existing callers that ignore the return value are unaffected

## References

- `_agent_docs/specifications/change-requests/2026-07-18-01-review-followups.md`
- `_agent_docs/specifications/change-requests/2026-07-18-02-progress-bar-when-adding-images.md`
- `_agent_docs/reviews/2026-07-18-title-changes-review.md`
- `_agent_docs/plans/2026-07-17-title-changes-implementation.md` (previous title changes plan)
- `building-web-apps` skill: accessibility (ARIA live regions, aria-pressed, progressbar role), toast notifications, factory testability patterns
