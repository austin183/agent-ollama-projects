# Phase 4 Priority Decisions: Polish & Advanced Features

**Date:** 2026-07-02
**Scope:** Priority decisions for Phase 4 features to determine MVP vs deferred scope.
**References:** [Master Implementation Plan](./2026-06-30-collagemaker-web-port-implementation.md), [Midpoint Gap Analysis](./2026-07-02-MidpointGapAnalysis.md)

---

## 1. Overview

Phase 4 focuses on transitioning the CollageMaker web port from a functional prototype to a polished, production-ready tool. The primary goal is to balance high-impact UX improvements with the technical overhead of advanced features like Machine Learning and PWA capabilities.

This document defines the "Minimum Viable Product" (MVP) for the Phase 4 scope, ensuring that deployment to the public landing page occurs with a stable, performant, and accessible application without introducing unnecessary complexity or bundle bloat.

---

## 2. Priority Decision Matrix

| Feature | Priority | Rationale | Est. Effort |
| :--- | :--- | :--- | :--- |
| **Landing Page Integration** | Must-have | Essential for user discovery and public accessibility. | Trivial |
| **Keyboard Shortcuts** | Must-have | Significant productivity boost; low effort to implement. | Low |
| **ML-Based Saliency** | Nice-to-have | High complexity and bundle size; center-crop is sufficient for MVP. | High |
| **Saliency Debug Overlay** | Nice-to-have | Only useful for developers/tuning ML saliency. | Low |
| **Responsive Design** | Nice-to-have | Desktop-first is the primary target for MVP launch. | Medium |
| **PWA Capabilities** | Nice-to-have | Not required for the core value proposition of a static site. | Medium |

---

## 3. Detailed Analysis per Feature

### 3.1 Keyboard Shortcuts

- **Description**: Implementation of standard keyboard accelerators for common actions (Open, Export, Layout switching, Selection management).
- **User Impact**: High. Power users and frequent editors expect these shortcuts.
- **Effort**: Low. Requires a centralized event listener and mapping to existing state/interaction methods.
- **Dependencies**: None.
- **Risk**: Low. Potential conflict with browser defaults (though `Cmd` keys are generally safe).
- **Recommendation**: **Must-have for MVP**.
- **Implementation Outline**:
  - Create `MyESModules/Interaction/KeyboardHandler.js`
  - Register global `keydown` listeners
  - Map keys to `App` or `State` methods (e.g., `Cmd+S` → `ExportManager.exportToJpeg()`)
  - Shortcuts to implement:
    - `Cmd+O`: Open file picker (trigger image upload)
    - `Cmd+S`: Export (trigger export)
    - `Cmd+1` through `Cmd+5`: Switch layout styles (uniform, hero, mosaic, diagonalSlices, hexagonal)
    - `Escape`: Deselect panel
    - `Delete`/`Backspace`: Remove selected image
    - `Cmd+Z` / `Cmd+Shift+Z`: Undo/Redo (already implemented in Phase 2)

#### 3.1.1 Recommended Module Interface (for testability)

The `KeyboardHandler` should follow the existing interaction handler pattern (factory function with `attach`/`detach` lifecycle) and expose pure functions for unit testing without DOM dependencies:

```javascript
// Pure functions (testable without browser context)
export function parseKeyShortcut(event) { /* normalizes KeyboardEvent */ }
export function matchesShortcut(parsed, pattern) { /* matches against "meta+s", "Escape", etc. */ }

// Constants
export const KEYBOARD_SHORTCUTS = { /* mapping of shortcut name → pattern string */ };

// Full handler (DOM-dependent)
export function createKeyboardHandler({ callbacks }) {
    return { attach(), detach(), handleKeydown(e) };
}
```

Key design decisions:
- `meta+` patterns match both `metaKey` (macOS Cmd) and `ctrlKey` (Windows/Linux)
- `handleKeydown` is exposed on the returned object for integration testing
- Callbacks are injected as a plain object, enabling spy/mock usage in tests
- **Focus-aware suppression**: shortcuts do NOT fire when focus is in `<input>`, `<textarea>`, `<select>`, or `[contenteditable]` elements

#### 3.1.2 Test Scenarios

**Test file**: `MyComponents/KeyboardHandlerTest.html` (new, following established convention of one HTML file per module).

**Unit Tests — Pure Key Parsing (`parseKeyShortcut`)**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.1.2.1 | Basic key press (no modifiers) | `new KeyboardEvent('keydown', { key: 's' })` | `{ key: 's', meta: false, ctrl: false, shift: false, alt: false }` |
| 3.1.2.2 | Meta key + letter | `{ key: 's', metaKey: true }` | `{ key: 's', meta: true, ...rest false }` |
| 3.1.2.3 | Ctrl key + letter | `{ key: 's', ctrlKey: true }` | `{ key: 's', ctrl: true, ...rest false }` |
| 3.1.2.4 | Meta + Shift + letter | `{ key: 'z', metaKey: true, shiftKey: true }` | `{ key: 'z', meta: true, shift: true, ... }` |
| 3.1.2.5 | Escape key | `{ key: 'Escape' }` | `{ key: 'Escape', all modifiers false }` |
| 3.1.2.6 | Delete key | `{ key: 'Delete' }` | `{ key: 'Delete', all modifiers false }` |
| 3.1.2.7 | Backspace key | `{ key: 'Backspace' }` | `{ key: 'Backspace', all modifiers false }` |
| 3.1.2.8 | Number key | `{ key: '1' }` | `{ key: '1', all modifiers false }` |
| 3.1.2.9 | Key normalized to lowercase | `{ key: 'Z', shiftKey: true }` | `key` is `'z'` |
| 3.1.2.10 | Alt key captured | `{ key: 's', altKey: true }` | `{ key: 's', alt: true }` |

**Unit Tests — Shortcut Matching (`matchesShortcut`)**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.1.2.11 | Exact meta+letter match | parsed `{key:'s', meta:true}`, `"meta+s"` | `true` |
| 3.1.2.12 | Ctrl treated as meta equivalent | parsed `{key:'s', ctrl:true}`, `"meta+s"` | `true` |
| 3.1.2.13 | Meta+Shift match | parsed `{key:'z', meta:true, shift:true}`, `"shift+meta+z"` | `true` |
| 3.1.2.14 | Ctrl+Shift treated as meta+shift | parsed `{key:'z', ctrl:true, shift:true}`, `"shift+meta+z"` | `true` |
| 3.1.2.15 | No match: wrong key | parsed `{key:'s', meta:true}`, `"meta+z"` | `false` |
| 3.1.2.16 | No match: missing modifier | parsed `{key:'s'}`, `"meta+s"` | `false` |
| 3.1.2.17 | No match: extra modifier | parsed `{key:'s', meta:true, shift:true}`, `"meta+s"` | `false` |
| 3.1.2.18 | Escape match | parsed `{key:'Escape'}`, `"Escape"` | `true` |
| 3.1.2.19 | Delete match | parsed `{key:'Delete'}`, `"Delete"` | `true` |
| 3.1.2.20 | Backspace match | parsed `{key:'Backspace'}`, `"Backspace"` | `true` |
| 3.1.2.21 | Number key match | parsed `{key:'1', meta:true}`, `"meta+1"` | `true` |
| 3.1.2.22 | Pattern order insensitive | parsed `{key:'z', meta:true, shift:true}`, `"meta+shift+z"` | `true` |
| 3.1.2.23 | No match: Escape vs other key | parsed `{key:'s'}`, `"Escape"` | `false` |
| 3.1.2.24 | No match: Alt present but not in pattern | parsed `{key:'s', alt:true}`, `"s"` | `false` |

**Unit Tests — Shortcut Mapping Constants (`KEYBOARD_SHORTCUTS`)**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.1.2.25 | All shortcut entries present | `Object.keys(KEYBOARD_SHORTCUTS)` | Length = 11 |
| 3.1.2.26 | Layout shortcuts are numbered 1-5 | `LAYOUT_UNIFORM` through `LAYOUT_HEXAGONAL` | Patterns: `meta+1` through `meta+5` |
| 3.1.2.27 | Layout shortcut values map to LayoutStyle | Each layout shortcut value | Matches corresponding `LayoutStyle.*` value |
| 3.1.2.28 | Undo/Redo patterns match existing behavior | `UNDO: meta+z`, `REDO: shift+meta+z` | Matches current `_handleKeyboard` logic in `createCollageLifecycle.js` |

**Unit Tests — Handler Lifecycle (attach/detach)**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.1.2.29 | Handler created with callbacks | `createKeyboardHandler({ callbacks: { ... } })` | Returns object with `attach`, `detach`, `handleKeydown` |
| 3.1.2.30 | attach() adds listener to document | Call `handler.attach()` | `document` has keydown listener registered |
| 3.1.2.31 | detach() removes listener | Call `attach()` then `detach()` | `document` no longer has keydown listener |
| 3.1.2.32 | Double attach is a no-op | Call `attach()` twice | Only one listener registered (no duplicate fires) |
| 3.1.2.33 | Double detach is a no-op | Call `detach()` twice | No error thrown |
| 3.1.2.34 | Detach without attach is safe | Call `detach()` without `attach()` | No error thrown |
| 3.1.2.35 | Handler dispatches on keydown | `attach()`, dispatch `keydown` on document | Callback invoked |
| 3.1.2.36 | Handler does not fire on keyup | `attach()`, dispatch `keyup` on document | Callback NOT invoked |

**Unit Tests — Shortcut → Callback Dispatch (Integration)**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.1.2.37 | Cmd+O triggers onOpenFilePicker | `{ key: 'o', metaKey: true }` | `onOpenFilePicker` called once |
| 3.1.2.38 | Ctrl+O triggers onOpenFilePicker | `{ key: 'o', ctrlKey: true }` | `onOpenFilePicker` called once |
| 3.1.2.39 | Cmd+S triggers onExport | `{ key: 's', metaKey: true }` | `onExport` called once |
| 3.1.2.40 | Ctrl+S triggers onExport | `{ key: 's', ctrlKey: true }` | `onExport` called once |
| 3.1.2.41 | Cmd+1 → uniform layout | `{ key: '1', metaKey: true }` | `onLayoutSwitch` called with `'uniform'` |
| 3.1.2.42 | Cmd+2 → hero layout | `{ key: '2', metaKey: true }` | `onLayoutSwitch` called with `'hero'` |
| 3.1.2.43 | Cmd+3 → mosaic layout | `{ key: '3', metaKey: true }` | `onLayoutSwitch` called with `'mosaic'` |
| 3.1.2.44 | Cmd+4 → diagonalSlices | `{ key: '4', metaKey: true }` | `onLayoutSwitch` called with `'diagonalSlices'` |
| 3.1.2.45 | Cmd+5 → hexagonal | `{ key: '5', metaKey: true }` | `onLayoutSwitch` called with `'hexagonal'` |
| 3.1.2.46 | Escape triggers onDeselect | `{ key: 'Escape' }` | `onDeselect` called once |
| 3.1.2.47 | Delete triggers onRemoveSelected | `{ key: 'Delete' }` | `onRemoveSelected` called once |
| 3.1.2.48 | Backspace triggers onRemoveSelected | `{ key: 'Backspace' }` | `onRemoveSelected` called once |
| 3.1.2.49 | Cmd+Z triggers onUndo | `{ key: 'z', metaKey: true }` | `onUndo` called once |
| 3.1.2.50 | Cmd+Shift+Z triggers onRedo | `{ key: 'Z', metaKey: true, shiftKey: true }` | `onRedo` called once |
| 3.1.2.51 | Ctrl+Shift+Z triggers onRedo | `{ key: 'Z', ctrlKey: true, shiftKey: true }` | `onRedo` called once |
| 3.1.2.52 | Unrecognized key does not trigger callback | `{ key: 'x', metaKey: true }` | No callback called |
| 3.1.2.53 | Plain 's' (no modifier) does not trigger export | `{ key: 's' }` | `onExport` NOT called |
| 3.1.2.54 | preventDefault called for recognized shortcuts | `{ key: 's', metaKey: true }` | `event.preventDefault()` called |
| 3.1.2.55 | preventDefault NOT called for unrecognized | `{ key: 'x' }` | `event.preventDefault()` NOT called |

**Unit Tests — Focus-Aware Suppression**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.1.2.56 | Shortcut suppressed in `<input>` | `keydown` on `<input>` element | No callback fired |
| 3.1.2.57 | Shortcut suppressed in `<textarea>` | `keydown` on `<textarea>` | No callback fired |
| 3.1.2.58 | Shortcut suppressed in `<select>` | `keydown` on `<select>` | No callback fired |
| 3.1.2.59 | Shortcut suppressed in `[contenteditable]` | `keydown` on contenteditable div | No callback fired |
| 3.1.2.60 | Shortcut fires on `<body>` target | `keydown` with `target === document.body` | Callback fires normally |
| 3.1.2.61 | Shortcut fires on `<canvas>` target | `keydown` with `target === canvas` | Callback fires normally |
| 3.1.2.62 | Shortcut fires on custom `<div>` | `keydown` on non-editable `<div>` | Callback fires normally |

**Unit Tests — Edge Cases**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.1.2.63 | Missing callback is safe | `createKeyboardHandler({ callbacks: {} })` + Cmd+O | No error thrown |
| 3.1.2.64 | Null callbacks object | `createKeyboardHandler({ callbacks: null })` | No error thrown |
| 3.1.2.65 | Callback that throws does not crash handler | `onExport` throws, Cmd+S pressed | Error propagates, handler still functional for next event |
| 3.1.2.66 | Rapid key presses do not corrupt state | 20 rapid Cmd+1 events | `onLayoutSwitch` called exactly 20 times |
| 3.1.2.67 | Key event with unusual key value | `{ key: 'Undefined' }` | No error thrown |
| 3.1.2.68 | Shift+Delete behaves like Delete | `{ key: 'Delete', shiftKey: true }` | `onRemoveSelected` called (same as plain Delete) |
| 3.1.2.69 | Cmd+Shift+Z with lowercase 'z' | `{ key: 'z', metaKey: true, shiftKey: true }` | `onRedo` called (case-insensitive key check) |

#### 3.1.3 E2E Test Scenarios (Playwright)

**Test file**: `test/e2e/keyboard-shortcuts.spec.js` (new).

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.1.3.1 | Cmd+O opens file picker | Load app, press `Meta+O` | File chooser event fires (`page.waitForEvent('filechooser')`) |
| 3.1.3.2 | Cmd+S triggers export | Load app with images, press `Meta+S` | Export download event fires |
| 3.1.3.3 | Cmd+1 switches to uniform | Load app with images, press `Meta+1` | `#layoutStyleSelect` value = `'uniform'` |
| 3.1.3.4 | Cmd+2 switches to hero | Load app with images, press `Meta+2` | `#layoutStyleSelect` value = `'hero'` |
| 3.1.3.5 | Cmd+3 switches to mosaic | Load app with images, press `Meta+3` | `#layoutStyleSelect` value = `'mosaic'` |
| 3.1.3.6 | Cmd+4 switches to diagonalSlices | Load app with images, press `Meta+4` | `#layoutStyleSelect` value = `'diagonalSlices'` |
| 3.1.3.7 | Cmd+5 switches to hexagonal | Load app with images, press `Meta+5` | `#layoutStyleSelect` value = `'hexagonal'` |
| 3.1.3.8 | Escape deselects panel | Load app, select panel on canvas, press `Escape` | No selection indicator visible |
| 3.1.3.9 | Delete removes selected image | Load app with 2 images, select panel, press `Delete` | Image count decreases to 1 |
| 3.1.3.10 | Cmd+Z undo after crop reset | Load app, reset crop, press `Meta+Z` | Crop returns to pre-reset state |
| 3.1.3.11 | Cmd+Shift+Z redo after undo | Load app, reset crop, undo, press `Meta+Shift+Z` | Crop returns to reset state |
| 3.1.3.12 | Shortcuts suppressed in text input | Focus title input, press `Meta+S` | Export NOT triggered |
| 3.1.3.13 | Cmd+S with no images — no crash | Fresh app (no images), press `Meta+S` | No console errors, no crash |
| 3.1.3.14 | Delete with no panel selected — no crash | No panel selected, press `Delete` | No console errors, no crash |
| 3.1.3.15 | Rapid layout switching — no hang | Press `Meta+1` through `Meta+5` rapidly 3x | Canvas renders final layout, no crash |

#### 3.1.4 Integration with Existing Keyboard Handler

The existing `_handleKeyboard` method in `createCollageLifecycle.js` (lines 204-226) handles Undo/Redo/Escape inline. The new `KeyboardHandler` module should **replace** this method entirely (not coexist) to maintain a single source of truth for shortcut handling.

**Migration approach**:
1. In `mounted()`: Replace inline listener setup with `createKeyboardHandler({ callbacks: { ... } })`
2. In `beforeUnmount()`: Replace `removeEventListener` with `handler.detach()`
3. Remove `_handleKeyboard` method from `methods` block
4. Add `createKeyboardHandler` import and barrel export in `MyESModules/index.js`

#### 3.1.5 Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | 3.1.2.11-3.1.2.24 (Matching), 3.1.2.37-3.1.1.2.55 (Dispatch), 3.1.3.1-3.1.3.11 (E2E core) | Core functionality — if these fail, the feature doesn't work |
| **P1** | 3.1.2.1-3.1.1.2.10 (Parsing), 3.1.2.25-3.1.2.36 (Constants/Lifecycle), 3.1.2.56-3.1.2.62 (Focus suppression) | Structural correctness and UX safety |
| **P2** | 3.1.2.63-3.1.2.69 (Edge cases), 3.1.3.12-3.1.3.15 (E2E edge cases) | Robustness and polish |

#### 3.1.6 Known Behaviors to Document

1. **Browser default conflicts**: `Cmd+O` and `Cmd+S` will call `preventDefault()` to suppress the browser's native "Open File" and "Save Page" dialogs. This is intentional — the app's own file picker and export should take precedence.
2. **No shortcut when typing**: Keyboard shortcuts are suppressed when focus is in any editable element (`<input>`, `<textarea>`, `<select>`, `[contenteditable]`). This prevents accidental triggers while the user is typing in the title input or search field.
3. **No visual shortcut feedback**: The MVP does not include toast notifications or visual confirmation when a shortcut is triggered. The UI state change (e.g., layout dropdown updating) serves as implicit feedback. Shortcut tooltips on toolbar buttons (e.g., "Export [Cmd+S]") may be added in a future polish pass.
4. **International keyboard layouts**: The handler uses `e.key` (not `e.keyCode`) for key detection. Number keys (`1`–`5`) map to the logical character value, so `Cmd+1` works regardless of physical key position on AZERTY/QWERTZ layouts.

### 3.2 Landing Page Integration

- **Description**: Adding a project card to the root `index.html` to link to the CollageMaker application.
- **User Impact**: High. This is the only way for users to find the app via the main portfolio.
- **Effort**: Trivial. Adding a few lines of HTML following the existing `project-card` pattern.
- **Dependencies**: None.
- **Risk**: Trivial.
- **Recommendation**: **Must-have for MVP**.
- **Implementation Outline**:
  - Modify root `index.html` (at `~/workspace/austin183.github.io/index.html`)
  - Add `project-card` entry in "Tools & Educational" section
  - Card should include: icon, title ("CollageMaker"), description, and "Launch" button linking to `CollageMaker/index.html`
  - Card `id` must be `collageMakerCard` for test targeting
  - Follow existing card pattern: `card-icon` → `material-icons` span, `card-title`, `card-description`, `launch-button` (anchor tag)
  - Use relative path `CollageMaker/index.html` (consistent with existing cards like `TaxBracketVisualizer/index.html`)
  - Do NOT use `target="_blank"` (consistent with existing internal project cards)

#### 3.2.1 Unit Tests — DOM Structure Validation

**Test file**: `CollageMaker/MyComponents/LandingPageTest.html` (new).

Since the landing page is static HTML (no application logic), "unit tests" here validate the DOM structure by fetching the landing page HTML via `fetch()`, parsing it with `DOMParser`, and asserting element presence, attributes, and text content. Follows the existing `MyComponents/*Test.html` convention.

| # | Test | Selector | Expected |
|---|------|----------|----------|
| 3.2.1.1 | Card element exists | `#collageMakerCard` | Element exists in parsed DOM |
| 3.2.1.2 | Card has `project-card` class | `#collageMakerCard` | `classList.contains('project-card')` is `true` |
| 3.2.1.3 | Card has a visual variant class | `#collageMakerCard` | Has one of: `card-primary`, `card-secondary`, `card-accent`, `card-neutral` |
| 3.2.1.4 | Card icon container exists | `#collageMakerCard .card-icon` | Element exists |
| 3.2.1.5 | Card icon uses Material Icons | `#collageMakerCard .card-icon .material-icons` | Element exists, `textContent.trim()` is non-empty |
| 3.2.1.6 | Card title element exists | `#collageMakerCard .card-title` | Element is `<h2>` |
| 3.2.1.7 | Card title text is "CollageMaker" | `#collageMakerCard .card-title` | `textContent.trim() === "CollageMaker"` |
| 3.2.1.8 | Card description element exists | `#collageMakerCard .card-description` | Element is `<p>` |
| 3.2.1.9 | Card description is non-empty | `#collageMakerCard .card-description` | `textContent.trim().length > 0` |
| 3.2.1.10 | Card description mentions collage | `#collageMakerCard .card-description` | Text contains "collage" (case-insensitive) |
| 3.2.1.11 | Launch button is an anchor tag | `#collageMakerCard .launch-button` | Element is `<a>` tag |
| 3.2.1.12 | Launch button text is "Launch" | `#collageMakerCard .launch-button` | `textContent.trim() === "Launch"` |
| 3.2.1.13 | Launch href is correct relative path | `#collageMakerCard .launch-button` | `getAttribute('href') === "CollageMaker/index.html"` |
| 3.2.1.14 | Launch does not open new tab | `#collageMakerCard .launch-button` | Does NOT have `target="_blank"` attribute |
| 3.2.1.15 | Card is within a category section | `#collageMakerCard.closest('.category-section')` | Element exists |
| 3.2.1.16 | Card is within a category grid | `#collageMakerCard.closest('.category-grid')` | Element exists |
| 3.2.1.17 | Card structure matches existing cards | Compare children of `#collageMakerCard` with `#taxCard` | Same child element classes: `.card-icon`, `.card-title`, `.card-description`, `.launch-button` |
| 3.2.1.18 | No duplicate card IDs on page | `document.querySelectorAll('[id="collageMakerCard"]')` | Exactly 1 element |

#### 3.2.2 E2E Test Scenarios (Playwright)

**Test file**: `CollageMaker/test/e2e/landing-page.spec.js` (new).

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.2.2.1 | Landing page loads without errors | Navigate to `/` | No console errors, page renders |
| 3.2.2.2 | CollageMaker card is visible | Navigate to `/` | `#collageMakerCard` is visible (`offsetParent !== null`) |
| 3.2.2.3 | Card title displays "CollageMaker" | Navigate to `/` | `.card-title` within card contains "CollageMaker" |
| 3.2.2.4 | Launch button is clickable | Navigate to `/`, click `.launch-button` within `#collageMakerCard` | Navigation occurs |
| 3.2.2.5 | Launch navigates to CollageMaker app | Click Launch button | URL changes to include `/CollageMaker/index.html` |
| 3.2.2.6 | CollageMaker app loads after navigation | Click Launch, `waitForSelector('#app')` | Vue app mounted, `#app` visible |
| 3.2.2.7 | CollageMaker canvas visible after navigation | Click Launch, `waitForSelector('#previewCanvas')` | Canvas element present (may show empty state) |
| 3.2.2.8 | Back button returns to landing page | Click Launch, then `page.goBack()` | URL returns to `/` |
| 3.2.2.9 | Card visible in dark theme | Navigate to `/`, click `.theme-toggle`, check card | `#collageMakerCard` still visible |
| 3.2.2.10 | Direct URL access works | Navigate directly to `/CollageMaker/index.html` | App loads without 404 for CSS/JS modules |
| 3.2.2.11 | Rapid Launch clicks — no crash | Click Launch 5 times rapidly | Navigates once, no duplicate navigations or errors |

#### 3.2.3 Manual Verification Checklist

These items require human judgment and are not suitable for automation.

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.2.3.1 | Icon visual appropriateness | Visual inspection of card icon | Icon clearly represents "collage" or "photo collage" concept |
| 3.2.3.2 | Description accuracy | Read description aloud | Text is clear, concise, and accurately describes what CollageMaker does |
| 3.2.3.3 | Card visual consistency | Compare with other cards in section | Card matches overall aesthetic (colors, spacing, typography, shadow) |
| 3.2.3.4 | Card placement logic | Review category organization | Card is in the most logical category section (e.g., "Tools & Educational" or a new "Creative Tools" section) |
| 3.2.3.5 | Mobile appearance | Open on mobile device or 375px viewport | Card displays correctly, Launch button is tappable (min 44x44px touch target) |
| 3.2.3.6 | Dark theme legibility | Toggle to dark mode | Card text and icon are legible, contrast meets WCAG AA (4.5:1 for normal text) |

#### 3.2.4 Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | 3.2.1.1–3.2.1.16 (DOM structure), 3.2.2.1–3.2.2.7 (E2E core navigation) | Core functionality — if these fail, the feature doesn't work |
| **P1** | 3.2.1.17–3.2.1.18 (consistency), 3.2.2.8–3.2.2.11 (E2E edge cases) | Quality and consistency with existing cards |
| **P2** | 3.2.3.1–3.2.3.6 (Manual checklist) | Visual polish and accessibility |

#### 3.2.5 Known Behaviors to Document

1. **Link path strategy**: Uses relative path `CollageMaker/index.html` (consistent with existing internal cards like `TaxBracketVisualizer/index.html`). This works correctly when served from the repository root on GitHub Pages.
2. **Same-tab navigation**: The Launch button does NOT use `target="_blank"` (consistent with all existing internal project cards). Users navigate away from the portfolio page and can return via browser Back button.
3. **No external dependencies**: The card HTML is self-contained and does not require any additional CSS or JavaScript beyond what the landing page already loads.

### 3.3 ML-Based Saliency

- **Description**: Using TensorFlow.js models to detect faces and objects to optimize automatic cropping.
- **User Impact**: Medium/High. Improves the "magic" feel of auto-cropping.
- **Effort**: High. Requires lazy-loading large models, Web Worker implementation to prevent UI freeze, and async state management.
- **Dependencies**: `@tensorflow-models/face-detection` (~3MB), `@tensorflow-models/coco-ssd` (~6MB).
- **Risk**: Medium. Increases initial load time/bundle size by ~9MB; potential for performance degradation on low-end devices.
- **Recommendation**: **Nice-to-have (Deferred)**. The existing center-crop heuristic provides 80% of the value for 1% of the effort.
- **Implementation Outline** (for future reference):
  - Create `MyESModules/Saliency/SaliencyAnalyzer.js`
  - Implement worker-based inference loop
  - Integrate with `Layout` generation logic
  - Tiered approach: face detection → object detection → center fallback

#### 3.3.1 Recommended Module Interface (for testability)

The `SaliencyAnalyzer` should follow existing project conventions: pure functions for core math, factory functions with lifecycle methods, and explicit constants. All pure functions must be testable without browser context or TF.js dependencies.

```javascript
// MyESModules/Saliency/SaliencyAnalyzer.js

// Constants
export const SALIENCY_CONFIG = {
    MAX_INFERENCE_DIMENSION: 512,          // Downscale images above this for inference
    MIN_INFERENCE_DIMENSION: 32,           // Below this, skip inference (too small for TF.js)
    FACE_CONFIDENCE_THRESHOLD: 0.5,        // Minimum confidence for face detections
    OBJECT_CONFIDENCE_THRESHOLD: 0.3,      // Minimum confidence for object detections
    MIN_DETECTION_PIXEL_SIZE: 20,          // Ignore detections smaller than 20px (in original image)
    MODEL_PRIORITY: ['face-detection', 'coco-ssd', 'center-fallback'],
    INFERENCE_TIMEOUT_MS: 15000,           // Max time per inference before fallback
    WORKER_URL: './MyESModules/Saliency/SaliencyWorker.js',
};

// Pure functions (testable without browser/TF.js)
export function computeFocusPoint(detections, imageSize, config) { /* ... */ }
export function filterDetections(detections, imageSize, minConfidence, minPixelSize) { /* ... */ }
export function computeBboxCentroid(bboxes, imageSize) { /* ... */ }
export function saliencyCrop(centerCrop, focusPoint, imageSize) { /* ... */ }
export function computeInferenceSize(imageSize, maxDim) { /* ... */ }
export function scaleDetectionUp(bbox, scale) { /* ... */ }

// Worker message protocol
export const WORKER_MSG = {
    INIT_MODELS: 'saliency:init_models',
    ANALYZE_IMAGE: 'saliency:analyze_image',
    DISPOSE: 'saliency:dispose',
    MODELS_READY: 'saliency:models_ready',
    MODELS_FAILED: 'saliency:models_failed',
    ANALYSIS_COMPLETE: 'saliency:analysis_complete',
    ANALYSIS_ERROR: 'saliency:analysis_error',
    DISPOSED: 'saliency:disposed',
};

// Full analyzer factory
export function createSaliencyAnalyzer({ onModelsReady, onModelsFailed, onAnalysisComplete, onAnalysisError }) {
    return { initModels(), analyzeImage(image, imageSize), cancel(), dispose(), getState() };
}
```

Key design decisions:
- **Pure functions first**: `computeFocusPoint`, `saliencyCrop`, `filterDetections`, `computeBboxCentroid`, `computeInferenceSize`, `scaleDetectionUp` are all pure and testable in isolation without TF.js, Web Workers, or browser APIs
- **Config injection**: `SALIENCY_CONFIG` is passed as a parameter to pure functions, enabling tests to override thresholds without globals
- **Worker message protocol**: Explicit string constants for all message types, enabling protocol validation tests
- **Factory pattern**: `createSaliencyAnalyzer` follows the project convention with `init`/`dispose` lifecycle
- **Callback injection**: The full analyzer receives callbacks as a plain object, enabling spy/mock usage in integration tests

#### 3.3.2 Test Scenarios (Unit Tests — Pure Functions)

**Test file**: `MyComponents/SaliencyTest.html` (new).

**Focus Point Computation**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.3.2.1 | Single face detection → focus on face center | `faces: [{bbox: {x:400, y:300, w:200, h:200}, conf: 0.9}]`, image: 1000x1000 | Focus = {x: 0.5, y: 0.5}, source: 'face-detection' |
| 3.3.2.2 | Single face at top-left → focus shifted to top-left | `faces: [{bbox: {x:50, y:50, w:100, h:100}, conf: 0.8}]`, image: 1000x1000 | Focus ≈ {x: 0.1, y: 0.1} |
| 3.3.2.3 | Single face at bottom-right → focus shifted to bottom-right | `faces: [{bbox: {x:850, y:850, w:100, h:100}, conf: 0.8}]`, image: 1000x1000 | Focus ≈ {x: 0.9, y: 0.9} |
| 3.3.2.4 | Multiple faces → centroid of all face centers | 2 faces at opposite corners, image: 1000x1000 | Focus ≈ {x: 0.5, y: 0.5} |
| 3.3.2.5 | Three faces in triangle → centroid | 3 faces at triangle vertices, image: 1000x1000 | Focus ≈ {x: 0.45, y: 0.5} |
| 3.3.2.6 | No detections → center of image | `faces: [], objects: []`, image: 1000x1000 | Focus = {x: 0.5, y: 0.5}, source: 'center-fallback' |
| 3.3.2.7 | No faces but objects → use object centroid | `faces: [], objects: [{bbox: {x:600, y:400, w:200, h:200}, conf: 0.7}]` | Focus ≈ {x: 0.7, y: 0.5}, source: 'coco-ssd' |
| 3.3.2.8 | Face + object mix → prioritize faces over objects | 1 face at top-left, 1 object at bottom-right | Focus on face center, source: 'face-detection' |
| 3.3.2.9 | Detection at image boundary → clamp to valid range | `faces: [{bbox: {x:0, y:0, w:100, h:100}}]`, image: 1000x1000 | Focus = {x: 0.05, y: 0.05}, within [0, 1] |
| 3.3.2.10 | Detection extending beyond image → clamp bbox | `faces: [{bbox: {x:950, y:950, w:100, h:100}}]`, image: 1000x1000 | Bbox clamped, focus within [0, 1] |
| 3.3.2.11 | Very small detection below min size → ignored | `faces: [{bbox: {x:500, y:500, w:5, h:5}}]`, minPixelSize: 20 | Filtered out, focus = center fallback |
| 3.3.2.12 | Detection exactly at min size threshold → included | `faces: [{bbox: {x:500, y:500, w:20, h:20}}]`, minPixelSize: 20 | Included, focus computed from face |
| 3.3.2.13 | Low confidence face below threshold → filtered | `conf: 0.3`, faceThreshold: 0.5 | Face filtered, focus = center fallback |
| 3.3.2.14 | Low confidence face at threshold → included | `conf: 0.5`, faceThreshold: 0.5 | Included (>= threshold) |
| 3.3.2.15 | Low confidence object below threshold → filtered | `conf: 0.2`, objectThreshold: 0.3 | Object filtered, focus = center fallback |
| 3.3.2.16 | Mixed confidence: one high, one low face → only high used | `conf: 0.9` and `conf: 0.3` | Only high-confidence face used |
| 3.3.2.17 | All faces low confidence, objects high → fall back to objects | All faces conf < 0.5, objects conf > 0.3 | Focus from objects, source: 'coco-ssd' |
| 3.3.2.18 | Portrait image with face at center | `faces: [{bbox: {x:400, y:400, w:200, h:200}}]`, image: 1080x1920 | Focus ≈ {x: 0.5, y: 0.31} |
| 3.3.2.19 | Panoramic image (21:9) with face at left third | `faces: [{bbox: {x:300, y:400, w:100, h:100}}]`, image: 3780x1800 | Focus ≈ {x: 0.09, y: 0.28} |
| 3.3.2.20 | Empty detections object → center fallback | `detections: {}`, image: 1000x1000 | Focus = {x: 0.5, y: 0.5}, source: 'center-fallback' |
| 3.3.2.21 | Null/undefined faces array → center fallback | `detections: { objects: [] }` | Focus = {x: 0.5, y: 0.5} |
| 3.3.2.22 | Null/undefined objects array → center fallback | `detections: { faces: [] }` | Focus = {x: 0.5, y: 0.5} |
| 3.3.2.23 | Zero-size image → center fallback | Any detections, image: {width: 0, height: 0} | Focus = {x: 0.5, y: 0.5} |
| 3.3.2.24 | Very small image (50x50) with detection | `faces: [{bbox: {x:15, y:15, w:20, h:20}}]`, image: 50x50 | Focus computed, normalized to [0,1] |

**Saliency Crop Shifting**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.3.2.25 | Focus at center → same as center crop | centerCrop: {x:500, y:0, w:1000, h:1000}, focus: {x:0.5, y:0.5} | Result = centerCrop (no shift) |
| 3.3.2.26 | Focus at top-left → crop shifts toward top-left | focus: {x:0.0, y:0.0} | Result.x < centerCrop.x, result.y clamped to 0 |
| 3.3.2.27 | Focus at bottom-right → crop shifts toward bottom-right | focus: {x:1.0, y:1.0} | Result.x > centerCrop.x, clamped to bounds |
| 3.3.2.28 | Focus at top edge midpoint → crop shifts up | focus: {x:0.5, y:0.0} | Result.y < centerCrop.y |
| 3.3.2.29 | Focus at bottom edge midpoint → crop shifts down | focus: {x:0.5, y:1.0} | Result.y > centerCrop.y |
| 3.3.2.30 | Focus at left edge midpoint → crop shifts left | focus: {x:0.0, y:0.5} | Result.x < centerCrop.x |
| 3.3.2.31 | Focus at right edge midpoint → crop shifts right | focus: {x:1.0, y:0.5} | Result.x > centerCrop.x |
| 3.3.2.32 | Crop clamping: shift doesn't exceed image bounds left | Extreme left shift | Result.x >= 0 |
| 3.3.2.33 | Crop clamping: shift doesn't exceed image bounds right | Extreme right shift | Result.x + Result.width <= image.width |
| 3.3.2.34 | Crop clamping: shift doesn't exceed image bounds top | Extreme up shift | Result.y >= 0 |
| 3.3.2.35 | Crop clamping: shift doesn't exceed image bounds bottom | Extreme down shift | Result.y + Result.height <= image.height |
| 3.3.2.36 | Crop preserves aspect ratio after shift | Any shift | Result.width === centerCrop.width, Result.height === centerCrop.height |
| 3.3.2.37 | Crop preserves dimensions after shift | Any shift | Result.width and Result.height unchanged |
| 3.3.2.38 | Very wide panel crop (21:9) with focus at center | centerCrop fills width, focus: {x:0.5, y:0.5} | Result = centerCrop (no shift) |
| 3.3.2.39 | Very tall panel crop (9:21) with focus at bottom | centerCrop fills height, focus: {x:0.5, y:1.0} | Result.y = 0 (clamped, crop fills height) |
| 3.3.2.40 | Square panel crop with focus slightly off-center | focus: {x:0.6, y:0.4} | Result.x shifted right, Result.y shifted up |
| 3.3.2.41 | Crop with minimum size (1px) — shift still works | centerCrop: {w:1, h:1}, focus: {x:0.0, y:0.0} | Result.x = 0, Result.y = 0 |
| 3.3.2.42 | Crop fills entire image — no shift possible | centerCrop = full image, focus: {x:0.1, y:0.1} | Result = centerCrop (no room to shift) |
| 3.3.2.43 | Focus point outside [0,1] range → clamped | focus: {x:1.5, y:-0.5} | Clamped to {x:1.0, y:0.0} |
| 3.3.2.44 | NaN focus point → treated as center | focus: {x:NaN, y:NaN} | Result = centerCrop (no shift) |
| 3.3.2.45 | Infinity focus point → clamped to edge | focus: {x:Infinity, y:-Infinity} | Clamped to {x:1.0, y:0.0} |

**Detection Filtering**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.3.2.46 | filterDetections — all pass threshold | 3 detections conf: 0.9, 0.8, 0.7, minConfidence: 0.5 | Returns all 3 |
| 3.3.2.47 | filterDetections — all below threshold | conf: 0.2, 0.1, 0.05, minConfidence: 0.5 | Returns empty array |
| 3.3.2.48 | filterDetections — mixed confidence | conf: 0.9, 0.3, 0.6, minConfidence: 0.5 | Returns 2 (0.9 and 0.6) |
| 3.3.2.49 | filterDetections — empty input | [], minConfidence: 0.5 | Returns empty array |
| 3.3.2.50 | filterDetections — size filtering active | bbox: {w:5, h:5}, minPixelSize: 20 | Filtered out |
| 3.3.2.51 | filterDetections — size exactly at threshold | bbox: {w:20, h:20}, minPixelSize: 20 | Included |
| 3.3.2.52 | filterDetections — both confidence and size filtering | conf: 0.9, bbox: {w:5, h:5}, minPixelSize: 20 | Filtered out (too small) |

**Bbox Centroid Computation**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.3.2.53 | computeBboxCentroid — single bbox | [{x:100, y:100, w:100, h:100}] | Returns {x: 150, y: 150} |
| 3.3.2.54 | computeBboxCentroid — two bboxes | [{x:0, y:0, w:100, h:100}, {x:900, y:900, w:100, h:100}] | Returns {x: 500, y: 500} |
| 3.3.2.55 | computeBboxCentroid — empty array | [] | Returns image center {x: 500, y: 500} |
| 3.3.2.56 | computeBboxCentroid — overlapping bboxes | Two overlapping bboxes | Returns centroid of centers (not affected by overlap) |

**Inference Size Computation**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.3.2.57 | computeInferenceSize — image below max | image: 400x300, maxDim: 512 | Returns {width: 400, height: 300, scale: 1.0} |
| 3.3.2.58 | computeInferenceSize — image above max (landscape) | image: 1920x1080, maxDim: 512 | Returns {width: 512, height: 288, scale: 0.267} |
| 3.3.2.59 | computeInferenceSize — image above max (portrait) | image: 1080x1920, maxDim: 512 | Returns {width: 288, height: 512, scale: 0.267} |
| 3.3.2.60 | computeInferenceSize — square image above max | image: 2000x2000, maxDim: 512 | Returns {width: 512, height: 512, scale: 0.256} |
| 3.3.2.61 | computeInferenceSize — 4K image | image: 3840x2160, maxDim: 512 | Returns {width: 512, height: 288, scale: 0.133} |
| 3.3.2.62 | computeInferenceSize — 8K image | image: 7680x4320, maxDim: 512 | Returns {width: 512, height: 288, scale: 0.067} |
| 3.3.2.63 | computeInferenceSize — zero-size image | image: {width: 0, height: 0} | Returns {width: 0, height: 0, scale: 1.0} |

**Detection Scaling**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.3.2.64 | scaleDetectionUp — scale factor 0.5 | bbox: {x:100, y:100, w:50, h:50}, scale: 0.5 | Returns {x: 200, y: 200, w: 100, h: 100} |
| 3.3.2.65 | scaleDetectionUp — scale factor 1.0 | scale: 1.0 | Returns same bbox |
| 3.3.2.66 | scaleDetectionUp — scale factor 0.1 | scale: 0.1 | Returns {x: 500, y: 500, w: 200, h: 200} |
| 3.3.2.67 | scaleDetectionUp — zero scale → no crash | scale: 0 | Handles gracefully (Infinity or clamped) |
| 3.3.2.68 | scaleDetectionUp — negative scale → no crash | scale: -0.5 | Handles gracefully |

**Constants Validation**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.3.2.69 | SALIENCY_CONFIG has all required fields | `SALIENCY_CONFIG` | All 8 fields present |
| 3.3.2.70 | MODEL_PRIORITY order | `SALIENCY_CONFIG.MODEL_PRIORITY` | ['face-detection', 'coco-ssd', 'center-fallback'] |
| 3.3.2.71 | MAX_INFERENCE_DIMENSION is reasonable | `SALIENCY_CONFIG.MAX_INFERENCE_DIMENSION` | Value = 512 |
| 3.3.2.72 | INFERENCE_TIMEOUT_MS is positive | `SALIENCY_CONFIG.INFERENCE_TIMEOUT_MS` | Value > 0 |

#### 3.3.3 Test Scenarios (Unit Tests — Worker Message Protocol)

**Test file**: Same `MyComponents/SaliencyTest.html` (protocol constants and message validation).

**Worker Message Constants**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.3.3.1 | WORKER_MSG has all required types | `WORKER_MSG` | Contains all 8 message types |
| 3.3.3.2 | All message types are unique strings | `Object.values(WORKER_MSG)` | All values distinct, no duplicates |
| 3.3.3.3 | All message types follow naming convention | `Object.values(WORKER_MSG)` | All start with 'saliency:' prefix |

**Request Message Format (Main → Worker)**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.3.3.4 | INIT_MODELS message format | `{ type: WORKER_MSG.INIT_MODELS }` | Valid message |
| 3.3.3.5 | ANALYZE_IMAGE includes image data | `{ type: ANALYZE_IMAGE, imageData: 'base64...', imageSize: {w:1920, h:1080} }` | Has type, imageData (string), imageSize |
| 3.3.3.6 | ANALYZE_IMAGE with data URL | `{ type: ANALYZE_IMAGE, imageData: 'data:image/png;base64,...' }` | Valid |
| 3.3.3.7 | DISPOSE message format | `{ type: WORKER_MSG.DISPOSE }` | Valid |
| 3.3.3.8 | ANALYZE_IMAGE missing imageSize → handled | No imageSize field | Worker rejects or uses defaults, no crash |
| 3.3.3.9 | ANALYZE_IMAGE with null imageData → handled | `imageData: null` | Worker rejects with ANALYSIS_ERROR |
| 3.3.3.10 | Unknown message type → handled | `{ type: 'unknown:type' }` | Worker ignores or errors, no crash |

**Response Message Format (Worker → Main)**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.3.3.11 | MODELS_READY success response | `{ type: MODELS_READY, models: [...] }` | Has type, models array |
| 3.3.3.12 | MODELS_FAILED response | `{ type: MODELS_FAILED, error: '...' }` | Has type, error string |
| 3.3.3.13 | ANALYSIS_COMPLETE with face detection | `{ type: ANALYSIS_COMPLETE, focusPoint: {...}, source: 'face-detection' }` | Has type, focusPoint, source |
| 3.3.3.14 | ANALYSIS_COMPLETE with center fallback | `source: 'center-fallback'` | focusPoint at center |
| 3.3.3.15 | ANALYSIS_ERROR response | `{ type: ANALYSIS_ERROR, error: '...' }` | Has type, error string |
| 3.3.3.16 | DISPOSED response | `{ type: DISPOSED }` | Has type |

**Message Handling Edge Cases**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.3.3.17 | ANALYZE_IMAGE before INIT_MODELS | Send ANALYZE_IMAGE without prior INIT_MODELS | Returns ANALYSIS_ERROR or uses fallback |
| 3.3.3.18 | Multiple ANALYZE_IMAGE in flight | 3 rapid ANALYZE_IMAGE messages | Last wins or all queued |
| 3.3.3.19 | DISPOSE during active analysis | ANALYZE_IMAGE then DISPOSE before response | Clean termination, no leaked resources |
| 3.3.3.20 | INIT_MODELS called twice → idempotent | Send INIT_MODELS twice | Second call is no-op or reinitializes safely |

#### 3.3.4 Test Scenarios (Integration Tests)

**Test file**: Same `MyComponents/SaliencyTest.html` (integration section using mocked Worker and TF.js).

**Analyzer Lifecycle**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.3.4.1 | createSaliencyAnalyzer returns correct interface | `createSaliencyAnalyzer({ callbacks })` | Has: initModels, analyzeImage, cancel, dispose, getState |
| 3.3.4.2 | Initial state is 'idle' | `analyzer.getState()` after creation | Returns 'idle' |
| 3.3.4.3 | initModels transitions to 'loading' | `analyzer.initModels()` | State changes to 'loading' |
| 3.3.4.4 | initModels success → 'ready', fires onModelsReady | Mock worker sends MODELS_READY | State = 'ready', callback fires |
| 3.3.4.5 | initModels failure → 'failed', fires onModelsFailed | Mock worker sends MODELS_FAILED | State = 'failed', callback fires |
| 3.3.4.6 | analyzeImage when state is 'loading' → queued or rejected | Call before models ready | Queued or returns center fallback |
| 3.3.4.7 | analyzeImage when state is 'failed' → center fallback | Call after models failed | Returns center crop, no crash |
| 3.3.4.8 | dispose → state becomes 'idle' or disposed | `analyzer.dispose()` | Worker terminated, no further callbacks |
| 3.3.4.9 | Double dispose is safe | `dispose()` called twice | No error thrown |
| 3.3.4.10 | initModels after dispose → reinitializes | `dispose()` then `initModels()` | New worker created, models reload |

**Model Loading States**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.3.4.11 | Models load successfully | Mock worker responds MODELS_READY | onModelsReady fires, state = 'ready' |
| 3.3.4.12 | Models fail to load (network error) | Mock worker responds MODELS_FAILED | onModelsFailed fires, state = 'failed' |
| 3.3.4.13 | Models timeout | No response within INFERENCE_TIMEOUT_MS | onModelsFailed fires with timeout error |
| 3.3.4.14 | Partial model load (face ok, coco failed) | Face-detection loads, coco-ssd fails | onModelsReady with ['face-detection'] only |

**Async Inference Flow**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.3.4.15 | Successful face detection analysis | Valid image, models ready | onAnalysisComplete with focusPoint from faces |
| 3.3.4.16 | Analysis with no faces → object fallback | No faces but objects detected | onAnalysisComplete with focusPoint from coco-ssd |
| 3.3.4.17 | Analysis with no detections → center fallback | No faces or objects | focusPoint: {0.5, 0.5}, source: 'center-fallback' |
| 3.3.4.18 | Inference error → onAnalysisError fired | Worker sends ANALYSIS_ERROR | Callback fires with error, no crash |
| 3.3.4.19 | Inference timeout → fallback to center | Worker takes > INFERENCE_TIMEOUT_MS | Center fallback applied |
| 3.3.4.20 | Cancel during analysis → pending request aborted | `analyzeImage()` then `cancel()` | No onAnalysisComplete fires |
| 3.3.4.21 | Multiple sequential analyses → all complete | `analyzeImage(img1)`, wait, `analyzeImage(img2)` | Both complete with correct results |
| 3.3.4.22 | Rapid successive analyses → no race conditions | 5 rapid `analyzeImage()` calls | All 5 complete, no interleaved state |

**Integration with CropManager**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.3.4.23 | Saliency focus point applied to crop | FocusPoint → `saliencyCrop()` → `setSourceRect()` | sourceRect shifted toward focus, clamped |
| 3.3.4.24 | Saliency crop preserves CropInfo structure | Analyzer output through CropInfo pipeline | Has panelId, sourceRect, destination |
| 3.3.4.25 | Saliency crop + manual override | Saliency sets crop, user adjusts via CropManager | Manual adjustment overrides saliency |
| 3.3.4.26 | Saliency crop reset → back to center | `resetCrop()` after saliency crop | Returns to FitMath.sourceRect center |

#### 3.3.5 E2E Test Scenarios (Playwright)

**Test file**: `test/e2e/saliency.spec.js` (new).

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.3.5.1 | Saliency analysis shows loading indicator | Upload image with faces, saliency enabled | Loading indicator visible during analysis, disappears when complete |
| 3.3.5.2 | Saliency affects crop — face-centered | Upload portrait with face, wait for analysis | Canvas shows crop focused on face (not centered) |
| 3.3.5.3 | Saliency crop differs from center crop | Upload image with off-center subject | Crop coordinates differ from FitMath.sourceRect center |
| 3.3.5.4 | Fallback to center when models fail | Block TF.js model URLs, upload image | App functions with center crop, no console errors, no stuck state |
| 3.3.5.5 | Fallback to center when no detections | Upload abstract art (no faces/objects) | Center crop applied, no errors |
| 3.3.5.6 | No UI freeze during inference | Upload 4K image, measure responsiveness | UI responsive during analysis — no main thread blocking > 100ms |
| 3.3.5.7 | Privacy — no external image uploads | Upload image, monitor network | No image data sent externally. Only TF.js model CDN requests |
| 3.3.5.8 | Memory leak check — multiple uploads | Upload 10 images sequentially with saliency | No unbounded memory growth, no TF.js tensor leaks |
| 3.3.5.9 | Saliency toggle — disable and re-enable | Toggle off, upload, toggle on, upload | Disabled: center crop. Enabled: saliency crop. No crash |
| 3.3.5.10 | Saliency with hero layout | Upload 3 images with hero layout | Hero + side panels all use saliency crops |
| 3.3.5.11 | Saliency with hexagonal layout | Upload 7 images with hexagonal layout | All 7 panels have valid crops, no NaN/Infinity |
| 3.3.5.12 | Very small image (50x50) — skips inference | Upload 50x50 image | Center crop used (below MIN_INFERENCE_DIMENSION) |
| 3.3.5.13 | Very large image (4K) — downsampled | Upload 4000x3000 image | Analysis completes (downsampled to MAX_INFERENCE_DIMENSION) |
| 3.3.5.14 | Layout change after saliency — crops reset | Upload, wait for saliency, change layout | New layout uses default center crops (documented behavior) |
| 3.3.5.15 | Multiple images — batch processing | Upload 5 images simultaneously | All analyzed, no UI freeze, reasonable total time |
| 3.3.5.16 | aria-busy during analysis | Upload image, check aria attributes | `aria-busy="true"` during, `aria-busy="false"` after |
| 3.3.5.17 | Keyboard-accessible saliency toggle | Tab to toggle, press Enter/Space | Toggle state changes, visual feedback shown |
| 3.3.5.18 | Page refresh — saliency state | Upload, analyze, refresh page | Documented behavior: re-analysis or center crop |
| 3.3.5.19 | Worker crash recovery | Simulate worker crash, upload image | Graceful fallback to center crop, no permanent broken state |
| 3.3.5.20 | Saliency disabled by default | Fresh page load | Saliency disabled (center crop used) to avoid unexpected model downloads |

#### 3.3.6 Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | 3.3.2.1–3.3.2.24 (Focus Point Computation), 3.3.2.25–3.3.2.45 (Saliency Crop Shifting), 3.3.4.4–3.3.4.5 (Model load states), 3.3.4.15–3.3.4.17 (Inference flow), 3.3.5.4–3.3.5.6 (Fallback + no freeze) | Core functionality — if these fail, the feature produces wrong crops or crashes the app. Graceful degradation is the single most critical requirement. |
| **P1** | 3.3.2.46–3.3.2.68 (Filtering, Centroid, Sizing, Scaling), 3.3.3.1–3.3.3.20 (Worker Protocol), 3.3.4.1–3.3.4.3 (Lifecycle), 3.3.4.18–3.3.4.26 (Error handling + CropManager), 3.3.5.1–3.3.5.3, 3.3.5.7–3.3.5.15 (E2E core) | Structural correctness, protocol validation, and integration with existing crop pipeline. |
| **P2** | 3.3.2.69–3.3.2.72 (Constants), 3.3.4.6–3.3.4.14 (Edge lifecycle), 3.3.5.16–3.3.5.20 (Accessibility, memory, edge cases) | Polish, accessibility, memory management, and edge-case robustness. |

#### 3.3.7 Known Behaviors to Document

1. **Privacy guarantee**: All saliency analysis runs entirely client-side using TensorFlow.js. No image data is ever sent to external servers. The only external requests are for loading TF.js model weights (~9MB total) from the CDN.

2. **Performance characteristics**: TF.js inference runs in a Web Worker to prevent main thread blocking. Typical inference: 500ms–3s per image on modern hardware. Images are downsampled to `MAX_INFERENCE_DIMENSION` (512px) before inference.

3. **Fallback guarantees**: Three-tier fallback: (1) face detection, (2) object detection, (3) center crop. At no point should the app freeze, crash, or show a broken state. Center crop is always available.

4. **Model size implications**: ~9MB total lazy-loaded when saliency is enabled. Cached by browser after first load. On slow connections, loading may take 10–30 seconds.

5. **Crop data lost on layout change**: When layout style changes, all crops (including saliency-computed) reset to defaults. Consistent with existing `LayoutManager.regenerate()` behavior.

6. **No saliency for very small images**: Images below `MIN_INFERENCE_DIMENSION` (32px) skip inference and use center crop. Prevents TF.js errors from inputs too small for the model.

7. **Saliency disabled by default**: On first load, saliency is disabled to avoid unexpected model downloads. Users must explicitly enable it. Setting can be persisted via `SettingsPersistence`.

8. **Tensor disposal**: TF.js WebGL tensors are disposed after each inference to prevent GPU memory leaks. `dispose()` terminates the Web Worker and releases all resources.

9. **Focus point normalization**: All focus points are normalized to [0, 1] relative to source image dimensions, making them portable across different image sizes and panel geometries.

10. **Detection confidence thresholds are configurable**: `SALIENCY_CONFIG` exposes all thresholds as constants, enabling future tuning without code changes.

### 3.4 Saliency Debug Overlay

- **Description**: Visual debug overlay showing the calculated focal point (green circle), geometric center (red dot), a shift vector line connecting the two, and a crop rectangle outline per panel. Renders as a new pass in the CollageAssembler pipeline.
- **User Impact**: Low. Only beneficial during the development/tuning of ML saliency.
- **Effort**: Low/Medium. Requires a new rendering module with pure coordinate functions and a canvas rendering pass.
- **Dependencies**: `SaliencyAnalyzer` (Section 3.3) for focus point data.
- **Risk**: Low. Must never contaminate exported JPEGs.
- **Recommendation**: **Nice-to-have (Deferred)**. No value if ML Saliency is deferred.
- **Implementation Outline** (for future reference):
  - Create `MyESModules/Rendering/SaliencyDebugOverlay.js`
  - Pure functions: `focusPointToCanvasCoords`, `imageCenterToCanvasCoords`, `computeDebugMarkers`, `validateFocusPoint`
  - Canvas rendering: `render(ctx, panels, images, crops, panelAssignments, focusPoints, canvasSize)`
  - Factory: `createDebugOverlay()`
  - Constants: `DEBUG_OVERLAY_STYLES`
  - Add `showDebugOverlay` and `focusPoints` to `CollageState`
  - Integrate into `CollageAssembler.render()` between selection and blend-mode overlay
  - Ensure `ExportManager.exportToJpeg()` does NOT pass debug overlay options

#### 3.4.1 Recommended Module Interface (for testability)

The `SaliencyDebugOverlay` module should follow the existing rendering pattern: pure functions for coordinate math (testable without canvas), a canvas rendering function (testable with offscreen canvas), and a factory for assembler integration.

```javascript
// MyESModules/Rendering/SaliencyDebugOverlay.js

// Constants
export const DEBUG_OVERLAY_STYLES = {
    FOCAL_POINT: { color: '#00FF00', radius: 6, lineWidth: 2 },    // Green circle
    CENTER_DOT: { color: '#FF0000', radius: 4, lineWidth: 1 },      // Red dot
    SHIFT_VECTOR: { color: '#00FF00', lineWidth: 1, dashPattern: [4, 4] }, // Dashed green line
    CROP_RECT: { color: '#FFFF00', lineWidth: 1 },                   // Yellow crop outline
    LABEL_FONT: '10px monospace',
    LABEL_OFFSET_X: 8,
    LABEL_OFFSET_Y: -8,
};

// Pure functions (testable without browser/canvas)
export function focusPointToCanvasCoords(focusPoint, imageSize, crop) { /* ... */ }
export function imageCenterToCanvasCoords(imageSize, crop) { /* ... */ }
export function computeDebugMarkers(panel, imageItem, crop, focusPoint) { /* ... */ }
export function validateFocusPoint(focusPoint) { /* ... */ }

// Canvas rendering (requires CanvasRenderingContext2D)
export function render(ctx, panels, images, crops, panelAssignments, focusPoints, canvasSize) { /* ... */ }

// Factory for integration with CollageAssembler
export function createDebugOverlay() {
    return { render(ctx, options) { ... } };
}
```

Key design decisions:
- **Pure functions first**: `focusPointToCanvasCoords`, `imageCenterToCanvasCoords`, `computeDebugMarkers`, `validateFocusPoint` are all pure and testable without any browser APIs
- **Constants as config**: `DEBUG_OVERLAY_STYLES` exposes all visual parameters, enabling tests to verify styling and future customization
- **No clipping**: Debug overlay renders outside panel clip paths — markers are drawn directly on the canvas context
- **DPR-aware marker sizing**: Marker radii are specified in screen pixels, not source-image pixels, ensuring consistent visibility at any zoom level
- **Shift vector visualization**: A dashed line connects the center dot to the focal point, visually communicating the crop shift magnitude and direction
- **Factory pattern**: `createDebugOverlay()` follows the project convention, returning an object with a `render` method compatible with CollageAssembler's pipeline

#### 3.4.2 Test Scenarios (Unit Tests — Pure Functions)

**Test file**: `MyComponents/SaliencyDebugOverlayTest.html` (new).

**Focus Point Coordinate Transformation (`focusPointToCanvasCoords`)**

The core mathematical function. Converts a normalized focus point `{x, y}` (0 = top/left, 1 = bottom/right) to canvas pixel coordinates, accounting for the crop's source rectangle and destination rectangle.

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.4.2.1 | Focus at image center → panel center | focus: `{x:0.5, y:0.5}`, image: 2000x2000, crop: source(0,0,2000,2000) → dest(0,0,1000,1000) | `{x: 500, y: 500}` |
| 3.4.2.2 | Focus at top-left of image → top-left of crop | focus: `{x:0.0, y:0.0}`, same crop | `{x: 0, y: 0}` |
| 3.4.2.3 | Focus at bottom-right → bottom-right of crop | focus: `{x:1.0, y:1.0}`, same crop | `{x: 1000, y: 1000}` |
| 3.4.2.4 | Focus at top-right → top-right of crop | focus: `{x:1.0, y:0.0}`, same crop | `{x: 1000, y: 0}` |
| 3.4.2.5 | Focus at bottom-left → bottom-left of crop | focus: `{x:0.0, y:1.0}`, same crop | `{x: 0, y: 1000}` |
| 3.4.2.6 | Crop offset: focus at center of cropped region | focus: `{x:0.5, y:0.5}`, image: 4000x3000, crop: source(1000,500,2000,2000) → dest(0,0,1000,1000) | `{x: 500, y: 500}` |
| 3.4.2.7 | Crop offset: focus at source rect top-left | focus: `{x:0.25, y:0.1667}`, image: 4000x3000, crop: source(1000,500,2000,2000) → dest(100,100,800,600) | `{x: 100, y: 100}` |
| 3.4.2.8 | Crop offset: focus at source rect bottom-right | focus: `{x:0.75, y:0.8333}`, same crop | `{x: 900, y: 700}` |
| 3.4.2.9 | Portrait image in landscape panel | focus: `{x:0.5, y:0.5}`, image: 1080x1920, crop from FitMath → dest(0,0,1000,562) | Pixel coords within dest rect |
| 3.4.2.10 | Landscape image in portrait panel | focus: `{x:0.5, y:0.5}`, image: 1920x1080, crop from FitMath → dest(0,0,562,1000) | Pixel coords within dest rect |
| 3.4.2.11 | Square image, 1:1 crop | focus: `{x:0.3, y:0.7}`, image: 1000x1000, crop: source(0,0,1000,1000) → dest(0,0,500,500) | `{x: 150, y: 350}` |
| 3.4.2.12 | Focus slightly off-center | focus: `{x:0.55, y:0.45}`, image: 2000x2000, crop: source(0,0,2000,2000) → dest(0,0,1000,1000) | `{x: 550, y: 450}` |
| 3.4.2.13 | Very small crop (100x100) | focus: `{x:0.5, y:0.5}`, image: 4000x3000, crop: source(1900,1400,200,200) → dest(400,400,100,100) | `{x: 450, y: 450}` |
| 3.4.2.14 | Panel destination offset from canvas origin | focus: `{x:0.5, y:0.5}`, image: 2000x2000, crop: source(0,0,2000,2000) → dest(500,300,400,300) | `{x: 700, y: 450}` |
| 3.4.2.15 | Non-integer focus values | focus: `{x:0.333333, y:0.666667}`, image: 3000x3000, crop: source(0,0,3000,3000) → dest(0,0,900,900) | `{x: 300, y: 600}` (within 0.1 tolerance) |

**Image Center Coordinate Computation (`imageCenterToCanvasCoords`)**

Convenience wrapper that computes the canvas position of the image's geometric center. Must produce the same result as `focusPointToCanvasCoords({x: 0.5, y: 0.5}, ...)`.

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.4.2.16 | Center of full-image crop | image: 2000x2000, crop: source(0,0,2000,2000) → dest(0,0,1000,1000) | `{x: 500, y: 500}` |
| 3.4.2.17 | Center equals focusPointToCanvasCoords at 0.5,0.5 | Same inputs as 3.4.2.16 | Identical result |
| 3.4.2.18 | Center with offset crop | image: 4000x3000, crop: source(1000,500,2000,2000) → dest(100,100,800,600) | `{x: 500, y: 400}` |
| 3.4.2.19 | Center of portrait image in landscape crop | image: 1080x1920, crop from FitMath → dest(0,0,1000,562) | Within dest rect bounds |
| 3.4.2.20 | Center with panel offset | image: 2000x2000, crop: source(0,0,2000,2000) → dest(500,300,400,300) | `{x: 700, y: 450}` |

**Debug Marker Computation (`computeDebugMarkers`)**

Assembles the marker data for a single panel. Returns an array of `{type, x, y}` objects.

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.4.2.21 | Panel with valid focus point → two markers | panel, imageItem, crop, focusPoint: `{x:0.3, y:0.4}` | Returns `[{type:'focal',...}, {type:'center',...}]` |
| 3.4.2.22 | Panel with no focus point → center marker only | focusPoint: `undefined` | Returns `[{type:'center',...}]` |
| 3.4.2.23 | Panel with no crop → empty array | crop: `undefined`, focusPoint: valid | Returns `[]` |
| 3.4.2.24 | Panel with no image → empty array | imageItem: `undefined`, crop: valid | Returns `[]` |
| 3.4.2.25 | Panel with no image AND no crop → empty array | All undefined | Returns `[]` |
| 3.4.2.26 | Focus point at image center → markers overlap | focusPoint: `{x:0.5, y:0.5}` | Both markers have same x,y (two distinct entries) |
| 3.4.2.27 | Focus point at image corner → markers far apart | focusPoint: `{x:0.0, y:0.0}` | Focal at top-left, center at panel center |
| 3.4.2.28 | Multiple panels → independent computation | 3 panels with different crops | Each panel's markers computed independently |
| 3.4.2.29 | Panel with NaN focus point → center-only | focusPoint: `{x:NaN, y:NaN}` | Returns `[{type:'center',...}]` |
| 3.4.2.30 | Panel with Infinity focus point → center-only | focusPoint: `{x:Infinity, y:Infinity}` | Returns `[{type:'center',...}]` |
| 3.4.2.31 | Panel with focus point outside [0,1] → center-only | focusPoint: `{x:1.5, y:-0.5}` | Returns `[{type:'center',...}]` |
| 3.4.2.32 | Panel with null focus point → center-only | focusPoint: `null` | Returns `[{type:'center',...}]` |

**Focus Point Validation (`validateFocusPoint`)**

Guard function used before coordinate transformation.

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.4.2.33 | Valid focus point at center | `{x: 0.5, y: 0.5}` | `true` |
| 3.4.2.34 | Valid focus point at corner | `{x: 0.0, y: 0.0}` | `true` |
| 3.4.2.35 | Valid focus point at opposite corner | `{x: 1.0, y: 1.0}` | `true` |
| 3.4.2.36 | Valid focus point at edge | `{x: 0.0, y: 0.5}` | `true` |
| 3.4.2.37 | Valid focus point fractional | `{x: 0.333, y: 0.667}` | `true` |
| 3.4.2.38 | NaN x → invalid | `{x: NaN, y: 0.5}` | `false` |
| 3.4.2.39 | NaN y → invalid | `{x: 0.5, y: NaN}` | `false` |
| 3.4.2.40 | Both NaN → invalid | `{x: NaN, y: NaN}` | `false` |
| 3.4.2.41 | Infinity x → invalid | `{x: Infinity, y: 0.5}` | `false` |
| 3.4.2.42 | Negative Infinity → invalid | `{x: -Infinity, y: 0.5}` | `false` |
| 3.4.2.43 | x > 1 → invalid | `{x: 1.5, y: 0.5}` | `false` |
| 3.4.2.44 | y < 0 → invalid | `{x: 0.5, y: -0.1}` | `false` |
| 3.4.2.45 | Null → invalid | `null` | `false` |
| 3.4.2.46 | Undefined → invalid | `undefined` | `false` |
| 3.4.2.47 | Empty object → invalid | `{}` | `false` |
| 3.4.2.48 | Missing x → invalid | `{y: 0.5}` | `false` |
| 3.4.2.49 | Missing y → invalid | `{x: 0.5}` | `false` |
| 3.4.2.50 | String values → invalid | `{x: '0.5', y: '0.5'}` | `false` |
| 3.4.2.51 | Zero values → valid | `{x: 0, y: 0}` | `true` |
| 3.4.2.52 | One valid, one NaN → invalid | `{x: 0.5, y: NaN}` | `false` |

**Constants Validation**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.4.2.53 | DEBUG_OVERLAY_STYLES has all required fields | `DEBUG_OVERLAY_STYLES` | Contains `FOCAL_POINT`, `CENTER_DOT`, `SHIFT_VECTOR`, `CROP_RECT`, `LABEL_FONT`, `LABEL_OFFSET_X`, `LABEL_OFFSET_Y` |
| 3.4.2.54 | FOCAL_POINT color is green | `DEBUG_OVERLAY_STYLES.FOCAL_POINT.color` | `'#00FF00'` |
| 3.4.2.55 | CENTER_DOT color is red | `DEBUG_OVERLAY_STYLES.CENTER_DOT.color` | `'#FF0000'` |
| 3.4.2.56 | SHIFT_VECTOR has dash pattern | `DEBUG_OVERLAY_STYLES.SHIFT_VECTOR.dashPattern` | Array with alternating values |
| 3.4.2.57 | FOCAL_POINT radius > CENTER_DOT radius | Compare radii | `FOCAL_POINT.radius > CENTER_DOT.radius` |
| 3.4.2.58 | LABEL_FONT is valid CSS font string | `DEBUG_OVERLAY_STYLES.LABEL_FONT` | Matches `/^\d+px\s+\w+$/` |

**Estimated pure function tests: 58**

#### 3.4.3 Test Scenarios (Unit Tests — Canvas Rendering)

These tests use an offscreen `<canvas>` element and its `CanvasRenderingContext2D` to verify rendering behavior. Follows the `ExportManagerTest.html` pattern of creating real canvas elements and inspecting context state via spies.

**Basic Drawing**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.4.3.1 | Render with valid focus point → arc called for focal | 1 panel, focusPoint: `{x:0.5, y:0.5}`, crop → dest(0,0,1000,1000) | `ctx.arc()` called at (500, 500) with green fill |
| 3.4.3.2 | Render with valid focus point → arc called for center | Same as 3.4.3.1 | `ctx.arc()` called at (500, 500) with red fill |
| 3.4.3.3 | Render without focus point → only center drawn | 1 panel, no focusPoint | `ctx.arc()` called once (red center only) |
| 3.4.3.4 | Render with no panels → no drawing | Empty panels array | No `ctx.arc()` calls |
| 3.4.3.5 | Render with no images → no drawing | Panels exist but images array empty | No `ctx.arc()` calls |
| 3.4.3.6 | Render with no crops → no drawing | Panels and images exist, crops empty | No `ctx.arc()` calls |
| 3.4.3.7 | Render with multiple panels → markers for each | 3 panels, each with focusPoint | 6 `ctx.arc()` calls (2 per panel) |
| 3.4.3.8 | Render with mixed panels (some with focus, some without) | 2 panels with focus, 1 without | 5 `ctx.arc()` calls (2+2+1) |
| 3.4.3.9 | Render uses ctx.save/restore | Any valid input | `ctx.save()` called before draw, `ctx.restore()` after |
| 3.4.3.10 | Render does not modify ctx globalAlpha outside save/restore | Verify via spy | `globalAlpha` unchanged after render |
| 3.4.3.11 | Render does not modify ctx fillStyle outside save/restore | Verify via spy | `fillStyle` unchanged after render |
| 3.4.3.12 | Focal point drawn as filled circle | focusPoint valid | `ctx.fill()` called after `ctx.arc()` for green marker |
| 3.4.3.13 | Center dot drawn as filled circle | Any valid panel | `ctx.fill()` called after `ctx.arc()` for red marker |
| 3.4.3.14 | Focal point has stroke outline | focusPoint valid | `ctx.stroke()` called for green marker |
| 3.4.3.15 | Shift vector line drawn when focus differs from center | focusPoint: `{x:0.3, y:0.4}` | `ctx.moveTo()` + `ctx.lineTo()` called for dashed line |
| 3.4.3.16 | Shift vector NOT drawn when focus equals center | focusPoint: `{x:0.5, y:0.5}` | No `ctx.lineTo()` calls (zero-length vector skipped) |
| 3.4.3.17 | Crop rectangle outline drawn | Any valid panel | `ctx.strokeRect()` called with yellow stroke |

**Marker Positioning Verification**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.4.3.18 | Marker at canvas origin | Panel at (0,0,100,100), focus at image top-left | `ctx.arc()` called at (0, 0, ...) |
| 3.4.3.19 | Marker at canvas center | Panel at (460,290,1000,500), focus at image center | `ctx.arc()` called at (960, 540, ...) |
| 3.4.3.20 | Marker at canvas edge | Panel at (1800,980,100,100), focus at image bottom-right | `ctx.arc()` called at (1900, 1080, ...) |
| 3.4.3.21 | Two panels side by side → markers at different positions | Panel A at (0,0,960,540), Panel B at (960,0,960,540) | Two sets of markers at distinct positions |
| 3.4.3.22 | Hexagonal layout → markers within panel bounds | 7 hexagonal panels, each with focusPoint | All markers within respective panel bounding rects |

**Style Verification**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.4.3.23 | Focal point uses green fill | Any valid input | `ctx.fillStyle` set to `'#00FF00'` before green arc |
| 3.4.3.24 | Center dot uses red fill | Any valid input | `ctx.fillStyle` set to `'#FF0000'` before red arc |
| 3.4.3.25 | Focal point radius matches constant | Any valid input | `ctx.arc()` radius = `DEBUG_OVERLAY_STYLES.FOCAL_POINT.radius` (6) |
| 3.4.3.26 | Center dot radius matches constant | Any valid input | `ctx.arc()` radius = `DEBUG_OVERLAY_STYLES.CENTER_DOT.radius` (4) |
| 3.4.3.27 | Stroke width for focal point | Any valid input | `ctx.lineWidth` = `DEBUG_OVERLAY_STYLES.FOCAL_POINT.lineWidth` (2) |
| 3.4.3.28 | Stroke width for center dot | Any valid input | `ctx.lineWidth` = `DEBUG_OVERLAY_STYLES.CENTER_DOT.lineWidth` (1) |
| 3.4.3.29 | Shift vector uses dashed line | focusPoint differs from center | `ctx.setLineDash()` called with dash pattern |
| 3.4.3.30 | Crop rectangle uses yellow stroke | Any valid panel | `ctx.strokeStyle` set to `'#FFFF00'` |

**Edge Cases**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.4.3.31 | Very small panel (10x10) → markers still drawn | Panel dest: (0,0,10,10) | `ctx.arc()` called, markers drawn (may overlap) |
| 3.4.3.32 | Panel at negative coordinates → no crash | Panel dest: (-100, -100, 200, 200) | No crash, markers drawn at computed positions |
| 3.4.3.33 | Panel extends beyond canvas → markers drawn | Panel dest: (1800, 900, 200, 200) | No crash, markers drawn |
| 3.4.3.34 | Image with zero dimensions → no markers | imageItem: `{width: 0, height: 0}` | No crash, no markers drawn |
| 3.4.3.35 | Crop with zero-size source rect → no markers | crop: `{sourceRect: {x:0, y:0, width:0, height:0}}` | No crash, no markers drawn |
| 3.4.3.36 | Crop with zero-size destination → no markers | crop: `{destination: {x:0, y:0, width:0, height:0}}` | No crash, no markers drawn |
| 3.4.3.37 | NaN in crop coordinates → no crash | crop: `{sourceRect: {x:NaN, ...}, destination: {x:NaN, ...}}` | No crash, no markers drawn |
| 3.4.3.38 | Infinity in crop coordinates → no crash | crop: `{sourceRect: {x:Infinity, ...}}` | No crash, no markers drawn |
| 3.4.3.39 | Null ctx → no crash | ctx: `null` | No crash, early return |
| 3.4.3.40 | Undefined panels → no crash | panels: `undefined` | No crash, no markers drawn |
| 3.4.3.41 | Undefined images → no crash | images: `undefined` | No crash, no markers drawn |
| 3.4.3.42 | Undefined crops → no crash | crops: `undefined` | No crash, no markers drawn |
| 3.4.3.43 | Undefined focusPoints → no crash | focusPoints: `undefined` | No crash, center markers only |
| 3.4.3.44 | FocusPoints Map with missing key → center-only | focusPoints Map doesn't contain panel's image index | Center marker drawn, focal skipped |
| 3.4.3.45 | DPR scaling: marker radius adjusted for high-DPR | Mock devicePixelRatio = 2 | Radius divided by DPR, markers remain consistent screen size |

**Estimated canvas rendering tests: 45**

#### 3.4.4 Test Scenarios (Integration — CollageAssembler)

These tests verify the debug overlay integrates correctly into the existing rendering pipeline.

**CollageAssembler Integration**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.4.4.1 | Debug overlay renders when enabled | `assembler.render(ctx, {..., showDebugOverlay: true, focusPoints: Map{...}})` | Debug markers appear on canvas |
| 3.4.4.2 | Debug overlay does NOT render when disabled | `assembler.render(ctx, {..., showDebugOverlay: false})` | No debug markers on canvas |
| 3.4.4.3 | Debug overlay does NOT render when option omitted | `assembler.render(ctx, {...})` (no showDebugOverlay key) | No debug markers on canvas |
| 3.4.4.4 | Debug overlay renders AFTER selection border | Render with selectedPanelId + showDebugOverlay | Selection border drawn, then debug markers on top |
| 3.4.4.5 | Debug overlay renders BEFORE blend-mode overlay | Render with overlayState + showDebugOverlay | Debug markers drawn, then overlay on top |
| 3.4.4.6 | Debug overlay renders BEFORE title | Render with titleStyle + titleRuns + showDebugOverlay | Debug markers drawn, then title on top |
| 3.4.4.7 | Full pipeline: clear → bg → panels → hover → selection → debug → overlay → title | All options provided | All layers rendered in correct order |
| 3.4.4.8 | Debug overlay with no focus points → center markers only | showDebugOverlay: true, focusPoints: empty Map | Red center dots drawn for each panel, no green circles |
| 3.4.4.9 | Debug overlay survives render cycle | Call render twice with same state | Both renders produce identical output |
| 3.4.4.10 | Toggle debug overlay on/off on same canvas | Render without, then with, then without | Markers appear only on the with-debug render |
| 3.4.4.11 | Debug overlay with selected panel → highlighted markers | selectedPanelId set + showDebugOverlay | Selected panel's debug markers use thicker lines/brighter colors |
| 3.4.4.12 | Debug overlay with hovered panel → highlighted markers | hoveredPanelId set + showDebugOverlay | Hovered panel's debug markers visually distinct |

**Debug Overlay Factory**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.4.4.13 | createDebugOverlay returns render method | `createDebugOverlay()` | Returns object with `render` function |
| 3.4.4.14 | Factory render is compatible with assembler pipeline | `overlay.render(ctx, options)` | No crash, renders correctly |

**Estimated integration tests: 14**

#### 3.4.5 Test Scenarios (State Management)

**CollageState Extension**

The state needs a `showDebugOverlay` boolean and a `focusPoints` Map.

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.4.5.1 | New state has showDebugOverlay = false | `createCollageState()` | `state.showDebugOverlay === false` |
| 3.4.5.2 | Toggle showDebugOverlay to true | `state.showDebugOverlay = true` | `state.showDebugOverlay === true` |
| 3.4.5.3 | Toggle showDebugOverlay back to false | `state.showDebugOverlay = false` | `state.showDebugOverlay === false` |
| 3.4.5.4 | FocusPoints Map exists on state | `createCollageState()` | `state.focusPoints` is a `Map` or null |
| 3.4.5.5 | FocusPoints Map can be populated | `state.focusPoints.set(0, {x:0.3, y:0.4})` | Map contains entry |
| 3.4.5.6 | FocusPoints Map keyed by image index | Set focusPoint for image index 0 and 2 | Both entries accessible |

**Export Safety**

The most critical integration requirement: the debug overlay must **never** appear in exported JPEGs. The `ExportManager.exportToJpeg()` function must NOT pass `showDebugOverlay` or `focusPoints` to the assembler's render call.

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.4.5.7 | Export with showDebugOverlay = true → no debug markers | `exportToJpeg(assembler, state, 0.92)` where `state.showDebugOverlay = true` | Exported canvas has no debug markers |
| 3.4.5.8 | Export renderData does not include showDebugOverlay | Intercept assembler.render call during export | `renderData.showDebugOverlay` is `undefined` or `false` |
| 3.4.5.9 | Export renderData does not include focusPoints | Intercept assembler.render call during export | `renderData.focusPoints` is `undefined` |
| 3.4.5.10 | Export with focusPoints on state → still no debug markers | State has populated focusPoints Map | No debug markers in export |
| 3.4.5.11 | Export follows same pattern as selection/hover stripping | Compare export code | `showDebugOverlay` handled same way as `selectedPanelId: null` |

**Estimated state/export tests: 11**

#### 3.4.6 E2E Test Scenarios (Playwright)

**Test file**: `test/e2e/saliency-debug-overlay.spec.js` (new).

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.4.6.1 | Debug overlay toggle exists in UI | Load app, inspect toolbar | Toggle element with `data-testid="debug-overlay-toggle"` or similar |
| 3.4.6.2 | Toggle on → markers visible | Upload image, enable debug overlay | Canvas shows green circle and red dot (verify via screenshot comparison) |
| 3.4.6.3 | Toggle off → markers hidden | Enable then disable debug overlay | Canvas shows no debug markers |
| 3.4.6.4 | Default state: debug overlay off | Fresh page load | No debug markers visible |
| 3.4.6.5 | Multiple images → markers for each panel | Upload 3 images, enable debug | Markers visible on all 3 panels |
| 3.4.6.6 | Layout change preserves debug toggle state | Enable debug, switch layout | Toggle remains enabled, markers reappear for new layout |
| 3.4.6.7 | Export does not include debug markers | Enable debug, click Export, inspect downloaded file | Downloaded JPEG has no green circles or red dots |
| 3.4.6.8 | Debug overlay does not interfere with panel selection | Enable debug, click panel | Panel selection works normally, selection border visible |
| 3.4.6.9 | Debug overlay does not interfere with crop interaction | Enable debug, drag crop handle | Crop interaction works normally |
| 3.4.6.10 | Debug overlay with hero layout | Upload 3 images, hero layout, enable debug | Markers visible on hero + side panels |
| 3.4.6.11 | Debug overlay with hexagonal layout | Upload 7 images, hexagonal layout, enable debug | Markers visible on all hexagonal panels |
| 3.4.6.12 | Debug overlay keyboard toggle (if implemented) | Enable/disable via keyboard shortcut | Toggle state changes, markers appear/disappear |
| 3.4.6.13 | No crash with debug overlay + overlay blend mode | Enable both debug overlay and blend-mode overlay | Both render correctly, no canvas corruption |
| 3.4.6.14 | No crash with debug overlay + title | Enable both debug overlay and title | Both render correctly, no canvas corruption |
| 3.4.6.15 | Shift vector visible when focus differs from center | Upload image with off-center saliency, enable debug | Dashed green line visible between red dot and green circle |
| 3.4.6.16 | No shift vector when saliency uses center fallback | Upload image with center fallback, enable debug | Red dot and green circle overlap, no shift line |

**Estimated E2E tests: 16**

#### 3.4.7 Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | 3.4.2.1–3.4.2.15 (Coordinate math), 3.4.5.7–3.4.5.11 (Export safety), 3.4.6.7 (E2E export) | Core correctness: wrong coordinates = useless debug overlay. Export contamination is a hard requirement — must never leak debug markers into user exports. |
| **P1** | 3.4.2.16–3.4.2.58 (Center, markers, validation, constants), 3.4.3.1–3.4.3.17 (Canvas rendering), 3.4.4.1–3.4.4.10 (Assembler integration) | Structural correctness: all rendering paths, marker computation, and pipeline integration. |
| **P2** | 3.4.3.18–3.4.3.45 (Positioning, styles, edge cases, DPR), 3.4.4.11–3.4.4.14 (Highlighting, factory), 3.4.5.1–3.4.5.6 (State), 3.4.6.1–3.4.6.6, 3.4.6.8–3.4.6.16 (E2E) | Polish, edge-case robustness, DPR scaling, and E2E workflow verification. |

#### 3.4.8 Known Behaviors to Document

1. **Debug overlay is a dev-only feature**: It has no user-facing value and is intended solely for developers tuning ML saliency parameters. It should be hidden behind a developer toggle or keyboard shortcut, not a prominent UI button.

2. **No debug overlay in exports**: The `ExportManager.exportToJpeg()` function explicitly omits `showDebugOverlay` and `focusPoints` from the assembler render call, ensuring debug markers are never rendered into exported JPEGs. This mirrors the existing pattern of stripping `selectedPanelId: null` and `hoveredPanelId: null` from export render data.

3. **Focus point normalization**: All focus points are stored as `{x, y}` normalized to [0, 1] relative to the source image dimensions. The debug overlay's coordinate transformation converts these to canvas pixel coordinates using the crop's source and destination rectangles.

4. **Both markers drawn even when they overlap**: When the focal point coincides with the image center (e.g., `{x: 0.5, y: 0.5}`), both the green circle and red dot are drawn at the same position. The green circle is drawn first, then the red dot on top, so the red dot may partially obscure the green circle. This is intentional — it visually confirms that the focal point equals the center. The shift vector line is suppressed when the two points coincide (zero-length).

5. **No debug markers for panels without images**: If a panel has no assigned image (e.g., more panels than images), no markers are drawn for that panel. This prevents rendering artifacts for empty slots.

6. **Invalid focus points silently skipped**: If a focus point has NaN, Infinity, or values outside [0, 1], the green focal point marker is skipped. The red center dot is still drawn (since it doesn't depend on the focus point).

7. **Debug overlay renders outside panel clips**: Unlike the PanelRenderer which clips each panel to its geometry before drawing, the debug overlay renders directly on the canvas without clipping. Markers may appear outside panel boundaries if the crop/panel geometry produces unusual coordinates.

8. **Debug overlay does not persist across page refresh**: The `showDebugOverlay` toggle is not persisted to `localStorage`. Each page load starts with the overlay disabled.

9. **DPR-aware marker sizing**: Marker radii are divided by `devicePixelRatio` before drawing, ensuring markers appear at consistent screen-pixel sizes regardless of display resolution. A 6px focal point circle appears the same physical size on a 1x display and a 3x Retina display.

10. **Shift vector visualization**: A dashed green line connects the red center dot to the green focal point, visually communicating the crop shift magnitude and direction. The line is omitted when the two points coincide (zero-length vector). This is the primary diagnostic element for tuning saliency — developers can immediately see whether the ML is pulling the crop too aggressively toward an edge.

11. **Hover/selection highlighting**: When a panel is hovered or selected, its debug overlay elements (crop box, shift vector) use thicker lines or brighter colors to distinguish them from other panels' overlays. This helps developers focus on one panel at a time in complex collages.

#### 3.4.9 Total Test Count Summary

| Category | Count |
|----------|-------|
| Pure function tests (coordinate math, marker computation, validation, constants) | 58 |
| Canvas rendering tests (offscreen canvas: drawing, positioning, styles, edge cases, DPR) | 45 |
| Integration tests (CollageAssembler pipeline, factory) | 14 |
| State management tests | 6 |
| Export safety tests | 5 |
| E2E tests (Playwright) | 16 |
| **Total** | **144** |

### 3.5 Responsive Design

- **Description**: Adapting the CollageMaker UI for mobile and tablet screens via CSS media queries, touch gesture handling, and viewport-aware layout adjustments. The feature includes three responsive tiers: desktop (≥1200px), tablet (768–1199px), and mobile (<768px). At tablet width, sidebars collapse to overlay/drawer mode. At mobile width, the three-panel layout stacks vertically with the canvas on top. Touch gestures leverage the existing pointer event infrastructure (which already handles touch on modern browsers) but require `touch-action` CSS tuning and minimum touch target sizes.
- **User Impact**: Medium. Enables usage on tablets and phones, expanding the addressable audience.
- **Effort**: Medium. Requires `Style.css` media queries, a responsive layout utility module, and touch-action CSS adjustments. No new interaction modules needed since pointer events handle both mouse and touch.
- **Dependencies**: None. Independent of ML Saliency, Debug Overlay, and PWA features.
- **Risk**: Low. CSS changes are additive and scoped to media queries. Pointer events already support touch on all modern browsers.
- **Recommendation**: **Nice-to-have (Deferred)**. The complex nature of canvas manipulation is better suited for desktop-first MVP.
- **Implementation Outline** (for future reference):
  - Create `MyESModules/Utils/ResponsiveUtils.js` — pure functions for breakpoint detection, sidebar config, touch target math
  - Add media queries to `Style.css` for mobile (<768px) and tablet (<1200px) breakpoints
  - Stack sidebars below canvas on narrow screens (flex-direction: column)
  - Overlay/drawer mode for sidebars at tablet width
  - Apply `touch-action: none` to canvas elements to prevent browser gesture interference
  - Enforce 44x44px minimum touch targets via CSS in mobile media queries
  - Ensure viewport meta tag includes `width=device-width, initial-scale=1.0` (no `user-scalable=no`)

#### 3.5.1 Recommended Module Interface (for testability)

A new module `MyESModules/Utils/ResponsiveUtils.js` provides pure functions and constants for responsive layout calculations. This follows the project convention of extracting pure math/logic from DOM-dependent code.

```javascript
// MyESModules/Utils/ResponsiveUtils.js

// Breakpoint constants (in CSS pixels)
export const BREAKPOINTS = {
    MOBILE: 768,       // < 768px: stacked layout
    TABLET: 1200,      // < 1200px: sidebar overlay mode
};

// Touch target minimums (WCAG 2.5.5 / Apple HIG)
export const TOUCH_TARGET = {
    MIN_SIZE: 44,      // 44x44px minimum touch target
    RECOMMENDED_SIZE: 48,
};

// Sidebar configuration per breakpoint tier
export const SIDEBAR_CONFIG = {
    DESKTOP: { width: 260, min: 200, max: 350, mode: 'inline' },
    TABLET: { width: 0, min: 0, max: 0, mode: 'overlay' },
    MOBILE: { width: 0, min: 0, max: 0, mode: 'stacked' },
};

// Pure functions (testable without browser context)
export function getLayoutTier(viewportWidth) { /* returns 'mobile' | 'tablet' | 'desktop' */ }
export function getSidebarConfig(viewportWidth) { /* returns sidebar config object */ }
export function getCanvasMaxDimensions(viewportWidth, viewportHeight, tierConfig) { /* returns {maxWidth, maxHeight} */ }
export function hasResponsiveClass(classList, expectedClass) { /* validates CSS class presence */ }
export function computeTouchPadding(baseWidth, baseHeight) { /* ensures 44x44px minimum */ }
export function isStackedLayout(viewportWidth) { /* returns boolean */ }
export function isOverlaySidebar(viewportWidth) { /* returns boolean */ }
```

Key design decisions:
- **Constants first**: `BREAKPOINTS`, `TOUCH_TARGET`, `SIDEBAR_CONFIG` are exported as plain objects, enabling tests to validate values and future CSS changes to reference the same constants
- **Pure functions**: All layout calculations are pure, testable without browser context. The actual CSS media queries should mirror these breakpoint values
- **Tier-based logic**: Three tiers (`mobile`, `tablet`, `desktop`) provide clear breakpoints for both CSS and JS logic
- **Touch target math**: `computeTouchPadding` ensures interactive elements meet WCAG 2.5.5 minimum touch target size

#### 3.5.2 Test Scenarios (Unit Tests — Pure Functions)

**Test file**: `MyComponents/ResponsiveUtilsTest.html` (new).

**Breakpoint Constants Validation**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.5.2.1 | BREAKPOINTS has MOBILE and TABLET keys | `BREAKPOINTS` | Both keys present with numeric values |
| 3.5.2.2 | MOBILE breakpoint is 768 | `BREAKPOINTS.MOBILE` | `768` |
| 3.5.2.3 | TABLET breakpoint is 1200 | `BREAKPOINTS.TABLET` | `1200` |
| 3.5.2.4 | MOBILE < TABLET | `BREAKPOINTS.MOBILE < BREAKPOINTS.TABLET` | `true` |
| 3.5.2.5 | TOUCH_TARGET.MIN_SIZE is 44 | `TOUCH_TARGET.MIN_SIZE` | `44` |
| 3.5.2.6 | TOUCH_TARGET.RECOMMENDED_SIZE >= MIN_SIZE | `TOUCH_TARGET` | `48 >= 44` |
| 3.5.2.7 | SIDEBAR_CONFIG has all three tiers | `SIDEBAR_CONFIG` | Has `DESKTOP`, `TABLET`, `MOBILE` keys |
| 3.5.2.8 | DESKTOP sidebar mode is 'inline' | `SIDEBAR_CONFIG.DESKTOP.mode` | `'inline'` |
| 3.5.2.9 | TABLET sidebar mode is 'overlay' | `SIDEBAR_CONFIG.TABLET.mode` | `'overlay'` |
| 3.5.2.10 | MOBILE sidebar mode is 'stacked' | `SIDEBAR_CONFIG.MOBILE.mode` | `'stacked'` |
| 3.5.2.11 | DESKTOP sidebar width > 0 | `SIDEBAR_CONFIG.DESKTOP.width` | `260` |
| 3.5.2.12 | TABLET sidebar width = 0 (overlay) | `SIDEBAR_CONFIG.TABLET.width` | `0` |
| 3.5.2.13 | MOBILE sidebar width = 0 (stacked) | `SIDEBAR_CONFIG.MOBILE.width` | `0` |

**Layout Tier Detection (`getLayoutTier`)**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.5.2.14 | Width 1920 → desktop | `getLayoutTier(1920)` | `'desktop'` |
| 3.5.2.15 | Width 1400 → desktop | `getLayoutTier(1400)` | `'desktop'` |
| 3.5.2.16 | Width 1200 → desktop (boundary inclusive) | `getLayoutTier(1200)` | `'desktop'` |
| 3.5.2.17 | Width 1199 → tablet | `getLayoutTier(1199)` | `'tablet'` |
| 3.5.2.18 | Width 1000 → tablet | `getLayoutTier(1000)` | `'tablet'` |
| 3.5.2.19 | Width 768 → tablet (boundary inclusive) | `getLayoutTier(768)` | `'tablet'` |
| 3.5.2.20 | Width 767 → mobile | `getLayoutTier(767)` | `'mobile'` |
| 3.5.2.21 | Width 375 → mobile (iPhone SE) | `getLayoutTier(375)` | `'mobile'` |
| 3.5.2.22 | Width 320 → mobile (small phone) | `getLayoutTier(320)` | `'mobile'` |
| 3.5.2.23 | Width 0 → mobile | `getLayoutTier(0)` | `'mobile'` |
| 3.5.2.24 | Width 2560 → desktop (QHD) | `getLayoutTier(2560)` | `'desktop'` |
| 3.5.2.25 | Width 3840 → desktop (4K) | `getLayoutTier(3840)` | `'desktop'` |

**Sidebar Config Selection (`getSidebarConfig`)**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.5.2.26 | Desktop width → inline config | `getSidebarConfig(1400)` | `{ width: 260, mode: 'inline' }` |
| 3.5.2.27 | Tablet width → overlay config | `getSidebarConfig(900)` | `{ width: 0, mode: 'overlay' }` |
| 3.5.2.28 | Mobile width → stacked config | `getSidebarConfig(400)` | `{ width: 0, mode: 'stacked' }` |
| 3.5.2.29 | Width 1200 → inline (boundary) | `getSidebarConfig(1200)` | `{ width: 260, mode: 'inline' }` |
| 3.5.2.30 | Width 768 → overlay (boundary) | `getSidebarConfig(768)` | `{ width: 0, mode: 'overlay' }` |
| 3.5.2.31 | Config includes min/max for desktop | `getSidebarConfig(1400)` | `min: 200, max: 350` |
| 3.5.2.32 | Config min/max = 0 for non-desktop | `getSidebarConfig(400)` | `min: 0, max: 0` |

**Canvas Dimension Calculation (`getCanvasMaxDimensions`)**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.5.2.33 | Desktop: full width minus sidebars | vw: 1400, vh: 900, tier: desktop | `maxWidth ≈ 880` (1400 - 260 - 260) |
| 3.5.2.34 | Tablet: full width (sidebars overlay) | vw: 900, vh: 600, tier: tablet | `maxWidth ≈ 900 - padding` |
| 3.5.2.35 | Mobile: full width (stacked) | vw: 400, vh: 700, tier: mobile | `maxWidth ≈ 400 - padding` |
| 3.5.2.36 | Height constraint applied | vw: 1400, vh: 400, tier: desktop | `maxHeight < 400` (toolbar + padding subtracted) |
| 3.5.2.37 | Very narrow viewport | vw: 320, vh: 568, tier: mobile | Positive dimensions, no NaN |
| 3.5.2.38 | Very tall viewport | vw: 400, vh: 900, tier: mobile | Positive dimensions |
| 3.5.2.39 | Ultra-wide viewport | vw: 3840, vh: 2160, tier: desktop | Large positive dimensions |
| 3.5.2.40 | Square viewport | vw: 800, vh: 800, tier: tablet | Positive, reasonable dimensions |

**Touch Target Math (`computeTouchPadding`)**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.5.2.41 | Already meets minimum (48x48) | `computeTouchPadding(48, 48)` | `padding: 0, finalWidth: 48, finalHeight: 48` |
| 3.5.2.42 | Below minimum (32x32) | `computeTouchPadding(32, 32)` | `padding: 6, finalWidth: 44, finalHeight: 44` |
| 3.5.2.43 | Width OK, height below (44x30) | `computeTouchPadding(44, 30)` | `finalHeight >= 44` |
| 3.5.2.44 | Height OK, width below (30x44) | `computeTouchPadding(30, 44)` | `finalWidth >= 44` |
| 3.5.2.45 | Both below minimum (20x20) | `computeTouchPadding(20, 20)` | `finalWidth >= 44, finalHeight >= 44` |
| 3.5.2.46 | Zero-size input | `computeTouchPadding(0, 0)` | `finalWidth >= 44, finalHeight >= 44` |
| 3.5.2.47 | One dimension already large (100x10) | `computeTouchPadding(100, 10)` | `finalWidth: 100, finalHeight >= 44` |
| 3.5.2.48 | Fractional input (33.5x33.5) | `computeTouchPadding(33.5, 33.5)` | `finalWidth >= 44, finalHeight >= 44` |

**Boolean Helpers (`isStackedLayout`, `isOverlaySidebar`)**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.5.2.49 | isStackedLayout at 375 | `isStackedLayout(375)` | `true` |
| 3.5.2.50 | isStackedLayout at 767 | `isStackedLayout(767)` | `true` |
| 3.5.2.51 | isStackedLayout at 768 | `isStackedLayout(768)` | `false` |
| 3.5.2.52 | isStackedLayout at 1400 | `isStackedLayout(1400)` | `false` |
| 3.5.2.53 | isOverlaySidebar at 900 | `isOverlaySidebar(900)` | `true` |
| 3.5.2.54 | isOverlaySidebar at 1199 | `isOverlaySidebar(1199)` | `true` |
| 3.5.2.55 | isOverlaySidebar at 1200 | `isOverlaySidebar(1200)` | `false` |
| 3.5.2.56 | isOverlaySidebar at 400 | `isOverlaySidebar(400)` | `false` (mobile is stacked, not overlay) |

**Responsive Class Validation (`hasResponsiveClass`)**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.5.2.57 | Class present in list | `hasResponsiveClass('sidebar responsive-tablet', 'responsive-tablet')` | `true` |
| 3.5.2.58 | Class not present | `hasResponsiveClass('sidebar', 'responsive-tablet')` | `false` |
| 3.5.2.59 | Empty class list | `hasResponsiveClass('', 'responsive-tablet')` | `false` |
| 3.5.2.60 | Whitespace-only class list | `hasResponsiveClass('   ', 'responsive-tablet')` | `false` |
| 3.5.2.61 | Partial match rejected | `hasResponsiveClass('responsive-tablet-extra', 'responsive-tablet')` | `false` |
| 3.5.2.62 | Multiple classes, target in middle | `hasResponsiveClass('a responsive-mobile b', 'responsive-mobile')` | `true` |

**Estimated pure function tests: 62**

#### 3.5.3 Test Scenarios (Unit Tests — CSS/DOM Validation)

**Test file**: `MyComponents/ResponsiveCSSValidationTest.html` (new).

These tests validate CSS media query behavior by fetching `Style.css` and `index.html`, parsing them, and verifying responsive rules. Follows the `LandingPageTest.html` pattern of `fetch()` + `DOMParser`.

**Media Query Presence and Structure**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.5.3.1 | Style.css contains `@media` rules | Fetch `Style.css`, parse text | At least one `@media` block present |
| 3.5.3.2 | Media query for mobile breakpoint (768px) | CSS text contains `768px` | `max-width: 767px` or `max-width: 768px` rule exists |
| 3.5.3.3 | Media query for tablet breakpoint (1200px) | CSS text contains `1200px` | `max-width: 1199px` or `max-width: 1200px` rule exists |
| 3.5.3.4 | `.main-layout` has responsive override | CSS text in mobile media query | `.main-layout` or `#mainLayout` targeted with `flex-direction: column` |
| 3.5.3.5 | `.sidebar` has responsive override | CSS text in tablet/mobile media query | `.sidebar` width overridden (0 or hidden) |
| 3.5.3.6 | `.canvas-area` responsive rules | CSS text in mobile media query | Canvas area width adjusted for stacked layout |
| 3.5.3.7 | Toolbar responsive rules | CSS text in mobile media query | `.collage-toolbar` adjusted for narrow screens |

**Viewport Meta Tag Validation**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.5.3.8 | Viewport meta tag exists | Parse `index.html` | `<meta name="viewport" ...>` present |
| 3.5.3.9 | Viewport has `width=device-width` | Viewport meta `content` attribute | Contains `width=device-width` |
| 3.5.3.10 | Viewport has `initial-scale=1.0` | Viewport meta `content` attribute | Contains `initial-scale=1` or `initial-scale=1.0` |
| 3.5.3.11 | Viewport does NOT prevent zoom | Viewport meta `content` attribute | Does NOT contain `user-scalable=no` or `maximum-scale=1` |
| 3.5.3.12 | Viewport has `viewport-fit=cover` (for notched devices) | Viewport meta `content` attribute | May or may not contain `viewport-fit=cover` |

**Touch Target Size Validation (CSS-based)**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.5.3.13 | `.remove-btn` has min 44x44px touch target | CSS in mobile media query | `min-width: 44px` and `min-height: 44px` or equivalent padding |
| 3.5.3.14 | `.toolbar-icon-btn` has min 44x44px | CSS in mobile media query | `min-width: 44px` and `min-height: 44px` |
| 3.5.3.15 | `.pure-button` has min 44px height | CSS in mobile media query | `min-height: 44px` |
| 3.5.3.16 | `.segment-btn` has min 44px height | CSS in mobile media query | `min-height: 44px` |
| 3.5.3.17 | `.format-btn` has min 44x44px | CSS in mobile media query | `min-width: 44px` and `min-height: 44px` |
| 3.5.3.18 | `.image-item` has min 44px height | CSS in mobile media query | `min-height: 44px` |
| 3.5.3.19 | `.reset-crop-btn` has min 44px height | CSS in mobile media query | `min-height: 44px` |
| 3.5.3.20 | `.export-btn` has min 44px height | CSS in mobile media query | `min-height: 44px` |

**Sidebar Responsive Behavior**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.5.3.21 | Sidebar hidden/overlay at tablet width | CSS `@media (max-width: 1199px)` | `.sidebar` or `.sidebar-left` width set to 0 or `display: none` |
| 3.5.3.22 | Sidebar hidden/overlay at mobile width | CSS `@media (max-width: 767px)` | Both sidebars hidden or overlay |
| 3.5.3.23 | `.sidebar-collapsed` class still works | CSS `.sidebar-collapsed` rule | Width 0, overflow hidden (unaffected by media queries) |
| 3.5.3.24 | Sidebar toggle button visible at all breakpoints | CSS | `#sidebarToggleBtn` or `.toolbar-icon-btn` not hidden |

**Canvas Scaling Behavior**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.5.3.25 | `#previewCanvas` has `max-width: 100%` | CSS `#previewCanvas` rule | `max-width: 100%` present (already in current CSS) |
| 3.5.3.26 | `#previewCanvas` has `max-height: 100%` | CSS `#previewCanvas` rule | `max-height: 100%` present (already in current CSS) |
| 3.5.3.27 | Canvas container responsive at mobile | CSS mobile media query | `.canvas-container` or `.canvas-area` width adjusted |
| 3.5.3.28 | Crop preview canvas responsive | CSS mobile media query | `.crop-preview-canvas` sizing adjusted for narrow screens |

**Touch-Action CSS**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.5.3.29 | `#previewCanvas` has `touch-action: none` or `manipulation` | CSS `#previewCanvas` rule | `touch-action` property set to prevent browser gestures |
| 3.5.3.30 | `.crop-preview-canvas` has `touch-action: none` | CSS `.crop-preview-canvas` rule | `touch-action: none` to prevent scroll during crop drag |
| 3.5.3.31 | `.image-library` allows scroll | CSS `.image-library` rule | `touch-action: pan-y` or default (allows vertical scroll) |
| 3.5.3.32 | `.sidebar-scroll-container` allows scroll | CSS `.sidebar-scroll-container` rule | `touch-action: pan-y` or default |

**Estimated CSS/DOM validation tests: 32**

#### 3.5.4 Test Scenarios (Unit Tests — Pointer Event Compatibility)

**Test file**: `MyComponents/ResponsivePointerEventsTest.html` (new).

These tests verify that the existing pointer event handlers work correctly with touch events. Since modern browsers fire `pointerdown`/`pointermove`/`pointerup` for both mouse and touch, the existing `GestureHandler` and `CropInteraction` should work without modification. These tests validate that assumption.

**GestureHandler Touch Compatibility**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.5.4.1 | `pointerdown` from touch triggers panel selection | PointerEvent with `pointerType: 'touch'` | `_onPointerDown` processes event, calls `onPanelSelected` |
| 3.5.4.2 | `pointermove` from touch triggers hover | PointerEvent with `pointerType: 'touch'` | `_onPointerMove` processes event |
| 3.5.4.3 | `pointerleave` from touch clears hover | Simulate pointer leave | `lastHoveredPanelId` set to null |
| 3.5.4.4 | Touch pointer has `isPrimary` = true | PointerEvent with `isPrimary: true` | Event is processed (not filtered out) |
| 3.5.4.5 | Multi-touch secondary pointer ignored | PointerEvent with `isPrimary: false` | Event is ignored or handled gracefully |
| 3.5.4.6 | `screenToCanvas` works with touch coordinates | PointerEvent from touch with clientX/clientY | Returns valid canvas coordinates |
| 3.5.4.7 | Hit test works with touch coordinates | Touch pointer event on canvas | `hitTestPanel` returns correct panel ID |

**CropInteraction Touch Compatibility**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.5.4.8 | `pointerdown` from touch starts crop drag | PointerEvent with `pointerType: 'touch'` | `isDragging = true` |
| 3.5.4.9 | `pointermove` from touch updates crop | PointerEvent with `pointerType: 'touch'` | Crop region updated |
| 3.5.4.10 | `pointerup` from touch ends crop drag | PointerEvent with `pointerType: 'touch'` | `isDragging = false` |
| 3.5.4.11 | `setPointerCapture` works with touch | PointerEvent with valid `pointerId` | Canvas captures pointer |
| 3.5.4.12 | Corner resize works with touch | Touch pointer on corner handle | `isResizing = true`, `resizeCorner` set |

**Estimated pointer event compatibility tests: 12**

#### 3.5.5 Test Scenarios (Integration — Responsive State)

**Test file**: Same `MyComponents/ResponsiveUtilsTest.html` (integration section).

**Responsive State in CollageState**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.5.5.1 | State has `layoutTier` property | `createCollageState()` | `state.layoutTier` exists |
| 3.5.5.2 | Initial `layoutTier` is 'desktop' | `createCollageState()` | `state.layoutTier === 'desktop'` |
| 3.5.5.3 | `layoutTier` updates on resize | Set `layoutTier` to `'mobile'` | `state.layoutTier === 'mobile'` |
| 3.5.5.4 | `layoutTier` change triggers re-render | Change tier, check render scheduled | `_scheduleRender` called |
| 3.5.5.5 | Sidebar open state preserved across tier change | `rightSidebarOpen: true`, change tier | `rightSidebarOpen` value unchanged |
| 3.5.5.6 | Sidebar auto-closed at tablet/mobile | Tier changes to tablet/mobile | Sidebar overlay logic handles open state |
| 3.5.5.7 | Crop interaction disabled in stacked mode | Tier: 'mobile', crop panel selected | Crop interaction gracefully disabled or adapted |
| 3.5.5.8 | Gesture handler re-attaches after tier change | Tier changes, gesture handler active | Pointer events still functional |

**Responsive Resize Handler**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.5.5.9 | Window resize updates layout tier | Dispatch `resize` event | `layoutTier` updated to match new width |
| 3.5.5.10 | Rapid resize events debounced | 10 rapid `resize` events | Layout tier updated once (debounced) or last value wins |
| 3.5.5.11 | Resize handler cleaned up on unmount | `beforeUnmount()` called | `resize` listener removed |
| 3.5.5.12 | Orientation change triggers resize | Dispatch `orientationchange` → `resize` | Layout tier updated |

**Estimated integration tests: 12**

#### 3.5.6 E2E Test Scenarios (Playwright)

**Test file**: `test/e2e/responsive-design.spec.js` (new).

**Viewport Emulation — Desktop**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.5.6.1 | Desktop layout at 1920px viewport | `page.setViewportSize({width: 1920, height: 1080})` | Three-panel layout visible, both sidebars present |
| 3.5.6.2 | Desktop layout at 1400px viewport | `page.setViewportSize({width: 1400, height: 900})` | Three-panel layout, sidebars visible |
| 3.5.6.3 | Desktop layout at 1200px (boundary) | `page.setViewportSize({width: 1200, height: 800})` | Three-panel layout, sidebars visible |
| 3.5.6.4 | Canvas visible and interactive at desktop | Desktop viewport, upload images | Canvas renders, clicking selects panels |

**Viewport Emulation — Tablet**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.5.6.5 | Tablet layout at 1199px (boundary) | `page.setViewportSize({width: 1199, height: 800})` | Sidebar in overlay mode or hidden |
| 3.5.6.6 | Tablet layout at 900px | `page.setViewportSize({width: 900, height: 600})` | Canvas takes primary space, sidebars overlay |
| 3.5.6.7 | Tablet layout at 768px (boundary) | `page.setViewportSize({width: 768, height: 1024})` | Tablet behavior, not mobile |
| 3.5.6.8 | Canvas interactive at tablet | Tablet viewport, upload images | Canvas renders, pointer events work |

**Viewport Emulation — Mobile**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.5.6.9 | Mobile layout at 767px (boundary) | `page.setViewportSize({width: 767, height: 1024})` | Stacked layout, canvas on top |
| 3.5.6.10 | Mobile layout at 375px (iPhone SE) | `page.setViewportSize({width: 375, height: 667})` | Stacked layout, all elements visible |
| 3.5.6.11 | Mobile layout at 320px (small phone) | `page.setViewportSize({width: 320, height: 568})` | Stacked layout, no horizontal overflow |
| 3.5.6.12 | Canvas interactive at mobile | Mobile viewport, upload images | Canvas renders, touch events work |
| 3.5.6.13 | Toolbar accessible at mobile | Mobile viewport | All toolbar buttons visible and tappable |
| 3.5.6.14 | Image library scrollable at mobile | Mobile viewport, 10+ images | Library scrolls vertically |

**Touch Event Simulation**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.5.6.15 | Tap selects panel on canvas | `page.tap('#previewCanvas')` at tablet/mobile | Panel selected, crop section updates |
| 3.5.6.16 | Tap toolbar button works | `page.tap('#addImagesBtn')` | File chooser opens |
| 3.5.6.17 | Tap layout dropdown works | `page.tap('#layoutStyleSelect')` | Dropdown opens |
| 3.5.6.18 | Scroll in image library works | Touch scroll in `.image-library` | Content scrolls, canvas not affected |
| 3.5.6.19 | No accidental panel selection during scroll | Scroll in sidebar | Canvas panel selection unchanged |

**Layout Transition**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.5.6.20 | Resize from desktop to tablet | Start 1400px, resize to 900px | Layout transitions smoothly, no crash |
| 3.5.6.21 | Resize from tablet to mobile | Start 900px, resize to 375px | Layout transitions to stacked, no crash |
| 3.5.6.22 | Resize from mobile back to desktop | Start 375px, resize to 1400px | Layout transitions back to three-panel |
| 3.5.6.23 | State preserved across resize | Select panel at desktop, resize to mobile | Panel selection state preserved |
| 3.5.6.24 | Images preserved across resize | Upload images at desktop, resize to mobile | Images still visible and selectable |

**Estimated E2E tests: 24**

#### 3.5.7 Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | 3.5.2.14–3.5.2.25 (Layout tier detection), 3.5.2.26–3.5.2.32 (Sidebar config), 3.5.3.1–3.5.3.7 (Media query presence), 3.5.3.8–3.5.3.12 (Viewport meta), 3.5.6.5–3.5.6.14 (Tablet+Mobile E2E) | Core responsive functionality — if these fail, the responsive feature doesn't work. Viewport meta is foundational. |
| **P1** | 3.5.2.1–3.5.2.13 (Constants), 3.5.2.33–3.5.2.40 (Canvas dimensions), 3.5.2.41–3.5.2.48 (Touch targets), 3.5.2.49–3.5.2.62 (Boolean helpers + class validation), 3.5.3.13–3.5.3.20 (Touch target CSS), 3.5.3.29–3.5.3.32 (Touch-action CSS), 3.5.4.1–3.5.4.12 (Pointer event compatibility), 3.5.6.1–3.5.6.4 (Desktop E2E), 3.5.6.15–3.5.6.19 (Touch E2E) | Structural correctness: touch targets, pointer compatibility, CSS touch-action, and touch event simulation. |
| **P2** | 3.5.3.21–3.5.3.28 (Sidebar/canvas CSS details), 3.5.5.1–3.5.5.12 (State integration), 3.5.6.20–3.5.6.24 (Layout transitions) | Integration, state management, and layout transition verification. |

#### 3.5.8 Known Behaviors to Document

1. **Pointer events handle both mouse and touch**: Modern browsers (Chrome, Firefox, Safari, Edge) fire `pointerdown`/`pointermove`/`pointerup` events for both mouse and touch input. The existing `GestureHandler` and `CropInteraction` modules use pointer events exclusively, so they work with touch without modification. No separate `touchstart`/`touchmove` handlers are needed.

2. **`touch-action` CSS is critical for canvas interaction**: Without `touch-action: none` on `#previewCanvas` and `.crop-preview-canvas`, the browser's default touch gestures (scroll, zoom) will interfere with canvas drag operations. The CSS sets `touch-action: none` on canvases to disable browser gestures and let the pointer event handlers take full control.

3. **Scrollable areas retain scroll**: Elements like `.image-library` and `.sidebar-scroll-container` should have `touch-action: pan-y` (or default) to allow vertical scrolling. This prevents the "scroll vs drag" conflict — only the canvas surfaces suppress browser touch gestures.

4. **Three-tier responsive layout**:
   - **Desktop (≥1200px)**: Three-panel flexbox layout, both sidebars visible inline
   - **Tablet (768–1199px)**: Canvas takes primary space, sidebars in overlay/drawer mode (slide in on toggle)
   - **Mobile (<768px)**: Stacked vertical layout — toolbar on top, canvas in middle, sidebars below (or as bottom sheets)

5. **Touch target minimum: 44x44px**: All interactive elements (buttons, image items, remove buttons, format buttons, segmented controls) must have a minimum touch target of 44x44px per WCAG 2.5.5. This is enforced via CSS `min-width`/`min-height` in the mobile media query.

6. **Viewport meta tag**: The `<meta name="viewport">` tag must include `width=device-width, initial-scale=1.0` and must NOT include `user-scalable=no` or `maximum-scale=1` to respect user zoom preferences and accessibility requirements.

7. **No pinch-to-zoom on canvas**: The canvas area does not support pinch-to-zoom. The logical canvas resolution (1920x1080) is fixed; CSS scaling handles display sizing. Pinch gestures on the canvas are consumed by the `touch-action: none` rule.

8. **Sidebar toggle behavior changes by tier**: At desktop, the sidebar toggle button collapses the right sidebar inline. At tablet/mobile, it opens a full-screen overlay or bottom sheet. The `rightSidebarOpen` state property is preserved across tier changes.

9. **Crop interaction adapted for mobile**: The crop preview canvas and corner handles are sized appropriately for touch interaction. Corner handle size (12px in CSS pixels) is increased for mobile via media query to ensure tappable targets.

10. **No virtual keyboard handling in MVP**: When the virtual keyboard appears on mobile (e.g., in the title input or search field), the viewport height changes but the app does not actively adjust layout. CSS `height: 100vh` may cause the bottom of the page to be obscured. This is a known limitation deferred to a future polish pass.

11. **Orientation change behavior**: On mobile devices, rotating from portrait to landscape fires a `resize` event. The responsive handler updates `layoutTier` accordingly. State (selected panel, loaded images) is preserved.

12. **Export resolution unchanged**: Responsive design affects only the display layout. The export resolution remains fixed at 1920x1080 regardless of viewport size. A user on a phone produces the same quality JPEG as a user on a desktop.

#### 3.5.9 Total Test Count Summary

| Category | Count |
|----------|-------|
| Pure function tests (constants, tier detection, sidebar config, canvas dimensions, touch targets, boolean helpers, class validation) | 62 |
| CSS/DOM validation tests (media queries, viewport meta, touch targets, sidebar, canvas, touch-action) | 32 |
| Pointer event compatibility tests (GestureHandler + CropInteraction with touch) | 12 |
| Integration tests (responsive state, resize handler) | 12 |
| E2E tests (Playwright: viewport emulation, touch simulation, layout transitions) | 24 |
| **Total** | **142** |

### 3.6 PWA Capabilities

- **Description**: Enabling offline access and "Install to Desktop" via Service Workers and a Web Manifest. The PWA layer adds an installable app shell cache (cache-first for app assets, network-first for images) and a manifest defining display mode, icons, and theme colors.
- **User Impact**: Medium. Convenient for repeated use; allows standalone window mode without browser chrome.
- **Effort**: Medium. Requires `manifest.json`, `service-worker.js`, and `PWACacheUtils.js` (pure utilities extracted for testability).
- **Dependencies**: Browser PWA support, HTTPS (satisfied by GitHub Pages).
- **Risk**: Medium. Stale cache can serve broken Vue/Canvas rendering code. Cache bloat from user-uploaded images can exhaust storage quota. Subdirectory scoping on GitHub Pages requires careful path handling.
- **Recommendation**: **Nice-to-have (Deferred)**. Not critical for a tool that typically requires online image sources. Progressive enhancement — app works fine without PWA.
- **Implementation Outline** (for future reference):
  - Create `manifest.json` with name, icons (192x192 + 512x512), display: standalone, theme colors
  - Create `MyESModules/Utils/PWACacheUtils.js` — pure functions for cache routing, key computation, manifest validation
  - Implement `service-worker.js` with App Shell caching (cache-first for app assets, network-first for images, passthrough for CDN)
  - Add `<link rel="manifest">`, `<meta name="theme-color">`, and SW registration to `index.html`
  - Implement `beforeinstallprompt` handling with install button in toolbar
  - Cache version management: bump `CACHE_VERSION` to invalidate old caches on deploy

#### 3.6.1 Recommended Module Interface (for testability)

The service worker logic should be split into two parts: **(a)** pure utility functions testable in the browser without a service worker context, and **(b)** the actual `service-worker.js` that uses those utilities.

```javascript
// MyESModules/Utils/PWACacheUtils.js — Pure functions (testable in browser)
export const CACHE_CONFIG = {
    APP_SHELL_CACHE_NAME: 'collagemaker-shell-v1',
    IMAGE_CACHE_NAME: 'collagemaker-images-v1',
    CACHE_VERSION: 1,
    MAX_IMAGE_CACHE_SIZE: 50,
    IMAGE_CACHE_TTL_MS: 7 * 24 * 60 * 60 * 1000, // 7 days
    APP_SHELL_URLS: [ /* all local app assets */ ],
};

// Pure functions
export function isAppShellURL(url) { /* boolean */ }
export function isImageURL(url) { /* boolean, extension-based */ }
export function routeRequest(url) { /* 'shell' | 'images' | 'passthrough' */ }
export function computeCacheKey(url, cacheName) { /* versioned key string */ }
export function getCacheName(type) { /* cache name from type */ }
export function shouldCacheResponse(url, response) { /* status + content-type check */ }
export function validateManifest(manifest) { /* { valid, errors[] } */ }
```

Key design decisions:
- **Pure functions first**: `isAppShellURL`, `isImageURL`, `routeRequest`, `shouldCacheResponse`, `computeCacheKey`, `validateManifest` are all pure and testable without service worker context
- **Config injection**: `CACHE_CONFIG` is a constant that can be overridden in tests
- **Route classification**: Every URL falls into exactly one category: shell (cache-first), images (network-first), or passthrough (no cache)
- **Manifest validation**: Extracted as a pure function so the manifest can be validated in both unit tests and a CI step

#### 3.6.2 Test Scenarios (Unit Tests — Pure Functions)

**Test file**: `MyComponents/PWACacheUtilsTest.html` (new).

**Cache Configuration Constants**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.6.2.1 | `APP_SHELL_CACHE_NAME` contains version | `CACHE_CONFIG.APP_SHELL_CACHE_NAME` | Contains `-v` followed by a number |
| 3.6.2.2 | `IMAGE_CACHE_NAME` contains version | `CACHE_CONFIG.IMAGE_CACHE_NAME` | Contains `-v` followed by a number |
| 3.6.2.3 | `CACHE_VERSION` is positive integer | `CACHE_CONFIG.CACHE_VERSION` | Value >= 1 |
| 3.6.2.4 | `MAX_IMAGE_CACHE_SIZE` is reasonable | `CACHE_CONFIG.MAX_IMAGE_CACHE_SIZE` | Value between 10 and 200 |
| 3.6.2.5 | `IMAGE_CACHE_TTL_MS` is positive | `CACHE_CONFIG.IMAGE_CACHE_TTL_MS` | Value > 0, equals 7 days in ms |
| 3.6.2.6 | `APP_SHELL_URLS` is non-empty | `CACHE_CONFIG.APP_SHELL_URLS` | Array length > 0 |
| 3.6.2.7 | `APP_SHELL_URLS` includes index.html | `CACHE_CONFIG.APP_SHELL_URLS` | Contains `'./index.html'` or `'index.html'` |
| 3.6.2.8 | Shell URLs include all JS modules | `CACHE_CONFIG.APP_SHELL_URLS` | Contains paths for all files in `MyESModules/` |
| 3.6.2.9 | Shell URLs are relative paths | Each URL in `APP_SHELL_URLS` | Starts with `./` or has no protocol |

**`isAppShellURL(url)`**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.6.2.10 | index.html is shell URL | `'./index.html'` | `true` |
| 3.6.2.11 | CSS file is shell URL | `'./Style.css'` | `true` |
| 3.6.2.12 | JS module is shell URL | `'./MyESModules/index.js'` | `true` |
| 3.6.2.13 | Nested JS module is shell URL | `'./MyESModules/Rendering/CanvasRenderer.js'` | `true` |
| 3.6.2.14 | Image file is NOT shell URL | `'https://example.com/photo.jpg'` | `false` |
| 3.6.2.15 | External CDN URL is NOT shell URL | `'https://unpkg.com/vue@3/...'` | `false` |
| 3.6.2.16 | Google Fonts URL is NOT shell URL | `'https://fonts.googleapis.com/...'` | `false` |
| 3.6.2.17 | Empty string is NOT shell URL | `''` | `false` |
| 3.6.2.18 | Null input is NOT shell URL | `null` | `false` |
| 3.6.2.19 | URL with query params not in list | `'./index.html?t=123'` | `false` (exact match required) |

**`isImageURL(url)`**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.6.2.20 | JPEG URL | `'https://example.com/photo.jpg'` | `true` |
| 3.6.2.21 | PNG URL | `'https://example.com/icon.png'` | `true` |
| 3.6.2.22 | WebP URL | `'https://example.com/image.webp'` | `true` |
| 3.6.2.23 | GIF URL | `'https://example.com/anim.gif'` | `true` |
| 3.6.2.24 | SVG URL | `'https://example.com/logo.svg'` | `true` |
| 3.6.2.25 | HTML file | `'./index.html'` | `false` |
| 3.6.2.26 | CSS file | `'./Style.css'` | `false` |
| 3.6.2.27 | JS file | `'./MyESModules/index.js'` | `false` |
| 3.6.2.28 | JSON file | `'./manifest.json'` | `false` |
| 3.6.2.29 | URL with query params | `'https://example.com/photo.jpg?v=2'` | `true` (extension-based) |
| 3.6.2.30 | URL without extension | `'https://example.com/image'` | `false` |
| 3.6.2.31 | Data URL for image | `'data:image/png;base64,...'` | `false` (not a network request) |
| 3.6.2.32 | Blob URL | `'blob:https://example.com/abc123'` | `false` |
| 3.6.2.33 | Empty string | `''` | `false` |
| 3.6.2.34 | Case-insensitive extension | `'https://example.com/photo.JPG'` | `true` |

**`routeRequest(url)`**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.6.2.35 | Shell HTML | `'./index.html'` | `'shell'` |
| 3.6.2.36 | Shell CSS | `'./Style.css'` | `'shell'` |
| 3.6.2.37 | Shell JS | `'./MyESModules/index.js'` | `'shell'` |
| 3.6.2.38 | Image JPEG | `'https://example.com/photo.jpg'` | `'images'` |
| 3.6.2.39 | Image PNG | `'https://example.com/icon.png'` | `'images'` |
| 3.6.2.40 | External CDN JS | `'https://unpkg.com/vue@3/...'` | `'passthrough'` |
| 3.6.2.41 | Google Fonts | `'https://fonts.googleapis.com/...'` | `'passthrough'` |
| 3.6.2.42 | API endpoint | `'https://api.example.com/data'` | `'passthrough'` |
| 3.6.2.43 | Unknown extension | `'https://example.com/file.xyz'` | `'passthrough'` |
| 3.6.2.44 | Empty URL | `''` | `'passthrough'` |
| 3.6.2.45 | Manifest itself | `'./manifest.json'` | `'passthrough'` or `'shell'` (documented) |
| 3.6.2.46 | Service worker itself | `'./service-worker.js'` | `'shell'` |

**`computeCacheKey(url, cacheName)`**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.6.2.47 | Basic cache key | url: `'./index.html'`, cacheName: `'shell-v1'` | Returns string containing url and version |
| 3.6.2.48 | Same URL, different cache names | `'./index.html'` with `'shell-v1'` vs `'images-v1'` | Keys differ |
| 3.6.2.49 | Different URLs produce different keys | `'./index.html'` vs `'./Style.css'` | Keys differ |
| 3.6.2.50 | Key includes version | Any URL | Key contains version number |
| 3.6.2.51 | Key is deterministic | Same inputs called twice | Identical output |
| 3.6.2.52 | URL with query params preserved | `'./index.html?t=1'` | Key contains query string |
| 3.6.2.53 | URL with hash preserved | `'./index.html#section'` | Key contains hash |

**`shouldCacheResponse(url, response)`**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.6.2.54 | 200 OK response | `{ status: 200, headers: { 'content-type': 'text/html' } }` | `true` |
| 3.6.2.55 | 200 OK image | `{ status: 200, headers: { 'content-type': 'image/jpeg' } }` | `true` |
| 3.6.2.56 | 304 Not Modified | `{ status: 304 }` | `false` (no body to cache) |
| 3.6.2.57 | 404 Not Found | `{ status: 404 }` | `false` |
| 3.6.2.58 | 500 Server Error | `{ status: 500 }` | `false` |
| 3.6.2.59 | 403 Forbidden | `{ status: 403 }` | `false` |
| 3.6.2.60 | Redirect (301) | `{ status: 301 }` | `false` |
| 3.6.2.61 | Response with no content-type | `{ status: 200, headers: {} }` | `false` |
| 3.6.2.62 | Null response | `null` | `false` |
| 3.6.2.63 | Response with opaque type (CORS) | `{ type: 'opaque' }` | `false` |

**`getCacheName(type)`**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.6.2.64 | Shell cache name | `'shell'` | Returns `CACHE_CONFIG.APP_SHELL_CACHE_NAME` |
| 3.6.2.65 | Image cache name | `'images'` | Returns `CACHE_CONFIG.IMAGE_CACHE_NAME` |
| 3.6.2.66 | Unknown type | `'unknown'` | Returns `null` or throws |
| 3.6.2.67 | Empty string | `''` | Returns `null` or throws |
| 3.6.2.68 | Null input | `null` | Returns `null` or throws |

**`validateManifest(manifest)`**

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3.6.2.69 | Valid manifest | Complete manifest with all required fields | `{ valid: true, errors: [] }` |
| 3.6.2.70 | Missing `name` | `{ short_name: 'CM', ... }` | `{ valid: false, errors: ['Missing required field: name'] }` |
| 3.6.2.71 | Missing `short_name` | `{ name: 'CollageMaker', ... }` | `{ valid: false, errors: ['Missing required field: short_name'] }` |
| 3.6.2.72 | Missing `start_url` | No `start_url` field | `{ valid: false, errors: ['Missing required field: start_url'] }` |
| 3.6.2.73 | Missing `display` | No `display` field | `{ valid: false, errors: ['Missing required field: display'] }` |
| 3.6.2.74 | Missing `icons` | No `icons` array | `{ valid: false, errors: ['Missing required field: icons'] }` |
| 3.6.2.75 | Empty icons array | `{ icons: [] }` | `{ valid: false, errors: ['icons must have at least 1 entry'] }` |
| 3.6.2.76 | Icon missing src | `{ icons: [{ sizes: '192x192', type: 'image/png' }] }` | `{ valid: false, errors: ['Icon missing src'] }` |
| 3.6.2.77 | Icon missing sizes | `{ icons: [{ src: 'icon.png', type: 'image/png' }] }` | `{ valid: false, errors: ['Icon missing sizes'] }` |
| 3.6.2.78 | Display value invalid | `{ display: 'browser' }` | `{ valid: false, errors: ['display must be standalone or fullscreen'] }` |
| 3.6.2.79 | Valid display standalone | `{ display: 'standalone' }` | `{ valid: true, errors: [] }` |
| 3.6.2.80 | start_url not relative | `{ start_url: 'https://other.com/' }` | `{ valid: false, errors: ['start_url must be relative'] }` |
| 3.6.2.81 | Missing `background_color` | No `background_color` | `{ valid: false, errors: ['Missing recommended field: background_color'] }` |
| 3.6.2.82 | Missing `theme_color` | No `theme_color` | `{ valid: false, errors: ['Missing recommended field: theme_color'] }` |
| 3.6.2.83 | Null manifest | `null` | `{ valid: false, errors: ['Manifest is null'] }` |
| 3.6.2.84 | Non-object manifest | `'string'` | `{ valid: false, errors: ['Manifest must be an object'] }` |
| 3.6.2.85 | name is empty string | `{ name: '' }` | `{ valid: false, errors: ['name must be non-empty'] }` |
| 3.6.2.86 | short_name exceeds 12 chars | `{ short_name: 'CollageMaker12345' }` | `{ valid: false, errors: ['short_name exceeds 12 characters'] }` |
| 3.6.2.87 | Icon has at least 192x192 | `{ icons: [{ src: '192.png', sizes: '192x192' }] }` | `{ valid: true, errors: [] }` |

**Estimated pure function tests: 87**

#### 3.6.3 Test Scenarios (Web Manifest Validation)

**Test file**: `MyComponents/PWAManifestTest.html` (new).

These tests fetch the actual `manifest.json` file and validate its structure, following the `LandingPageTest.html` pattern of `fetch()` + `DOMParser`.

**Required Fields**

| # | Test | Selector | Expected |
|---|------|----------|----------|
| 3.6.3.1 | Manifest file is valid JSON | `fetch('./manifest.json')` + `JSON.parse()` | No parse error |
| 3.6.3.2 | `name` field present | `manifest.name` | Non-empty string |
| 3.6.3.3 | `name` contains "CollageMaker" | `manifest.name` | Contains "CollageMaker" (case-insensitive) |
| 3.6.3.4 | `short_name` field present | `manifest.short_name` | Non-empty string, length <= 12 |
| 3.6.3.5 | `start_url` field present | `manifest.start_url` | String value |
| 3.6.3.6 | `start_url` points to app entry | `manifest.start_url` | Equals `'./index.html'`, `'/'`, or `'index.html'` |
| 3.6.3.7 | `display` field present | `manifest.display` | String value |
| 3.6.3.8 | `display` is valid value | `manifest.display` | One of: `'standalone'`, `'fullscreen'`, `'minimal-ui'` |
| 3.6.3.9 | `icons` field present | `manifest.icons` | Array with length > 0 |
| 3.6.3.10 | `description` field present | `manifest.description` | Non-empty string |

**Icons**

| # | Test | Selector | Expected |
|---|------|----------|----------|
| 3.6.3.11 | At least 2 icon sizes | `manifest.icons.length` | >= 2 |
| 3.6.3.12 | 192x192 icon present | `manifest.icons` | One icon has `sizes` containing `192x192` |
| 3.6.3.13 | 512x512 icon present | `manifest.icons` | One icon has `sizes` containing `512x512` |
| 3.6.3.14 | All icons have `src` | Each icon in `manifest.icons` | `src` is a non-empty string |
| 3.6.3.15 | All icons have `sizes` | Each icon | `sizes` is a non-empty string |
| 3.6.3.16 | All icons have `type` | Each icon | `type` is `'image/png'` or `'image/webp'` |
| 3.6.3.17 | Icon src paths are relative | Each icon `src` | No protocol prefix (`http://`, `https://`) |
| 3.6.3.18 | Icon sizes are valid format | Each icon `sizes` | Matches pattern `\d+x\d+` |
| 3.6.3.19 | 180x180 icon for Apple | `manifest.icons` | One icon has `sizes` containing `180x180` |
| 3.6.3.20 | Icons sorted by size | `manifest.icons` | Sizes in ascending order |

**Theme and Colors**

| # | Test | Selector | Expected |
|---|------|----------|----------|
| 3.6.3.21 | `background_color` present | `manifest.background_color` | Non-empty string |
| 3.6.3.22 | `background_color` is valid hex | `manifest.background_color` | Matches `^#[0-9A-Fa-f]{6}$` |
| 3.6.3.23 | `theme_color` present | `manifest.theme_color` | Non-empty string |
| 3.6.3.24 | `theme_color` is valid hex | `manifest.theme_color` | Matches `^#[0-9A-Fa-f]{6}$` |
| 3.6.3.25 | `theme_color` matches CSS theme | Compare with `Style.css` | Color matches toolbar/background theme |

**Manifest in HTML Link Tag**

| # | Test | Selector | Expected |
|---|------|----------|----------|
| 3.6.3.26 | `<link rel="manifest">` present | `document.querySelector('link[rel="manifest"]')` | Element exists |
| 3.6.3.27 | Manifest href is correct | `link.href` | Points to `manifest.json` |
| 3.6.3.28 | `<meta name="theme-color">` present | `document.querySelector('meta[name="theme-color"]')` | Element exists |
| 3.6.3.29 | Theme color meta matches manifest | `meta.content` vs `manifest.theme_color` | Values match |
| 3.6.3.30 | Apple touch icon meta present | `document.querySelector('link[rel="apple-touch-icon"]')` | Element exists |
| 3.6.3.31 | Apple mobile web app cap | `document.querySelector('meta[name="apple-mobile-web-app-capable"]')` | Content is `'yes'` |

**Estimated manifest validation tests: 31**

#### 3.6.4 Test Scenarios (Service Worker Lifecycle)

**Test file**: `MyComponents/PWACacheUtilsTest.html` (SW lifecycle section) + Playwright E2E.

**Service Worker File Structure**

| # | Test | Method | Expected |
|---|------|--------|----------|
| 3.6.4.1 | `service-worker.js` exists | `fetch('./service-worker.js')` | 200 OK |
| 3.6.4.2 | File is valid JavaScript | Parse with `Function()` | No syntax error |
| 3.6.4.3 | `install` event listener present | File content | Contains `'install'` event handler |
| 3.6.4.4 | `activate` event listener present | File content | Contains `'activate'` event handler |
| 3.6.4.5 | `fetch` event listener present | File content | Contains `'fetch'` event handler |
| 3.6.4.6 | `message` event listener present | File content | Contains `'message'` event handler (for update control) |
| 3.6.4.7 | `skipWaiting()` called | File content | Contains `skipWaiting()` call |
| 3.6.4.8 | `clients.claim()` called | File content | Contains `clients.claim()` call |

**Registration and Lifecycle (Playwright E2E)**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.6.4.9 | Service worker registers on first load | Navigate to app, wait 2s | `navigator.serviceWorker.controller` is not null |
| 3.6.4.10 | Service worker state is 'activated' | After registration | `registration.active.state === 'activated'` |
| 3.6.4.11 | Service worker scope covers app | After registration | `registration.scope` includes `index.html` path |
| 3.6.4.12 | Service worker version matches CACHE_VERSION | Read from SW message | Version matches `CACHE_CONFIG.CACHE_VERSION` |
| 3.6.4.13 | Skip waiting — new SW activates immediately | Update SW, send skip message | New SW becomes active without reload |
| 3.6.4.14 | Clients claim — existing pages get new controller | Update SW, call `clients.claim()` | `navigator.serviceWorker.controller` updates |
| 3.6.4.15 | Unregister works | `registration.unregister()` | Service worker removed |
| 3.6.4.16 | Re-register after unregister | Unregister, then reload page | Service worker re-registers automatically |

**Estimated SW lifecycle tests: 16**

#### 3.6.5 Test Scenarios (Cache Strategy)

**Test file**: `MyComponents/PWACacheUtilsTest.html` (cache strategy section) + Playwright E2E.

**App Shell Cache (Cache-First)**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.6.5.1 | Shell files cached on install | First load, check caches API | `collagemaker-shell-vN` cache exists |
| 3.6.5.2 | index.html cached | Check cache contents | `./index.html` in shell cache |
| 3.6.5.3 | Style.css cached | Check cache contents | `./Style.css` in shell cache |
| 3.6.5.4 | All JS modules cached | Check cache contents | All entries from `APP_SHELL_URLS` in cache |
| 3.6.5.5 | Cache-first: offline returns cached shell | Go offline, request `./index.html` | Returns cached response, status 200 |
| 3.6.5.6 | Cache-first: CSS served from cache offline | Go offline, request `./Style.css` | Returns cached response |
| 3.6.5.7 | Cache-first: JS served from cache offline | Go offline, request `./MyESModules/index.js` | Returns cached response |
| 3.6.5.8 | Cache-first: stale cache served when network fails | Block network, request shell URL | Returns cached version (not error) |
| 3.6.5.9 | Cache-first: network response stored on update | Update a shell file, reload | New version cached, old version replaced |
| 3.6.5.10 | Cache-first: response status validated | Cached response has status 200 | Only 200 responses cached |

**Image Cache (Network-First)**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.6.5.11 | Image cache created on first image request | Load app, upload image | `collagemaker-images-vN` cache exists |
| 3.6.5.12 | Network-first: tries network first | Request image with network available | Network request made, response cached |
| 3.6.5.13 | Network-first: falls back to cache when offline | Go offline, request previously loaded image | Returns cached image |
| 3.6.5.14 | Network-first: does NOT cache failed responses | Request non-existent image | No entry added to image cache |
| 3.6.5.15 | Image cache respects max size | Upload 60 images | Cache contains at most `MAX_IMAGE_CACHE_SIZE` entries |
| 3.6.5.16 | Oldest images evicted first | Fill cache, add new image | Oldest entry removed |
| 3.6.5.17 | Image cache does not cache data URLs | Upload image, check cache | No `data:` URLs in cache |
| 3.6.5.18 | Image cache does not cache blob URLs | Export, check cache | No `blob:` URLs in cache |

**Cache Invalidation on Version Bump**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.6.5.19 | Old shell cache deleted on activation | Bump CACHE_VERSION, reload | Old `shell-v(N-1)` cache deleted |
| 3.6.5.20 | Old image cache deleted on activation | Bump CACHE_VERSION, reload | Old `images-v(N-1)` cache deleted |
| 3.6.5.21 | New cache populated on activation | Bump version, reload | New `shell-vN` cache populated |
| 3.6.5.22 | Unknown caches cleaned on activation | Manually create `random-cache`, reload | `random-cache` deleted |

**Passthrough (No Cache)**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.6.5.23 | CDN requests not cached | Request `https://unpkg.com/vue@3/...` | Network request each time, not in cache |
| 3.6.5.24 | Google Fonts not cached | Request `https://fonts.googleapis.com/...` | Network request each time |
| 3.6.5.25 | Unknown URL scheme passthrough | Request `ws://...` | No caching attempt, no error |

**Estimated cache strategy tests: 25**

#### 3.6.6 Test Scenarios (Integration)

**Test file**: `MyComponents/PWACacheUtilsTest.html` (integration section) + Playwright E2E.

**App Shell + Service Worker Integration**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.6.6.1 | Full app loads from cache on second visit | Load app, hard refresh, go offline | App fully functional offline |
| 3.6.6.2 | Vue app mounts from cached shell | Go offline after first visit | `#app` visible, Vue mounted |
| 3.6.6.3 | Canvas renders from cached shell | Go offline, check canvas | `#previewCanvas` visible |
| 3.6.6.4 | Toolbar buttons functional offline | Go offline, click "Add Images" | File picker opens |
| 3.6.6.5 | Export works offline | Go offline, export collage | Export triggers (uses cached assembler) |
| 3.6.6.6 | Settings persistence works offline | Go offline, change settings, refresh | Settings saved and loaded from localStorage |

**Image Upload + Cache Integration**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.6.6.7 | Upload image online → cached | Upload image while online | Image cached in image cache |
| 3.6.6.8 | Reload offline → image available | Go offline, reload page | Previously uploaded images visible |
| 3.6.6.9 | Upload image offline → fails gracefully | Go offline, try to upload new image | Error handled, existing images still work |
| 3.6.6.10 | Image from file input works offline | Upload from local file while offline | File loaded via FileReader (not network) |

**Update Detection + User Control**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.6.6.11 | Update available notification | Update SW, send message to check | `'UPDATE_AVAILABLE'` message received |
| 3.6.6.12 | Update applied on user action | Receive update notification, click "Update" | New SW activates, page reloads |
| 3.6.6.13 | Update discarded | Receive notification, click "Dismiss" | Old SW remains active |
| 3.6.6.14 | No notification if no update | Reload without changes | No update notification shown |

**Estimated integration tests: 14**

#### 3.6.7 Test Scenarios (Install Prompt)

**Test file**: Playwright E2E in `test/e2e/pwa-capabilities.spec.js`.

**`beforeinstallprompt` Event**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.6.7.1 | Event fires on eligible page | Load app in installable context | `beforeinstallprompt` event captured |
| 3.6.7.2 | Event provides `prompt()` method | Event received | `event.prompt` is a function |
| 3.6.7.3 | Event deferred until user action | Load page, wait 5s | Install button hidden until `beforeinstallprompt` fires |
| 3.6.7.4 | Event not fired if already installed | App already installed | `beforeinstallprompt` does not fire |
| 3.6.7.5 | Event not fired on unsupported browser | Firefox Desktop | `beforeinstallprompt` does not fire (handled gracefully) |

**Install Button Behavior**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.6.7.6 | Install button hidden by default | Page load | Install button not visible |
| 3.6.7.7 | Install button shown after `beforeinstallprompt` | Event fires | Install button becomes visible |
| 3.6.7.8 | Install button triggers `prompt()` | Click install button | `prompt()` called, native install dialog shown |
| 3.6.7.9 | Install button hidden after acceptance | User accepts install | Install button hidden |
| 3.6.7.10 | Install button hidden after dismissal | User dismisses install | Install button hidden (or shown again, documented) |
| 3.6.7.11 | Install button hidden when app installed | App installed, reload | Install button not shown |
| 3.6.7.12 | Install button has accessible label | Check button | `aria-label` or text content describes action |
| 3.6.7.13 | Install button keyboard accessible | Tab to button, press Enter | Install prompt triggers |

**Estimated install prompt tests: 13**

#### 3.6.8 Test Scenarios (Offline Behavior)

**Test file**: Playwright E2E in `test/e2e/pwa-capabilities.spec.js`.

**App Functionality Offline**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.6.8.1 | App loads from cache offline | First visit online, go offline, reload | Page loads, app mounts |
| 3.6.8.2 | Canvas renders offline | Go offline, check canvas | Canvas visible, renders correctly |
| 3.6.8.3 | Layout switching works offline | Go offline, change layout | Layout changes, canvas updates |
| 3.6.8.4 | Gutter adjustment works offline | Go offline, adjust gutter | Gutter changes applied |
| 3.6.8.5 | Background change works offline | Go offline, change background | Background updates |
| 3.6.8.6 | Title editing works offline | Go offline, edit title | Title updates on canvas |
| 3.6.8.7 | Export works offline | Go offline, export collage | JPEG downloaded (uses cached assembler) |
| 3.6.8.8 | Undo/Redo works offline | Go offline, crop, undo | Undo functions correctly |
| 3.6.8.9 | Keyboard shortcuts work offline | Go offline, press Cmd+Z | Shortcut fires |
| 3.6.8.10 | Theme toggle works offline | Go offline, toggle theme | Theme changes |

**Graceful Degradation**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.6.8.11 | Network-first image fails gracefully offline | Go offline, request uncached image | Error handled, no crash |
| 3.6.8.12 | Vue CDN not cached — app fails if not visited | First visit offline (no cache) | App does not load (expected — no shell cached) |
| 3.6.8.13 | Service worker not supported — app works | Disable SW in browser | App loads and functions normally (no SW) |
| 3.6.8.14 | Cache API not supported — app works | Mock no Cache API | App loads and functions normally |
| 3.6.8.15 | Cache storage full — graceful error | Simulate quota exceeded | Error logged, app continues |

**Estimated offline behavior tests: 15**

#### 3.6.9 E2E Test Scenarios (Playwright)

**Test file**: `test/e2e/pwa-capabilities.spec.js` (new).

**Service Worker Registration**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.6.9.1 | SW registers on first load | Navigate to app, wait 2s | `navigator.serviceWorker.controller` not null |
| 3.6.9.2 | SW activates within timeout | Navigate, wait 5s | `registration.active` exists |
| 3.6.9.3 | SW scope is correct | Check registration | Scope includes app directory |
| 3.6.9.4 | SW file served with correct MIME type | `fetch('./service-worker.js')` | `content-type: text/javascript` |
| 3.6.9.5 | Manifest served with correct MIME type | `fetch('./manifest.json')` | `content-type: application/manifest+json` or `application/json` |

**Offline Mode**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.6.9.6 | App loads after going offline | Load online, set context offline, reload | `#app` visible |
| 3.6.9.7 | Canvas visible offline | Go offline, check canvas | `#previewCanvas` visible |
| 3.6.9.8 | Toolbar functional offline | Go offline, click buttons | No errors in console |
| 3.6.9.9 | Settings persist across offline reload | Set settings offline, reload | Settings restored |
| 3.6.9.10 | Previously loaded images visible offline | Load images online, go offline, reload | Images in sidebar, canvas renders |
| 3.6.9.11 | Export produces file offline | Go offline, export | Download event fires |

**Cache Validation**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.6.9.12 | Shell cache populated | First load, check caches | Shell cache exists with entries |
| 3.6.9.13 | Shell cache contains index.html | Check cache | `./index.html` present |
| 3.6.9.14 | Shell cache contains all JS modules | Check cache | All module files present |
| 3.6.9.15 | CDN requests not in cache | Check all caches | No unpkg.com or fonts.googleapis.com entries |

**Update Cycle**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.6.9.16 | SW update detected on file change | Modify SW, reload | New SW registers |
| 3.6.9.17 | Old cache cleaned on version bump | Bump version, reload | Old cache entries removed |
| 3.6.9.18 | New cache populated on update | Bump version, reload | New cache populated |
| 3.6.9.19 | Skip waiting activates immediately | Send skip message | New SW becomes controller |

**Installability (Conditional)**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.6.9.20 | `beforeinstallprompt` fires (if eligible) | Load in installable context | Event captured via `page.evaluate` |
| 3.6.9.21 | App installable criteria met | Check manifest + SW + HTTPS | All PWA criteria satisfied |

**Edge Cases**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.6.9.22 | Service worker disabled — app works | `serviceWorkers: 'block'` in context | App loads and functions |
| 3.6.9.23 | Manifest missing — app works | Remove manifest link | App loads (no install prompt) |
| 3.6.9.24 | Rapid offline/online toggle | Toggle 10 times rapidly | No crash, state consistent |
| 3.6.9.25 | Large image cache — eviction works | Upload 100 images | Cache size bounded by MAX_IMAGE_CACHE_SIZE |
| 3.6.9.26 | Concurrent requests while offline | Multiple simultaneous requests | All served from cache or fail gracefully |

**GitHub Pages Compatibility**

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.6.9.27 | SW registered from subdirectory | `https://user.github.io/CollageMaker/service-worker.js` | SW scope covers `/CollageMaker/` |
| 3.6.9.28 | `start_url` resolves correctly on GitHub Pages | `manifest.start_url` | Resolves to `https://user.github.io/CollageMaker/index.html` |
| 3.6.9.29 | Icon paths resolve on GitHub Pages | Each icon `src` | Resolves to `https://user.github.io/CollageMaker/icons/...` |
| 3.6.9.30 | HTTPS required — works on GitHub Pages | Load on `https://` | SW registers (GitHub Pages provides HTTPS) |
| 3.6.9.31 | SW does not intercept root page | SW scope limited to `/CollageMaker/` | Root `index.html` not cached by CollageMaker SW |
| 3.6.9.32 | SW does not intercept sibling projects | Request `/Midiestro/...` | Not handled by CollageMaker SW |

**Estimated E2E tests: 32**

#### 3.6.10 Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | 3.6.2.1–3.6.2.9 (Config constants), 3.6.2.35–3.6.2.46 (Route classification), 3.6.2.69–3.6.2.87 (Manifest validation), 3.6.3.1–3.6.3.10 (Manifest required fields), 3.6.3.11–3.6.3.13 (Icons), 3.6.5.1–3.6.5.10 (Shell cache), 3.6.8.1–3.6.8.10 (Offline functionality), 3.6.9.1–3.6.9.5 (SW registration), 3.6.9.6–3.6.9.11 (Offline E2E) | Core PWA functionality — if these fail, the app is not installable or does not work offline |
| **P1** | 3.6.2.10–3.6.2.34 (isAppShellURL + isImageURL), 3.6.2.47–3.6.2.68 (Cache keys, response validation, cache names), 3.6.3.14–3.6.3.31 (Icons, theme, HTML link tags), 3.6.4.1–3.6.4.8 (SW file structure), 3.6.5.11–3.6.5.25 (Image cache, invalidation, passthrough), 3.6.6.1–3.6.6.10 (Shell+SW integration), 3.6.7.1–3.6.7.13 (Install prompt), 3.6.9.12–3.6.9.21 (Cache E2E, update cycle, installability), 3.6.9.27–3.6.9.32 (GitHub Pages compat) | Structural correctness, installability, and platform compatibility |
| **P2** | 3.6.4.9–3.6.4.16 (SW lifecycle E2E), 3.6.6.11–3.6.6.14 (Update detection), 3.6.8.11–3.6.8.15 (Graceful degradation), 3.6.9.22–3.6.9.26 (Edge cases) | Polish, edge cases, and robustness |

#### 3.6.11 Known Behaviors to Document

1. **First visit must be online**: The app shell is cached on the first visit. If a user visits for the first time while offline, the app will not load because Vue.js and all modules are fetched from CDN/local and not yet cached. There is no "cold start" offline support.

2. **CDN dependencies not cached**: Vue.js, PureCSS, and Google Fonts are loaded from external CDNs. These are NOT cached by the service worker (passthrough routing). If the CDN is unavailable, the app will fail to load even if previously visited. **Mitigation**: Consider caching the Vue CDN URL in the app shell for production.

3. **Image cache is user-data dependent**: The image cache stores images uploaded by the user. These are not part of the app shell and are evicted based on LRU policy. An image available offline on one visit may be evicted on a subsequent visit if the cache is full.

4. **Service worker scope is subdirectory-limited**: On GitHub Pages, the SW at `/CollageMaker/service-worker.js` can only intercept requests under `/CollageMaker/`. It cannot cache or intercept requests to the root landing page or sibling projects.

5. **No push notifications**: The PWA does not implement push notifications. The `message` event handler is used only for update detection (skip-waiting control).

6. **Install eligibility varies by browser**: Chrome and Edge on desktop support install prompts. Safari on macOS does not. Safari on iOS supports "Add to Home Screen" but not the `beforeinstallprompt` event. Firefox does not support install prompts. The install button is hidden on unsupported browsers.

7. **Service worker not supported — app works fine**: If the browser does not support service workers, the app loads and functions normally. PWA capabilities are progressive enhancements.

8. **Cache version bump clears all image cache**: When `CACHE_VERSION` is incremented, both shell and image caches are deleted and rebuilt. This means all previously uploaded images need to be re-uploaded after a version bump. **Mitigation**: Consider separate versioning for shell vs image caches.

9. **Offline file upload works via FileReader**: When offline, the "Add Images" button still works because it uses `FileReader.readAsDataURL()` (local file access, not network). The resulting data URL is rendered on canvas but is NOT cached in the service worker image cache.

10. **Export offline produces same quality**: The export function uses `canvas.toBlob()` which is a local operation. Export quality is identical whether online or offline.

#### 3.6.12 Total Test Count Summary

| Category | Count |
|----------|-------|
| Pure function tests (config, routing, cache keys, response validation, manifest validation) | 87 |
| Manifest validation tests (required fields, icons, theme, HTML link tags) | 31 |
| Service Worker lifecycle tests (file structure, registration, activation) | 16 |
| Cache strategy tests (shell cache, image cache, invalidation, passthrough) | 25 |
| Integration tests (shell+SW integration, image upload+cache, update detection) | 14 |
| Install prompt tests (beforeinstallprompt event, install button) | 13 |
| Offline behavior tests (app functionality offline, graceful degradation) | 15 |
| E2E tests (Playwright: registration, offline mode, cache validation, update cycle, installability, edge cases, GitHub Pages) | 32 |
| **Total** | **233** |

---

## 4. Recommended MVP Scope

The Phase 4 MVP will be strictly focused on **Discoverability** and **UX Fluidity**.

### Included in MVP:
- **Landing Page Integration** — Enables users to discover and access the app
- **Keyboard Shortcuts** — Completes the interaction model with standard accelerators

### Deferred to Post-Launch:
- **ML-Based Saliency & Debugging** — Center-weighted heuristic is sufficient for MVP
- **Responsive/Touch Design** — Desktop-first is the MVP target
- **PWA Capabilities** — Not required for static site deployment

---

## 5. Implementation Order

1. **Keyboard Shortcuts** — Final polish to the interaction model. Complete remaining shortcuts (Cmd+O, Cmd+S, Cmd+1-5, Escape, Delete/Backspace).
2. **Landing Page Integration** — Last step before deployment to enable public access.

---

## 6. Success Criteria

### Automated Verification
- [ ] `node scripts/run-tests.js` — all `KeyboardHandlerTest.html` tests pass (70+ unit tests)
- [ ] `node scripts/run-tests.js` — all `LandingPageTest.html` tests pass (18 unit tests)
- [ ] `npx playwright test keyboard-shortcuts` — all E2E keyboard shortcut tests pass (15 tests)
- [ ] `npx playwright test landing-page` — all E2E landing page tests pass (11 tests)
- [ ] `MyESModules/Interaction/KeyboardHandler.js` exists and exports `createKeyboardHandler`, `parseKeyShortcut`, `matchesShortcut`, `KEYBOARD_SHORTCUTS`
- [ ] `MyComponents/KeyboardHandlerTest.html` exists and loads without errors
- [ ] `MyComponents/LandingPageTest.html` exists and loads without errors
- [ ] `test/e2e/keyboard-shortcuts.spec.js` exists and is picked up by Playwright config
- [ ] `test/e2e/landing-page.spec.js` exists and is picked up by Playwright config

### Deferred Automated Verification (ML-Based Saliency — Section 3.3)
- [ ] `node scripts/run-tests.js` — all `SaliencyTest.html` tests pass (118 unit tests: 72 pure functions + 20 worker protocol + 26 integration)
- [ ] `npx playwright test saliency` — all E2E saliency tests pass (20 tests)
- [ ] `MyESModules/Saliency/SaliencyAnalyzer.js` exists and exports `createSaliencyAnalyzer`, `computeFocusPoint`, `saliencyCrop`, `filterDetections`, `computeBboxCentroid`, `computeInferenceSize`, `scaleDetectionUp`, `SALIENCY_CONFIG`, `WORKER_MSG`
- [ ] `MyComponents/SaliencyTest.html` exists and loads without errors
- [ ] `test/e2e/saliency.spec.js` exists and is picked up by Playwright config

### Deferred Automated Verification (Saliency Debug Overlay — Section 3.4)
- [ ] `node scripts/run-tests.js` — all `SaliencyDebugOverlayTest.html` tests pass (144 tests: 58 pure functions + 45 canvas rendering + 14 integration + 11 state/export)
- [ ] `npx playwright test saliency-debug-overlay` — all E2E debug overlay tests pass (16 tests)
- [ ] `MyESModules/Rendering/SaliencyDebugOverlay.js` exists and exports `createDebugOverlay`, `focusPointToCanvasCoords`, `imageCenterToCanvasCoords`, `computeDebugMarkers`, `validateFocusPoint`, `DEBUG_OVERLAY_STYLES`, `render`
- [ ] `MyComponents/SaliencyDebugOverlayTest.html` exists and loads without errors
- [ ] `test/e2e/saliency-debug-overlay.spec.js` exists and is picked up by Playwright config
- [ ] Export with debug overlay enabled produces JPEG with no debug markers (verified via pixel inspection or renderData interception)

### Manual Verification
- [ ] The CollageMaker project card is visible on the root landing page and links correctly to `CollageMaker/index.html`
- [ ] The card icon visually represents "collage" or "photo collage" concept
- [ ] The card description is clear, concise, and accurately describes what CollageMaker does
- [ ] The card matches the visual style of other cards in the section (colors, spacing, typography)
- [ ] The card displays correctly at 375px viewport width (mobile)
- [ ] The card is legible in dark theme (WCAG AA contrast)
- [ ] Pressing `Cmd+O` triggers the image upload dialog (browser's native "Open File" dialog is suppressed)
- [ ] Pressing `Cmd+S` triggers the export process (browser's native "Save Page" dialog is suppressed)
- [ ] `Cmd+1` through `Cmd+5` successfully switch between the five layout styles
- [ ] `Delete` or `Backspace` removes the currently selected image
- [ ] `Escape` deselects the active panel
- [ ] Keyboard shortcuts do NOT fire when typing in the title input or search field
- [ ] `Cmd+S` with no images loaded does not crash the app
- [ ] `Delete` with no panel selected does not crash the app
- [ ] Application bundle size remains lean (no TF.js dependencies included in MVP)

### Deferred Manual Verification (Responsive Design — Section 3.5)
- [ ] At 375px viewport (iPhone SE), layout stacks vertically with no horizontal scroll
- [ ] At 768px viewport (iPad portrait), sidebars collapse to overlay/drawer mode
- [ ] At 1200px viewport (small laptop), three-panel layout displays correctly
- [ ] All interactive elements meet 44x44px minimum touch target on mobile
- [ ] Canvas is tappable and panel selection works via touch on mobile
- [ ] Image library scrolls vertically on mobile without triggering canvas interactions
- [ ] Crop preview drag works on touch devices without page scroll interference
- [ ] Layout transitions smoothly when resizing from desktop to mobile and back
- [ ] State (selected panel, loaded images, crop settings) is preserved across viewport resize
- [ ] Export produces same quality JPEG regardless of viewport size

### Deferred Manual Verification (PWA Capabilities — Section 3.6)
- [ ] "Install to Desktop" prompt appears in Chrome/Edge after first visit
- [ ] Installed app opens in standalone window without browser chrome
- [ ] App icon displays correctly on desktop/taskbar
- [ ] App functions fully offline after first online visit (layout switching, export, undo/redo)
- [ ] "Add Images" button works offline (via FileReader, not network)
- [ ] Export produces same quality JPEG offline as online
- [ ] Service worker update is detected and applied on page refresh after deploy
- [ ] App works in browsers without service worker support (graceful degradation)
- [ ] App works without manifest (graceful degradation, no install prompt)
- [ ] Cache does not grow unboundedly with repeated image uploads

### Critical Files for Implementation
- `CollageMaker/MyESModules/Interaction/KeyboardHandler.js` — [New: Core logic for shortcut mapping, attach/detach lifecycle]
- `CollageMaker/MyComponents/KeyboardHandlerTest.html` — [New: Mocha/Chai unit tests for KeyboardHandler]
- `CollageMaker/test/e2e/keyboard-shortcuts.spec.js` — [New: Playwright E2E tests for keyboard shortcuts]
- `CollageMaker/MyComponents/LandingPageTest.html` — [New: Mocha/Chai DOM structure tests for landing page card]
- `CollageMaker/test/e2e/landing-page.spec.js` — [New: Playwright E2E tests for landing page navigation]
- `CollageMaker/MyESModules/App/createCollageLifecycle.js` — [Modify: Replace inline `_handleKeyboard` with KeyboardHandler module]
- `CollageMaker/MyESModules/index.js` — [Modify: Add barrel export for KeyboardHandler]
- `/index.html` (Root) — [Modify: Add CollageMaker project card for discoverability]

### Deferred Critical Files (ML-Based Saliency — Section 3.3)
- `CollageMaker/MyESModules/Saliency/SaliencyAnalyzer.js` — [New: Core saliency analysis with pure functions, worker protocol, factory]
- `CollageMaker/MyESModules/Saliency/SaliencyWorker.js` — [New: Web Worker for TF.js inference]
- `CollageMaker/MyComponents/SaliencyTest.html` — [New: Mocha/Chai unit tests for SaliencyAnalyzer (118 tests)]
- `CollageMaker/test/e2e/saliency.spec.js` — [New: Playwright E2E tests for saliency (20 tests)]
- `CollageMaker/MyESModules/index.js` — [Modify: Add barrel exports for SaliencyAnalyzer]

### Deferred Automated Verification (Responsive Design — Section 3.5)
- [ ] `node scripts/run-tests.js` — all `ResponsiveUtilsTest.html` tests pass (74 unit tests: 62 pure functions + 12 integration)
- [ ] `node scripts/run-tests.js` — all `ResponsiveCSSValidationTest.html` tests pass (32 CSS/DOM validation tests)
- [ ] `node scripts/run-tests.js` — all `ResponsivePointerEventsTest.html` tests pass (12 pointer event compatibility tests)
- [ ] `npx playwright test responsive-design` — all E2E responsive design tests pass (24 tests)
- [ ] `MyESModules/Utils/ResponsiveUtils.js` exists and exports `getLayoutTier`, `getSidebarConfig`, `getCanvasMaxDimensions`, `hasResponsiveClass`, `computeTouchPadding`, `isStackedLayout`, `isOverlaySidebar`, `BREAKPOINTS`, `TOUCH_TARGET`, `SIDEBAR_CONFIG`
- [ ] `MyComponents/ResponsiveUtilsTest.html` exists and loads without errors
- [ ] `MyComponents/ResponsiveCSSValidationTest.html` exists and loads without errors
- [ ] `test/e2e/responsive-design.spec.js` exists and is picked up by Playwright config
- [ ] `Style.css` contains `@media` rules for mobile (<768px) and tablet (<1200px) breakpoints
- [ ] `Style.css` contains `touch-action: none` on `#previewCanvas` and `.crop-preview-canvas`
- [ ] `index.html` viewport meta tag includes `width=device-width, initial-scale=1.0` (no `user-scalable=no`)

### Deferred Critical Files (Saliency Debug Overlay — Section 3.4)
- `CollageMaker/MyESModules/Rendering/SaliencyDebugOverlay.js` — [New: Core module with pure coordinate functions, canvas rendering, factory, constants]
- `CollageMaker/MyESModules/Rendering/CollageAssembler.js` — [Modify: Add debug overlay render pass between selection and blend-mode overlay]
- `CollageMaker/MyESModules/Export/ExportManager.js` — [Modify: Ensure showDebugOverlay and focusPoints are excluded from export render data]
- `CollageMaker/MyESModules/State/CollageState.js` — [Modify: Add showDebugOverlay and focusPoints fields]
- `CollageMaker/MyComponents/SaliencyDebugOverlayTest.html` — [New: Mocha/Chai unit tests for SaliencyDebugOverlay (144 tests)]
- `CollageMaker/test/e2e/saliency-debug-overlay.spec.js` — [New: Playwright E2E tests for debug overlay (16 tests)]
- `CollageMaker/MyESModules/index.js` — [Modify: Add barrel exports for SaliencyDebugOverlay]

### Deferred Critical Files (Responsive Design — Section 3.5)
- `CollageMaker/MyESModules/Utils/ResponsiveUtils.js` — [New: Pure functions for breakpoint detection, sidebar config, touch target math]
- `CollageMaker/Style.css` — [Modify: Add media queries for mobile/tablet breakpoints, touch-action CSS, touch target sizing]
- `CollageMaker/index.html` — [Modify: Ensure viewport meta tag supports responsive design]
- `CollageMaker/MyComponents/ResponsiveUtilsTest.html` — [New: Mocha/Chai unit tests for ResponsiveUtils (74 tests: 62 pure + 12 integration)]
- `CollageMaker/MyComponents/ResponsiveCSSValidationTest.html` — [New: CSS/DOM validation tests (32 tests)]
- `CollageMaker/MyComponents/ResponsivePointerEventsTest.html` — [New: Pointer event compatibility tests (12 tests)]
- `CollageMaker/test/e2e/responsive-design.spec.js` — [New: Playwright E2E tests for responsive design (24 tests)]
- `CollageMaker/MyESModules/index.js` — [Modify: Add barrel exports for ResponsiveUtils]

### Deferred Automated Verification (PWA Capabilities — Section 3.6)
- [ ] `node scripts/run-tests.js` — all `PWACacheUtilsTest.html` tests pass (142 unit tests: 87 pure functions + 16 SW lifecycle + 25 cache strategy + 14 integration)
- [ ] `node scripts/run-tests.js` — all `PWAManifestTest.html` tests pass (31 manifest validation tests)
- [ ] `npx playwright test pwa-capabilities` — all E2E PWA tests pass (32 tests)
- [ ] `MyESModules/Utils/PWACacheUtils.js` exists and exports `isAppShellURL`, `isImageURL`, `routeRequest`, `computeCacheKey`, `getCacheName`, `shouldCacheResponse`, `validateManifest`, `CACHE_CONFIG`
- [ ] `manifest.json` exists and is valid JSON with required fields (name, short_name, start_url, display, icons)
- [ ] `service-worker.js` exists and registers successfully in browser
- [ ] `MyComponents/PWACacheUtilsTest.html` exists and loads without errors
- [ ] `MyComponents/PWAManifestTest.html` exists and loads without errors
- [ ] `test/e2e/pwa-capabilities.spec.js` exists and is picked up by Playwright config
- [ ] `index.html` includes `<link rel="manifest">` and `<meta name="theme-color">`
- [ ] App loads and functions correctly when offline after first online visit
- [ ] CDN requests (unpkg.com, fonts.googleapis.com) are NOT cached by service worker

### Deferred Manual Verification (PWA Capabilities — Section 3.6)
- [ ] "Install to Desktop" prompt appears in Chrome/Edge after first visit
- [ ] Installed app opens in standalone window without browser chrome
- [ ] App icon displays correctly on desktop/taskbar
- [ ] App functions fully offline after first online visit (layout switching, export, undo/redo)
- [ ] "Add Images" button works offline (via FileReader, not network)
- [ ] Export produces same quality JPEG offline as online
- [ ] Service worker update is detected and applied on page refresh after deploy
- [ ] App works in browsers without service worker support (graceful degradation)
- [ ] App works without manifest (graceful degradation, no install prompt)
- [ ] Cache does not grow unboundedly with repeated image uploads

### Deferred Critical Files (PWA Capabilities — Section 3.6)
- `CollageMaker/manifest.json` — [New: Web app manifest with name, icons (192x192 + 512x512), display: standalone, theme colors]
- `CollageMaker/service-worker.js` — [New: Service worker with App Shell caching (cache-first for app assets, network-first for images, passthrough for CDN)]
- `CollageMaker/MyESModules/Utils/PWACacheUtils.js` — [New: Pure utility functions extracted from SW logic for unit testing]
- `CollageMaker/index.html` — [Modify: Add `<link rel="manifest">`, `<meta name="theme-color">`, Apple touch icon meta, SW registration script]
- `CollageMaker/MyComponents/PWACacheUtilsTest.html` — [New: Mocha/Chai unit tests for PWACacheUtils (142 tests: 87 pure + 16 lifecycle + 25 cache + 14 integration)]
- `CollageMaker/MyComponents/PWAManifestTest.html` — [New: Mocha/Chai manifest validation tests (31 tests)]
- `CollageMaker/test/e2e/pwa-capabilities.spec.js` — [New: Playwright E2E tests for PWA (32 tests)]
- `CollageMaker/MyESModules/index.js` — [Modify: Add barrel exports for PWACacheUtils]
