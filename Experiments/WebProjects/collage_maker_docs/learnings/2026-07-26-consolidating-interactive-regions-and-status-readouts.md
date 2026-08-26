# Consolidating Duplicate Interactive Regions and Reactive Status Readouts

**Date:** 2026-07-26
**Session:** 2026-07-26-008 (Mobile Bottom Sheet Adjustments Phase 1)

## Summary

Removed the mobile bottom sheet crop preview canvas (`bsCropPreviewCanvas`) because its 12px corner handles fell below WCAG 2.5.8 minimum touch targets (44x44px) on a constrained bottom sheet (70dvh). This change had an unexpected accessibility benefit: eliminating a duplicate `role="application"` interactive region. Replaced the canvas with a reactive numeric readout using `role="status" aria-live="polite"` for screen reader announcements.

---

## 1. Duplicate `role="application"` Regions Confuse Screen Readers

When two separate regions on a page both use `role="application"` for the same interaction (e.g., crop editing on both a desktop sidebar canvas and a mobile bottom sheet canvas), screen reader users encounter:

- **Duplicate focus targets** — the same action is available in two places, creating confusion about which is "the real" one
- **Ambiguous navigation paths** — tab order may jump between two application regions serving the same purpose
- **Context switching overhead** — users must determine which region is active/visible

### Pattern: Consolidate to Single Source of Truth

When an interaction is available in multiple UI locations, designate one as the primary interactive region. Other locations should be read-only or removed entirely.

**Before (two application regions):**
```html
<!-- Main canvas — primary crop interaction -->
<canvas id="previewCanvas" role="application" aria-label="Canvas"></canvas>

<!-- Desktop sidebar — crop preview with handles -->
<canvas id="cropPreviewCanvas" class="crop-preview-canvas"
        role="application" aria-label="Crop editor — drag handles to adjust crop region"></canvas>

<!-- Mobile bottom sheet — crop preview with handles -->
<canvas id="bsCropPreviewCanvas" class="crop-preview-canvas"
        role="application" aria-label="Crop editor — drag handles to adjust crop region"></canvas>
```

**After (one application region + read-only readout):**
```html
<!-- Main canvas — primary crop interaction (unchanged) -->
<canvas id="previewCanvas" role="application" aria-label="Canvas"></canvas>

<!-- Desktop sidebar — crop preview with handles (unchanged) -->
<canvas id="cropPreviewCanvas" class="crop-preview-canvas"
        role="application" aria-label="Crop editor — drag handles to adjust crop region"></canvas>

<!-- Mobile bottom sheet — read-only crop info (no role="application") -->
<div class="detail-section" aria-label="Crop settings">
    <div class="crop-info" role="status" aria-live="polite">
        <span class="crop-info-item">X: 120</span>
        <span class="crop-info-item">Y: 340</span>
        <span class="crop-info-item">W: 800</span>
        <span class="crop-info-item">H: 600</span>
    </div>
    <button class="pure-button reset-crop-btn">Reset Crop</button>
</div>
```

### Decision Framework

| Factor | Keep as `role="application"` | Demote to read-only |
|--------|------------------------------|---------------------|
| Touch targets meet 44x44px minimum | Yes | No |
| Spatial context is sufficient for interaction | Yes | No |
| User can perform the action meaningfully in this location | Yes | No |
| Main canvas provides adequate feedback | N/A | Prefer demote |

---

## 2. `role="status" aria-live="polite"` for Reactive Numeric Readouts

When replacing an interactive canvas with a numeric readout (X, Y, W, H, dimensions, etc.), use `role="status" aria-live="polite"` on the container so screen readers announce value changes automatically.

### Why `role="status"` over `aria-live` alone?

- `role="status"` implicitly sets `aria-live="polite"` and `aria-atomic="true"`
- `aria-atomic="true"` ensures the entire readout is announced as a unit (not individual numbers)
- Screen readers treat `role="status"` as a live region by default — no additional attributes needed

### Why `aria-live="polite"` over `assertive`?

- Crop readout values update frequently during drag gestures
- `polite` waits for the user to pause before announcing — `assertive` would interrupt
- Crop coordinates are supplementary information, not critical alerts

### Pattern

```html
<div class="detail-section" aria-label="Crop settings">
    <div class="crop-info" role="status" aria-live="polite">
        <span class="crop-info-item">X: {{ Math.round(selectedCropInfo.sourceRect.x) }}</span>
        <span class="crop-info-item">Y: {{ Math.round(selectedCropInfo.sourceRect.y) }}</span>
        <span class="crop-info-item">W: {{ Math.round(selectedCropInfo.sourceRect.width) }}</span>
        <span class="crop-info-item">H: {{ Math.round(selectedCropInfo.sourceRect.height) }}</span>
    </div>
</div>
```

Vue reactivity automatically updates the text content, and `aria-live="polite"` ensures screen readers announce the changes.

---

## File References

- `index.html` — crop section in `#bs-panel-edit` (mobile bottom sheet Edit tab)
- `MyESModules/App/createCropPreviewRenderer.js` — renderer guard for extensibility (line 183)
- `MyESModules/Interaction/CropInteraction.js` — single canvas ID normalization (line 24)
