# Phase 3 — N-25: Assert the resume timeout against the constant

**Source:** review N-25 · `UiHandlersTest.html` — the one real-timer test hardcodes `greaterThan(700)`; it drifts silently if `RESUME_TIMEOUT_MS` changes.

## Change

In `UiHandlersTest.html`, import `SCHEDULER` from `../MyESModules/Playback/playbackEngine.js` and assert `expect(Date.now() - t0).to.be.greaterThan(SCHEDULER.RESUME_TIMEOUT_MS - 50);` (−50 ms keeps the real-timer test flake-safe while pinning the constant).

## Scenarios (inline; canonical in `behavior-specs.md` §7)

- **R-N25.1** — the bound is the imported constant, not a magic 700.

## Success criteria

- [ ] Test green at the item commit (no production change).

Status: ✅ done (2026-08-22)
