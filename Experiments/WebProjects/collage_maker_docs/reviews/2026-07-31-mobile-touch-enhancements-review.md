# Mobile Touch Enhancements — Pre-Commit Review

**Date:** 2026-07-31
**Plan:** `_agent_docs/plans/2026-07-29-mobile-touch-enhancements.md`
**Files Reviewed:** 17 staged files (1716 net insertions)

## Files Changed

| File | Role | Change Type |
|------|------|-------------|
| `MyESModules/Interaction/MultiTouchHandler.js` | Core gesture handler | Major refactor (TouchEvent → PointerEvent-only) |
| `MyESModules/Interaction/TitleInteraction.js` | Title drag/resize handler | Extension (pointerType tracking, pointerleave) |
| `MyESModules/Rendering/TitleRenderer.js` | Title canvas rendering | Extension (touch resize handles) |
| `MyESModules/Rendering/CollageAssembler.js` | Render pipeline assembly | Extension (pointerType threading) |
| `MyESModules/App/createCollageData.js` | Vue state factory | Extension (new state property) |
| `MyESModules/App/createRenderMethods.js` | Render method factory | Extension (pointerType passthrough) |
| `Style.css` | Canvas styling | Change (touch-action) |
| `index.html` | HTML template | Extension (7 new bottom sheet controls) |
| `MyComponents/MultiTouchHandlerTest.html` | Unit tests | Major rewrite |
| `MyComponents/TitleInteractionTest.html` | Unit tests | Extension |
| `MyComponents/TitleRendererTest.html` | Unit tests | Extension |
| `MyComponents/MobileTouchGestureTest.html` | Unit tests | Update |
| `MyComponents/MobilePolishTest.html` | Unit tests | Update |
| `MyComponents/BottomSheetTitleControlsTest.html` | Unit tests | New file |
| `.opencode/skills/building-web-apps/SKILL.md` | Skill docs | Update |
| `.opencode/skills/building-web-apps/references/interaction.md` | Skill docs | Update |
| `.opencode/skills/building-web-apps/references/testing-unit.md` | Skill docs | Update |

---

## Architectural Review

### Phase 1: PointerEvents Migration

**Assessment: APPROVED with notes**

The migration from dual-path (TouchEvent + PointerEvent) to PointerEvent-only is architecturally sound. The PointerEvent API with `setPointerCapture` is the modern, unified approach that eliminates the dual-path maintenance burden.

**SRP (Single Responsibility):** Maintained. MultiTouchHandler.js still has one clear responsibility: two-finger pan and pinch-to-zoom for the selected panel. The removal of the TouchEvent path simplifies rather than complicates this.

**OCP (Open/Closed):** The new `applyZoomExponent()` function is a pure function with numeric guards (`Number.isFinite`, `ratio <= 0`). This follows the project convention of extracting pure math for testability. The function is closed for modification (exponent is a constant 0.3) and open for extension via parameter if needed.

**DIP (Dependency Inversion):** The handler continues to depend on abstractions: `cropManager` interface, `state` object, and callback functions. No new concrete dependencies introduced.

**Key observations:**
- The `activePointers` Map cleanup in the `startGesture` failure path (lines 229-237) is well-implemented. The save-before-clear pattern prevents stale pointer captures.
- The 3+ finger `e.preventDefault()` guard at line 242-244 is correct but minimal. It prevents the browser from interpreting 3+ finger gestures but doesn't release already-captured pointers. This is acceptable since 3+ finger gestures are rare during normal use.
- The `pointercancel` handler properly releases all captures and clears all state. Good.

### Phase 2: Zoom Sensitivity

**Assessment: APPROVED**

The exponent change from 0.15 to 0.3 is a configuration-level change with no architectural impact. The new `applyZoomExponent()` function is:
- A pure function with proper numeric guards
- Exported for unit testing
- Documented with JSDoc including examples

### Phase 3: Bottom Sheet Controls

**Assessment: APPROVED**

The 7 new controls follow the established patterns:
- All IDs use `bs` prefix (no collision with desktop sidebar)
- Vue bindings (`v-model`, `@click`, `@change`) match desktop equivalents
- Undo snapshot pattern (`@focus="snapshotTitleStyle"`, `@blur="commitTitleStyle"`) is consistent
- ARIA attributes (`aria-valuenow`, `aria-valuemin`, `aria-valuemax`, `aria-pressed`) are present

**Nit:** The formatting bar buttons use `@mousedown.prevent` to prevent text selection interference. This is consistent with the desktop sidebar pattern.

### Phase 4: Resize Handle Discoverability

**Assessment: APPROVED with notes**

The pointerType threading through the render pipeline follows the established data flow pattern:

```
TitleInteraction.js (captures pointerType)
  → state.titleInteractionPointerType
    → createCollageData.js (state property)
      → createRenderMethods.js (passes to assembler)
        → CollageAssembler.js (threads to TitleRenderer)
          → TitleRenderer.js (conditional rendering)
```

This is a clean, linear data flow with no circular dependencies.

**SRP:** `drawTouchResizeHandles()` is a focused pure rendering function. It draws exactly two circles and nothing more.

**The `pointerleave` handler** in TitleInteraction.js is a nice addition. It correctly guards against clearing active interaction state (`if (isInteracting) return;`) and only clears hover state.

---

## SOLID Principles Analysis

### Single Responsibility Principle

| Module | Responsibility | Verdict |
|--------|---------------|---------|
| `MultiTouchHandler.js` | Two-finger pan/zoom gestures | ✅ One clear responsibility |
| `TitleInteraction.js` | Title drag/resize interaction | ✅ One clear responsibility |
| `TitleRenderer.js` | Title canvas rendering | ✅ One clear responsibility |
| `CollageAssembler.js` | Full canvas composition | ✅ One clear responsibility |
| `createCollageData.js` | Vue state initialization | ✅ One clear responsibility |
| `createRenderMethods.js` | Render method factory | ✅ One clear responsibility |

### Open/Closed Principle

- `applyZoomExponent()` is a closed pure function. The exponent (0.3) is a constant. If a different exponent is needed in the future, it would require modification rather than extension. However, this is acceptable for a configuration constant — the function signature remains stable.
- `drawTouchResizeHandles()` accepts `activeEdge` as a parameter, making it open to different interaction states without modification.

### Liskov Substitution

Not applicable — this project uses factory functions and plain objects, not class hierarchies.

### Interface Segregation

All module interfaces remain focused:
- `MultiTouchHandler` exposes `attach()`, `detach()`, and test handlers
- `TitleInteraction` exposes `attach()`, `detach()`, and test handlers
- No module is forced to depend on methods it doesn't use

### Dependency Inversion

No regressions. All modules continue to depend on abstractions:
- Handlers depend on `cropManager`, `state`, and callback functions
- Renderers depend on canvas context and data objects
- No new concrete dependencies introduced

---

## Separation of Concerns

**Layering:** Maintained across all layers:
- **Presentation:** `index.html` (Vue template), `Style.css`
- **Interaction:** `MultiTouchHandler.js`, `TitleInteraction.js`
- **Rendering:** `TitleRenderer.js`, `CollageAssembler.js`
- **State:** `createCollageData.js`
- **Assembly:** `createRenderMethods.js`

**No layer violations detected.** The pointerType threading flows correctly from interaction → state → assembly → rendering without any layer reaching into another's domain.

**Cohesion:** High. Each module handles exactly its domain.

**Coupling:** Low. The only coupling is through the shared `state` object, which is the established pattern.

---

## Code Quality

### Function Size and Focus

- `applyZoomExponent()`: 3 lines of logic, pure function ✅
- `drawTouchResizeHandles()`: ~20 lines, single rendering concern ✅
- `_onPointerLeave()`: ~12 lines, single cleanup concern ✅
- `_onPointerDown()` in MultiTouchHandler: ~33 lines, handles pointer capture + gesture start + 3+ finger guard. This is at the upper bound but each section has a clear purpose. Acceptable.

### Naming

- `applyZoomExponent` — clear and descriptive ✅
- `drawTouchResizeHandles` — clear and descriptive ✅
- `lastPointerType` — clear intent ✅
- `titleInteractionPointerType` — follows existing naming pattern (`titleInteractionMode`, `titleHoverTarget`) ✅

### Error Handling

- `setPointerCapture` / `releasePointerCapture` wrapped in try/catch ✅
- `applyZoomExponent` guards against NaN/Infinity/zero ✅
- `pointercancel` handler releases all captures and clears all state ✅
- `pointerleave` handler guards against clearing active interaction ✅

### State Management

- `lastPointerType` is properly initialized, set, and cleared in `_clearInteractionState()` ✅
- `state.titleInteractionPointerType` follows the same lifecycle as `state.titleInteractionMode` ✅

---

## Test Coverage

### New Tests

| Test File | Tests | Coverage |
|-----------|-------|----------|
| `BottomSheetTitleControlsTest.html` | 40 tests | All 7 new controls, ID prefixing, Vue method availability |
| `MultiTouchHandlerTest.html` | Rewritten | PointerEvent-only path, zoom exponent, pointer capture lifecycle |
| `TitleInteractionTest.html` | Extended | pointerType tracking, pointerleave handler |
| `TitleRendererTest.html` | Extended | drawTouchResizeHandles, conditional rendering by pointerType |

### Test Quality

The `BottomSheetTitleControlsTest.html` is well-structured:
- Uses DOMParser to parse `index.html` for structural tests
- Verifies Vue bindings via innerHTML inspection
- Tests Vue method availability via factory function instantiation
- Each test has a clear test ID (BSC-01 through BSC-40)

**Nit:** The DOMParser approach for testing Vue bindings (checking for `:aria-pressed` as literal strings) is a known pattern documented in the `building-web-apps` skill. It works but is inherently fragile if the HTML structure changes significantly.

---

## World Review — User Experience Perspective

### Critical Priority

**1. 3+ Finger OS Gesture Guard**
The `e.preventDefault()` at line 242-244 in MultiTouchHandler.js prevents the browser from handling 3+ finger gestures. However, the code still captures pointers for 3+ finger input via `setPointerCapture`. On iOS Safari, a 3-finger swipe is the back/forward navigation gesture. If the app captures these pointers, it could interfere with OS navigation.

**Mitigation:** The current code does call `e.preventDefault()` for 3+ pointers, which should prevent the OS gesture. However, the pointers are still added to `activePointers`. Consider adding an early return for 3+ pointers to avoid capturing them entirely:
```javascript
if (activePointers.size > 2) {
    e.preventDefault();
    activePointers.delete(e.pointerId); // Don't track 3+ finger pointers
    return;
}
```

**Verdict:** LOW RISK — the `preventDefault()` should be sufficient, but the extra cleanup would be more defensive.

**2. touch-action: none and Form Controls**
The `touch-action: none` is scoped to `#previewCanvas` only. The bottom sheet controls live in separate DOM elements outside the canvas. No inheritance issue expected.

**Verdict:** NO RISK — the CSS selector is specific to the canvas element.

**3. Pointer Capture Lifecycle**
The `pointercancel` handler in both MultiTouchHandler and TitleInteraction properly releases all captures. The `window.addEventListener('blur')` and `document.addEventListener('visibilitychange')` handlers in MultiTouchHandler provide additional safety nets.

**Verdict:** NO RISK — comprehensive cleanup is in place.

### Important Priority

**4. Resize Handle Visibility on High-DPR Displays**
The `drawTouchResizeHandles()` function uses logical pixel coordinates (radius = 8). The canvas rendering pipeline handles DPR scaling automatically — an 8px radius renders as 16px diameter on 1x displays and 32px on 2x displays. The white stroke (`#ffffff`) at 2px logical width will also scale with DPR.

**Potential concern:** The blue fill (`#3b82f6` solid or `rgba(59, 130, 246, 0.6)` semi-transparent) may have low contrast against light-colored title text or backgrounds. The white stroke helps, but consider testing against white backgrounds.

**Verdict:** LOW RISK — handles will be visible, but contrast testing on real devices is recommended.

**5. Trackpad Gestures**
The WheelEvent path (`_onWheel`) is completely unchanged. Trackpad two-finger pan (deltaY/deltaX) and pinch-to-zoom (deltaZ or ctrlKey+deltaY) continue to work via the wheel event listener.

**Verdict:** NO RISK — WheelEvent path is untouched.

**6. Bottom Sheet Control Clutter**
11 controls in a single bottom sheet tab is substantial. The controls are wrapped in `detail-section` divs which provide visual separation. The bottom sheet panel has `overflow-y: auto` for scrolling.

**Verdict:** ACCEPTABLE — the controls are well-organized with visual separators. Users who need advanced title customization will appreciate the parity.

**7. Device Rotation During Interaction**
The `pointerleave` handler correctly guards against clearing active interaction. The `setPointerCapture` ensures pointer events continue even if the pointer position changes during rotation. The canvas resize handler (not modified in this change) would trigger a re-render, which would update the title position.

**Verdict:** LOW RISK — pointer capture and the existing resize handler should handle this gracefully.

### Nice-to-Have

**8. Touch Hover State**
The `pointerleave` handler is primarily useful for mouse/pen interactions. On touch devices, `pointerleave` fires when the touch point moves outside the canvas element. With `setPointerCapture`, this shouldn't happen during active interaction.

**Verdict:** COSMETIC — the handler is harmless and provides a safety net.

**9. ARIA Labels**
All new form controls have appropriate ARIA attributes:
- Sliders: `aria-valuenow`, `aria-valuemin`, `aria-valuemax`
- Formatting buttons: `aria-pressed`
- Color picker: associated `<label>`
- Checkbox: associated `<label>`

**Verdict:** COMPLIANT — all controls have proper accessibility attributes.

**10. Graceful Degradation**
All `setPointerCapture` and `releasePointerCapture` calls are wrapped in try/catch blocks. The `applyZoomExponent` function guards against invalid input. The `pointerleave` handler guards against clearing active state.

**Verdict:** ROBUST — comprehensive error handling throughout.

---

## Issues Found

### Critical: None

No blocking issues found. The changes are architecturally sound and follow project conventions.

### Important: None

No significant issues found.

### Nits

1. **MultiTouchHandler.js line 242-244:** Consider deleting the pointer from `activePointers` when 3+ fingers are detected, rather than just calling `preventDefault()`. This avoids tracking pointers that won't participate in gestures.

2. **TitleRenderer.js `drawTouchResizeHandles`:** The hardcoded colors (`#3b82f6`, `rgba(59, 130, 246, 0.6)`, `#ffffff`) match the existing interaction outline colors. This is consistent but could be extracted to a shared constant if the color scheme changes in the future.

3. **EDGE_THRESHOLD_COARSE increase (16 → 22):** This is a good change for WCAG compliance (44px touch target / 2 = 22px). The comment correctly documents the rationale.

4. **Bottom sheet controls order:** The controls are added in a logical order (formatting → opacity → background → width → reset). This matches the desktop sidebar layout pattern.

---

## Approval Decision

**APPROVED**

The mobile touch enhancements are well-architected, thoroughly tested, and follow all project conventions. The changes:

1. **Follow SOLID principles** — single responsibility maintained, no tight coupling introduced
2. **Maintain separation of concerns** — clean layering across interaction, state, rendering, and presentation
3. **Are well-tested** — 40+ new tests covering all new functionality
4. **Have proper error handling** — try/catch for pointer capture, numeric guards, state cleanup
5. **Are accessible** — ARIA attributes on all new controls
6. **Follow project conventions** — factory functions, pure math exports, ES modules, `bs` ID prefixing

The world review confirms no critical user experience risks. The changes are ready for commit.

---

## Reviewer Notes

- **Architecture reviewer:** Primary review of SOLID principles, separation of concerns, code quality
- **World reviewer:** User experience analysis covering mobile/iOS/Android/desktop scenarios, accessibility, edge cases
- **Plan alignment:** All four phases of the implementation plan are addressed in the staged changes
