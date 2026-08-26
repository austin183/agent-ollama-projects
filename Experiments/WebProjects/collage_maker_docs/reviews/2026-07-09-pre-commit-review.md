# Pre-Commit Code Review — 2026-07-09

**Reviewer:** build-docs agent (SOLID + architectural analysis) + world-review subagent (UX analysis)
**Scope:** 42 staged files, ~4,428 additions, ~376 deletions
**Branch:** `prototype/collage-maker`
**Plan Reference:** `_agent_docs/plans/2026-07-07-change-requests-implementation-plan.md` (all 5 phases)

---

## Executive Summary

This commit implements the complete 5-phase change requests plan: keyboard shortcut corrections, saliency timeout guard, background compositing fix, export format selector, collapsible sidebar, bidirectional diagonal slices, shaped crop overlays, hexagonal enhancements (size multiplier + drag-and-drop swap), multi-touch gestures, and full Phase 5 refactoring (DOM ID injection, callback pattern, method extraction, layout options).

**Overall Assessment: APPROVE with notes** — strong architectural improvements with no blocking SOLID violations. The callback pattern refactoring (CR-14) and DOM ID injection (CR-15) significantly improve testability and DIP compliance. Several UX polish items identified for post-commit follow-up.

---

## 1. SOLID Principles Analysis

### Single Responsibility Principle (SRP)

**Strengths:**
- `createCollageMethods.js` is now cleanly structured: closure functions for core methods (lines 38-232), handler composition (lines 237-276), and delegation wrappers (lines 280-557). The God Module is substantially tamed.
- `HexPanelSwap.js` (218 lines) cleanly separates `swapPanelAssignments()` pure function from `createHexDragHandler()` factory
- `MultiTouchHandler.js` (246 lines) exports pure math functions (`computeTouchMidpoint`, `computeTouchDistance`, `computePinchScale`) alongside the factory — testable without DOM
- `CropOverlayShape.js` (87 lines) is a pure math module with zero side effects
- Each handler module (`createLayoutHandlers.js`, `createCropHandlers.js`, etc.) owns exactly one domain

**Concerns:**

| Priority | File | Lines | Issue |
|----------|------|-------|-------|
| Low | `createCollageMethods.js` | 38-232 | Core methods (`_scheduleRender`, `_scheduleCropPreviewRender`, undo/redo) are still defined as closures inside the factory. Per the Phase 5 plan, these should eventually be extracted into `createRenderMethods.js`, `createCropPreviewRenderer.js`, and `createUndoMethods.js`. Acceptable as interim state. |
| Low | `createCollageLifecycle.js` | 34-226 | The `mounted()` hook is 192 lines and initializes 8+ subsystems. Consider extracting into `createSubsystemInit(base, ids)` for readability. Not blocking. |

### Open/Closed Principle (OCP)

**Strengths:**
- `LayoutGenerator.getLayoutOptions()` (lines 83-92) enables dynamic UI option visibility without hardcoded conditions — new layouts only need a new entry in the options map
- `LayoutGenerator.registerLayoutStyle()` still works for custom layout registration
- `ExportManager` strategy pattern from prior phases remains intact

**No concerns.**

### Liskov Substitution Principle (LSP)

Not applicable — factory function architecture avoids class inheritance.

### Interface Segregation Principle (ISP)

**Strengths:**
- Handler factories accept minimal parameter sets: `createOverlayHandlers(onRenderScheduled)` takes only what it needs
- `createFileHandlers(getImageLibrary, onRegenerate, fileInputId)` — three focused parameters
- `createHexDragHandler()` accepts a focused options object with only required callbacks

**No concerns.**

### Dependency Inversion Principle (DIP)

**Strengths (Major Improvement):**
- **CR-14 is the highlight:** All 6 handler modules now use injected callbacks (`onRenderScheduled`, `onCropPreviewRender`, `onRegenerate`) instead of `this._scheduleRender()`. This eliminates the implicit dependency on Vue instance methods.
- **CR-15:** DOM IDs are injected via configuration objects with sensible defaults. `createCollageLifecycle(base, domIds)` and `createFileHandlers(..., fileInputId)` no longer hardcode element IDs.
- Handler modules are now fully testable without a Vue instance — callbacks can be mocked.

**Concerns:**

| Priority | File | Lines | Issue |
|----------|------|-------|-------|
| Low | `createCollageLifecycle.js` | 89-103 | `createGestureHandler` still receives `state: this` (full Vue reactive state). The `actions.js` scaffolding exists for future migration to pure state + action functions. Acceptable interim design. |
| Low | `createCollageLifecycle.js` | 106-131 | `createHexDragHandler` also receives `state: this`. Same pattern, consistent with existing architecture. |

---

## 2. Architectural Quality

### Event Handler Binding Pattern (New Consistent Pattern)

**Files:** `CropInteraction.js`, `GestureHandler.js`, `HexPanelSwap.js`, `MultiTouchHandler.js`

All four interaction handlers now use the same late-binding pattern:
```javascript
let onPointerDown, onPointerMove, onPointerUp;
const handler = { /* ... */ };
onPointerDown = (e) => handler._onPointerDown(e);
return handler;
```

**Assessment:** Excellent. This pattern was needed because `removeEventListener` requires the exact same function reference. The old pattern of inline arrow functions `(e) => this._onPointerDown(e)` created new function references on each call, making cleanup impossible. This is a **correct and necessary** pattern for proper memory management.

### Callback Pattern Wiring

The callback wiring in `createCollageMethods.js` is well-structured:

```javascript
const layoutHandlers = createLayoutHandlers(
    () => base.getLayoutManager(),
    (vm) => _scheduleRender(vm)
);
```

Each callback receives the Vue instance (`vm`) as a parameter, enabling the handler to access reactive state when needed. The delegation wrappers then call handlers with `.call(this)`:

```javascript
onLayoutStyleChange() {
    layoutHandlers.onLayoutStyleChange.call(this);
}
```

**Assessment:** Sound. The `.call(this)` pattern preserves Vue template bindings while the injected callbacks provide DIP compliance.

### Method Extraction Status

The diff shows that methods like `_scheduleRender`, `_buildBackgroundState`, etc. are now defined as closure functions that accept `vm` as a parameter, then wrapped as Vue methods that pass `this`:

```javascript
function _scheduleRender(vm) { /* ... */ }
// ...
_scheduleRender() { _scheduleRender(this); }
```

**Assessment:** This is a good intermediate state. The closure functions are pure in the sense that they don't capture `this`, making them testable. The Vue method wrappers maintain template compatibility. Full extraction into separate modules (per Phase 5 plan) can happen incrementally.

---

## 3. Code Quality

### New Modules

| Module | Lines | Quality | Notes |
|--------|-------|---------|-------|
| `MultiTouchHandler.js` | 246 | Excellent | Pure math exports, proper cleanup, threshold guards |
| `HexPanelSwap.js` | 218 | Excellent | Pure swap function, proper hit detection, undo integration |
| `CropOverlayShape.js` | 87 | Excellent | Pure math, defensive null handling, aspect ratio preservation |

### Bug Fixes

| CR | Fix | Quality |
|----|-----|---------|
| CR-03 | Background image compositing with color behind | Correct — `ctx.save()/restore()` isolates alpha, background fills first |
| CR-10 | Keyboard shortcut conflicts | Correct — `meta+e` and `alt+[1-5]` avoid all known browser conflicts |
| CR-11 | Saliency timeout guard | Correct — timeout cleared on success/failure/dispose, state transitions properly |

### `createExportHandlers.js` Format Validation

```javascript
const format = (this.exportFormat === 'png' ? 'png' : 'jpeg');
```

**Assessment:** Good defensive coding. Only 'png' and 'jpeg' are supported, and anything else defaults to 'jpeg'.

---

## 4. Test Coverage

### New Test Files (7 files, ~2,100 lines)

| Test File | Coverage | Quality |
|-----------|----------|---------|
| `MultiTouchHandlerTest.html` | 726 lines, 15+ tests | Excellent — pure math + factory + gesture lifecycle + edge cases |
| `Phase5RefactoringTest.html` | 497 lines, 20+ tests | Excellent — DOM ID injection, callback pattern, layout options, method composition |
| `CropOverlayShapeTest.html` | 154 lines, 8 tests | Good — null handling, aspect ratio, centering, zero-size |
| `HexPanelSwapTest.html` | 130 lines, 6 tests | Good — swap correctness, same-ID guard, not-found guard, undo-friendliness |
| `SidebarSectionsTest.html` | 134 lines, 8 tests | Good — toggle, auto-expand, deselect behavior |

### Updated Test Files (5 files)

| Test File | Changes |
|-----------|---------|
| `KeyboardHandlerTest.html` | All `meta+s` → `meta+e`, `meta+[1-5]` → `alt+[1-5]`, new CR-10 tests |
| `LayoutMathTest.html` | Negative angle tests, hex size multiplier tests, LayoutGenerator passthrough |
| `BackgroundRendererTest.html` | 7 new tests for image compositing (Section 1.5) |
| `SaliencyTest.html` | Timeout guard tests |
| `test/e2e/keyboard-shortcuts.spec.js` | Updated shortcut keys |

**Assessment:** Test coverage is comprehensive. Every new module has corresponding unit tests. The pure-function-first approach in `MultiTouchHandler`, `CropOverlayShape`, and `HexPanelSwap` enables thorough testing without browser dependencies. New tests follow the existing Mocha/Chai HTML test file pattern.

---

## 5. User Experience Analysis (world-review findings)

### Critical Priority

#### 5.1 Saliency Model Failure UX (CR-11)

The timeout guard correctly transitions to `state === 'failed'` and fires `onModelsFailed`. However, the **UI-facing consequence** depends on how the Vue app handles this callback. If the callback merely sets a flag without user-visible feedback, the user may not understand why saliency-based cropping isn't working.

**Recommendation:** Verify that `onModelsFailed` in the Vue app displays a non-blocking notification (toast or subtle banner) and that the app gracefully falls back to center-crop. Not blocking — the fallback path (`center-fallback`) is already implemented in the code.

#### 5.2 Hexagonal Drag-and-Drop Visual Feedback (CR-04c)

The `HexPanelSwap.js` handler correctly detects drag start, tracks movement threshold, and performs swap on pointer up. However, there is **no visual feedback** during the drag operation — no target highlighting, no cursor change, no drag indicator. On mobile with imprecise touch, users may not know which hexagon they're targeting.

**Recommendation (post-commit):** Add hover-state feedback during hex drags. The `GestureHandler` already has hover infrastructure (`onHoverChanged` callback) — the hex drag handler could emit a "hovering target" event during `_onPointerMove` when over a valid hex cell.

#### 5.3 Multi-Touch Event Conflicts (CR-06)

The `MultiTouchHandler.js` uses `{ passive: false }` and calls `e.preventDefault()` on two-finger gestures. This is correct for preventing browser scroll/zoom hijacking. The handler correctly ignores 1-finger and 3+ finger events.

**Assessment:** Correctly implemented. The `passive: false` option is used only where `preventDefault` is needed.

### Important Priority

#### 5.4 Keyboard Shortcut Discoverability (CR-10)

The new shortcuts (`meta+e` for export, `alt+[1-5]` for layouts) are functionally correct but **undiscoverable** without tooltips or documentation. Users won't know about `alt+[1-5]` unless they see it somewhere in the UI.

**Recommendation (post-commit):** Add tooltip text to layout buttons (e.g., "Uniform [Alt+1]") and export button ("Export [Cmd+E]"). Consider a keyboard shortcuts help modal.

#### 5.5 Collapsible Sidebar Accessibility (CR-08)

The `expandedSections` state and `toggleSection()` method are correct. For accessibility, the sidebar section headers should have `aria-expanded` and `aria-controls` attributes.

**Recommendation (post-commit):** Add ARIA attributes to section headers in `index.html`.

#### 5.6 Background Compositing + PNG Export (CR-03 + CR-07)

The `renderImage()` function in `BackgroundRenderer.js` pre-fills the canvas with a solid/gradient color before drawing the image. For JPEG exports this is correct. For PNG exports with transparent backgrounds, this pre-fill could destroy transparency.

**Assessment:** Low risk — the current UI always has a background color configured. If users later want transparent PNG exports, this would need adjustment. Not blocking for current functionality.

### Nice-to-Have

#### 5.7 Export Progress Feedback

The `exportCollage()` method in `createExportHandlers.js` sets `isExporting` and `exportStatus` state. Ensure the UI reflects these with a loading indicator during export.

#### 5.8 Hex Size Multiplier Labeling

If exposed in the UI, `hexSizeMultiplier` should have an intuitive label like "Hexagon Size" with a tooltip.

---

## 6. Memory and Performance

### Memory Management

| Resource | Management | Status |
|----------|-----------|--------|
| Event listeners | Late-binding pattern + `detach()` in `beforeUnmount` | ✅ All handlers |
| Web Worker | `dispose()` clears timeout + terminates worker | ✅ CR-11 |
| Canvas renderer | `dispose()` in `beforeUnmount` | ✅ |
| Image library | `clearAll()` disposes all images | ✅ |
| Touch handlers | `detach()` removes listeners, resets state | ✅ CR-06 |

### Performance

- **Shaped crop overlays (CR-04a):** `computeShapeOverlayPoints()` is O(n) in polygon vertices (typically 4-6). Called once per crop preview render, not per frame. Acceptable.
- **Multi-touch (CR-06):** Pinch scale uses `Math.pow(ratio, 0.15)` for smooth incremental zoom. Render calls are consolidated — single `onCropPreviewRender()` per touchmove. Good.
- **Hex drag-and-drop (CR-04c):** Hit test iterates panels top-to-bottom. O(n) in panel count. Acceptable for typical collage sizes (< 50 panels).

**No performance concerns.**

---

## 7. Skills and Documentation

### New Skills

- `.opencode/skills/writing-plans/SKILL.md` (213 lines) — comprehensive plan authoring guide
- `.opencode/skills/writing-plans/references/create-plan.md` (162 lines) — plan template
- `.opencode/skills/writing-plans/references/iterate-plan.md` (174 lines) — iteration guide

### Updated References

- `building-web-apps/references/accessibility.md` (54 lines) — new
- `building-web-apps/references/canvas-2d.md` — updated
- `building-web-apps/references/interaction.md` (146 lines) — new
- `building-web-apps/references/memory-management.md` — updated
- `building-web-apps/references/testing.md` (115 lines) — new
- `building-web-apps/references/web-workers.md` (163 lines) — new

**Assessment:** Documentation is thorough and follows project conventions. The new `interaction.md` and `web-workers.md` references capture the patterns used in the new modules.

---

## 8. Summary of Recommendations

| Priority | Issue | File | Recommendation |
|----------|-------|------|----------------|
| 🟡 Medium | Saliency failure UX visibility | `createCollageLifecycle.js` / Vue app | Ensure `onModelsFailed` shows user-visible notification |
| 🟡 Medium | Hex swap lacks visual feedback | `HexPanelSwap.js` | Add target highlighting during drag (post-commit) |
| 🟡 Medium | Keyboard shortcuts undiscoverable | `index.html` UI | Add tooltips showing shortcut keys (post-commit) |
| 🟢 Low | Sidebar ARIA attributes | `index.html` | Add `aria-expanded`/`aria-controls` to section headers |
| 🟢 Low | PNG transparency + bg fill | `BackgroundRenderer.js` | Document current behavior; adjust if transparent PNG exports are added |
| 🟢 Low | Full method extraction | `createCollageMethods.js` | Extract render/crop-preview/undo into separate modules (per Phase 5 plan) |
| 🟢 Low | Export progress UI | `index.html` / `createExportHandlers.js` | Ensure `isExporting`/`exportStatus` drive loading indicator |

---

## 9. Approval Decision

**APPROVE** — This is a high-quality, comprehensive implementation of the 5-phase change requests plan. The code demonstrates:

### What's Done Well
- **DIP compliance:** The callback pattern (CR-14) eliminates implicit Vue method dependencies across all handler modules
- **Testability:** DOM ID injection (CR-15) and pure-function-first design in new modules enable thorough unit testing
- **Memory safety:** The late-binding event handler pattern ensures proper cleanup across all interaction modules
- **Bug fixes:** Keyboard shortcut conflicts (CR-10), background compositing (CR-03), and saliency timeout (CR-11) are all correctly implemented
- **Test coverage:** 7 new test files (~2,100 lines) plus 5 updated test files provide comprehensive coverage of all new functionality
- **Documentation:** New skills and references capture the patterns and decisions for future development

### Follow-Up Items (post-commit)
1. Add visual feedback for hex panel drag-and-drop (target highlighting)
2. Add keyboard shortcut tooltips to UI buttons
3. Add ARIA attributes to collapsible sidebar sections
4. Verify saliency failure UX shows user notification
5. Complete method extraction from `createCollageMethods.js` into dedicated modules
6. Consider export progress loading indicator

No blocking issues identified. The staged changes are ready for commit.
