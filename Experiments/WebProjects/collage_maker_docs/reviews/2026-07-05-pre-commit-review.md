# Pre-Commit Code Review: Handler Decomposition + Feature Additions

**Date:** 2026-07-05
**Reviewers:** SOLID analysis (manual) + World Review (subagent)
**Scope:** Staged files for upcoming commit — handler decomposition, export strategy, saliency modules, keyboard shortcuts, responsive utilities, PWA utilities, and associated tests.

---

## 1. Executive Summary

This commit represents a **significant architectural improvement** over the prior codebase. The decomposition of the 768-line `createCollageMethods.js` god module into 9 focused handler modules is a clear win for SRP and maintainability. The export strategy pattern, keyboard handler with pure functions, and saliency/debug-overlay modules are all well-structured.

However, there are **two critical bugs** that must be addressed before committing, and several medium-priority concerns that should be tracked.

**Verdict: Request Changes** — Fix the two critical issues below before committing.

---

## 2. SOLID Principles Assessment

### 2.1 Single Responsibility Principle — IMPROVED

**Before:** `createCollageMethods.js` handled file I/O, layout changes, crop operations, background editing, title editing, overlay management, export, settings persistence, and sidebar toggling — all in one module.

**After (474 lines):** The file now composes 9 focused handler modules:
- `createFileHandlers.js` (60 lines) — file picker + drag-drop
- `createImagePanelHandlers.js` (74 lines) — image selection/removal
- `createLayoutHandlers.js` (49 lines) — layout style, gutter, angle, spacing
- `createCropHandlers.js` (75 lines) — panel selection, crop reset, adjust, zoom
- `createBackgroundHandlers.js` (136 lines) — background style, colors, gradients, opacity, image
- `createTitleHandlers.js` (168 lines) — title text, formatting, font properties
- `createOverlayHandlers.js` (74 lines) — overlay image, mode, opacity
- `createExportHandlers.js` (63 lines) — export trigger, quality
- `createSettingsHandlers.js` (78 lines) — save/load settings

**Assessment: PASS.** Each module has a single, well-defined responsibility. The composition pattern in `createCollageMethods.js` is clean and follows the factory decomposition pattern established in the project.

**Nit:** `createCollageMethods.js` still retains "legacy methods" (`_regenerateAndRender`, `_scheduleRender`, `_buildBackgroundState`, `_buildOverlayState`, `_scheduleCropPreviewRender`, `_updateUndoState`, `_performUndo`, `_performRedo`) — these are cross-cutting concerns that don't cleanly belong to any single handler. They are acceptable for now as orchestration logic, but should be monitored for growth.

### 2.2 Open/Closed Principle — IMPROVED

**Export Strategy Pattern:** `ExportManager.js` now uses a registry-based strategy pattern:
```javascript
const EXPORT_FORMATS = { jpeg: exportToJpeg, png: exportToPng };
ExportManager.registerFormat(formatName, exporterFn);
```
Adding a new format (WebP, SVG) requires only creating a new file and registering it — zero modifications to existing code. **PASS.**

**Layout Generator:** The prior review identified a `switch` dispatch in `LayoutGenerator.js`. This remains **UNRESOLVED** — still an OCP violation. Adding a new layout style still requires modifying `LayoutGenerator.js`. This is a known carryover concern.

### 2.3 Liskov Substitution Principle — N/A

The project uses factory functions and plain objects rather than class hierarchies, so LSP is not directly applicable. The strategy pattern in `ExportManager` satisfies the spirit of LSP — any registered exporter conforming to `{ assembler, state, quality?, exportSize? } => Promise` can substitute for any other.

### 2.4 Interface Segregation Principle — IMPROVED

Handler modules receive only the dependencies they need via getter functions:
- `createFileHandlers(getImageLibrary, onRegenerate)` — 2 deps
- `createLayoutHandlers(getLayoutManager, getCanvasRenderer)` — 2 deps
- `createOverlayHandlers(getCanvasRenderer)` — 1 dep
- `createSettingsHandlers()` — 0 deps

**Assessment: PASS.** Each handler depends on the minimal set of services it requires.

**Concern:** `createCollageLifecycle.js` still passes the full Vue `this` instance to state managers (`createLayoutManager(this, base.assembler)`, `createCropManager(this, onCropChanged)`, etc.). This violates ISP — managers receive the entire Vue instance when they need only specific state slices. This is a **known carryover concern** from the prior review.

### 2.5 Dependency Inversion Principle — PARTIAL

**Good:** Handler modules depend on getter functions (abstractions) rather than concrete instances. The `createCollageMethods(base)` factory accepts a `base` object and calls getters to retrieve services.

**Concern:** State managers still depend directly on the Vue reactive state object. `ImageLibrary.js` receives `state` and mutates `state.images.push(...)`, `state.images.splice(...)`. This is a DIP violation — business logic depends on a concrete framework type.

**Positive:** `State/actions.js` is a new module that provides pure state mutation functions. These are decoupled from Vue and could be the foundation for the DIP transition. However, they are not yet wired into the state managers.

---

## 3. Critical Issues (Must Fix Before Commit)

### 3.1 CRITICAL: PNG Export Signature Mismatch

**Files:** `Export/formats/pngExporter.js` line 6, `Export/ExportManager.js` lines 34-40

**Problem:** `ExportManager.export()` passes `quality` as the 3rd argument to all exporters:
```javascript
return exporter(assembler, state, quality);
```

But `exportToPng` has the signature:
```javascript
export function exportToPng(assembler, state, exportSize = { width: 1920, height: 1080 })
```

When exporting as PNG, `quality` (0.92) is received as `exportSize`, so `exportSize.width` and `exportSize.height` are `undefined`. The canvas is created with default dimensions (300x150) instead of 1920x1080.

**Fix:** Align the PNG signature with JPEG:
```javascript
export function exportToPng(assembler, state, _quality = 1.0, exportSize = { width: 1920, height: 1080 })
```

### 3.2 CRITICAL: Duplicate `_loadImageFromFile` Utility

**Files:** `App/createCollageMethods.js` lines 243-255, `App/createBackgroundHandlers.js` lines 122-134, `App/createOverlayHandlers.js` lines 59-71

**Problem:** The same `FileReader` → `Image` loading pattern is duplicated in three locations. This violates DRY and creates a maintenance burden.

**Fix:** Extract to a shared utility in `Utils/` (e.g., `loadImageFromFile(file)`) and import it where needed. Alternatively, place it in `createCollageMethods.js` and pass it as a dependency to the handlers that need it.

---

## 4. High-Priority Issues

### 4.1 Memory Leak: SaliencyAnalyzer Worker Not Disposed

**File:** `App/createCollageLifecycle.js` `beforeUnmount()` (lines 174-197)

**Problem:** If `createSaliencyAnalyzer()` is ever instantiated, its Web Worker and TF.js models will not be disposed on component unmount. The `beforeUnmount` hook cleans up gesture handlers, crop interaction, canvas renderer, and image library, but has no reference to a saliency analyzer.

**Fix:** When saliency is wired up, add `if (this._saliencyAnalyzer) this._saliencyAnalyzer.dispose();` to `beforeUnmount()`.

### 4.2 Memory Leak: Canvas GPU Memory Not Released

**File:** `Rendering/CanvasRenderer.js` lines 142-146

**Problem:** `dispose()` sets closure variables to `null` but doesn't clear the canvas buffer. In Safari/WebKit, GPU-backed canvas memory may not be released.

**Fix:**
```javascript
dispose() {
    this.cancelPending();
    if (canvas) {
        canvas.width = 0;
        canvas.height = 0;
    }
    canvas = null;
    ctx = null;
}
```

### 4.3 Crop Preview Render Not Debounced

**File:** `App/createCollageMethods.js` lines 347-432 (`_scheduleCropPreviewRender`)

**Problem:** Unlike the main canvas render (which uses `requestAnimationFrame` debouncing), crop preview renders execute synchronously on every call. During rapid drag adjustments, this causes excessive `getBoundingClientRect()`, canvas re-sizing, and drawing operations.

**Fix:** Add a simple RAF-based debounce:
```javascript
let cropPreviewPending = false;
_scheduleCropPreviewRender() {
    if (cropPreviewPending) return;
    cropPreviewPending = true;
    requestAnimationFrame(() => {
        cropPreviewPending = false;
        // ... existing render logic ...
    });
}
```

### 4.4 Dead Code: `actions.js` Not Wired In

**File:** `State/actions.js`

**Problem:** The module exports pure state mutation functions (`addImagesAction`, `removeImageAction`, `disposeImageAction`, `clearImagesAction`, `regenerateLayoutAction`, `setCropAction`, `resetCropAction`) but none of them are imported or used by any state manager. They appear to be scaffolding for a future decoupling effort.

**Recommendation:** Either wire them in or remove them. Shipping dead code creates confusion and maintenance burden. If this is intentional scaffolding, add a comment explaining the plan.

### 4.5 Dead Code: `removeImage()` in ImageLibrary

**File:** `State/ImageLibrary.js` lines 61-65

**Problem:** The `removeImage()` method is marked `@deprecated` and `disposeImage()` is the preferred method. But `removeImage()` is still exported and callable. If nothing calls it, remove it. If something still calls it, either update the callers or keep it with a proper deprecation warning in the console.

---

## 5. Medium-Priority Issues

### 5.1 Barrel Export Inconsistency

**File:** `MyESModules/index.js` line 46

```javascript
export { exportToJpeg } from './Export/ExportManager.js';
```

`ExportManager.js` doesn't export `exportToJpeg` — that function lives in `Export/formats/jpegExporter.js`. This import will either fail at runtime or be incorrect. The barrel should either re-export `ExportManager` or import from the correct path.

### 5.2 `setupGlobalDrop` Event Listeners Never Removed

**File:** `App/createFileHandlers.js` lines 42-58

The `setupGlobalDrop()` method adds `dragover` and `drop` listeners to `document` but there is no corresponding cleanup. These listeners are set up in `createCollageLifecycle.js` line 139 but never removed in `beforeUnmount()`.

**Fix:** Return cleanup functions from `setupGlobalDrop()` and call them in `beforeUnmount()`, or attach the listeners on the lifecycle object so they can be removed.

### 5.3 State Object Allocation in RAF Callback

**File:** `App/createCollageMethods.js` lines 285-310

`_buildBackgroundState()` and `_buildOverlayState()` create new object literals on every render callback. While renders are debounced, this still creates GC pressure during rapid state changes.

**Fix:** Consider reusing a single state object and mutating it in place, or memoize the state builders.

### 5.4 Awkward `getCropManager` Guard

**File:** `App/createCollageMethods.js` line 41

```javascript
() => base.getCropManager ? base.getCropManager() : null,
```

The ternary guard suggests this was added during refactoring when `getCropManager` didn't exist yet. Since `CollageBase.js` defines `getCropManager()` as a method, this guard is unnecessary dead code.

**Fix:** Simplify to `() => base.getCropManager()`.

### 5.5 `ComponentRegistry.js` Deleted, `CollageState.js` Deleted

**Files:** `Utils/ComponentRegistry.js` (deleted), `State/CollageState.js` (deleted)

**Assessment: GOOD.** The prior review flagged both as dead code. Removing them is correct. Verify that nothing still references `ComponentRegistry` (grep for `ComponentRegistry` and `createCollageState` to confirm).

---

## 6. World Review Findings (UX, Memory, Performance)

### 6.1 User Experience

| Severity | Issue | Location |
|----------|-------|----------|
| High | No visual feedback for drag-and-drop — `dragover` prevents default but shows no drop zone indicator | `App/createFileHandlers.js` lines 42-57 |
| Medium | PNG export infrastructure exists but no UI option to select format | `index.html` export button |
| Low | Title formatting touch targets may be too small on mobile (< 44px) | `index.html` format buttons |

### 6.2 Memory Leaks

| Severity | Issue | Location |
|----------|-------|----------|
| High | SaliencyAnalyzer Web Worker not disposed in `beforeUnmount()` | `App/createCollageLifecycle.js` lines 174-197 |
| Medium | `CanvasRenderer.dispose()` doesn't clear canvas buffer for GPU release | `Rendering/CanvasRenderer.js` lines 142-146 |
| Medium | `setupGlobalDrop` listeners never cleaned up | `App/createFileHandlers.js` lines 42-58 |

### 6.3 Performance

| Severity | Issue | Location |
|----------|-------|----------|
| Medium | `_scheduleCropPreviewRender()` not debounced — fires synchronously on every drag event | `App/createCollageMethods.js` lines 347-432 |
| Low | State objects allocated in RAF callback create GC pressure | `App/createCollageMethods.js` lines 285-310 |

### 6.4 Integration

| Severity | Issue | Location |
|----------|-------|----------|
| Critical | PNG exporter signature mismatch with ExportManager | `Export/formats/pngExporter.js` line 6 |
| Low | `_loadImageFromFile` duplicated in 3 handler files | `createCollageMethods.js`, `createBackgroundHandlers.js`, `createOverlayHandlers.js` |
| Low | `actions.js` pure functions not wired into any manager | `State/actions.js` |

---

## 7. Positive Observations

1. **Handler decomposition is well-executed.** The 9 handler modules are small, focused, and follow consistent patterns. The composition in `createCollageMethods.js` is clean.

2. **KeyboardHandler is excellent.** Pure functions (`parseKeyShortcut`, `matchesShortcut`) are fully testable without DOM. The `SHORTCUT_SAFE_INPUT_TYPES` whitelist is a nice touch. The attach/detach lifecycle is idempotent.

3. **SaliencyAnalyzer separates pure math from DOM-dependent code.** The 270 lines of pure functions (lines 1-271) are completely testable without TF.js or browser APIs. The worker factory (lines 296-449) is cleanly isolated.

4. **SaliencyDebugOverlay follows the same pattern.** Pure coordinate functions (`focusPointToCanvasCoords`, `computeDebugMarkers`, `validateFocusPoint`) are exported for testing. The canvas rendering is a thin layer on top.

5. **Export strategy pattern is well-designed.** The registry-based approach in `ExportManager` is extensible. The JPEG and PNG exporters are nearly identical, making future format additions straightforward.

6. **ResponsiveUtils and PWACacheUtils are clean.** All pure functions, well-documented, and immediately testable.

7. **Memory management improvements.** `ImageLibrary.disposeImage()` and `clearAll()` now properly dispose image references. `createImagePanelHandlers.removeImage()` uses `disposeImage` instead of raw `splice`.

8. **Dead code removal.** Deleting `CollageState.js` and `ComponentRegistry.js` addresses items #7 from the prior review.

---

## 8. Recommendations Summary

### Block Commit (Fix Now)

| # | Issue | Principle | Files |
|---|-------|-----------|-------|
| 1 | **Fix PNG exporter signature** — add `_quality` parameter to match JPEG | Bug | `Export/formats/pngExporter.js` |
| 2 | **Deduplicate `_loadImageFromFile`** — extract to shared utility | DRY | `App/createBackgroundHandlers.js`, `App/createOverlayHandlers.js`, `App/createCollageMethods.js` |

### Address Soon (Next Session)

| # | Issue | Principle | Files |
|---|-------|-----------|-------|
| 3 | **Dispose SaliencyAnalyzer in `beforeUnmount()`** | Memory | `App/createCollageLifecycle.js` |
| 4 | **Clear canvas buffer in `CanvasRenderer.dispose()`** | Memory | `Rendering/CanvasRenderer.js` |
| 5 | **Debounce `_scheduleCropPreviewRender()`** | Performance | `App/createCollageMethods.js` |
| 6 | **Clean up `setupGlobalDrop` listeners** | Memory | `App/createFileHandlers.js` |
| 7 | **Fix barrel export for `exportToJpeg`** | Bug | `MyESModules/index.js` |
| 8 | **Remove or wire in `actions.js`** | DRY | `State/actions.js` |
| 9 | **Remove deprecated `removeImage()` from ImageLibrary** | DRY | `State/ImageLibrary.js` |
| 10 | **Simplify `getCropManager` guard** | Clean code | `App/createCollageMethods.js` |

### Carryover from Prior Review (Unchanged)

| # | Issue | Principle | Files |
|---|-------|-----------|-------|
| — | **Layout switch dispatch** — still uses `switch` | OCP | `Layout/LayoutGenerator.js` |
| — | **State managers accept full Vue instance** | ISP, DIP | `State/*.js` |
| — | **Hit-test coordinate transform bug** | Bug | `Interaction/GestureHandler.js` |
| — | **Crop preview DPR mismatch** | Bug | `App/createCollageMethods.js` |
| — | **Missing image size validation** | Robustness | `State/ImageLibrary.js` |

---

## 9. Review Methodology

This review was conducted by:
1. Reading all staged source files (18 new files, 20 modified files)
2. Evaluating SOLID principles against each module
3. Running a world-review subagent for UX, memory leak, and performance analysis
4. Cross-referencing findings against the [Post-Phase 3 State Review](./2026-07-04-post-phase3-state-review.md) to track resolution of prior concerns
5. Prioritizing findings by severity and impact on the commit
