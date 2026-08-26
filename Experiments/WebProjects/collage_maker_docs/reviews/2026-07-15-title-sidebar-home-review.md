# Pre-Commit Code Review — 2026-07-15

**Reviewer:** build-docs agent (SOLID + architectural analysis) + world-review subagent (UX analysis)
**Scope:** 40 staged files, ~5,371 additions, ~883 deletions
**Branch:** `prototype/collage-maker`
**Plan Reference:** `_agent_docs/plans/2026-07-13-title-sidebar-home-implementation.md` (all 6 phases)

---

## Executive Summary

This commit implements the complete 6-phase plan: home link (Phase 1), sidebar reorganization with Layout moved to left sidebar (Phase 2), title opacity controls (Phase 3), title width and alignment within width (Phase 4), title position with reset (Phase 5), and title canvas interaction with drag-to-move and edge-drag-to-resize (Phase 6). Additionally, `HexPanelSwap.js` was generalized into `PanelSwap.js` to support all layouts, and `GestureHandler.js` was simplified by delegating panel selection to `PanelSwap`.

**Overall Assessment: REQUEST CHANGES** — one critical issue must be resolved before commit: **settings persistence for new title fields is missing**. Title opacity, position, and width will be lost on every page reload. The architectural quality is otherwise strong, with clean handler patterns, proper SOLID adherence, and good cross-handler coordination.

---

## 1. SOLID Principles Analysis

### Single Responsibility Principle (SRP)

**Strengths:**
- `TitleInteraction.js` (361 lines) owns exactly one concern: canvas pointer interaction for title box manipulation. Hit testing, drag, resize, and state coordination are all cohesive.
- `PanelSwap.js` (489 lines) cleanly separates `swapPanelAssignments()` pure function from `createPanelSwapHandler()` factory. The `adaptCropToPanelAspect()` function is a standalone pure function.
- `TitleRenderer.js` extracts `computeBounds()` as a pure function — testable without DOM, reusable by interaction handler.
- `TitleManager.js` new methods (`setFontOpacity`, `setBgOpacity`, `setWidth`, `setPosition`, `resetPosition`) each do one thing with proper clamping/validation.
- Handler factories (`createTitleHandlers`, `createTitleInteraction`, `createPanelSwapHandler`) follow the same pattern: accept options, return handler with `attach()`/`detach()`.

**No concerns.**

### Open/Closed Principle (OCP)

**Strengths:**
- `computeBounds()` is a pure function that can be used by any future interaction handler without modifying TitleRenderer.
- `PanelSwap.js` generalizes from hex-only to all layouts — new layouts automatically get drag-and-drop swap support.
- `drawInteractionOutline()` is a private helper that can be extended for other interactive elements.

**No concerns.**

### Liskov Substitution Principle (LSP)

Not applicable — factory function architecture avoids class inheritance.

### Interface Segregation Principle (ISP)

**Strengths:**
- `createTitleInteraction()` accepts a focused options object: `{ canvasId, state, titleManager, onRenderScheduled, onInteractionStart, onInteractionEnd }` — each parameter serves a clear purpose.
- `createPanelSwapHandler()` accepts `{ canvasId, state, onPanelSelected, onRenderScheduled, onSwapPerformed, onTargetHovered, onDragStart, onDragEnd }` — optional callbacks for optional features.

**No concerns.**

### Dependency Inversion Principle (DIP)

**Strengths:**
- All handler factories use injected callbacks (`onRenderScheduled`, `onInteractionStart`, `onInteractionEnd`) — no dependency on Vue instance methods.
- `TitleInteraction` depends on `titleManager` abstraction (factory return value), not on a concrete class.
- `computeBounds` accepts optional `measureCtx` — callers can provide a context to avoid offscreen canvas creation.

**Concerns:**

| Priority | File | Lines | Issue |
|----------|------|-------|-------|
| Low | `TitleInteraction.js` | 113-140 | `_hitTestTitle` hardcodes `1920` and `1080` as the canonical canvas dimensions. These are the `SIZE_CONSTANTS` values but should ideally be injected or imported for consistency. |
| Low | `TitleInteraction.js` | 230-235 | Drag clamping also hardcodes `1920`, `1080`, `400` (default width). Same concern. |

---

## 2. Architectural Quality

### Event Handler Coordination

**Files:** `TitleInteraction.js`, `PanelSwap.js`, `MultiTouchHandler.js`, `GestureHandler.js`

The cross-handler coordination pattern is well-designed:

```
Pointer event flow (highest priority first):
1. TitleInteraction — checks _multiTouchGestureActive guard, sets titleInteractionMode
2. PanelSwap — checks _multiTouchGestureActive AND titleInteractionMode guards
3. MultiTouchHandler — manages _multiTouchGestureActive flag
4. GestureHandler — hover-only (pointerdown removed, delegated to PanelSwap)
```

This priority chain prevents conflicts. The `_multiTouchGestureActive` state flag is the right abstraction for coordinating touch vs. pointer interactions.

### Handler Attachment Order

**File:** `createCollageLifecycle.js` lines 192-252

The attachment order is intentional and correct:
1. `_titleInteraction.attach()` fires first
2. `_panelSwapHandler.attach()` fires second (after title)

This ensures TitleInteraction's `pointerdown` handler runs before PanelSwap's, allowing it to set `titleInteractionMode` which PanelSwap checks. The comment at line 250 documents this rationale.

**Strength.**

### Pure Function Extraction

**File:** `TitleRenderer.js` lines 17-78

`computeBounds()` is properly extracted as a pure function with:
- No side effects on passed context (uses `measureCtx` if provided, creates offscreen canvas otherwise)
- Deterministic output for same inputs
- JSDoc documenting parameters and return type
- Exported for use by `TitleInteraction.js`

**Strength.**

### Legacy Mode Preservation

**File:** `TitleRenderer.js` lines 156-175

The renderer correctly preserves backward compatibility:
- When `titleBoxWidth` and `titleBoxX` are both `null`, renders identically to pre-change behavior
- `isLegacyMode` flag controls background padding offset calculation
- Text alignment within canvas (not within box) in legacy mode

**Strength.**

### Undo Integration

**File:** `createCollageLifecycle.js` lines 195-242

Title interaction undo is well-implemented:
- Captures pre-interaction state on `onInteractionStart`
- Pushes undo command only if values actually changed (avoids empty undo entries)
- Both undo and redo restore exact state values
- Snapshot cleared after command is pushed

**Strength.**

---

## 3. Critical Issues (Must Fix Before Commit)

### CI-1: Missing Settings Persistence for New Title Fields

**Severity: CRITICAL — BLOCKS COMMIT**

**Files:** `createSettingsHandlers.js` (NOT modified), `createCollageLifecycle.js` (not modified in persistence section)

**Problem:** The new title fields are NOT saved to or loaded from localStorage:
- `fontOpacity` — not persisted
- `bgOpacity` — not persisted
- `titleBoxWidth` — not persisted
- `titleBoxX` — not persisted
- `titleBoxY` — not persisted

Additionally, pre-existing fields are also missing from persistence:
- `showBackground` — not persisted
- `backgroundColor` (title) — not persisted

**Impact:** All title customization (opacity, position, width, background settings) will be lost on every page reload. This makes the feature practically unusable for any workflow that involves navigation or page refresh.

**Fix Required:**

In `createSettingsHandlers.js` `_saveSettings()`:
```javascript
titleFontOpacity: state.titleStyle.fontOpacity,
titleBgOpacity: state.titleStyle.bgOpacity,
titleBoxWidth: state.titleStyle.titleBoxWidth,
titleBoxX: state.titleStyle.titleBoxX,
titleBoxY: state.titleStyle.titleBoxY,
titleShowBackground: state.titleStyle.showBackground,
titleBackgroundColor: state.titleStyle.backgroundColor,
```

In `_applySavedSettings()`:
```javascript
if (settings.titleFontOpacity !== undefined) state.titleStyle.fontOpacity = settings.titleFontOpacity;
if (settings.titleBgOpacity !== undefined) state.titleStyle.bgOpacity = settings.titleBgOpacity;
if (settings.titleBoxWidth !== undefined) state.titleStyle.titleBoxWidth = settings.titleBoxWidth;
if (settings.titleBoxX !== undefined) state.titleStyle.titleBoxX = settings.titleBoxX;
if (settings.titleBoxY !== undefined) state.titleStyle.titleBoxY = settings.titleBoxY;
if (settings.titleShowBackground !== undefined) state.titleStyle.showBackground = settings.titleShowBackground;
if (settings.titleBackgroundColor) state.titleStyle.backgroundColor = settings.titleBackgroundColor;
```

Same changes needed in `createCollageLifecycle.js` `_applySavedSettings()` method (lines 367-371).

---

## 4. Important Issues (Should Fix)

### II-1: Hardcoded Canvas Dimensions in TitleInteraction

**File:** `TitleInteraction.js` lines 113-140, 230-235

**Problem:** Multiple hardcoded references to `1920` and `1080` as canvas dimensions. These match `SIZE_CONSTANTS` but create a maintenance risk if constants ever change.

**Recommendation:** Import `SIZE_CONSTANTS` from `../Models/SizeConstants.js` and use `SIZE_CONSTANTS.CANVAS_WIDTH` and `SIZE_CONSTANTS.CANVAS_HEIGHT`.

### II-2: Title Drag Boundary Clamping

**File:** `TitleInteraction.js` lines 230-235

**Problem:** The clamping logic allows the title to be dragged partially off-canvas. The Y clamp is `Math.max(fontSize + 12, Math.min(newY, 1080 - 12))` which allows the title baseline to go near the top edge, potentially putting the title box entirely above the visible area.

**Recommendation:** Clamp so at least part of the title box remains visible. For example:
```javascript
newX = Math.max(-boxWidth + 50, Math.min(newX, 1920 - 50));
```
This allows 50px of the box to remain visible even when dragged to an edge.

### II-3: Slider ARIA Attributes for Range Inputs

**File:** `index.html` title section

**Problem:** The opacity sliders have `aria-valuenow`, `aria-valuemin`, and `aria-valuemax` attributes, but the width slider does not:
```html
<input type="range" id="titleWidthSlider" v-model.number="titleStyle.titleBoxWidth" min="100" max="1920" step="1" class="fullRange" @input="onTitleWidthChange">
```

**Recommendation:** Add ARIA attributes:
```html
:aria-valuenow="(titleStyle.titleBoxWidth ? Math.round(titleStyle.titleBoxWidth) + 'px' : 'Auto')"
aria-valuemin="100px"
aria-valuemax="1920px"
```

### II-4: `onTitleWidthChange` Parameter Handling

**File:** `createTitleHandlers.js` lines 189-198

**Problem:** The handler accepts an optional `value` parameter with backward compat logic:
```javascript
onTitleWidthChange(value) {
    const w = value !== undefined ? Number(value) : this.titleStyle.titleBoxWidth;
    titleManager.setWidth(w);
}
```

When called from the Vue template via `@input="onTitleWidthChange"`, the event object is passed, not the value. Since `v-model.number` already updates `this.titleStyle.titleBoxWidth`, the handler correctly falls back to `this.titleStyle.titleBoxWidth`. However, this is fragile — if the template binding changes, the fallback might not work.

**Recommendation:** Remove the `value` parameter and always read from `this.titleStyle.titleBoxWidth` (since `v-model.number` is the source of truth):
```javascript
onTitleWidthChange() {
    const titleManager = getTitleManager();
    if (titleManager) {
        titleManager.setWidth(this.titleStyle.titleBoxWidth);
    }
    onRenderScheduled(this);
}
```

---

## 5. Nice-to-Have (Post-Commit Polish)

### NI-1: Touch Device Edge Resize Discovery

**Context:** Edge-drag-to-resize relies on cursor feedback (`ew-resize`) which doesn't exist on touch devices. The edge hit area (8 CSS pixels) may be too small for finger interaction.

**Recommendation:** Consider drawing subtle visual resize handles (small circles or vertical bars) at the left and right edges of the title box when it's in an active state. Alternatively, increase `EDGE_THRESHOLD` for touch pointer types.

### NI-2: Keyboard Nudging for Title Position

**Context:** The plan explicitly excludes keyboard nudging ("Arrow key position adjustment for title is out of scope"). However, this is an accessibility gap for keyboard-only users.

**Recommendation:** Defer to a future iteration, but document as a known accessibility limitation.

### NI-3: Interaction Hint for New Users

**Context:** Canvas title interaction (drag to move, edge-drag to resize) is a new mental model.

**Recommendation:** Add a subtle hint in the Title section: "Drag the title on the canvas to reposition it."

### NI-4: PanelSwap `_capturedPointerId` Property

**File:** `PanelSwap.js` line 237

The `_clearDragState` method references `this._capturedPointerId` but this property is set in `_onPointerDown` as `this._capturedPointerId = e.pointerId`. This works but is inconsistent with `TitleInteraction.js` which uses a module-level `capturedPointerId` variable.

**Recommendation:** Align the pattern — either both use module-level variables or both use `this.` properties. Prefer module-level for consistency with the existing handler pattern.

---

## 6. World-Review UX Analysis Summary

The world-review subagent identified the following additional UX considerations:

### Strengths Identified:
- **Excellent accessibility foundations:** Home link with `target="_blank" rel="noopener noreferrer"`, 44x44 minimum touch targets, proper ARIA attributes
- **Smart state coordination:** `_multiTouchGestureActive` flag prevents conflicting pointer events
- **Graceful legacy support:** Existing projects render identically when no custom title settings are applied

### Concerns Identified (summarized):
| # | Issue | Severity | Status |
|---|-------|----------|--------|
| 1 | Missing keyboard navigation for canvas title interactions | Critical (accessibility) | Out of scope per plan, document as known limitation |
| 2 | Touch devices lack visual feedback for edge-resize | Important | See NI-1 |
| 3 | Title can be dragged off-canvas with no recovery | Important | See II-2 |
| 4 | Slider-triggered re-renders may cause performance jank | Important | Existing `_scheduleRender` uses `requestAnimationFrame` — low risk |
| 5 | Layout section default collapsed + muscle memory shift | Low | `autoExpandLayoutOnImages()` mitigates for multi-image projects |
| 6 | Slider ARIA attributes incomplete | Important | See II-3 |

---

## 7. Test Coverage Assessment

### New Tests
| Test File | Lines | Coverage |
|-----------|-------|----------|
| `TitleInteractionTest.html` | 1083 | Hit testing, drag, resize, edge detection, pointer capture, state coordination |
| `PanelSwapTest.html` | 990 | Panel hit testing, swap logic, crop adaptation, aspect ratio handling |
| `test/e2e/home-link.spec.js` | 174 | Visibility, attributes, accessibility, focus, new tab, touch target, mobile viewport |

### Existing Tests Updated
| Test File | Changes |
|-----------|---------|
| `TitleManagerTest.html` | +194 lines — opacity, width, position, reset tests |
| `TitleRendererTest.html` | +465 lines — opacity rendering, width/alignment, interaction outline |
| `MultiTouchHandlerTest.html` | +238 lines — `_multiTouchGestureActive` flag tests |
| `RenderingTest.html` | +48 lines — assembler interaction state passthrough |
| `SidebarSectionsTest.html` | +78 lines — left sidebar collapsible tests |
| `CropOverlayShapeTest.html` | +209 lines — shape overlay tests |
| `CropPreviewTest.html` | +271 lines — new crop preview tests |
| `Phase3FollowUpTest.html` | +207 lines — refactoring follow-up tests |

### Test Gaps
| Gap | Severity |
|-----|----------|
| No test for settings persistence of new title fields (because persistence is missing) | Critical — tied to CI-1 |
| No E2E test for title canvas interaction (drag/resize) | Medium — complex to automate, manual testing acceptable |
| No E2E test for sidebar reorganization (layout in left sidebar) | Low — UI-only change, existing tests cover functionality |

---

## 8. Code Quality

### Naming
- `hexDragTargetId` → `dragTargetId` rename is consistent across all files
- `createHexDragHandler` → `createPanelSwapHandler` rename is clear and accurate
- `drawHexDragTarget` → `drawDragTarget` rename is consistent

### Documentation
- All new functions have JSDoc comments
- `TitleInteraction.js` has comprehensive module-level documentation
- `PanelSwap.js` documents `adaptCropToPanelAspect` algorithm

### Style Consistency
- Event handler binding pattern (late-binding with placeholder variables) is consistent across all handlers
- Factory function return value pattern is consistent
- `save()`/`restore()` pattern for `globalAlpha` is properly applied

---

## 9. Decision

**REQUEST CHANGES** — one critical blocking issue:

1. **CI-1: Add settings persistence for new title fields** (`fontOpacity`, `bgOpacity`, `titleBoxWidth`, `titleBoxX`, `titleBoxY`, `showBackground`, `backgroundColor`) in both `createSettingsHandlers.js` and `createCollageLifecycle.js`.

Once CI-1 is resolved, the commit is ready for approval. The important issues (II-1 through II-4) and nice-to-haves can be addressed in follow-up commits.

---

## 10. Reviewer Sign-Off

| Reviewer | Verdict | Notes |
|----------|---------|-------|
| build-docs (SOLID + architecture) | REQUEST CHANGES | CI-1 blocks; II-1 through II-4 should be addressed |
| world-review (UX) | APPROVE with notes | Accessibility gap (keyboard nudge) is documented as out-of-scope; touch resize discovery is a polish item |
