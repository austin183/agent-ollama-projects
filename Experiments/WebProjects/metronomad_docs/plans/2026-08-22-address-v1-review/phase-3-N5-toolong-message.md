# Phase 3 — N-5: Interpolate maxDurationSec into the tooLong message

**Source:** review N-5 · `fileLoader.js:62-66` — the `tooLong` message hardcodes "30 minutes" while `maxDurationSec` is injectable.

## Change

```js
message: `Song too long — maximum length is ${Math.round(maxDurationSec / 60)} minutes`
```

The default (1800 s) still renders "Song too long — maximum length is 30 minutes" — the U-20/KB-7 string is unchanged, so the string inventory is untouched.

## Scenarios (inline; canonical in `behavior-specs.md` §7)

- **R-N5.1** — `maxDurationSec: 3600` → "Song too long — maximum length is 60 minutes"; default → "30 minutes" (F-06 assertion preserved).

## Success criteria

- [ ] R-N5.1 RED first (custom `maxDurationSec` case), then green; F-06 default-string assertion stays.
- [ ] Both suites green at the item commit.

Status: ✅ done (2026-08-22)
