# Phase 3 — N-15: Drop the redundant scrubber :tabindex

**Source:** review N-15 · `index.html:75-77` — `:tabindex="isReady ? 0 : -1"` on `#offsetScrubber` duplicates `:disabled="!isReady"` (a disabled control is already out of the tab order).

## Change

Template-only: delete the `:tabindex` binding from `#offsetScrubber`.

## Scenarios

**No new row** — behavior is identical in both states (ready: focusable via native tabindex 0; not-ready: disabled ⇒ not focusable). Pinned by the existing keyboard E2E (scrubber reachable when enabled) and the parameter-lock E2E (disabled while running).

## Success criteria

- [ ] `npx playwright test` fully green at the item commit (keyboard.spec.cjs + playback E2E-1.6).

Status: ✅ done (2026-08-22)
