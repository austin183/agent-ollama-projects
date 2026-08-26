# Terminal Events Can Arrive Before a Poll-Driven State Transition

**Date:** 2026-08-19
**Context:** Metronomad Phase 4 — PlaybackEngine: the visible state flips `countingIn → playing` when a 25 ms scheduler tick observes `clock >= songStart.time`, but the song's authoritative `onended` event is event-driven (sample-accurate), not tick-driven

## The Bug Class

A state machine whose **visible state transitions on a poll** (interval tick) but whose **sequence termination is event-driven** has a race window: the end event can arrive before the flip tick runs.

Concretely: a song with an offset leaving less than one tick period (~25 ms) of audio. The song starts at `songStart.time` and ends at `songStart + 0.02 s`. The flip tick (next 25 ms boundary) has not run when `onended` fires — state is still `countingIn`. The terminal handler's guard:

```javascript
if (_state !== ENGINE_STATES.PLAYING) return;  // swallows the event
```

...silently drops the event. The sources are dead but the engine is frozen in `countingIn` forever — the UI shows "Counting in" with a dead Stop target. Found in Refactor-phase code review (not by a test); the fix was one RED test + one guard clause.

## The Rule

**A terminal handler must accept the event from every state the sequence can legitimately be in — not just the "expected" one.**

```javascript
_songSource.onended = () => {
    if (gen !== _generation) return; // stale (D4)
    // countingIn included: if the offset leaves < one tick of song,
    // onended can arrive before the flip tick ran — no frozen state.
    if (_state !== ENGINE_STATES.PLAYING && _state !== ENGINE_STATES.COUNTING_IN) return;
    _teardown();
    _state = ENGINE_STATES.STOPPED; // silent — 'ended' is the single terminal event
    _emit('ended');
};
```

General form: for any sequence with states `A → B → (terminal event) T`, the handler for T must accept **A and B** (every state reachable after the sequence started and before T), and only reject states belonging to a *different* generation/sequence. Generation/epoch guards handle cross-sequence rejection; state guards should not double as the primary rejection mechanism for the sequence's own events.

## Related Gotcha (same engine): generation-guard capture order

The D4 pattern is "capture `_generation` at creation; no-op if stale at event time." The increment happens inside the teardown that also stops sources:

- `onended` handlers: capture `const gen = _generation` **after** `_teardown()` in the start path → gen equals the live generation → guard works.
- The watch tick originally captured `gen` **before** calling `_teardown()` (which increments) → `gen !== _generation` was *always* true → `onInterrupted` silently dead. The "fires at most once" guarantee came from the watch interval being cleared in teardown, not from a generation check — the check was both wrong and unnecessary.

Rule: **capture the epoch after the operation that may bump it, or don't guard on it at all** — be deliberate about which mechanism provides the one-shot guarantee (epoch vs. resource cleanup) and don't stack a broken second one.

## When It Does NOT Apply

- Transitions driven by the same event clock as the terminations (e.g., everything flipped inside one handler) — no window exists.
- Sequences where the remaining duration is provably longer than the tick period by construction — the window is theoretical. (Still cheap to guard; Metronomad's minimum remaining-duration bound did not exist, so the guard was one clause.)

## Skill Mapping

- **`building-web-apps`** — the skill has **no audio coverage at all** (zero mentions of AudioContext/onended/lookahead/generation counter across SKILL.md + references). Candidates:
  - New `references/audio-scheduling.md` (or a section in an existing reference): the "A Tale of Two Clocks" shape (immediate precision start + lookahead click scheduling), poll-vs-event state race (this doc), generation/epoch guard placement, and the fake-context/clock/RAF/timer test harness from `Metronomad/MyComponents/PlaybackEngineTest.html` (shared ordered `calls` log is the Web-Audio analogue of the existing "Canvas Render Order Testing via Context Method Wrapping").
  - Until then, this doc is the canonical reference for the race.
- **`build-tdd` role** — review-phase value confirmed: the GREEN suite was 22/22 before this bug was found; the cost of the extra RED-GREEN cycle was ~10 minutes. Refactor-phase review is not optional polish for state machines.

## Session Note

Also pinned in the same phase: terminal events are SINGLE (`'ended'` / `'previewEnded'`), not preceded by `'stopped'` — the state silently becomes `stopped` and the terminal event is the one `onStateChange` call. A first-draft engine emitted both and the P-06 event-log assertion caught it.

---
**Status:** Closed (guard + test landed in Phase 4)
**Follow-up:** Phase 5 manual acceptance should include an offset within ~50 ms of track end (fastest realistic trigger of this window). Skill audio reference landed: `building-web-apps/references/audio-scheduling.md` (2026-08-19)
