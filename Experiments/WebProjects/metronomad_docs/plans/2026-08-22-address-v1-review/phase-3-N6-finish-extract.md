# Phase 3 — N-6: Extract _finish(event) for the terminal-transition pattern

**Source:** review N-6 · `playbackEngine.js` — the terminal pattern (gen check → state guard → teardown → silent `_state = STOPPED` → emit) is duplicated for song and preview, the deliberate `_setState` bypass documented only in comments.

## Change

Refactor-only. Extract:

```js
// N-6: the shared terminal transition. Silent _state reset (bypassing
// _setState, which would emit 'stopped' as a second event) + the single
// terminal emit — exactly one of 'ended'/'previewEnded' per finished run.
function _finish(event) {
    _teardown();
    _state = ENGINE_STATES.STOPPED;
    _emit(event);
}
```

Both `onended` handlers keep their guards and call `_finish(ENGINE_EVENTS.ENDED)` / `_finish(ENGINE_EVENTS.PREVIEW_ENDED)` (constants land with N-7; if N-6 commits first, literals with a comment).

## Scenarios

**No new row** — the behavior is already fully pinned by P-04 (song onended), P-06 (preview onended), P-07 (early end), R-I4.2 (user-stop event sequence), and P-03 (stale callbacks). The refactor must not change any observable event sequence.

## Success criteria

- [ ] Pure refactor: all existing engine tests green with zero test edits.
- [ ] Both suites green at the item commit.

Status: ✅ done (2026-08-22)
