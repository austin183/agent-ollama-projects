# Synopsis
Using the web app on a mobile touch screen feels a little off.  We want to try to modify the touch screen inputs on the mobile UI without sacrificing the desktop version.

# Canvas Changes

## Pinch to Zoom feels slow and will swap unexpectedly
**Reported:** When I try to pinch to zoom, the zoom in and out feels very slow.  If one of my fingers intersects with another panel during the pinch to zoom in gesture, the panels will swap.  This seems to happen intermittently

**Severity:** High

**Root Causes:**
- **Slow zoom:** `MultiTouchHandler.js` line 194 uses `Math.pow(scaleRatio, 0.15)` which converts a 1.5x pinch into only ~1.06x per step — feels sluggish compared to native mobile apps.
- **Unexpected swapping:** TouchEvents are bound to the canvas element only with no `setPointerCapture` equivalent. If a finger's touch point intersects another panel during the gesture, stray pointer events can slip through the `state._multiTouchGestureActive` guard in `PanelSwap.js` line 364, triggering an unintended swap.

**Proposed Solutions:**
1. Increase zoom sensitivity — change the exponent from `0.15` to `0.3` or switch to a linear delta-based scaling approach.
2. Set `state._multiTouchGestureActive = true` synchronously at the very beginning of the gesture start path, before any rendering or hit-testing executes.
3. Migrate multi-touch handling from TouchEvents to PointerEvents with `setPointerCapture` (shared fix with Issue 2 below).

**Affected Files:**
- `MyESModules/Interaction/MultiTouchHandler.js` — zoom math (line 194), gesture state flagging (line 151)
- `MyESModules/Interaction/PanelSwap.js` — multi-touch guard (line 364)

**Testability:**
- Unit tests can verify `state._multiTouchGestureActive` is set on gesture start and that PanelSwap skips when flag is true.
- Chrome DevTools device emulation can approximate pinch gestures but cannot accurately reproduce simultaneous two-finger delta timing.
- Zoom "feel" requires real-device validation.

---

## Two fingers to pan stops panning when leaving the panel
**Reported:** When I try to use to fingers to pan the image, it sometimes will stop panning when I leave the panel, and sometimes it will swap with a neighboring panel when I my pan gesture intersects with it.

**Severity:** High

**Root Cause:** TouchEvents are bound to the canvas element only. There is no `setPointerCapture` equivalent for TouchEvents. When one finger's touch point leaves the canvas element or moves over a different DOM element, `touchmove` stops firing on the canvas and the gesture drops. This also clears the `_multiTouchGestureActive` guard, allowing PanelSwap to fire.

**Proposed Solutions:**
1. **Primary fix — migrate to PointerEvents:** Use PointerEvents with `setPointerCapture(e.pointerId)` for each captured pointer so events continue firing even when fingers leave the canvas. The PointerEvent path already exists in `MultiTouchHandler.js` lines 265-352 for non-touch pointers — extend it to handle `pointerType === 'touch'` instead of delegating to the TouchEvent path.
2. **Fallback — bind to document:** As an interim fix, bind `touchmove` and `touchend` to `document` instead of just the canvas element and track `e.changedTouches`.

**Affected Files:**
- `MyESModules/Interaction/MultiTouchHandler.js` — TouchEvent handlers (lines 220-259), attach/detach (lines 404-470)

**Testability:**
- Unit tests can verify `setPointerCapture` is called for each pointer ID.
- Playwright can simulate pointer events but cannot reliably reproduce the finger-leaving-canvas edge case with TouchEvents.
- Real-device validation required for gesture fluidity.

---

## Dragging the title with one finger will sometimes get dropped mid-drag
**Reported:** Occassionally, when I try to move the title by tapping and dragging it, it will drop itself before I stop my tap and drag gesture.

**Severity:** High

**Root Causes:**
- The canvas has `touch-action: pan-y` (Style.css line 345) which allows browser default gestures (pull-to-refresh, back-swipe on iOS Safari) to fire and potentially interrupt the drag by triggering `pointercancel`.
- Mobile browser gesture interference can cause `pointercancel` events that clear `state.titleInteractionMode` without the user lifting their finger.

**Proposed Solutions:**
1. Change `touch-action: pan-y` to `touch-action: none` on `#previewCanvas` to prevent browser gestures from stealing pointer events during title drags.
2. Ensure `TitleInteraction.js` handles `pointercancel` explicitly — it already listens for `pointercancel` (line 55) and maps it to `_onPointerUp`, but verify the global cleanup handler also covers `pointercancel`.

**Affected Files:**
- `Style.css` line 345 — `touch-action` on `#previewCanvas`
- `MyESModules/Interaction/TitleInteraction.js` — `pointercancel` handling (line 55), global cleanup (line 429)

**Testability:**
- Chrome DevTools can verify `touch-action: none` is applied via computed styles.
- Unit tests can verify `pointercancel` clears interaction state.
- Browser gesture interference (Safari pull-to-refresh, iOS back-swipe) requires real-device validation.

---

## Resizing title width handles are hard to click on
**Reported:** It is not clear that tapping and dragging on the sides of the title outline will expand and contract the title width.

**Severity:** Medium

**Root Cause:** The edge threshold for touch is already generous at 16px (`EDGE_THRESHOLD_COARSE` in `TitleInteraction.js` line 32), so the hit area is adequate. The real problem is discoverability — on touch devices there is no hover state to show cursor changes (`ew-resize`), and no visible resize handles are drawn on the canvas. Users have no visual indication that the title edges are interactive.

**Proposed Solutions:**
1. Draw explicit resize handle indicators on the canvas when in title interaction mode and `pointerType === 'touch'` — render visible circles or bars at the left and right edges of the title bounding box, sized to at least 24px minimum (accounting for DPR scaling).
2. When a touch point enters the edge threshold zone, render a subtle highlight or outline change to indicate the resize state is active.

**Affected Files:**
- `MyESModules/Rendering/TitleRenderer.js` — add handle rendering for touch mode
- `MyESModules/Interaction/TitleInteraction.js` — edge threshold logic (line 199), hover target tracking (line 400)

**Testability:**
- Unit tests can verify handle rendering paths are exercised when `pointerType === 'touch'`.
- Chrome DevTools device emulation can verify visual appearance of handles.
- Touch target sizing can be validated via CSS pixel measurements in Playwright.

---

# Bottom Sheet Changes

## No Font Background Options under Edit Bottomsheet
**Reported:** When I go under Edit, I have the title, font, and color options, but not the background color, the checkbox, or the opacity sliders.  Can we add those back?

**Severity:** Medium (feature parity gap)

**Root Cause:** The mobile bottom sheet Edit tab template (`index.html` lines 397-431) is missing several controls that exist in the desktop sidebar Title section (`index.html` lines 472-549). This is a template omission from the mobile bottom sheet implementation.

**Missing controls (present in desktop, absent in mobile bottom sheet):**
| Control | Desktop location | State binding |
|---------|-----------------|---------------|
| Font Opacity slider | Line 507 | `titleStyle.fontOpacity` |
| Background Color picker | Line 511 | `titleStyle.backgroundColor` |
| Background Opacity slider | Line 517 | `titleStyle.bgOpacity` |
| "Show Background" checkbox | Line 522 | `titleStyle.showBackground` |
| Width slider | Line 541 | `titleStyle.titleBoxWidth` |
| Reset Position button | Line 545 | calls `resetTitlePosition` |
| Bold/Italic/Underline bar | Lines 478-487 | calls `toggleTitleBold/Italic/Underline` |

**Proposed Solution:** Copy the missing control elements from the desktop sidebar Title section into the mobile bottom sheet Edit tab template, placing them after the Alignment controls (line 431) and before the closing `</div>` of the Edit panel. Ensure:
- All IDs are prefixed with `bs` (e.g., `bsTitleBgColorPicker`, `bsTitleFontOpacitySlider`) to avoid ID collisions with the desktop sidebar.
- All Vue bindings (`v-model`, `@input`, `@focus`, `@blur`) are correctly wired to the same state model.
- Undo snapshot/commit handlers (`snapshotTitleStyle`, `commitTitleStyle`) are applied consistently.

**Affected Files:**
- `index.html` lines 397-431 — bottom sheet Edit tab Title section

**Testability:**
- Fully testable via Playwright — verify all controls render in the bottom sheet Edit tab and that state changes propagate correctly.
- Unit tests can verify Vue method bindings for each new control.
- No real-device requirement beyond verifying touch target sizing (44x44px minimum).

---

# Cross-Cutting Concerns

## Shared fix: Migrate multi-touch from TouchEvents to PointerEvents
Issues 1 and 2 share a common root cause: TouchEvents lack pointer capture and are element-scoped. Migrating the multi-touch gesture handler to use PointerEvents with `setPointerCapture` addresses both issues simultaneously. The PointerEvent infrastructure already exists in `MultiTouchHandler.js` — the change is to stop delegating `pointerType === 'touch'` to the TouchEvent path and instead handle touch pointers through the same PointerEvent flow with capture.

## CSS touch-action change
Changing `touch-action: pan-y` to `touch-action: none` on `#previewCanvas` (Style.css line 345) addresses Issue 3 but also benefits Issues 1 and 2 by preventing browser gestures from interfering with any canvas interaction. This is a low-risk change since the canvas occupies the full viewport area on mobile and vertical scroll passthrough is not needed during active interactions.

# Prioritization

| Priority | Issue | Rationale |
|----------|-------|-----------|
| **P1 - Critical** | Two-finger pan stops + Title drag drops | Core workflow breakage, shared fix (PointerEvents + touch-action) |
| **P2 - High** | Pinch zoom slow + swap | High user frustration, shares infrastructure with P1 fix |
| **P3 - Medium** | Missing bottom sheet controls | Feature parity gap, straightforward template work, fully testable |
| **P4 - Lower** | Title resize handle discoverability | Quality-of-life, no blocking impact |
