# Phase 3 — N-2: KB-11 — background-tab interval throttling (docs only)

**Source:** review N-2 · `playbackEngine.js:179-192`.

## Change (docs only, no code)

Record **KB-11** in `_agent_docs/plans/2026-08-17-metronomad-v1/context.md` (next free ID per this plan's cross-cutting constraint — the review's "KB-10" reference is superseded; KB-10 is the offline deferral):

- Background-tab `setInterval` throttling (Chrome: ≥1 s, intensive mode 1/min) late-schedules count-in clicks in a burst; `start(when)` with a past `when` fires immediately → a **compressed count-in**. The song start stays sample-exact (D5's immediate `start(when, offset)` is not throttled), the D9 dots self-heal (phase is a pure function of the audio clock), and the D10 watch can't catch it (context is still `running`).
- Acceptable v1 edge. The optional fix — **skip** clicks >50 ms past instead of late-scheduling — is a behavior change and is **deferred** with the KB.

## Success criteria

- [ ] KB-11 present in the v1 `context.md` known-behaviors list with the deferred-skip note.
- [ ] No code changes; suites untouched.

Status: ✅ done (2026-08-22)
