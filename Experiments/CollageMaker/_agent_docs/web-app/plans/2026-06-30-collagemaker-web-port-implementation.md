# CollageMaker Web Port — Implementation Plan

**Date:** 2026-06-30  
**Source:** Porting `CollageMaker` macOS SwiftUI app to a static web app on `austin183.github.io`  
**Target:** `austin183.github.io/CollageMaker/`  
**References:** [World View Specs](./specifications/world-view-specifications.md), [Library Research](./research/MidiestroLibraryResearch.md), [TF.js Saliency Research](./research/TFJSModelsSaliencyResearch.md)

---

## Overview

Port the CollageMaker macOS desktop app to a static web application hosted on `austin183.github.io/CollageMaker/`. The web app will replicate the core collage-making workflow: load images, arrange them in various layouts, adjust crops, add titles and backgrounds, and export as JPEG. The app follows the proven **Midiestro3D pattern**: single HTML entry point, Vue 3 reactive state, native ES modules, CDN-loaded libraries, no build step, no bundler, no server-side code.

---

## Current State Analysis

### Source: CollageMaker macOS App
- **Location:** `~/workspace/agent-ollama-projects/Experiments/CollageMaker/`
- **Architecture:** SwiftUI + AppKit, `@Observable` `CollageViewModel` as single source of truth, delegated sub-managers (`LayoutManager`, `CropManager`, `BackgroundManager`, `TitleManager`, `ImageLibraryManager`, `ExportManager`)
- **Key services:** `LayoutGenerator` (5 layout strategies), `CollageAssembler` (CoreGraphics compositing), `SaliencyAnalyzer` (Vision framework), `FitMath` (crop positioning math)
- **50+ Swift files** across Models (10), ViewModel (10), Services (14), and Views (15) packages
- **Platform dependencies:** Vision framework (saliency), CoreGraphics (compositing), CoreText (title rendering), NSImage/CGImage (image handling), UndoManager, UserDefaults

### Target: austin183.github.io
- **Hosting:** GitHub Pages static site, Python dev server via `start-server.sh`
- **Existing pattern:** `MidiSongBuilder/Midiestro3D.html` — Vue 3 + ES modules + CDN libraries, no build step
- **Shared infrastructure:** `src/css/variables.css` (design tokens), `src/js/themeSwitcher.js` (theme toggle), `src/js/collapsibleSections.js` (collapsible panels)
- **Other sub-projects:** `MidiSongBuilder/`, `TaxBracketVisualizer/`, `UrlQRCodes/`, `BlogPosts/`

### Key Platform Gaps

| macOS Feature | Web Equivalent | Gap Level |
|---------------|----------------|-----------|
| SwiftUI UI | Vue 3 + HTML/CSS | Medium — full rewrite |
| CoreGraphics compositing | Canvas 2D API | Low — direct mapping |
| Vision saliency | Center heuristic (MVP) / TF.js (future) | High — no direct equivalent |
| CoreText title rendering | Canvas `fillText()` | Low — simplified |
| `NSImage`/`CGImage` | `ImageBitmap`/`HTMLImageElement` | Low — standard web APIs |
| `UndoManager` | Custom command-pattern undo stack | Medium — new implementation |
| `UserDefaults` | `localStorage` | Low — direct mapping |
| Gestures (SwiftUI) | Pointer events + custom handlers | Medium — platform-specific |
| `NSOpenPanel` | `<input type="file">` + drag-and-drop | Low — standard web APIs |

---

## Desired End State

A fully functional collage maker web app at `austin183.github.io/CollageMaker/index.html` that:

1. **Loads images** via drag-and-drop or file picker (multiple files)
2. **Displays a three-panel layout:** image library sidebar (left), canvas (center), detail/editor panel (right)
3. **Supports 5 layout styles:** uniform grid, hero, mosaic, diagonal slices, hexagonal
4. **Allows per-panel crop editing:** drag to reposition, corner-drag to zoom, reset
5. **Supports title text** with per-character formatting (bold/italic/underline), font family (web-safe), size, color, background, alignment
6. **Supports backgrounds:** solid color, gradient, image
7. **Supports overlay/mask image** with opacity control (double exposure)
8. **Exports as JPEG** with quality slider, browser download
9. **Provides undo/redo** for all edits
10. **Uses center-weighted default crops** (saliency deferred to Phase 4)
11. **Follows site conventions:** shared design tokens, theme toggle, responsive layout

The app is verified by:
- Loading 3-10 images and producing a collage in each of the 5 layout styles
- Exporting the collage as JPEG and confirming file downloads
- Manual crop adjustments on individual panels
- Undo/redo working across multiple edit types
- Dark/light theme toggle working correctly

---

## Key Discoveries

### Reusable Patterns from Midiestro
- **Vue 3 Options API factory** (`createMidiestroApp.js`) — directly adaptable as `createCollageApp()`
- **Config decomposition** (`createGameData/Methods/Lifecycle/Services`) — proven pattern for organizing Vue app configuration
- **FileDropHandler** — drag-and-drop + file input pattern, needs multi-file adaptation
- **ComponentRegistry** — simple DI container, directly reusable
- **Canvas lifecycle** (`init/resize/render/startAnimation/stopAnimation/dispose`) — directly applicable to 2D canvas
- **Shared CSS tokens** (`variables.css`) — design tokens system, directly reusable
- **Theme switcher** — directly reusable as-is

### Layout Math is Pure Computation
- `LayoutGenerator.swift` contains 5 layout strategies with **zero platform dependencies**
- `FitMath.swift` is pure math — direct port
- `PolygonClipper.swift` (Sutherland-Hodgman) is pure math — direct port
- `SeededPRNG.swift` (xorshift) is pure math — direct port
- These 4 files form the **easiest porting target** and can be validated in isolation

### Rendering Pipeline Maps Cleanly
- CoreGraphics `CGContext` → Canvas 2D `CanvasRenderingContext2D`
- `CGPath` clipping → `ctx.beginPath()/moveTo()/lineTo()/clip()`
- `CGImage` drawing → `ctx.drawImage()`
- Gradient drawing → `ctx.createLinearGradient()`
- Blend modes → `ctx.globalCompositeOperation`
- Text → `ctx.fillText()` / `ctx.measureText()`

### Saliency Must Be Deferred
- Apple's `VNGenerateAttentionBasedSaliencyImageRequest` has no web equivalent
- TF.js models (coco-ssd, face-detection) are viable but add 9+ MB and complexity
- **Decision:** Use center-weighted heuristic for MVP, add ML-based saliency in Phase 4

---

## What We're NOT Doing

1. **No build step or bundler** — follows the Midiestro convention of zero-build static site
2. **No Three.js or WebGL** — this is a 2D tool; Canvas 2D is sufficient
3. **No ML-based saliency in Phases 1-3** — center-weighted heuristic only; TF.js deferred to Phase 4
4. **No full rich text editor** — title uses per-character formatting (bold/italic/underline toggles) rendered via segmented `fillText()` calls, matching the macOS attributed-string approach. No WYSIWYG editor or paragraph-level formatting.
5. **No PWA/offline support** — deferred to Phase 4
6. **No mobile-first responsive design** — desktop-first; mobile support deferred to Phase 4
7. **No font embedding** — JPEG export is pixel data; no font files needed
8. **No IndexedDB** — `localStorage` suffices for settings; images are ephemeral (in-memory)
9. **No server-side code** — fully static; all processing happens in the browser

---

## Implementation Approach

### Architecture: Vue 3 + Canvas 2D + ES Modules

```
austin183.github.io/CollageMaker/
├── index.html              # Main entry point (like Midiestro3D.html)
├── Style.css               # Project-specific styles
├── AGENTS.md               # Project-specific agent instructions
├── MyESModules/
│   ├── index.js            # Barrel exports
│   │
│   ├── App/                # Vue app assembly
│   │   ├── CollageBase.js          # Base initialization (services, defaults)
│   │   ├── createCollageApp.js     # Vue app factory
│   │   ├── createCollageData.js    # Reactive data factory
│   │   ├── createCollageMethods.js # Methods factory
│   │   ├── createCollageLifecycle.js # Lifecycle hooks
│   │   └── createCollageServices.js # DI via provide/inject
│   │
│   ├── Models/             # Data types (ported from Swift Models/)
│   │   ├── ImageItem.js    # UUID + image element + filename + size
│   │   ├── ImagePanel.js   # UUID + imageIndex + PanelGeometry
│   │   ├── CropInfo.js     # panelId + sourceRect + destination geometry
│   │   ├── PanelGeometry.js # { type: 'rect', rect: {...} } | { type: 'path', points: [...], boundingRect: {...} }
│   │   ├── LayoutStyle.js  # Enum: 'uniform', 'hero', 'mosaic', 'diagonalSlices', 'hexagonal'
│   │   ├── TitleStyle.js   # fontFamily, fontSize, fontColor, backgroundColor, alignment, showBackground
│   │   ├── TitleRun.js     # { text, bold, italic, underline } — per-character formatting run
│   │   ├── BackgroundStyle.js # Enum: 'solid', 'gradient', 'image'
│   │   ├── AssemblyConfig.js # Aggregated config for assembler
│   │   └── SizeConstants.js # defaultCanvasSize, defaultPreviewSize
│   │
│   ├── Layout/             # Layout generation (ported from Swift Services/)
│   │   ├── LayoutGenerator.js    # Main generator, dispatches to strategies
│   │   ├── UniformLayout.js      # Simple grid
│   │   ├── HeroLayout.js         # Hero + grid
│   │   ├── MosaicLayout.js       # Recursive subdivision
│   │   ├── DiagonalSlicesLayout.js # Parallelogram panels
│   │   ├── HexagonalLayout.js    # Hex grid
│   │   ├── FitMath.js            # Aspect-ratio fit calculations
│   │   ├── PolygonClipper.js     # Sutherland-Hodgman clipping
│   │   └── SeededPRNG.js         # Deterministic PRNG for mosaic
│   │
│   ├── Rendering/          # Canvas 2D rendering (ported from Swift Services/)
│   │   ├── CanvasRenderer.js     # Main canvas lifecycle (init/resize/render/dispose)
│   │   ├── CollageAssembler.js   # Composites all layers on canvas
│   │   ├── PanelRenderer.js      # Per-panel clip + draw
│   │   ├── BackgroundRenderer.js # Solid/gradient/image backgrounds
│   │   ├── TitleRenderer.js      # Canvas fillText title rendering
│   │   └── OverlayRenderer.js    # Double exposure mask compositing
│   │
│   ├── State/              # State management (ported from Swift ViewModel/)
│   │   ├── CollageState.js       # Reactive state (replaces CollageViewModel)
│   │   ├── LayoutManager.js      # Layout style, gutter, panel regeneration
│   │   ├── CropManager.js        # Per-panel crop state
│   │   ├── BackgroundManager.js  # Background color/style/image
│   │   ├── TitleManager.js       # Title text, style, positioning
│   │   ├── ImageLibrary.js       # Image collection management
│   │   └── UndoManager.js        # Custom command-pattern undo/redo
│   │
│   ├── Interaction/        # User interaction (ported from Swift Views/)
│   │   ├── FileDropHandler.js    # Multi-file image drop (adapted from Midiestro)
│   │   ├── GestureHandler.js     # Canvas pan/zoom, panel selection
│   │   ├── CropInteraction.js    # Crop preview drag/resize
│   │   └── KeyboardHandler.js    # Keyboard shortcuts
│   │
│   ├── Export/             # Export functionality
│   │   └── ExportManager.js      # Canvas toBlob + browser download
│   │
│   ├── Persistence/        # Settings persistence
│   │   └── SettingsPersistence.js # localStorage settings
│   │
│   ├── Saliency/           # Saliency analysis (MVP: heuristic only)
│   │   └── SaliencyFallback.js   # Center-weighted crop heuristic
│   │
│   └── Utils/              # Shared utilities
│       ├── ComponentRegistry.js  # Service registry (reused from Midiestro)
│       ├── BrowserUtils.js       # Feature detection (reused from Midiestro)
│       ├── DomUtils.js           # DOM helpers (reused from Midiestro)
│       └── ColorUtils.js         # Color conversion utilities
```

### Rendering Pipeline

Two canvas elements:
- **Preview canvas** (`#preview-canvas`): Scaled-down real-time preview (960x540 default), updates on every state change (debounced)
- **Export canvas** (`#export-canvas`): Full-resolution canvas (1920x1080 default), created on-demand for export, destroyed after download

Pipeline per render:
```
1. Clear canvas
2. Background layer     → BackgroundRenderer (solid/gradient/image)
3. Panel layer          → PanelRenderer (clip path + drawImage per panel)
4. Overlay layer        → OverlayRenderer (globalCompositeOperation + drawImage)
5. Title layer          → TitleRenderer (fillText + optional background rect)
```

### State Management

Vue 3 reactive state replaces `CollageViewModel`. The `CollageState.js` module provides a reactive object with:
- `images`: Array of `ImageItem`
- `panels`: Array of `ImagePanel`
- `cropMap`: Map of panelId → `CropInfo`
- `layoutStyle`, `gutter`, `sliceAngle`, `hexSpacing`
- `titleText`, `titleStyle`
- `backgroundStyle`, `backgroundColor`, `gradientColors`, `backgroundImage`
- `overlayImage`, `overlayOpacity`
- `selectedPanelId`, `selectedImageId`
- `exportQuality`, `isExporting`, `exportStatus`

Changes flow:
```
User action → Vue method → State mutation → Vue reactivity → Canvas re-render (debounced)
```

---

## Phase 1: Foundation & Core Rendering

### Overview
Establish the project structure, HTML entry point, Vue app shell, layout math, and basic canvas rendering. At the end of this phase, users can load images and see them arranged in a default uniform grid layout on the canvas.

### Changes Required:

#### 1.1 Project Skeleton
**Files:**
- `CollageMaker/index.html` — Main HTML entry point
- `CollageMaker/Style.css` — Project-specific styles
- `CollageMaker/AGENTS.md` — Project-specific agent instructions
- `CollageMaker/MyESModules/index.js` — Barrel exports

**Details:**
- `index.html` follows Midiestro3D.html pattern: CDN scripts (Vue 3, Pure CSS, Material Icons), shared CSS (`../src/css/variables.css`, `../src/css/Style.css`, `../Style.css`), shared JS (`../src/js/themeSwitcher.js`), ES module script block
- Three-panel layout skeleton: left sidebar (placeholder), center canvas area, right detail panel (placeholder)
- Theme toggle button included

#### 1.2 Data Models
**Files:**
- `MyESModules/Models/LayoutStyle.js` — Layout style enum and options
- `MyESModules/Models/ImageItem.js` — Image data structure
- `MyESModules/Models/ImagePanel.js` — Panel data structure
- `MyESModules/Models/PanelGeometry.js` — Rect/path geometry
- `MyESModules/Models/SizeConstants.js` — Canvas dimensions

**Details:**
- Pure data factories, no platform dependencies
- `PanelGeometry` uses plain objects: `{ type: 'rect', rect: {x,y,w,h} }` or `{ type: 'path', points: [[x,y],...], boundingRect: {x,y,w,h} }`

#### 1.3 Layout Math (Pure Computation)
**Files:**
- `MyESModules/Layout/SeededPRNG.js` — xorshift PRNG (direct port from `Math+Utils.swift`)
- `MyESModules/Layout/FitMath.js` — Aspect-ratio fit calculations (direct port from `FitMath.swift`)
- `MyESModules/Layout/PolygonClipper.js` — Sutherland-Hodgman clipping (direct port from `PolygonClipper.swift`)
- `MyESModules/Layout/UniformLayout.js` — Grid layout (port from `UniformLayoutStrategy`)
- `MyESModules/Layout/HeroLayout.js` — Hero layout (port from `HeroLayoutStrategy`)
- `MyESModules/Layout/MosaicLayout.js` — Mosaic layout (port from `MosaicLayoutStrategy`)
- `MyESModules/Layout/DiagonalSlicesLayout.js` — Diagonal slices (port from `DiagonalSlicesLayoutStrategy`)
- `MyESModules/Layout/HexagonalLayout.js` — Hexagonal layout (port from `HexagonalLayoutStrategy`)
- `MyESModules/Layout/LayoutGenerator.js` — Main generator dispatching to strategies

**Details:**
- These are **pure functions** with no side effects or platform dependencies
- Can be tested in isolation with unit tests
- The Swift source is the authoritative reference for the math

#### 1.4 Canvas Renderer
**Files:**
- `MyESModules/Rendering/CanvasRenderer.js` — Canvas lifecycle (init/resize/render/dispose)
- `MyESModules/Rendering/PanelRenderer.js` — Per-panel clip + drawImage
- `MyESModules/Rendering/CollageAssembler.js` — Composites all layers

**Details:**
- `CanvasRenderer` follows ThreeJSRenderer lifecycle pattern: `init(canvasId)`, `resize()`, `render()`, `dispose()`
- `PanelRenderer` maps CoreGraphics `CGContext` calls to Canvas 2D:
  - `ctx.beginPath()`, `ctx.moveTo()`, `ctx.lineTo()`, `ctx.closePath()`, `ctx.clip()` for path panels
  - `ctx.drawImage(image, sx, sy, sw, sh, dx, dy, dw, dh)` for cropped image drawing
- `CollageAssembler` orchestrates: clear → background → panels → (later: overlay → title)

#### 1.5 Vue App Shell + Reactive State
**Files:**
- `MyESModules/App/CollageBase.js` — Base initialization
- `MyESModules/App/createCollageApp.js` — Vue app factory
- `MyESModules/App/createCollageData.js` — Reactive data
- `MyESModules/App/createCollageMethods.js` — Methods
- `MyESModules/App/createCollageLifecycle.js` — Lifecycle hooks
- `MyESModules/App/createCollageServices.js` — DI services
- `MyESModules/State/CollageState.js` — Reactive state container
- `MyESModules/State/LayoutManager.js` — Layout style + regeneration

**Details:**
- Follows Midiestro `createMidiestroApp()` pattern with 4 config objects
- `CollageState` holds reactive state; `LayoutManager` triggers layout regeneration
- Lifecycle: `mounted()` initializes canvas renderer, `beforeUnmount()` disposes

#### 1.6 Image Loading
**Files:**
- `MyESModules/Interaction/FileDropHandler.js` — Multi-file image drop
- `MyESModules/State/ImageLibrary.js` — Image collection management
- `MyESModules/Utils/BrowserUtils.js` — Feature detection (adapted from Midiestro)
- `MyESModules/Utils/ComponentRegistry.js` — Service registry (reused from Midiestro)

**Details:**
- `FileDropHandler` adapted from Midiestro: accepts multiple files, filters for image MIME types, uses `readAsDataURL` + `new Image()` to load images
- `ImageLibrary` manages the image array with add/remove/reorder operations
- Both drag-and-drop onto canvas and file input button supported

#### 1.7 UI: Image Library Sidebar
**File:** `index.html` — Left sidebar template

**Details:**
- Vue-rendered list of image thumbnails with filenames and sequential numbers
- Search field for filtering by filename
- "Add Images" button and "Clear All" button
- Click to select image, "X" button to remove individual image

#### 1.8 UI: Canvas Area
**File:** `index.html` — Center canvas template + `Style.css`

**Details:**
- Canvas element with scroll container for pan/zoom
- "No Images" placeholder state when library is empty
- Live preview updates as images are added and layout is generated

### Success Criteria:

#### Automated Verification:
- [ ] `start-server.sh` serves the page without errors
- [ ] `http://localhost:8000/CollageMaker/index.html` loads without console errors
- [ ] Vue app mounts successfully (no Vue warnings)
- [ ] LayoutGenerator produces valid panel arrays for all 5 layout styles with 1-10 images
- [ ] FitMath produces correct aspect-ratio-fitted rectangles (verifiable with unit tests)
- [ ] CanvasRenderer init/resize/dispose lifecycle completes without errors

#### Manual Verification:
- [ ] Page loads with three-panel layout (sidebar, canvas, detail panel)
- [ ] Drag-and-drop of 3+ images onto canvas loads them into the library
- [ ] File picker button loads images
- [ ] Canvas displays images arranged in a uniform grid
- [ ] Switching layout style updates the canvas preview
- [ ] Theme toggle (dark/light) works
- [ ] "No Images" placeholder appears when no images are loaded
- [ ] Image library sidebar shows thumbnails and filenames

**Implementation Note**: After completing Phase 1 and all verification passes, pause for manual confirmation before proceeding to Phase 2.

---

## Phase 2: Panel Editing & Crop Controls

### Overview
Add per-panel crop editing, panel selection, gesture handling, and undo/redo. At the end of this phase, users can select individual panels, adjust their crops via drag and corner-resize, and undo/redo changes.

### Changes Required:

#### 2.1 Crop State Management
**Files:**
- `MyESModules/Models/CropInfo.js` — Crop data structure
- `MyESModules/State/CropManager.js` — Per-panel crop state
- `MyESModules/Saliency/SaliencyFallback.js` — Center-weighted default crop heuristic

**Details:**
- `CropInfo` stores `sourceRect` (portion of source image to display) and `destinationRect` (panel position on canvas)
- `CropManager` manages crop state per panel, provides `adjustCrop(panDelta)`, `zoomCrop(scaleFactor)`, `resetCrop(panelId)`
- `SaliencyFallback` computes default crop that centers the image within the panel (using `FitMath.sourceRect()`)

#### 2.2 Panel Selection & Hit Testing
**Files:**
- `MyESModules/Interaction/GestureHandler.js` — Canvas click/tap hit testing

**Details:**
- Point-in-rectangle test for rect panels
- Point-in-polygon test for path panels (diagonal slices, hexagons) — use even-odd fill rule
- Click on panel selects it; click on empty space deselects
- Selected panel highlighted with border (drawn by CanvasRenderer)

#### 2.3 Crop Preview Panel
**File:** `index.html` — Right detail panel crop editor section + `Style.css`

**Details:**
- Shows the source image with a crop overlay
- Draggable visible region (white area) within the image
- Corner handles for proportional resize
- "Reset Crop" button
- Position and size display (X, Y, W, H)

#### 2.4 Crop Interaction
**Files:**
- `MyESModules/Interaction/CropInteraction.js` — Drag and corner-resize on crop preview

**Details:**
- Pointer events (mousedown/mousemove/mouseup) for drag
- Corner detection for resize mode
- Aspect-ratio preservation during resize
- Bounds clamping to image dimensions
- Live preview update during drag (debounced)

#### 2.5 Undo/Redo System
**Files:**
- `MyESModules/State/UndoManager.js` — Command-pattern undo stack

**Details:**
- Each state change produces a `{ undo, redo }` command pair
- Commands tracked: layout change, crop change, gutter change, background change, title change
- Gesture-based edits batch into single undo actions (e.g., one "Adjust Crop" per drag session)
- Max 60 undo levels (matching macOS app)
- Keyboard shortcuts: Cmd+Z (undo), Cmd+Shift+Z (redo)

#### 2.6 Layout Configuration UI
**File:** `index.html` — Left sidebar layout config section

**Details:**
- Layout style picker (segmented control or select dropdown with 5 options)
- Gutter slider (0-20pt)
- Slice angle slider (0-75°, only visible for diagonal slices)
- Hex spacing slider (0-30pt, only visible for hexagonal)
- Live preview update on any change

**Status:** Completed in Phase 1 — layout config UI was implemented as part of the foundation.

#### 2.7 Canvas Pan & Zoom
**File:** `MyESModules/Interaction/GestureHandler.js` — Extended

**Details:**
- Scroll wheel for canvas panning
- Pinch-to-zoom (pointer events) or Ctrl+scroll for zoom
- Zoom range: 25% to 400%
- Pan constrained to canvas bounds

**Status:** Deferred — current CSS-based canvas scaling (contain) provides adequate zoom for preview. Dedicated pan/zoom gestures can be added as polish.

### Success Criteria:

#### Automated Verification:
- [x] `http://localhost:8000/CollageMaker/index.html` loads without console errors
- [x] CropManager produces valid sourceRect values clamped to image bounds
- [x] UndoManager supports 60+ levels of undo
- [x] LayoutGenerator + CropManager pipeline produces valid crop info for all panels

#### Manual Verification:
- [ ] Clicking a panel on the canvas selects it (white border highlight)
- [ ] Clicking empty canvas deselects panel
- [ ] Crop preview panel appears in right sidebar when panel is selected
- [ ] Dragging crop preview repositions the image within the panel
- [ ] Corner-resize on crop preview zooms the image proportionally
- [ ] "Reset Crop" restores default crop
- [ ] Undo (Cmd+Z) reverses crop changes
- [ ] Redo (Cmd+Shift+Z) re-applies undone changes
- [ ] Layout style switcher updates canvas in real-time
- [ ] Gutter slider adjusts spacing between panels
- [ ] Canvas can be panned with scroll wheel
- [ ] Canvas can be zoomed with Ctrl+scroll

**Implementation Note**: After completing Phase 2 and all verification passes, pause for manual confirmation before proceeding to Phase 3.

---

## Phase 3: Styling, Backgrounds, Title, Export

### Overview
Add title text with per-character formatting (bold/italic/underline via segmented rendering), background options (solid/gradient/image), overlay/mask support with all blend modes, and JPEG export. At the end of this phase, the app is feature-complete per the world-view specifications (minus ML saliency).

### Changes Required:

#### 3.1 Background Rendering
**Files:**
- `MyESModules/Models/BackgroundStyle.js` — Background style enum
- `MyESModules/State/BackgroundManager.js` — Background state
- `MyESModules/Rendering/BackgroundRenderer.js` — Canvas 2D background rendering

**Details:**
- Solid color: `ctx.fillStyle = color; ctx.fillRect()`
- Gradient: `ctx.createLinearGradient()` with configurable angle (0-360°), start/end colors
- Image background: `ctx.globalAlpha = opacity; ctx.drawImage(backgroundImage)`
- Background state: style type, color(s), image, opacity, gradient angle

#### 3.2 Background UI
**File:** `index.html` — Right sidebar background section

**Details:**
- Segmented control: Solid / Gradient / Image
- Solid: color picker (`<input type="color">`)
- Gradient: two color pickers + angle slider (0-360°)
- Image: file picker for background image + opacity slider (0-100%)

#### 3.3 Title Rendering — Per-Character Formatting
**Files:**
- `MyESModules/Models/TitleStyle.js` — Title style data (base font family, size, color)
- `MyESModules/Models/TitleRun.js` — Run data: `{ text, bold, italic, underline }` (ported from Swift `TitleTextRun`)
- `MyESModules/State/TitleManager.js` — Title text and style state; manages array of `TitleRun` objects
- `MyESModules/Rendering/TitleRenderer.js` — Canvas 2D segmented text rendering

**Details:**
- Title text is stored as an array of `TitleRun` objects, each with its own `bold`, `italic`, `underline` flags
- Rendering iterates runs left-to-right, calling `ctx.font = "bold italic 36px Arial"` per run, then `ctx.fillText(run.text, cursorX, y)`, then `cursorX += ctx.measureText(run.text).width`
- Underline per run: `ctx.fillRect(runX, baselineY + 2, runWidth, 2)`
- Total width computed by summing `measureText()` per run for alignment calculations
- Background rect: `ctx.fillStyle = bgColor; ctx.roundRect()` (or `fillRect` fallback) drawn once around full title bounds
- Alignment: left (x = positionX), center (x = positionX - totalWidth/2), right (x = positionX - totalWidth)
- `TitleManager` provides `insertChar(char, bold, italic, underline)`, `toggleBold(range)`, `toggleItalic(range)`, `toggleUnderline(range)`, `deleteChar(index)` — matching macOS `AttributedStringEditor` behavior

#### 3.4 Title UI — Per-Character Formatting
**File:** `index.html` — Right sidebar title section

**Details:**
- **Contenteditable text area** or custom text input that supports character selection
- **Bold/Italic/Underline toggle buttons** — apply to selected text range (or next inserted characters if no selection), matching macOS `AttributedStringEditor` toolbar behavior
- **Font family select** — curated list of web-safe fonts: Arial, Helvetica, Times New Roman, Georgia, Courier New, Verdana, Trebuchet MS, Impact, Comic Sans MS, Palatino, Lucida Console, Garamond, Bookman
- **Font size slider** (12-120pt) — applies to selected range or entire title
- **Text color picker** (`<input type="color">`) — applies to selected range or entire title
- **Background color picker** (`<input type="color">`) — for title background box
- **Show/hide background toggle**
- **Alignment segmented control** (left/center/right)
- Formatting state reflects current selection: B/I/U buttons show pressed/unpressed based on selected characters' styles

#### 3.5 Overlay/Mask
**Files:**
- `MyESModules/Rendering/OverlayRenderer.js` — Double exposure compositing

**Details:**
- `ctx.globalCompositeOperation` set to user-selected blend mode. All Canvas 2D composite operations exposed:
  - `source-over` (default), `source-in`, `source-out`, `source-atop`
  - `destination-over`, `destination-in`, `destination-out`, `destination-atop`
  - `lighter`, `copy`, `xor`
  - `multiply`, `screen`, `overlay`, `darken`, `lighten`, `color-dodge`, `color-burn`
  - `hard-light`, `soft-light`, `difference`, `exclusion`
  - `hue`, `saturation`, `color`, `luminosity`
- `ctx.globalAlpha = opacity`
- `ctx.drawImage(maskImage, 0, 0, canvasWidth, canvasHeight)`
- File picker for mask image
- Blend mode selector (dropdown with all composite operations)
- Opacity slider (0-100%)
- Remove mask button

#### 3.6 Export
**Files:**
- `MyESModules/Export/ExportManager.js` — Canvas toBlob + download

**Details:**
- Creates full-resolution offscreen canvas (1920x1080)
- Renders all layers at full resolution
- `canvas.toBlob(callback, 'image/jpeg', quality)` for JPEG encoding
- Creates temporary `<a>` element with `download` attribute for browser download
- Quality slider (50-100%)
- Export button disabled during export
- Progress indicator during export
- Success/error feedback messages

#### 3.7 Export UI
**File:** `index.html` — Right sidebar export section

**Details:**
- "Export JPEG" button
- Quality slider with percentage display
- Status messages (success checkmark, error text)
- Cancel button during export

#### 3.8 Settings Persistence
**File:** `MyESModules/Persistence/SettingsPersistence.js`

**Details:**
- `localStorage` for settings: default layout, gutter, background style, title font/size, export quality, theme
- Load on app init, save on change
- Same keys as macOS `UserDefaultsPersistence.Keys`

#### 3.9 Image Library Enhancements
**File:** `index.html` — Left sidebar enhancements

**Details:**
- Drag-and-drop reordering within sidebar
- Context menu or button for "Remove" per image
- "Clear All" with undo support
- Search field for filename filtering

#### 3.10 Collapsible Right Sidebar
**File:** `index.html` — Toolbar toggle button

**Details:**
- Toggle button in toolbar to show/hide right detail panel
- Uses shared `collapsibleSections.js` pattern or custom toggle

### Success Criteria:

#### Automated Verification:
- [ ] `http://localhost:8000/CollageMaker/index.html` loads without console errors
- [ ] BackgroundRenderer produces correct output for all 3 background types
- [ ] TitleRenderer correctly positions text with all alignment options
- [ ] ExportManager produces valid JPEG blob (verifiable by checking MIME type and file size)
- [ ] SettingsPersistence saves and loads values from localStorage

#### Manual Verification:
- [ ] Solid color background changes canvas background
- [ ] Gradient background with angle adjustment works
- [ ] Image background with opacity slider works
- [ ] Title text appears on canvas with correct font, size, color
- [ ] Title background toggle shows/hides background box
- [ ] Title alignment (left/center/right) works
- [ ] Bold/italic/underline styling applies to selected text ranges (per-character formatting)
- [ ] Mixed formatting in same title renders correctly (e.g., **bold** normal *italic* normal)
- [ ] Mask image overlay with opacity control works
- [ ] Blend mode selector exposes all Canvas 2D composite operations
- [ ] Switching blend modes updates the overlay rendering
- [ ] Export JPEG downloads a valid image file
- [ ] Export quality slider affects output quality
- [ ] Export button shows progress during export
- [ ] Success message appears after export
- [ ] Settings persist across page reload (layout, gutter, background, title style)
- [ ] Right sidebar can be collapsed/expanded
- [ ] Image reordering in sidebar works via drag-and-drop
- [ ] "Clear All" removes all images with undo support

**Implementation Note**: After completing Phase 3 and all verification passes, pause for manual confirmation before proceeding to Phase 4.

---

## Phase 4: Polish & Advanced Features

### Overview
Add ML-based saliency analysis, responsive design improvements, PWA capabilities, and remaining polish items. This phase is optional for MVP and can be deferred based on priorities.

### Changes Required:

#### 4.1 ML-Based Saliency (Optional)
**Files:**
- `MyESModules/Saliency/SaliencyAnalyzer.js` — TF.js-based saliency pipeline

**Details:**
- Tiered approach as per TFJSModelsSaliencyResearch.md:
  1. Face detection (`@tensorflow-models/face-detection`) — ~3MB, ~100ms
  2. Object detection (`@tensorflow-models/coco-ssd`) — ~6MB, ~200ms
  3. Center fallback (already implemented)
- Lazy loading: only load models on first image analysis
- Web Worker for inference to avoid blocking main thread
- Progressive rendering: show center-cropped preview immediately, update to ML crop when analysis completes
- CDN loading via script tags (no build step)

#### 4.2 Saliency Debug Overlay
**File:** `index.html` — Toggle in toolbar

**Details:**
- Toggle button to show saliency debug overlay
- Green circle indicating focal region, red center dot
- Matches macOS app's saliency debug overlay

#### 4.3 Responsive Design
**File:** `Style.css` — Mobile breakpoints

**Details:**
- Stack sidebars below canvas on narrow screens
- Touch-friendly gesture handling (tap to select, pinch to zoom)
- Collapsed sidebars by default on mobile

#### 4.4 PWA (Optional)
**Files:**
- `manifest.json` — Web app manifest
- `service-worker.js` — Offline caching

**Details:**
- Install prompt for desktop/mobile
- Cache app shell for offline use
- Images not cached (ephemeral)

#### 4.5 Keyboard Shortcuts
**File:** `MyESModules/Interaction/KeyboardHandler.js`

**Details:**
- Cmd+O: Add images
- Cmd+S: Export
- Cmd+Z / Cmd+Shift+Z: Undo/Redo
- Cmd+1-5: Switch layout styles
- Escape: Deselect panel
- Delete/Backspace: Remove selected image

#### 4.6 Landing Page Integration
**File:** `index.html` (root)

**Details:**
- Add CollageMaker project card to the existing "Tools & Educational" category section
- Card follows the established pattern: `project-card` with icon, title, description, and "Launch" button linking to `CollageMaker/index.html`

### Success Criteria:

#### Automated Verification:
- [ ] TF.js models load via CDN without errors (if Phase 4.1 implemented)
- [ ] SaliencyAnalyzer returns valid focusPoint for test images

#### Manual Verification:
- [ ] ML-based saliency produces better default crops than center heuristic (if implemented)
- [ ] Saliency debug overlay correctly visualizes focal points
- [ ] App is usable on mobile devices (if responsive design implemented)
- [ ] PWA install prompt appears (if PWA implemented)
- [ ] Keyboard shortcuts work as documented
- [ ] CollageMaker project card appears under "Tools & Educational" category on the site's landing page

---

## Testing Strategy

### Unit Tests — Mocha + Chai
Run via CDN-loaded Mocha/Chai (following Midiestro's test pattern), executed in-browser against a test HTML page.

**Layout Math Tests:** Pure functions, ideal for unit testing:
- **FitMath tests:** Verify aspect-ratio calculations for various image/panel size combinations
- **UniformLayout tests:** Verify grid cell sizes and positions for 1-10 images
- **HeroLayout tests:** Verify hero panel takes left half, remaining panels fill right
- **MosaicLayout tests:** Verify deterministic output with same seed
- **DiagonalSlicesLayout tests:** Verify parallelogram vertex coordinates
- **HexagonalLayout tests:** Verify hexagon centers and radii
- **PolygonClipper tests:** Verify Sutherland-Hodgman clipping against known inputs
- **SeededPRNG tests:** Verify deterministic sequence

**State Manager Tests:**
- **CropManager tests:** Verify sourceRect clamping to image bounds, reset behavior
- **UndoManager tests:** Verify command stack push/pop, max 60 levels, batch grouping
- **TitleManager tests:** Verify TitleRun array mutations (insert, delete, toggle bold/italic/underline on ranges)
- **LayoutManager tests:** Verify layout regeneration triggers, gutter/slice angle/hex spacing updates

**Approach:** `CollageMaker/test/unit-tests.html` loads Mocha/Chai via CDN, imports ES modules under test, runs `describe`/`it` blocks. Follows Midiestro's `MidiSongBuilder/test/` pattern.

### UI Tests — Playwright
End-to-end browser tests using Playwright (already a dependency in `austin183.github.io/package.json`).

**Test scenarios:**
- **Image loading flow:** Drag-and-drop 3+ images, verify they appear in library sidebar and on canvas
- **Layout switching:** Cycle through all 5 layout styles, verify canvas re-renders
- **Crop editing:** Select panel, drag crop preview, verify canvas updates; corner-resize, verify proportional zoom
- **Title formatting:** Enter title text, apply bold/italic/underline to selection, verify rendered on canvas
- **Background changes:** Switch between solid/gradient/image backgrounds, verify canvas updates
- **Export flow:** Click export, verify JPEG file downloads, verify file is valid image
- **Undo/redo:** Make several edits, press Cmd+Z multiple times, verify state reverts; Cmd+Shift+Z to redo
- **Settings persistence:** Change settings, reload page, verify settings persist

**Approach:** `CollageMaker/test/ui-tests/` directory with Playwright test files. Reuse existing Playwright config from the repo. Tests run against `http://localhost:8000` (started via `start-server.sh`).

### Manual Testing Steps
1. Load 5 test images via drag-and-drop
2. Switch between all 5 layout styles, verify panels rearrange correctly
3. Select each panel, verify crop preview appears
4. Adjust crop via drag and corner-resize, verify canvas updates
5. Add a title, select text ranges, apply bold/italic/underline, verify on canvas
6. Change background to gradient, adjust colors and angle
7. Add a mask image, cycle through blend modes, adjust opacity
8. Export as JPEG at 100% quality, verify downloaded file
9. Undo several changes, verify state reverts
10. Reload page, verify settings persist

---

## Performance Considerations

### Canvas Rendering
- **Preview canvas** renders at reduced resolution (960x540) for responsiveness
- **Export canvas** renders at full resolution (1920x1080) only when needed
- **Debouncing:** Layout changes and slider adjustments debounce re-renders at 20ms (matching macOS `FrameTempo`)
- **`requestAnimationFrame`:** Batch canvas renders to avoid redundant draws

### Image Loading
- **`createImageBitmap()`:** Use GPU-backed image decoding for large images
- **Thumbnail generation:** Draw to small offscreen canvas for sidebar thumbnails
- **Memory management:** Release `ImageBitmap` objects when images are removed

### Large Image Handling
- **Preview scaling:** Never render full-resolution images on preview canvas
- **Export on-demand:** Full-resolution rendering only during export
- **Image count limit:** Consider soft limit (e.g., 20 images) with warning

---

## Migration Notes

### From macOS to Web
This is a **new implementation**, not a migration. The macOS app continues to exist independently. The web app is a parallel implementation targeting browsers.

### Data Portability
- No data migration needed — images are loaded fresh each session
- Settings persist via `localStorage` (web) vs `UserDefaults` (macOS) — separate stores

---

## Design Decisions (Resolved)

All open questions from the initial draft have been resolved:

| Decision | Resolution |
|----------|-----------|
| Font picker source | Web-safe fonts only (curated list) |
| Color picker implementation | Native `<input type="color">` |
| Title text formatting | Per-character formatting (bold/italic/underline via TitleRun segments) |
| Image format support | JPEG, PNG, GIF, WebP, SVG, BMP (standard `new Image()` formats) |
| Export resolution | Fixed 1920x1080 (1080p) |
| Overlay blend modes | All Canvas 2D `globalCompositeOperation` modes exposed |
| Landing page category | "Tools & Educational" (existing category) |
| Test infrastructure | Mocha/Chai unit tests + Playwright UI tests |

---

## References

### Specifications
- [World View Specifications](./specifications/world-view-specifications.md) — User-facing feature spec
- [Initial Thoughts](./InitialThoughts.md) — Project vision

### Research
- [Library & Architecture Research](./research/MidiestroLibraryResearch.md) — Platform mapping, reusable patterns, proposed architecture
- [TF.js Saliency Research](./research/TFJSModelsSaliencyResearch.md) — Saliency detection alternatives

### Source Code (macOS — to be ported)
- `~/workspace/agent-ollama-projects/Experiments/CollageMaker/CollageMaker/CollageMaker/Models/` — Data models
- `~/workspace/agent-ollama-projects/Experiments/CollageMaker/CollageMaker/CollageMaker/ViewModel/` — State management
- `~/workspace/agent-ollama-projects/Experiments/CollageMaker/CollageMaker/CollageMaker/Services/` — Business logic
- `~/workspace/agent-ollama-projects/Experiments/CollageMaker/CollageMaker/CollageMaker/Views/` — UI (reference only, full rewrite for web)

### Patterns (web — to be reused)
- `~/workspace/austin183.github.io/MidiSongBuilder/Midiestro3D.html` — Entry point pattern
- `~/workspace/austin183.github.io/MidiSongBuilder/MyESModules/createMidiestroApp.js` — Vue factory pattern
- `~/workspace/austin183.github.io/MidiSongBuilder/MyESModules/FileDropHandler.js` — File drop pattern
- `~/workspace/austin183.github.io/MidiSongBuilder/MyESModules/ThreeJSRenderer.js` — Canvas lifecycle pattern
- `~/workspace/austin183.github.io/src/css/variables.css` — Design tokens
- `~/workspace/austin183.github.io/src/js/themeSwitcher.js` — Theme toggle
