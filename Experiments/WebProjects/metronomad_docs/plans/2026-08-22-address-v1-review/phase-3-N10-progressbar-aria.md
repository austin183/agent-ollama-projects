# Phase 3 — N-10: Progressbar — static aria-label + aria-valuetext

**Source:** review N-10 — the live position appears in *both* `aria-label` (churning every ~100 ms) and `aria-valuenow` (unquantized float, e.g. `1.2345678`). Static label + `aria-valuetext="formatTime(songPosition)"` is the pattern the `progressbar` role intends.

## Change

- `index.html` progress region: `aria-label="Song progress"` (static), `:aria-valuetext="formattedPosition"` (the existing computed = `formatTime(songPosition)`).
- `createMetronomadApp.js`: delete the `progressAriaLabel` computed.
- `BeatDotsTest.html` B-04: replace the `progressAriaLabel` assertions with the static label (template — asserted via the pinned B-04 row, not a computed) + `formattedPosition` = "0:01.5" as the `aria-valuetext` source.
- v1 `behavior-specs.md` B-04 row: amend the aria-label clause (superseded by B-04 rev in this plan's `behavior-specs.md` §7).

## Scenarios

- **B-04 (rev)** — inline in `behavior-specs.md` §7 (fill/marker unchanged; static label; valuetext).

## Success criteria

- [ ] B-04 tests updated and green; no `progressAriaLabel` references remain (grep).
- [ ] Keyboard/reducedMotion E2E unaffected; both suites green at the item commit.

Status: ✅ done (2026-08-22)
