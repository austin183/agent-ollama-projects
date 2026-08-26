# Phase 3 — N-19: One offset-format story (keep formatTime, fix the hint)

**Source:** review N-19 — offset renders `m:ss.t` (unpadded minutes, `timeFormat.js`) while the placeholder and the format hint literally say "mm:ss.t".

## Change (planning default)

Keep `formatTime` (unpadded minutes match every other display in the app). Align the two literals to the *display*:

- `index.html`: `#offsetInput` placeholder `mm:ss.t` → `m:ss.t`.
- `commitOffsetEntry` hint: `'Enter the time as mm:ss.t'` → `'Enter the time as m:ss.t'`.
- `UiHandlersTest.html` V-04: update the two hint assertions.
- v1 `behavior-specs.md` V-04 row: update the hint wording.

String inventory: two *existing* strings reworded for internal consistency (pre-approved by the scope list); no new strings.

## Scenarios

No new row — the V-04 rows (v1 + this plan's amendments) carry the pinned strings; the placeholder is asserted by reading (template).

## Success criteria

- [ ] V-04 unit assertions updated and green.
- [ ] v1 spec row updated; both suites green at the item commit.

Status: ✅ done (2026-08-22)
