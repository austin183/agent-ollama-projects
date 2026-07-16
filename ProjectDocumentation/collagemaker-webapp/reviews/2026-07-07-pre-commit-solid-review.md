# Pre-Commit Code Review — 2026-07-07

**Reviewer:** build-docs agent (SOLID analysis) + world-review subagent (UX/memory/performance)
**Scope:** 79 staged files, ~14K additions, ~1.2K deletions
**Branch/Context:** Major refactoring phase — handler decomposition, new modules (KeyboardHandler, SaliencyAnalyzer, SaliencyDebugOverlay, ResponsiveUtils, PWACacheUtils, actions.js, export strategy pattern)

---

## Executive Summary

The codebase demonstrates **strong architectural decomposition** with well-applied SOLID principles across the majority of new modules. The handler factory pattern, strategy pattern for exports, and pure-function-first approach in saliency/responsive/PWA utilities are all well-executed. There are **no blocking SOLID violations**, though several areas warrant follow-up refactoring.

**Overall Assessment: APPROVE with notes** — no critical issues requiring changes before commit.

---

## 1. SOLID Principles Analysis

### Single Responsibility Principle (SRP)

**Strengths:**
- Each handler module (`createFileHandlers`, `createCropHandlers`, `createLayoutHandlers`, etc.) has one clear domain responsibility
- `ExportManager.js` (43 lines) handles only format registration and dispatch — clean single concern
- `KeyboardHandler.js` separates pure functions (`parseKeyShortcut`, `matchesShortcut`) from DOM-dependent factory (`createKeyboardHandler`)
- `SaliencyAnalyzer.js` cleanly separates pure math (lines 50-271) from Web Worker lifecycle (lines 296-449)
- State managers each own one domain: `ImageLibrary`, `LayoutManager`, `CropManager`, `BackgroundManager`, `TitleManager`
- `ResponsiveUtils.js` and `PWACacheUtils.js` are pure utility modules with zero side effects

**Concerns:**

| Priority | File | Lines | Issue |
|----------|------|-------|-------|
| Low | `createCollageMethods.js` | 258-480 | "Legacy methods" section still contains `_scheduleRender` (37 lines), `_scheduleCropPreviewRender` (92 lines of inline canvas rendering), `_buildBackgroundState`, `_buildOverlayState`, undo/redo methods. Should be extracted into `createRenderMethods.js`, `createCropPreviewRenderer.js`, and `createUndoMethods.js`. |
| Low | `TitleManager.js` | 1-367 | Handles both text-run manipulation AND style setters. Related enough to be acceptable, but at 367 lines consider splitting style setters into `TitleStyleManager`. |

### Open/Closed Principle (OCP)

**Strengths:**
- `ExportManager.registerFormat()` enables adding new export formats without modifying the manager
- `KEYBOARD_SHORTCUTS` constant in `KeyboardHandler.js` is data-driven — adding shortcuts requires only a new entry, no code changes
- `actions.js` provides extension points for the planned DIP transition

**No concerns.**

### Liskov Substitution Principle (LSP)

Not strongly applicable — the codebase uses factory functions and plain objects rather than class inheritance. No LSP violations observed.

### Interface Segregation Principle (ISP)

**Strengths:**
- Factory functions return focused interfaces (e.g., `ImageLibrary` only exposes image operations, `CropManager` only exposes crop operations)
- Handler modules receive only the getter functions they need (e.g., `createLayoutHandlers` receives only `getLayoutManager` and `getCanvasRenderer`)
- `KeyboardHandler` accepts a `callbacks` object where missing callbacks are silently ignored — clients aren't forced to implement unused callbacks

**Concerns:**

| Priority | File | Lines | Issue |
|----------|------|-------|-------|
| Low | State managers | All | Managers depend on the full Vue reactive state object rather than a minimal interface. The `actions.js` TODO acknowledges this: "scaffolding for the DIP transition where state managers will depend on pure action functions instead of directly mutating Vue reactive state." Acceptable as interim design. |

### Dependency Inversion Principle (DIP)

**Strengths:**
- Handler modules depend on getter functions (abstractions) rather than concrete manager instances
- `ExportManager` depends on the `assembler` abstraction, not a concrete renderer
- `actions.js` is scaffolding for future DIP where managers depend on pure action functions
- Callback pattern (`onImagesChanged`, `onCropChanged`, etc.) provides inversion points

**Concerns:**

| Priority | File | Lines | Issue |
|----------|------|-------|-------|
| Low | `createCollageLifecycle.js` | 28, 96 | Hardcoded canvas IDs `'previewCanvas'` and `'cropPreviewCanvas'`. Consider passing IDs as configuration for testability. |
| Low | `createFileHandlers.js` | 21 | Hardcoded `'fileInput'` element ID. Same recommendation. |
| Low | `createFileHandlers.js` | 36 | `handleFileInputChange` calls `this._regenerateAndRender()` (Vue instance method) while the factory also receives an unused `onRegenerate` callback. Inconsistent — pick one pattern. |

---

## 2. User Experience Analysis

### Keyboard Shortcuts (`KeyboardHandler.js`, lines 21-33)

| Shortcut | Concern | Severity |
|----------|---------|----------|
| `meta+s` (Export) | Conflicts with browser native "Save Page" on macOS. `preventDefault()` suppresses browser dialog, which may confuse users expecting browser save behavior. | Medium |
| `meta+1` through `meta+5` (Layouts) | Conflicts with macOS Safari tab switching (Cmd+1-9). Users on Safari may experience unexpected tab switching. | Medium |
| `meta+o` (Open) | Standard convention, no conflicts. | None |
| `Escape` (Deselect) | Standard convention, no conflicts. | None |
| `Delete`/`Backspace` (Remove) | Standard convention, no conflicts. | None |
| `meta+z` / `shift+meta+z` (Undo/Redo) | Standard convention, no conflicts. | None |

**Recommendation:** Consider `meta+shift+s` or `meta+e` for export. For layout shortcuts, document the Safari conflict or consider an alternative like `alt+[1-5]`.

### Crop Preview (`createCollageMethods.js`, lines 349-440)

The `_scheduleCropPreviewRender()` method uses `requestAnimationFrame` debouncing with ~92 lines of inline canvas rendering. UX is acceptable — RAF prevents excessive synchronous operations during drag. However, this is a maintenance concern (see SRP section above).

### Saliency Debug Overlay (`SaliencyDebugOverlay.js`)

High-contrast debug colors (green focal, red center, yellow crop) at 85% opacity. Appropriate for debug use. Currently gated behind `showDebugOverlay` flag in `CollageAssembler.js` line 76. **No production leak risk** — the flag is not set anywhere in the current codebase.

---

## 3. Memory Leak Analysis

### Event Listener Lifecycle

| Handler | Attachment | Detachment | Status |
|---------|-----------|------------|--------|
| `KeyboardHandler` | `_attached` flag + `_listener` ref (line 239-243) | `detach()` removes listener (lines 248-256) | ✅ Correct |
| `GestureHandler` | `handlerAttached` flag | `detach()` removes pointer events | ✅ Correct |
| `FileDropHandler` / `createFileHandlers` | `activeCleanup` closure | Cleanup function returned and called in `beforeUnmount` | ✅ Correct |
| `CropInteraction` | Canvas event listeners | `detach()` in `beforeUnmount` line 186 | ✅ Correct |
| Window resize | `window.addEventListener('resize')` line 171 | `window.removeEventListener('resize')` line 190 | ✅ Correct |

### Image/Cleanup Lifecycle (`createCollageLifecycle.js`, `beforeUnmount`)

Lines 174-210 properly handle:
1. Drop cleanup, keyboard handler, gesture handler, crop interaction detachment
2. Window resize listener removal
3. Canvas renderer disposal
4. Image library `clearAll()` → calls `disposeImageItem` for each image
5. Saliency analyzer disposal
6. Background and overlay images set to null

### Web Worker Lifecycle (`SaliencyAnalyzer.js`)

The `dispose()` method (lines 430-442) correctly:
- Posts DISPOSE message to worker
- Calls `worker.terminate()` with try/catch
- Nulls worker reference
- Clears pending queue and state

**⚠️ One issue:** `INFERENCE_TIMEOUT_MS: 15000` constant (line 25) is defined but **not implemented**. If TF.js models fail to load or the worker hangs, the app could be stuck in `state === 'loading'` indefinitely.

**Recommendation:** Add a timeout guard in `initModels()`:
```javascript
let modelInitTimeout = setTimeout(() => {
    if (state === 'loading') {
        state = 'failed';
        if (cb.onModelsFailed) cb.onModelsFailed('Model initialization timeout');
    }
}, SALIENCY_CONFIG.INFERENCE_TIMEOUT_MS);
```

### Export Blob URL Cleanup

Both `jpegExporter.js` (lines 48-59) and `pngExporter.js` (lines 52-63) correctly use try/finally to ensure `URL.revokeObjectURL(url)` is called. ✅

---

## 4. Compute Bottleneck Analysis

### Rendering Pipeline

- **On-demand rendering** via `CanvasRenderer.scheduleRender()` (lines 73-93) with RAF debouncing is sound — rapid state changes produce at most one render per frame
- **No continuous render loop** — CPU/battery efficient
- Export renders at fixed 1920x1080 — bounded and predictable

### Layout Generation

- `LayoutManager.regenerate()` calls `LayoutGenerator.generate()` which processes panels linearly — O(n) in number of images
- No nested loops creating O(n²) behavior

### Title Processing

- `TitleManager.applyFormattingToRange()` (lines 54-111) iterates runs once — O(r) where r = number of runs
- `mergeAdjacentRuns()` (lines 28-45) also O(r)
- For typical titles (< 100 characters), this is negligible

### Saliency Analysis

- Images downscaled to `MAX_INFERENCE_DIMENSION: 512` before inference — bounded
- Web Worker offloads TF.js from main thread — correct approach
- `pendingQueue` drains when models are ready — no request loss
- **Missing:** timeout for model initialization (see Memory section)

---

## 5. Specific Code Concerns

### `actions.js` — Outdated Documentation

The JSDoc comment (lines 5-9) states:
> "@todo WIREFUTURE: These functions are scaffolding... Not yet wired into any manager."

**This is outdated.** `actions.js` IS being used:
- `CropManager.js` imports `setCropAction`, `resetCropAction` (lines 8, 46, 117)
- `LayoutManager.js` imports `regenerateLayoutAction` (lines 8, 53)

**Recommendation:** Update the comment to reflect current usage.

### Export Strategy Pattern — Justified

`jpegExporter.js` and `pngExporter.js` share ~80% structural similarity, but the strategy pattern in `ExportManager.js` is worth it:
- JPEG has a `quality` parameter PNG doesn't use
- Different MIME types and blob generation
- Future formats (WebP, AVIF) would have different parameters
- `ExportManager.registerFormat()` provides clean extension point

No refactoring needed.

### `createCollageMethods.js` — Still 482 Lines

Despite handler decomposition, the "Legacy Methods" section (lines 258-480) contains:
- `_scheduleRender()` — 37 lines of render orchestration
- `_buildBackgroundState()` — 10 lines
- `_buildOverlayState()` — 9 lines
- `_scheduleCropPreviewRender()` — 92 lines of inline canvas rendering
- `_updateUndoState()`, `_performUndo()`, `_performRedo()` — 20 lines

**Recommendation (post-commit):** Extract into dedicated modules:
1. `createRenderMethods.js` — render scheduling and state builders
2. `createCropPreviewRenderer.js` — crop preview canvas rendering
3. `createUndoMethods.js` — undo/redo state management

### Duplicate `_scheduleRender()` Calls

Every handler module calls `this._scheduleRender()` after state mutations. This is a pervasive implicit dependency on a Vue instance method. It works but creates a coupling between handler modules and the Vue methods layer. The `onRegenerate` callback pattern in `createFileHandlers` suggests an alternative that isn't consistently applied.

---

## 6. Test Coverage

**New test files staged (20 files):**
- `KeyboardHandlerTest.html` (728 lines) — comprehensive shortcut testing
- `SaliencyTest.html` (869 lines) — pure function testing
- `SaliencyDebugOverlayTest.html` (1421 lines) — thorough coordinate and rendering tests
- `ResponsiveUtilsTest.html` (513 lines) — breakpoint and config testing
- `ResponsiveCSSValidationTest.html` (330 lines)
- `ResponsivePointerEventsTest.html` (469 lines)
- `PWACacheUtilsTest.html` (565 lines) — cache routing and manifest validation
- `PWAManifestTest.html` (280 lines)
- `FileDropHandlerTest.html` (230 lines)
- `ImageLibraryMemoryTest.html` (148 lines) — memory disposal testing
- `LandingPageTest.html` (176 lines)
- `LayoutGeneratorTest.html` (161 lines)
- `RenderingTest.html` (188 lines)
- `TitleRendererTest.html` (449 lines)
- `BackgroundRendererTest.html` (518 lines)
- `CropPreviewTest.html` (328 lines)
- `Phase4CodeQualityTest.html` (258 lines)
- `EdgeCasesTest.html` (updated)
- `LayoutMathTest.html` (updated)
- `ExportManagerTest.html` (updated)

**E2E tests (4 new files):**
- `keyboard-shortcuts.spec.js` (269 lines)
- `landing-page.spec.js` (144 lines)
- `pwa-capabilities.spec.js` (574 lines)
- `responsive-design.spec.js` (441 lines)

**Assessment:** Test coverage is excellent. New modules have corresponding unit tests, and E2E tests cover the major user flows. The pure-function-first approach in `KeyboardHandler`, `SaliencyAnalyzer`, `ResponsiveUtils`, and `PWACacheUtils` enables thorough unit testing without browser dependencies.

---

## 7. Summary of Recommendations

| Priority | Issue | File | Recommendation |
|----------|-------|------|----------------|
| 🔴 Medium | Export shortcut conflicts with browser save | `KeyboardHandler.js:22` | Change `EXPORT: 'meta+s'` to `'meta+shift+s'` or `'meta+e'` |
| 🟡 Medium | Layout shortcuts conflict with Safari tabs | `KeyboardHandler.js:24-28` | Document conflict or use `alt+[1-5]` |
| 🟡 Medium | Saliency timeout constant unused | `SaliencyAnalyzer.js:25` | Implement actual timeout in `initModels()` |
| 🟢 Low | Outdated WIREFUTURE comment | `actions.js:5-9` | Update to reflect actions are wired into CropManager and LayoutManager |
| 🟢 Low | Legacy methods in createCollageMethods | `createCollageMethods.js:258-480` | Extract render/crop-preview/undo methods into dedicated modules (post-commit) |
| 🟢 Low | Inconsistent handler callback usage | `createFileHandlers.js:36` | Align on using either Vue methods or `onRegenerate` callback |
| 🟢 Low | Hardcoded DOM IDs | `createCollageLifecycle.js:28,96`, `createFileHandlers.js:21` | Pass as configuration for testability (post-commit) |

---

## 8. Approval Decision

**APPROVE** — The code demonstrates strong SOLID adherence, clean separation of concerns, and comprehensive test coverage. The issues identified are all medium or low priority, suitable for post-commit follow-up. No blocking architectural or design flaws.

### What's Done Well
- Handler factory decomposition eliminates the God Module anti-pattern
- Strategy pattern for export formats provides clean extensibility
- Pure-function-first approach in new modules (Saliency, Responsive, PWA, Keyboard) enables thorough testing
- Memory lifecycle management is thorough and correct
- On-demand rendering saves CPU/battery
- Test coverage is comprehensive across unit and E2E levels

### Follow-Up Items (post-commit)
1. Extract legacy methods from `createCollageMethods.js`
2. Implement saliency model initialization timeout
3. Evaluate keyboard shortcut conflicts
4. Update `actions.js` documentation
5. Consider consistent callback pattern for handler regeneration
