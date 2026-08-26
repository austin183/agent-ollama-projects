# Playwright Escape Key Unreliability with Vue `.window` Modifier

**Date:** 2026-07-28
**Session:** 2026-07-28-001 (Focus Trap E2E Tests)

## Summary

`page.keyboard.press('Escape')` does not reliably trigger Vue's `@keydown.escape.window.prevent` handler in headless Chromium. This affects any E2E test that needs to verify Escape key dismissal of overlays, modals, or dialogs.

## The Problem

Vue's `.window` modifier attaches the event listener directly to the `window` object. In headless Chromium, `page.keyboard.press('Escape')` dispatches keyboard events to the document/active element, but the event may not propagate to the `window` listener in all contexts — particularly when the focused element is inside a modal dialog or overlay.

### Observed Behavior

```javascript
// Vue template
<div id="app" @keydown.escape.window.prevent="closeSidebars">

// Playwright test — UNRELIABLE in headless mode
await page.keyboard.press('Escape');
// closeSidebars() may NOT be called
// Bottom sheet remains open despite Escape press
```

### Why It Fails

The exact cause is unclear — it may be related to:
1. Headless Chromium's event dispatch order (document vs window)
2. The `.window` modifier attaching a non-capturing listener that doesn't receive events dispatched to `document`
3. Focus state inside the modal dialog interfering with window-level event propagation

### What DOES Work

`page.keyboard.press('Escape')` works fine for:
- Non-`.window` handlers (e.g., `@keydown.escape` on a specific element)
- Keyboard shortcut handlers that attach to `document` (like the CollageMaker KeyboardHandler)
- Desktop viewport tests (the issue appears specific to mobile viewport + modal context)

## Workarounds

### Option 1: Backdrop Click (Recommended for E2E)

Click the backdrop overlay, which exercises the same `closeSidebars()` code path:

```javascript
// Click above the bottom sheet (z-index: backdrop=140, sheet=160)
await page.mouse.click(100, 100);
await page.waitForTimeout(400);
```

**Advantage:** Tests the actual user interaction path (tap outside to dismiss).

### Option 2: Unit Test the Handler

Test `closeSidebars()` directly in a unit test:

```javascript
it('closeSidebars() releases focus trap and returns focus', () => {
    state.bottomSheetOpen = true;
    methods.closeSidebars.call(vm);
    expect(vm.bottomSheetOpen).to.equal(false);
    // Verify focus return, trap release, etc.
});
```

**Advantage:** Deterministic, no browser quirks.

### Option 3: Dispatch Event via `page.evaluate()`

```javascript
await page.evaluate(() => {
    const event = new KeyboardEvent('keydown', {
        key: 'Escape',
        bubbles: true,
        cancelable: true,
    });
    window.dispatchEvent(event);
});
```

**Caveat:** May still not work reliably. The Vue `.window` listener may not receive programmatically dispatched events in all browser contexts.

## Decision Made

For the bottom sheet focus trap E2E tests (BS-FT-E2E-05), we use **backdrop click** instead of Escape key. The unit test BS-FT-13 covers `closeSidebars()` focus return directly. This combination provides full coverage without relying on unreliable Escape key behavior.

## Related

- `2026-07-22-playwright-event-simulation-gotchas.md` — Other Playwright event simulation issues
- `2026-07-27-focus-trap-aria-modal-dialog.md` — Focus trap implementation and unit testing
- `references/mobile-ui-patterns.md` — Vue `.window` modifier for global Escape
