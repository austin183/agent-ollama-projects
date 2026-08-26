# Synthetic pointer events exercise the REAL capture + cleanup paths in E2E — `setPointerCapture` throws on a synthetic pointerId, and a non-fatal try/catch is what makes that testable

**Date:** 2026-08-25
**Context:** Metronomad CR 001 Phase 5, E2E-3.7 (W-1: `pointercancel` and window `blur` mid-drag must discard the draft, the iOS OS-gesture shape). The cleanup paths are exactly the ones you cannot trigger with Playwright's trusted mouse API — there is no `page.mouse.cancel()` and no "lose window focus mid-drag" primitive. The test instead dispatches synthetic `PointerEvent`s in-page, and it works *because of* a production design decision:

```js
// in-page, standalone program (define every helper locally):
const canvas = document.getElementById('waveformCanvas');
const rect = canvas.getBoundingClientRect();
canvas.dispatchEvent(new PointerEvent('pointerdown', {
  clientX: rect.left + rect.width * 0.5, clientY: rect.top + rect.height / 2,
  pointerId: 1, bubbles: true, cancelable: true
}));
// …assert the draft is live on the readout…
canvas.dispatchEvent(new PointerEvent('pointercancel', { pointerId: 1, bubbles: true, cancelable: true }));
// …assert discard; a subsequent TRUSTED page.mouse.click commits normally…
// window-blur variant: window.dispatchEvent(new Event('blur'))
```

Why this drives the real paths:

1. **The synthetic pointer is not an *active* pointer** — `setPointerCapture(1)` in the production `pointerdown` handler throws `NotFoundError`. The production handler wraps capture in try/catch (W-1: Safari stale-pointerId hygiene), so the throw is non-fatal and the drag state machine proceeds exactly as it would with a real pointer.
2. **`pointercancel` / `window 'blur'` are ordinary events** — the production listeners fire identically for dispatched events; `_endDrag(false)` runs the exact discard path (capture release in its own try/catch, `onScrubEnd(false)`, no focus return).
3. **The follow-up trusted click proves no stuck state** — if the synthetic sequence had stranded `_dragPointerId`, the real click's `pointerdown` would hit the one-drag-at-a-time guard and the commit would silently no-op; the test's final `0:01.5` assertion fails. The trusted click is the canary.

## Rules

1. **When a production pointer path wraps `setPointerCapture` in a non-fatal try/catch, synthetic `PointerEvent`s are a first-class E2E driver for its cancel/cleanup branches** — dispatch `pointerdown` (any `pointerId`; the capture throw is absorbed), then `pointercancel` on the same target or `window.dispatchEvent(new Event('blur'))`, and assert the discard. No OS gesture, no trusted-event limitation, no global patching.
2. **Keep the canary:** after exercising a cleanup path with synthetic events, perform the equivalent operation with a *trusted* Playwright input (`page.mouse.click`) and assert it works. That one assertion is what converts "the synthetic path ran" into "no state was stranded".
3. **If the production code does NOT wrap capture (no try/catch), this technique inverts into a trap** — the synthetic `pointerdown` throws inside the listener and the drag never starts. In that case the missing try/catch is itself a finding (stale/invalid pointerIds are a documented browser reality — Safari), not a test problem.
4. **Draft-state assertions target the draft's own display surface.** In Metronomad the draft rides the readout (`displayPosition`) and the in-canvas marker; the offset *text field* mirrors the committed value only (pinned by WF-I2.3/2.4). Asserting draft-liveness on the committed surface times out at 5 s and looks like a broken handler.

## Skill mapping (landed 2026-08-25)

- [x] `building-web-apps` → `references/testing-e2e.md`, new "Synthetic Pointer Events Drive Cancel/Cleanup Branches" subsection under "PointerEvent Testing" (pattern + trusted-input canary rule + missing-try/catch-is-a-finding); summarized in `SKILL.md` gotchas.
