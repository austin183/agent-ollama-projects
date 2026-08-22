# CollageMaker Web Port — Phase 3 Test Plan

**Date:** 2026-07-02
**Scope:** Tests for all Phase 3 features: Background Rendering, Title Rendering/Management, Overlay Compositing, Export Functionality, and Settings Persistence.
**Prerequisite:** Phase 1-2 tests must be passing and the core rendering pipeline must be stable.
**References:** [Phase 1-2 Test Plan](./2026-07-01-collagemaker-test-plan.md), [Phase 3 Implementation Plan](./2026-07-02-midpoint-gap-phase3-implementation-plan.md), [Master Implementation Plan](./2026-06-30-collagemaker-web-port-implementation.md)

---

## Test Infrastructure

### Unit Tests
- **Framework:** Mocha + Chai loaded via CDN
- **Execution:** In-browser via `CollageMaker/test/unit-tests.html`
- **Pattern:** Pure function validation and state mutation testing

### E2E / UI Tests
- **Framework:** Playwright
- **Execution:** `CollageMaker/test/e2e/` directory, against `http://localhost:8000`
- **Prerequisite:** Dev server running via `start-server.sh`

---

## Section 1: BackgroundRenderer Unit Tests

`MyESModules/Rendering/BackgroundRenderer.js` — Responsible for filling the base canvas layer.

### 1.1 Solid Backgrounds
| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.1.1 | Solid Hex Color | color: '#FF0000' | `ctx.fillStyle` = '#FF0000', `fillRect` called for full canvas |
| 1.1.2 | Solid RGB Object | color: {r: 0, g: 255, b: 0} | `ctx.fillStyle` = 'rgb(0, 255, 0)', `fillRect` called |
| 1.1.3 | Solid RGBA Object | color: {r: 0, g: 0, b: 255, a: 0.5} | `ctx.fillStyle` = 'rgba(0, 0, 255, 0.5)', `fillRect` called |
| 1.1.4 | Default Color | color: null / undefined | Falls back to white ('#FFFFFF') |
| 1.1.5 | Invalid Color String | color: 'not-a-color' | Gracefully falls back to default white |
| 1.1.6 | Empty Color String | color: '' | Gracefully falls back to default white |

### 1.2 Gradient Backgrounds
| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.2.1 | Linear Gradient 0° (Right) | angle: 0, colors: ['#000', '#FFF'] | `createLinearGradient` called with start(0,0) end(W,0) |
| 1.2.2 | Linear Gradient 90° (Down) | angle: 90, colors: ['#000', '#FFF'] | `createLinearGradient` called with start(0,0) end(0,H) |
| 1.2.3 | Linear Gradient 180° (Left) | angle: 180, colors: ['#000', '#FFF'] | `createLinearGradient` called with start(W,0) end(0,0) |
| 1.2.4 | Linear Gradient 270° (Up) | angle: 270, colors: ['#000', '#FFF'] | `createLinearGradient` called with start(0,H) end(0,0) |
| 1.2.5 | Linear Gradient 45° (Diagonal) | angle: 45, colors: ['#000', '#FFF'] | Correct trig used for start/end points |
| 1.2.6 | Gradient — Single Color | angle: 90, colors: ['#FF0000'] | Falls back to solid color render |
| 1.2.7 | Gradient — Three Colors | angle: 90, colors: ['#F00', '#0F0', '#00F'] | `addColorStop` called 3 times with correct ratios |
| 1.2.8 | Gradient — Invalid Angle | angle: NaN | Defaults to 90° |
| 1.2.9 | Gradient — Null Colors | colors: null | Falls back to default white |

### 1.3 Image Backgrounds
| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.3.1 | Opaque Image | image: img, opacity: 1.0 | `globalAlpha` = 1.0, `drawImage` covers full canvas |
| 1.3.2 | Semi-transparent Image | image: img, opacity: 0.5 | `globalAlpha` = 0.5, `drawImage` covers full canvas |
| 1.3.3 | Transparent Image | image: img, opacity: 0.0 | `globalAlpha` = 0.0, `drawImage` called (or early return) |
| 1.3.4 | Image Not Yet Loaded | image: unloadedImg | No draw call, no crash |
| 1.3.5 | Image Null | image: null | Early return, no draw |
| 1.3.6 | Image Aspect Ratio Mismatch | image: 1:1, canvas: 16:9 | Image stretched/fitted to cover full canvas |

---

## Section 2: TitleRenderer Unit Tests

`MyESModules/Rendering/TitleRenderer.js` — Renders the text overlay with per-character formatting.

### 2.1 Basic Rendering & Formatting
| # | Test | Input | Expected |
|---|------|-------|----------|
| 2.1.1 | Single Run (Plain) | runs: [{text: 'Hello', bold: false, italic: false, underline: false}] | `fillText` called once for 'Hello' |
| 2.1.2 | Single Run (Bold) | runs: [{text: 'Hello', bold: true, ...}] | `ctx.font` includes 'bold' |
| 2.1.3 | Single Run (Italic) | runs: [{text: 'Hello', italic: true, ...}] | `ctx.font` includes 'italic' |
| 2.1.4 | Mixed Runs (Bold + Plain) | runs: [{t: 'Hi', b: true}, {t: ' there', b: false}] | Two `fillText` calls, font changes between them |
| 2.1.5 | Mixed Runs (Bold + Italic) | runs: [{t: 'Hi', b: true}, {t: ' there', i: true}] | Two `fillText` calls, font changes |
| 2.1.6 | Underline Rendering | runs: [{text: 'Hi', underline: true}] | `fillRect` called at baselineY + 2 for run width |
| 2.1.7 | Multiple Underlines | Mixed runs with some underline: true | Multiple `fillRect` calls for specific run segments |
| 2.1.8 | Empty Title | runs: [] | No `fillText` calls, no crash |
| 2.1.9 | Title With Spaces Only | runs: [{text: '   '}] | `measureText` called, `fillText` called, bounds updated |

### 2.2 Alignment & Positioning
| # | Test | Input | Expected |
|---|------|-------|----------|
| 2.2.1 | Left Alignment | align: 'left' | StartX = margin |
| 2.2.2 | Center Alignment | align: 'center' | StartX = (W - totalWidth) / 2 |
| 2.2.3 | Right Alignment | align: 'right' | StartX = W - margin - totalWidth |
| 2.2.4 | Alignment With Empty Title | align: 'center', runs: [] | No render, bounds zero |
| 2.2.5 | Alignment With Long Title | align: 'center', text > canvasWidth | Text centered, potentially overflows edges |

### 2.3 Background Rect
| # | Test | Input | Expected |
|---|------|-------|----------|
| 2.3.1 | Background Enabled | bgColor: '#000', runs: [...] | `fillRect` called for bounds of all runs |
| 2.3.2 | Background Disabled | bgColor: null | No `fillRect` for title background |
| 2.3.3 | Background Padding | padding: 10 | `fillRect` expanded by 10px around text bounds |
| 2.3.4 | Background With Single Char | runs: [{t: 'A'}] | `fillRect` matches single character bounds + padding |

---

## Section 3: TitleManager Unit Tests

`MyESModules/State/TitleManager.js` — Logic for manipulating the `TitleRun` array.

### 3.1 Character Mutations
| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.1.1 | insertChar — Start | 'Hello', char: '!', index: 0 | runs: [{text: '!', ...}, {text: 'Hello', ...}] |
| 3.1.2 | insertChar — End | 'Hello', char: '!', index: 5 | runs: [{text: 'Hello', ...}, {text: '!', ...}] |
| 3.1.3 | insertChar — Middle | 'Hello', char: '!', index: 2 | 'He' and 'llo' split into different runs if formatting differs |
| 3.1.4 | deleteChar — Start | 'Hello', index: 0 | 'ello' remains |
| 3.1.5 | deleteChar — End | 'Hello', index: 4 | 'Hell' remains |
| 3.1.6 | deleteChar — Middle | 'Hello', index: 2 | 'Helo' remains |
| 3.1.7 | deleteChar — Only Char | 'A', index: 0 | runs: [] |
| 3.1.8 | deleteChar — Out of Bounds | 'Hello', index: 10 | No-op, no crash |

### 3.2 Formatting Toggles (Ranges)
| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.2.1 | toggleBold — Entire String | 'Hello', range: [0, 5] | All chars bold |
| 3.2.2 | toggleBold — Middle | 'Hello', range: [1, 3] | 'H' (plain), 'el' (bold), 'lo' (plain) |
| 3.2.3 | toggleBold — Start | 'Hello', range: [0, 2] | 'He' (bold), 'llo' (plain) |
| 3.2.4 | toggleBold — End | 'Hello', range: [3, 5] | 'Hel' (plain), 'lo' (bold) |
| 3.2.5 | toggleItalic — Overlapping | Bold 'el', then Italic 'el' | 'el' becomes both Bold and Italic |
| 3.2.6 | toggleUnderline — Single Char | 'Hello', range: [0, 1] | 'H' underlined, rest plain |
| 3.2.7 | toggle — Inverse | Bold 'el', then toggleBold 'el' | 'el' returns to plain |

### 3.3 Run Merging & Splitting
| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.3.1 | Split single run | Run 'Hello' (Plain), Bold [1, 3] | 3 runs: 'H' (P), 'el' (B), 'lo' (P) |
| 3.3.2 | Merge adjacent same-style | Run 'A' (B), Run 'B' (B) | Merge into single run 'AB' (B) |
| 3.3.3 | Merge via range bold | Run 'A' (B), Run 'B' (P), Run 'C' (B), Bold [0, 3] | Merge into single run 'ABC' (B) |
| 3.3.4 | Split via range plain | Run 'ABC' (B), Plain [1, 2] | 3 runs: 'A' (B), 'B' (P), 'C' (B) |
| 3.3.5 | Formatting empty string | '', toggleBold [0, 0] | No runs created, or empty run handled |

---

## Section 4: OverlayRenderer Unit Tests

`MyESModules/Rendering/OverlayRenderer.js` — Handles the final composite layer.

### 4.1 Blend Modes
| # | Test | Input | Expected |
|---|------|-------|----------|
| 4.1.1 | source-over (Default) | mode: 'source-over' | `globalCompositeOperation` = 'source-over' |
| 4.1.2 | multiply | mode: 'multiply' | `globalCompositeOperation` = 'multiply' |
| 4.1.3 | screen | mode: 'screen' | `globalCompositeOperation` = 'screen' |
| 4.1.4 | overlay | mode: 'overlay' | `globalCompositeOperation` = 'overlay' |
| 4.1.5 | darken | mode: 'darken' | `globalCompositeOperation` = 'darken' |
| 4.1.6 | lighten | mode: 'lighten' | `globalCompositeOperation` = 'lighten' |
| 4.1.7 | color-dodge | mode: 'color-dodge' | `globalCompositeOperation` = 'color-dodge' |
| 4.1.8 | color-burn | mode: 'color-burn' | `globalCompositeOperation` = 'color-burn' |
| 4.1.9 | hard-light | mode: 'hard-light' | `globalCompositeOperation` = 'hard-light' |
| 4.1.10 | soft-light | mode: 'soft-light' | `globalCompositeOperation` = 'soft-light' |
| 4.1.11 | difference | mode: 'difference' | `globalCompositeOperation` = 'difference' |
| 4.1.12 | exclusion | mode: 'exclusion' | `globalCompositeOperation` = 'exclusion' |
| 4.1.13 | hue | mode: 'hue' | `globalCompositeOperation` = 'hue' |
| 4.1.14 | saturation | mode: 'saturation' | `globalCompositeOperation` = 'saturation' |
| 4.1.15 | color | mode: 'color' | `globalCompositeOperation` = 'color' |
| 4.1.16 | luminosity | mode: 'luminosity' | `globalCompositeOperation` = 'luminosity' |

### 4.2 Opacity & State
| # | Test | Input | Expected |
|---|------|-------|----------|
| 4.2.1 | Full Opacity | opacity: 1.0 | `globalAlpha` = 1.0 |
| 4.2.2 | Half Opacity | opacity: 0.5 | `globalAlpha` = 0.5 |
| 4.2.3 | Zero Opacity | opacity: 0.0 | `globalAlpha` = 0.0 |
| 4.2.4 | No Overlay Image | image: null | Early return, no `drawImage` |
| 4.2.5 | Image Not Loaded | image: unloadedImg | No `drawImage` call |
| 4.2.6 | Reset State | render() | `globalAlpha` and `globalCompositeOperation` reset to defaults after draw |

---

## Section 5: ExportManager Unit Tests

`MyESModules/Export/ExportManager.js` — High-resolution canvas generation and file download.

### 5.1 Canvas Generation
| # | Test | Expected |
|---|------|----------|
| 5.1.1 | Offscreen Canvas Size | Created canvas is exactly 1920x1080 |
| 5.1.2 | No DOM Leak | Offscreen canvas not appended to `document.body` |
| 5.1.3 | Full Render Pipeline | `assembler.render` called with offscreen context |
| 5.1.4 | DPR Independence | Export resolution is 1920x1080 regardless of screen DPR |

### 5.2 Blob & Download
| # | Test | Input | Expected |
|---|------|-------|----------|
| 5.2.1 | toBlob JPEG | format: 'image/jpeg' | `canvas.toBlob` called with 'image/jpeg' |
| 5.2.2 | Quality 100% | quality: 1.0 | `canvas.toBlob` called with 1.0 |
| 5.2.3 | Quality 50% | quality: 0.5 | `canvas.toBlob` called with 0.5 |
| 5.2.4 | Download Trigger | valid Blob | `<a>` element created with `download` attribute and `url` |
| 5.2.5 | Cleanup | After download | `<a>` element removed from DOM, `URL.revokeObjectURL` called |

### 5.3 Error Handling
| # | Test | Expected |
|---|------|----------|
| 5.3.1 | toBlob Failure | Callback called with error, console.error logged |
| 5.3.2 | Zero-size Canvas | No crash, handled gracefully |

---

## Section 6: SettingsPersistence Unit Tests

`MyESModules/Persistence/SettingsPersistence.js` — `localStorage` wrapper.

### 6.1 Save/Load Cycle
| # | Test | Input | Expected |
|---|------|-------|----------|
| 6.1.1 | Save Layout Style | {style: 'mosaic'} | `localStorage.setItem` called with key 'collagemaker_settings' |
| 6.1.2 | Save Gutter | {gutter: 10} | `localStorage.setItem` called |
| 6.1.3 | Load Valid Settings | stored: '{"style":"mosaic"}' | Returns object `{style: 'mosaic'}` |
| 6.1.4 | Load Partial Settings | stored: '{"gutter":10}' | Returns object with gutter=10, others default |
| 6.1.5 | Load Corrupted JSON | stored: 'invalid-json' | Returns default settings, console.warn logged |

### 6.2 Edge Cases
| # | Test | Expected |
|---|------|----------|
| 6.2.1 | First Run (Empty LS) | `localStorage.getItem` = null -> Returns default settings |
| 6.2.2 | LS Quota Exceeded | `setItem` throws QuotaExceededError -> Caught, console.error logged |
| 6.2.3 | Load Invalid Values | stored: '{"gutter": "not-a-number"}' | Sanitize values (fallback to default) |
| 6.2.4 | Clear Settings | `clearSettings()` -> `localStorage.removeItem` called |

---

## Section 7: Integration Tests

### 7.1 Feature Pipeline
| # | Test | Expected |
|---|------|----------|
| 7.1.1 | Background -> Title -> Overlay | Layers rendered in correct Z-order (Background, Panels, Overlay, Title) |
| 7.1.2 | Settings -> App Init | Settings loaded from LS and applied to `LayoutManager` and `Assembler` |
| 7.1.3 | TitleManager -> TitleRenderer | `TitleManager` mutation triggers `Assembler.scheduleRender`, result visible |
| 7.1.4 | Export -> Settings | Export quality setting used in `ExportManager.toBlob` |

### 7.2 Undo Integration
| # | Test | Expected |
|---|------|----------|
| 7.2.1 | Background change + undo | Set background, undo() | Background restored to previous state |
| 7.2.2 | Title change + undo | Format title text, undo() | Title runs restored to previous state |
| 7.2.3 | Overlay change + undo | Set overlay image/mode, undo() | Overlay state restored |

---

## Section 8: E2E Workflow Tests (Playwright)

### 8.1 Background & Title Workflow
| # | Test | Steps | Expected |
|---|------|-------|----------|
| 8.1.1 | Background Switch | Change solid -> gradient -> image | Canvas updates instantly with correct style |
| 8.1.2 | Title Formatting | Type "Hello" -> Select "ell" -> Bold | "ell" rendered bold on canvas |
| 8.1.3 | Title Alignment | Switch Left -> Center -> Right | Title moves across canvas |
| 8.1.4 | Overlay Mode | Switch mode to 'Multiply' | Overlay image blends with content below |

### 8.2 Export & Persistence Workflow
| # | Test | Steps | Expected |
|---|------|-------|----------|
| 8.2.1 | Export Download | Set BG Red -> Export | JPEG file downloaded, content is red |
| 8.2.2 | Settings Persistence | Change Layout to Mosaic -> Refresh Page | Page loads with Mosaic layout already active |
| 8.2.3 | Full Session | Load images -> Set BG -> Format Title -> Export -> Refresh | All settings preserved, export successful |

---

## Section 9: Edge Cases & Error Handling

| # | Test | Input | Expected |
|---|------|-------|----------|
| 9.1.1 | Very Long Title | text > 100 chars | Title renders, bounds calculated, no crash |
| 9.1.2 | Rapid Formatting | Toggle bold 10x/sec | No state corruption, final state correct |
| 9.1.3 | Background Image Fail | Invalid image URL | Background remains default color, no crash |
| 9.1.4 | Export During Load | Trigger export while images loading | Exported image contains whatever was loaded so far |

---

## Section 10: Performance & Memory

| # | Test | Method | Threshold |
|---|------|--------|-----------|
| 10.1.1 | Title Render Speed | Measure `render()` with 10 runs | < 2ms |
| 10.1.2 | Overlay Blend Speed | Measure `render()` with 100% opacity | < 16ms (60fps) |
| 10.1.3 | Export Memory | Measure heap before/after export | No significant leak (offscreen canvas disposed) |
| 10.1.4 | Settings Save | Measure `localStorage` write | < 5ms |

---

## Priority Ordering

### P0 — Critical
- All **Section 3 (TitleManager)** tests — Formatting logic is the core of the title system.
- All **Section 5 (ExportManager)** tests — Primary output of the app.
- All **Section 6 (SettingsPersistence)** tests — User experience depends on saved state.
- **8.2.3 (Full Session)** E2E test.

### P1 — High
- All **Section 1 (BackgroundRenderer)** tests.
- All **Section 2 (TitleRenderer)** tests.
- All **Section 4 (OverlayRenderer)** tests.
- All **Section 8 (E2E Workflow)** tests.

### P2 — Normal
- Section 7 (Integration) tests.
- Section 9 (Edge Cases).
- Section 10 (Performance).

---

## Known Behaviors to Document

1. **Export Resolution Fixed**: The export resolution is locked at 1920x1080 regardless of the current window size or preview scale. This ensures high-quality output.

2. **Title Overflow**: Very long titles that exceed the canvas width are currently not wrapped; they will overflow the canvas edges.

3. **Local Storage Limits**: If `localStorage` is full, settings will not be saved, and the app will log a warning to the console.

4. **Title Formatting on Layout Change**: Formatting in the `TitleManager` is independent of layout. Changing the layout style does NOT reset title text or formatting.
