# Playwright E2E Event Simulation Gotchas

**Date:** 2026-07-22
**Session:** build-tdd undo-redo E2E tests

## Summary

When writing Playwright E2E tests for Vue apps that depend on native DOM events for state management (e.g., `@focus` for snapshots, `@select` for selection tracking), several Playwright methods do NOT fire the events that Vue handlers expect.

## Gotcha 1: `el.focus()` Does NOT Fire `focus` Event

In headless Chromium, calling `element.focus()` programmatically changes the focus state but does NOT fire a `focus` event. This means Vue's `@focus` handlers won't execute.

**Problem:** The CollageMaker layout style change uses `@focus="snapshotLayoutStyle"` to capture the pre-change state. If the focus event doesn't fire, no snapshot is captured, and no undo command is created.

```javascript
// BAD — focus() does NOT fire focus event
await page.evaluate((selector) => {
    const el = document.querySelector(selector);
    el.focus();           // Changes focus state but NO event fired
    el.value = 'uniform'; // v-model updates
    el.dispatchEvent(new Event('change', { bubbles: true }));
}, '#layoutStyleSelect');
// Result: @focus handler never runs, no snapshot, no undo command

// GOOD — explicitly dispatch focus event
await page.evaluate((args) => {
    const el = document.querySelector(args.selector);
    el.focus();
    el.dispatchEvent(new Event('focus', { bubbles: true })); // Explicit dispatch
    setTimeout(() => {
        el.value = args.value;
        el.dispatchEvent(new Event('change', { bubbles: true }));
    }, 50);
}, { selector: '#layoutStyleSelect', value: 'uniform' });
```

**Workaround:** Use `locator.focus()` which may fire the event in some contexts, or use keyboard shortcuts (Alt+1 through Alt+5) that bypass the focus/change pattern entirely.

## Gotcha 2: `page.selectText()` Does NOT Fire `select` Event

Playwright's `locator.selectText()` selects all text in an input/textarea but does NOT fire the `select` event. Vue's `@select` handlers for tracking selection range won't execute.

**Problem:** The CollageMaker title formatting uses `@select="onTitleSelectionChange"` to capture `titleSelectionStart` and `titleSelectionEnd`. Without these values, the bold/italic/underline toggle handlers see `start === end` and skip the action.

```javascript
// BAD — selectText() does NOT fire select event
await page.locator('#titleInput').selectText();
// Result: titleSelectionStart/End remain at 0, bold button stays disabled

// GOOD — set selection range and dispatch select event
await page.evaluate(() => {
    const el = document.getElementById('titleInput');
    el.focus();
    const len = el.value.length;
    el.setSelectionRange(0, len);
    el.dispatchEvent(new Event('select', { bubbles: true }));
});
```

**Also doesn't work:** `page.keyboard.press('Control+a')` — fires keydown/keyup but not `select` event in headless Chromium.

## Gotcha 3: `page.fill()` Does NOT Work on Range Inputs

`page.fill()` only works on text inputs, textareas, and `<select>` elements. It silently fails (or throws) on `<input type="range">`.

**Problem:** The CollageMaker gutter slider is a range input. Using `page.fill()` to set the value doesn't work.

```javascript
// BAD — fill() does NOT work on range inputs
await page.fill('#gutterSlider', '10');
// Result: value stays at 0, no input event fired

// GOOD — use evaluate to set value and dispatch input event
await page.evaluate((args) => {
    const el = document.querySelector(args.selector);
    el.value = args.value;
    el.dispatchEvent(new Event('input', { bubbles: true }));
}, { selector: '#gutterSlider', value: 10 });
```

## Gotcha 4: Sidebar Sections Collapsed by Default

The CollageMaker right sidebar sections (Title, Background, Overlay, Crop, Export) are all collapsed by default (`expandedSections: { crop: false, background: false, overlay: false, title: false, export: false }`). Only the left sidebar "Image Library" section is expanded by default.

**Impact:** Elements inside collapsed sections are not visible and cannot be interacted with. Tests must expand sections first.

```javascript
// Expand a right sidebar section by label
async function expandRightSection(page, sectionLabel) {
    const header = page.locator('.sidebar-right .sidebar-section-header')
        .filter({ hasText: sectionLabel });
    const isExpanded = await header.getAttribute('aria-expanded');
    if (isExpanded !== 'true') {
        await header.click();
        await page.waitForTimeout(100);
    }
}

// Usage
await expandRightSection(page, 'Title');
await page.fill('#titleInput', 'Hello World');
```

**Note:** The left sidebar "Layout" section is auto-expanded when images are loaded (`autoExpandLayoutOnImages`). But tests should still explicitly expand it for reliability.

## Gotcha 5: Settings Persistence Across Tests

The CollageMaker app persists settings (layout style, background, title style, etc.) via `localStorage`. When tests navigate to the app, these settings are restored.

**Impact:** Tests that assume default values (e.g., "layout starts as 'hero'") may fail if a previous test saved a different value.

```javascript
// BAD — assumes default layout
expect(await page.locator('#layoutStyleSelect').inputValue()).toBe('hero');

// GOOD — read current state, then test relative change
const originalStyle = await page.locator('#layoutStyleSelect').inputValue();
const targetStyle = originalStyle === 'uniform' ? 'hero' : 'uniform';
await page.selectOption('#layoutStyleSelect', targetStyle);
expect(await page.locator('#layoutStyleSelect').inputValue()).toBe(targetStyle);
```

## Summary Table

| Playwright Method | Expected Event | Actually Fires | Workaround |
|---|---|---|---|
| `el.focus()` | `focus` | No | `dispatchEvent(new Event('focus'))` |
| `locator.selectText()` | `select` | No | `setSelectionRange()` + `dispatchEvent` |
| `keyboard.press('Control+a')` | `select` | No (fires keydown/keyup) | `setSelectionRange()` + `dispatchEvent` |
| `page.fill()` on range | `input` | No (doesn't work) | `evaluate()` to set value + dispatch |
| `page.selectOption()` | `focus` | No | `locator.focus()` first, then `selectOption` |

## Related

- `playwright-canvas-e2e.md` — General Playwright patterns for canvas apps
- `testing-e2e.md` (skill reference) — E2E testing patterns
