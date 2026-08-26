# Testing Browser API Utilities with Real Objects

## Context

When extracting a shared utility that wraps browser APIs (FileReader, Image, Canvas), you need to decide between mocking the APIs or using real browser objects. Phase 4's `loadImageFromFile` utility (FileReader → Image) is a good example.

## Pattern: Real Objects Over Mocks

For browser-based Mocha/Chai tests, prefer **real browser objects** over mocked APIs when the objects are easy to construct:

```javascript
// Create a minimal 1x1 red PNG as a File object
function createTestImageFile() {
    const pngBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
    const binary = atob(pngBase64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
    }
    return new File([bytes], 'test.png', { type: 'image/png' });
}
```

**Advantages over mocking:**
1. **Tests actual behavior** — FileReader.readAsDataURL() and Image.onload fire correctly
2. **No mock maintenance** — no need to intercept FileReader constructor, bind callbacks, or restore
3. **Catches real edge cases** — invalid MIME types, corrupted data, actual decode failures

**When to mock instead:**
- When the API has side effects you can't control (network fetches, localStorage quota)
- When you need to test error paths that are hard to trigger with real objects (FileReader.onerror)

## Guard Against Null Inputs

Browser API utilities that accept user input MUST guard against null/undefined:

```javascript
// BAD — throws TypeError: Cannot read properties of null
export function loadImageFromFile(file) {
    const reader = new FileReader();
    reader.readAsDataURL(file); // Crashes if file is null
}

// GOOD — returns null gracefully
export function loadImageFromFile(file) {
    if (!file) {
        return Promise.resolve(null);
    }
    // ... rest of implementation
}
```

**Why it matters:** The utility may be called from multiple code paths. If one path passes null (e.g., event.target.files[0] when no file selected), the utility should handle it gracefully rather than throwing.

## Optional Chaining for Guard Simplification

When simplifying existence guards on objects with known interfaces, use optional chaining instead of bare calls:

```javascript
// BEFORE — defensive ternary
() => base.getCropManager ? base.getCropManager() : null

// AFTER — optional chaining (safe with null base)
() => base?.getCropManager?.() ?? null
```

**Why not just `base.getCropManager()`?** If a test double or non-CollageBase object is passed, calling `.getCropManager()` on a non-function throws. Optional chaining makes the guard resilient without the verbosity of the ternary.

## Testing Strategy for Deduplication

When extracting a shared utility from N duplicated implementations:

1. **Test the utility in isolation** — happy path, error paths, null inputs
2. **Test the barrel export** — verify the re-export resolves to a function
3. **Test the consumers still work** — the existing test suite should catch regressions
4. **Verify line count reduction** — document how many lines were eliminated

## Related

- `MyComponents/Phase4CodeQualityTest.html` — Real File objects, null guards, optional chaining tests
- `MyESModules/Utils/loadImageFromFile.js` — Production utility with null guard
- `MyESModules/App/createCollageMethods.js` — Optional chaining guard pattern
