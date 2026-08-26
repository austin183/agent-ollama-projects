# Phase 3 — N-1: Clear the scheduler interval at the PLAYING flip

**Source:** review N-1 · `playbackEngine.js` — the 25 ms scheduler interval is never cleared at the PLAYING flip; a 30-min song runs ~72,000 no-op ticks.

## Change

In `_schedulerTick`, when the clock crosses `_seq.songStart.time` (the flip branch that calls `_setState(PLAYING)`), also clear the scheduler interval (`_clearInterval(_schedulerId); _schedulerId = null`). All clicks are strictly before `songStart.time`, so nothing is left to schedule. The watch interval (D10) keeps running through playback.

## Scenarios (inline; canonical in `behavior-specs.md` §7)

- **R-N1.1** — countingIn with all clicks scheduled; advance clock past songStart + one tick → state `playing`; `timers.count() === 1` (watch only); `tickScheduler()` returns 0 (no scheduler interval); further ticks create no sources and emit nothing.

## Success criteria

- [ ] R-N1.1 written RED first (fake-timer count assertion), then green.
- [ ] Existing P-01/P-02/P-04/P-05/P-07/P-08/P-10/P-11/P-14 still green (they tick the scheduler before the flip or after stop).
- [ ] `node scripts/run-tests.cjs` + `npx playwright test` green at the item commit.

Status: ✅ done (2026-08-22)
