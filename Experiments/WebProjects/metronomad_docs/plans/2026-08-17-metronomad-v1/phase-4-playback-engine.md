# Phase 4: PlaybackEngine (P0)

**Depends on:** Phase 2 (beatGrid math: `buildSchedule`, `beatInterval`), Phase 3 (`initHowler` for the real context/masterGain at wiring time — tests use fakes).

**Context to load:**
- `context.md` → Design Decisions D4 (generation counter), D5 (immediate song start), D6 (hand-rolled scheduler), D7 (click buffers), D10 (context watch); File Layout & Module Interfaces (playbackEngine + clickBuffers interfaces — the full method list is the contract); Testing Strategy (no real AudioContext in tests)
- Research: `_agent_docs/research/howlerjs-research.md` §3.2 / §8 (scheduler shape, click rendering)
- Skill: `references/testing-unit.md` (RAF/timer mocking, callback injection)

**TDD workflow:** start with 2–3 P0 scenarios (failing test → minimal code → run), then continue in small batches — don't write the full suite before the first green run.

## Overview

The core: lookahead scheduler, generation counter, state machine, interrupt watch, preview — all deterministic under injected fakes.

## Changes Required

- `MyESModules/Playback/playbackEngine.js` (P-01…P-14, D4/D5/D6/D10); `MyESModules/Audio/clickBuffers.js` (H-03, D7).
- `MyComponents/PlaybackEngineTest.html` — `fakeAudioContext` (`createBufferSource() → fakeSource`, `currentTime`, `state`, `resume()`), `fakeClock`, `fakeRAF` helpers in-page; fake sources record `{ when, offset, duration, stopped, ended() }` and connect calls (P-14).

**Testability core (from context.md interfaces):** every time read via `clock.currentTime`; every source created via one `_createSource(buffer)` closure that tests replace with a recording stub; timers injectable (`raf`, `cancelRaf`, `setInterval`, `clearInterval`, `schedulerMs`, `lookaheadSec`).

## Scenarios owned by this phase (canonical copy in `behavior-specs.md` §3.2)

Engine owns one sequence at a time. `state ∈ { stopped, countingIn, playing, preview }`. All time reads go through `clock.currentTime` (injectable fake — **no real AudioContext needed in tests**).

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| P-01 | P0 | `t_p = 100.0` on the fake clock | `startSequence({ buffer, bpm: 120, countInBeats: 4, offset: 90.0 })` | Click sources `start()` at **100.5 / 101.0 / 101.5 / 102.0** with isAccent `[true, false, false, false]`; song source `start(102.5, 90.0)` (immediate, D5); state `countingIn` → `playing` when clock passes 102.5; `onStateChange` fires once per transition |
| P-02 | P0 | Counting in (t_p=100), stopped at 100.75, 120 BPM/4 | `stop()` | Clicks at 101.0/101.5/102.0 **and** the scheduled song source (for 102.5) all `.stop()`-ed (spied); state `stopped`; `onStateChange('stopped')` once; second `stop()` is a no-op (idempotent) |
| P-03 | P0 | 20× alternating `startSequence(...)`/`stop()` in a tight loop | Mash test | Exactly one live source set at the end (zero after a final stop); zero scheduler intervals left running; zero callbacks referencing a dead generation (D4) |
| P-04 | P0 | Sequence A running, then `stop()` | Manually fire A's song `onended` | State **stays** `stopped`; no `onStateChange('ended')`. Then sequence B: B's `onended` → `onStateChange('ended')` exactly once |
| P-05 | P0 | `playing` | `restart({...})` | Synchronous `stop()` + `startSequence()` in one call; new `t_p = clock.currentTime` at the call; old song source stopped **before** new one starts (order spied) |
| P-06 | P0 | 3.0 s buffer, `t_p = 50.0` | `preview({ buffer, offset: 1.0 })` | One song source `start(50.0, 1.0, 2.0)` (duration = min(3, 3−1)); state `preview`; `onended` → `stopped` + `onStateChange('previewEnded')`; **no click sources created**. `preview({ buffer, offset: 2.9 })` → `start(50.0, 2.9, 0.1)` — clamped, never 0 or negative |
| P-07 | P1 | 3.0 s buffer, offset 2.5, sequence started | Clock passes song start + 0.5 s | `onended` → `onStateChange('ended')`, state `stopped`, scheduler cleared |
| P-08 | P1 | Fake clock frozen at t_p; engine started | Manual scheduler ticks | Scheduled sources have `when ∈ (now, now + 0.1]`; advancing `now` past a click time schedules the *next* unscheduled click exactly once — no duplicates, no gaps across the 25 ms tick boundary |
| P-09 | P1 | `countInBeats: 8` / `1` / `16` | `buildSchedule` accents | `[T,F,F,F,T,F,F,F]` / `[T]` / accents on clicks 1, 5, 9, 13 |
| P-10 | P1 | `startSequence(120, 4, t_p)` done | `getBeatGrid()` | `{ firstBeatTime: t_p + 0.5, interval: 0.5, state: 'countingIn' }` — the grid the dot loop renders from (D9). The song's downbeat (`firstBeatTime + 4·interval`) lies on this same grid, so dots stay in lockstep through the song |
| P-11 | P1 | Fake ctx reporting `state: 'suspended'` while `playing` | Watch ticks (250 ms) | Engine self-stops within one tick and fires `onInterrupted()` once; a second firing never happens; after our own `stop()` the watch interval is cleared (spied) |
| P-12 | P1 | Visual clock running | `stopVisualClock()` | `onFrame` called each RAF with `beatPhaseFromGrid(now, grid)`; `cancelAnimationFrame` receives the last pending id; no further frames |
| P-13 | P2 | Invalid params | `startSequence({ bpm: 0 })` / `({ countInBeats: 17 })` / `({ offset: -1 })` | Returns `{ ok: false }`; no sources created; state unchanged (defense-in-depth — UI already clamps) |
| P-14 | P1 | Any sequence running | Stop/end | Every created source connected `source → GainNode → masterGain` (spied `connect`) and all `disconnect()`-ed on stop/end — no dangling nodes |

**clickBuffers**

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| H-03 | P1 | Real or fake ctx | `renderClickBuffers(ctx)` | `{ accent, regular }`, both `AudioBuffer`s, `duration === 0.06 ± 0.001`, sample rate = `ctx.sampleRate`, buffers distinct (accent 1568 Hz vs regular 1047 Hz — assert configured frequencies differ and buffers are non-identical) |

## Success Criteria

**Automated:**
- [ ] All P-01…P-14 + H-03 pass with **zero real AudioContext instantiated**.
- [ ] Mash test (P-03) and stale-onended (P-04) pass — these are the atomicity gate.

**Manual:** none yet (engine has no UI).
