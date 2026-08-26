# Code Review Fixes Implementation Plan

**Date:** 2026-07-15
**Source:** `_agent_docs/reviews/2026-07-15-title-sidebar-home-review.md`
**Original Plan:** `_agent_docs/plans/2026-07-13-title-sidebar-home-implementation.md`

## Overview

This plan addresses the issues identified in the pre-commit code review for the title sidebar + home link feature. The review returned **REQUEST CHANGES** with one critical blocking issue (missing settings persistence for new title fields) and four important issues (hardcoded constants, drag clamping, ARIA attributes, handler simplification).

## Current State Analysis

### CI-1: Missing Settings Persistence (CRITICAL)
- `createSettingsHandlers.js` `_saveSettings()` saves only 4 title fields: `fontFamily`, `fontSize`, `fontColor`, `alignment`
- `createCollageLifecycle.js` `_applySavedSettings()` restores only those same 4 fields
- **7 title fields are missing** from both save and restore: `fontOpacity`, `bgOpacity`, `titleBoxWidth`, `titleBoxX`, `titleBoxY`, `showBackground`, `backgroundColor`
- All title customization is lost on page reload — effectively breaking the feature for any real workflow

### II-1: Hardcoded Canvas Dimensions
- `TitleInteraction.js` hardcodes `1920` and `1080` in 12 locations across `_hitTestTitle`, `_onPointerDown`, and `_onPointerMove`
- `SIZE_CONSTANTS` exists at `MyESModules/Models/SizeConstants.js` with `defaultCanvasWidth: 1920` and `defaultCanvasHeight: 1080`

### II-2: Title Drag Boundary Clamping
- X-axis: `Math.max(0, Math.min(newX, 1920 - actualBoxWidth))` — allows title to be dragged fully off-canvas horizontally with no recovery
- Y-axis: `Math.max(fontSize + 12, Math.min(newY, 1080 - 12))` — acceptable as-is (box top stays at y=0 minimum)

### II-3: Width Slider ARIA
- `index.html` line 227: `titleWidthSlider` missing `aria-valuenow`, `aria-valuemin`, `aria-valuemax`
- Opacity sliders (lines 193, 203) already have proper ARIA attributes as a reference pattern

### II-4: Handler Parameter Handling
- `createTitleHandlers.js` line 194: `onTitleWidthChange(value)` accepts optional parameter with fragile fallback logic
- All other handlers in the same file read directly from `this.titleStyle.*` — this one should be consistent

## Desired End State

After this plan is complete:
1. All title style fields (including new ones) survive a page reload
2. TitleInteraction uses `SIZE_CONSTANTS` instead of hardcoded dimensions
3. Title drag keeps at least 50px of the box visible at all edges
4. Width slider has full ARIA support matching opacity slider pattern
5. `onTitleWidthChange` follows the same pattern as all other title handlers

### Key Discoveries:
- `createSettingsHandlers.js` has a `_applySavedSettings(state, settings)` method that is **never called** — the live code is the method on `createCollageLifecycle.js` (line 352)
- `createCollageMethods.js` wraps `onTitleWidthChange` and calls it with **no arguments** (`titleHandlers.onTitleWidthChange.call(this)`) — confirming the `value` parameter is unnecessary
- The `MARGIN=40` literal in `TitleInteraction.js` (line 138, 211) is duplicated from `TitleRenderer.js` — out of scope for this plan
- `_saveSettings()` is called from `createCollageMethods.js` `onLayoutStyleChange()` — settings are saved on layout changes but not on every title change. This is a pre-existing behavior, not a regression introduced by this plan.

## What We're NOT Doing

- **Not adding debounced auto-save on every title change** — pre-existing save behavior is preserved; this plan only fixes the payload completeness
- **Not extracting MARGIN/PADDING constants** — duplicated literals in TitleInteraction.js are a separate concern
- **Not adding keyboard nudging for title position** — documented as out-of-scope accessibility limitation
- **Not adding visual resize handles for touch devices** — deferred to future polish
- **Not deleting dead code** (`createSettingsHandlers._applySavedSettings`) — minimize blast radius; flag for future cleanup
- **Not adding interaction hint text** — deferred to future polish

## Implementation Approach

Two phases: **Persistence** (critical, self-contained) and **Polish** (independent improvements, lower risk). II-1 and II-2 both modify `TitleInteraction.js` and should be done in the same pass.

---

## Phase 1: Settings Persistence for Title Fields

### Overview

Add the 7 missing title fields to both the save payload and the restore logic. This is the only blocking issue from the review.

### Changes Required:

#### 1. `createSettingsHandlers.js` — Save Payload
**File**: `MyESModules/App/createSettingsHandlers.js`
**Changes**: Add 7 fields to `_saveSettings()` payload (lines 19-33)

```javascript
_saveSettings(state) {
    try {
        saveSettings({
            layoutStyle: state.layoutStyle,
            gutter: state.gutter,
            sliceAngle: state.sliceAngle,
            hexSpacing: state.hexSpacing,
            backgroundStyle: state.backgroundStyle,
            backgroundColor: state.backgroundColor,
            gradientColors: state.gradientColors,
            gradientAngle: state.gradientAngle,
            titleFontFamily: state.titleStyle.fontFamily,
            titleFontSize: state.titleStyle.fontSize,
            titleFontColor: state.titleStyle.fontColor,
            titleAlignment: state.titleStyle.alignment,
            // NEW: Title opacity, position, width, and background fields
            titleFontOpacity: state.titleStyle.fontOpacity,
            titleBgOpacity: state.titleStyle.bgOpacity,
            titleBoxWidth: state.titleStyle.titleBoxWidth,
            titleBoxX: state.titleStyle.titleBoxX,
            titleBoxY: state.titleStyle.titleBoxY,
            titleShowBackground: state.titleStyle.showBackground,
            titleBackgroundColor: state.titleStyle.backgroundColor,
            exportQuality: state.exportQuality
        });
    } catch (e) {
        console.warn('Failed to save settings:', e);
    }
},
```

**Naming rationale:** `titleBackgroundColor` (not `backgroundColor`) to avoid collision with the collage-level `backgroundColor` key. Same prefix convention as existing `titleFontFamily`, `titleFontSize`, etc.

#### 2. `createCollageLifecycle.js` — Restore Logic
**File**: `MyESModules/App/createCollageLifecycle.js`
**Changes**: Add 7 fields to `_applySavedSettings()` method (lines 352-375)

```javascript
_applySavedSettings(settings) {
    if (!settings) return;

    // Layout settings
    if (settings.layoutStyle) this.layoutStyle = settings.layoutStyle;
    if (settings.gutter !== undefined) this.gutter = settings.gutter;
    if (settings.sliceAngle !== undefined) this.sliceAngle = settings.sliceAngle;
    if (settings.hexSpacing !== undefined) this.hexSpacing = settings.hexSpacing;

    // Background settings
    if (settings.backgroundStyle) this.backgroundStyle = settings.backgroundStyle;
    if (settings.backgroundColor) this.backgroundColor = settings.backgroundColor;
    if (settings.gradientColors) this.gradientColors = settings.gradientColors;
    if (settings.gradientAngle !== undefined) this.gradientAngle = settings.gradientAngle;

    // Title settings
    if (settings.titleFontFamily) this.titleStyle.fontFamily = settings.titleFontFamily;
    if (settings.titleFontSize !== undefined) this.titleStyle.fontSize = settings.titleFontSize;
    if (settings.titleFontColor) this.titleStyle.fontColor = settings.titleFontColor;
    if (settings.titleAlignment) this.titleStyle.alignment = settings.titleAlignment;
    // NEW: Restore title opacity, position, width, and background fields
    if (settings.titleFontOpacity !== undefined) this.titleStyle.fontOpacity = settings.titleFontOpacity;
    if (settings.titleBgOpacity !== undefined) this.titleStyle.bgOpacity = settings.titleBgOpacity;
    if (settings.titleBoxWidth !== undefined) this.titleStyle.titleBoxWidth = settings.titleBoxWidth;
    if (settings.titleBoxX !== undefined) this.titleStyle.titleBoxX = settings.titleBoxX;
    if (settings.titleBoxY !== undefined) this.titleStyle.titleBoxY = settings.titleBoxY;
    if (settings.titleShowBackground !== undefined) this.titleStyle.showBackground = settings.titleShowBackground;
    if (settings.titleBackgroundColor) this.titleStyle.backgroundColor = settings.titleBackgroundColor;

    // Export settings
    if (settings.exportQuality !== undefined) this.exportQuality = settings.exportQuality;
},
```

**Guard rationale:** `!== undefined` for numeric/boolean fields (allows `0` and `false` values), truthy check for string fields. This matches the existing pattern used for all other fields.

### Behavior Scenarios

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 1.1.1 | Title font opacity is set to 0.5, bg opacity to 0.7, width to 600, position to (200, 800), background is enabled with color #FF0000 | The user reloads the page | All 7 title fields are restored to their saved values |
| 1.1.2 | Title fields are at default values (fontOpacity=1, bgOpacity=1, titleBoxWidth=null, titleBoxX=null, titleBoxY=null, showBackground=false, backgroundColor='#000000') | The user reloads the page | Title fields remain at defaults |
| 1.1.3 | The user sets fontOpacity=0.3 and titleBoxX=500, then changes layout style (triggering save) | The user reloads the page | fontOpacity=0.3 and titleBoxX=500 are restored |
| 1.1.4 | Saved settings from a previous app version exist (without the new title fields) | The user loads the page | New title fields fall back to their Vue defaults (no crash, no undefined) |

#### Component Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 1.2.1 | `state.titleStyle` has `fontOpacity: 0.5`, `bgOpacity: 0.8`, `titleBoxWidth: 500`, `titleBoxX: 100`, `titleBoxY: 850`, `showBackground: true`, `backgroundColor: '#FF0000'` | `_saveSettings(state)` is called | `save()` receives an object containing `titleFontOpacity: 0.5`, `titleBgOpacity: 0.8`, `titleBoxWidth: 500`, `titleBoxX: 100`, `titleBoxY: 850`, `titleShowBackground: true`, `titleBackgroundColor: '#FF0000'` |
| 1.2.2 | Saved settings include all 7 new title fields | `_applySavedSettings(settings)` is called on a fresh Vue state | `this.titleStyle` has all 7 fields restored to the saved values |
| 1.2.3 | Saved settings include `titleFontOpacity: 0` and `titleShowBackground: false` | `_applySavedSettings(settings)` is called | Values `0` and `false` are correctly restored (not filtered out by truthy check) |
| 1.2.4 | Saved settings do NOT include the new title fields (old settings format) | `_applySavedSettings(settings)` is called | New fields remain at their Vue defaults (no error, no mutation) |

#### Pure Function Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 1.3.1 | Settings object with `titleBoxWidth: null`, `titleBoxX: null`, `titleBoxY: null` | `_applySavedSettings` applies these values | `titleStyle.titleBoxWidth`, `titleBoxX`, `titleBoxY` are set to `null` (triggering legacy centered mode in renderer) |

### Success Criteria:

#### Automated Verification:
- [ ] `SettingsPersistenceTest.html` passes with new round-trip test including all 7 title fields
- [ ] New unit test verifies `_saveSettings` includes all 7 new fields in the save payload
- [ ] New unit test verifies `_applySavedSettings` restores all 7 fields from saved settings
- [ ] New unit test verifies backward compatibility (old settings without new fields don't crash)
- [ ] Existing tests continue to pass

#### Manual Verification:
- [ ] Set title font opacity to 50%, reload page — opacity persists
- [ ] Set title bg opacity to 70%, reload page — opacity persists
- [ ] Set title width to 600px, reload page — width persists
- [ ] Drag title to a custom position on canvas, change layout (triggers save), reload page — position persists
- [ ] Enable title background with custom color, change layout, reload page — background persists
- [ ] Load page with old saved settings (clear localStorage, save without new fields, reload) — no crash

### Test Scenarios

#### Unit Tests — `SettingsPersistenceTest.html` (new section)

| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.T.1 | Save/load round-trip includes all 7 new title fields | Settings with `titleFontOpacity: 0.5`, `titleBgOpacity: 0.8`, `titleBoxWidth: 500`, `titleBoxX: 100`, `titleBoxY: 850`, `titleShowBackground: true`, `titleBackgroundColor: '#FF0000'` | All 7 fields round-trip through save/load |
| 1.T.2 | Save includes `titleBackgroundColor` without colliding with `backgroundColor` | Settings with both `backgroundColor: '#ffffff'` and `titleBackgroundColor: '#FF0000'` | Both keys present and distinct in saved JSON |
| 1.T.3 | Save with `titleBoxWidth: null`, `titleBoxX: null`, `titleBoxY: null` | Settings with null position/width | Null values preserved through round-trip |
| 1.T.4 | Save with `titleFontOpacity: 0`, `titleShowBackground: false` | Settings with falsy values | Falsy values preserved through round-trip |

#### Unit Tests — New `SettingsHandlersTest.html`

| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.T.5 | `_saveSettings` includes all 7 new fields | Mock state with custom title values | `save()` called with object containing all 7 new keys |
| 1.T.6 | `_applySavedSettings` restores all 7 new fields | Settings object with all 7 new fields | `state.titleStyle` has all 7 fields set correctly |
| 1.T.7 | `_applySavedSettings` handles missing new fields gracefully | Settings object without new title fields | No error, existing title fields restored, new fields untouched |
| 1.T.8 | `_applySavedSettings` handles `titleFontOpacity: 0` correctly | Settings with `titleFontOpacity: 0` | `state.titleStyle.fontOpacity` is `0` (not skipped by truthy guard) |
| 1.T.9 | `_applySavedSettings` handles `titleShowBackground: false` correctly | Settings with `titleShowBackground: false` | `state.titleStyle.showBackground` is `false` (not skipped by truthy guard) |

---

## Phase 2: Code Quality & UX Polish

### Overview

Address the four important issues: replace hardcoded canvas dimensions with `SIZE_CONSTANTS`, fix drag boundary clamping, add ARIA attributes to width slider, and simplify `onTitleWidthChange`.

### Changes Required:

#### 1. `TitleInteraction.js` — SIZE_CONSTANTS Import + Refactor
**File**: `MyESModules/Interaction/TitleInteraction.js`
**Changes**: Add import at top, replace 12 hardcoded values

**Import addition** (after line 16):
```javascript
import { SIZE_CONSTANTS } from '../Models/SizeConstants.js';
```

**Replacements** (all occurrences):

| Location | Current | Replace With |
|----------|---------|--------------|
| Line 127 | `computeBounds(state.titleStyle, runs, 1920, 1080)` | `computeBounds(state.titleStyle, runs, SIZE_CONSTANTS.defaultCanvasWidth, SIZE_CONSTANTS.defaultCanvasHeight)` |
| Line 134 | `(1920 - boxWidth) / 2` | `(SIZE_CONSTANTS.defaultCanvasWidth - boxWidth) / 2` |
| Line 138 | `1080 - 40` | `SIZE_CONSTANTS.defaultCanvasHeight - 40` |
| Line 145 | `canvasWidth / 1920` | `canvasWidth / SIZE_CONSTANTS.defaultCanvasWidth` |
| Line 146 | `canvasHeight / 1080` | `canvasHeight / SIZE_CONSTANTS.defaultCanvasHeight` |
| Line 208 | `(1920 - (state.titleStyle.titleBoxWidth ?? 0)) / 2` | `(SIZE_CONSTANTS.defaultCanvasWidth - (state.titleStyle.titleBoxWidth ?? 0)) / 2` |
| Line 211 | `1080 - 40` | `SIZE_CONSTANTS.defaultCanvasHeight - 40` |
| Line 267 | `1920 / canvasWidth` | `SIZE_CONSTANTS.defaultCanvasWidth / canvasWidth` |
| Line 268 | `1080 / canvasHeight` | `SIZE_CONSTANTS.defaultCanvasHeight / canvasHeight` |
| Line 282 | `1920 - actualBoxWidth` | `SIZE_CONSTANTS.defaultCanvasWidth - actualBoxWidth` |
| Line 283 | `1080 - 12` | `SIZE_CONSTANTS.defaultCanvasHeight - 12` |
| Line 291 | `computeBounds(state.titleStyle, runs, 1920, 1080)` | `computeBounds(state.titleStyle, runs, SIZE_CONSTANTS.defaultCanvasWidth, SIZE_CONSTANTS.defaultCanvasHeight)` |
| Line 293 | `1920 - 80` | `SIZE_CONSTANTS.defaultCanvasWidth - 80` |
| Line 302 | `computeBounds(state.titleStyle, runs, 1920, 1080)` | `computeBounds(state.titleStyle, runs, SIZE_CONSTANTS.defaultCanvasWidth, SIZE_CONSTANTS.defaultCanvasHeight)` |
| Line 304 | `1920 - 80` | `SIZE_CONSTANTS.defaultCanvasWidth - 80` |
| Line 309 | `1920 - newWidth` | `SIZE_CONSTANTS.defaultCanvasWidth - newWidth` |

#### 2. `TitleInteraction.js` — Drag Boundary Clamping Fix
**File**: `MyESModules/Interaction/TitleInteraction.js`
**Changes**: Fix X-axis clamping in `_onPointerMove` (lines 280-283)

**Current** (lines 280-283):
```javascript
const actualBoxWidth = state.titleStyle.titleBoxWidth ?? 400;
const fontSize = state.titleStyle.fontSize || 36;
newX = Math.max(0, Math.min(newX, 1920 - actualBoxWidth));
newY = Math.max(fontSize + 12, Math.min(newY, 1080 - 12));
```

**Replace with**:
```javascript
const actualBoxWidth = state.titleStyle.titleBoxWidth ?? 400;
const fontSize = state.titleStyle.fontSize || 36;
const VISIBLE_MIN = 50; // px of box that must remain visible at edges
newX = Math.max(-actualBoxWidth + VISIBLE_MIN, Math.min(newX, SIZE_CONSTANTS.defaultCanvasWidth - VISIBLE_MIN));
newY = Math.max(fontSize + 12, Math.min(newY, SIZE_CONSTANTS.defaultCanvasHeight - 12));
```

**Rationale:** The `VISIBLE_MIN` constant ensures at least 50px of the title box remains visible when dragged to any edge. This prevents the "stranded UI" scenario where a title is dragged completely off-canvas with no way to recover it. The Y-axis clamp is preserved as-is (with SIZE_CONSTANTS substitution) since it already prevents full off-canvas drift.

#### 3. `index.html` — Width Slider ARIA Attributes
**File**: `index.html`
**Changes**: Add ARIA attributes to `titleWidthSlider` (line 227)

**Current**:
```html
<input type="range" id="titleWidthSlider" v-model.number="titleStyle.titleBoxWidth" min="100" max="1920" step="1" class="fullRange" @input="onTitleWidthChange">
```

**Replace with**:
```html
<input type="range" id="titleWidthSlider" v-model.number="titleStyle.titleBoxWidth" min="100" max="1920" step="1" :aria-valuenow="(titleStyle.titleBoxWidth ? Math.round(titleStyle.titleBoxWidth) + 'px' : 'Auto')" aria-valuemin="100px" aria-valuemax="1920px" class="fullRange" @input="onTitleWidthChange">
```

**Pattern match:** Mirrors the opacity sliders at lines 193 and 203 which use `:aria-valuenow="Math.round(titleStyle.*Opacity * 100) + '%'"` — width uses pixel units instead of percentage.

#### 4. `createTitleHandlers.js` — Simplify `onTitleWidthChange`
**File**: `MyESModules/App/createTitleHandlers.js`
**Changes**: Remove `value` parameter (lines 193-201)

**Current**:
```javascript
onTitleWidthChange(value) {
    const titleManager = getTitleManager();
    if (titleManager) {
        const w = value !== undefined ? Number(value) : this.titleStyle.titleBoxWidth;
        titleManager.setWidth(w);
    }
    onRenderScheduled(this);
},
```

**Replace with**:
```javascript
onTitleWidthChange() {
    const titleManager = getTitleManager();
    if (titleManager) {
        titleManager.setWidth(this.titleStyle.titleBoxWidth);
    }
    onRenderScheduled(this);
},
```

**Rationale:** `v-model.number` on the slider is the source of truth for `this.titleStyle.titleBoxWidth`. The `value` parameter receives the event object when called from `@input`, not the slider value. The fallback to `this.titleStyle.titleBoxWidth` works but is fragile. All other handlers in this file (`onTitleFontOpacityChange`, `onTitleBgOpacityChange`, etc.) read directly from `this.titleStyle.*` — this change brings `onTitleWidthChange` into alignment.

### Behavior Scenarios

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 2.1.1 | Title is at position (960, 900) with width 400 | User drags title left to the far edge | Title stops with at least 50px of the box still visible on the left edge (titleBoxX >= -350) |
| 2.1.2 | Title is at position (960, 900) with width 400 | User drags title right to the far edge | Title stops with at least 50px of the box still visible on the right edge (titleBoxX <= 1870) |
| 2.1.3 | Title is at position (960, 900) with width 400 | User drags title up toward the top | Title stops with baseline at fontSize+12 (existing behavior preserved) |
| 2.1.4 | Title is at position (960, 900) with width 400 | User drags title down toward the bottom | Title stops with baseline at 1080-12 (existing behavior preserved) |
| 2.1.5 | Width slider is at 600px | Screen reader user focuses the width slider | Screen reader announces "600px" as the current value |
| 2.1.6 | Width slider is at default (Auto/null) | Screen reader user focuses the width slider | Screen reader announces "Auto" as the current value |

#### Component Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 2.2.1 | TitleInteraction uses `SIZE_CONSTANTS.defaultCanvasWidth` (1920) | `_hitTestTitle` is called with canvas dimensions 960x540 | Hit testing scales correctly using SIZE_CONSTANTS values |
| 2.2.2 | Title at `titleBoxX: 0`, `titleBoxWidth: 400` | User drags title 500px to the left | `titleBoxX` is clamped to `-350` (not `-400`), keeping 50px visible |
| 2.2.3 | Title at `titleBoxX: 1920`, `titleBoxWidth: 400` | User drags title 500px to the right | `titleBoxX` is clamped to `1870` (not `1920`), keeping 50px visible |
| 2.2.4 | `onTitleWidthChange` called with no arguments (from `@input` template binding) | `this.titleStyle.titleBoxWidth` is 600 | `titleManager.setWidth(600)` is called (reads from v-model source of truth) |

#### Pure Function Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 2.3.1 | `SIZE_CONSTANTS.defaultCanvasWidth` = 1920, `VISIBLE_MIN` = 50, `actualBoxWidth` = 400 | `Math.max(-400 + 50, Math.min(-500, 1920 - 50))` | Result is `-350` (clamped to VISIBLE_MIN threshold) |
| 2.3.2 | `SIZE_CONSTANTS.defaultCanvasWidth` = 1920, `VISIBLE_MIN` = 50, `actualBoxWidth` = 400 | `Math.max(-400 + 50, Math.min(2000, 1920 - 50))` | Result is `1870` (clamped to canvas - VISIBLE_MIN) |
| 2.3.3 | `SIZE_CONSTANTS.defaultCanvasWidth` = 1920, `VISIBLE_MIN` = 50, `actualBoxWidth` = 400 | `Math.max(-400 + 50, Math.min(960, 1920 - 50))` | Result is `960` (within bounds, no clamping) |

### Success Criteria:

#### Automated Verification:
- [x] `TitleInteractionTest.html` passes — all existing tests still pass with SIZE_CONSTANTS (29 tests, 0 failures)
- [x] New tests verify drag clamping respects VISIBLE_MIN = 50px on both edges (2.T.1 through 2.T.4b)
- [x] New tests verify SIZE_CONSTANTS values are used (not hardcoded literals) (2.T.5, 2.T.5b)
- [x] `TitleManagerTest.html` passes — `setWidth` called with correct value from simplified handler
- [x] `SettingsPersistenceTest.html` passes — all Phase 1 tests still pass
- [x] All existing tests continue to pass

#### Manual Verification:
- [ ] Drag title to left edge — at least 50px of box remains visible
- [ ] Drag title to right edge — at least 50px of box remains visible
- [ ] Drag title up/down — existing Y-axis behavior preserved
- [ ] Width slider: verify ARIA attributes present in DOM via browser dev tools
- [ ] Width slider: verify screen reader announces correct value
- [ ] Resize width via slider — title resizes correctly (no regression from handler simplification)
- [ ] Reset Position button still works after all changes

### Test Scenarios

#### Unit Tests — `TitleInteractionTest.html` (new section)

| # | Test | Input | Expected |
|---|------|-------|----------|
| 2.T.1 | Drag left: clamped to VISIBLE_MIN | Start at x=0, drag 500px left, boxWidth=400 | `titleBoxX` clamped to -350 (not -400) |
| 2.T.2 | Drag right: clamped to canvas - VISIBLE_MIN | Start at x=1920, drag 500px right, boxWidth=400 | `titleBoxX` clamped to 1870 (not 1920) |
| 2.T.3 | Drag within bounds: no clamping | Start at x=960, drag 100px left | `titleBoxX` = 860 (no clamping applied) |
| 2.T.4 | Resize-left drag: clamped correctly | Start resize-left from x=0, drag left | New X and width clamped so 50px remains visible |
| 2.T.5 | SIZE_CONSTANTS used in hit testing | `_hitTestTitle` called | No hardcoded 1920/1080 in hit test calculation |

#### Unit Tests — `SettingsHandlersTest.html` (new test file)

| # | Test | Input | Expected |
|---|------|-------|----------|
| 2.T.6 | `onTitleWidthChange` with no args reads from v-model | `this.titleStyle.titleBoxWidth` = 600, no args passed | `titleManager.setWidth(600)` called |
| 2.T.7 | `onTitleWidthChange` consistent with other handlers | Compare signature with `onTitleFontOpacityChange` | Both take no parameters, both read from `this.titleStyle.*` |

#### E2E Tests — Playwright (optional, low priority)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 2.T.e.1 | Width slider ARIA attributes present | Navigate to page, open title section, inspect width slider | `aria-valuenow`, `aria-valuemin`, `aria-valuemax` all present |
| 2.T.e.2 | Title drag respects boundaries | Load images, set title, drag title to far left edge | Title box does not go fully off-canvas |

### Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | 1.T.1 through 1.T.4, 1.1.1 through 1.1.4 | Settings persistence — without these, the feature is unusable |
| **P1** | 2.T.1 through 2.T.5, 2.1.1 through 2.1.4 | Drag clamping and SIZE_CONSTANTS — prevent stranded UI and maintenance risk |
| **P2** | 2.T.6 through 2.T.7, 2.T.e.1 through 2.T.e.2, 2.1.5 through 2.1.6 | ARIA and handler simplification — accessibility polish and code consistency |

## Testing Strategy

### Unit Tests:
- **SettingsPersistenceTest.html**: Add round-trip test for all 7 new title fields (1.T.1 through 1.T.4)
- **SettingsHandlersTest.html** (NEW): Test `_saveSettings` and `_applySavedSettings` with mock state for all 7 new fields, including edge cases for falsy values and backward compatibility (1.T.5 through 1.T.9)
- **TitleInteractionTest.html**: Add drag boundary clamping tests for VISIBLE_MIN (2.T.1 through 2.T.5)

### E2E Tests (Playwright):
- **home-link.spec.js**: No changes needed (existing E2E tests unaffected)
- Optional: Add ARIA attribute verification for width slider (2.T.e.1)
- Optional: Add title drag boundary verification (2.T.e.2)

### Manual Testing Steps:
1. Open CollageMaker, load images, add a title
2. Set font opacity to 50%, bg opacity to 70%, width to 600px
3. Drag title to a custom position on the canvas
4. Enable title background with a custom color
5. Change layout style (triggers save)
6. Reload the page — verify all 7 title fields are restored
7. Drag title to far left edge — verify at least 50px remains visible
8. Drag title to far right edge — verify at least 50px remains visible
9. Inspect width slider in browser dev tools — verify ARIA attributes present
10. Click Reset Position — verify title returns to centered default

## Known Behaviors

1. **`_saveSettings()` trigger**: Settings are saved when `onLayoutStyleChange()` is called (via `createCollageMethods.js`). Title-only changes without a layout change will NOT trigger a save. This is pre-existing behavior, not a regression. Users should be aware that changing layout or exporting will trigger a save.

2. **Dead code in `createSettingsHandlers.js`**: The `_applySavedSettings(state, settings)` method in this file is never called. The live restore logic is in `createCollageLifecycle.js`. This is flagged for future cleanup but not addressed in this plan.

3. **`MARGIN=40` duplication**: The literal `40` in `TitleInteraction.js` (lines 138, 211) matches `MARGIN` in `TitleRenderer.js` but is not imported. This is a separate concern from SIZE_CONSTANTS.

4. **Legacy mode**: When `titleBoxWidth`, `titleBoxX`, and `titleBoxY` are all `null`, the renderer uses legacy centered mode. Persistence correctly saves and restores `null` values to preserve this state.

5. **`titleBackgroundColor` naming**: Uses `titleBackgroundColor` key in settings payload to avoid collision with collage-level `backgroundColor`. The restore path maps `settings.titleBackgroundColor` to `state.titleStyle.backgroundColor`.

## References

- Review: `_agent_docs/reviews/2026-07-15-title-sidebar-home-review.md`
- Original plan: `_agent_docs/plans/2026-07-13-title-sidebar-home-implementation.md`
- `MyESModules/Models/SizeConstants.js` — SIZE_CONSTANTS definition
- `MyESModules/Persistence/SettingsPersistence.js` — localStorage wrapper
- `MyESModules/Rendering/TitleRenderer.js` — MARGIN=40, PADDING=12 constants
- `MyESModules/App/createCollageMethods.js` — `onTitleWidthChange` wrapper (line 251-252)
