# Pre-Merge Review — Final Consolidated — 2026-07-19

**Reviewer:** build-docs agent (Barbara) with 12 parallel subagents
**Scope:** 195 files, 49,244 insertions, 14 commits
**Branch:** `prototype/collage-maker`
**Plan Reference:** `_agent_docs/plans/2026-07-19-pre-merge-review-plan.md`
**Prior reviews:** 8 existing review documents in `_agent_docs/reviews/`

---

## Executive Summary

This is the eighth and final consolidated review for PR #12 (prototype/collage-maker → main). The review was executed across 7 phases with 12 parallel subagents covering all 8 architectural domains, UX, test coverage, HTML/CSS, and infrastructure.

**VERDICT: REQUEST CHANGES** — one critical blocking issue was discovered that renders the undo/redo system completely non-functional.

---

## Phase 0: Automated Test Results

| Suite | Files | Tests | Pass | Fail |
|-------|-------|-------|------|------|
| Unit tests | 36 HTML files | 1,399 | 1,399 | 0 |
| E2E tests | 7 Playwright specs | — | — | — |

**Result:** All 1,399 unit tests pass with zero failures. Console errors observed are from deliberate error-handling tests (simulated export failures, keyboard shortcut error propagation, invalid JSON parsing).

**Note:** E2E tests were not executed during this review (dev server not available). The `pwa-capabilities.spec.js` (32 tests) is entirely deferred — PWA features are not yet implemented.

---

## Critical Blocking Issue

### CR-1: Undo/Redo Completely Broken — `base.undoManager` Never Registered

**Severity: CRITICAL — BLOCKS MERGE**

**Files:** `CollageBase.js`, `createUndoMethods.js`, `createCollageLifecycle.js`

**Root cause:** `createUndoMethods.js` accesses `base.undoManager` (lines 23, 24, 25, 45, 47, 60, 62) but `CollageBase.js` has no `undoManager` getter/setter. The undo manager is created in `createCollageLifecycle.js:54` and stored only on the Vue instance as `this.undoManager`.

**Impact:** Every undo/redo operation silently does nothing:
- Keyboard shortcuts (Cmd+Z / Cmd+Shift+Z) — no effect
- Panel swap undo — no effect
- Crop drag undo — no effect
- Title move undo — no effect
- `vm.canUndo` / `vm.canRedo` — never updated (always stale)

**Why it was missed:** The test suite validates the provider-function callback pattern in `createUndoMethods.js` in isolation (6 tests in `UndoManagerTest.html`), but never tests the end-to-end flow from keyboard shortcut through `_performUndo` to actual state restoration. The guard `if (!base.undoManager || !base.undoManager.canUndo()) return;` always returns early.

**Fix required:**
1. Add `getUndoManager()`/`setUndoManager()` to `CollageBase.js` (matching the pattern of other managers at lines 33-73)
2. In `createCollageLifecycle.js:54`, add `base.setUndoManager(this.undoManager);` after creating the undo manager
3. In `createUndoMethods.js`, replace `base.undoManager` with `base.getUndoManager()` (or `base?.getUndoManager?.()` for safety)

---

## Prior Issues Verification (12 issues from 3 prior reviews)

| # | Source | Issue | Severity | Status |
|---|--------|-------|----------|--------|
| 1 | 07-12 | `_onWheel` unconditional `preventDefault()` | Medium | ✅ **Fixed** — two-level gate: early return when no panel selected, `hasAction` check before `preventDefault()` |
| 2 | 07-12 | Hex drag target drawn after selection border | Minor | ✅ **Fixed** — drag target moved to step 4b (before selection at step 5), same-panel guard added |
| 3 | 07-12 | HexPanelSwap / MultiTouchHandler pointer conflict | Low-Medium | ✅ **Fixed** — `PanelSwap._onPointerDown` and `TitleInteraction._onPointerDown` both guard with `_multiTouchGestureActive` |
| 4 | 07-12 | `HexagonalLayout` comment accuracy for `R_grid` | Low | ✅ **Fixed** — comment now accurately describes "proportional spacing" behavior |
| 5 | 07-12 | Incomplete pointer capture in `_onPointerDown` | Low-Medium | ✅ **Fixed** — MultiTouchHandler, PanelSwap, TitleInteraction all call `setPointerCapture` with try-catch |
| 6 | 07-12 | Missing `releasePointerCapture` | Low | ⚠️ **Partial** — MultiTouchHandler, PanelSwap, TitleInteraction fixed; **CropInteraction still missing** (new concern flagged below) |
| 7 | 07-12 | Stale undo callbacks | Low | ✅ **Fixed** — provider function pattern with `_invokeProvider` guard. **However**, CR-1 above means the entire undo system is non-functional regardless. |
| 8 | 07-15 | Missing settings persistence for title fields | Medium | ✅ **Fixed** — all 10 title fields saved in `createSettingsHandlers.js:28-39` and restored in `createCollageLifecycle.js:378-389` |
| 9 | 07-18 | Duplicate MARGIN constant in `TitleInteraction.js` | Nit | ✅ **Fixed** — `MARGIN` imported from `TitleRenderer.js` |
| 10 | 07-18 | Offscreen canvas in interaction hot path | Nit | ✅ **Fixed** — shared `measureCanvas` (1×1) created at factory init in `TitleInteraction.js:36-39` |
| 11 | 07-18 | Enter key flicker on 3-line title | Nit | ⚠️ **Not fully addressed** — textarea may briefly show 4th line before Vue clamps. UX review flagged this as a concern. |
| 12 | 07-18 | Silent truncation feedback for pasted text | Nit | ⚠️ **Not fully addressed** — `setText` returns `{ truncated: true }` but no toast is triggered in the handler. |

---

## Domain Review Findings

### Domain A: State Management

**Blocking:** CR-1 (undo/redo broken) — see above.

**Concerns:**
- `UndoManager.beginBatch()` silently drops accumulated commands on nested call (line 48-51) — latent data-loss bug
- `LayoutManager.regenerate()` empty-images path bypasses `actions.js` — inconsistent mutation pattern
- Lifecycle undo callbacks (panel swap, crop, title) inline mutations instead of using `actions.js` — dual mutation pattern

**Nits:**
- `clearImagesAction` replaces array reference (breaks Vue reactivity if ever called)
- `BackgroundManager.getState()` has redundant null check
- `TitleManager.setText()` replaces array reference (inconsistent with other methods)
- `TitleManager` at 442 lines — consider splitting content editing from style setters

### Domain B: Layout

**No blocking issues.**

**Concerns:**
- `getLayoutOptions()` in `LayoutGenerator.js` is a hardcoded lookup — violates OCP of the strategy pattern. Registering a new layout requires editing `getLayoutOptions()`.
- `CropOverlayShape.js` contains Canvas 2D rendering functions (`drawShapeOverlay`, `beginPathFromPoints`) that belong in the Rendering domain.

**Nits:**
- `DiagonalSlicesLayout` has no angle validation (±90° produces Infinity)
- `MosaicLayout` non-deterministic by default (no seed = `Math.random()`)
- `registerLayoutStyle` mutates shared module state (test isolation risk)

### Domain C: Rendering

**No blocking issues.**

**Concerns:**
- Export DPR scaling not implemented — `jpegExporter.js` and `pngExporter.js` create canvases at raw resolution without DPR multiplication
- `createDebugOverlay` factory in `SaliencyDebugOverlay.js` is dead code — assembler calls `renderDebugOverlay()` directly
- `TitleInteraction.js` creates a shared measure canvas but doesn't pass it to `computeMultiLineBounds` — still creates offscreen canvases per pointermove

**Nits:**
- `computeBounds` single-line function creates offscreen canvas on every call
- `_drawPanelBorder` dead code path (`config.inset || 0`)
- Exporters duplicate clear+fill logic (3 lines, extractable)

### Domain D: Interaction

**No blocking issues.**

**Concerns:**
- `CropInteraction` missing `releasePointerCapture` — regression of prior issue #6. All other handlers properly release capture.
- `CropInteraction.setPointerCapture` unprotected by try-catch — can throw on unsupported browsers.

**Nits:**
- Redundant `computeMultiLineBounds` calls in drag hot path (3× per pointermove)
- Unused `scale` variable in `GestureHandler.js:87`
- Duplicated point-in-polygon hit testing in `GestureHandler.js` vs `PanelSwap.js` (~20 lines each)

### Domain E: App Assembly

**Blocking (contributor to CR-1):** `createImagePanelHandlers` bypasses injected callback pattern — direct `this._scheduleRender()` calls. Sole outlier among handler modules, making it untestable in isolation.

**Concerns:**
- `base.undoManager` never set (CR-1, confirmed above)
- `createCollageServices` provides `componentRegistry` that doesn't exist — always `undefined`
- Duplicated `_applySavedSettings` logic across `createCollageLifecycle.js` and `createSettingsHandlers.js` — risk of drift

**Nits:**
- Dead `onExportQualityChange` no-op
- Missing file input reset in `handleBackgroundImageChange`
- Defensive fallbacks in overlay handlers are unreachable
- `createExportHandlers` receives concrete dependency, not getter

### Domain F: Export/Persistence

**No blocking issues.**

**Concerns:**
- Dead/incomplete `_applySavedSettings` in `createSettingsHandlers.js:60-83` — saves 10 title fields but only restores 4. If ever wired up, will silently drop 6 fields.
- Stale `theme: 'light'` default in `SettingsPersistence.js:27` — never saved or loaded.

**Nits:**
- `ExportManager` doesn't pass `exportSize` to exporters (hardcodes 1080p)
- Exporters share ~40 lines of near-identical boilerplate
- JSDoc says `@returns {Promise<string>}` but actual resolution in exporters

### Domain G: Saliency/Utils

**No blocking issues.**

**Concerns:**
- Incompatible `saliencyCrop` signatures across `SaliencyAnalyzer.js` and `SaliencyFallback.js` — same exported name, different parameters
- `validateManifest` treats recommended fields as validation errors — manifest missing only recommended fields fails validation
- Hardcoded CSS values in `getCanvasMaxDimensions` — magic numbers must stay in sync with `Style.css` manually

**Nits:**
- `worker.onerror` doesn't clear `loadingTimeoutId`
- `SaliencyFallback.js` JSDoc is outdated (mentions "MVP until Phase 4")
- `hasResponsiveClass` duplicates native `classList.contains()`
- `APP_SHELL_URLS` is manually maintained (50+ URLs)
- `loadImageFromFile` doesn't set `crossOrigin`
- `SaliencyWorker.js` is missing (falls back gracefully)

### Domain H: Models

**No blocking issues.**

**Concerns:**
- `CropInfo.js` depends on Layout layer (`FitMath.js`) — Models should be the lowest layer with zero cross-layer dependencies
- `generateThumbnail()` in `ImageItem.js` leaks Canvas 2D rendering into Models layer
- Inconsistent default-value operators (`||` vs `??`) across factories

**Nits:**
- `SIZE_CONSTANTS` uses camelCase properties despite being a constants object
- ID generation could collide under rapid creation (same millisecond)
- `createTitleRun()` coerces types but other factories don't
- Hardcoded `1920`/`1080` persists in 6+ modules instead of importing `SIZE_CONSTANTS`

---

## Latest Commit Deep Dive (39d5ae2)

### ImageLibrary.js — Progress Overlay

**No blocking issues.**

**Concerns:**
- Deprecated `removeImage()` left in production — latent memory leak vector
- `onImagesChanged` called without `typeof` guard — cryptic TypeError risk
- Two divergent progress-overlay wiring patterns (file-input vs drop) — different cleanup semantics

**Nits:**
- Progress callback fires for failed images (misleading progress bar)
- `this` passed to progress callback is unnecessary noise
- `_loadImage` FileReader has no abort mechanism (race condition with `clearAll`)

### UX — Loading Overlay, Truncation Toast, WCAG Touch, Enter Key Guard

**Concerns:**
- Loading overlay has `pointer-events: none` while visually suggesting blocking operation — UX mismatch
- Truncation toast not triggered — `setText` returns `{ truncated: true }` but handler doesn't show toast
- Enter key guard may cause cursor jump/flicker — native textarea updates before Vue clamps

### WCAG Touch Thresholds

**Concern:** Multiple interactive elements below 44x44px minimum:
- `#themeToggle`: 40×40px
- `.toolbar-icon-btn`: 32×32px
- `.format-btn`: 32×32px
- `.remove-btn`: ~20×20px

---

## Full UX World Review

### Blocking Issues
1. **Missing PWA capabilities** — No `manifest.json` or service worker. App cannot be installed. (Documented as deferred.)
2. **Touch targets below WCAG 44x44px** — `.format-btn` at 32×32px, others worse.
3. **Image load failures not reported** — No user feedback when images fail to load.
4. **Storage full not handled** — `console.warn` only, no user notification.

### Concerns
- No mobile/tablet responsive breakpoints — fixed sidebar widths won't work on small screens
- ARIA state management incomplete — format buttons missing `aria-disabled`
- Export success message only 3000ms — may be too brief
- Progress overlay `pointer-events: none` — no visual failure indicator
- Crop corner handles at 12px — below 44px touch target

---

## Test Coverage Assessment

### Coverage Summary
- **36 HTML test files**, 1,399 tests, 0 failures
- **7 Playwright E2E specs** (1 deferred: PWA)
- **All source modules** have at least one corresponding test file

### Coverage Gaps
1. `App/createApp.js` — no dedicated unit test (medium risk, covered by E2E only)
2. PWA E2E tests entirely deferred (low risk if PWA is future feature)
3. No tests for Vue reactivity/watchers (low risk)

### Test Quality: Excellent
- Edge cases thoroughly covered (null inputs, empty arrays, boundary values)
- Error handling tested (callback throws, missing callbacks, null objects)
- Determinism verified (seeded PRNG, exact pixel values, layout reproducibility)

---

## HTML/CSS Review

**No blocking issues.**

**Concerns:**
1. Touch targets below WCAG 44x44px (multiple elements, see above)
2. Missing ARIA attributes — theme toggle missing `aria-label`, sidebar toggle missing `aria-expanded`
3. No print styles
4. No responsive media queries for mobile/tablet
5. Inconsistent CSS custom properties — toast colors use hardcoded hex values

---

## Configuration & Infrastructure

### Playwright Config
- Chromium-only, single worker, 30s timeout, 1 retry on CI
- `forbidOnly` enabled on CI — good
- `trace: 'on-first-retry'` — good for debugging
- No Firefox/WebKit coverage — acceptable for initial release

### Scripts
- `run-tests.js` — automated test runner, works correctly
- `run-page-tests.cjs` — interactive test helper
- No `package.json` or `.gitignore` in CollageMaker directory (inherited from workspace root)

---

## Architecture Strengths

Despite the critical issue, the codebase demonstrates strong architectural quality:

1. **Factory-function architecture** — consistent `attach()`/`detach()` lifecycle, no classes
2. **Callback injection pattern** — DIP-compliant, enables isolated unit testing
3. **Pure-function-first design** — layout math, rendering helpers, and interaction utilities are testable without DOM
4. **Late-binding event handler pattern** — correct memory management for event listener cleanup
5. **Provider function pattern** — prevents stale callback references (issue #7 fix)
6. **Action-based mutations** — `actions.js` provides explicit state mutation functions
7. **Undo integration** — well-designed snapshot/restore pattern for panel swap, crop, and title interactions
8. **Cross-handler coordination** — `_multiTouchGestureActive` flag prevents pointer conflicts
9. **Comprehensive test suite** — 1,399 tests with excellent edge case coverage

---

## Summary of Issues

### Blocking (must fix before merge)
| # | Issue | Severity |
|---|-------|----------|
| CR-1 | Undo/redo completely broken — `base.undoManager` never registered | **CRITICAL** |

### High Priority (should fix before merge)
| # | Issue | Severity |
|---|-------|----------|
| H-1 | WCAG touch targets below 44x44px (4+ elements) | High |
| H-2 | Image load failures not reported to users | High |
| H-3 | Storage full scenario not handled | High |
| H-4 | `createImagePanelHandlers` bypasses callback pattern | High |
| H-5 | `CropInteraction` missing `releasePointerCapture` | Medium |
| H-6 | `CropInteraction.setPointerCapture` unprotected by try-catch | Medium |
| H-7 | Deprecated `removeImage()` left in production | Medium |

### Medium Priority (should fix)
| # | Issue | Severity |
|---|-------|----------|
| M-1 | `UndoManager.beginBatch()` silently drops commands on nested call | Medium |
| M-2 | `LayoutManager` empty path bypasses `actions.js` | Medium |
| M-3 | Lifecycle undo callbacks inline mutations instead of using `actions.js` | Medium |
| M-4 | Export DPR scaling not implemented | Medium |
| M-5 | Dead `createDebugOverlay` factory | Medium |
| M-6 | Dead/incomplete `_applySavedSettings` in `createSettingsHandlers.js` | Medium |
| M-7 | Incompatible `saliencyCrop` signatures | Medium |
| M-8 | `CropInfo.js` depends on Layout layer | Medium |
| M-9 | `generateThumbnail()` in Models leaks rendering concern | Medium |
| M-10 | `validateManifest` treats recommended as errors | Medium |
| M-11 | `componentRegistry` in services doesn't exist | Medium |
| M-12 | Duplicated `_applySavedSettings` across two modules | Medium |

### Nits (optional polish)
| # | Issue |
|---|-------|
| N-1 | `clearImagesAction` replaces array reference |
| N-2 | `BackgroundManager.getState()` redundant null check |
| N-3 | `TitleManager` at 442 lines — consider splitting |
| N-4 | `getLayoutOptions()` violates OCP |
| N-5 | `CropOverlayShape.js` rendering functions belong in Rendering |
| N-6 | `DiagonalSlicesLayout` no angle validation |
| N-7 | `MosaicLayout` non-deterministic by default |
| N-8 | `registerLayoutStyle` mutates shared state |
| N-9 | Exporters duplicate clear+fill logic |
| N-10 | Redundant `computeMultiLineBounds` in drag hot path |
| N-11 | Unused `scale` variable in `GestureHandler.js` |
| N-12 | Duplicated point-in-polygon hit testing |
| N-13 | Dead `onExportQualityChange` no-op |
| N-14 | Missing file input reset in background handler |
| N-15 | `ExportManager` doesn't pass `exportSize` |
| N-16 | Exporters share ~40 lines of boilerplate |
| N-17 | `worker.onerror` doesn't clear timeout |
| N-18 | `SaliencyFallback.js` JSDoc outdated |
| N-19 | `hasResponsiveClass` duplicates `classList.contains()` |
| N-20 | `APP_SHELL_URLS` manually maintained |
| N-21 | `loadImageFromFile` no `crossOrigin` |
| N-22 | `SaliencyWorker.js` missing |
| N-23 | `SIZE_CONSTANTS` camelCase properties |
| N-24 | ID generation collision risk |
| N-25 | Inconsistent default-value operators (`||` vs `??`) |
| N-26 | Hardcoded `1920`/`1080` in 6+ modules |
| N-27 | No responsive media queries |
| N-28 | Missing ARIA attributes (theme toggle, sidebar toggle) |
| N-29 | No print styles |
| N-30 | Inconsistent CSS custom properties |
| N-31 | Enter key flicker on 3-line title |
| N-32 | Silent truncation feedback |
| N-33 | Truncation toast not triggered |
| N-34 | Loading overlay `pointer-events: none` UX mismatch |

---

## Decision

**REQUEST CHANGES** — one critical blocking issue:

1. **CR-1: Wire up `base.undoManager`** — Add `getUndoManager()`/`setUndoManager()` to `CollageBase.js` and register the undo manager in `createCollageLifecycle.js`. This renders the entire undo/redo system non-functional, including Cmd+Z, Cmd+Shift+Z, panel swap undo, crop undo, and title move undo.

Once CR-1 is resolved, the high-priority issues (H-1 through H-6) should be addressed. The medium-priority issues and nits can be handled in follow-up commits.

---

## Reviewer Sign-Off

| Reviewer | Verdict | Notes |
|----------|---------|-------|
| build-docs / Barbara (consolidator) | **REQUEST CHANGES** | CR-1 blocks merge |
| solid-review (Domain A: State) | REQUEST CHANGES | CR-1 confirmed critical |
| solid-review (Domain B: Layout) | APPROVE | No blocking issues |
| solid-review (Domain C: Rendering) | APPROVE | No blocking issues |
| solid-review (Domain D: Interaction) | APPROVE | CropInteraction concerns noted |
| solid-review (Domain E: App Assembly) | REQUEST CHANGES | CR-1 + callback pattern violation |
| solid-review (Domain F: Export/Persistence) | APPROVE | Dead code concern noted |
| solid-review (Domain G: Saliency/Utils) | APPROVE | No blocking issues |
| solid-review (Domain H: Models) | APPROVE | Layering concerns noted |
| solid-review (ImageLibrary) | APPROVE | Deprecated method concern |
| world-review (Latest commit UX) | APPROVE with notes | Touch targets + truncation feedback |
| world-review (Full UX) | APPROVE with notes | PWA deferred, touch targets, error feedback |
| world-review (HTML/CSS) | APPROVE with notes | Touch targets, ARIA, responsive gaps |
| explore (Test coverage) | APPROVE | Excellent quality, minor gaps |
