# Bottom Sheet Content Duplication and ARIA Tab Pattern Completeness

**Date:** 2026-07-25
**Session:** 2026-07-25-002 (Phase 1: Core Bottom Sheet — TDD implementation)

## Summary

Implemented the mobile bottom sheet Phase 1 via TDD. World-review revealed that the ARIA tab pattern requires explicit `id`/`aria-controls`/`aria-labelledby` wiring between tabs and panels — not just `role="tab"` and `aria-selected`. Also learned that when duplicating sidebar content into a bottom sheet, all `id` attributes must be prefixed to avoid duplicate ID violations in the DOM.

---

## 1. ARIA Tab Pattern: `id` + `aria-controls` + `aria-labelledby` Wiring

The WAI-ARIA tabs pattern requires three relationships that are easy to miss when implementing the visual pattern:

### What's Often Done (Incomplete)

```html
<!-- Has role="tab" and aria-selected but missing id/aria-controls -->
<button role="tab" :aria-selected="active === 'images'" @click="setTab('images')">
    Images
</button>
<div role="tabpanel" v-show="active === 'images'">
    <!-- Content -->
</div>
```

This works visually and screen readers will announce `aria-selected`, but the **programmatic relationship** between tabs and their panels is missing. Assistive technologies that rely on `aria-controls` to navigate between a tab and its panel (e.g., VoiceOver's rotor, JAWS tab list navigation) will not function correctly.

### What's Required (Complete)

```html
<!-- Each tab needs: id, aria-controls pointing to panel -->
<button id="bs-tab-images" role="tab"
        :aria-selected="activeBottomSheetTab === 'images'"
        aria-controls="bs-panel-images"
        @click="setBottomSheetTab('images')">
    Images
</button>

<!-- Each panel needs: id matching aria-controls, aria-labelledby pointing to tab -->
<div id="bs-panel-images" role="tabpanel"
     aria-labelledby="bs-tab-images"
     v-show="activeBottomSheetTab === 'images'">
    <!-- Content -->
</div>
```

### Why Both `aria-controls` AND `aria-labelledby`?

- **`aria-controls`** (on the tab): Tells assistive tech "this tab controls this panel". Enables tab-to-panel navigation.
- **`aria-labelledby`** (on the panel): Tells assistive tech "this panel's label comes from this tab". When focus enters the panel, the tab label is announced as context.

### File References

- `index.html` — Bottom sheet tab bar and panels with complete ARIA wiring
- `.opencode/skills/building-web-apps/references/accessibility.md` — General ARIA guidance (this pattern extends it for tab panels)

---

## 2. Focus Return on Dialog Close

When a modal dialog (`role="dialog" aria-modal="true"`) closes, focus MUST return to the element that opened it. This is a WCAG 2.1 Level A requirement (2.4.3 Focus Order). Without it, keyboard users lose their place and don't know where they are after the dialog closes.

### Pattern

```javascript
closeSidebars() {
    const wasBottomSheetOpen = this.bottomSheetOpen;
    this.leftSidebarMobileOpen = false;
    this.rightSidebarMobileOpen = false;
    this.bottomSheetOpen = false;
    // Return focus to the element that opened the dialog
    if (wasBottomSheetOpen) {
        const btn = document.getElementById('bottomSheetToggleBtn');
        if (btn) btn.focus();
    }
}
```

### Key Details

- **Capture state before mutation** — `wasBottomSheetOpen` is read before setting `bottomSheetOpen = false`, because the method is called for all overlay dismissal paths (backdrop tap, Escape key).
- **Defensive DOM lookup** — `getElementById()` may return `null` if the element is hidden by CSS (`display: none`) at the time of lookup. Guard with `if (btn)`.
- **Only for bottom sheet** — The hamburger button is the opener for the bottom sheet. Sidebar overlays use different openers. Only return focus when the bottom sheet was the thing that closed.

---

## 3. Visual Drag Handle for Bottom Sheet Discoverability

A bottom sheet that slides up from the bottom has no obvious "close" affordance for touch users. The backdrop tap and Escape key are invisible dismiss methods. A visual drag handle (grab bar) signals that the sheet can be dismissed.

### Pattern

```html
<div class="bottom-sheet-handle" aria-hidden="true">
    <span class="bottom-sheet-handle-bar"></span>
</div>
```

```css
.bottom-sheet-handle {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 8px 0 4px;
    flex-shrink: 0;
}

.bottom-sheet-handle-bar {
    width: 32px;
    height: 4px;
    background-color: var(--color-surface-variant);
    border-radius: 2px;
}
```

### Key Details

- **`aria-hidden="true"`** — The handle is purely decorative. Screen readers should not announce it as an interactive element.
- **`flex-shrink: 0`** — Prevents the handle from being compressed when the content area grows.
- **Positioned above the tab bar** — The handle is the first visual element users see when the sheet opens, establishing the "this is a dismissible panel" mental model.

---

## 4. Content Duplication with ID Prefixing

When duplicating sidebar content into a bottom sheet (Phase 1 approach, deduplicated in Phase 3), every `id` attribute must be unique in the DOM. Duplicate IDs cause:
- `document.getElementById()` returning the wrong element
- ARIA `for`/`aria-labelledby`/`aria-describedby` associations breaking
- HTML validation failures

### Pattern

Prefix all bottom sheet IDs with `bs`:

| Sidebar ID | Bottom Sheet ID |
|---|---|
| `layoutStyleSelect` | `bsLayoutStyleSelect` |
| `gutterSlider` | `bsGutterSlider` |
| `cropPreviewCanvas` | `bsCropPreviewCanvas` |
| `bgColorPicker` | `bsBgColorPicker` |
| `exportBtn` | `bsExportBtn` |

### Key Details

- **Consistent prefix** — Using `bs` (bottom sheet) across all duplicated elements makes the pattern easy to audit.
- **`for` attributes must match** — When a `<label for="bsBgColorPicker">` references an `<input id="bsBgColorPicker">`, both must use the prefixed ID.
- **`v-for` keys** — Use a distinct key prefix in `v-for` loops (e.g., `:key="'bs-img-' + image.id"`) to avoid Vue key conflicts between sidebar and bottom sheet lists.

---

## 5. Auto-Switch Tab on Content Change

When the bottom sheet is open on a non-"Images" tab and the user adds new images, the new images are invisible until the user manually switches to the Images tab. Auto-switching to the Images tab after adding images provides immediate feedback.

### Pattern

```javascript
// In createCollageMethods.js
async handleFileInputChange() {
    await fileHandlers.handleFileInputChange.call(this);
    if (this.bottomSheetOpen) {
        this.activeBottomSheetTab = 'images';
    }
}

// In createCollageLifecycle.js — drag-drop path
this._regenerateAndRender();
if (this.bottomSheetOpen) {
    this.activeBottomSheetTab = 'images';
}
```

### Key Details

- **Both paths must be covered** — File picker (`handleFileInputChange`) and drag-drop (lifecycle `setupGlobalDrop`) are independent code paths. Both need the tab switch.
- **Only when bottom sheet is open** — The tab switch is a no-op when the bottom sheet is closed, but guarding with `if (this.bottomSheetOpen)` makes the intent explicit and avoids unnecessary reactive updates.

---

## 6. CSS `dvh` Units for Bottom Sheet Height

Dynamic viewport height (`dvh`) units are essential for mobile bottom sheets because iOS Safari's address bar changes the available viewport height. Using `vh` causes the bottom sheet to be clipped or extend below the visible area.

### Pattern

```css
.bottom-sheet {
    max-height: 70dvh;  /* Portrait */
}

@media (max-width: 699px) and (orientation: landscape) {
    .bottom-sheet {
        max-height: 50dvh;  /* Landscape */
    }
}
```

### Key Details

- **`viewport-fit=cover` required** — The viewport meta tag must include `viewport-fit=cover` for `dvh` to work correctly on iOS.
- **`env(safe-area-inset-bottom)` for padding** — The bottom sheet should also use `padding-bottom: env(safe-area-inset-bottom, 0px)` to avoid content being obscured by the iOS home indicator.
- **Landscape reduction** — In landscape orientation, the available vertical space is much less. Reducing from `70dvh` to `50dvh` prevents the bottom sheet from covering the entire canvas.

### File References

- `Style.css` — Bottom sheet CSS with `dvh` units and safe area padding
- `index.html` — Viewport meta tag with `viewport-fit=cover`
