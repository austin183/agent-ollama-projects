# Phase 3 Implementation Plan: Advanced Rendering, Export, and Persistence

**Date:** 2026-07-02
**Scope:** Step-by-step implementation guide for Phase 3 features: Backgrounds, Title with Per-Character Formatting, Overlay/Mask, Export, and Settings Persistence.
**Target Agent:** `build-code`
**References:** [Master Implementation Plan](./2026-06-30-collagemaker-web-port-implementation.md), [Phase 3 Test Plan](./2026-07-02-midpoint-gap-phase3-test-plan.md), [Midpoint Gap Analysis](./2026-07-02-MidpointGapAnalysis.md)

---

## 1. Overview

Phase 3 expands the CollageMaker from a basic layout tool to a full-featured creation app. The primary goals are:

1. Implement a layered rendering pipeline: **Background → Panels → Overlay → Title**
2. Add professional export capabilities at 1080p resolution
3. Build a sophisticated rich-text title system with per-character formatting
4. Persist user settings via `localStorage`

At the end of this phase, the app is feature-complete per the world-view specifications (minus ML saliency from Phase 4).

---

## 2. File Creation Order

To maintain dependency integrity, files should be implemented in the following order:

### Step 1: Models (Data Structures)
1. `MyESModules/Models/BackgroundStyle.js` — Enum for BG types.
2. `MyESModules/Models/TitleStyle.js` — Configuration for title appearance.
3. `MyESModules/Models/TitleRun.js` — Factory for formatted text segments.

### Step 2: State & Management (Logic)
4. `MyESModules/State/BackgroundManager.js` — State for BG colors, images, and gradients.
5. `MyESModules/State/TitleManager.js` — Logic for managing `TitleRun` segments and formatting.
6. `MyESModules/Persistence/SettingsPersistence.js` — localStorage wrappers.

### Step 3: Rendering (Canvas 2D)
7. `MyESModules/Rendering/BackgroundRenderer.js` — Solid/gradient/image BG rendering.
8. `MyESModules/Rendering/OverlayRenderer.js` — Blend mode and mask rendering.
9. `MyESModules/Rendering/TitleRenderer.js` — Segmented text rendering with B/I/U.

### Step 4: Export
10. `MyESModules/Export/ExportManager.js` — Offscreen canvas and blob generation.

### Step 5: System Integration (Modify Existing Files)
11. `MyESModules/Rendering/CollageAssembler.js` — **Modify**: Update `render()` to use the new rendering pipeline.
12. `MyESModules/App/createCollageServices.js` — **Modify**: Register new managers.
13. `MyESModules/App/createCollageData.js` — **Modify**: Add reactive state for new features.
14. `MyESModules/App/createCollageMethods.js` — **Modify**: Add setters and undo-wrapped methods.
15. `MyESModules/App/createCollageLifecycle.js` — **Modify**: Load settings on mount, save on changes.

### Step 6: UI Integration
16. `index.html` — **Modify**: Add Right Sidebar sections and toolbar toggles.
17. `Style.css` — **Modify**: Styles for new sidebar sections.

---

## 3. Detailed Implementation Steps

### 3.1 Background System

#### `MyESModules/Models/BackgroundStyle.js`
- Define constants: `SOLID = 'solid'`, `GRADIENT = 'gradient'`, `IMAGE = 'image'`
- Export `BACKGROUND_STYLE_OPTIONS` array
- Export `createBackgroundStyle(type, ...)` factory function

#### `MyESModules/State/BackgroundManager.js`
- State: `style`, `color1`, `color2`, `angle`, `image`, `opacity`
- Methods: `updateStyle(newStyle)`, `setColor(color)`, `setGradientColors(c1, c2)`, `setAngle(deg)`, `setImage(img)`, `setOpacity(val)`
- Callback: `onBackgroundChanged(fn)` — fires on any state change
- Default: solid black background

#### `MyESModules/Rendering/BackgroundRenderer.js`
- `render(ctx, width, height, bgState)`:
  - **Solid**: `ctx.fillStyle = bgState.color1; ctx.fillRect(0, 0, width, height);`
  - **Gradient**: Use `ctx.createLinearGradient` calculating start/end points using `Math.cos/sin` of `bgState.angle` (converted from degrees to radians). Add color stops for each color in `bgState.colors`.
  - **Image**: `ctx.globalAlpha = bgState.opacity; ctx.drawImage(bgState.image, 0, 0, width, height); ctx.globalAlpha = 1.0;`

### 3.2 Title System (Per-Character Formatting)

#### `MyESModules/Models/TitleRun.js`
- Factory: `createTitleRun(text, bold, italic, underline)` returning `{ text: string, bold: bool, italic: bool, underline: bool }`
- Clone function: `cloneTitleRun(run)`

#### `MyESModules/Models/TitleStyle.js`
- Factory: `createTitleStyle(fontFamily, fontSize, fontColor, backgroundColor, alignment, showBackground)`
- Default values: fontFamily: 'Arial', fontSize: 36, fontColor: '#FFFFFF', backgroundColor: '#000000', alignment: 'center', showBackground: false

#### `MyESModules/State/TitleManager.js`
- Maintain an array of `TitleRun` objects
- `setText(text)` — Set title text (creates single plain run)
- `insertChar(index, char, bold, italic, underline)` — Insert character at position
- `deleteChar(index)` — Delete character at position
- `toggleBold(startIndex, endIndex)` — Toggle bold on range, splits/merges runs as needed
- `toggleItalic(startIndex, endIndex)` — Same pattern
- `toggleUnderline(startIndex, endIndex)` — Same pattern
- `getRuns()` — Return current run array
- `getFullText()` — Concatenate all run text
- `getTextAt(index)` — Find which run contains the character at `index`
- **Run merging/splitting logic**: After formatting changes, merge adjacent runs with identical formatting to keep the array minimal

#### `MyESModules/Rendering/TitleRenderer.js`
- `render(ctx, width, height, titleStyle, titleRuns)`:
  1. If no runs, return early
  2. Calculate total width by iterating runs and calling `ctx.measureText` with the specific font for that run
  3. Center the total block based on `titleStyle.alignment`:
     - Left: `startX = margin`
     - Center: `startX = (width - totalWidth) / 2`
     - Right: `startX = width - margin - totalWidth`
  4. If `titleStyle.showBackground`, draw background rect: `ctx.fillStyle = titleStyle.backgroundColor; ctx.fillRect(startX - padding, y - fontSize - padding, totalWidth + padding*2, fontSize + padding*2)`
  5. For each run:
     - Set `ctx.font` (combine bold/italic modifiers + fontSize + fontFamily)
     - `ctx.fillText(run.text, cursorX, y)`
     - If `run.underline`, draw: `ctx.fillStyle = titleStyle.fontColor; ctx.fillRect(cursorX, y + 2, runWidth, 2)`
     - `cursorX += ctx.measureText(run.text).width`

### 3.3 Overlay & Masking

#### `MyESModules/Rendering/OverlayRenderer.js`
- `render(ctx, width, height, overlayState)`:
  1. If no image, return early
  2. `ctx.save()`
  3. `ctx.globalCompositeOperation = overlayState.mode` (e.g., 'multiply', 'screen', 'overlay')
  4. `ctx.globalAlpha = overlayState.opacity`
  5. `ctx.drawImage(overlayState.image, 0, 0, width, height)`
  6. `ctx.restore()` — Critical: resets globalCompositeOperation and globalAlpha

### 3.4 Export Functionality

#### `MyESModules/Export/ExportManager.js`
- `exportToJpeg(assembler, state, quality)`:
  1. Create an offscreen canvas `1920x1080` (never appended to DOM)
  2. Get 2D context from offscreen canvas
  3. Call `assembler.render(offscreenCtx, state)` — renders all layers at full resolution
  4. Call `canvas.toBlob((blob) => { ... }, 'image/jpeg', quality)`
  5. On success: create temporary `<a>` element, set `href = URL.createObjectURL(blob)`, set `download = "collage.jpg"`, call `.click()`, then cleanup
  6. Remove `<a>` element from DOM, call `URL.revokeObjectURL(url)`, remove offscreen canvas
  7. Return Promise for async handling

### 3.5 Settings Persistence

#### `MyESModules/Persistence/SettingsPersistence.js`
- Key: `collagemaker_settings`
- `save(settings)`: JSON stringify and `localStorage.setItem`
- `load()`: Parse JSON from `localStorage.getItem`, return defaults if null or invalid
- `clear()`: `localStorage.removeItem`
- Settings object shape: `{ layoutStyle, gutter, sliceAngle, hexSpacing, backgroundStyle, backgroundColor, gradientColors, gradientAngle, titleFontFamily, titleFontSize, titleFontColor, titleAlignment, exportQuality, theme }`
- Error handling: catch `QuotaExceededError`, log warning, return defaults

---

## 4. UI Integration Details

### Right Sidebar Sections (`index.html`)

Add a scrollable container in the right sidebar with the following collapsible sections:

#### 4.1 Background Section
- Segmented control: Solid / Gradient / Image
- **Solid**: `<input type="color">` for background color
- **Gradient**: Two `<input type="color">` elements + range slider for angle (0-360°)
- **Image**: `<input type="file" accept="image/*">` for background image + range slider for opacity (0-100%)

#### 4.2 Title Section
- `contenteditable` div for text entry (or custom text input with selection support)
- **Formatting Bar**: B, I, U toggle buttons (apply to selected text range)
- **Font Family select**: Curated list of web-safe fonts (Arial, Helvetica, Times New Roman, Georgia, Courier New, Verdana, Trebuchet MS, Impact, Comic Sans MS, Palatino, Lucida Console, Garamond, Bookman)
- **Font Size slider**: 12-120pt
- **Font Color picker**: `<input type="color">`
- **Background Color picker**: `<input type="color">`
- **Show Background toggle**: checkbox
- **Alignment segmented control**: Left / Center / Right

#### 4.3 Overlay Section
- `<input type="file" accept="image/*">` for mask image
- Blend Mode dropdown: All Canvas 2D `globalCompositeOperation` values
- Opacity slider: 0-100%
- Remove mask button

#### 4.4 Export Section
- Quality slider: 50-100% with percentage display
- "Export JPEG" button
- Status messages: success checkmark, error text
- Cancel button (during export)

### Sidebar Toggle
- Toggle button in toolbar to show/hide right detail panel
- CSS class toggle: `.sidebar-collapsed`

---

## 5. Technical Specifications

### Export Canvas Lifecycle
- **Preview Canvas**: Always active. Rendered on every state change via `CanvasRenderer.scheduleRender()`.
- **Export Canvas**:
  - Created inside `ExportManager.exportToJpeg`
  - Never added to the DOM
  - Destroyed immediately after the blob is generated to free memory
  - Resolution: fixed 1920x1080 (1080p)

### Rendering Pipeline Order
The `CollageAssembler.render()` method must follow this exact sequence:
1. `ctx.clearRect(0, 0, W, H)`
2. `BackgroundRenderer.render(ctx, W, H, backgroundState)`
3. `PanelRenderer.drawPanels(ctx, panels, images, crops, W, H)` — existing logic
4. `PanelRenderer.drawSelectionBorder(ctx, selectedPanelId, ...)` — existing logic
5. `OverlayRenderer.render(ctx, W, H, overlayState)`
6. `TitleRenderer.render(ctx, W, H, titleStyle, titleRuns)`

### CollageAssembler Modification
In `MyESModules/Rendering/CollageAssembler.js`, replace the inline background color fill with a call to `BackgroundRenderer.render()`. Add calls to `OverlayRenderer.render()` and `TitleRenderer.render()` after the panel rendering step.

---

## 6. Integration with Existing Systems

### UndoManager Integration
Every setter in `createCollageMethods.js` must use the `UndoManager` with non-mutating push pattern:

```javascript
// Example: Background color change
setBackgroundColor(color) {
    const oldColor = this.backgroundColor;
    this.backgroundColor = color;
    this.canvasRenderer.scheduleRender();
    this.undoManager.push({
        label: 'Change Background',
        undo: () => this.setBackgroundColorSilent(oldColor),
        redo: () => this.setBackgroundColorSilent(color)
    });
}
setBackgroundColorSilent(color) {
    this.backgroundColor = color;
    this.canvasRenderer.scheduleRender();
}
```

Same pattern for: title text changes, title formatting changes, overlay changes, export quality changes.

### Vue Data (`createCollageData.js`)
Add the following reactive properties:
```javascript
// Background
backgroundStyle: 'solid',
backgroundColor: '#000000',
gradientColors: ['#000000', '#333333'],
gradientAngle: 90,
backgroundImage: null,
backgroundOpacity: 1.0,

// Title
titleText: '',
titleRuns: [],
titleStyle: { fontFamily: 'Arial', fontSize: 36, fontColor: '#FFFFFF', backgroundColor: '#000000', alignment: 'center', showBackground: false },
titleSelectionStart: 0,
titleSelectionEnd: 0,

// Overlay
overlayImage: null,
overlayMode: 'multiply',
overlayOpacity: 0.5,

// Export
exportQuality: 0.92,
isExporting: false,
exportStatus: ''
```

### Vue Methods (`createCollageMethods.js`)
- All background setters (style, color, gradient, image, opacity)
- All title setters (text, formatting toggles, style properties)
- Overlay setters (image, mode, opacity, remove)
- Export trigger method
- Settings save/load methods

### Vue Services (`createCollageServices.js`)
Register: `BackgroundManager`, `TitleManager`, `ExportManager`, `SettingsPersistence`

### Vue Lifecycle (`createCollageLifecycle.js`)
- `mounted()`: Load settings from `SettingsPersistence`, apply to state, initialize new managers
- `beforeUnmount()`: Dispose of overlay image, background image references

---

## 7. Success Criteria

- [ ] Backgrounds (Solid, Gradient, Image) render correctly and are undoable
- [ ] Title supports multiple formats (e.g., "Hello **World**") in a single line
- [ ] Title alignment and font styles update in real-time
- [ ] Overlay blend modes correctly affect only the image below them
- [ ] Export produces a high-resolution (1920x1080) JPEG that matches the preview layout
- [ ] Page refresh restores previously saved layout and style settings
- [ ] Right sidebar can be collapsed without breaking the layout
- [ ] All Phase 3 undo/redo operations work correctly
- [ ] No console errors during normal usage

---

## 8. Implementation Order for `build-code` Agent

Execute in this order to minimize integration friction:

1. **Models first** (BackgroundStyle, TitleStyle, TitleRun) — no dependencies
2. **State managers** (BackgroundManager, TitleManager) — depend on models
3. **Persistence** (SettingsPersistence) — standalone
4. **Renderers** (BackgroundRenderer, OverlayRenderer, TitleRenderer) — depend on state managers
5. **Export** (ExportManager) — depends on assembler
6. **Assembler integration** — wire new renderers into existing pipeline
7. **Vue integration** — data, methods, services, lifecycle
8. **UI integration** — HTML template sections, CSS styling
9. **Undo integration** — wrap all setters with undo commands
10. **Settings persistence** — wire save/load into lifecycle hooks

**Implementation Note**: After completing Phase 3 and all verification passes, pause for manual confirmation before proceeding to Phase 4.
