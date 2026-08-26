# Focus Trap for ARIA Modal Dialogs — Implementation and Testing Patterns

**Date:** 2026-07-27
**Session:** 2026-07-27-005 (Phase 1: Focus Trap Implementation)

## Summary

Implemented a lightweight inline focus trap for the mobile bottom sheet `aria-modal` dialog. Key learnings cover the focus trap algorithm, Vue `$nextTick` race condition guards, internal closure patterns for factory testability, focus return on all dismiss paths, and testing focus traps with `offsetParent` visibility checks.

---

## 1. Inline Focus Trap Algorithm

For a single modal dialog with known focusable elements, an inline focus trap (~30 lines) is preferable to adding a library dependency (~15KB). The trap intercepts Tab/Shift+Tab on the modal container and wraps focus at boundaries.

### Pattern

```javascript
const FOCUSABLE_SELECTOR = 'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])';

function trapFocus(container) {
    const onTabKey = (e) => {
        if (e.key !== 'Tab') return;

        // Collect focusable elements from visible areas only
        const allFocusable = Array.from(container.querySelectorAll(FOCUSABLE_SELECTOR))
            .filter(el => el.offsetParent !== null); // Only visible elements
        if (allFocusable.length === 0) return;

        const firstEl = allFocusable[0];
        const lastEl = allFocusable[allFocusable.length - 1];

        if (e.shiftKey) {
            if (document.activeElement === firstEl) {
                e.preventDefault();
                lastEl.focus();
            }
        } else {
            if (document.activeElement === lastEl) {
                e.preventDefault();
                firstEl.focus();
            }
        }
    };
    container.addEventListener('keydown', onTabKey);
    return onTabKey; // Return handler reference for cleanup
}
```

### Key Decisions

- **Collect elements on every Tab press** — The list of focusable elements changes dynamically (tab switches, conditional controls, dynamic image lists). Collecting once at trap setup would be stale. The query is fast (<1ms) for ~20-30 elements.
- **`offsetParent !== null` for visibility** — More reliable than checking `display` computed style. Catches elements hidden by `display: none` AND elements whose ancestors are hidden. Does NOT catch `opacity: 0` or `visibility: hidden` — use `display: none` (via `v-show`) for hidden panels.
- **`preventDefault()` only at boundaries** — Middle elements use native Tab behavior. Only wrap at first/last elements.
- **Both Tab AND Shift+Tab** — Standard focus traps must handle both directions. Check `e.shiftKey`.

### File References

- `MyESModules/App/createCollageMethods.js` — `_trapFocusInBottomSheet()` and `_releaseFocusTrap()` closures

---

## 2. Vue `$nextTick` Race Condition Guard

When using `$nextTick` to defer DOM-dependent work (like focus trap setup), rapid user interactions can cause stale callbacks to fire after state has changed.

### The Problem

```javascript
// User rapidly opens and closes bottom sheet
toggleBottomSheet() {
    this.bottomSheetOpen = true;
    this.$nextTick(() => {
        // This fires AFTER user already closed the sheet
        this.trapFocusInBottomSheet(); // Sets up trap on hidden sheet!
    });
}
// User immediately closes
toggleBottomSheet() {
    this.bottomSheetOpen = false;
    this.releaseFocusTrap(); // Releases trap
    // But the $nextTick callback from the open is still queued...
}
```

### The Fix

Guard the `$nextTick` callback with a state check:

```javascript
this.$nextTick(() => {
    if (!this.bottomSheetOpen) return; // Guard against rapid close
    this.trapFocusInBottomSheet();
    const firstTab = document.getElementById('bs-tab-images');
    if (firstTab) firstTab.focus();
});
```

### When to Apply

Any `$nextTick` callback that performs DOM-dependent side effects (focus management, element queries, measurements) should include a guard that checks the triggering state is still current.

### File References

- `MyESModules/App/createCollageMethods.js` — `toggleBottomSheet()` with `$nextTick` guard

---

## 3. Internal Closure Pattern for Factory Testability

When a Vue factory method calls other methods on `this`, tests that mock partial VMs (spreading only state, not all methods) break. Using factory-scoped closures avoids `this` dependencies in internal lifecycle methods.

### The Problem

```javascript
// toggleBottomSheet calls this.trapFocusInBottomSheet()
// Test VM: { ...state } — doesn't have trapFocusInBottomSheet
// Result: TypeError: this.trapFocusInBottomSheet is not a function
```

### The Fix

Define internal functions at factory scope and have both the public methods and internal lifecycle methods use them:

```javascript
// Factory-scoped internal functions
let _focusTrapHandler = null;

function _trapFocus(vm) { /* ... */ }
function _releaseFocus(vm) { /* ... */ }

return {
    // Internal lifecycle methods use closures directly
    toggleBottomSheet() {
        if (this.isOpen) {
            _trapFocus(this);
        } else {
            _releaseFocus(this);
        }
    },

    // Public API delegates to closures
    trapFocusInBottomSheet() {
        _trapFocus(this);
    },
    releaseFocusTrap() {
        _releaseFocus(this);
    }
};
```

### Why Not Module-Level Exports?

Factory-scoped closures capture factory dependencies (like `FOCUSABLE_SELECTOR`) without creating new import dependencies. Module-level exports would require the test to import both the factory and the exported function.

### File References

- `MyESModules/App/createCollageMethods.js` — `_trapFocusInBottomSheet` / `_releaseFocusTrap` closures

---

## 4. Focus Return on All Dismiss Paths

A modal dialog MUST return focus to the trigger element on close. Every dismissal path must include this behavior.

### Common Dismissal Paths

| Path | Method | Focus Return |
|------|--------|-------------|
| Toggle button | `toggleBottomSheet()` close branch | ✅ `bottomSheetToggleBtn.focus()` |
| Escape key | `closeSidebars()` (via global handler) | ✅ `bottomSheetToggleBtn.focus()` |
| Backdrop tap | `closeSidebars()` (via `@click`) | ✅ `bottomSheetToggleBtn.focus()` |
| Swipe dismiss | `bsTouchEnd()` | ✅ `bottomSheetToggleBtn.focus()` |

### World-Review Catch

The world-review identified that `bsTouchEnd()` and `toggleBottomSheet()` close branch were missing focus return. `closeSidebars()` already had it. All three paths now consistently return focus.

### Pattern

```javascript
// At the end of every dismiss path:
const btn = document.getElementById('bottomSheetToggleBtn');
if (btn) btn.focus();
```

### File References

- `MyESModules/App/createCollageMethods.js` — Focus return in `toggleBottomSheet()`, `closeSidebars()`, `bsTouchEnd()`

---

## 5. Testing Focus Traps: `offsetParent` Gotcha

When testing focus trap behavior with synthetic DOM elements, `offsetParent` is `null` for detached elements. This causes the visibility filter (`el.offsetParent !== null`) to exclude ALL elements.

### The Problem

```javascript
const mockSheet = document.createElement('div');
const input = document.createElement('input');
mockSheet.appendChild(input);
// input.offsetParent === null (detached from document)
// Focus trap filter excludes it → empty focusable list
```

### The Fix

Mount the mock element to `document.body` before testing:

```javascript
const mockSheet = document.createElement('div');
mockSheet.id = 'bottomSheet';
// ... build DOM tree ...
document.body.appendChild(mockSheet); // Now offsetParent works

// Run test...

document.body.removeChild(mockSheet); // Cleanup
```

### Alternative Approaches

- **Mock `offsetParent`** — `Object.defineProperty(input, 'offsetParent', { get: () => mockSheet })` — works but fragile
- **Skip visibility filter in tests** — Not recommended; tests should match production behavior

### File References

- `MyComponents/BottomSheetTest.html` — BS-FT-06 through BS-FT-10 mount mock sheet to `document.body`

---

## 6. `getElementById` Mock Safety

When mocking `document.getElementById` in tests, falling through to the original function can cause "Illegal invocation" errors because `document.getElementById` requires a specific `this` context.

### The Problem

```javascript
const origGetById = document.getElementById;
document.getElementById = (id) => {
    if (id === 'bottomSheet') return mockSheet;
    return origGetById(id); // Illegal invocation!
};
```

### The Fix

Return `null` for unknown IDs instead of calling the original:

```javascript
document.getElementById = (id) => {
    if (id === 'bottomSheet') return mockSheet;
    return null; // Production code guards against null
};
```

### Why This Works

The production code already guards against null:
```javascript
const btn = document.getElementById('bottomSheetToggleBtn');
if (btn) btn.focus(); // Safe — null check prevents error
```

### File References

- `MyComponents/BottomSheetTest.html` — All focus trap tests use safe `getElementById` mocks

---

## What's NOT New (Already Documented)

- **ARIA dialog attributes** (`role="dialog"`, `aria-modal="true"`) — covered in `references/accessibility.md`
- **Body scroll lock** — covered in `2026-07-25-mobile-bottom-sheet-accessibility-scroll-lock.md`
- **ARIA tab keyboard navigation** — covered in `2026-07-25-mobile-bottom-sheet-accessibility-scroll-lock.md`
- **Keyboard activation (Enter + Space)** — covered in `2026-07-10-wcag-keyboard-activation-and-motion-accessibility.md`
- **Lifecycle cleanup** — covered in skill reference `references/memory-management.md`
