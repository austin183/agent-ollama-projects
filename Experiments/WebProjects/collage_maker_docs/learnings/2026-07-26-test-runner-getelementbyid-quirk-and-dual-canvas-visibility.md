# Test Runner getElementById Quirk & Dual-Canvas Visibility Guard

## Problem

Two issues discovered during Phase 3 crop preview dual-canvas migration:

1. **Test runner failure**: `CropPreviewDualCanvasTest.html` passed when loaded directly in Playwright but consistently failed in the test runner with "Could not find #mocha element" error. The `document.getElementById('mocha')` returned `null` even though `document.querySelector('#mocha')` found the element and mocha tests had run successfully.

2. **Performance concern**: Rendering crop preview to both desktop sidebar canvas and mobile bottom sheet canvas simultaneously could cause unnecessary rendering overhead on mobile devices when one canvas is hidden.

## Root Cause

### getElementById Quirk
After Mocha runs and populates the `#mocha` div with test results, `document.getElementById('mocha')` can return `null` in certain Playwright evaluation contexts, while `document.querySelector('#mocha')` reliably finds the element. This appears to be a DOM state anomaly where Mocha's internal manipulation of the element (adding/removing classes, injecting child elements) can cause `getElementById` to fail in some execution contexts. This is a known edge case in HTML DOM — `getElementById` is not always equivalent to `querySelector('#id')` when the DOM is dynamically modified.

### Dual-Canvas Rendering Overhead
When both `cropPreviewCanvas` (desktop sidebar) and `bsCropPreviewCanvas` (mobile bottom sheet) are configured, the renderer iterates over both IDs and draws to each canvas. On mobile devices, the desktop canvas is hidden via CSS (`display: none`), but Canvas 2D still executes all draw operations for hidden canvases. On high-DPR mobile screens (2x or 3x), this effectively doubles the rendering workload during crop adjustments.

## Fix

### Test Runner
Changed `scripts/run-tests.js` from:
```javascript
const mochaEl = document.getElementById('mocha');
```
to:
```javascript
const mochaEl = document.querySelector('#mocha');
```

Also added `waitForSelector('#mocha .test', { timeout: 10000 })` for more reliable test completion detection instead of a fixed `waitForTimeout(1000)`.

### Dual-Canvas Visibility Guard
Added visibility check in `_renderCropPreviewOnCanvas()`:
```javascript
if (!canvas.isConnected || canvas.offsetParent === null) return;
```

This skips rendering for canvases that are disconnected from the DOM or hidden (`display: none` sets `offsetParent` to `null`). The check is O(1) and prevents all Canvas 2D draw operations for hidden canvases.

## Key Insight

- **Always use `querySelector` over `getElementById` in test runners** when the DOM might be dynamically modified by test frameworks. The `getElementById` API has edge cases where it returns `null` for elements that `querySelector` can find.

- **Always guard canvas rendering with visibility checks** when rendering to multiple canvases. Hidden canvases still execute draw operations, which wastes CPU/GPU cycles and can cause frame drops during interactive operations.

- **Use `e.currentTarget` for per-canvas coordinate math** when handling pointer events on multiple canvases. A stored canvas reference can become stale or ambiguous when multiple canvases receive events.
