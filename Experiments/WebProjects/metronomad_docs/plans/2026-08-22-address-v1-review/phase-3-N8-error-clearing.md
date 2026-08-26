# Phase 3 — N-8: Clear errorMessage where its condition resolves

**Source:** review N-8 · `createMetronomadMethods.js` — `errorMessage` never auto-clears (only a successful load clears it). "Audio is blocked — tap again" survives the tap that works; the drop-lock message outlives the Stop that unblocks it.

## Change (scoping pick: clear at resolution, no dismiss "×")

- **Stop path** (`onPlayToggle` while locked): after `this._engine.stop()`, clear **only** the drop-lock message (`if (this.errorMessage === 'Drop a new song after stopping') this.errorMessage = '';`) — a Stop does not resolve a decode error, so no blanket clear.
- **Ok paths** clear the stale error, since a successful action resolves any start/preview/restart failure that produced one: `onPlayToggle` after `startSequence` ok, `onRestart` after restart ok, `onPreview` after preview ok → `this.errorMessage = ''`.
- No new user-facing strings (clearing adds none) — string inventory unchanged.

## Scenarios (inline; canonical in `behavior-specs.md` §7)

- **R-N8.1** — playing + lock message → Stop → message cleared, `engine.stop` called.
- **R-N8.2** — ready + "Audio is blocked…" → Play with running context → start ok → message cleared.
- **R-N8.3** — stale error → successful `onRestart` / `onPreview` / start → message cleared.

## Success criteria

- [ ] R-N8.1…R-N8.3 RED first (mock-VM), then green.
- [ ] V-01/V-02/U-08 suites still green (error set on failure paths unchanged).
- [ ] Both suites green at the item commit.

Status: ✅ done (2026-08-22)
