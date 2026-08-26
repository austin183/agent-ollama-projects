# Phase 3 — N-12: Restart announces "Count-in restarted"

**Source:** review N-12 — Restart *during count-in* announces nothing (`_setState` no-ops on unchanged state) → silent to assistive tech.

## Change

`onRestart`'s ok path (after `engine.restart` returns ok, before the refocus): `this.announcement = 'Count-in restarted';`. True in both enabled states — restart always restarts the count-in, whether pressed during count-in or during the song.

String inventory: **+1** ("Count-in restarted") — spec-consistent per the scope list (V-07 inventory +1 pre-approved).

## Scenarios (inline; canonical in `behavior-specs.md` §7)

- **R-N12.1** — countingIn or playing, restart ok → `announcement` = "Count-in restarted".

## Success criteria

- [ ] R-N12.1 RED first, then green (mock-VM; the countingIn case is the one the review names).
- [ ] V-02 suite green; both suites green at the item commit.

Status: ✅ done (2026-08-22)
