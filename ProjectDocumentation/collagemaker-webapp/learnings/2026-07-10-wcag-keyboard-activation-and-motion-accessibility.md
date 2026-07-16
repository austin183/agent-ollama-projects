# WCAG Keyboard Activation and Motion Accessibility for Custom Controls

**Date:** 2026-07-10
**Session:** 63 (Phase 2 Follow-Up: Descriptive Color Labels + Export Progress)

## Summary

Implemented descriptive color labels and export progress indicators. Key learnings around Vue ref reliability with native form inputs, loading state accessibility, and respecting user motion preferences. Also documented WCAG keyboard activation requirements for custom button roles (learned during initial approach before pivoting to simpler solution).

---

## Vue Refs on Native Form Inputs Are Unreliable for Programmatic Clicks

When trying to programmatically trigger a `<input type="color">` from a sibling element using Vue refs, the ref may not expose `.click()` reliably.

### The Problem

```html
<!-- This does NOT work in Vue 3 Options API -->
<input type="color" id="myPicker" ref="myPicker">
<span @click="$refs.myPicker.click()">Click me</span>
```

In Vue 3, `$refs` on native DOM elements should give you the raw element. However, in practice with `<input type="color">`, the ref can resolve to `undefined` or a Vue internal wrapper that doesn't expose `.click()`. This was observed as:

```
Uncaught TypeError: $refs.myPicker?.click is not a function
```

### Root Cause

The exact behavior varies by browser and Vue version. Some browsers restrict programmatic clicking of `<input type="color">` for security reasons (it should only be triggered by user gesture). Vue's ref system may also interfere with the native element's method exposure.

### Solutions (Best to Worst)

**1. Descriptive labels instead of duplicate click targets (BEST)**

The `<input type="color">` is already a fully accessible, clickable control. Instead of adding a second clickable target, add descriptive text:

```html
<input type="color" id="myPicker" v-model="colorValue">
<span class="color-label">Changes color behind panels</span>
```

This is simpler, more accessible, and avoids the technical headache entirely.

**2. Use `document.getElementById()` (WORKS BUT FRAGILE)**

```html
<span @click="document.getElementById('myPicker').click()">Click me</span>
```

This bypasses Vue refs entirely and calls `.click()` on the raw DOM element. **However**, some browsers still block programmatic clicks on `<input type="color">` if not triggered by a direct user gesture on the input itself.

**3. Use a Vue method (CLEANER BUT STILL MAY FAIL)**

```javascript
methods: {
    openColorPicker() {
        this.$refs.myPicker?.click()
    }
}
```

Same reliability issues as template-level ref access.

### Key Takeaway

**Don't add duplicate interactive targets for `<input type="color">`.** The native color picker is already accessible and clickable. If users need more context, add descriptive text labels instead of clickable swatches. This avoids:
- Vue ref reliability issues
- Browser security restrictions on programmatic color picker activation
- Accessibility complexity with custom button roles
- Maintenance burden of keeping two interactive elements in sync

### File Reference

- `index.html` — Color picker rows with descriptive labels instead of clickable swatches

---

## WCAG 2.1 SC 2.1.1: Custom Buttons Must Handle Enter AND Space

When a non-interactive element (like `<span>`) is given `role="button"` and `tabindex="0"`, it becomes a custom button. Per [WAI-ARIA Authoring Practices 1.2](https://www.w3.org/WAI/ARIA/apg/patterns/button/), custom buttons MUST activate on **both** Enter and Space keys.

### The Problem

A common mistake is adding only `@keydown.enter` for activation:

```html
<!-- WRONG — only Enter works, Space does nothing -->
<span role="button" tabindex="0" @keydown.enter="doSomething">
    Click me
</span>
```

Keyboard-only users who rely on Space to activate controls (a common muscle memory from native `<button>` elements) will be unable to interact with the control.

### The Fix

```html
<span role="button"
      tabindex="0"
      @click="doSomething"
      @keydown.enter="doSomething"
      @keydown.space.prevent="doSomething">
    Click me
</span>
```

**Key points:**
- **`@keydown.space.prevent`** — Space key on a focused element triggers default browser scroll behavior. `.prevent` stops the page from scrolling when the user presses Space on a custom button.
- **Always pair Enter and Space** — if you handle one, handle the other.
- **`@click` covers mouse users** — no need for separate `@mousedown` or `@mouseup`.

### Native `<button>` Elements

Native `<button>` elements already handle Enter and Space. They do NOT need `@keydown` handlers. Use `<button>` whenever possible and reserve `role="button"` for cases where a `<button>` would break layout or semantics.

### File Reference

- `index.html` — Color swatch spans with `@keydown.enter` and `@keydown.space.prevent`

---

## `aria-busy` for Loading State Buttons

When a button triggers an async operation (like export), screen readers benefit from explicit loading state feedback.

### Pattern

```html
<button :aria-busy="isExporting" :disabled="isExporting">
    <span v-if="isExporting" class="spinner" aria-hidden="true">...</span>
    {{ isExporting ? 'Exporting...' : 'Export' }}
</button>
```

**Key points:**
- **`:aria-busy="isExporting"`** — Screen readers announce "busy" when the button is in loading state
- **`:disabled="isExporting"`** — Prevents double-clicks and native focus behavior during loading
- **`aria-hidden="true"` on spinner** — Decorative animated icons should be hidden from screen readers; the button text and `aria-busy` provide the loading context

### Without `aria-busy`

Without `aria-busy`, a screen reader user who triggers the export and then tabs back to the button would hear "Export JPEG, button, disabled" — they'd know it's disabled but not that work is in progress. With `aria-busy`, they hear "Exporting, button, busy" — explicit loading state.

### File Reference

- `index.html` — Export button with `:aria-busy="isExporting"`

---

## `prefers-reduced-motion` for CSS Animations

Continuous CSS animations (like a spinning loader) can cause discomfort for users with vestibular disorders. The `prefers-reduced-motion` media query lets users opt out of motion effects.

### Pattern

```css
.export-spinner {
    animation: export-spin 1s linear infinite;
}

@media (prefers-reduced-motion: reduce) {
    .export-spinner {
        animation: none;
    }
}
```

**Key points:**
- **`prefers-reduced-motion: reduce`** — Set by users in OS/browser settings
- **`animation: none`** — Completely disables the animation; the icon remains static (still visible as a visual indicator)
- **Consider alternative feedback** — For critical loading indicators, pair the animation with text ("Exporting...") so the loading state is communicated even when motion is disabled
- **Not just spinners** — Any continuous animation (pulsing, sliding, color transitions) should respect this preference

### WCAG Reference

This addresses [WCAG 2.1 SC 2.3.3 (Animation from Interactions)](https://www.w3.org/WAI/WCAG21/Understanding/animation-from-interactions.html) — Level AAA. While Level AA compliance doesn't strictly require it, it's a low-effort high-impact accessibility improvement.

### File Reference

- `Style.css` — `.export-spinner` with `@media (prefers-reduced-motion: reduce)` override

---

## Testing Custom Button Keyboard Activation

When testing custom button keyboard behavior, use `KeyboardEvent` with the correct `key` property:

```javascript
// Enter key
const enterEvent = new KeyboardEvent('keydown', { key: 'Enter', bubbles: true });
element.dispatchEvent(enterEvent);

// Space key — note: key is ' ' (space character), not 'Space'
const spaceEvent = new KeyboardEvent('keydown', { key: ' ', bubbles: true });
element.dispatchEvent(spaceEvent);
```

**Gotcha:** The `key` property for Space is `' '` (a space character), not `'Space'`. Some older browsers may use `'Spacebar'`. Test for both if supporting legacy browsers.

### File Reference

- `MyComponents/Phase2FollowUpTest.html` — Tests 2A.1.4 (Space) and 2A.1.5 (Enter)
