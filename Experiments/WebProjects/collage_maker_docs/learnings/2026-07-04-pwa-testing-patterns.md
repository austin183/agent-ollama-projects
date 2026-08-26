# PWA Testing Patterns (2026-07-04)

**Context:** Implementing Section 3.6 PWA Capabilities tests for CollageMaker (deferred feature).

## Key Learnings

### 1. Falsy vs. Missing Field Validation

When validating manifest fields, `!manifest.name` catches both `undefined` and `''` (empty string), since empty string is falsy in JavaScript. To distinguish between "missing" and "empty", use explicit checks:

```javascript
// WRONG — catches both undefined and empty string
if (!manifest.name) {
    errors.push('Missing required field: name');
}

// CORRECT — distinguishes missing from empty
if (manifest.name === undefined || manifest.name === null) {
    errors.push('Missing required field: name');
} else if (typeof manifest.name === 'string' && !manifest.name.trim()) {
    errors.push('name must be non-empty');
}
```

Same pattern applies to arrays: `!manifest.icons` catches `undefined`, `null`, and `false` but NOT `[]` (empty array is truthy). However, `manifest.icons.length === 0` in the same condition catches empty arrays. Structure the checks to handle each case separately.

### 2. Playwright `networkidle` vs `domcontentloaded` for Mocha Tests

The test runner (`scripts/run-tests.js`) originally used `waitUntil: 'networkidle'` to wait for test pages to load. This caused timeouts when tests included `fetch()` calls for non-existent resources (e.g., `fetch('../manifest.json')` for deferred PWA feature).

**Fix:** Changed to `waitUntil: 'domcontentloaded'` + `waitForSelector('#mocha', { state: 'attached' })`. This approach:
- Loads the DOM quickly without waiting for all network requests
- Waits for Mocha to be ready (CDN scripts loaded, `#mocha` element created)
- Mocha tests run after `window.load`, so async fetch calls in tests don't block page navigation

**Risk:** If any existing tests rely on `networkidle` to ensure Vue 3 has fully mounted or all images are loaded before assertions, they could become flaky. However, all 878 tests pass with the new approach, suggesting no tests depend on `networkidle` for correctness.

### 3. Service Worker Cache Strategy: Pure Functions First

PWA cache utilities (`PWACacheUtils.js`) are designed as pure functions that can be:
- Unit tested without a service worker context
- Imported by the actual `service-worker.js` for cache routing decisions
- Validated independently of browser APIs

Key pure functions:
- `isAppShellURL(url)` — exact match against APP_SHELL_URLS list
- `isImageURL(url)` — extension-based regex, rejects data:/blob:/file: URLs
- `routeRequest(url)` — returns 'shell', 'images', or 'passthrough'
- `computeCacheKey(url, cacheName)` — versioned cache key for invalidation
- `getCacheName(type)` — maps route type to cache name
- `shouldCacheResponse(url, response)` — validates response before caching
- `validateManifest(manifest)` — checks required/recommended fields

### 4. Cache API: No Built-in Eviction

The Cache API has no built-in LRU eviction or size limits. The `MAX_IMAGE_CACHE_SIZE` constant in `CACHE_CONFIG` documents the intended limit, but the actual eviction logic must be implemented in the service worker's `activate` event. This is deferred for now.

### 5. Opaque Response Handling

In service workers, cross-origin requests without CORS headers return `response.type === 'opaque'`. The Cache API cannot cache opaque responses via `caches.put()` — it throws `TypeError`. The `shouldCacheResponse` function must check `response.type !== 'opaque'` before attempting to cache.

### 6. Deferred Feature Test Patterns

For deferred features (PWA, ML saliency), tests serve as requirements documentation:
- Unit tests for pure functions pass immediately (no browser API dependencies)
- E2E tests document expected behavior but will fail until the feature is implemented
- Deferred tests include clear comments explaining what's needed
- Test numbering follows the priority plan sections for traceability

## Files Affected

- `MyESModules/Utils/PWACacheUtils.js` — Pure PWA cache utilities
- `MyComponents/PWACacheUtilsTest.html` — 88 unit tests
- `MyComponents/PWAManifestTest.html` — 33 manifest validation tests
- `test/e2e/pwa-capabilities.spec.js` — 32 E2E tests (deferred)
- `scripts/run-tests.js` — Fixed `networkidle` timeout issue
