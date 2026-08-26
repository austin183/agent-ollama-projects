# The 5 ms in-page logger is a LOSSY sampler — drain it only after it recorded the terminal tick, and never pin exact intermediate ticks

**Date:** 2026-08-25
**Context:** Metronomad CR 001 Phase 5, E2E-3.6 (drag scrubs continuously; the 5 ms in-page readout logger samples the draft tracking during the drag). Two distinct failures, one per run, both in the logger's *bookkeeping* — not the app:

1. **Drain race (isolated run):** the last recorded sample was `0:01.5`, not the committed `0:01.8`. The test did `mouse.up()` → `toHaveText('0:01.8 …')` (DOM check, passed) → `clearInterval` + read the log. But `toHaveText` passes the instant the DOM changes — the logger's *next 5 ms tick* had not necessarily run yet. The final tick was never recorded.
2. **Load coalescing (full-suite run):** the *first* recorded sample was `0:00.9`, not the press point's `0:00.6`. Under full-suite load, the pointerdown draft (0.6) and the first `mouse.move` (0.9) landed inside one 5 ms window; the sampler saw only the later value. The pin `positions[0] toBeCloseTo(0.6, 1)` failed.

## Rules

1. **When a test drains an in-page interval logger, wait for the LOGGER to record the terminal state — not for the DOM to show it.** The DOM assertion and the log tail are two different observers of the same change, and the DOM leads:

   ```js
   await expect(page.locator('.progress-readout')).toHaveText('0:01.8 / 0:03.0'); // DOM leads
   await page.waitForFunction(() => {            // …the logger trails by up to one tick
     const log = window.__readoutLog;
     return log.length > 0 && log[log.length - 1] === '0:01.8 / 0:03.0';
   });
   const log = await page.evaluate(() => { clearInterval(window.__roIv); return window.__readoutLog; });
   ```

   After that wait, the last log element is *exactly* the terminal value — assertable with `toBeCloseTo`/`toEqual`.
2. **Intermediate ticks of a continuous signal are coalescing-prone — assert the range and the endpoints, not the exact intermediate values.** What is pinned by the behavior contract is "samples advance" (monotonic) + the start/end positions; which discrete ticks the 5 ms window happened to sample is an artifact of machine load. Concretely: `positions.length ≥ 3`, strictly increasing, `positions[0] ≥ 0.6 && < 1.8` (started at the press side, never jumped to the release), `positions[last] ≈ 1.8` (safe after rule 1).
3. **Discrete CDP actions are NOT a sampling guarantee.** Each `page.mouse.move` is its own round-trip, but several can land in one 5 ms window under load; do not count on "N moves → N samples".

## Why it matters

Both failure modes look like app bugs (a "stuck draft" at 1.5; a scrub that "started late") and send you debugging production code that is correct. The Phase-4 sibling learning (in-page-poll-loggers-cannot-order-sub-period-events) covers *choosing* the capture mechanism (poll vs MutationObserver); this one covers *using a poll correctly once it's the right tool* — drain discipline and tolerance shape.

## Skill mapping (landed 2026-08-25)

- [x] `building-web-apps` → `references/testing-e2e.md`, "Sub-second timing assertions": (1) drain-after-log-tail pattern added, (2) "endpoints exact, intermediates range" tolerance rule for continuous-signal assertions added; both summarized in `SKILL.md` gotchas.
