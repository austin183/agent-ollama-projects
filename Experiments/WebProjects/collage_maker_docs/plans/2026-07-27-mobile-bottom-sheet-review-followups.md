# Mobile Bottom Sheet Review Follow-ups — Implementation Plan

**Date:** 2026-07-27
**Source:** Review `_agent_docs/reviews/2026-07-27-mobile-bottom-sheet-review.md`
**Priority:** P1 — Accessibility compliance and test coverage

---

## Overview

Address the four follow-up items from the pre-commit review of the mobile bottom sheet implementation. Of the four items, only **N-1 (focus trap)** requires substantive code changes. Items N-3 and N-4 were based on incorrect assumptions about test file state and require no changes. Item N-2 (content deduplication) is already tracked as Phase 3 migration work.

This plan focuses on:
1. **Implementing a focus trap** for the bottom sheet `aria-modal` dialog (N-1)
2. **Adding focus trap test coverage** to existing test files
3. **Documenting findings** on N-3 and N-4 (no changes needed)

---

## Current State Analysis

### Focus Management (what exists)

| Feature | Status | File:Line |
|---------|--------|-----------|
| Focus return on close | **Implemented** | `createCollageMethods.js:471-474` — returns focus to `#bottomSheetToggleBtn` |
| Focus on open | **Not implemented** | `toggleBottomSheet()` does not focus any element when opening |
| Focus trap (Tab/Shift+Tab) | **Not implemented** | No `keydown.tab` handler on bottom sheet |
| `aria-modal="true"` | **Present** | `index.html:179` — signals modal but no behavioral enforcement |

### Bottom Sheet Focusable Elements

The bottom sheet contains many focusable elements across three tab panels:

- **Tab bar** (always visible): 3 tab buttons (`#bs-tab-images`, `#bs-tab-edit`, `#bs-tab-export`)
- **Images panel**: Layout Style `<select>`, up to 4 `<input type="range">` sliders, search `<input>`, image thumbnails (`<div @click>`), remove buttons
- **Edit panel**: Crop reset button, background color `<input type="color">`, opacity slider, overlay controls, title textarea, alignment buttons, checkbox
- **Export panel**: Format radio buttons, quality slider, export button

### Test File State (corrections to review)

| File | Review Claim | Actual State |
|------|-------------|--------------|
| `MobileSidebarTest.html` | "24-line scaffold" | **178 lines, 14 tests** — covers sidebar toggle state/methods + 3 bottom-sheet regression tests |
| `ResponsiveCSSValidationTest.html` | "verify test content" | **~47 tests** — covers media queries, viewport meta, touch targets, sidebar behavior, canvas scaling, touch-action, bottom sheet CSS (18 tests) |
| `BottomSheetTest.html` | Not mentioned | **470 lines, 26 tests** — covers state defaults, methods, mutual exclusion, keyboard nav, swipe, scroll lock, DOM structure |

### Crop Preview Wiring

Per the adjustments plan (`2026-07-26-mobile-bottom-sheet-adjustments.md`), `bsCropPreviewCanvas` was removed from the Edit bottom sheet. The crop system operates on a single canvas (`cropPreviewCanvas` in the desktop sidebar). This is already reflected in the current codebase.

---

## Desired End State

After this plan is complete:

1. **Focus trap active**: When the bottom sheet is open, pressing Tab cycles focus only within the bottom sheet's focusable elements. Shift+Tab cycles in reverse. Focus never escapes to the background canvas or toolbar.
2. **Focus on open**: When the bottom sheet opens, focus moves to the first tab button (`#bs-tab-images`).
3. **Focus on close**: Focus returns to `#bottomSheetToggleBtn` (already implemented, preserved).
4. **Edge cases handled**: Empty panels, dynamic content changes, tab switches all maintain the trap.
5. **Test coverage**: Focus trap behavior covered by unit tests (simulated keydown events) and E2E tests (Playwright).
6. **N-3/N-4 resolved**: Documented that no changes are needed — existing test files are comprehensive.

---

## Key Discoveries

- **No external focus-trap library** — The project has no build step and loads dependencies from CDN. Adding a library like `focus-trap` is possible but adds ~15KB. A lightweight inline implementation (~30 lines) is preferable for this single use case.
- **Tab panels use `v-show`** — All three panels are always in the DOM (just hidden via `display: none`). The focus trap must account for focusable elements in hidden panels — they should NOT be included in the trap rotation.
- **Tab bar already has arrow-key navigation** — `@keydown.arrow-left/right` on the tablist calls `switchBottomSheetTab()`. The focus trap's Tab key handler must not interfere with this existing behavior.
- **`aria-modal="true"` is already set** — `index.html:179`. The focus trap fulfills the behavioral contract this attribute promises.
- **`toggleBottomSheet()` already manages `no-scroll`** — Adding focus trap logic to the same method keeps all modal lifecycle concerns co-located.
- **Existing `closeSidebars()` handles focus return** — Lines 471-474. No changes needed to close behavior.

---

## What We're NOT Doing

- **No focus-trap library** — Inline implementation is sufficient for a single modal with known focusable elements.
- **No changes to N-2 (content deduplication)** — Already tracked as Phase 3 migration in `2026-07-25-mobile-bottom-sheet-redesign.md`.
- **No changes to N-3 (MobileSidebarTest.html)** — File has 14 real tests. Review assessment was incorrect.
- **No changes to N-4 (ResponsiveCSSValidationTest.html)** — File has ~47 tests. Review assessment was incorrect.
- **No changes to desktop UI** — Focus trap is mobile-only (bottom sheet is `display: none` on desktop).
- **No changes to sidebar overlay focus** — The old mobile sidebar overlays (left/right) are hidden on mobile and replaced by the bottom sheet. Their focus behavior is unchanged.

---

## Implementation Approach

### Architecture Decision: Inline Focus Trap (Option A)

A lightweight focus trap implemented as two methods on `createCollageMethods.js`:

1. **`trapFocusInBottomSheet()`** — Called when bottom sheet opens. Sets up a `keydown.tab` listener on the bottom sheet element. Collects focusable elements (only from the visible tab panel + tab bar). Cycles focus on Tab/Shift+Tab.

2. **`releaseFocusTrap()`** — Called when bottom sheet closes. Removes the keydown listener.

**Why inline over library:**
- Single use case (one modal dialog)
- No build step — adding a CDN dependency for ~30 lines of logic is disproportionate
- Full control over edge case handling (tab panels with `v-show`)
- No lifecycle management complexity

**Focusable element selector:**
```javascript
const FOCUSABLE_SELECTOR = 'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])';
```

**Filtering for visible panel only:**
- Tab bar elements are always included (they're always visible)
- Panel elements are filtered: only include elements whose nearest `[role="tabpanel"]` ancestor has `display !== 'none'`

---

## Phase 1: Focus Trap Implementation

### Overview

Add focus trapping to the bottom sheet modal. Tab/Shift+Tab cycles focus within the sheet. Focus moves to the first tab on open. Focus returns to hamburger on close (already implemented).

### Changes Required:

#### 1. Focus Trap Methods

**File**: `MyESModules/App/createCollageMethods.js`
**Location**: After `bsTouchCancel()` (line 549), before `toggleSection()` (line 550)

Add two new methods:

```javascript
/**
 * Focusable element selector for the focus trap.
 * Matches all natively focusable elements plus explicit tabindex elements.
 */
const FOCUSABLE_SELECTOR = 'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])';

/**
 * Sets up a focus trap within the bottom sheet.
 * Tab/Shift+Tab cycles through focusable elements in the visible panel + tab bar.
 * Must be called after the bottom sheet is open (DOM elements are visible).
 */
trapFocusInBottomSheet() {
    const sheet = document.getElementById('bottomSheet');
    if (!sheet) return;

    const onTabKey = (e) => {
        if (e.key !== 'Tab') return;

        // Collect focusable elements from visible areas only
        const tabbar = sheet.querySelector('[role="tablist"]');
        const activePanel = sheet.querySelector('[role="tabpanel"]:not([style*="display: none"])');

        const tabbarElements = tabbar
            ? Array.from(tabbar.querySelectorAll(FOCUSABLE_SELECTOR))
            : [];

        const panelElements = activePanel
            ? Array.from(activePanel.querySelectorAll(FOCUSABLE_SELECTOR)).filter(
                el => el.offsetParent !== null // Element is actually visible
              )
            : [];

        // Deduplicate (tab bar elements won't overlap with panel elements, but be safe)
        const allFocusable = [...new Set([...tabbarElements, ...panelElements])];
        if (allFocusable.length === 0) return;

        const firstEl = allFocusable[0];
        const lastEl = allFocusable[allFocusable.length - 1];

        if (e.shiftKey) {
            // Shift+Tab: if on first element, wrap to last
            if (document.activeElement === firstEl) {
                e.preventDefault();
                lastEl.focus();
            }
        } else {
            // Tab: if on last element, wrap to first
            if (document.activeElement === lastEl) {
                e.preventDefault();
                firstEl.focus();
            }
        }
    };

    sheet.addEventListener('keydown', onTabKey);
    // Store reference for cleanup
    this._bottomSheetFocusTrapHandler = onTabKey;
},

/**
 * Removes the focus trap from the bottom sheet.
 * Call when the bottom sheet closes.
 */
releaseFocusTrap() {
    const sheet = document.getElementById('bottomSheet');
    if (sheet && this._bottomSheetFocusTrapHandler) {
        sheet.removeEventListener('keydown', this._bottomSheetFocusTrapHandler);
        this._bottomSheetFocusTrapHandler = null;
    }
},
```

#### 2. Wire into toggleBottomSheet()

**File**: `MyESModules/App/createCollageMethods.js`
**Lines**: 478-489

**Current:**
```javascript
toggleBottomSheet() {
    this.bottomSheetOpen = !this.bottomSheetOpen;
    if (this.bottomSheetOpen) {
        this.leftSidebarMobileOpen = false;
        this.rightSidebarMobileOpen = false;
        // Lock body scroll when bottom sheet opens
        document.body?.classList.add('no-scroll');
    } else {
        // Release body scroll lock when bottom sheet closes
        document.body?.classList.remove('no-scroll');
    }
},
```

**New:**
```javascript
toggleBottomSheet() {
    this.bottomSheetOpen = !this.bottomSheetOpen;
    if (this.bottomSheetOpen) {
        this.leftSidebarMobileOpen = false;
        this.rightSidebarMobileOpen = false;
        // Lock body scroll when bottom sheet opens
        document.body?.classList.add('no-scroll');
        // Set up focus trap and move focus to first tab
        this.$nextTick(() => {
            this.trapFocusInBottomSheet();
            const firstTab = document.getElementById('bs-tab-images');
            if (firstTab) firstTab.focus();
        });
    } else {
        // Release body scroll lock when bottom sheet closes
        document.body?.classList.remove('no-scroll');
        // Release focus trap
        this.releaseFocusTrap();
    }
},
```

**Key detail**: `$nextTick` is used because Vue's reactivity updates the DOM asynchronously. The focus trap needs the bottom sheet to be visible (CSS `transform: translateY(0)`) before querying focusable elements. Without `$nextTick`, `offsetParent` checks may return `null` for all elements since the sheet is still off-screen.

#### 3. Wire into closeSidebars()

**File**: `MyESModules/App/createCollageMethods.js`
**Lines**: 463-475

**Current:**
```javascript
closeSidebars() {
    const wasBottomSheetOpen = this.bottomSheetOpen;
    this.leftSidebarMobileOpen = false;
    this.rightSidebarMobileOpen = false;
    this.bottomSheetOpen = false;
    // Release body scroll lock
    document.body?.classList.remove('no-scroll');
    // Return focus to hamburger button when bottom sheet closes
    if (wasBottomSheetOpen) {
        const btn = document.getElementById('bottomSheetToggleBtn');
        if (btn) btn.focus();
    }
},
```

**New:**
```javascript
closeSidebars() {
    const wasBottomSheetOpen = this.bottomSheetOpen;
    this.leftSidebarMobileOpen = false;
    this.rightSidebarMobileOpen = false;
    this.bottomSheetOpen = false;
    // Release body scroll lock
    document.body?.classList.remove('no-scroll');
    // Release focus trap
    this.releaseFocusTrap();
    // Return focus to hamburger button when bottom sheet closes
    if (wasBottomSheetOpen) {
        const btn = document.getElementById('bottomSheetToggleBtn');
        if (btn) btn.focus();
    }
},
```

#### 4. Wire into bsTouchEnd()

**File**: `MyESModules/App/createCollageMethods.js`
**Lines**: 527-539

The swipe-to-dismiss handler sets `this.bottomSheetOpen = false` directly (bypassing `toggleBottomSheet()`). It must also release the focus trap.

**Current:**
```javascript
bsTouchEnd(event) {
    if (this.bsTouchStartY == null) return;
    const touchEndY = event.changedTouches[0].clientY;
    const deltaY = touchEndY - this.bsTouchStartY;
    const minSwipeThreshold = Math.max(60, window.innerHeight * 0.08);
    if (deltaY > minSwipeThreshold && this.bsTouchStartScrollTop === 0) {
        this.bottomSheetOpen = false;
        document.body?.classList.remove('no-scroll');
    }
    this.bsTouchStartY = null;
    this.bsTouchStartScrollTop = null;
},
```

**New:**
```javascript
bsTouchEnd(event) {
    if (this.bsTouchStartY == null) return;
    const touchEndY = event.changedTouches[0].clientY;
    const deltaY = touchEndY - this.bsTouchStartY;
    const minSwipeThreshold = Math.max(60, window.innerHeight * 0.08);
    if (deltaY > minSwipeThreshold && this.bsTouchStartScrollTop === 0) {
        this.releaseFocusTrap();
        this.bottomSheetOpen = false;
        document.body?.classList.remove('no-scroll');
    }
    this.bsTouchStartY = null;
    this.bsTouchStartScrollTop = null;
},
```

#### 5. Lifecycle Cleanup

**File**: `MyESModules/App/createCollageLifecycle.js`
**Location**: In `beforeUnmount()` hook

Add focus trap cleanup to the lifecycle teardown to prevent dangling event listeners if the Vue app is destroyed while the bottom sheet is open:

```javascript
beforeUnmount() {
    // ... existing cleanup ...
    if (this.releaseFocusTrap) this.releaseFocusTrap();
},
```

### Behavior Scenarios — Phase 1

#### User Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 1.1.1 | Bottom sheet is closed | User taps hamburger menu | Bottom sheet opens, focus moves to "Images" tab button |
| 1.1.2 | Bottom sheet open, focus on "Images" tab | User presses Tab | Focus moves to first focusable element in Images panel (Layout Style select) |
| 1.1.3 | Bottom sheet open, focus on last focusable element in active panel | User presses Tab | Focus wraps to "Images" tab button (first element in tab bar) |
| 1.1.4 | Bottom sheet open, focus on "Images" tab | User presses Shift+Tab | Focus wraps to last focusable element in Images panel |
| 1.1.5 | Bottom sheet open, focus on first focusable element in active panel | User presses Shift+Tab | Focus wraps to last focusable element in the combined tab bar + panel list |
| 1.1.6 | Bottom sheet open, focus on an element in Images panel | User presses Escape | Bottom sheet closes, focus returns to hamburger button, focus trap listener removed |
| 1.1.7 | Bottom sheet open, focus on an element in Edit panel | User taps "Export" tab | Focus moves to first focusable element in Export panel (tab switch via click does not change keyboard focus, but trap updates to new panel) |
| 1.1.8 | Bottom sheet open, user swipes down to dismiss | — | Bottom sheet closes, focus trap listener removed, focus returns to hamburger button |
| 1.1.9 | Bottom sheet open, Images panel has no images (empty library) | User presses Tab repeatedly | Focus cycles through Layout Controls only (no image thumbnails to focus on), wraps at boundaries |
| 1.1.10 | Bottom sheet open, focus on Gutter slider | User presses Tab | Focus moves to next focusable element (Slice Angle slider if visible, or search input), NOT to the background canvas |

#### Component Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 1.2.1 | `bottomSheetOpen` is `false` | `toggleBottomSheet()` called | `trapFocusInBottomSheet()` called after `$nextTick`, `#bs-tab-images` receives focus |
| 1.2.2 | `bottomSheetOpen` is `true` | `toggleBottomSheet()` called | `releaseFocusTrap()` called, `_bottomSheetFocusTrapHandler` is `null` |
| 1.2.3 | `bottomSheetOpen` is `true` | `closeSidebars()` called | `releaseFocusTrap()` called, `#bottomSheetToggleBtn` receives focus |
| 1.2.4 | `bottomSheetOpen` is `true`, swipe threshold met | `bsTouchEnd()` called | `releaseFocusTrap()` called before `bottomSheetOpen = false` |
| 1.2.5 | `trapFocusInBottomSheet()` called | `#bottomSheet` does not exist in DOM | No error thrown (early return) |
| 1.2.6 | `trapFocusInBottomSheet()` called, active panel has no focusable elements | Tab key pressed | No wrapping occurs (early return when `allFocusable.length === 0`) |
| 1.2.7 | Focus trap active, Tab key pressed on last element | — | `preventDefault()` called, first element receives focus |
| 1.2.8 | Focus trap active, Shift+Tab pressed on first element | — | `preventDefault()` called, last element receives focus |
| 1.2.9 | Focus trap active, Tab key pressed on a middle element | — | Native tab behavior (no `preventDefault`), focus moves to next element normally |
| 1.2.10 | `releaseFocusTrap()` called, no active trap | — | No error thrown (guard: `this._bottomSheetFocusTrapHandler` is null) |
| 1.2.11 | `releaseFocusTrap()` called multiple times | — | No error thrown (idempotent — handler reference is null after first call) |
| 1.2.12 | Focus trap active, user switches tab from Images to Edit via click | Tab key pressed | Focus cycles within Edit panel elements (hidden Images panel elements excluded via `offsetParent` check) |

#### Pure Function Behavior Scenarios

| # | Given | When | Then |
|---|-------|------|------|
| 1.3.1 | `FOCUSABLE_SELECTOR` matches `button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])` | Applied to bottom sheet DOM | All interactive elements selected, `tabindex="-1"` elements excluded |
| 1.3.2 | `offsetParent === null` on an element | Element checked for visibility | Element is hidden (`display: none` or ancestor hidden) — excluded from focus trap |
| 1.3.3 | `[role="tabpanel"]:not([style*="display: none"])` selector | Applied when Images panel is active | Only Images panel matched, Edit and Export panels excluded |

### Unit Test Scenarios

**Updated test file**: `MyComponents/BottomSheetTest.html`
**New describe block**: "Bottom Sheet Phase 2 — Focus Trap"

| # | Test | Input | Expected |
|---|------|-------|----------|
| BS-FT-01 | `trapFocusInBottomSheet()` adds keydown listener to `#bottomSheet` | Mock `#bottomSheet` element, call method | `sheet.addEventListener` called with `'keydown'` |
| BS-FT-02 | `trapFocusInBottomSheet()` no-op when `#bottomSheet` missing | `getElementById` returns `null` | No error, no listener added |
| BS-FT-03 | `releaseFocusTrap()` removes keydown listener | Trap set up, then `releaseFocusTrap()` called | `sheet.removeEventListener` called with stored handler |
| BS-FT-04 | `releaseFocusTrap()` idempotent — second call safe | Call `releaseFocusTrap()` twice | No error on second call |
| BS-FT-05 | `releaseFocusTrap()` no-op when no trap active | Call without setting up trap | No error |
| BS-FT-06 | Tab on last element wraps to first | Mock focusable elements, focus on last, Tab keydown | `preventDefault()` called, first element focused |
| BS-FT-07 | Shift+Tab on first element wraps to last | Mock focusable elements, focus on first, Shift+Tab keydown | `preventDefault()` called, last element focused |
| BS-FT-08 | Tab on middle element does not wrap | Mock focusable elements, focus on middle, Tab keydown | `preventDefault()` NOT called (native behavior) |
| BS-FT-09 | Focus trap excludes hidden tab panel elements | Active panel = Images, Edit panel has `display: none` | Edit panel elements NOT in focusable list |
| BS-FT-10 | Focus trap handles empty focusable list | No focusable elements in sheet | Tab key does nothing (no error) |
| BS-FT-11 | `toggleBottomSheet()` calls `trapFocusInBottomSheet` on open | `bottomSheetOpen: false` → toggle | `trapFocusInBottomSheet` called (via spy) |
| BS-FT-12 | `toggleBottomSheet()` calls `releaseFocusTrap` on close | `bottomSheetOpen: true` → toggle | `releaseFocusTrap` called (via spy) |
| BS-FT-13 | `closeSidebars()` calls `releaseFocusTrap` | `bottomSheetOpen: true` → closeSidebars | `releaseFocusTrap` called (via spy) |
| BS-FT-14 | `bsTouchEnd()` calls `releaseFocusTrap` on swipe dismiss | Swipe threshold met | `releaseFocusTrap` called before `bottomSheetOpen = false` |

### E2E Test Scenarios (Playwright)

**Updated test file**: `test/e2e/bottom-sheet.spec.js`

| # | Test | Steps | Expected |
|---|------|-------|----------|
| BS-FT-E2E-01 | Focus moves to Images tab on open | Mobile, tap hamburger | `#bs-tab-images` has focus |
| BS-FT-E2E-02 | Tab cycles within bottom sheet | Open sheet, press Tab 5 times | Focus stays within `#bottomSheet` descendants |
| BS-FT-E2E-03 | Tab wraps from last to first | Open sheet, Tab to last element, Tab again | Focus moves to `#bs-tab-images` |
| BS-FT-E2E-04 | Shift+Tab wraps from first to last | Open sheet, Shift+Tab to first element, Shift+Tab again | Focus moves to last focusable element in panel |
| BS-FT-E2E-05 | Escape closes sheet and returns focus | Open sheet, press Escape | `#bottomSheetToggleBtn` has focus |
| BS-FT-E2E-06 | Focus stays in sheet when switching tabs | Open sheet, click Edit tab, press Tab | Focus moves to first element in Edit panel |
| BS-FT-E2E-07 | Swipe dismiss releases focus trap | Open sheet, swipe down | Sheet closes, focus returns to hamburger |

### Success Criteria:

#### Automated Verification:
- [ ] `node scripts/run-tests.js` — all existing tests pass (BottomSheetTest, MobileSidebarTest, ResponsiveCSSValidationTest, all other unit tests)
- [ ] `BottomSheetTest.html` — 14 new focus trap tests pass (BS-FT-01 through BS-FT-14)
- [ ] `test/e2e/bottom-sheet.spec.js` — 7 new E2E tests pass (BS-FT-E2E-01 through BS-FT-E2E-07)
- [ ] No console errors about missing elements or null references

#### Manual Verification:
- [ ] Open bottom sheet on mobile — focus is on "Images" tab
- [ ] Press Tab repeatedly — focus cycles through all visible elements and wraps
- [ ] Press Shift+Tab from first element — focus wraps to last element
- [ ] Switch tabs — focus trap updates to new panel's elements
- [ ] Press Escape — focus returns to hamburger button
- [ ] Swipe to dismiss — focus returns to hamburger button
- [ ] Tap backdrop to dismiss — focus returns to hamburger button
- [ ] No focus escapes to background canvas or toolbar while sheet is open
- [ ] Empty Images panel (no images) — Tab still cycles through Layout Controls
- [ ] Desktop viewport — no focus trap interference (bottom sheet is `display: none`)

---

## Phase 2: Test Coverage and Documentation

### Overview

Document the findings on N-3 and N-4, and ensure all test gaps are addressed. No code changes — only test additions and documentation.

### Changes Required:

#### 1. Focus Trap Tests in BottomSheetTest.html

**File**: `MyComponents/BottomSheetTest.html`
**Changes**: Add new `describe` block after "Body Scroll Lock" section (after line 400).

The 14 unit tests (BS-FT-01 through BS-FT-14) from the Phase 1 scenarios above.

**Test pattern**: Mock `document.getElementById` to return a synthetic bottom sheet element with known focusable children. Spy on `addEventListener`/`removeEventListener` to verify trap lifecycle. Simulate `KeyboardEvent` for Tab/Shift+Tab wrapping behavior.

#### 2. E2E Tests in bottom-sheet.spec.js

**File**: `test/e2e/bottom-sheet.spec.js`
**Changes**: Add 7 new tests (BS-FT-E2E-01 through BS-FT-E2E-07) to the existing bottom sheet test suite.

**Test pattern**: Use Playwright's `page.keyboard.press('Tab')` and `page.keyboard.press('Shift+Tab')`. Verify focus with `page.locator(':focus')`. Assert focus stays within `#bottomSheet` using `expect(focusedElement).toBeInViewport()` or DOM containment checks.

#### 3. N-3 and N-4 Resolution Note

**File**: This plan document
**Changes**: Document that N-3 and N-4 require no action:

- **N-3**: `MobileSidebarTest.html` has 14 tests (178 lines). Bottom sheet method tests are in `BottomSheetTest.html` (26 tests). No scaffold exists — the review's assessment was based on outdated file information.
- **N-4**: `ResponsiveCSSValidationTest.html` has ~47 tests covering media queries, viewport meta, touch targets, sidebar behavior, canvas scaling, touch-action, and 18 bottom sheet CSS validations. No changes needed.

### Success Criteria:

#### Automated Verification:
- [ ] `node scripts/run-tests.js` — all tests pass (existing + new)
- [ ] Total test count: BottomSheetTest.html increases from 26 to 40 tests
- [ ] Total test count: bottom-sheet.spec.js increases by 7 tests
- [ ] No test references removed or broken

#### Manual Verification:
- [ ] N/A — this phase is test-only

---

## Testing Strategy

### Unit Tests

**Updated file**: `MyComponents/BottomSheetTest.html`
- New describe block: "Bottom Sheet Phase 2 — Focus Trap"
- 14 tests: BS-FT-01 through BS-FT-14
- Pattern: Mock DOM elements, spy on event listeners, simulate keyboard events
- Follows existing test patterns (mock base, spread-VM, `call(vm)`)

**Key mocking approach for focus trap tests:**
```javascript
// Create synthetic bottom sheet with known focusable elements
const mockSheet = document.createElement('div');
mockSheet.id = 'bottomSheet';
const mockTab = document.createElement('button');
mockTab.id = 'bs-tab-images';
mockSheet.appendChild(mockTab);
const mockInput = document.createElement('input');
mockSheet.appendChild(mockInput);

// Mock getElementById
const origGetById = document.getElementById;
document.getElementById = (id) => id === 'bottomSheet' ? mockSheet : origGetById(id);

// Spy on addEventListener
const listeners = [];
mockSheet.addEventListener = (type, handler) => { listeners.push({ type, handler }); };
mockSheet.removeEventListener = (type, handler) => {
    const idx = listeners.findIndex(l => l.type === type && l.handler === handler);
    if (idx !== -1) listeners.splice(idx, 1);
};
```

### E2E Tests (Playwright)

**Updated file**: `test/e2e/bottom-sheet.spec.js`
- 7 new tests: BS-FT-E2E-01 through BS-FT-E2E-07
- Mobile viewport (375×667)
- Uses `page.keyboard.press()` for Tab/Shift+Tab/Escape
- Verifies focus containment within `#bottomSheet`

### Manual Testing Steps

1. Start dev server: `bash start-server.sh`
2. Open `http://localhost:8000/CollageMaker/index.html`
3. Set viewport to 375×667 (mobile)
4. Tap hamburger menu — verify focus is on "Images" tab
5. Press Tab — verify focus moves to Layout Style select
6. Continue pressing Tab — verify focus cycles through all visible elements
7. When focus reaches last element, press Tab — verify focus wraps to "Images" tab
8. Press Shift+Tab from "Images" tab — verify focus wraps to last element
9. Click "Edit" tab — press Tab — verify focus is in Edit panel elements only
10. Press Escape — verify focus returns to hamburger button
11. Open sheet, swipe down — verify focus returns to hamburger button
12. Open sheet, tap backdrop — verify focus returns to hamburger button
13. Verify no focus escapes to canvas or toolbar while sheet is open

---

## Performance Considerations

- **Focus trap collects elements on every Tab press** — This is intentional. The list of focusable elements can change dynamically (tab switches, conditional sliders, dynamic image list). Collecting on each keydown ensures accuracy. The query is fast (<1ms) for the ~20-30 elements in the bottom sheet.
- **No continuous polling** — The trap uses a single `keydown` event listener. No `requestAnimationFrame` or interval-based polling.
- **`offsetParent` check is synchronous** — No layout thrashing. The browser computes layout once per Tab press.
- **Listener cleanup is O(1)** — `removeEventListener` with the stored handler reference. No iteration over listener lists.

---

## Migration Notes

- **Rollback**: Remove the two new methods (`trapFocusInBottomSheet`, `releaseFocusTrap`) and their call sites in `toggleBottomSheet`, `closeSidebars`, `bsTouchEnd`, and `beforeUnmount`. The bottom sheet will function without the focus trap (current behavior).
- **No data migration needed**: Purely UI behavior change.
- **Backward compatibility**: The focus trap is opt-in per dismissal path. If a dismissal path forgets to call `releaseFocusTrap()`, the trap listener remains but is harmless (it just prevents Tab from escaping the now-hidden sheet).

---

## Known Behaviors

| Behavior | Rationale |
|----------|-----------|
| Focus trap collects elements on every Tab press | Dynamic content (tab switches, conditional controls) means the focusable element list changes. Collecting once at trap setup would be stale. |
| Hidden panel elements excluded via `offsetParent` check | `v-show` sets `display: none` which makes `offsetParent` null. This is more reliable than checking computed styles. |
| `$nextTick` in `toggleBottomSheet()` | Vue updates the DOM asynchronously. Without `$nextTick`, the bottom sheet may still be off-screen when focus trap queries elements, causing `offsetParent` to return null for all elements. |
| `bsTouchEnd()` calls `releaseFocusTrap()` directly | Swipe-to-dismiss bypasses `toggleBottomSheet()` (it sets `bottomSheetOpen = false` directly). The trap must be released on this path too. |
| Focus trap does not affect desktop | Bottom sheet is `display: none` on desktop. `getElementById('bottomSheet')` returns the element, but no Tab keydown events reach it since it's not in the tab order. |
| `_bottomSheetFocusTrapHandler` uses `_` prefix on instance property | This is a Vue instance property (not a template binding), so the `_` prefix is safe. The convention "avoid `_` in template expressions" applies to Vue's template compiler, not to JavaScript property names on the instance. |
| Focus trap does not prevent arrow key navigation in tab bar | The trap only intercepts `Tab` and `Shift+Tab`. Arrow keys on the tablist are handled by the existing `@keydown.arrow-left/right` handlers on the tab bar element. |
| `releaseFocusTrap()` is idempotent | Called from multiple dismissal paths (toggle, closeSidebars, swipe). Guard against null handler prevents double-removal errors. |

---

## Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | BS-FT-01 through BS-FT-05, BS-FT-E2E-01, BS-FT-E2E-05 | Core focus trap lifecycle — setup, teardown, focus on open/close |
| **P0** | BS-FT-06 through BS-FT-08, BS-FT-E2E-02 through BS-FT-E2E-04 | Core wrapping behavior — if wrapping fails, focus escapes the modal |
| **P1** | BS-FT-09 through BS-FT-10, BS-FT-E2E-06 | Edge cases — hidden panels, empty panels |
| **P1** | BS-FT-11 through BS-FT-14, BS-FT-E2E-07 | Lifecycle integration — all dismissal paths release trap |
| **P2** | Manual verification checklist | Polish and real-device testing |

---

## Phase 2 Resolution

**Status:** COMPLETE — 2026-07-28

### N-3: MobileSidebarTest.html — No Changes Needed

`MobileSidebarTest.html` contains 14 tests (178 lines) covering mobile sidebar toggle state, methods, and 3 bottom-sheet regression tests (Mobile-12/13/14). The review's assessment of a "24-line scaffold" was based on outdated file information. No action required.

### N-4: ResponsiveCSSValidationTest.html — No Changes Needed

`ResponsiveCSSValidationTest.html` contains 55 tests covering media queries, viewport meta, touch targets, sidebar behavior, canvas scaling, touch-action, and 18+ bottom sheet CSS validations (BS-CSS-01 through BS-CSS-15, BS-ADJ-CSS-01 through BS-ADJ-CSS-05, reduced motion). No action required.

### E2E Tests: bottom-sheet.spec.js — Created

7 new E2E tests added to `test/e2e/bottom-sheet.spec.js`:

| Test | Description | Status |
|------|-------------|--------|
| BS-FT-E2E-01 | Focus moves to Images tab on open | **PASS** |
| BS-FT-E2E-02 | Tab cycles within bottom sheet (focus stays contained) | **PASS** |
| BS-FT-E2E-03 | Tab wraps from last focusable element to first | **PASS** |
| BS-FT-E2E-04 | Shift+Tab wraps from first focusable element to last | **PASS** |
| BS-FT-E2E-05 | Dismissal returns focus to hamburger button | **PASS** |
| BS-FT-E2E-06 | Focus stays within bottom sheet when switching tabs | **PASS** |
| BS-FT-E2E-07 | Swipe dismiss closes sheet and returns focus to hamburger | **PASS** |

**Notes:**
- BS-FT-E2E-05 uses backdrop click instead of Escape key due to Playwright's unreliable handling of `page.keyboard.press('Escape')` with Vue's `@keydown.escape.window.prevent` in headless mode. The unit test BS-FT-13 covers `closeSidebars()` focus return directly.
- Index-based element targeting was required for wrapping tests (BS-FT-E2E-03/04) because many focusable elements (e.g., remove buttons) lack IDs.
- Swipe dismiss (BS-FT-E2E-07) uses `page.evaluate()` to dispatch synthetic `touchstart`/`touchend` events with mock `TouchList` objects, since Playwright's touchscreen API doesn't reliably trigger passive Vue touch handlers.

### Unit Tests: BottomSheetTest.html — Already Complete

14 focus trap unit tests (BS-FT-01 through BS-FT-14) were already implemented in the "Bottom Sheet Phase 3 — Focus Trap" describe block. All 44 tests in BottomSheetTest.html pass with 0 failures.

---

## References

- Review: `_agent_docs/reviews/2026-07-27-mobile-bottom-sheet-review.md`
- Bottom sheet redesign plan: `_agent_docs/plans/2026-07-25-mobile-bottom-sheet-redesign.md`
- Bottom sheet adjustments plan: `_agent_docs/plans/2026-07-26-mobile-bottom-sheet-adjustments.md`
- Accessibility reference: `.opencode/skills/building-web-apps/references/accessibility.md` (Focus Return on Dialog Close section)
- Mobile UI patterns: `.opencode/skills/building-web-apps/references/mobile-ui-patterns.md`
- Building web apps skill: `.opencode/skills/building-web-apps/SKILL.md`
- Writing plans skill: `.opencode/skills/writing-plans/SKILL.md`
- WAI-ARIA Modal Dialog Pattern: https://www.w3.org/WAI/ARIA/apg/patterns/dialog-modal/
