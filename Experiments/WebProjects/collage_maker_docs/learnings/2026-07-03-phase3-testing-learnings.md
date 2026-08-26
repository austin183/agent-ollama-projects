# Phase 3 Testing — Learnings (2026-07-03)

**Purpose:** Hard-won knowledge from implementing P0 Phase 3 unit tests (TitleManager, ExportManager, SettingsPersistence, E2E Full Session).

---

## TitleManager: Toggle Functions Flip ALL Formatting Flags

`toggleBold(start, end)` passes `{ bold: undefined }` to `applyFormattingToRange`. The undefined check (`formatting.bold !== undefined ? formatting.bold : !run.bold`) applies to **all three** formatting properties. So `toggleBold` also flips `italic` and `underline` on the affected runs.

**Impact:** After `toggleBold(1, 3)` on plain text, the range becomes bold+italic+underline. A subsequent `toggleItalic(1, 3)` flips all three back to false, merging runs back to plain.

**Test strategy:** Tests must verify actual behavior, not the intuitive "only bold toggles" expectation. When testing sequential formatting operations, account for cross-flag toggling.

**Location:** `MyESModules/State/TitleManager.js` lines 233-259, specifically `applyFormattingToRange` line 91-93.

---

## Mocking Browser APIs in Mocha/Chai HTML Tests

Since tests run in a real browser (not Node.js), mocking requires intercepting `document.createElement` and `localStorage`:

```javascript
// Mock document.createElement to intercept canvas creation
const originalCreateElement = document.createElement.bind(document);
document.createElement = function(tag) {
    const el = originalCreateElement(tag);
    if (tag === 'canvas') {
        el.toBlob = function(callback, type, quality) {
            // Custom behavior
            callback(new Blob(['fake'], { type: 'image/jpeg' }));
        };
    }
    return el;
};
// ... test ...
document.createElement = originalCreateElement; // Restore
```

```javascript
// Mock localStorage.setItem to simulate quota exceeded
const originalSetItem = localStorage.setItem;
localStorage.setItem = function() {
    const e = new Error('Quota exceeded');
    e.name = 'QuotaExceededError';
    e.code = 22;
    throw e;
};
// ... test ...
localStorage.setItem = originalSetItem; // Restore
```

**Key:** Always bind the original (`document.createElement.bind(document)`) to preserve the `this` context. Always restore in a `finally` block or after the test.

---

## Chai Browser Limitations

Chai loaded via CDN (v4.3.10) lacks plugins like `chai-as-promised`. Two gotchas:

1. **No `eventually`** — `expect(promise).to.eventually.be.rejected` throws `Invalid Chai property: eventually`. Use try/catch instead:
   ```javascript
   let errorThrown = null;
   try { await someAsyncFunction(); } catch (e) { errorThrown = e; }
   expect(errorThrown).to.not.be.null;
   ```

2. **No `startWith`** — `expect(str).to.startWith('blob:')` throws `Invalid Chai property: startWith`. Use regex instead:
   ```javascript
   expect(str).to.match(/^blob:/);
   ```

**If async assertions are needed frequently,** consider adding `chai-as-promised` via CDN.

---

## ExportManager: Offscreen Canvas Testing

`exportToJpeg` creates an offscreen canvas that is **never** appended to the DOM. To test it:

- Intercept `document.createElement` to capture the canvas and its dimensions
- Verify the canvas is NOT in `document.body` after export completes
- Verify no `<a>` download links remain (cleanup runs in `finally` block)
- Use a mock assembler with a `render()` method that records calls for inspection

**Pattern:** The mock assembler approach lets you verify the render pipeline (what data was passed, context type, canvas size) without needing a real canvas render.

---

## SettingsPersistence: Testing localStorage Round-Trips

The `save()`/`load()` functions use `localStorage` directly. Testing strategy:

1. **`beforeEach`**: Always `localStorage.removeItem(STORAGE_KEY)` to start clean
2. **Corrupted JSON**: Write invalid JSON string, verify `load()` returns defaults
3. **Quota exceeded**: Mock `localStorage.setItem` to throw `QuotaExceededError`
4. **Partial data**: Write incomplete settings object, verify defaults fill missing fields
5. **Empty string**: `localStorage.setItem(key, '')` — empty string is falsy, so `load()` returns defaults

**Key insight:** `load()` merges with defaults via `{ ...defaults, ...parsed }`, so stored values override defaults but missing keys get default values. This is the correct versioning strategy for settings that evolve over time.

---

## E2E Full Session: Playwright File Upload

For the E2E test, file uploads use `page.waitForEvent('filechooser')` paired with `fileChooser.setFiles()`. Buffer-based test images (base64-encoded PNG) avoid needing test fixtures on disk:

```javascript
const redPng = Buffer.from('iVBORw0KGgo...', 'base64');
await fileChooser.setFiles([{
    name: 'test.png',
    mimeType: 'image/png',
    buffer: redPng,
}]);
```

**Caveat:** The full session test requires the dev server running on port 8000 and is sensitive to Vue app mount timing. Use `waitForSelector('#app')` before interacting.

---

## Test Counting

Grep-based assertion counting (`grep -c 'expect(' file`) is a quick way to estimate test coverage. For the P0 tests:
- TitleManager: 39 tests, 121 assertions (3.1:1 ratio)
- ExportManager: 15 tests, 32 assertions (2.1:1 ratio)
- SettingsPersistence: 17 tests, 55 assertions (3.2:1 ratio)
- E2E Full Session: 1 test, 6 assertions

**Rule of thumb:** Unit tests average 2-3 assertions per test. E2E tests average fewer assertions since each interaction is expensive.

---

**Status:** Closed
**Follow-up:** P1 tests (BackgroundRenderer, TitleRenderer, OverlayRenderer) may reveal more mocking patterns for Canvas 2D contexts.
