# Phase 3 — N-4: startSequence returns a frozen copy view, not the live _seq

**Source:** review N-4 · `playbackEngine.js:258-259` — `startSequence` returns the live mutable `_seq` (incl. the `scheduled` flags the scheduler trusts). The app ignores it; only tests read it.

## Change

Return a **frozen snapshot** in the same shape (tests keep reading `schedule.songStart`):

```js
return { ok: true, schedule: Object.freeze({
    tP, interval, offset,
    clicks: Object.freeze(_seq.clicks.map(c => Object.freeze({ time: c.time, isAccent: c.isAccent, scheduled: c.scheduled }))),
    songStart: Object.freeze({ time: built.songStart.time, offset: built.songStart.offset })
})};
```

The engine's internal `_seq` (with the live `scheduled` flags) is never exposed.

## Scenarios (inline; canonical in `behavior-specs.md` §7)

- **R-N4.1** — `result.schedule` is `Object.isFrozen`; mutating `result.schedule.clicks[0].scheduled = true` does not disturb the engine (the scheduler still schedules every click from its own `_seq`); P-01's `schedule.songStart` deep-equal still holds.

## Success criteria

- [ ] R-N4.1 RED first, then green.
- [ ] P-01 (and every other `.schedule` reader) still green.
- [ ] Both suites green at the item commit.

Status: ✅ done (2026-08-22)
