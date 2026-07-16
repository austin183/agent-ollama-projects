# Change Requests Follow-Up Implementation Plan

**Date:** July 9, 2026
**Status:** Phase 1 implemented (CR-FU-04, CR-FU-06), Phase 2 implemented (CR-FU-03, CR-FU-08), Phase 4 implemented (CR-FU-02), Phase 5 implemented (CR-FU-09)
**Supersedes:** None (complements `2026-07-07-change-requests-implementation-plan.md`)

| CR | Description | Existing Phase | Risk |
|----|-------------|----------------|------|
| CR-FU-01 | Sidebar Reorder | Phase 3 | Low |
| CR-FU-02 | Multi-Finger Trackpad Gestures (PointerEvent) | Phase 4 | Medium |
| CR-FU-03 | Clickable Color Labels | Phase 2 | Low |
| CR-FU-04 | Saliency Failure Toast | Phase 1 | Low |
| CR-FU-05 | Hex Panel Swap Visual Feedback | Phase 3 | Medium |
| CR-FU-06 | Keyboard Shortcut Discoverability | Phase 1 | Low |
| CR-FU-07 | ARIA Accessibility for Collapsible Sidebar | Phase 3 | Low |
| CR-FU-08 | Export Progress Loading Indicator | Phase 2 | Low |
| CR-FU-09 | Complete Method Extraction from createCollageMethods | Phase 5 | Medium-High |

---

## Overview

This plan addresses 9 follow-up change requests that were identified during code review and post-implementation feedback. These changes integrate into the existing 5-phase implementation plan (`2026-07-07-change-requests-implementation-plan.md`) without requiring new phases. They span quick UI fixes, accessibility improvements, interaction enhancements, and architectural refactoring.

## Current State Analysis

### Architecture (unchanged from base plan)
- **Framework:** Vue 3 Options API, CDN-loaded, no build step
- **Rendering:** Canvas 2D via `CollageAssembler.js` pipeline: clear → background → panels → hover → selection → debug → overlay → title
- **State:** Factory managers with callback injection pattern
- **Interaction:** Handler modules with `createXxxHandler({ callbacks })` → `{ attach, detach }`

### Key Discoveries from Review

1. **Toast notifications appear in 3+ CRs** (saliency failure, export success/error, potential future uses). A shared toast/notification pattern is recommended to avoid ad-hoc implementations.

2. **`MultiTouchHandler.js` comment is outdated** — says "PointerEvents don't support multi-touch tracking" which is false. Modern PointerEvents support multi-touch via `pointerId`. The handler should be extended (not replaced) with PointerEvent support.

3. **`index.html` sidebar is data-driven** — uses `v-for="section in sidebarSections"` with `<template v-if="section.id === 'xxx'">` blocks. Reordering the `sidebarSections` array in `createCollageData.js` is sufficient — no template changes needed.

4. **Export progress is partially implemented** — `isExporting` state exists, button is disabled during export, text shows "Exporting...". Missing: visual spinner, success/error toast feedback.

5. **`createCollageMethods.js` is 558 lines** — contains closure functions for render scheduling, crop preview rendering, and undo/redo. The skill reference (`building-web-apps/SKILL.md` line 89) advises against extraction if functions already use callback injection with explicit parameters. Extraction is optional for organizational clarity.

6. **Color swatches exist but are non-interactive** — `<span class="color-swatch">` elements have `aria-hidden="true"` and no click handler. They look clickable but do nothing.

7. **Export button already has shortcut tooltip** — `:title="'Export as ' + (exportFormat === 'jpeg' ? 'JPEG' : 'PNG') + ' (Cmd+E)'"` is already present. Only layout shortcuts need discoverability improvements.

### Key Discoveries (file references):
- `MyESModules/App/createCollageData.js` — `sidebarSections` array, `isExporting`, `exportStatus` reactive state
- `MyESModules/Interaction/MultiTouchHandler.js` — TouchEvent-only implementation, outdated comment about PointerEvents
- `MyESModules/Interaction/HexPanelSwap.js` — tracks `dragSourceId` and `isDragging` but no target hover tracking
- `MyESModules/App/createCollageLifecycle.js` — saliency `onModelsFailed` callback wiring point
- `index.html` lines 92-327 — sidebar template with collapsible sections
- `index.html` line 318 — export button with existing `:disabled="isExporting"` binding
- `index.html` lines 155-165, 225-244 — color picker rows with non-interactive swatches

## Desired End State

After all follow-up changes complete:
1. Right sidebar order is Crop → Layout → Background → Overlay → Title → Export
2. Two-finger trackpad pan and pinch-to-zoom work on the preview canvas (macOS trackpad + touchscreens)
3. Color swatch buttons are clickable and open the native color picker
4. Saliency model failure shows a non-blocking toast: "AI features unavailable — using default focus"
5. Hex panel drag-and-drop shows target highlighting and cursor feedback during drag
6. Keyboard shortcuts are discoverable via UI hints (layout shortcuts listed, export tooltip present)
7. Collapsible sidebar sections have proper ARIA attributes for screen reader support
8. Export shows a loading spinner and success/error feedback
9. Method extraction from `createCollageMethods.js` is complete (optional, deferred if risk is deemed too high)

## What We're NOT Doing

- **No dedicated Toast component** — toasts are implemented as simple reactive state + template elements. A full toast component library is out of scope.
- **No keyboard shortcut help modal** — shortcut hints are inline only. A modal dialog is deferred to a future sprint.
- **No transparent PNG exports** — documented as a future consideration in the review follow-ups. No action in this plan.
- **No PointerEvent migration** — we extend `MultiTouchHandler` with PointerEvent support alongside the existing TouchEvent path, not replace it. This minimizes risk.
- **No method extraction if skill guidance says it's unnecessary** — CR-FU-09 is scoped as optional. If the team agrees that callback injection is sufficient, extraction can be deferred.

---

## Cross-Cutting Pattern: Shared Toast/Notification

Multiple CRs require toast notifications. Rather than ad-hoc implementations, we establish a minimal shared pattern:

### Reactive State (in `createCollageData.js`)
```javascript
toast: {
    message: '',
    type: '',       // 'info', 'success', 'error'
    visible: false,
    timer: null
}
```

### Method (in `createCollageMethods.js`)
```javascript
showToast(message, type = 'info', duration = 5000) {
    // Clear existing timer to prevent stale auto-dismiss
    if (this.toast.timer) {
        clearTimeout(this.toast.timer);
    }
    this.toast.message = message;
    this.toast.type = type;
    this.toast.visible = true;
    this.toast.timer = setTimeout(() => {
        this.toast.visible = false;
        this.toast.message = '';
        this.toast.timer = null;
    }, duration);
}
```

### Template (in `index.html`, at root level)
```html
<div class="toast-notification"
     v-show="toast.visible"
     :class="'toast-' + toast.type"
     role="alert"
     aria-live="polite">
    <span class="material-icons">{{ toast.type === 'error' ? 'error' : 'info' }}</span>
    {{ toast.message }}
</div>
```

### CSS (in `Style.css`)
```css
.toast-notification {
    position: fixed;
    bottom: 16px;
    left: 50%;
    transform: translateX(-50%);
    padding: 10px 20px;
    border-radius: 8px;
    font-size: 14px;
    display: flex;
    align-items: center;
    gap: 8px;
    z-index: 300;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
    transition: opacity 0.3s ease;
}
.toast-info { background-color: #3b82f6; color: white; }
.toast-success { background-color: #22c55e; color: white; }
.toast-error { background-color: #ef4444; color: white; }
.toast-notification .material-icons { font-size: 18px; }
```

This pattern is reused by CR-FU-04 (saliency toast) and CR-FU-08 (export progress feedback).

---

## Phase 1 Additions: Saliency Toast + Shortcut Discoverability

### Overview

Two lightweight additions to Phase 1: user-visible feedback for saliency failures, and keyboard shortcut discoverability hints. Both depend on Phase 1's CR-11 (saliency timeout) and CR-10 (keyboard shortcut conflicts) respectively.

### Changes Required

#### 1. CR-FU-04: Saliency Failure Toast

**File:** `MyESModules/App/createCollageData.js`
**Changes:** Add `toast` reactive state object (see cross-cutting pattern above).

**File:** `MyESModules/App/createCollageMethods.js`
**Changes:** Add `showToast()` method (see cross-cutting pattern above).

**File:** `MyESModules/App/createCollageLifecycle.js`
**Changes:** Wire `onModelsFailed` callback to call `this.showToast('AI features unavailable — using default focus', 'info', 5000)`.

**File:** `index.html`
**Changes:** Add toast notification template at root level (see cross-cutting pattern above).

**File:** `Style.css`
**Changes:** Add `.toast-notification` styles (see cross-cutting pattern above).

**Success Criteria:**

##### Automated Verification:
- [ ] Unit test: `showToast()` sets `toast.visible = true` and `toast.message`
- [ ] Unit test: `showToast()` auto-dismisses after duration (mock `setTimeout`)
- [ ] Unit test: Rapid successive calls clear previous timer (no overlapping toasts)
- [ ] Unit test: `onModelsFailed` callback invokes `showToast()` with correct message

##### Manual Verification:
- [ ] Block TF.js network requests, verify toast appears after 15s
- [ ] Toast auto-dismisses after 5 seconds
- [ ] App continues normally with center-crop fallback
- [ ] Toast does not block interaction with the app

---

#### 2. CR-FU-06: Keyboard Shortcut Discoverability

**File:** `index.html`
**Changes:** Add shortcut hint below the layout style selector:
```html
<div class="layout-shortcut-hint">
    Shortcuts: Alt+1 Uniform · Alt+2 Hero · Alt+3 Mosaic · Alt+4 Slices · Alt+5 Hex
</div>
```

**File:** `Style.css`
**Changes:** Add `.layout-shortcut-hint` styles:
```css
.layout-shortcut-hint {
    font-size: 11px;
    color: var(--color-text-secondary, #888);
    padding: 4px 16px 8px;
    opacity: 0.7;
    line-height: 1.4;
}
```

**Note:** The export button already has a `title` attribute with the shortcut: `:title="'Export as ' + (exportFormat === 'jpeg' ? 'JPEG' : 'PNG') + ' (Cmd+E)'"`. No changes needed there.

**Success Criteria:**

##### Automated Verification:
- [ ] Layout hint element exists in DOM when Layout section is expanded
- [ ] Hint text contains "Alt+1" through "Alt+5"

##### Manual Verification:
- [ ] Hover over export button → tooltip shows "Export as JPEG (Cmd+E)"
- [ ] Layout shortcut hint is visible and legible
- [ ] Hint text matches actual shortcut bindings

---

### Phase 1 Additions Test Plan

#### Unit Tests — Toast System

| # | Test | Input | Expected |
|---|------|-------|----------|
| 1A.1.1 | Toast shows on call | `showToast('msg', 'info', 5000)` | `toast.visible === true`, `toast.message === 'msg'` |
| 1A.1.2 | Toast auto-dismisses | `showToast()`, wait 5001ms (mocked) | `toast.visible === false`, `toast.message === ''` |
| 1A.1.3 | Rapid calls clear previous timer | `showToast()` twice in quick succession | Only one timer active, no double-dismiss |
| 1A.1.4 | Toast type is preserved | `showToast('err', 'error')` | `toast.type === 'error'` |

#### Unit Tests — Saliency Toast Wiring

| # | Test | Input | Expected |
|---|------|-------|----------|
| 1A.2.1 | onModelsFailed calls showToast | Simulate saliency timeout | `showToast` invoked with "AI features unavailable..." |
| 1A.2.2 | Toast is non-blocking | Toast visible, user clicks other UI | Other UI interactions proceed normally |

#### E2E Tests — Shortcut Discoverability

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 1A.3.1 | Export tooltip shows shortcut | Hover export button | Tooltip contains "Cmd+E" |
| 1A.3.2 | Layout hint is visible | Expand Layout section | Hint text visible with all 5 shortcuts |

#### Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | 1A.1.1, 1A.2.1 | Core toast and saliency feedback |
| **P1** | 1A.1.2, 1A.1.3 | Toast lifecycle correctness |
| **P2** | 1A.3.1, 1A.3.2 | Shortcut discoverability (visual only) |

#### Known Behaviors
- Toast uses `role="alert"` and `aria-live="polite"` for screen reader announcement
- Toast auto-dismiss timer is cleared on successive calls (no stacking)
- Toast is positioned at bottom-center, z-index 300 (above sidebar, below modal)
- Layout shortcut hint uses `·` (middle dot) as separator

---

## Phase 2 Additions: Clickable Color Labels + Export Progress

### Overview

Two lightweight UI enhancements: make color swatch buttons clickable to open the native color picker, and add a loading spinner to the export button with success/error toast feedback.

### Changes Required

#### 1. CR-FU-03: Clickable Color Labels

**File:** `index.html`
**Changes:** For each color picker row, make the `.color-swatch` clickable:

For the Background Color swatch (line ~227):
```html
<span class="color-swatch"
      :style="{ backgroundColor: backgroundColor }"
      @click="$refs.bgColorPicker?.click()"
      role="button"
      tabindex="0"
      @keydown.enter="$refs.bgColorPicker?.click()"
      :aria-label="'Change background color. Current: ' + backgroundColor">
</span>
```

Apply the same pattern to all color swatches:
- Title Font Color (line ~157)
- Title Background Color (line ~163)
- Gradient Color 1 (line ~236)
- Gradient Color 2 (line ~242)

Each swatch clicks its corresponding `<input type="color">` element. Use `ref` attributes on the color inputs for reliable targeting.

**File:** `Style.css`
**Changes:** Update `.color-swatch` to indicate clickability:
```css
.color-swatch {
    cursor: pointer;
    /* ... existing styles ... */
}
.color-swatch:hover {
    opacity: 0.85;
    outline: 2px solid var(--color-primary, #4285f4);
    outline-offset: 2px;
}
```

**Success Criteria:**

##### Automated Verification:
- [ ] Each `.color-swatch` has `role="button"` and `tabindex="0"`
- [ ] Each `.color-swatch` has `aria-label` containing the current color value

##### Manual Verification:
- [ ] Clicking a color swatch opens the native color picker
- [ ] Tabbing to a swatch and pressing Enter opens the color picker
- [ ] Hover shows outline feedback
- [ ] Screen reader announces "button, change background color. Current: #xxxxxx"

---

#### 2. CR-FU-08: Export Progress Loading Indicator

**File:** `index.html`
**Changes:** Add a spinner icon to the export button:
```html
<button id="exportBtn" class="pure-button pure-button-primary export-btn"
        @click="exportCollage"
        :disabled="isExporting || images.length === 0"
        :title="'Export as ' + (exportFormat === 'jpeg' ? 'JPEG' : 'PNG') + ' (Cmd+E)'">
    <span v-if="isExporting" class="material-icons export-spinner">autorenew</span>
    <span v-else class="material-icons" style="vertical-align: middle; margin-right: 4px;">save</span>
    {{ isExporting ? 'Exporting...' : 'Export ' + exportFormat.toUpperCase() }}
</button>
```

**File:** `MyESModules/App/createExportHandlers.js`
**Changes:** After successful export, call `this.showToast('Collage exported!', 'success', 3000)`. On error, call `this.showToast('Export failed: ' + error.message, 'error', 5000)`.

**File:** `Style.css`
**Changes:** Add spinner animation:
```css
.export-spinner {
    vertical-align: middle;
    margin-right: 4px;
    animation: export-spin 1s linear infinite;
}
@keyframes export-spin {
    from { transform: rotate(0deg); }
    to { transform: rotate(360deg); }
}
```

**Success Criteria:**

##### Automated Verification:
- [ ] Export button is `:disabled` when `isExporting === true`
- [ ] Spinner element is visible when `isExporting === true`
- [ ] Success toast calls `showToast()` with 'success' type after export
- [ ] Error toast calls `showToast()` with 'error' type on export failure

##### Manual Verification:
- [ ] Click export → button disabled, spinner appears, text shows "Exporting..."
- [ ] After export completes → button re-enables, success toast appears
- [ ] Success toast auto-dismisses after 3 seconds
- [ ] Export button is re-enabled even if export fails

---

### Phase 2 Additions Test Plan

#### Unit Tests — Color Swatch Clickability

| # | Test | Input | Expected |
|---|------|-------|----------|
| 2A.1.1 | Swatch click triggers color input | Click `.color-swatch` | Corresponding `<input type="color">.click()` called |
| 2A.1.2 | Swatch Enter key triggers color input | Focus swatch, press Enter | Same as above |
| 2A.1.3 | Swatch has role="button" | Inspect DOM | `role="button"` present |

#### Unit Tests — Export Progress

| # | Test | Input | Expected |
|---|------|-------|----------|
| 2A.2.1 | isExporting set before export | Call `exportCollage()` | `isExporting === true` immediately |
| 2A.2.2 | isExporting cleared after export | Export completes | `isExporting === false` in `finally` |
| 2A.2.3 | isExporting cleared on error | Export throws | `isExporting === false` in `finally` |
| 2A.2.4 | Success toast on completion | Export succeeds | `showToast('Collage exported!', 'success')` called |
| 2A.2.5 | Error toast on failure | Export throws error | `showToast('Export failed: ...', 'error')` called |

#### E2E Tests — Export Progress

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 2A.3.1 | Button disabled during export | Click export | Button disabled, spinner visible |
| 2A.3.2 | Button re-enabled after export | Wait for export | Button enabled, success toast visible |
| 2A.3.3 | Double-click prevention | Click export twice rapidly | Only one export initiated |

#### Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | 2A.2.1, 2A.2.2, 2A.2.3 | Export state management correctness |
| **P0** | 2A.3.1, 2A.3.3 | Export UX safety (no double-clicks) |
| **P1** | 2A.1.1, 2A.1.2 | Color swatch clickability |
| **P1** | 2A.2.4, 2A.2.5 | Export feedback toasts |
| **P2** | 2A.1.3, 2A.3.2 | Accessibility and polish |

#### Known Behaviors
- Native `<input type="color">` opens a browser-native picker — behavior varies by OS/browser
- Spinner uses CSS `@keyframes` animation, no JavaScript animation loop
- Export toasts use the shared toast pattern from Phase 1
- `isExporting` is managed in `createExportHandlers.js` via `try/finally`

---

## Phase 3 Additions: Sidebar Reorder + ARIA + Hex Swap Feedback

### Overview

Three changes for Phase 3: reorder the sidebar sections, add ARIA accessibility attributes, and add visual feedback during hex panel drag-and-drop. The sidebar reorder and ARIA changes are trivial; hex swap feedback is medium-risk as it touches the rendering pipeline.

### Changes Required

#### 1. CR-FU-01: Sidebar Reorder

**File:** `MyESModules/App/createCollageData.js`
**Changes:** Reorder the `sidebarSections` array:
```javascript
sidebarSections: [
    { id: 'crop', label: 'Crop' },
    { id: 'layout', label: 'Layout' },
    { id: 'background', label: 'Background' },
    { id: 'overlay', label: 'Overlay' },
    { id: 'title', label: 'Title' },
    { id: 'export', label: 'Export' }
]
```

**File:** `index.html`
**Changes:** None needed — the sidebar uses `v-for="section in sidebarSections"` with `v-if` blocks keyed by `section.id`. Reordering the array is sufficient.

**Success Criteria:**

##### Automated Verification:
- [ ] `sidebarSections[0].id === 'crop'`
- [ ] `sidebarSections[1].id === 'layout'`
- [ ] All 6 sections present in correct order

##### Manual Verification:
- [ ] Visual order matches: Crop → Layout → Background → Overlay → Title → Export

---

#### 2. CR-FU-07: ARIA Accessibility for Collapsible Sidebar

**File:** `index.html`
**Changes:** Add `aria-controls` to section headers and `id` to content containers:
```html
<button class="sidebar-section-header"
        @click="toggleSection(section.id)"
        :aria-expanded="expandedSections[section.id]"
        :aria-controls="'section-content-' + section.id">
    <span class="section-chevron" :class="{ expanded: expandedSections[section.id] }">▶</span>
    <span>{{ section.label }}</span>
</button>
<div class="sidebar-section-content"
     :id="'section-content-' + section.id"
     v-show="expandedSections[section.id]">
    <!-- section content -->
</div>
```

**Note:** `aria-expanded` is already present. This change adds `aria-controls` and the corresponding `id`.

**Success Criteria:**

##### Automated Verification:
- [ ] Each header has `aria-controls` pointing to `'section-content-' + section.id`
- [ ] Each content container has matching `id`
- [ ] `aria-expanded` toggles between `true` and `false`

##### Manual Verification:
- [ ] VoiceOver (macOS) announces section headers as "button, collapsed" / "button, expanded"
- [ ] Activating section header toggles content visibility
- [ ] Focus management: pressing Enter/Space on header toggles section

---

#### 3. CR-FU-05: Hex Panel Swap Visual Feedback

**File:** `MyESModules/Interaction/HexPanelSwap.js`
**Changes:** Add target tracking during drag:
- Add `dragTargetId` state variable
- In `_onPointerMove`, perform hit test and update `dragTargetId`
- Call `onTargetHovered(dragTargetId)` when target changes
- Clear `dragTargetId` on drag end

```javascript
// New state
let dragTargetId = null;

// In _onPointerMove, when isDragging:
const newTargetId = hitTestPanel(coords.x, coords.y, panels, canvasWidth, canvasHeight);
if (newTargetId !== dragTargetId) {
    dragTargetId = newTargetId;
    if (callbacks.onTargetHovered) {
        callbacks.onTargetHovered(dragTargetId);
    }
    if (callbacks.onRenderScheduled) {
        callbacks.onRenderScheduled();
    }
}

// In drag end/cancel:
dragTargetId = null;
if (callbacks.onTargetHovered) {
    callbacks.onTargetHovered(null);
}
```

**File:** `MyESModules/App/createCollageData.js`
**Changes:** Add `hexDragTargetId: null` to reactive state.

**File:** `MyESModules/App/createCollageLifecycle.js`
**Changes:** Wire `onTargetHovered` callback:
```javascript
onTargetHovered: (targetId) => {
    this.hexDragTargetId = targetId;
}
```
Set canvas cursor during drag:
```javascript
onDragStart: () => { canvas.style.cursor = 'grabbing'; },
onDragEnd: () => { canvas.style.cursor = ''; }
```

**File:** `MyESModules/Rendering/CollageAssembler.js`
**Changes:** Add hex drag target highlight rendering between selection and overlay:
```javascript
// Hex drag target highlight
if (renderState.hexDragTargetId && panels) {
    const targetPanel = panels.find(p => p.id === renderState.hexDragTargetId);
    if (targetPanel) {
        panelRenderer.drawHexDragTarget(ctx, targetPanel);
    }
}
```

**File:** `MyESModules/Rendering/PanelRenderer.js`
**Changes:** Add `drawHexDragTarget` method:
```javascript
drawHexDragTarget(ctx, panel) {
    ctx.save();
    ctx.strokeStyle = '#4285f4';
    ctx.lineWidth = 3 / this.dpr;
    ctx.setLineDash([6 / this.dpr, 4 / this.dpr]);
    ctx.globalAlpha = 0.8;
    this._drawPanelGeometry(ctx, panel.geometry);
    ctx.restore();
}
```

**File:** `Style.css`
**Changes:** Ensure `#previewCanvas` has `cursor: grab` default for hexagonal layout.

**Success Criteria:**

##### Automated Verification:
- [ ] `onTargetHovered` callback fires with correct panel ID during drag
- [ ] `hexDragTargetId` is `null` when not dragging
- [ ] `hexDragTargetId` is cleared on drag end
- [ ] Canvas cursor is 'grabbing' during drag, '' after drag end

##### Manual Verification:
- [ ] Drag from one hex panel to another → target panel shows dashed blue highlight
- [ ] Cursor changes to grabbing during drag
- [ ] Highlight disappears when pointer leaves all panels
- [ ] After swap, both panels render fully (no clipping issues)
- [ ] Non-hexagonal layouts are unaffected

---

### Phase 3 Additions Test Plan

#### Unit Tests — Sidebar Reorder

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3A.1.1 | First section is Crop | `sidebarSections[0]` | `{ id: 'crop', label: 'Crop' }` |
| 3A.1.2 | All 6 sections present | `sidebarSections.length` | `6` |
| 3A.1.3 | Order is correct | `sidebarSections.map(s => s.id)` | `['crop', 'layout', 'background', 'overlay', 'title', 'export']` |

#### Unit Tests — ARIA Attributes

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3A.2.1 | Header has aria-controls | Inspect header element | `aria-controls="section-content-crop"` (etc.) |
| 3A.2.2 | Content has matching id | Inspect content element | `id="section-content-crop"` (etc.) |
| 3A.2.3 | aria-expanded toggles | Click header twice | `true` → `false` → `true` |

#### Unit Tests — Hex Swap Visual Feedback

| # | Test | Input | Expected |
|---|------|-------|----------|
| 3A.3.1 | Target hover fires on move | Drag over panel B from panel A | `onTargetHovered('panel-B')` called |
| 3A.3.2 | Target cleared on end | End drag | `onTargetHovered(null)` called |
| 3A.3.3 | No hover on non-hex layout | Drag on Uniform layout | No `onTargetHovered` calls |
| 3A.3.4 | Cursor set on drag start | Begin drag | `canvas.style.cursor === 'grabbing'` |
| 3A.3.5 | Cursor cleared on drag end | End drag | `canvas.style.cursor === ''` |

#### E2E Tests — Hex Swap Visual Feedback

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 3A.4.1 | Target highlight during drag | Hex layout, drag from panel A to B | Panel B shows dashed blue border |
| 3A.4.2 | Highlight follows pointer | Drag across multiple panels | Highlight moves with pointer |
| 3A.4.3 | Highlight clears on outside drop | Drag outside canvas, release | No highlight, drag reverts |
| 3A.4.4 | Full panels after swap | Swap two panels | Both panels render fully, no clipping |

#### Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | 3A.1.1-3A.1.3 | Sidebar order correctness |
| **P0** | 3A.3.1, 3A.3.2 | Hex swap target tracking |
| **P1** | 3A.2.1-3A.2.3 | ARIA accessibility |
| **P1** | 3A.3.3-3A.3.5 | Hex swap edge cases |
| **P1** | 3A.4.1-3A.4.3 | Hex swap visual feedback |
| **P2** | 3A.4.4 | Post-swap rendering correctness |

#### Known Behaviors
- `v-for` + `v-if` pattern in sidebar template is order-agnostic
- ARIA disclosure widget pattern follows WAI-ARIA Authoring Practices
- Hex drag target highlight renders between selection and overlay in the render pipeline
- Dashed line width and dash pattern are DPR-scaled
- Cursor management is scoped to hexagonal layout only

---

## Phase 4 Additions: Multi-Finger Trackpad Gestures (PointerEvent)

### Overview

Extend `MultiTouchHandler.js` to support PointerEvent for trackpad gestures (macOS two-finger pan, pinch-to-zoom). The existing TouchEvent path remains unchanged for touchscreen devices. A `pointerType` guard prevents double-firing on hybrid devices.

### Changes Required

#### 1. CR-FU-02: PointerEvent Support in MultiTouchHandler

**File:** `MyESModules/Interaction/MultiTouchHandler.js`
**Changes:** Add PointerEvent handler system alongside existing TouchEvent handlers:

```javascript
// New state for PointerEvent tracking
let activePointers = new Map(); // pointerId -> { clientX, clientY }
let pointerGestureActive = false;

// In attach():
canvas.addEventListener('pointerdown', _onPointerDown, { passive: false });
canvas.addEventListener('pointermove', _onPointerMove, { passive: false });
canvas.addEventListener('pointerup', _onPointerUp);
canvas.addEventListener('pointercancel', _onPointerCancel);

// Guard: skip PointerEvent for touch pointers (let TouchEvent handle them)
function _onPointerDown(e) {
    if (e.pointerType === 'touch') return; // Delegate to TouchEvent path
    activePointers.set(e.pointerId, { clientX: e.clientX, clientY: e.clientY });
    if (activePointers.size === 2) {
        e.preventDefault();
        pointerGestureActive = true;
        canvas.setPointerCapture(e.pointerId);
        startGesture([...activePointers.values()]);
    }
}

function _onPointerMove(e) {
    if (e.pointerType === 'touch') return;
    if (!pointerGestureActive) return;
    e.preventDefault();
    activePointers.set(e.pointerId, { clientX: e.clientX, clientY: e.clientY });
    if (activePointers.size >= 2) {
        const pointers = [...activePointers.values()].slice(0, 2);
        processGesture(pointers[0], pointers[1]);
    }
}

function _onPointerUp(e) {
    if (e.pointerType === 'touch') return;
    activePointers.delete(e.pointerId);
    if (activePointers.size < 2) {
        endGesture();
        pointerGestureActive = false;
        activePointers.clear();
    }
}

function _onPointerCancel(e) {
    _onPointerUp(e);
}
```

**Key design decisions:**
- `e.pointerType === 'touch'` guard ensures TouchEvent and PointerEvent paths don't overlap on touchscreens
- Trackpad pointers have `pointerType === 'mouse'` or `pointerType === 'pen'` — these go through the PointerEvent path
- `canvas.setPointerCapture()` ensures pointer events continue even if pointer leaves canvas bounds
- `activePointers.clear()` on gesture end prevents stale state

**File:** `Style.css`
**Changes:** Ensure `#previewCanvas` has `touch-action: none`:
```css
#previewCanvas {
    touch-action: none;
}
```

**File:** `MyComponents/MultiTouchHandlerTest.html`
**Changes:** Add PointerEvent-based tests:
```javascript
// Test: Two-pointer gesture activates
const p1 = new PointerEvent('pointerdown', { pointerId: 1, clientX: 100, clientY: 100, pointerType: 'mouse' });
const p2 = new PointerEvent('pointerdown', { pointerId: 2, clientX: 120, clientY: 100, pointerType: 'mouse' });
canvas.dispatchEvent(p1);
canvas.dispatchEvent(p2);
// Verify gesture started

// Test: Touch pointerType skips pointer handler
const touchP = new PointerEvent('pointerdown', { pointerId: 1, clientX: 100, clientY: 100, pointerType: 'touch' });
canvas.dispatchEvent(touchP);
// Verify pointer handler did NOT activate
```

**Success Criteria:**

##### Automated Verification:
- [ ] Two `pointerdown` events with `pointerType: 'mouse'` start a gesture
- [ ] `pointerType: 'touch'` is skipped by pointer handler (no activation)
- [ ] `pointerup` with < 2 pointers ends gesture
- [ ] `pointercancel` ends gesture and clears state
- [ ] `activePointers` map is empty after gesture ends
- [ ] Existing TouchEvent tests still pass (no regression)

##### Manual Verification:
- [ ] macOS trackpad two-finger pan moves image in selected panel
- [ ] macOS trackpad pinch-to-zoom zooms image in/out
- [ ] Touchscreen two-finger gestures still work (TouchEvent path unchanged)
- [ ] Single-finger interactions (click, select) are unaffected
- [ ] Page does not scroll during trackpad gestures on canvas

---

### Phase 4 Additions Test Plan

#### Unit Tests — PointerEvent Path

| # | Test | Input | Expected |
|---|------|-------|----------|
| 4A.1.1 | Two mouse pointers start gesture | `pointerdown` x2, `pointerType: 'touch'` | Gesture active, `activePointers.size === 2` |
| 4A.1.2 | Touch pointer skipped | `pointerdown`, `pointerType: 'touch'` | `activePointers.size === 0` |
| 4A.1.3 | Pointer move updates position | `pointermove` on active pointer | Midpoint/distance recomputed |
| 4A.1.4 | Single pointer up ends gesture | `pointerup` on one pointer | `pointerGestureActive === false`, map cleared |
| 4A.1.5 | Pointercancel ends gesture | `pointercancel` | Same as pointer up |
| 4A.1.6 | Three+ pointers uses first two | `pointerdown` x3 | Only first 2 used for gesture math |

#### Unit Tests — Pure Math Reuse

| # | Test | Input | Expected |
|---|------|-------|----------|
| 4A.2.1 | computeTouchMidpoint works with pointer objects | `{ clientX: 100, clientY: 100 }, { clientX: 200, clientY: 100 }` | `{ clientX: 150, clientY: 100 }` |
| 4A.2.2 | computeTouchDistance works with pointer objects | Same as above | `100` |
| 4A.2.3 | computePinchScale works | oldDist: 100, newDist: 150 | `1.5` |

#### E2E Tests — Trackpad Gestures

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 4A.3.1 | Two-finger trackpad pan | Select panel, two-finger drag | Image moves within panel |
| 4A.3.2 | Pinch-to-zoom on trackpad | Select panel, pinch gesture | Image zooms in/out |
| 4A.3.3 | Touchscreen still works | Select panel, two-finger touch drag | Image moves (TouchEvent path) |
| 4A.3.4 | Single finger unaffected | Single click on canvas | Panel selection works normally |
| 4A.3.5 | No page scroll | Two-finger drag on canvas | Page does not scroll |

#### Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | 4A.1.1, 4A.1.2, 4A.3.1, 4A.3.2 | Core PointerEvent gesture functionality |
| **P0** | 4A.3.3, 4A.3.4 | No regression in TouchEvent path |
| **P1** | 4A.1.3-4A.1.6 | Gesture lifecycle correctness |
| **P1** | 4A.2.1-4A.2.3 | Pure math reuse verification |
| **P2** | 4A.3.5 | Page scroll prevention |

#### Known Behaviors
- `pointerType === 'touch'` is the guard to prevent double-firing on hybrid devices
- `touch-action: none` on the canvas prevents browser default gestures (scroll, zoom)
- `setPointerCapture()` ensures pointer events continue if pointer leaves canvas
- Pure math functions (`computeTouchMidpoint`, etc.) work with any `{ clientX, clientY }` object
- Trackpad sensitivity may differ from touchscreens — thresholds may need tuning
- Safari's PointerEvent trackpad support has historically lagged Chrome/Firefox

---

## Phase 5 Additions: Complete Method Extraction

### Overview

Extract remaining closure functions from `createCollageMethods.js` into dedicated modules. This is optional per the skill reference guidance — if the team determines callback injection is sufficient, this phase can be deferred.

### Changes Required

#### 1. CR-FU-09: Method Extraction from createCollageMethods

**New file:** `MyESModules/App/createRenderMethods.js`
```javascript
/**
 * Render-related methods extracted from createCollageMethods.
 * Handles render scheduling, background/overlay state building,
 * and layout regeneration + render.
 */
export function createRenderMethods(base) {
    const layoutManager = () => base.getLayoutManager();
    const imageLibrary = () => base.getImageLibrary();
    const cropManager = () => base.getCropManager();
    const backgroundManager = () => base.getBackgroundManager();
    const overlayManager = () => base.getOverlayManager();
    const titleManager = () => base.getTitleManager();

    function _scheduleRender(vm) {
        // ... existing ~36 lines ...
    }

    function _buildBackgroundState(vm) {
        // ... existing ~9 lines ...
    }

    function _buildOverlayState(vm) {
        // ... existing ~6 lines ...
    }

    function _regenerateAndRender(vm) {
        // ... existing ~5 lines ...
    }

    return {
        _scheduleRender,
        _buildBackgroundState,
        _buildOverlayState,
        _regenerateAndRender
    };
}
```

**New file:** `MyESModules/App/createCropPreviewRenderer.js`
```javascript
/**
 * Crop preview rendering extracted from createCollageMethods.
 * Handles the ~104 line inline canvas rendering for crop previews:
 * DPR scaling, image contain math, dark overlay, border,
 * corner handles, and shaped overlay.
 */
export function createCropPreviewRenderer(base, domIds) {
    const cropManager = () => base.getCropManager();
    const imageLibrary = () => base.getImageLibrary();
    const layoutManager = () => base.getLayoutManager();

    function _scheduleCropPreviewRender(vm) {
        // ... existing ~104 lines ...
    }

    return { _scheduleCropPreviewRender };
}
```

**New file:** `MyESModules/App/createUndoMethods.js`
```javascript
/**
 * Undo/redo methods extracted from createCollageMethods.
 * Handles undo state management and undo/redo execution.
 */
export function createUndoMethods(base) {
    const undoManager = () => base.getUndoManager();

    function _updateUndoState(vm) {
        // ... existing ~4 lines ...
    }

    function _performUndo(vm) {
        // ... existing ~8 lines ...
    }

    function _performRedo(vm) {
        // ... existing ~8 lines ...
    }

    return {
        _updateUndoState,
        _performUndo,
        _performRedo
    };
}
```

**File:** `MyESModules/App/createCollageMethods.js`
**Changes:** Import and compose extracted methods:
```javascript
import { createRenderMethods } from './createRenderMethods.js';
import { createCropPreviewRenderer } from './createCropPreviewRenderer.js';
import { createUndoMethods } from './createUndoMethods.js';

export function createCollageMethods(base, domIds = {}) {
    const renderMethods = createRenderMethods(base);
    const cropPreviewMethods = createCropPreviewRenderer(base, domIds);
    const undoMethods = createUndoMethods(base);

    // Use extracted methods as callbacks for handler factories
    const layoutHandlers = createLayoutHandlers(
        () => base.getLayoutManager(),
        (vm) => renderMethods._scheduleRender(vm)
    );
    // ... other handlers ...

    return {
        ...renderMethods,
        ...cropPreviewMethods,
        ...undoMethods,
        // ... existing handler methods ...
    };
}
```

**File:** `MyESModules/index.js`
**Changes:** Add barrel exports for new modules if needed.

**Success Criteria:**

##### Automated Verification:
- [ ] `createRenderMethods` exports a function
- [ ] `createCropPreviewRenderer` exports a function
- [ ] `createUndoMethods` exports a function
- [ ] All methods are accessible on the Vue instance after composition
- [ ] `createCollageMethods.js` reduced from 558 lines to ~200 lines
- [ ] All existing unit tests pass without modification
- [ ] All existing E2E tests pass without modification

##### Manual Verification:
- [ ] App loads and renders correctly after extraction
- [ ] Export works identically
- [ ] Undo/redo works identically
- [ ] Crop preview renders correctly
- [ ] Layout switches work correctly
- [ ] No rendering regressions

---

### Phase 5 Additions Test Plan

#### Unit Tests — Module Exports

| # | Test | Input | Expected |
|---|------|-------|----------|
| 5A.1.1 | createRenderMethods is a function | `typeof createRenderMethods` | `'function'` |
| 5A.1.2 | createRenderMethods returns expected methods | `createRenderMethods(base)` | Object with `_scheduleRender`, `_buildBackgroundState`, `_buildOverlayState`, `_regenerateAndRender` |
| 5A.1.3 | createCropPreviewRenderer returns expected methods | `createCropPreviewRenderer(base, domIds)` | Object with `_scheduleCropPreviewRender` |
| 5A.1.4 | createUndoMethods returns expected methods | `createUndoMethods(base)` | Object with `_updateUndoState`, `_performUndo`, `_performRedo` |

#### Unit Tests — Composition

| # | Test | Input | Expected |
|---|------|-------|----------|
| 5A.2.1 | Methods spread into main object | `createCollageMethods(base, domIds)` | All extracted methods present |
| 5A.2.2 | Method names unchanged | Check method keys | Same names as before extraction |
| 5A.2.3 | Callbacks wired correctly | Handler factory receives callbacks | Callbacks reference extracted methods |

#### Integration Tests — Full Pipeline

| # | Test | Steps | Expected |
|---|------|-------|----------|
| 5A.3.1 | App loads with extracted modules | Start app, add images | App renders correctly |
| 5A.3.2 | Export works after extraction | Export collage | File downloads successfully |
| 5A.3.3 | Undo/redo works after extraction | Make changes, undo, redo | State reverses and restores |
| 5A.3.4 | Crop preview works after extraction | Select panel, adjust crop | Preview updates correctly |
| 5A.3.5 | Layout switch works after extraction | Switch layouts | Layout regenerates and renders |

#### Priority Ordering

| Priority | Tests | Rationale |
|----------|-------|-----------|
| **P0** | 5A.3.1-5A.3.5 | Full pipeline integration — refactoring must not break anything |
| **P0** | 5A.1.1-5A.1.4 | Module extraction correctness |
| **P0** | 5A.2.1-5A.2.3 | Method composition correctness |
| **P1** | Existing test suite | All pre-existing tests still pass |

#### Known Behaviors
- Method names must remain identical for Vue template bindings
- `_scheduleRender()` is RAF-debounced — callback pattern must preserve this
- Undo/redo uses command pattern with max 60 levels
- This is pure refactoring — behavior should be identical before and after

---

## Testing Strategy Summary

### Automated Testing
- **Unit tests:** Mocha/Chai browser-based tests in `MyComponents/`
- **E2E tests:** Playwright tests in `test/e2e/`
- **Canvas mocking:** Proxy-based Canvas 2D context mocking for unit tests

### Manual Testing
- **Trackpad gestures:** Requires macOS device with trackpad
- **Accessibility:** VoiceOver (macOS) or NVDA (Windows) for ARIA verification
- **Color pickers:** Native browser color picker behavior varies by OS
- **Toast notifications:** Verify positioning, auto-dismiss, and non-blocking behavior

### Test Infrastructure
- New tests follow existing patterns: HTML test files for unit tests, `.spec.js` for E2E
- PointerEvent tests use `new PointerEvent()` with `pointerType` property
- Toast tests mock `setTimeout` for deterministic auto-dismiss verification

---

## Performance Considerations

1. **PointerEvent handlers:** Use `{ passive: false }` only where `preventDefault()` is needed. All pointer handlers should be non-passive since we need to prevent browser defaults during gestures.

2. **Hex drag target rendering:** The dashed border highlight adds one extra draw call per frame during drag. This is negligible for the expected panel count (< 50 panels).

3. **Toast notifications:** Simple reactive state + CSS transitions — no animation loops or heavy DOM manipulation.

4. **Method extraction:** No performance impact — pure code organization change.

---

## Migration Notes

- **No data migration needed:** All changes are UI/architectural — no persistent data format changes
- **Backward compatibility:** All changes are additive or internal — no breaking changes to existing functionality
- **Rollback:** Each change is independent and can be rolled back individually via git
- **Phase dependency:** Changes integrate into existing phases — execute them alongside the base plan phases

---

## World Review Findings (2026-07-11)

**Reviewer:** world-review subagent (session `ses_0ac395555ffevuPXEYMRg4bKIw`)

### CR-FU-09: Method Extraction — Implemented ✅ (2026-07-11)

Method extraction from `createCollageMethods.js` completed:
- **New modules:** `createRenderMethods.js`, `createCropPreviewRenderer.js`, `createUndoMethods.js`
- **createCollageMethods.js** reduced from 576 to 392 lines
- All 1044 tests pass (no regressions)
- 26 new tests added for extracted modules

**World-review fixes applied:**
- 🔴 Critical: Moved `assembler()` call inside `scheduleRender` callback to guard against undefined assembler
- 🔴 Critical: Added optional chaining `vm.panels?.find()` in crop preview renderer
- 🟡 Medium: Added safe optional chaining `base?.getCropManager?.() || null` in crop preview renderer
- 🟡 Medium: RAF lifecycle concern noted — existing `_cropPreviewPending` flag and `beforeUnmount` cleanup mitigate the risk

### P1: Toast ARIA Role — Known Gap ⚠️

**Issue:** `index.html` toast template uses static `role="status" aria-live="polite"` for all toast types. Error toasts should use `role="alert"` (implicit `aria-live="assertive"`) for immediate screen reader announcement.

**Status:** This gap is already documented in:
- `.opencode/skills/building-web-apps/references/accessibility.md` — ARIA Live Regions section
- `_agent_docs/learnings/2026-07-10-toast-patterns-and-aria-live-regions.md` — ARIA Live Region Selection section
- `.opencode/skills/building-web-apps/SKILL.md` — Toast Notifications section (anti-pattern warning)

**Recommendation:** Future `build-code` session should update toast template to dynamically set role: `:role="toast.type === 'error' ? 'alert' : 'status'"`.

### P2: Export State Duplication — Design Choice, Not a Bug ℹ️

**Issue:** Both `exportStatus` (inline, near export button) and `toast.message` (bottom-center notification) convey export feedback.

**Resolution:** These serve different UX purposes:
- `exportStatus`: Proximity feedback — appears inline near the export button for immediate context
- `toast`: Broad notification — appears at bottom-center for users whose attention is elsewhere

The dual-feedback pattern is defensible and common in desktop applications. No action needed.

### Other Validations ✅

- **PointerEvent trackpad gestures** — Implementation validated as sound (three-input-path model, pointer type guard, unified gesture functions, setPointerCapture with fallback, global safety net)
- **`touch-action: none`** — Correctly applied to `#previewCanvas`
- **Memory management** — `beforeUnmount()` cleanup is comprehensive (toast timer, all handlers, renderer, image library, saliency analyzer)

---

## References

- Base implementation plan: `_agent_docs/plans/2026-07-07-change-requests-implementation-plan.md`
- Change request specs:
  - `_agent_docs/specifications/change-requests/2026-07--0-02-reorder-righthand-sidebar.md`
  - `_agent_docs/specifications/change-requests/2026-07-09-01-multi-finger-trackpad-gestures.md`
  - `_agent_docs/specifications/change-requests/2026-07-09-03-color-labels.md`
  - `_agent_docs/specifications/change-requests/2026-07-09-06-review-followups.md`
- World review analysis: Provided by world-review subagent (session ses_0b64f3035ffeVugdF6AmbSk83z)
- Planner analysis: Provided by planner subagent (session ses_0b64c856affeTfYWuBEAWRnWkY)
- Skill references:
  - `.opencode/skills/building-web-apps/SKILL.md` — Factory patterns, callback injection, method extraction guidance
  - `.opencode/skills/building-web-apps/references/interaction.md` — PointerEvent patterns, `touch-action: none`
  - `.opencode/skills/building-web-apps/references/canvas-2d.md` — Rendering pipeline, DPR scaling
  - `.opencode/skills/building-web-apps/references/accessibility.md` — ARIA patterns
  - `.opencode/skills/building-web-apps/references/testing-unit.md` — Mock patterns
