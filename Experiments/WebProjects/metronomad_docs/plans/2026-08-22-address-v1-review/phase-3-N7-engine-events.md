# Phase 3 — N-7: Export ENGINE_EVENTS; kill the magic event strings

**Source:** review N-7 · `playbackEngine.js` emits `'ended'`/`'previewEnded'` through `onStateChange` — magic strings not in `ENGINE_STATES`, switched on as bare literals in `createMetronomadMethods.js`.

## Change

- `playbackEngine.js`: `export const ENGINE_EVENTS = { ENDED: 'ended', PREVIEW_ENDED: 'previewEnded' };` — the engine emits `ENGINE_EVENTS.*` (no new `onEvent` surface; the event strings are part of the existing `onStateChange` contract, so values are unchanged).
- `createMetronomadMethods.js`: import `ENGINE_EVENTS`; the `onEngineStateChange` switch uses `case ENGINE_EVENTS.ENDED:` / `case ENGINE_EVENTS.PREVIEW_ENDED:`.

## Scenarios (inline; canonical in `behavior-specs.md` §7)

- **R-N7.1** — `ENGINE_EVENTS` deep-equals `{ ENDED: 'ended', PREVIEW_ENDED: 'previewEnded' }`; V-07's event-string behavior is unchanged (existing V-07 tests keep passing unmodified — they pin the wire values).

## Success criteria

- [ ] R-N7.1 RED first, then green.
- [ ] V-07 suite + engine suite green at the item commit.

Status: ✅ done (2026-08-22)
