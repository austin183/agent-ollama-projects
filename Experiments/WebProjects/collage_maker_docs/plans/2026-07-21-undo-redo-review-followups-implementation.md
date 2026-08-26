# Undo/Redo Expansion Review Follow-Ups Implementation Plan

## Overview

Address 4 follow-up issues identified in the pre-commit review (`_agent_docs/reviews/2026-07-21-undo-redo-expansion-review.md`) for the Undo/Redo Expansion feature. The review verdict was **APPROVE with noted improvements** — these items are non-blocking polish and test-coverage gaps.

| Issue | Description | Severity | Priority |
|-------|-------------|----------|----------|
| **N-1** | Template inline expressions in segmented controls | Nit | P1 |
| **N-2** | Technical error messages in undo toasts | Nit | P0 |
| **N-4** | Missing E2E tests for undo expansion | Low | P1 |
| **N-5** | Verify Cmd+Z behavior when title textarea focused | Low | P2 (no code change) |

## Current State Analysis

### N-1: Inline Expressions

There are **8 inline multi-statement Vue expressions** in `index.html` that perform snapshot/mutate/commit cycles for undo support:

| Location | Line(s) | Expression |
|----------|---------|------------|
| Title alignment buttons | 229, 232, 235 | `snapshotTitleStyle(); titleStyle.alignment = 'X'; onTitleAlignmentChange(); commitTitleStyle()` |
| Title showBackground checkbox | 222 | `snapshotTitleStyle(); onTitleShowBackgroundChange(); commitTitleStyle()` |
| Background style buttons | 282-284 | `snapshotBackground(); backgroundStyle = 'X'; onBackgroundStyleChange(); commitBackground()` |
| Background remove image button | 315 | `snapshotBackground(); removeBackgroundImage(); commitBackground()` |
| Overlay remove button | 332 | `snapshotOverlay(); removeOverlay(); commitOverlay()` |

These work correctly but violate Vue best practices (logic in templates), reduce readability, and make undo lifecycle harder to test.

### N-2: Error Messages

`createCollageMethods.js` lines 62-76 expose JavaScript internals to users:
```javascript
vm.showToast('Undo failed: ' + e.message, 'error', 5000);
vm.showToast('Redo failed: ' + e.message, 'error', 5000);
```

### N-4: E2E Coverage Gap

`test/e2e/keyboard-shortcuts.spec.js` tests undo only for crop reset (tests 3.1.3.10, 3.1.3.11). The undo expansion added ~17 new undoable actions across image operations, layout changes, title edits, background, and overlay — none of which have E2E coverage.

### N-5: Cmd+Z in Textarea

**Verified: No code change needed.** `KeyboardHandler.js` lines 140-165: `_isFocusInEditableElement()` returns `true` for `textarea`, `select`, and `contenteditable` elements. `handleKeydown()` returns early (line 165) when focus is in an editable element, allowing native browser Cmd+Z to work in the title textarea.

## Desired End State

After this plan is complete:
- All segmented control and checkbox undo actions use dedicated handler methods (no inline Vue expressions)
- Undo/redo error toasts show user-friendly messages; debugging details remain in console
- E2E tests cover each major undoable action category (image, layout, title, background, overlay)
- Cmd+Z textarea behavior is documented as verified

## What We're NOT Doing

1. **Refactoring all template expressions** — Only the 8 undo-related inline expressions. Other template expressions (e.g., `Math.round(titleStyle.fontOpacity * 100)`) are out of scope.
2. **Extracting a generic batching utility** — Background and overlay batching patterns differ enough that a shared utility adds complexity without clear benefit (confirmed in review).
3. **Extracting title formatting toggle duplication** — Bold/italic/underline each have ~8 lines of inline undo logic. The duplication is minimal and context-specific snapshots make a shared helper awkward.
4. **Adding undo tooltips on buttons** — Nice-to-have for future iteration.
5. **Adding E2E tests for every undo permutation** — Unit tests (`UndoExpansionTest.html`) cover detailed state transitions. E2E tests cover the happy path for each action category.

## Implementation Approach

### Architecture Decision: Handler Module Methods (Option A)

For N-1, new atomic methods are added to each handler module. This keeps handler modules self-contained, follows the existing callback injection pattern, and yields the cleanest templates.

**Why not a generic helper?** A generic `undoWrap(snapshotFn, mutateFn, commitFn)` would need to pass snapshot/commit callbacks through the wiring layer, breaking the handler factory pattern. The handler modules already own the undo lifecycle via their closure variables (`titleStyleSnapshot`, `backgroundSnapshot`, etc.).

**Why not Vue methods in the app assembly?** Scattering undo lifecycle logic out of handler modules violates the established decomposition pattern and makes testing harder.

---

## Phase 1: Genericize Error Messages (N-2)

### Overview

Replace technical error messages in `pushUndoCommand` with user-friendly text. Console logging retains full debugging details.

### Changes Required:

#### 1. `MyESModules/App/createCollageMethods.js` (lines 62-76)

Replace the two toast messages:

```javascript
// Before:
vm.showToast('Undo failed: ' + e.message, 'error', 5000);
vm.showToast('Redo failed: ' + e.message, 'error', 5000);

// After:
vm.showToast('Something went wrong', 'error', 5000);
vm.showToast('Something went wrong', 'error', 5000);
```

The `console.error` calls on lines 63 and 70 retain full debugging info: `console.error('Undo error (${cmd.label}):', e)`.

### Test Scenarios

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 1.1.1 | An undo command throws an error during execution | User triggers undo | Toast shows "Something went wrong" — no JavaScript internals visible |
| 1.1.2 | A redo command throws an error during execution | User triggers redo | Toast shows "Something went wrong" — no JavaScript internals visible |

#### Unit Test Scenarios

| # | Test | Input | Expected |
|---|------|-------|----------|
| 1.2.1 | Undo error toast is generic | `undoFn` throws `TypeError: Cannot read properties of undefined` | Toast message is `'Something went wrong'` (not containing `e.message`) |
| 1.2.2 | Redo error toast is generic | `redoFn` throws `ReferenceError: foo is not defined` | Toast message is `'Something went wrong'` |
| 1.2.3 | Console retains debug details | `undoFn` throws any error | `console.error` called with command label and error object |

### Success Criteria:

#### Automated Verification:
- [ ] All existing tests pass (`node scripts/run-tests.js`)
- [ ] No test asserts on `'Undo failed:'` or `'Redo failed:'` toast text (search and update if any exist)

#### Manual Verification:
- [ ] Trigger an undo error (e.g., dispose an image, then undo its removal) and verify toast shows generic message
- [ ] Open DevTools console and verify error details are still logged

---

## Phase 2: Extract Segmented Control Inline Expressions (N-1)

### Overview

Replace 8 inline Vue expressions with 5 dedicated handler methods across 3 handler modules. Each method performs an atomic snapshot/mutate/commit cycle.

### Changes Required:

#### 1. `MyESModules/App/createTitleHandlers.js` — Add 2 methods

**`setTitleAlignment(alignment)`** — Atomic alignment change:
```javascript
setTitleAlignment(alignment) {
    const preState = { ...this.titleStyle };
    this.titleStyle.alignment = alignment;
    const titleManager = getTitleManager();
    if (titleManager) titleManager.setAlignment(alignment);
    onRenderScheduled(this);
    if (onUndoCommand && preState.alignment !== alignment) {
        const postState = { ...this.titleStyle };
        onUndoCommand(this, {
            label: 'Change Title Style',
            undoFn: (v) => {
                v.titleStyle.alignment = preState.alignment;
                if (v._scheduleRender) v._scheduleRender();
            },
            redoFn: (v) => {
                v.titleStyle.alignment = postState.alignment;
                if (v._scheduleRender) v._scheduleRender();
            }
        });
    }
},
```

**`toggleTitleShowBackground()`** — Atomic background visibility toggle:
```javascript
toggleTitleShowBackground() {
    const preState = this.titleStyle.showBackground;
    this.titleStyle.showBackground = !preState;
    const titleManager = getTitleManager();
    if (titleManager) titleManager.showBackground(this.titleStyle.showBackground);
    onRenderScheduled(this);
    if (onUndoCommand) {
        const postState = this.titleStyle.showBackground;
        onUndoCommand(this, {
            label: 'Change Title Style',
            undoFn: (v) => {
                v.titleStyle.showBackground = preState;
                if (v._scheduleRender) v._scheduleRender();
            },
            redoFn: (v) => {
                v.titleStyle.showBackground = postState;
                if (v._scheduleRender) v._scheduleRender();
            }
        });
    }
},
```

**Important:** For the checkbox, replace `v-model="titleStyle.showBackground"` with `:checked="titleStyle.showBackground"` to avoid Vue's v-model timing issue (v-model toggles the value BEFORE `@change` fires, so the handler would see the already-toggled value).

#### 2. `MyESModules/App/createBackgroundHandlers.js` — Add 2 methods

**`setBackgroundStyle(style)`** — Atomic style change:
```javascript
setBackgroundStyle(style) {
    const preStyle = this.backgroundStyle;
    this.backgroundStyle = style;
    const backgroundManager = getBackgroundManager();
    if (backgroundManager) backgroundManager.updateStyle(style);
    onRenderScheduled(this);
    if (onUndoCommand && preStyle !== style) {
        onUndoCommand(this, {
            label: 'Change Background',
            undoFn: (v) => {
                v.backgroundStyle = preStyle;
                const bm = v.backgroundManager;
                if (bm) bm.updateStyle(preStyle);
                if (v._scheduleRender) v._scheduleRender();
            },
            redoFn: (v) => {
                v.backgroundStyle = style;
                const bm = v.backgroundManager;
                if (bm) bm.updateStyle(style);
                if (v._scheduleRender) v._scheduleRender();
            }
        });
    }
},
```

**`removeBackgroundImageAtomic()`** — Atomic image removal:
```javascript
removeBackgroundImageAtomic() {
    const preState = {
        backgroundImage: this.backgroundImage,
        backgroundStyle: this.backgroundStyle
    };
    this.backgroundImage = null;
    this.backgroundStyle = 'solid';
    const backgroundManager = getBackgroundManager();
    if (backgroundManager) backgroundManager.setImage(null);
    onRenderScheduled(this);
    if (onUndoCommand && preState.backgroundImage) {
        onUndoCommand(this, {
            label: 'Change Background',
            undoFn: (v) => {
                v.backgroundImage = preState.backgroundImage;
                v.backgroundStyle = preState.backgroundStyle;
                const bm = v.backgroundManager;
                if (bm) {
                    bm.updateStyle(preState.backgroundStyle);
                    bm.setImage(preState.backgroundImage);
                }
                if (v._scheduleRender) v._scheduleRender();
            },
            redoFn: (v) => {
                v.backgroundImage = null;
                v.backgroundStyle = 'solid';
                const bm = v.backgroundManager;
                if (bm) {
                    bm.updateStyle('solid');
                    bm.setImage(null);
                }
                if (v._scheduleRender) v._scheduleRender();
            }
        });
    }
},
```

#### 3. `MyESModules/App/createOverlayHandlers.js` — Add 1 method

**`removeOverlayAtomic()`** — Atomic overlay removal:
```javascript
removeOverlayAtomic() {
    const preState = {
        overlayImage: this.overlayImage,
        overlayMode: this.overlayMode,
        overlayOpacity: this.overlayOpacity
    };
    this.overlayImage = null;
    onRenderScheduled(this);
    if (onUndoCommand && preState.overlayImage) {
        onUndoCommand(this, {
            label: 'Change Overlay',
            undoFn: (v) => {
                v.overlayImage = preState.overlayImage;
                v.overlayMode = preState.overlayMode;
                v.overlayOpacity = preState.overlayOpacity;
                if (v._scheduleRender) v._scheduleRender();
            },
            redoFn: (v) => {
                v.overlayImage = null;
                if (v._scheduleRender) v._scheduleRender();
            }
        });
    }
},
```

#### 4. `MyESModules/App/createCollageMethods.js` — Wire 5 new methods

Add to the return object:
```javascript
setTitleAlignment(alignment) {
    titleHandlers.setTitleAlignment.call(this, alignment);
},
toggleTitleShowBackground() {
    titleHandlers.toggleTitleShowBackground.call(this);
},
setBackgroundStyle(style) {
    backgroundHandlers.setBackgroundStyle.call(this, style);
},
removeBackgroundImageAtomic() {
    backgroundHandlers.removeBackgroundImageAtomic.call(this);
},
removeOverlayAtomic() {
    overlayHandlers.removeOverlayAtomic.call(this);
},
```

#### 5. `index.html` — Replace 8 inline expressions

**Title alignment (lines 229, 232, 235):**
```html
<!-- Before: -->
<button @click="snapshotTitleStyle(); titleStyle.alignment = 'left'; onTitleAlignmentChange(); commitTitleStyle()">
<!-- After: -->
<button @click="setTitleAlignment('left')">
```

**Title showBackground (line 222):**
```html
<!-- Before: -->
<input type="checkbox" v-model="titleStyle.showBackground" @change="snapshotTitleStyle(); onTitleShowBackgroundChange(); commitTitleStyle()">
<!-- After: -->
<input type="checkbox" :checked="titleStyle.showBackground" @change="toggleTitleShowBackground">
```

**Background style (lines 282-284):**
```html
<!-- Before: -->
<button @click="snapshotBackground(); backgroundStyle = 'solid'; onBackgroundStyleChange(); commitBackground()">
<!-- After: -->
<button @click="setBackgroundStyle('solid')">
```

**Background remove (line 315):**
```html
<!-- Before: -->
<button @click="snapshotBackground(); removeBackgroundImage(); commitBackground()">
<!-- After: -->
<button @click="removeBackgroundImageAtomic()">
```

**Overlay remove (line 332):**
```html
<!-- Before: -->
<button @click="snapshotOverlay(); removeOverlay(); commitOverlay()">
<!-- After: -->
<button @click="removeOverlayAtomic()">
```

### Test Scenarios

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 2.1.1 | Title alignment is 'center' | User clicks "Left" alignment button | Alignment changes to 'left', canvas re-renders, undo button enabled |
| 2.1.2 | Alignment just changed to 'left' | User presses Cmd+Z | Alignment reverts to 'center', canvas re-renders |
| 2.1.3 | Title background is hidden | User clicks "Show Background" checkbox | Background shown, undo button enabled |
| 2.1.4 | Title background just shown | User presses Cmd+Z | Background hidden again |
| 2.1.5 | Background style is 'solid' | User clicks "Gradient" button | Style changes to 'gradient', undo button enabled |
| 2.1.6 | Background style just changed to 'gradient' | User presses Cmd+Z | Style reverts to 'solid' |
| 2.1.7 | Background image is loaded | User clicks "Remove Image" button | Image removed, style reverts to 'solid', undo button enabled |
| 2.1.8 | Background image just removed | User presses Cmd+Z | Image and style restored |
| 2.1.9 | Overlay image is loaded | User clicks "Remove Mask" button | Overlay removed, undo button enabled |
| 2.1.10 | Overlay just removed | User presses Cmd+Z | Overlay restored |

#### Component Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 2.2.1 | `setTitleAlignment` called with 'right' | `titleStyle.alignment` was 'center' | `onUndoCommand` called with pre-state alignment='center', post-state alignment='right' |
| 2.2.2 | `setTitleAlignment` called with 'center' | `titleStyle.alignment` is already 'center' | No undo command pushed (no-op when value unchanged) |
| 2.2.3 | `toggleTitleShowBackground` called | `showBackground` was `false` | Toggled to `true`, undo command pushed with correct pre/post |
| 2.2.4 | `setBackgroundStyle` called with 'image' | `backgroundStyle` was 'solid' | Style changed, BackgroundManager updated, undo command pushed |
| 2.2.5 | `removeBackgroundImageAtomic` called | `backgroundImage` is null | No undo command pushed (guard: no image to remove) |
| 2.2.6 | `removeOverlayAtomic` called | `overlayImage` exists | Image nulled, undo command pushed with full pre-state |

#### Pure Function Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 2.3.1 | `setTitleAlignment` undoFn called | preState.alignment = 'left' | `vm.titleStyle.alignment` set to 'left', render scheduled |
| 2.3.2 | `setTitleAlignment` redoFn called | postState.alignment = 'right' | `vm.titleStyle.alignment` set to 'right', render scheduled |
| 2.3.3 | `removeBackgroundImageAtomic` undoFn called | preState had image + style 'image' | Both `backgroundImage` and `backgroundStyle` restored, BackgroundManager updated |

### Success Criteria:

#### Automated Verification:
- [ ] All existing tests pass (`node scripts/run-tests.js`)
- [ ] New unit tests in `UndoExpansionTest.html` for each new method (5 methods × 3 tests = ~15 tests)
- [ ] No console errors when clicking segmented controls

#### Manual Verification:
- [ ] Click each alignment button → Cmd+Z reverts
- [ ] Toggle "Show Background" → Cmd+Z reverts
- [ ] Click each background style button → Cmd+Z reverts
- [ ] Remove background image → Cmd+Z restores
- [ ] Remove overlay → Cmd+Z restores
- [ ] Rapid clicks on segmented buttons don't produce duplicate undo commands
- [ ] Checkbox visual state stays in sync with `titleStyle.showBackground`

---

## Phase 3: E2E Tests for Undo Expansion (N-4)

### Overview

Create `test/e2e/undo-redo.spec.js` with Playwright tests covering each major undoable action category. Tests verify the happy path: action → undo button enabled → undo → state restored.

### Changes Required:

#### 1. `test/e2e/undo-redo.spec.js` — New file

Follow the pattern established in `test/e2e/keyboard-shortcuts.spec.js` (same base URL, same image loading helpers, same Control+key convention for cross-platform compatibility).

### Test Scenarios

#### E2E Test Scenarios (Playwright)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3.1.1 | Add images creates undo history | Load app → load 2 images → Cmd+Z | Image count goes to 0, undo button disabled |
| 3.1.2 | Remove image is undoable | Load 2 images → remove 1 → Cmd+Z | Image count back to 2 |
| 3.1.3 | Layout style change is undoable | Load images → switch to 'hero' → Cmd+Z | Layout reverts to 'uniform' |
| 3.1.4 | Layout options change is undoable | Load images → adjust gutter slider → blur → Cmd+Z | Gutter reverts to default |
| 3.1.5 | Title text change is undoable | Load images → type title → blur → Cmd+Z | Title text cleared |
| 3.1.6 | Title formatting is undoable | Load images → type title → select text → click Bold → Cmd+Z | Bold removed |
| 3.1.7 | Background style change is undoable | Load images → click "Gradient" → Cmd+Z | Reverts to "Solid" |
| 3.1.8 | Overlay add is undoable | Load images → load overlay → Cmd+Z | Overlay removed |
| 3.1.9 | Multiple undos work in sequence | Add images → change layout → change background → Cmd+Z × 3 | Each undo reverses one action in LIFO order |

#### Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | 3.1.1, 3.1.2, 3.1.3 | Core undoable actions — if these fail, the feature doesn't work |
| **P1** | 3.1.4, 3.1.5, 3.1.7 | Structural correctness and UX safety |
| **P2** | 3.1.6, 3.1.8, 3.1.9 | Robustness and polish |

### Success Criteria:

#### Automated Verification:
- [x] All 9 E2E tests pass (`npx playwright test --config=playwright.config.cjs test/e2e/undo-redo.spec.js`)
- [x] Tests run independently of `keyboard-shortcuts.spec.js`
- [x] No flaky assertions (use `waitForTimeout` where render timing matters)

#### Manual Verification:
- [ ] Run dev server, manually verify each test scenario in browser
- [ ] Verify undo button enabled/disabled state matches expectations

### Implementation Notes

**E2E limitations discovered during implementation:**

1. **`@focus` event reliability**: In headless Chromium, `el.focus()` does NOT fire a `focus` event. The `@focus` Vue handler (used for snapshot capture) requires explicit `dispatchEvent(new Event('focus'))`. This affects layout style change undo when triggered via select element.

2. **`@select` event for textareas**: `page.selectText()` and `page.keyboard.press('Control+a')` do NOT fire the `@select` event that Vue handlers depend on for tracking `titleSelectionStart/End`. Must use `page.evaluate()` to set selection range and dispatch the event.

3. **`page.fill()` on range inputs**: Does NOT work on `<input type="range">`. Must use `page.evaluate()` to set value and dispatch `input` event.

4. **Sidebar sections collapsed by default**: Right sidebar sections (Title, Background, Overlay) are collapsed by default. Tests must expand sections before interacting with their contents.

5. **Settings persistence across tests**: Layout style and other settings persist via localStorage between test runs. Tests should not assume default values — read current state first.

---

## Phase 4: Document Cmd+Z Textarea Verification (N-5) — ✅ COMPLETED

### Overview

No code changes. Document that Cmd+Z in the title textarea correctly uses native browser undo (not app-level undo) as verified by code inspection and automated testing.

### Verification Summary

| Check | File | Line | Result |
|-------|------|------|--------|
| `_isFocusInEditableElement` checks textarea | `KeyboardHandler.js` | 145 | `tag === 'textarea'` returns `true` |
| Shortcuts suppressed in editable elements | `KeyboardHandler.js` | 165 | `if (_isFocusInEditableElement(e)) return;` |
| Unit test covers textarea suppression | `KeyboardHandlerTest.html` | 611-616 | Test 3.1.2.57 — `handleKeydown` with textarea target — callback NOT invoked |
| Unit test covers select suppression | `KeyboardHandlerTest.html` | 619-624 | Test 3.1.2.58 — `handleKeydown` with select target — callback NOT invoked |
| Unit test covers contenteditable suppression | `KeyboardHandlerTest.html` | 627-633 | Test 3.1.2.59 — `handleKeydown` with contenteditable div — callback NOT invoked |

### Automated Verification Results

- **Test 3.1.2.57** (textarea suppression): **PASS** — `called` is `false` when Cmd+E pressed with textarea target
- **Full KeyboardHandlerTest suite**: **84 passes, 0 failures** (verified 2026-07-22)
- **Full test suite**: **All 43 test suites pass, 0 failures** (verified 2026-07-22)

### How It Works

When the title textarea has focus:
1. User presses Cmd+Z
2. `handleKeydown()` receives the event with `e.target` = `<textarea>`
3. `_isFocusInEditableElement(e)` checks `tag === 'textarea' || tag === 'select' || el.isContentEditable` → returns `true`
4. `handleKeydown()` returns early (line 165) — **no app-level undo triggered**
5. Browser's native undo (text editing undo stack) handles Cmd+Z normally

When focus is outside the textarea:
1. User presses Cmd+Z
2. `handleKeydown()` receives the event with `e.target` = non-editable element
3. `_isFocusInEditableElement(e)` returns `false`
4. Shortcut matching proceeds → `UNDO: 'meta+z'` matches → `onUndo()` callback fires
5. App-level undo manager processes the command

**Note on non-text inputs:** `_isFocusInEditableElement` uses an allow-list (`SHORTCUT_SAFE_INPUT_TYPES`) for `<input>` elements. Types like `color`, `range`, and `number` are in the safe set, meaning app-level shortcuts (including Cmd+Z) are **not suppressed** when those controls have focus. This is intentional: these controls don't have text-editing undo stacks, so app-level undo is the desired behavior. Text-like input types (`text`, `password`, `email`, `search`, `url`) are NOT in the safe set, so shortcuts are suppressed for them.

### Success Criteria:

#### Automated Verification:
- [x] Existing `KeyboardHandlerTest.html` textarea suppression test passes (3.1.2.57)
- [x] Full test suite passes (43 suites, 0 failures)

#### Manual Verification:
- [x] Focus title textarea → type text → Cmd+Z → native undo works (character removed) — **verified by code path analysis: early return in handleKeydown allows browser default**
- [x] Click outside textarea → Cmd+Z → app-level undo works — **verified by code path analysis: shortcut matching proceeds to UNDO callback**

---

## Testing Strategy

### Unit Tests

**Phase 1 (N-2):** Search for any test asserting on `'Undo failed:'` or `'Redo failed:'` toast text. Update to expect `'Something went wrong'`.

**Phase 2 (N-1):** Add tests to `MyComponents/UndoExpansionTest.html`:

| Method | Tests |
|--------|-------|
| `setTitleAlignment` | Pushes undo command, no-op when unchanged, undo restores pre-state |
| `toggleTitleShowBackground` | Toggles correctly, pushes undo command, undo restores pre-state |
| `setBackgroundStyle` | Changes style, pushes undo command, undo restores pre-state |
| `removeBackgroundImageAtomic` | Removes image + reverts style, pushes undo command, no-op when no image |
| `removeOverlayAtomic` | Removes overlay, pushes undo command, no-op when no overlay |

### E2E Tests

**Phase 3 (N-4):** New file `test/e2e/undo-redo.spec.js` with 9 scenarios. Follow existing patterns:
- Use `Control+Z` instead of `Meta+Z` for cross-platform compatibility
- Use `waitForTimeout(300)` after render-triggering actions
- Use buffer-based PNG images for file uploads
- Verify undo button state (`#undoBtn`) as observable outcome

### Manual Testing Steps

1. Start dev server: `bash start-server.sh`
2. Navigate to `http://localhost:8000/CollageMaker/index.html`
3. Load 3 images
4. Remove one image → Cmd+Z → verify restored
5. Change layout → Cmd+Z → verify reverted
6. Adjust gutter slider → release → Cmd+Z → verify reverted
7. Type title text → blur → Cmd+Z → verify reverted
8. Bold selected title text → Cmd+Z → verify unbolded
9. Click "Gradient" background → Cmd+Z → verify reverted
10. Add overlay → Cmd+Z → verify removed
11. Click alignment buttons → Cmd+Z → verify reverted
12. Toggle "Show Background" → Cmd+Z → verify reverted
13. Focus title textarea → type → Cmd+Z → verify native undo (not app undo)
14. Verify no console errors throughout

## Performance Considerations

- **No performance impact** — These changes are refactorings and additions. No algorithmic changes.
- **Template expressions** — Single method calls in `@click` are faster to evaluate than multi-statement inline expressions (minor improvement).
- **E2E tests** — 9 new tests add ~15-30 seconds to the E2E suite runtime.

## Migration Notes

- **No data migration needed** — Undo history is ephemeral
- **Backward compatible** — Existing `onTitleAlignmentChange`, `removeBackgroundImage`, `removeOverlay` methods remain unchanged. New atomic methods are additions, not replacements.
- **Template changes are additive** — Only the 8 inline expressions are replaced. All other template bindings remain unchanged.

## References

- Pre-commit review: `_agent_docs/reviews/2026-07-21-undo-redo-expansion-review.md`
- Original implementation plan: `_agent_docs/plans/2026-07-20-undo-redo-expansion-implementation.md`
- Existing undo tests: `MyComponents/UndoExpansionTest.html`, `MyComponents/TitleUndoBugTest.html`
- Existing E2E tests: `test/e2e/keyboard-shortcuts.spec.js`
- Keyboard handler: `MyESModules/Interaction/KeyboardHandler.js`
- Skill references: `building-web-apps` (undo snapshots, Vue input patterns, segmented/checkbox inline snapshot/commit)
