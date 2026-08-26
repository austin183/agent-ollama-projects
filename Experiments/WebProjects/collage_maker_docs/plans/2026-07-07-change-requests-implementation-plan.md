# Change Requests Implementation Plan

**Date:** July 7, 2026
**Status:** Draft — awaiting approval

| Phase | Focus | CRs | Risk |
|-------|-------|-----|------|
| Phase 1 | Quick Wins & Critical Robustness | CR-13, CR-11, CR-10 | Low |
| Phase 2 | UI/UX Polish & Bug Fixes | CR-03, CR-09, CR-07 | Medium |
| Phase 3 | Major UX Enhancements | CR-08, CR-01, CR-04 | High |
| Phase 4 | Advanced Interactions | CR-06 | High |
| Phase 5 | Refactoring & Architecture | CR-15, CR-12, CR-14, CR-02 | Medium-High |

---

## Overview

This plan addresses 15 change requests spanning UI/UX enhancements, bug fixes, keyboard shortcut corrections, and architectural refactoring. The requests are grouped into 5 phases ordered by risk, dependency, and user value. Each phase is independently testable and delivers incremental value.

## Current State Analysis

### Architecture
- **Framework:** Vue 3 Options API, CDN-loaded, no build step
- **Layout:** Strategy pattern via `LayoutGenerator.js` with 5 layouts (Uniform, Hero, Mosaic, DiagonalSlices, Hexagonal)
- **Rendering:** Canvas 2D via `CollageAssembler.js` pipeline: clear → background → panels → hover → selection → debug → overlay → title
- **State:** 6 managers (Layout, ImageLibrary, Crop, Background, Title, Undo) with factory pattern + callbacks
- **Interaction:** 4 handler modules (Keyboard, Gesture, CropInteraction, FileDrop) with callback injection
- **App Assembly:** `createCollageMethods.js` (482 lines) composes 9 handler modules; legacy methods at lines 257-480

### Key Discoveries
- `createCollageMethods.js` contains 23 lines of legacy methods including `_scheduleRender()` (lines 278-314), `_scheduleCropPreviewRender()` (lines 349-439), and undo/redo (lines 446-479)
- `BackgroundRenderer.js` draws background images with `globalAlpha` but does not pre-fill the background color, causing white show-through at opacity <100%
- `KeyboardHandler.js` defines `meta+s` (conflicts with browser Save) and `meta+1` through `meta+5` (conflicts with Safari tab switching)
- `SaliencyAnalyzer.js` defines `INFERENCE_TIMEOUT_MS: 15000` but never enforces it — no timeout guard in `initModels()`
- `ExportManager.js` already supports JPEG and PNG via strategy pattern; only the UI selector is missing
- The right sidebar in `index.html` has 6 sections (Layout, Crop, Background, Title, Overlay, Export) but none are collapsible

## Desired End State

After all phases complete:
1. Slice angle supports -75 to 75 degrees for clockwise rotation
2. Hexagonal layout hides the gutter slider; each layout exposes only its relevant options
3. Background image opacity correctly composites over the configured solid/gradient color
4. Crop overlays match panel shapes (pentagonal, triangular, hexagonal, etc.)
5. Title is draggable, resizable, with alignment within its box and background opacity
6. Multi-touch gestures (two-finger move, pinch-to-zoom) work on mobile/tablet
7. Export format selector lets users choose JPEG or PNG; quality slider hidden for PNG
8. Right sidebar has 6 collapsible sections; Crop auto-expands on panel selection
9. Color pickers show a color swatch button instead of hex text
10. Keyboard shortcuts no longer conflict with browser/OS shortcuts
11. Saliency model loading has a 15-second timeout with proper fallback
12. `createCollageMethods.js` is split into focused modules (render, crop preview, undo)
13. `actions.js` documentation reflects current usage
14. All handler modules use consistent callback pattern (DIP compliance)
15. No hardcoded DOM IDs — all passed as factory configuration

## What We're NOT Doing

- **No framework migration**: Stay on Vue 3 Options API
- **No build step**: Continue ES modules from CDN
- **No new layout types**: Only enhance existing layouts
- **No CSS framework**: Continue with custom CSS
- **No state management library**: Continue with Vue reactivity + plain factory managers
- **CR-04 Hexagonal drag-and-drop**: Limited to swapping panel assignments between hex cells, not free-form repositioning
- **Title auto-layout**: Title positioning is manual only; no automatic title placement

---

## Phase 1: Quick Wins & Critical Robustness

### Overview

Zero-risk documentation fix, a critical robustness fix for saliency initialization, and keyboard shortcut corrections. All changes are small, well-scoped, and independently testable.

### Changes Required

#### 1. CR-13: Actions Documentation Fix
**File:** `MyESModules/State/actions.js`
**Changes:** Replace JSDoc at lines 5-9. Current comment says "WIREFUTURE: Not yet wired into any manager" — update to reflect that `CropManager.js` and `LayoutManager.js` already use these actions.

```javascript
/**
 * State actions — Pure functions for mutating state.
 * Used by CropManager, LayoutManager, and other state managers
 * to provide testable, decoupled state mutation logic.
 *
 * Future: Additional managers (ImageLibrary, etc.) should migrate
 * to use action functions for full DIP compliance.
 */
```

**Success Criteria:**
- [ ] JSDoc accurately describes current usage
- [ ] No functional code changes

#### 2. CR-11: Saliency Timeout Guard
**File:** `MyESModules/Saliency/SaliencyAnalyzer.js`
**Changes:** Add timeout enforcement in `createSaliencyAnalyzer()`:
- In `initModels()`: Start `setTimeout` for `SALIENCY_CONFIG.INFERENCE_TIMEOUT_MS` (15000ms)
- If timer fires while `state === 'loading'`: transition to `state === 'failed'`, fire `onModelsFailed` with timeout message
- Clear timeout in `MODELS_READY` and `MODELS_FAILED` message handlers
- Clear timeout in `dispose()` to prevent stale callbacks

**Success Criteria:**
- [ ] Timeout fires after 15s if models never load
- [ ] State transitions to 'failed' on timeout
- [ ] `onModelsFailed` callback fires with timeout message
- [ ] Timeout is cleared on successful load
- [ ] Timeout is cleared on `dispose()`

#### 3. CR-10: Keyboard Shortcut Conflicts
**File:** `MyESModules/Interaction/KeyboardHandler.js`
**Changes:**
- `KEYBOARD_SHORTCUTS.EXPORT`: Change from `'meta+s'` to `'meta+e'`
- `KEYBOARD_SHORTCUTS.LAYOUT_*`: Change from `'meta+[1-5]'` to `'alt+[1-5]'`

**File:** `index.html`
**Changes:** Update keyboard shortcut hints in toolbar buttons:
- Export button hint: `Cmd+S` → `Cmd+E`
- Layout shortcut hints in UI (if any)

**File:** `MyComponents/KeyboardHandlerTest.html`
**Changes:** Update all test assertions for new shortcut patterns

**File:** `test/e2e/keyboard-shortcuts.spec.js`
**Changes:** Update Playwright test keyboard inputs to match new shortcuts

**Success Criteria:**
- [ ] `meta+e` triggers export
- [ ] `alt+[1-5]` switches layouts
- [ ] `meta+s` no longer triggers export (browser Save works)
- [ ] `meta+[1-5]` no longer switches layouts (Safari tab switching works)
- [ ] All unit tests pass with new patterns
- [ ] All E2E tests pass with new shortcuts

### Phase 1 Test Plan

#### Unit Tests — KeyboardHandler

| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.1.1 | Export shortcut matches meta+e | `{ key: 'e', meta: true, shift: false, alt: false }`, pattern `'meta+e'` | `true` |
| 1.1.2 | Export shortcut does NOT match meta+s | `{ key: 's', meta: true }`, pattern `'meta+e'` | `false` |
| 1.1.3 | Layout Uniform matches alt+1 | `{ key: '1', alt: true, meta: false }`, pattern `'alt+1'` | `true` |
| 1.1.4 | Layout Uniform does NOT match meta+1 | `{ key: '1', meta: true, alt: false }`, pattern `'alt+1'` | `false` |
| 1.1.5 | Layout Hexagonal matches alt+5 | `{ key: '5', alt: true }`, pattern `'alt+5'` | `true` |
| 1.1.6 | meta+1 still works for browser (not intercepted) | `{ key: '1', meta: true }`, pattern `'alt+1'` | `false` (no match) |

#### Unit Tests — Saliency Timeout

| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.2.1 | Timeout fires after 15s | Mock worker never responds, wait 15001ms | `state === 'failed'` |
| 1.2.2 | onModelsFailed called on timeout | Same as above | Callback invoked with timeout message |
| 1.2.3 | Timeout cleared on success | Mock worker responds in 500ms | No timeout callback fires |
| 1.2.4 | Timeout cleared on dispose | Call `dispose()` while loading | No timeout callback fires |
| 1.2.5 | State is 'loading' during init | Call `initModels()` | `state === 'loading'` immediately |

#### E2E Tests — Keyboard Shortcuts

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 1.3.1 | Export via meta+e | Load app, add images, press `meta+e` | File download triggered |
| 1.3.2 | Layout switch via alt+1 | Load app, add images, press `alt+1` | Layout changes to Uniform |
| 1.3.3 | Layout switch via alt+5 | Load app, add images, press `alt+5` | Layout changes to Hexagonal |
| 1.3.4 | meta+s does NOT export | Load app, add images, press `meta+s` | No file download, no layout change |
| 1.3.5 | meta+1 does NOT switch layout | Load app, add images, press `meta+1` | Layout unchanged |

#### Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | 1.1.1, 1.1.3, 1.3.1, 1.3.2 | Core shortcut functionality |
| **P0** | 1.2.1, 1.2.2 | Saliency timeout prevents infinite loading |
| **P1** | 1.1.4, 1.1.5, 1.3.4, 1.3.5 | Conflict resolution verification |
| **P1** | 1.2.3, 1.2.4 | Timeout cleanup correctness |
| **P2** | 1.1.2, 1.1.6, 1.2.5 | Edge cases and negative tests |

#### Known Behaviors
- `meta+z` / `shift+meta+z` for undo/redo remain unchanged (no known conflicts)
- `Escape` for deselection remains unchanged
- Shortcuts are suppressed in editable elements (textarea, input[type=text], contenteditable)
- `alt` modifier is strict — `meta+alt+[1-5]` will NOT match `alt+[1-5]`

---

## Phase 2: UI/UX Polish & Bug Fixes

### Overview

Fix the background image opacity rendering bug, replace hex color text with visual color buttons, and add an export format selector. All changes are UI-focused with contained risk.

### Changes Required

#### 1. CR-03: Background Image Opacity + Background Color
**File:** `MyESModules/Rendering/BackgroundRenderer.js`
**Changes:** In the image background rendering path, before drawing the image with `globalAlpha`, pre-fill the canvas with the configured background color/gradient. Use `ctx.save()` / `ctx.restore()` to isolate the alpha state.

Rendering order should be:
1. Fill canvas with solid color or gradient (from `backgroundState.color` or `backgroundState.gradient`)
2. `ctx.save()`
3. Set `ctx.globalAlpha = backgroundState.opacity`
4. Draw background image
5. `ctx.restore()`

**File:** `MyESModules/App/createCollageMethods.js` (or `createRenderMethods.js` if Phase 5 is done first)
**Changes:** In `_buildBackgroundState()`, ensure the background color/gradient data is always included in the background state object, even when background style is 'image'.

**File:** `index.html` (optional UX improvement)
**Changes:** Consider separating Background Image into its own section independent of the Solid|Gradient|Image segmented control, per the UX design option in the spec.

**Success Criteria:**
- [ ] Background image at 50% opacity shows configured solid/gradient color behind it
- [ ] Background image at 100% opacity fully covers the background color
- [ ] Background image at 0% opacity shows only the background color
- [ ] Export output matches preview rendering
- [ ] No alpha leakage to subsequent render pipeline stages

#### 2. CR-09: Color Names → Color Button
**File:** `index.html`
**Changes:** For each color picker row (Background Solid, Gradient Color 1/2, Title Font Color, Title Background Color), replace the hex text display with a larger color swatch button. The button shows the current color as its background.

**File:** `Style.css`
**Changes:** Add styles for `.color-swatch` — a square button (e.g., 32x32px) with border, border-radius, and the selected color as background.

**Success Criteria:**
- [ ] Each color picker shows a visual color swatch instead of hex text
- [ ] Swatch updates reactively when color changes
- [ ] Swatch is large enough to tap on mobile (~32px minimum)
- [ ] Accessibility: swatch has `aria-label` with hex value

#### 3. CR-07: Export Format Selector
**File:** `index.html`
**Changes:** In the Export section, add a format selector (dropdown or segmented control) before the Export button:
```html
<div class="export-format-selector">
  <select v-model="exportFormat">
    <option value="jpeg">JPEG</option>
    <option value="png">PNG</option>
  </select>
</div>
```
- Change Export button text from "Export JPEG" to "Export" (or "Export JPEG"/"Export PNG" dynamically)
- Conditionally hide quality slider when `exportFormat === 'png'`

**File:** `MyESModules/App/createCollageData.js`
**Changes:** Add `exportFormat: 'jpeg'` to reactive state

**File:** `MyESModules/App/createExportHandlers.js`
**Changes:** In `exportCollage()`, pass `this.exportFormat` and conditional quality to `ExportManager.export()`

**Success Criteria:**
- [ ] Default format is JPEG
- [ ] Selecting PNG exports as PNG with `.png` extension
- [ ] Quality slider is hidden when PNG is selected
- [ ] Quality slider is visible when JPEG is selected
- [ ] Export button label reflects selected format

### Phase 2 Test Plan

#### Unit Tests — Background Rendering

| # | Test | Input | Expected |
|---|------|-------|----------|
| 2.1.1 | Image bg with solid color behind | `style: 'image'`, `opacity: 0.5`, `color: '#FF0000'` | Canvas has red fill behind semi-transparent image |
| 2.1.2 | Image bg with gradient behind | `style: 'image'`, `opacity: 0.3`, `gradient: [...]` | Canvas has gradient fill behind semi-transparent image |
| 2.1.3 | Image bg at 100% opacity | `style: 'image'`, `opacity: 1.0` | Image fully covers background, no color visible |
| 2.1.4 | Image bg at 0% opacity | `style: 'image'`, `opacity: 0.0` | Only background color/gradient visible, no image |
| 2.1.5 | Alpha state restored after render | Verify `ctx.globalAlpha` after render call | `globalAlpha === 1.0` (no leakage) |

#### Unit Tests — Export Manager

| # | Test | Input | Expected |
|---|------|-------|----------|
| 2.3.1 | Export as JPEG | `format: 'jpeg'`, `quality: 0.92` | Returns `'success'`, blob type `image/jpeg` |
| 2.3.2 | Export as PNG | `format: 'png'`, quality ignored | Returns `'success'`, blob type `image/png` |
| 2.3.3 | Default format is JPEG | `format` omitted | Uses `'jpeg'` as default |

#### E2E Tests — Background Opacity

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 2.4.1 | Solid bg visible behind image | Set solid red bg, add image bg at 50% opacity | Red tint visible in export |
| 2.4.2 | Gradient bg visible behind image | Set gradient bg, add image bg at 30% opacity | Gradient tint visible in export |
| 2.4.3 | No white show-through | Set blue bg, add image bg at 70% opacity | No white pixels in transparent areas of image |

#### E2E Tests — Export Format

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 2.5.1 | Export as JPEG (default) | Load app, add images, click Export | Downloads `collage.jpg` |
| 2.5.2 | Export as PNG | Select PNG, click Export | Downloads `collage.png` |
| 2.5.3 | Quality slider hidden for PNG | Select PNG | Quality slider not visible |
| 2.5.4 | Quality slider visible for JPEG | Select JPEG | Quality slider visible |

#### Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | 2.1.1, 2.1.5, 2.4.1 | Core rendering fix — alpha compositing correctness |
| **P0** | 2.3.1, 2.3.2, 2.5.1, 2.5.2 | Export format functionality |
| **P1** | 2.1.2, 2.1.3, 2.1.4, 2.4.2, 2.4.3 | Rendering edge cases |
| **P1** | 2.3.3, 2.5.3, 2.5.4 | UI behavior for format selector |
| **P2** | Color swatch visual tests | Visual polish, no functional risk |

#### Known Behaviors
- Background color/gradient rendering is handled by `BackgroundRenderer.js` which already supports solid, gradient, and image styles
- The `ctx.save()`/`ctx.restore()` pattern is already used in `PanelRenderer.js` for clip isolation
- Export uses an offscreen canvas at 1920x1080 — background rendering must work identically on offscreen canvas

---

## Phase 3: Major UX Enhancements

### Overview

The largest phase: collapsible sidebar sections, bidirectional diagonal slice angles, and crop overlay shape alignment with hexagonal layout improvements. These changes touch multiple files and require careful Canvas 2D testing.

### Changes Required

#### 1. CR-08: Collapsible Sidebar Sections
**File:** `index.html`
**Changes:** Wrap each right sidebar section (Layout, Title, Crop, Background, Overlay, Export) in a collapsible container:
```html
<div class="sidebar-section" v-for="section in sidebarSections" :key="section.id">
  <div class="sidebar-section-header" @click="toggleSection(section.id)">
    <span class="section-chevron" :class="{ expanded: expandedSections[section.id] }">▶</span>
    <span>{{ section.label }}</span>
  </div>
  <div class="sidebar-section-content" v-show="expandedSections[section.id]">
    <!-- section content -->
  </div>
</div>
```
Reorder sections: Layout → Title → Crop → Background → Overlay → Export

**File:** `MyESModules/App/createCollageData.js`
**Changes:** Add `sidebarSections` array and `expandedSections` reactive object. All sections start collapsed (`false`).

**File:** `MyESModules/App/createCollageMethods.js` (or new handler)
**Changes:** Add `toggleSection(sectionId)` method. Add watcher/computed: when `selectedPanelId` changes, auto-expand the 'crop' section.

**File:** `Style.css`
**Changes:** Add `.sidebar-section`, `.sidebar-section-header`, `.sidebar-section-content`, `.section-chevron` styles. Chevron rotates 90deg when expanded.

**Success Criteria:**
- [ ] All 6 sections are collapsible
- [ ] All sections start collapsed on page load
- [ ] Clicking header toggles section open/closed
- [ ] Chevron rotates to indicate expanded state
- [ ] Selecting a panel auto-expands the Crop section
- [ ] Deselecting a panel does NOT auto-collapse Crop (user control)
- [ ] Sections persist expanded/collapsed state via `PersistenceManager` (if feasible)

#### 2. CR-01: Diagonal Slice Angle — Negative Degrees
**File:** `index.html`
**Changes:** Update slice angle slider: `min="-75" max="75" step="1"` (currently `min="0" max="75"`)

**File:** `MyESModules/Layout/DiagonalSlicesLayout.js`
**Changes:** The layout math already supports negative angles (shear transformation). Verify that negative angles produce correct parallelogram geometry. If `Math.tan(angle * Math.PI / 180)` is used, negative angles will produce negative shear — which is the desired clockwise rotation.

**File:** `MyESModules/Layout/LayoutGenerator.js`
**Changes:** No changes needed if the generator already passes `sliceAngle` through to the layout function.

**Success Criteria:**
- [ ] Slider range is -75 to 75
- [ ] Angle 0 produces non-sheared (rectangular) panels
- [ ] Positive angles produce counter-clockwise shear
- [ ] Negative angles produce clockwise shear
- [ ] Layout regenerates correctly at all angle values
- [ ] Export renders correctly at negative angles

#### 3. CR-04a: Crop Overlay Shape Alignment
**File:** `MyESModules/App/createCollageMethods.js` (specifically `_scheduleCropPreviewRender()`, lines 349-439)
**Changes:** Currently draws a rectangular crop preview. For DiagonalSlices and Hexagonal layouts, the crop preview canvas needs to reflect the panel's actual shape.

Approach: Draw the panel's clip path on the crop preview canvas as a visual guide. The actual crop interaction (drag/resize) remains rectangular since it operates on the source image — the shaped overlay is purely visual feedback.

**File:** `MyESModules/Interaction/CropInteraction.js`
**Changes:** No changes needed — crop interaction operates on source image coordinates, not panel shape.

**Success Criteria:**
- [ ] DiagonalSlices crop preview shows parallelogram-shaped overlay
- [ ] Hexagonal crop preview shows hexagonal overlay
- [ ] Other layouts (Uniform, Hero, Mosaic) show rectangular overlay (unchanged)
- [ ] Crop drag/resize still works (operates on source image, not overlay shape)

#### 4. CR-04b: Hexagon Size Slider
**File:** `index.html`
**Changes:** Replace the "Gutter" slider (hidden for hexagonal) with a "Hexagon Size" slider. Range: minimum = default hex spacing value, maximum = 200% of default. The slider controls a size multiplier that is passed to the hexagonal layout generator.

**File:** `MyESModules/Layout/HexagonalLayout.js`
**Changes:** Accept a `hexSizeMultiplier` parameter (default 1.0). Scale hex radius by this multiplier. Allow hexagons to extend beyond canvas bounds — they will be clipped by the panel renderer.

**File:** `MyESModules/Layout/LayoutGenerator.js`
**Changes:** Pass `hexSizeMultiplier` to `generateHexagonalLayout()`

**File:** `MyESModules/App/createCollageData.js`
**Changes:** Add `hexSizeMultiplier: 1.0` to reactive state

**Success Criteria:**
- [ ] Hexagon Size slider replaces Gutter slider for hexagonal layout
- [ ] At 100%, hexagons match current default size
- [ ] At 200%, hexagons are twice the default size
- [ ] Hexagons that extend beyond canvas are clipped correctly
- [ ] Slider is hidden for non-hexagonal layouts

#### 5. CR-04c: Hexagonal Panel Drag-and-Drop
**File:** `MyESModules/Interaction/GestureHandler.js`
**Changes:** Enhance `hitTestPanel()` to support drag-and-drop reassignment for hexagonal layout. When user drags from one hex cell to another, update `panelAssignments` to swap the image assignment.

**File:** `MyESModules/App/createCropHandlers.js` or new `createHexDragHandlers.js`
**Changes:** Add drag start/end handlers for hexagonal panel reassignment. On drag end, find target hex cell and swap panel assignments.

**Success Criteria:**
- [ ] Dragging from one hex panel to another swaps their image assignments
- [ ] Dropping outside a valid hex cell reverts the drag
- [ ] Undo/redo works for hex panel swaps
- [ ] Non-hexagonal layouts are unaffected

### Phase 3 Test Plan

#### Unit Tests — Diagonal Slice Angle

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.2.1 | Angle 0 produces rect panels | `sliceAngle: 0`, 4 images | All panels are rectangular |
| 3.2.2 | Positive angle produces CCW shear | `sliceAngle: 45`, 4 images | Panels sheared counter-clockwise |
| 3.2.3 | Negative angle produces CW shear | `sliceAngle: -45`, 4 images | Panels sheared clockwise |
| 3.2.4 | Angle -75 is valid | `sliceAngle: -75`, 4 images | Layout generates without error |
| 3.2.5 | Angle 75 is valid | `sliceAngle: 75`, 4 images | Layout generates without error |

#### Unit Tests — Hexagon Size

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.4.1 | Multiplier 1.0 = default | `hexSizeMultiplier: 1.0` | Hex radius matches current default |
| 3.4.2 | Multiplier 2.0 = 2x size | `hexSizeMultiplier: 2.0` | Hex radius is 2x default |
| 3.4.3 | Off-canvas hexagons are generated | Large multiplier, many images | Panels generated even beyond canvas bounds |
| 3.4.4 | Small image count with large hex | 3 images, multiplier 2.0 | 3 hexagons generated, properly sized |

#### Unit Tests — Collapsible Sections

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.1.1 | All sections start collapsed | Initial state | `expandedSections` all `false` |
| 3.1.2 | Toggle expands section | `toggleSection('crop')` | `expandedSections.crop === true` |
| 3.1.3 | Toggle collapses section | `toggleSection('crop')` again | `expandedSections.crop === false` |
| 3.1.4 | Panel select auto-expands crop | `selectedPanelId` changes to non-null | `expandedSections.crop === true` |
| 3.1.5 | Panel deselect does not collapse crop | `selectedPanelId` changes to null, crop was manually expanded | `expandedSections.crop` unchanged |

#### E2E Tests — Collapsible Sidebar

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.6.1 | All sections collapsed on load | Navigate to app | All 6 sections collapsed |
| 3.6.2 | Toggle Layout section | Click Layout header | Layout section expands, chevron rotates |
| 3.6.3 | Toggle Layout again | Click Layout header again | Layout section collapses |
| 3.6.4 | Panel select expands Crop | Select a panel in canvas | Crop section auto-expands |
| 3.6.5 | Multiple toggles don't flap | Rapidly click section header | Section toggles correctly each time |

#### E2E Tests — Slice Angle

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.7.1 | Negative angle visible | Set angle to -30, Diagonal layout | Panels sheared clockwise |
| 3.7.2 | Export with negative angle | Set angle to -45, export | Export shows clockwise-sheared panels |
| 3.7.3 | Angle 0 is rectangular | Set angle to 0 | Panels are non-sheared rectangles |

#### E2E Tests — Hexagon Size

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.8.1 | Hexagon Size slider visible for hex | Select Hexagonal layout | Hexagon Size slider visible |
| 3.8.2 | Hexagon Size slider hidden for other | Select Uniform layout | Hexagon Size slider hidden |
| 3.8.3 | 200% hexagons render | Set slider to max | Large hexagons visible, clipped at edges |

#### Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | 3.2.1-3.2.5, 3.7.1-3.7.3 | Slice angle core functionality |
| **P0** | 3.1.1-3.1.5, 3.6.1-3.6.5 | Collapsible sidebar core functionality |
| **P0** | 3.4.1-3.4.4, 3.8.1-3.8.3 | Hexagon size core functionality |
| **P1** | 3.9 (hex DnD tests) | Hex panel reassignment |
| **P1** | Crop overlay shape visual tests | Visual feedback correctness |
| **P2** | 3.6.5 (toggle flapping) | Edge case robustness |

#### Known Behaviors
- Crop interaction (drag/resize) operates on source image coordinates — the shaped overlay is purely visual
- Hexagonal panels that extend beyond canvas bounds are clipped by the panel renderer's clip path
- Slice angle of 0 is the neutral position (no shear)
- Sidebar section state may or may not persist across sessions (depends on PersistenceManager scope)

---

## Phase 4: Advanced Interactions — Multi-Touch Gestures

### Overview

Add two-finger image movement and pinch-to-zoom for the selected panel. This is the highest-risk phase due to cross-browser touch event handling complexity.

### Changes Required

#### 1. CR-06: Multi-Touch Gestures
**File:** `MyESModules/Interaction/CropInteraction.js`
**Changes:** Extend the crop interaction module to handle multi-touch events:
- Add `touchstart` handler that detects 2-finger gestures
- Two-finger move: Calculate midpoint of two touches, apply delta to crop source rect (same as current drag behavior)
- Two-finger pinch: Calculate distance between two touches, compute scale factor, apply to crop zoom (same as current zoom behavior)
- Call `e.preventDefault()` on touch events to prevent browser default behaviors

**File:** `MyESModules/Interaction/GestureHandler.js`
**Changes:** Ensure touch events on the preview canvas are properly routed to the crop interaction module when a panel is selected.

**File:** `createCollageLifecycle.js`
**Changes:** Wire up touch event listeners alongside existing pointer event listeners.

**Success Criteria:**
- [ ] Two-finger drag moves the image within the selected panel
- [ ] Two-finger pinch zooms the image in/out within the selected panel
- [ ] Crop overlay follows gestures in real-time
- [ ] Single-finger interactions remain unchanged
- [ ] Touch events do not trigger mouse event duplicates
- [ ] Works on iOS Safari and Android Chrome

### Phase 4 Test Plan

#### E2E Tests — Multi-Touch Gestures

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 4.1.1 | Two-finger move | Select panel, two-finger drag on canvas | Image moves within panel, crop overlay updates |
| 4.1.2 | Pinch to zoom in | Select panel, pinch open gesture | Image zooms in, crop overlay updates |
| 4.1.3 | Pinch to zoom out | Select panel, pinch close gesture | Image zooms out, crop overlay updates |
| 4.1.4 | Single finger unchanged | Select panel, single-finger tap | Panel selection works as before |
| 4.1.5 | No page scroll on gesture | Two-finger drag on canvas | Page does not scroll |
| 4.1.6 | Gesture stops on lift | Lift one finger during gesture | Gesture stops, no further movement |

#### Manual Testing Steps
1. Open app on iOS Safari device
2. Add 3+ images, select a panel
3. Two-finger drag — verify image moves
4. Two-finger pinch — verify image zooms
5. Single-finger tap — verify panel selection still works
6. Repeat on Android Chrome
7. Repeat on desktop with touch screen (if available)

#### Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | 4.1.1, 4.1.2, 4.1.3 | Core gesture functionality |
| **P1** | 4.1.4, 4.1.5 | No regression in existing behavior |
| **P2** | 4.1.6 | Edge case — partial gesture |

#### Known Behaviors
- Touch events fire alongside mouse events on some browsers — `e.preventDefault()` is required
- iOS Safari may show/hide address bar during gestures, changing viewport dimensions
- Pinch-to-zoom scale factor is computed from inter-touch distance ratio
- Two-finger move uses the midpoint of both touches as the drag anchor

---

## Phase 5: Refactoring & Architecture

### Overview

Internal refactoring to improve testability, maintainability, and DIP compliance. CR-15 (hardcoded DOM IDs) is done first as it enables cleaner extraction in CR-12. CR-14 (callback pattern) and CR-02 (hex gutter OCP) follow.

### Changes Required

#### 1. CR-15: Remove Hardcoded DOM IDs
**File:** `MyESModules/App/createCollageLifecycle.js`
**Changes:** Accept `canvasIds` configuration:
```javascript
createCollageLifecycle({ base, canvasIds: { preview: 'previewCanvas', cropPreview: 'cropPreviewCanvas' } })
```
Replace `document.getElementById('previewCanvas')` with `document.getElementById(canvasIds.preview)`

**File:** `MyESModules/Interaction/FileDropHandler.js` or `createFileHandlers.js`
**Changes:** Accept `fileInputId` configuration. Replace `document.getElementById('fileInput')` with config value.

**File:** `MyESModules/App/createCollageMethods.js`
**Changes:** Accept `cropPreviewCanvasId` configuration for `_scheduleCropPreviewRender()`.

**File:** `MyESModules/App/createCollageApp.js`
**Changes:** Supply the DOM IDs when creating lifecycle, file handlers, and methods.

**Success Criteria:**
- [ ] All DOM element lookups use injected IDs
- [ ] No hardcoded `getElementById` calls in factory functions
- [ ] App functions identically with default IDs
- [ ] Unit tests can supply mock IDs

#### 2. CR-12: Extract Legacy Methods
**File:** `MyESModules/App/createCollageMethods.js`
**Changes:** Extract legacy methods into 3 new modules:

**New file:** `MyESModules/App/createRenderMethods.js`
- `_scheduleRender()` — Core render scheduler (lines 278-314)
- `_buildBackgroundState()` — Background state builder (lines 320-329)
- `_buildOverlayState()` — Overlay state builder (lines 335-341)
- `_regenerateAndRender()` — Layout + render combo (lines 265-270)

**New file:** `MyESModules/App/createCropPreviewRenderer.js`
- `_scheduleCropPreviewRender()` — Crop preview rendering (lines 349-439, ~92 lines)

**New file:** `MyESModules/App/createUndoMethods.js`
- `_updateUndoState()` — Undo state sync (lines 446-449)
- `_performUndo()` — Undo execution (lines 456-464)
- `_performRedo()` — Redo execution (lines 471-479)

**File:** `MyESModules/index.js`
**Changes:** Add barrel exports for new modules if needed

**Success Criteria:**
- [ ] `createCollageMethods.js` reduced from 482 lines to ~200 lines
- [ ] Each new module follows factory pattern
- [ ] Methods are composed via spread into main methods object
- [ ] Vue template bindings unchanged (method names preserved)
- [ ] All existing tests pass
- [ ] No rendering regressions

#### 3. CR-14: Handler Callback Pattern
**File:** `MyESModules/App/createFileHandlers.js`
**Changes:** Use the `onRegenerate` callback parameter instead of `this._regenerateAndRender()` in `handleFileInputChange`

**File:** `MyESModules/App/createLayoutHandlers.js`
**Changes:** Accept `onRenderScheduled` callback, invoke instead of `this._scheduleRender()`

**File:** `MyESModules/App/createCropHandlers.js`
**Changes:** Accept `onRenderScheduled` callback, invoke instead of `this._scheduleRender()`

**File:** `MyESModules/App/createBackgroundHandlers.js`
**Changes:** Accept `onRenderScheduled` callback, invoke instead of `this._scheduleRender()`

**File:** `MyESModules/App/createTitleHandlers.js`
**Changes:** Accept `onRenderScheduled` callback, invoke instead of `this._scheduleRender()`

**File:** `MyESModules/App/createOverlayHandlers.js`
**Changes:** Accept `onRenderScheduled` callback, invoke instead of `this._scheduleRender()`

**File:** `MyESModules/App/createCollageMethods.js`
**Changes:** Wire `onRenderScheduled: () => this._scheduleRender()` and `onRegenerate: () => this._regenerateAndRender()` to all handler factories

**Success Criteria:**
- [ ] No handler calls `this._scheduleRender()` directly
- [ ] No handler calls `this._regenerateAndRender()` directly
- [ ] All handlers receive callbacks via factory config
- [ ] App functions identically
- [ ] Handlers are testable without Vue instance

#### 4. CR-02: Hexagonal Gutter Removal + OCP
**File:** `index.html`
**Changes:** Add `v-show="layoutStyle !== 'hexagonal'"` to the Gutter slider. The Hex Spacing slider already has `v-show="layoutStyle === 'hexagonal'"`.

**File:** `MyESModules/Layout/LayoutGenerator.js` (optional OCP improvement)
**Changes:** Add a `getLayoutOptions()` method that returns which options each layout uses. This enables the UI to dynamically show/hide options based on the selected layout without hardcoded conditions.

**Success Criteria:**
- [ ] Gutter slider hidden when Hexagonal layout is selected
- [ ] Gutter slider visible for all other layouts
- [ ] Hex Spacing slider visible only for Hexagonal
- [ ] Slice Angle slider visible only for Diagonal Slices
- [ ] (Optional) Layout options are defined per-layout, not hardcoded in UI

### Phase 5 Test Plan

#### Unit Tests — DOM ID Injection

| # | Test | Input | Expected |
|---|------|-------|----------|
| 5.1.1 | Lifecycle uses injected preview ID | `canvasIds: { preview: 'testCanvas' }` | `getElementById('testCanvas')` called |
| 5.1.2 | Lifecycle uses injected crop ID | `canvasIds: { cropPreview: 'testCrop' }` | `getElementById('testCrop')` called |
| 5.1.3 | File handler uses injected input ID | `fileInputId: 'testInput'` | `getElementById('testInput')` called |

#### Unit Tests — Legacy Method Extraction

| # | Test | Input | Expected |
|---|------|-------|----------|
| 5.2.1 | Render methods module exports factory | Import `createRenderMethods` | Function returned |
| 5.2.2 | Crop preview module exports factory | Import `createCropPreviewRenderer` | Function returned |
| 5.2.3 | Undo methods module exports factory | Import `createUndoMethods` | Function returned |
| 5.2.4 | Methods composed into main object | Create app with extracted methods | All methods accessible on Vue instance |

#### Unit Tests — Callback Pattern

| # | Test | Input | Expected |
|---|------|-------|----------|
| 5.3.1 | File handler uses onRegenerate callback | Mock `onRegenerate` callback | Callback invoked on file input |
| 5.3.2 | Layout handler uses onRender callback | Mock `onRenderScheduled` callback | Callback invoked on layout change |
| 5.3.3 | Background handler uses onRender callback | Mock `onRenderScheduled` callback | Callback invoked on bg change |
| 5.3.4 | No direct this._scheduleRender in handlers | Code inspection | Zero occurrences of `this._scheduleRender` in handler modules |

#### Integration Tests — Full Pipeline

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 5.4.1 | App loads with all refactored modules | Start app, add images | App renders correctly |
| 5.4.2 | Export works after refactoring | Export collage | File downloads successfully |
| 5.4.3 | Undo/redo works after extraction | Make changes, undo, redo | State reverses and restores correctly |
| 5.4.4 | Crop preview works after extraction | Select panel, adjust crop | Preview updates correctly |
| 5.4.5 | Layout switch works after callback refactor | Switch layouts | Layout regenerates and renders |

#### Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | 5.4.1-5.4.5 | Full pipeline integration — refactoring must not break anything |
| **P0** | 5.2.1-5.2.4 | Module extraction correctness |
| **P1** | 5.1.1-5.1.3 | DOM ID injection |
| **P1** | 5.3.1-5.3.4 | Callback pattern adoption |
| **P2** | CR-02 UI tests | Gutter slider visibility |

#### Known Behaviors
- Method names must remain identical for Vue template bindings
- `_scheduleRender()` is RAF-debounced — callback pattern must preserve this
- Undo/redo uses command pattern with max 60 levels
- DOM ID injection enables future multi-instance scenarios but is not required for current single-instance app

---

## Cross-Cutting Concerns

### Performance
- Phase 3 crop overlay shapes: Canvas `clip()` paths add rendering overhead. Profile with 50+ panels to ensure acceptable frame rates.
- Phase 4 multi-touch: Touch event handlers should be passive where possible (`{ passive: false }` only where `preventDefault` is needed).

### Accessibility
- Phase 2 color swatches: Must have `aria-label` with hex value
- Phase 3 collapsible sections: Headers must be `button` elements or have `role="button"` with keyboard activation
- Phase 4 multi-touch: Touch gestures should not block keyboard/mouse alternatives

### Memory Management
- Phase 4 touch handlers: Ensure `touchstart`/`touchmove`/`touchend` listeners are removed in `dispose()`/`beforeUnmount()`
- Phase 5 refactoring: Verify no new memory leaks introduced during extraction

### Testing Infrastructure
- Existing test suite: `MyComponents/` (Mocha/Chai, browser-based) and `test/e2e/` (Playwright)
- New tests should follow existing patterns: HTML test files for unit tests, `.spec.js` for E2E
- Canvas mocking: Use proxy-based Canvas 2D context mocking for unit tests (per `references/testing.md`)

## Migration Notes

- **No data migration needed**: All changes are UI/architectural — no persistent data format changes
- **Backward compatibility**: All changes are additive or internal — no breaking changes to existing functionality
- **Rollback**: Each phase is independent and can be rolled back individually via git

## References

- Change request specs: `_agent_docs/specifications/change-requests/` (15 files)
- World review analysis: Provided by world-review subagent
- Codebase architecture: Explored via explore subagent
- Existing plans: `_agent_docs/plans/2026-07-04-architectural-refactoring-implementation.md`
- Testing patterns: `.opencode/skills/building-web-apps/references/testing.md`
- Canvas 2D patterns: `.opencode/skills/building-web-apps/references/canvas-2d.md`
- Vue Options API patterns: `.opencode/skills/building-web-apps/references/vue-options-api.md`
