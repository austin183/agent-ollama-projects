# Keyboard Shortcut Conflicts

The keyboard shortcuts defined in `MyESModules/Interaction/KeyboardHandler.js` conflict with browser and OS-level shortcuts.

## Export Shortcut — `meta+s`

`meta+s` conflicts with the browser native "Save Page" shortcut on macOS. While `preventDefault()` suppresses the browser dialog, users expecting the standard save behavior will be confused.

**Change:** Rename to `meta+shift+s` or `meta+e` (Export). Update `KEYBOARD_SHORTCUTS.EXPORT` and the corresponding callback in `createCollageLifecycle.js`.

## Layout Shortcuts — `meta+1` through `meta+5`

On macOS Safari, `meta+[1-9]` switches between tabs. Users on Safari will experience unexpected tab switching when attempting layout changes.

**Options:**
- Switch to `alt+[1-5]` (no known conflicts)
- Keep current shortcuts but add a visual shortcut indicator in the UI so users know what to expect
- Add browser detection and swap shortcuts automatically for Safari

## Testing

Update `MyComponents/KeyboardHandlerTest.html` and `test/e2e/keyboard-shortcuts.spec.js` to match new shortcut definitions.
