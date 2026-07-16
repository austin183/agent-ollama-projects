# Keyboard Handler Patterns

**Date:** 2026-07-03  
**Session:** 22 (Section 3.1 — Keyboard Shortcuts)  
**Module:** `MyESModules/Interaction/KeyboardHandler.js`

## Summary

The keyboard handler uses a three-layer architecture: pure parsing functions, pattern matching, and a factory-based event handler with attach/detach lifecycle. The key design decisions around modifier equivalence, bare-key leniency, and preventDefault ordering emerged from test-driven development and world-review feedback.

---

## Architecture Pattern

```
parseKeyShortcut(event)     → pure: KeyboardEvent → {key, meta, ctrl, shift, alt}
matchesShortcut(parsed, pattern) → pure: parsed object + string → boolean
createKeyboardHandler({callbacks}) → factory: returns {attach, detach, handleKeydown}
KEYBOARD_SHORTCUTS          → constant map of shortcut names to patterns/values
```

- Pure functions (`parseKeyShortcut`, `matchesShortcut`) are exported for unit testing without DOM dependencies.
- The factory creates a handler with closure-scoped state (`_attached`, `_listener`, `_callbacks`).
- Layout shortcuts use `{ pattern, value }` objects; simple shortcuts use strings; DELETE/BACKSPACE uses an array of patterns (both map to `onRemoveSelected`).

## matchesShortcut: Modifier Rules

| Rule | Rationale |
|------|-----------|
| `"meta+"` matches both `metaKey` AND `ctrlKey` | Cross-platform: Cmd on macOS, Ctrl on Windows/Linux |
| Pattern parts are order-insensitive | `"shift+meta+z"` === `"meta+shift+z"` |
| Key comparison is case-insensitive | `(parsed.key || '').toLowerCase() !== patternKey` |
| Alt is always strict | `hasAlt !== parsed.alt` — alt reserved for menus, never lenient |
| Shift: strict when pattern specifies it; **lenient for bare keys** | `Shift+Delete` matches `"Delete"` because no explicit shift in pattern |

### Bare-Key Leniency Logic

```javascript
const isBareKey = !hasMeta && !hasShift && !hasAlt;
// ...
if (hasShift && !parsed.shift) return false;           // Pattern says shift, event doesn't → fail
if (!isBareKey && !hasShift && parsed.shift) return false;  // Non-bare key with extra shift → fail
```

**Why?** `Shift+Delete` is a common variant of Delete. But `Alt+S` should NOT match `"s"` because alt is reserved for menus (always strict). The leniency only applies to **shift on bare keys**.

### Ctrl without meta is rejected for non-meta patterns

```javascript
if (!hasMeta && parsed.ctrl) return false;
```

A pattern of just `"s"` does NOT match `Ctrl+S` — that would conflict with browser defaults. This preserves the distinction between global shortcuts (`meta+s`) and modifier-less keys.

## Focus-Aware Suppression: SHORTCUT_SAFE_INPUT_TYPES

Instead of suppressing all `<input>` elements, use an **allow-list** of input types where shortcuts should still fire:

```javascript
const SHORTCUT_SAFE_INPUT_TYPES = new Set([
    'button', 'submit', 'reset',   // Interactive controls — not text entry
    'checkbox', 'radio',            // Toggles — keyboard expected
    'color',                        // Color picker — click-driven, keyboard rare
    'range',                        // Slider — arrow keys drive value
    'number'                        // Numeric input — arrow keys drive value
]);

function _isFocusInEditableElement(e) {
    const el = e.target;
    if (!el) return false;
    const tag = (el.tagName || '').toLowerCase();
    if (tag === 'textarea' || tag === 'select') return true;
    if (el.isContentEditable) return true;
    if (tag === 'input') {
        const inputType = (el.type || 'text').toLowerCase();
        if (!SHORTCUT_SAFE_INPUT_TYPES.has(inputType)) return true;  // Suppress text-like inputs
    }
    return false;
}
```

**What's suppressed:** `<input type="text">`, `password`, `search`, `email`, `url`, `tel`, `date`, etc. — any input that accepts free-form text entry.

**What's allowed:** sliders, color pickers, checkboxes, radios, buttons — controls where keyboard shortcuts are expected to work.

## preventDefault Ordering Rule

**Call `preventDefault()` AFTER the callback succeeds**, not before. If a callback throws:
- The error is caught and logged via `console.error`
- `preventDefault()` is NOT called (browser default can still fire)
- The handler remains functional for subsequent events

```javascript
try {
    cb();  // or cb(shortcut.value) for layouts
    e.preventDefault();  // Only suppress browser default on success
} catch (err) {
    console.error('Keyboard shortcut failed (' + name + '):', err);
}
```

**Edge case:** If the shortcut is recognized but no callback is registered, `preventDefault()` IS still called to suppress browser defaults (e.g., Cmd+S save dialog).

## Test-Driven Discoveries

These bugs were found during test implementation (Section 3.1):

| Bug | Root Cause | Fix |
|-----|-----------|-----|
| `matchesShortcut` failed on `{key:'Escape'}` vs pattern `'Escape'` | Pattern lowercased to `'escape'`, key not compared case-insensitively | `(parsed.key || '').toLowerCase()` in comparison |
| `KEYBOARD_SHORTCUTS` had 12 entries, plan expected 11 | DELETE and BACKSPACE were separate keys | Consolidated into single `DELETE_BACKSPACE: ['Delete', 'Backspace']` array pattern |
| `_isFocusInEditableElement` crashed on events with `target=document` (no tagName) | `el.tagName.toLowerCase()` assumed tagName exists | `(el.tagName || '').toLowerCase()` null guard |
| Lifecycle test 3.1.2.31 called `handleKeydown` directly instead of dispatching real event | Bypassed attach/detach mechanism entirely | Use `document.dispatchEvent(new KeyboardEvent(...))` for lifecycle tests |

## Test Conventions

- **Direct call tests** (callback dispatch, edge cases): Pass plain objects with mock `preventDefault: () => {}`. Works because `_isFocusInEditableElement` checks `el.tagName` which exists on mock targets.
- **Lifecycle tests** (attach/detach/keydown-only): Use real `KeyboardEvent` + `document.dispatchEvent()`. The event's target is `document`, not `document.body`.
- **Focus suppression tests**: Create actual DOM elements (`document.createElement('input')`) and pass them as `target`. Real elements have proper `tagName` and can be assigned `.type`.

## Related Files

- Production: `MyESModules/Interaction/KeyboardHandler.js`
- Tests: `MyComponents/KeyboardHandlerTest.html`, `test/e2e/keyboard-shortcuts.spec.js`
- Integration: `MyESModules/App/createCollageLifecycle.js` (mounted/beforeUnmount)
- Callbacks: `MyESModules/App/createCollageMethods.js` (`removeSelectedImage`)
