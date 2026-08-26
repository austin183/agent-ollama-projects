# Export Registry Signature Alignment and Barrel Export Verification

**Date:** 2026-07-05
**Session:** 48 (Phase 1: Pre-commit review fixes)

## Summary

Two production bugs discovered during pre-commit review: a PNG exporter signature mismatch that produced 300x150 exports instead of 1920x1080, and a barrel export that silently exported `undefined`.

---

## Export Registry Signature Alignment

When using a registry pattern where a dispatcher calls `exporter(assembler, state, quality)`, **all registered exporters must accept the same parameter order**. A single misaligned signature silently corrupts the output.

### The Bug

`ExportManager.export()` dispatches to format exporters as:
```javascript
return exporter(assembler, state, quality);  // quality = 0.92
```

JPEG exporter had the correct signature:
```javascript
export function exportToJpeg(assembler, state, quality = 0.92, exportSize = { width: 1920, height: 1080 })
```

PNG exporter had a misaligned signature:
```javascript
export function exportToPng(assembler, state, exportSize = { width: 1920, height: 1080 })
//                                                   ^^^^^^^^^^ receives 0.92 instead!
```

Result: `exportSize.width` was `undefined`, canvas defaulted to 300x150, PNG exports were tiny and unusable.

### The Fix

Align PNG signature to accept quality as 3rd parameter (unused, but required for positional correctness):
```javascript
export function exportToPng(assembler, state, _quality = 1.0, exportSize = { width: 1920, height: 1080 })
```

### Rule for Registry Patterns

**Every strategy in a registry must accept the same parameter shape as the dispatcher calls it.** If the dispatcher passes `(a, b, c)`, every strategy must have at least 3 parameters in the same order. Use underscore-prefixed names (`_quality`) for parameters a strategy doesn't use but must accept for alignment.

### Testing Strategy

Test the **integration path** (dispatcher → strategy), not just the strategy in isolation:
```javascript
// Test that ExportManager.export() with 'png' produces correct canvas dimensions
await ExportManager.export(mockAssembler, mockState, 'png', 0.92);
// Verify canvas was created with 1920x1080, not 300x150
```

---

## Barrel Export Verification

Barrel re-exports from a module that doesn't export the requested name will silently export `undefined` at runtime (no compile-time error in browsers).

### The Bug

```javascript
// MyESModules/index.js — WRONG
export { exportToJpeg } from './Export/ExportManager.js';
// ExportManager.js exports: { ExportManager: { registerFormat(), export() } }
// It does NOT export exportToJpeg — so barrel exports undefined
```

This was caught because a test file (`SaliencyDebugOverlayTest.html`) imported from the barrel and the module failed to load with:
```
SyntaxError: The requested module does not provide an export named 'exportToJpeg'
```

### The Fix

Re-export from the actual source module:
```javascript
// MyESModules/index.js — CORRECT
export { exportToJpeg } from './Export/formats/jpegExporter.js';
export { exportToPng } from './Export/formats/pngExporter.js';
```

### Rule for Barrel Exports

**Always verify the source module actually exports the name you're re-exporting.** A quick way to verify: check the source file for `export function exportToJpeg` or `export const exportToJpeg`. If the source exports a namespace object (like `ExportManager`), you can't re-export its methods via `export { method } from './source.js'`.

### Testing Strategy

Add a barrel export test that imports from the barrel and verifies the type:
```javascript
it('barrel exports exportToJpeg as a function', async () => {
    const barrel = await import('../MyESModules/index.js');
    expect(typeof barrel.exportToJpeg).to.equal('function');
});
```

---

## Canvas Dimension Interception for Exporter Testing

When testing canvas-based exporters, you can verify canvas dimensions without needing a full rendering pipeline by intercepting `document.createElement` and capturing width/height via `Object.defineProperty` on individual canvas elements:

```javascript
let originalCreateElement = document.createElement.bind(document);
let createdWidth, createdHeight;

document.createElement = function(tag) {
    const el = originalCreateElement(tag);
    if (tag === 'canvas') {
        Object.defineProperty(el, 'width', {
            get: () => createdWidth,
            set: (v) => { createdWidth = v; },
            configurable: true
        });
        Object.defineProperty(el, 'height', {
            get: () => createdHeight,
            set: (v) => { createdHeight = v; },
            configurable: true
        });
        el.getContext = () => null; // Fail early — we only need dimensions
    }
    return el;
};

try { await exportToPng(null, state, 0.92); } catch (e) { /* expected */ }
expect(createdWidth).to.equal(1920);
expect(createdHeight).to.equal(1080);

// Always restore
document.createElement = originalCreateElement;
```

### Key Points

- **Scope to `'canvas'` tag only** — other elements should pass through to the original
- **Restore in `afterEach`** — leaking the mock breaks subsequent tests
- **Bind the original** — `document.createElement.bind(document)` preserves the `this` context
- **Fail fast with `getContext = () => null`** — the test only needs dimensions, not rendering

---

## File Reference

- `MyESModules/Export/formats/pngExporter.js` — Signature fix
- `MyESModules/Export/ExportManager.js` — Dispatcher (unchanged)
- `MyESModules/index.js` — Barrel export fix
- `MyComponents/ExportManagerTest.html` — Tests (Section 6.1, 6.2)
- `MyComponents/SaliencyDebugOverlayTest.html` — Import path fix
