# CollageMaker Web Port — Library and Architecture Research

**Date:** 2026-06-30  
**Source:** Analysis of `Midiestro3D.html` and its ES module ecosystem  
**Target:** Porting CollageMaker from macOS SwiftUI to a static web app on `austin183.github.io`

---

## 1. Midiestro3D.html — Architecture Summary

### 1.1 Hosting Model

Midiestro3D.html is a **single HTML file** hosted as a static page on GitHub Pages (`austin183.github.io/MidiSongBuilder/Midiestro3D.html`). It loads all dependencies from CDNs and local ES modules — no build step, no bundler, no server-side code.

### 1.2 Library Stack

| Library | Version | Source | Purpose |
|---------|---------|--------|---------|
| **Vue 3** | 3.5.30 | `unpkg.com/vue@3.5.30/dist/vue.esm-browser.js` | Reactive state management, UI binding |
| **Three.js** | 0.183.0 | `unpkg.com/three@0.183.0` (import map) | 3D rendering (canvas-based) |
| **Tone.js** | 14.9.17 | `cdn.jsdelivr.net/npm/tone@14.9.17/build/Tone.js` | Audio synthesis |
| **@tonejs/midi** | latest | `unpkg.com/@tonejs/midi` | MIDI file parsing |
| **Pure CSS** | 3.0.0 | `cdn.jsdelivr.net/npm/purecss@3.0.0` | Minimal CSS framework |
| **Material Icons** | — | `fonts.googleapis.com` | Icon font |

### 1.3 Module Architecture

The app uses **native ES modules** (`type="module"`) with an **import map** for Three.js. All business logic lives in `MyESModules/` (~110 files). Key patterns:

- **Factory functions**: Every module exports a factory (e.g., `getScoreKeeper`, `createThreeJSRenderer`)
- **Mixin pattern**: Base functionality composed from mixins (state, audio, game loop, cleanup)
- **Strategy pattern**: Game modes (2D vs 3D) via `GameModeStrategy.js`
- **Dependency injection**: `ComponentRegistry` provides services to controllers
- **Vue 3 Options API**: `createMidiestroApp.js` assembles data, methods, lifecycle, and services into a Vue app

### 1.4 Shared Infrastructure

The `austin183.github.io` repo provides shared assets:

- **`src/css/variables.css`** — Design tokens (colors, spacing, typography, elevation, transitions) with dark mode support via `[data-theme="dark"]`
- **`src/css/CardGrid.css`** — Card grid layout styles
- **`src/css/Style.css`** — Global base styles
- **`src/js/themeSwitcher.js`** — Dark/light theme toggle with `localStorage` persistence and `prefers-color-scheme` detection
- **`src/js/collapsibleSections.js`** — Collapsible card UI pattern
- **`src/js/projectCards.js`** / `synopsis.js` — Index page utilities

---

## 2. CollageMaker — Current Architecture Summary

### 2.1 Platform Dependencies

CollageMaker is a **macOS SwiftUI desktop app** with deep Apple platform integration:

| Feature | macOS API | Web Equivalent? |
|---------|-----------|-----------------|
| UI Framework | SwiftUI + AppKit | Vue 3 (proven in Midiestro) |
| Image Loading | `NSImage`, `CGImage` | Canvas 2D (`createImageBitmap`, `drawImage`) |
| Image Picker | `NSOpenPanel` via `ImagePicker` protocol | `<input type="file">` + drag-and-drop |
| Saliency Analysis | Vision framework (`VNGenerateAttentionBasedSaliencyImageRequest`) | **No direct equivalent** — see Section 4 |
| Compositing | CoreGraphics (`CGContext`, `CGPath`, `CGImage`) | Canvas 2D API |
| Text Rendering | CoreText (`CTFramesetter`) | Canvas `fillText` / `measureText` |
| Color System | `NSColor` / `CGColor` | CSS colors / Canvas color strings |
| Font Management | `NSFontManager`, `FontMerger` | `document.fonts`, `@font-face` |
| Undo/Redo | `UndoManager` (AppKit) | Custom implementation needed |
| Persistence | `UserDefaults` | `localStorage` / `IndexedDB` |
| Concurrency | Swift actors, `@MainActor`, `Task` | `async/await`, Web Workers |
| Gestures | SwiftUI `.gesture()`, `.simultaneousGesture()` | Pointer events, custom gesture handling |
| Export | `NSBitmapImageRep` → JPEG | Canvas `toDataURL('image/jpeg')` / `toBlob()` |

### 2.2 Core Data Model

The key data structures from CollageMaker that need JavaScript equivalents:

- **`ImageItem`** — UUID + CGImage + thumbnail + filename + size
- **`ImagePanel`** — UUID + imageIndex + PanelGeometry (rect or path)
- **`CropInfo`** — panelId + sourceRect + destination geometry
- **`PanelGeometry`** — Either `.rect(CGRect)` or `.path(CGPath, boundingRect)`
- **`LayoutStyle`** — Enum: uniform, hero, mosaic, diagonalSlices, hexagonal
- **`LayoutOptions`** — sliceAngle, hexSpacing
- **`AssemblyConfig`** — layout + title + background + canvasSize + overlay
- **`TitleStyle`** — fontFamily, fontSize, fontColor, backgroundColor, alignment, showBackground
- **`BackgroundStyle`** — solid, gradient, image
- **`SizeConstants`** — defaultCanvasSize, defaultPreviewSize

### 2.3 Key Services

| Service | Role | Web Port Strategy |
|---------|------|-------------------|
| `CollageViewModel` | `@Observable` state, single source of truth | Vue 3 reactive state (proven pattern) |
| `LayoutManager` | Panel layout generation | Port `LayoutGenerator.swift` algorithms |
| `CropManager` | Per-panel crop state | JavaScript equivalent |
| `CollageAssembler` | CoreGraphics compositing | Canvas 2D API |
| `LayoutGenerator` | Panel layout math (5 strategies) | Pure JS — no platform deps |
| `PanelRenderer` | Per-panel image clipping | Canvas `clip()` + `drawImage()` |
| `BackgroundRenderer` | Background drawing (solid/gradient/image) | Canvas fill/gradient/drawImage |
| `TitleRendererCT` | CoreText title rendering | Canvas `fillText()` |
| `OverlayRenderer` | Double exposure mask | Canvas `globalCompositeOperation` |
| `SaliencyAnalyzer` | Vision-based focus detection | **Must be replaced** — see Section 4 |
| `RenderScheduler` | Serial queue for rendering | `async/await` or Web Worker |
| `ExportManager` | JPEG export flow | Canvas `toBlob()` + download |
| `ImageLibraryManager` | Image collection management | JavaScript array + reactive state |
| `UserDefaultsPersistence` | Settings persistence | `localStorage` |

---

## 3. Reusable Patterns from Midiestro

### 3.1 File Drop Handler

`FileDropHandler.js` provides a drag-and-drop + file input pattern that is **directly reusable** for CollageMaker's image loading. The CollageMaker web app needs a multi-file variant, but the core pattern (dragenter/dragover/drop listeners + file input change handler) is identical.

**Adaptation needed:** Accept multiple files (`e.dataTransfer.files` array) instead of single file, and accept image MIME types instead of `audio/midi`.

### 3.2 Theme System

The shared `variables.css` + `themeSwitcher.js` pattern provides:
- CSS custom properties for all colors
- Dark mode via `[data-theme="dark"]` selector
- `localStorage` persistence
- `prefers-color-scheme` auto-detection
- Custom event dispatch on theme change

**Directly reusable** for CollageMaker web app. The CollageMaker web app would add its own color tokens (e.g., `--collage-primary`) while inheriting the shared token system.

### 3.3 Collapsible Sections

`collapsibleSections.js` provides a `createSectionToggle()` factory that manages expand/collapse state. **Directly reusable** for any collapsible UI panels in CollageMaker (e.g., settings panels, instructions).

### 3.4 Vue 3 + ES Module Architecture

The `createMidiestroApp.js` pattern demonstrates:
- Vue 3 Options API with factory-assembled configuration objects
- Strategy pattern for mode-specific behavior
- Lifecycle hooks for init/cleanup
- Service injection via `provide`/`inject`

**Applicable to CollageMaker:** The web app would use a similar factory pattern: `createCollageApp({ dataConfig, methodsConfig, lifecycleConfig, servicesConfig })`.

### 3.5 Three.js Integration Pattern

Three.js is loaded via import map and used as a canvas renderer. For CollageMaker:
- **Three.js is NOT needed** — CollageMaker is a 2D collage tool
- However, the **canvas rendering pattern** (init renderer, render loop, resize handler, dispose) is applicable
- CollageMaker would use **Canvas 2D** instead of WebGL

### 3.6 Component Registry / DI

`ComponentRegistry.js` provides a simple dependency injection container. **Directly reusable** for managing CollageMaker services (layout manager, crop manager, assembler, etc.).

### 3.7 Browser Utilities

`BrowserUtils.js` provides feature detection (File API support). **Directly reusable** for checking Canvas API support, ImageBitmap support, etc.

---

## 4. Platform Gaps — What Has No Direct Equivalent

### 4.1 Saliency Analysis (Vision Framework)

**Current:** `SaliencyAnalyzer.swift` uses `VNGenerateAttentionBasedSaliencyImageRequest` from Apple's Vision framework to find focal regions in images.

**Web alternatives:**
- **TensorFlow.js** with a saliency model — heavy (~10MB+), complex
- **Simple heuristic fallback** — center-weighted crop or edge-detection via Canvas pixel analysis
- **Skip for MVP** — use "fit to panel" or "center crop" as default, add saliency later
- **ML5.js** — lighter-weight ML library, may have saliency or object detection models

**Recommendation:** Start with center-weighted default crops (the "fit" math from `FitMath.swift` is pure math and portable). Add saliency as a future enhancement.

### 4.2 CoreGraphics Path Clipping

**Current:** `PanelRenderer.swift` uses `CGContext` with `CGPath` for clipping images to panel shapes (rectangles, diagonal parallelograms, hexagons).

**Web equivalent:** Canvas 2D `ctx.beginPath()`, `ctx.moveTo()`, `ctx.lineTo()`, `ctx.clip()`, `ctx.drawImage()`. The `DiagonalSlicesLayoutStrategy` and `HexagonalLayoutStrategy` compute vertex coordinates that translate directly to Canvas path commands.

**Verdict:** Straightforward port. The layout math in `LayoutGenerator.swift` is pure computation with no platform dependencies.

### 4.3 CoreText Rich Text Rendering

**Current:** `TitleRendererCT.swift` uses CoreText (`CTFramesetter`, `CTLine`, etc.) for attributed string rendering with bold/italic/underline.

**Web equivalent:** Canvas `fillText()` with `font` property (e.g., `"bold italic 36px Arial"`). Underline requires manual `fillRect()` below text. For rich text with mixed styles, either:
- Parse attributed string into segments and render each with `fillText()`
- Use an HTML `<canvas>` overlay with actual HTML/CSS for text (complex)
- Use a library like **Opentype.js** for precise text metrics

**Recommendation:** Canvas `fillText()` for the MVP. The title system supports font family, size, color, background, and alignment — all achievable with Canvas 2D.

### 4.4 UndoManager

**Current:** macOS `UndoManager` with `registerUndo(withTarget:)` and grouping.

**Web equivalent:** Custom undo stack. Patterns:
- Command pattern: each action produces a `{ redo, undo }` pair
- Snapshot pattern: serialize state before/after each action
- Memento pattern: store state snapshots

**Recommendation:** Command pattern. The CollageViewModel already structures changes as discrete operations (setLayoutStyle, setGutter, resetCrop, etc.) — each can produce an undo command.

### 4.5 Font Management

**Current:** `FontMerger.swift` embeds fonts into exported JPEG. `NSFontManager` lists system fonts.

**Web equivalent:** 
- `document.fonts` API for available fonts
- No font embedding needed (JPEG export is pixel data, not font data)
- Font picker: `document.fonts.forEach()` to enumerate system fonts

### 4.6 Concurrency Model

**Current:** Swift actors, `@MainActor`, `Task`, `async/await`, `RenderScheduler` with dispatch queues.

**Web equivalent:**
- Main thread for UI (Vue reactivity)
- `async/await` for async operations
- Web Workers for heavy computation (layout generation, image processing)
- `requestAnimationFrame` for rendering loops

---

## 5. Proposed Web Architecture

### 5.1 Directory Structure

```
austin183.github.io/CollageMaker/
├── CollageMaker.html          # Main entry point (like Midiestro3D.html)
├── Style.css                  # CollageMaker-specific styles
├── MyESModules/
│   ├── CollageApp.js          # createCollageApp() — Vue app factory
│   ├── CollageState.js        # Reactive state (replaces CollageViewModel)
│   ├── ImageLibrary.js        # Image collection management
│   ├── LayoutGenerator.js     # Ported from LayoutGenerator.swift
│   ├── PanelRenderer.js       # Canvas 2D panel rendering
│   ├── BackgroundRenderer.js  # Canvas 2D background rendering
│   ├── TitleRenderer.js       # Canvas 2D text rendering
│   ├── OverlayRenderer.js     # Canvas 2D composite operations
│   ├── CollageAssembler.js    # Composites all layers
│   ├── CropManager.js         # Per-panel crop state
│   ├── UndoManager.js         # Custom undo/redo
│   ├── ExportManager.js       # Canvas toBlob + download
│   ├── FileDropHandler.js     # Multi-file image drop (adapted from Midiestro)
│   ├── GestureHandler.js      # Pan, zoom, pinch for web
│   ├── Persistence.js         # localStorage settings
│   ├── SaliencyFallback.js    # Center-weighted crop heuristic
│   └── models/
│       ├── ImageItem.js       # Data model
│       ├── ImagePanel.js      # Panel data model
│       ├── LayoutStyle.js     # Layout enum
│       └── AssemblyConfig.js  # Assembly configuration
└── test/
    └── (Mocha/Chai tests, following Midiestro pattern)
```

### 5.2 Rendering Pipeline

The CollageMaker rendering pipeline maps to Canvas 2D:

```
1. Background layer     → ctx.fillStyle / ctx.createLinearGradient() / ctx.drawImage()
2. Panel layer          → ctx.save() → ctx.beginPath() → ctx.clip() → ctx.drawImage() → ctx.restore()
3. Overlay layer        → ctx.globalCompositeOperation = 'multiply' → ctx.drawImage()
4. Title layer          → ctx.font / ctx.fillText() / ctx.fillRect() (background)
5. Export               → canvas.toBlob(callback, 'image/jpeg', quality)
```

### 5.3 Canvas Strategy

Two canvas elements:
- **Preview canvas** — Scaled-down real-time preview (like `defaultPreviewSize`)
- **Export canvas** — Full-resolution canvas created on-demand for export (like `defaultCanvasSize`)

The preview canvas updates on every state change (debounced). The export canvas is only created when the user clicks "Export JPEG."

### 5.4 Libraries Needed for CollageMaker Web

| Library | Purpose | CDN |
|---------|---------|-----|
| **Vue 3** | Reactive state + UI | `unpkg.com/vue@3.5.30` (same as Midiestro) |
| **Pure CSS** | Base styles | `cdn.jsdelivr.net/npm/purecss@3.0.0` (same as Midiestro) |
| **Material Icons** | Icons | `fonts.googleapis.com` (same as Midiestro) |

**NOT needed:**
- Three.js (2D only)
- Tone.js (no audio)
- @tonejs/midi (no MIDI)

**Shared with Midiestro:**
- `src/css/variables.css` — Design tokens
- `src/js/themeSwitcher.js` — Theme toggle
- `src/js/collapsibleSections.js` — Collapsible panels
- `src/css/CardGrid.css` — Potentially useful for image library grid

---

## 6. Porting Priority — What to Port First

### Phase 1: Core Rendering (MVP)
1. **LayoutGenerator.js** — Pure math, no platform deps, direct port from Swift
2. **PanelRenderer.js** — Canvas 2D clipping, straightforward mapping from CoreGraphics
3. **CollageAssembler.js** — Compose layers on Canvas
4. **ImageLibrary.js** + **FileDropHandler.js** — Load images via drag-and-drop
5. **CollageState.js** — Vue reactive state replacing CollageViewModel
6. **CollageApp.js** — Vue app factory following Midiestro pattern

### Phase 2: Editing Features
7. **CropManager.js** — Per-panel crop state
8. **GestureHandler.js** — Drag to pan crop, corner drag to zoom
9. **UndoManager.js** — Custom undo/redo
10. **BackgroundRenderer.js** — Solid/gradient/image backgrounds

### Phase 3: Polish
11. **TitleRenderer.js** — Text overlay with styling
12. **OverlayRenderer.js** — Double exposure mask
13. **ExportManager.js** — JPEG download
14. **Persistence.js** — localStorage settings
15. **SaliencyFallback.js** — Smart default crops

### Phase 4: Advanced
16. **Saliency via ML** — TensorFlow.js or ML5.js integration
17. **Responsive design** — Mobile support
18. **PWA** — Offline capability, install prompt

---

## 7. Key Technical Decisions

### 7.1 Vue 3 Options API vs Composition API

Midiestro uses Vue 3 **Options API** (`data`, `methods`, `mounted`). For CollageMaker, the **Composition API** with `<script setup>` might be cleaner, but since we're using inline ES modules (no SFC build step), the Options API via `createApp()` is the proven pattern.

**Decision:** Use Options API to match Midiestro's proven pattern. The `createCollageApp()` factory follows the same structure as `createMidiestroApp()`.

### 7.2 Canvas vs SVG

**Canvas 2D** is the right choice because:
- CollageMaker does pixel-level compositing (clipping, blending, gradients)
- Canvas `toBlob()` provides direct JPEG export
- Midiestro's canvas patterns are proven
- SVG would require complex clipping paths and wouldn't export to JPEG easily

### 7.3 Image Loading Strategy

**Web approach:**
1. User drops/selects image files
2. `FileReader.readAsDataURL()` or `createImageBitmap()` to load images
3. Draw to offscreen canvas to get pixel data
4. Store as `ImageBitmap` or `HTMLImageElement` in state

**Key difference from macOS:** No `CGImage` — use `ImageBitmap` for efficient rendering, or `HTMLImageElement` for simplicity.

### 7.4 Coordinate Systems

CollageMaker's macOS version deals with three coordinate systems (Vision bottom-left, CoreGraphics top-left, NSImage top-left). The web version simplifies to:
- **Canvas coordinates:** Top-left origin, Y increases downward
- **DOM coordinates:** Top-left origin, Y increases downward
- **No Vision framework:** No coordinate flip needed

This is a significant simplification over the macOS version.

---

## 8. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Canvas performance with large images | Slow rendering | Use preview canvas at reduced resolution, full-res only for export |
| No saliency analysis | Less smart default crops | Center-weighted heuristic, allow manual crop adjustment |
| Memory pressure from many images | Browser crash | Limit image count, use `createImageBitmap` (GPU-backed), release unused images |
| Touch gesture support | Mobile usability | Pointer events API, consider Hammer.js if needed |
| Font availability | Title rendering differences | Use web-safe fonts as defaults, `document.fonts` for system font picker |
| Large file sizes | Slow page load | Lazy-load images, use CDN for libraries |

---

## 9. Files Referenced in This Research

### Midiestro Source (patterns to reuse)
- `/Users/austin/workspace/austin183.github.io/MidiSongBuilder/Midiestro3D.html` — Main entry point
- `/Users/austin/workspace/austin183.github.io/MidiSongBuilder/MyESModules/MidiestroBase.js` — Service initialization pattern
- `/Users/austin/workspace/austin183.github.io/MidiSongBuilder/MyESModules/createMidiestroApp.js` — Vue app factory pattern
- `/Users/austin/workspace/austin183.github.io/MidiSongBuilder/MyESModules/FileDropHandler.js` — File drop pattern
- `/Users/austin/workspace/austin183.github.io/MidiSongBuilder/MyESModules/ThreeJSRenderer.js` — Canvas renderer lifecycle
- `/Users/austin/workspace/austin183.github.io/src/css/variables.css` — Shared design tokens
- `/Users/austin/workspace/austin183.github.io/src/js/themeSwitcher.js` — Theme toggle
- `/Users/austin/workspace/austin183.github.io/src/js/collapsibleSections.js` — Collapsible panels
- `/Users/austin/workspace/austin183.github.io/MidiSongBuilder/Style.css` — Component CSS patterns

### CollageMaker Source (to be ported)
- `/Users/austin/workspace/agent-ollama-projects/Experiments/CollageMaker/CollageMaker/CollageMaker/ViewModel/CollageViewModel.swift` — State management
- `/Users/austin/workspace/agent-ollama-projects/Experiments/CollageMaker/CollageMaker/CollageMaker/Services/CollageAssembler.swift` — Compositing
- `/Users/austin/workspace/agent-ollama-projects/Experiments/CollageMaker/CollageMaker/CollageMaker/Services/LayoutGenerator.swift` — Layout math
- `/Users/austin/workspace/agent-ollama-projects/Experiments/CollageMaker/CollageMaker/CollageMaker/Models/ImageItem.swift` — Data model
- `/Users/austin/workspace/agent-ollama-projects/Experiments/CollageMaker/CollageMaker/CollageMaker/Models/ImagePanel.swift` — Panel model
- `/Users/austin/workspace/agent-ollama-projects/Experiments/CollageMaker/CollageMaker/CollageMaker/Models/AssemblyConfig.swift` — Config model
- `/Users/austin/workspace/agent-ollama-projects/Experiments/CollageMaker/CollageMaker/CollageMaker/Models/LayoutStyle.swift` — Layout enum

### Specifications
- `/Users/austin/workspace/_agent_docs/CollageProject/ConvertToWebsite/InitialThoughts.md` — Project vision
- `/Users/austin/workspace/_agent_docs/CollageProject/ConvertToWebsite/specifications/world-view-specifications.md` — User-facing feature spec
