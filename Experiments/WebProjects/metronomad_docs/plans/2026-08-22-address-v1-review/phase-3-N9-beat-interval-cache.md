# Phase 3 — N-9: Cache --beat-interval (per-frame style churn)

**Source:** review N-9 · `createBeatDots.js` — `--beat-interval` is re-`setProperty`'d every frame with a constant value, dirtying style at ~60 fps.

## Change

In `createBeatDots._render`, track `_lastBeatInterval`; call `setProperty('--beat-interval', …)` only when `grid.interval !== _lastBeatInterval`. Reset `_lastBeatInterval = null` in `_clearDots` (shared by `stopVisualClock`/`stopAll`) so a new sequence — possibly at a new tempo — always re-applies.

## Scenarios (inline; canonical in `behavior-specs.md` §7)

- **R-N9.1** — N flushed frames at a constant interval → `setProperty` called exactly once for that value; a grid with a new interval → the next set; after `stopVisualClock`, a new clock run sets it again (cache reset).

Test note: the suite uses real DOM elements (`#beatDots` row) — wrap `rowEl.style.setProperty` per test (save/restore, local) to count calls.

## Success criteria

- [ ] R-N9.1 RED first, then green.
- [ ] Existing B-suite green (the `--beat-interval` value assertions in B-01/B-02 still hold).
- [ ] Both suites green at the item commit.

Status: ✅ done (2026-08-22)
