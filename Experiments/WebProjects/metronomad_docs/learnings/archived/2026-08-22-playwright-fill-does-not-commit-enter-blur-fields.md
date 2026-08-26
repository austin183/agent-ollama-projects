# Playwright `fill()` does not commit Enter/blur form fields

**Date:** 2026-08-22
**Context:** Metronomad Phase 1 (C-1) — BPM and count-in inputs were changed from a per-keystroke `@input` clamp to **commit-on-Enter/blur** (`v-model` draft + `@keyup.enter` / `@blur`). Six existing E2E tests that set count-in via `fill()` went silent-wrong until the helper was fixed.

## The gotcha

`page.fill(selector, value)` focuses the element, sets the value, and fires a single `input` event. It does **not** fire `blur`, and it does **not** fire `keyup.enter`. For a field whose model updates only on Enter/blur (the commit-on-commit pattern), `fill()` updates the **draft** but never commits the **model**:

```js
await page.fill('#countInInput', '2');   // draft text = "2", but countInBeats is still 4
// ... the test then runs the sequence with count-in 4, not 2 — silently wrong parameters
```

The failure is **silent**: no error, the field visibly shows the right text, but the underlying model — and therefore the behavior under test — uses the stale value. The wrongness shows up later as a timing/state assertion failing at a confusing spot, not at the `fill`.

## Rule

For any field that commits on Enter/blur (rather than on `input`), an E2E test that sets it via `fill()` must perform the commit the user would:

```js
await page.fill('#countInInput', String(value));
await page.keyboard.press('Enter');      // fires @keyup.enter → commit
```

(A genuine `blur` — e.g. focusing another element — also commits, but relying on incidental blur is fragile: it depends on focus order and what the test touches next. Press Enter explicitly.)

## Generalization

Treat `fill()` as a **draft** setter, not a **commit**. Whenever the app's contract is "the value is not applied until the user commits," the E2E must reproduce that commit (Enter, blur, or the field's submit action). This is why the phase's `setCountIn` helper gained a `press('Enter')`, and why E2E-2.3's BPM cases each gained a `press('Enter')` after `fill`.

## Check when you change an input's contract

If you convert a field from `@input`-driven to commit-on-Enter/blur (or vice-versa), grep the E2E specs for `fill('<that-id>')` and add/remove the explicit commit at each site. The offset field already committed via Enter, so its tests already pressed Enter — only the newly-converted fields needed the addition.
