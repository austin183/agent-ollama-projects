# Phase 3 — N-26: E2E-1.3 — assert against the grid-law flip, not 450 ms

**Source:** review N-26 — `playback.spec.cjs` E2E-1.3 asserts `actionT < 450`, a self-imposed bound over the 250 ms in-page timeout. Under saturated CI the timeout can slip past 450 ms while the stop is still a valid count-in stop (the window ends at the grid-law flip, t0+1500).

## Change

Replace the bound with the **grid-law flip time**: `const flipAt = (2 + 1) * 500;` (count-in 2 @ 120 BPM) and `expect(actionT).toBeLessThan(flipAt)`.

Scoping note: the review's phrasing "assert `actionT < playing.t`" cannot be taken literally in E2E-1.3 — a successful count-in stop never reaches `playing`, so no `playing` timeline entry exists. The grid-law flip time is the exact proxy for "before the song would have started." Recorded in `behavior-specs.md` §7 (R-N26.1).

## Scenarios

- **R-N26.1** — as above.

## Success criteria

- [ ] E2E-1.3 green at the item commit.

Status: ✅ done (2026-08-22)
