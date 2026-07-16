# Playwright E2E Patterns for Canvas Apps

**Date:** 2026-07-02
**Session:** 6 (P0 test implementation)

## Summary

The project uses Playwright for end-to-end browser tests. Canvas-heavy apps require special patterns since canvas content isn't accessible via DOM queries.

## Pattern

### Test File Structure

```javascript
// test/e2e/workflow-tests.spec.cjs
const { test, expect } = require('@playwright/test');

test('messy workflow', async ({ page }) => {
    await page.goto('http://localhost:8000/CollageMaker/index.html');

    // Upload images via file input
    const fileInput = page.locator('#fileInput');
    await fileInput.setInputFiles(['test/images/img1.jpg', 'test/images/img2.jpg']);

    // Wait for images to appear in library
    await page.waitForSelector('.image-item', { state: 'visible' });

    // Verify canvas has content
    const canvas = page.locator('#previewCanvas');
    await expect(canvas).toBeVisible();
});
```

### Key Patterns

1. **File upload via `setInputFiles`** — Simulates file selection through the file input element
2. **Wait for selectors** — Use `waitForSelector()` with `state: 'visible'` instead of `waitForTimeout()`
3. **Canvas verification** — Canvas content can't be queried via DOM. Use `page.screenshot()` comparison or pixel sampling for visual verification.
4. **Keyboard shortcuts** — Use `page.keyboard.press()` with platform-appropriate modifiers

## Gotchas

1. **`waitForTimeout()` is fragile** — Hardcoded delays fail in CI where timing varies. Always prefer assertion-based waits.
2. **Canvas content is opaque** — Playwright can't inspect canvas pixels directly. Use screenshot comparison or verify indirect signals (e.g., image count in sidebar).
3. **File upload simulation** — Playwright's `setInputFiles()` works for file inputs but not for drag-and-drop. Drag-and-drop requires simulating drag events.
4. **Platform modifiers** — Use `process.platform === 'darwin'` to choose between `Meta` (Mac) and `Control` (Linux/Windows) for keyboard shortcuts.
5. **`getAttribute('disabled')` returns `""` not `true`** — When a button has the `disabled` attribute, `getAttribute('disabled')` returns an empty string `""`, not `true`. When absent, it returns `null`. Use `toBeNull()` (enabled) and `not.toBeNull()` (disabled) for assertions.
6. **Playwright refuses to click disabled buttons** — `page.click('#btn')` on a disabled button will timeout waiting for it to become enabled. Use `getAttribute('disabled')` to check state instead of trying to click.

## Reusable Helper Pattern

Extract shared wait logic into named helper functions at the top of the test file:

```javascript
// Wait for images to actually load (checks sidebar count)
async function waitForImagesLoaded(page, expectedCount) {
    await page.waitForFunction(
        (count) => {
            const header = document.querySelector('#sidebar-left h3');
            if (!header) return false;
            return header.textContent.includes(count.toString());
        },
        expectedCount,
        { timeout: 10000 }
    );
}

// Wait for canvas to be visible
async function waitForCanvasVisible(page) {
    await page.waitForSelector('#previewCanvas', { state: 'visible', timeout: 5000 });
}

// Change layout and wait for re-render
async function changeLayout(page, style) {
    await page.locator('#layoutStyleSelect').selectOption(style);
    await waitForCanvasVisible(page);
}
```

## Canvas Panel Selection

To click on a specific area of the canvas (e.g., to select a panel):

```javascript
const canvasBounds = await page.locator('#previewCanvas').boundingBox();
await page.click('#previewCanvas', {
    position: { x: canvasBounds.width / 2, y: canvasBounds.height / 2 }
});
```

After clicking, verify the interaction worked by checking for UI changes (e.g., crop preview canvas appearing):

```javascript
const cropSectionVisible = await page.evaluate(() => {
    const cropCanvas = document.getElementById('cropPreviewCanvas');
    return cropCanvas && cropCanvas.offsetParent !== null;
});
```

## Theme Toggle Verification

Instead of `waitForTimeout()` after a theme toggle, wait for the theme icon to change:

```javascript
await page.click('#themeToggle');
await page.waitForFunction(() => {
    const icon = document.getElementById('theme-icon');
    return icon && icon.textContent !== 'bedtime';
}, { timeout: 3000 });
```

## Resolved Test Gaps

All P0 follow-up gaps have been addressed (commit `46da243`):

| Gap | Resolution |
|-----|-----------|
| Crop editing E2E flow | Tests 12.11.1-12.11.2 |
| Keyboard shortcut tests | Tests 12.9.1-12.9.3 |
| Undo/redo button state | Tests 12.10.1-12.10.4 |
| `waitForTimeout()` usage | All replaced with assertion-based waits |
| Drag-and-drop visual feedback | Still open (P1) |

## Playwright Config

```javascript
// playwright.config.cjs
module.exports = {
    testDir: './test/e2e',
    timeout: 30000,
    use: {
        trace: 'on-first-retry'
    },
    workers: 1,
    fullyParallel: false
};
```

- `workers: 1` and `fullyParallel: false` prevent race conditions with temp file creation
- `timeout: 30000` is generous for image-heavy workflows
- `trace: 'on-first-retry'` balances debuggability with CI speed
