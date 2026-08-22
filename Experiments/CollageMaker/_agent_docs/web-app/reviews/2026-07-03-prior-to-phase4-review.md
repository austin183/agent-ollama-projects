# Architecture and SOLID Review: CollageMaker (Prior to Phase 4)

**Date:** 2026-07-03
**Reviewers:** Manual Analysis + World-Review Subagent + SOLID-Review-G31 Subagent
**Scope:** Full codebase under `MyESModules/`, `index.html`, `Style.css`

---

## 1. Executive Summary

The CollageMaker project demonstrates a strong foundation in the "pure logic" layers (Models, Layout, and Rendering). The use of factory functions, plain objects, and a clear directory structure has prevented the codebase from becoming a tangled mess of classes. However, as the project has grown, the "glue" layer—specifically the application assembly and state management—has begun to suffer from significant architectural erosion.

**Critical risks identified across three review perspectives:**

1. **God Module:** `createCollageMethods.js` (768 lines) centralizes every UI action, violating SRP and creating a fragile star-topology dependency graph.
2. **Framework Coupling:** State managers directly mutate Vue reactive state, binding business logic to the presentation framework and hindering testability and portability.
3. **OCP Violations:** Both `LayoutGenerator` (switch dispatch) and `ExportManager` (JPEG-only) require core file modifications to extend.
4. **Memory Leaks:** Image references, object URLs, and thumbnail canvases are never cleaned up when images are removed.
5. **Duplicate Logic:** Canvas clearing and background rendering are performed redundantly across `CanvasRenderer` and `CollageAssembler`.
6. **Dead Code:** `CollageState.js` is defined but never used; `migrateLayoutStyle()` is exported but never called; `ComponentRegistry.js` is instantiated but never wired to any services.

Addressing the Critical and High items before Phase 4 is essential to maintain development velocity and code stability.

---

## 2. Project Architecture Overview

The project follows a modular ES module architecture organized under `MyESModules/`. No build step, no bundler—browser-native modules with CDN-loaded Vue 3.

```
MyESModules/
├── App/              # Vue assembly (6 files)
├── Models/           # Data factories (9 files)
├── Layout/           # Pure math, panel generation (9 files)
├── Rendering/        # Canvas 2D drawing (6 files)
├── State/            # State managers (7 files)
├── Interaction/      # DOM event handling (3 files)
├── Export/           # File export (1 file)
├── Persistence/      # localStorage I/O (1 file)
├── Saliency/         # Image analysis (1 file)
└── Utils/            # Shared helpers (2 files)
```

**Data flow:** User interaction → Vue methods → State managers → Reactive state → `requestAnimationFrame` → Canvas render pipeline.

---

## 3. SOLID Principles Analysis

### 3.1 Single Responsibility Principle (SRP)
**Verdict: Good in pure layers, violated in App layer**

| Status | Component | Detail |
|--------|-----------|--------|
| ✅ | `Models/*.js` | Pure data factories, one concern each |
| ✅ | `Layout/*.js` | Pure math, no side effects |
| ✅ | `Rendering/*.js` | Focused canvas drawing functions |
| ✅ | `State/UndoManager.js` | Self-contained command pattern, no external deps |
| ✅ | `Persistence/SettingsPersistence.js` | Simple localStorage wrapper |
| ✅ | `Saliency/SaliencyFallback.js` | Isolated image analysis |
| ✅ | `Utils/*.js` | Generic, reusable helpers |
| ⚠️ | `Rendering/CanvasRenderer.js` | Lines 96-107: clears canvas AND fills white background—painting logic belongs in assembler, not lifecycle manager |
| ⚠️ | `Rendering/CollageAssembler.js` | Lines 120-129: `_drawBackground()` duplicates `BackgroundRenderer.render()`—legacy fallback creating duplicate logic |
| ❌ | `App/createCollageMethods.js` | **God Module (768 lines).** Handles: file picking, image management, layout changes, crop operations, undo/redo, background editing, title editing, overlay management, export, sidebar toggling, settings persistence, image loading. Every UI action funnels through this single file. |

**Suggested Fixes:**
- Decompose `createCollageMethods.js` into focused groups: `createFileMethods()`, `createLayoutMethods()`, `createCropMethods()`, `createBackgroundMethods()`, `createTitleMethods()`, `createExportMethods()`, `createSettingsMethods()`. Compose them in `createCollageApp.js`.
- Remove painting logic from `CanvasRenderer` (lifecycle only). Remove `_drawBackground()` from `CollageAssembler`—always route through `BackgroundRenderer`.

---

### 3.2 Open/Closed Principle (OCP)
**Verdict: Needs Improvement**

**Issue 1 — Layout Extension (LayoutGenerator.js lines 39-51)**

Adding a new layout style (e.g., "Polaroid") requires modifying three locations:
1. `Models/LayoutStyle.js` — add new constant + option entry
2. `Layout/LayoutGenerator.js` — add new `case` in the `switch` statement
3. New layout file (e.g., `PolaroidLayout.js`)

The `switch` statement is the textbook OCP violation. Every new layout requires modifying the core generator.

**Issue 2 — Export Extension (ExportManager.js)**

`exportToJpeg()` is hardcoded: MIME type `'image/jpeg'` (line 69), filename `'collage.jpg'` (line 59). Adding PNG, WebP, or SVG requires modifying the export module. SVG export would additionally require entirely different rendering logic since the app uses Canvas 2D, not an SVG renderer.

**Issue 3 — No Plugin Architecture**

`ComponentRegistry.js` exists as a simple key-value service map but is never populated or queried by any module. There are no observable hooks, event systems, or extension points for third-party or user extensions.

**Suggested Fixes:**
- **Layout Registry:** Replace the `switch` in `LayoutGenerator` with a `Map`-based registry. Each layout module self-registers at import time:
  ```
  registerLayoutStyle(LayoutStyle.HERO, generateHeroLayout);
  ```
  `generate()` performs a `Map.get()` lookup. New layouts require zero modifications to existing files.
- **Export Strategy Registry:** Define an export strategy interface (`{ mimeType, extension, render(assembler, state, quality) }`). Each format registers itself. The UI calls `exportCollage(format, quality)`.
- **Activate ComponentRegistry:** Wire it into `CollageBase` and use it for service discovery instead of direct imports.

---

### 3.3 Liskov Substitution Principle (LSP)
**Verdict: N/A**

The project avoids class inheritance entirely, using factory functions and plain objects throughout. The factory pattern is appropriate for this codebase. LSP does not directly apply.

---

### 3.4 Interface Segregation Principle (ISP)
**Verdict: Good, with one significant concern**

**Strengths:**
- Manager interfaces are focused: `CropManager` handles only crops, `BackgroundManager` handles only backgrounds, `ImageLibrary` handles only image collection.
- Callback parameters are minimal and single-purpose: `onCropChanged`, `onImagesChanged`, `onBackgroundChanged`.

**Concern — Full Vue Instance Passed to Managers**

Every state manager receives the entire Vue instance as the `state` argument. For example:
- `createCropManager(state, onCropChanged)` — needs only `crops`, `panels`, `images`, `panelAssignments`
- `createLayoutManager(state, assembler)` — needs only `images`, `panels`, `crops`, `panelAssignments`, `layoutStyle`, `gutter`, `sliceAngle`, `hexSpacing`, `layoutVersion`
- `createImageLibrary(state, onImagesChanged)` — needs only `images`

Yet each receives the full Vue component with all 30+ reactive properties. This forces managers to implicitly depend on the complete state shape and makes it impossible to understand a manager's true dependencies without reading its implementation.

**Suggested Fix:**
Pass a **State View** — a curated, read-only subset of state that each manager actually needs:
```js
createCropManager({
    crops: this.crops,
    panels: this.panels,
    images: this.images,
    panelAssignments: this.panelAssignments
}, onCropChanged);
```
This makes each manager's dependencies explicit, minimal, and self-documenting.

---

### 3.5 Dependency Inversion Principle (DIP)
**Verdict: Partial Compliance**

**Strengths:**
- Callbacks are used throughout as inversion points: `onCropChanged`, `onImagesChanged`, `onRenderScheduled`, `onDragStart`, `onDragEnd`.
- `CollageBase.js` uses lazy getters/setters for services that need state, deferring initialization until the `mounted()` lifecycle hook. Clean dependency resolution.
- `ComponentRegistry.js` provides a DI container (currently underutilized).

**Issues:**

**Framework Coupling (CropManager.js, LayoutManager.js, ImageLibrary.js, BackgroundManager.js, TitleManager.js)**

Managers directly mutate Vue reactive state. Examples:
- `CropManager.js` line 40-41: `crop.sourceRect.x = newX; crop.sourceRect.y = newY;`
- `LayoutManager.js` line 22-25: `state.panels = []; state.crops = new Map(); state.panelAssignments = new Map();`
- `ImageLibrary.js` line 36: `state.images.push(...validItems);`
- `BackgroundManager.js` line 49: `state.backgroundStyle = newStyle;`

This is a concrete dependency on Vue's reactivity system. If this logic were ever needed outside Vue (e.g., a Node.js export worker, a standalone layout preview, or unit tests), it would not work.

**Concrete State Dependency (GestureHandler.js line 92)**

`hitTestPanel()` reads `state.panels` directly from the closure instead of receiving panels as a parameter. This hardcodes the dependency on the state shape.

**Suggested Fix:**
Managers should operate on plain data structures and return results rather than mutating in place. The Vue layer should be the thin adapter that:
1. Extracts data from reactive state
2. Calls manager methods with plain data
3. Writes results back to reactive state

For example, `CropManager.adjustCrop()` could accept a plain `Map` and return a new `Map` with the adjusted crop, leaving Vue to decide how to apply the change.

---

## 4. Separation of Concerns Analysis

### 4.1 Layer Analysis

| Layer | Responsibility | Coupling | Verdict |
|-------|----------------|----------|---------|
| `Models/` | Pure data factories | None | ✅ Clean |
| `Layout/` | Pure math, panel generation | None | ✅ Clean |
| `Rendering/` | Canvas drawing functions | Depends on Models only | ✅ Clean |
| `State/` | State mutation logic | Depends on Vue reactivity | ⚠️ Tight coupling |
| `Interaction/` | DOM event handling | Depends on State managers | ✅ Acceptable |
| `App/` | Vue assembly, UI glue | Depends on everything | ❌ God module |
| `Export/` | File export | Depends on Rendering | ✅ Clean |
| `Persistence/` | localStorage I/O | None | ✅ Clean |
| `Saliency/` | Image analysis | None | ✅ Clean |
| `Utils/` | Shared helpers | None | ✅ Clean |

### 4.2 Key Coupling Issues

1. **Bidirectional State Coupling:** The State layer is tightly bound to the App layer. Managers receive the Vue instance, mutate its properties, and rely on Vue's reactivity to propagate changes. This creates a bidirectional dependency between business logic and presentation.

2. **Star Topology:** `createCollageMethods.js` imports from `Export/`, `Persistence/`, and calls into `LayoutManager`, `ImageLibrary`, `CropManager`, `BackgroundManager`, `TitleManager`, and `UndoManager`. It is the central hub of a star-topology dependency graph—a fragile point of failure and a bottleneck for maintenance.

3. **Logic Duplication:** `CanvasRenderer.render()` (lines 96-107) clears the canvas and fills it white. `CollageAssembler.render()` (line 44) immediately clears it again and draws the actual background. Three background-clearing operations per frame: renderer clear → renderer fill-white → assembler clear → assembler/background-renderer fill.

4. **Dead Code — CollageState.js:** `State/CollageState.js` defines `createCollageState()` with a complete state shape, but it is never imported or used anywhere. `App/createCollageData.js` duplicates the same state structure inline. This is a duplicate source of truth.

5. **Dead Code — migrateLayoutStyle:** `Models/LayoutStyle.js` exports `migrateLayoutStyle()` (lines 27-32) but it is never called by any module.

6. **Dead Code — ComponentRegistry:** `Utils/ComponentRegistry.js` is instantiated in `CollageBase.js` and provided via Vue's `provide()`, but no component or manager ever calls `registerService()` or `getService()`.

---

## 5. Code Quality Observations

### 5.1 Strengths

- **Documentation:** Excellent. JSDoc comments with parameter types are present for nearly every function. Module-level comments explain purpose and Swift origin.
- **Naming:** High consistency. `createXxx` for factories, `XxxManager` for managers, `onXxx` for callbacks.
- **Factory Pattern:** Consistent use of factory functions over classes. Appropriate for the no-build-step constraint.
- **Pure Functions:** Layout generation (`Layout/`) and rendering (`Rendering/`) are free of side effects. Easily testable.

### 5.2 Bugs and Defects

**Bug 1 — Hit-Test Coordinate Transformation (GestureHandler.js lines 82-98)**

`hitTestPanel()` computes `scaleX = 1920 / canvasWidth` and `scaleY = 1080 / canvasHeight` separately, then uses `Math.min(scaleX, scaleY)` for the conceptual letterbox scale. However, `logicalX = x * scaleX` and `logicalY = y * scaleY` use the individual scales, not the letterbox scale. When the canvas is letterboxed (aspect ratio differs from 16:9), hit-testing will be inaccurate—clicks near the letterbox bars will map to wrong canvas coordinates.

**Bug 2 — Crop Preview DPR Mismatch (createCollageMethods.js lines 288-295)**

`_scheduleCropPreviewRender()` sets `ctx.setTransform(dpr, 0, 0, dpr, 0, 0)` (line 295) but then draws using CSS pixel coordinates (`cssW`, `cssH`). The transform scales subsequent drawing by DPR, so coordinates that are already in CSS pixels get drawn at 2x or 3x their intended size on high-DPR displays. This causes rendering inconsistencies on Retina and other high-DPR screens.

---

## 6. UX and Robustness Findings

### 6.1 Memory and Resource Management

**Memory Leak — Image References (ImageLibrary.js lines 63-85)**

`_loadImage()` creates `HTMLImageElement` objects and stores them in `state.images`. When images are removed via `removeImage()` (line 44-47), the image elements are spliced from the array but their internal resources (decoded pixel data, GPU textures) are never released. Over time, loading and removing many images will accumulate memory.

**Resource Leak — Object URLs (createCollageLifecycle.js lines 166-168)**

`beforeUnmount()` sets `this.backgroundImage = null; this.overlayImage = null;` but does not revoke any object URLs created during image loading. If images were loaded via `URL.createObjectURL()`, those URLs persist in the browser's memory.

**Resource Leak — Thumbnail Canvases (ImageItem.js)**

`generateThumbnail()` creates a new `<canvas>` element and 2D context for every image loaded. These offscreen canvases are never disposed. With many images, this accumulates GPU resources.

**Missing — Canvas Context Disposal (CanvasRenderer.js line 130)**

`dispose()` sets `canvas = null; ctx = null;` but does not clear the canvas content or ensure the browser releases the GPU texture associated with the 2D context.

### 6.2 Performance

**Reactivity Trigger Spam (createCollageMethods.js `_scheduleRender()`)**

During crop dragging, each `adjustCrop()` call triggers `onCropChanged()` which calls `_scheduleRender()`. While `requestAnimationFrame` debouncing in `CanvasRenderer.scheduleRender()` helps, each pointer move event still schedules a new frame. Rapid dragging generates many scheduled renders.

**Polygon Hit-Testing Performance (GestureHandler.js line 118-130)**

`_pointInPolygon()` uses an O(n) even-odd fill rule algorithm. For each pointer event, it iterates all panels and runs the algorithm on each. With complex layouts (hexagonal, diagonal slices) that have many panels with many polygon vertices, this becomes a bottleneck during hover and selection.

**Title Text Re-Computation (TitleManager.js line 274)**

`getFullText()` calls `(state.titleRuns || []).map(r => r.text).join('')` every time it's invoked. For titles with many formatted runs, this allocates new arrays and strings on every call. Called from `toggleBold()`, `toggleItalic()`, `toggleUnderline()`, `insertChar()`, and `deleteChar()`.

### 6.3 Robustness

**No Image Size Validation (ImageLibrary.js)**

When users load very large images (e.g., 4K+ photos, 50MP camera images), there is no size limiting or warning. The app attempts to process them fully, risking:
- Memory exhaustion in the browser
- Canvas rendering failures due to maximum texture size limits (typically 16384x16384)
- Export failures with `canvas.toBlob()` throwing errors for oversized canvases

**No Browser Compatibility Checks**

The code assumes modern canvas 2D API features without feature detection:
- Pointer events (`pointerdown`, `pointermove`) in `GestureHandler.js` and `CropInteraction.js` — no fallback to touch/mouse events
- `ctx.createLinearGradient`, `globalCompositeOperation`, `globalAlpha` — used without checking support
- `canvas.setPointerCapture()` in `CropInteraction.js` line 190 — not supported in all browsers

**Silent Failures in Layout Generation (LayoutGenerator.js line 51)**

Invalid layout styles fall back to `generateHeroLayout(base)` silently. No warning, no error, no user notification.

**TitleManager Edge Cases (TitleManager.js `applyFormattingToRange`)**

The `applyFormattingToRange()` function has potential issues:
- When `startIndex >= endIndex`, it returns early (line 53), but the callers (`toggleBold`, etc.) pass `undefined` as the formatting value to trigger toggle behavior, which may produce unexpected results
- Character index mapping could produce empty runs when formatting boundaries align exactly with existing run boundaries

**Drag-and-Drop Visual Feedback Gap (FileDropHandler.js lines 29-41)**

The drop handler adds `drag-over` class to `document.body` only. The canvas-specific drag state visible in `Style.css` (line 268, `.canvas-container.drag-over`) is never actually applied, since the handler targets `document.body`, not the canvas container.

### 6.4 UX Friction

**No Loading State (ImageLibrary.js)**

When images are added via file picker or drag-and-drop, there is no visual loading indicator while thumbnails are generated and layouts are computed. Users with large files or slow devices may experience apparent unresponsiveness.

**Title Formatting on Mobile (index.html lines 201-211)**

The formatting buttons use `@mousedown.prevent @click="toggleTitleBold"`. On mobile/touch devices, `mousedown` may not properly capture text selection state, making bold/italic/underline toggling unreliable.

---

## 7. Prioritized Recommendations

### Critical — Block Future Growth

| # | Recommendation | Principle | Files |
|---|---------------|-----------|-------|
| 1 | **Decompose `createCollageMethods.js`** — Split the 768-line god module into focused method groups (`createFileMethods`, `createLayoutMethods`, `createCropMethods`, `createBackgroundMethods`, `createTitleMethods`, `createExportMethods`, `createSettingsMethods`). Compose in `createCollageApp.js`. | SRP | `App/createCollageMethods.js`, `App/createCollageApp.js` |
| 2 | **Eliminate redundant painting** — Remove canvas clear + white fill from `CanvasRenderer.render()` (lines 96-107). Remove `_drawBackground()` from `CollageAssembler` (lines 120-129). Let `BackgroundRenderer` be the single source of truth for background rendering. | SRP, DRY | `Rendering/CanvasRenderer.js`, `Rendering/CollageAssembler.js` |
| 3 | **Fix memory leaks** — Revoke object URLs when images are removed. Null out `HTMLImageElement.src` in `ImageLibrary.removeImage()`. Dispose thumbnail canvases. Clean up in `beforeUnmount`. | Robustness | `State/ImageLibrary.js`, `Models/ImageItem.js`, `App/createCollageLifecycle.js` |

### High — Architectural Debt

| # | Recommendation | Principle | Files |
|---|---------------|-----------|-------|
| 4 | **Implement Layout Registry** — Replace the `switch` in `LayoutGenerator.generate()` with a `Map`-based registry. Each layout module self-registers at import time. New layouts require zero modifications to existing files. | OCP | `Layout/LayoutGenerator.js`, `Layout/*.js` |
| 5 | **Decouple State Managers from Vue** — Transition managers to accept plain data structures and return results, rather than mutating Vue reactive state. The Vue layer becomes a thin adapter. | DIP | `State/*.js` |
| 6 | **Implement State Views** — Pass curated state subsets to each manager instead of the full Vue instance. Makes dependencies explicit and minimal. | ISP | `State/*.js`, `App/createCollageLifecycle.js` |
| 7 | **Remove dead code** — Delete `CollageState.js` (unused, duplicated by `createCollageData.js`). Either wire up `ComponentRegistry.js` or remove it. Either use `migrateLayoutStyle()` or remove it. | DRY | `State/CollageState.js`, `Utils/ComponentRegistry.js`, `Models/LayoutStyle.js` |

### Medium — Quality and Stability

| # | Recommendation | Principle | Files |
|---|---------------|-----------|-------|
| 8 | **Fix hit-test coordinate transform** — Correct `GestureHandler.hitTestPanel()` to use the letterbox scale consistently for both X and Y, accounting for canvas padding. | Bug fix | `Interaction/GestureHandler.js` |
| 9 | **Fix crop preview DPR** — Correct `_scheduleCropPreviewRender()` to use consistent coordinate systems after `ctx.setTransform(dpr, ...)`. | Bug fix | `App/createCollageMethods.js` |
| 10 | **Add image size validation** — Reject or downscale images exceeding canvas maximum texture size (~16384px). Warn user if image is too large. | Robustness | `State/ImageLibrary.js` |
| 11 | **Add browser feature detection** — Check for pointer event support, canvas 2D features. Provide fallbacks or graceful degradation. | Robustness | `Interaction/*.js`, `Rendering/*.js` |

### Low — Polish and Optimization

| # | Recommendation | Principle | Files |
|---|---------------|-----------|-------|
| 12 | **Export strategy registry** — Create a strategy pattern for export formats (PNG, WebP, SVG). | OCP | `Export/ExportManager.js` |
| 13 | **Add loading indicators** — Show visual feedback during image processing and layout generation. | UX | `index.html`, `App/createCollageMethods.js` |
| 14 | **Optimize polygon hit-testing** — Add bounding-box pre-checks before running even-odd fill rule. Consider spatial indexing for complex layouts. | Performance | `Interaction/GestureHandler.js` |
| 15 | **Cache title text** — Memoize `TitleManager.getFullText()` or maintain a running total to avoid repeated string allocations. | Performance | `State/TitleManager.js` |
| 16 | **Fix mobile title formatting** — Replace `@mousedown.prevent` with touch-friendly selection handling. | UX | `index.html` |
| 17 | **Fix drag-over visual feedback** — Apply `drag-over` class to canvas container, not just `document.body`. | UX | `Interaction/FileDropHandler.js` |

---

## 8. Appendix: File-by-File Assessment

### App/

| File | Lines | Assessment | Key Issues |
|------|-------|-----------|------------|
| `CollageBase.js` | 74 | Good | Clean service initialization with lazy getters. `ComponentRegistry` created but never used. |
| `createCollageApp.js` | 51 | Good | Clean Vue assembly. Computed properties are well-defined. |
| `createCollageData.js` | 71 | Fair | Duplicates state structure from unused `CollageState.js`. |
| `createCollageLifecycle.js` | 229 | Fair | Proper cleanup in `beforeUnmount` but missing object URL revocation and image resource disposal. |
| `createCollageMethods.js` | 768 | **Poor** | God module. Contains crop preview rendering (should be in Rendering/), image loading (should be in Models/), and every UI action handler. |
| `createCollageServices.js` | 17 | Good | Minimal, provides assembler and registry. |

### Models/

| File | Assessment | Notes |
|------|-----------|-------|
| `LayoutStyle.js` | Excellent | Clean enum + options. `migrateLayoutStyle()` is dead code. |
| `ImageItem.js` | Good | Thumbnail generation creates undisposed canvases. |
| `ImagePanel.js` | Excellent | Pure factory. |
| `PanelGeometry.js` | Excellent | Pure geometry helpers. |
| `SizeConstants.js` | Excellent | Shared constants. |
| `CropInfo.js` | Excellent | Pure factories. |
| `BackgroundStyle.js` | Excellent | Clean enum + factory. |
| `TitleStyle.js` | Excellent | Pure factory. |
| `TitleRun.js` | Excellent | Pure factories with comparison helper. |

### Layout/

| File | Assessment | Notes |
|------|-----------|-------|
| `LayoutGenerator.js` | Fair | Switch dispatch violates OCP. Needs registry pattern. |
| `UniformLayout.js` | Excellent | Pure math. |
| `HeroLayout.js` | Excellent | Pure math. |
| `MosaicLayout.js` | Excellent | Pure math. |
| `DiagonalSlicesLayout.js` | Excellent | Pure math. |
| `HexagonalLayout.js` | Excellent | Pure math. |
| `FitMath.js` | Excellent | Pure math utilities. |
| `PolygonClipper.js` | Excellent | Pure geometry. |
| `SeededPRNG.js` | Excellent | Deterministic PRNG. |

### Rendering/

| File | Assessment | Notes |
|------|-----------|-------|
| `CanvasRenderer.js` | Fair | Good lifecycle management. Redundant clearing/filling in `render()`. Incomplete `dispose()`. |
| `CollageAssembler.js` | Fair | Good pipeline orchestration. Duplicate `_drawBackground()` method. |
| `PanelRenderer.js` | Excellent | Clean clip + draw logic. Proper source rect clamping. |
| `BackgroundRenderer.js` | Excellent | Pure rendering function. Single source of truth for backgrounds. |
| `OverlayRenderer.js` | Excellent | Clean blend mode + opacity rendering. |
| `TitleRenderer.js` | Excellent | Efficient two-pass measurement + rendering. |

### State/

| File | Assessment | Notes |
|------|-----------|-------|
| `CollageState.js` | **Dead code** | Never imported or used. Duplicated by `createCollageData.js`. |
| `LayoutManager.js` | Fair | Clean logic, but directly mutates Vue state. |
| `ImageLibrary.js` | Fair | Clean logic, but no image cleanup on removal. No size validation. |
| `CropManager.js` | Fair | Clean crop math, but directly mutates Vue state. |
| `UndoManager.js` | Excellent | Pure command pattern. No external dependencies. |
| `BackgroundManager.js` | Fair | Clean state management, but directly mutates Vue state. |
| `TitleManager.js` | Fair | Sophisticated run-based formatting. Edge cases in `applyFormattingToRange`. Repeated `getFullText()` allocations. |

### Interaction/

| File | Assessment | Notes |
|------|-----------|-------|
| `GestureHandler.js` | Fair | Good hit-testing structure. Coordinate transform bug. O(n) polygon testing. |
| `CropInteraction.js` | Good | Comprehensive drag + resize handling. Well-structured. |
| `FileDropHandler.js` | Fair | Functional but `drag-over` class applied to wrong element. |

### Export/

| File | Assessment | Notes |
|------|-----------|-------|
| `ExportManager.js` | Fair | Clean export flow. JPEG-only, hardcoded MIME and filename. No strategy pattern. |

### Persistence/

| File | Assessment | Notes |
|------|-----------|-------|
| `SettingsPersistence.js` | Excellent | Clean localStorage wrapper. Handles quota errors. Merges with defaults. |

### Saliency/

| File | Assessment | Notes |
|------|-----------|-------|
| `SaliencyFallback.js` | Good | Isolated image analysis logic. |

### Utils/

| File | Assessment | Notes |
|------|-----------|-------|
| `BrowserUtils.js` | Excellent | Simple browser capability checks. |
| `ComponentRegistry.js` | **Dead code** | Created but never populated or queried. |

---

## 9. Review Methodology

This review was conducted from three perspectives:

1. **Manual Analysis:** Direct code reading of all 50+ source files, tracing data flow, identifying SOLID violations, bugs, and architectural concerns.
2. **World-Review Subagent:** User experience and real-world robustness analysis focusing on memory management, performance, error handling, browser compatibility, and UX friction.
3. **SOLID-Review-G31 Subagent:** Automated SOLID principles evaluation and architectural quality assessment.

Findings were cross-referenced across all three perspectives to eliminate duplicates and validate severity ratings. Recommendations are prioritized by impact on future development velocity and code stability.
