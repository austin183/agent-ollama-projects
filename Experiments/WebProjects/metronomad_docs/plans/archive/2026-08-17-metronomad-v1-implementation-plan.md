> **ARCHIVED — superseded by the split plan directory [`2026-08-17-metronomad-v1/`](../2026-08-17-metronomad-v1/index.md).** This single-file plan is kept for history only; do not work from it.

# Metronomad v1 Implementation Plan

**Date:** 2026-08-17
**Spec:** `_agent_docs/specifications/metronomad-v1-specification.md`
**Research:** `_agent_docs/research/howlerjs-research.md` (Howler.js v2.2.3, verified empirically)
**Method:** BDD plan produced via `plan-bdd` workflow (world-review + planner delegation)

---

## Overview

Metronomad is a single-page static tool for musicians: drop a local audio file → set BPM (30–250, default 120), an offset (mm:ss.t, scrubber + direct entry), and count-in length (1–16, default 4) → **Play** runs a metronome count-in on the Web Audio clock, then starts the song **sample-accurately at the offset on the downbeat** via `AudioBufferSourceNode.start(when, offset)`.

Architecture is **Option B** from the research doc: Howler.js (CDN) provides only AudioContext setup, `Howler.masterGain`, `Howler.codecs()`, and mobile auto-unlock (`Howler.autoSuspend = false` — Pitfall 1). The precision-critical path is raw Web Audio: we decode the dropped `File` ourselves and schedule count-in clicks AND the song start on the same context into `Howler.masterGain`. No build step, Vue 3 Options API via CDN, ES modules with named exports — the repo's standard pattern.

## Current State Analysis

- `Metronomad/` is empty except `_agent_docs/` and `.pi/skills/building-web-apps` (symlink to the canonical CollageMaker skill).
- Howler research is complete and empirically verified: `start(when, offset)` is sample-accurate (0.41 ms measured drift); Howler's own `play()` cannot schedule a future start; blob URLs need `format`; `autoSuspend` kills custom playback; mp3 decodes in all three major browsers.
- CollageMaker is the reference implementation: Vue 3 CDN factory decomposition, `MyESModules/` + `MyComponents/` (Mocha+Chai in-browser unit tests) + `test/e2e/` (Playwright, chromium only, `baseURL :8000`, workers 1) + `scripts/run-tests.js` (Node+Playwright driver that opens Mocha test pages over HTTP).
- Root `node_modules` already has `@playwright/test` + chromium. Root `index.html` hosts project cards (`project-card` + `card-icon`/`card-title`/`card-description`/`launch-button`).
- Server: user runs `start-server.sh` → `http://localhost:8000/Metronomad/index.html` (repo rule: agents never start it).

## Desired End State

A musician can, at `http://localhost:8000/Metronomad/index.html`: load any Howler-decodable local audio file, set BPM/offset/count-in, and press Play to get a rhythmically exact count-in into the song at the offset — with Stop/Restart, offset preview, beat dots, progress with offset marker, keyboard + screen-reader access, and friendly errors. Verified by 34 pure-function unit scenarios, ~30 component/unit scenarios, 12 E2E scenarios, and a manual acceptance checklist.

### Key Discoveries:
- `AudioBufferSourceNode.start(when, offset)` on the shared context is sample-accurate; Howler's `play()` is not scheduleable (research §3).
- `Howler.autoSuspend` must be `false` — its 30 s timer only sees Howler's own sounds (research Pitfall 1).
- `Howler.ctx` is null until lazy setup — touch `Howler.volume()` first (research Pitfall 2).
- Decoded `AudioBuffer` is float32: 44.1 kHz stereo ≈ **21.1 MB/min** (research's 10.6 MB/min figure was 16-bit PCM) — drives the 30-minute guard (D3).
- Chromium supports every common codec, so the codec-reject path is unit-tested (F-02) + manually verified on Safari; it cannot be triggered with a real file in chromium E2E.
- Beat phase computed as a **pure function of the audio clock** makes hidden-tab RAF pausing (Safari) harmless — no accumulated phase to drift (D9).

## What We're NOT Doing

- No BPM/key detection or any audio analysis (spec §12).
- No persistence between visits, no queue/multi-song, no looping, no metronome-only mode.
- No time signatures other than 4/4 (accent fixed to every 4th beat).
- No volume sliders, custom click sounds, or click/song muting.
- No minimum lead-time floor at high BPM (D1 — spec's timing law wins).
- No pre-decode file-size confirmation dialog (post-decode duration guard instead, D3).
- No Firefox/Safari E2E projects (chromium only, matching CollageMaker); cross-browser checks are manual + a flagged follow-up.
- No live tempo/offset changes mid-sequence (parameters locked, spec §6).
- No mobile-first layout polish (basic responsiveness only, spec §12).

## Design Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | **No minimum lead floor** — first click is always exactly one beat after press (250 BPM → 0.24 s lead). | Spec §5/§14.2 are explicit; a floor would break the timing law `click k at t_p + k·b`. Documented as known behavior (KB-1). |
| D2 | **Preview = 3 s**, clamped to remainder: `min(3, duration − offset)`. | Spec says "a few seconds"; clamp avoids starting with ≤0 duration. |
| D3 | **30-minute max duration guard** checked *after* decode, before publishing: `buffer.duration > 1800` → discard buffer + revoke URL + `tooLong` error. | float32 PCM ≈ 21.1 MB/min; 30 min ≈ 635 MB worst case. Graceful guard for iOS memory (world-review 4.2/6.2). KB-7. |
| D4 | **Generation counter** in PlaybackEngine: every `stop()`/`startSequence()`/`restart()`/`preview()` increments `_generation`; `onended` callbacks and scheduler ticks capture their generation and no-op if stale. | Makes Play/Stop mashing atomic (world-review 2.1) and guarantees no phantom clicks (2.2) without a lock. |
| D5 | **Song source is `start(when, offset)`-ed immediately** in `startSequence`; the lookahead loop (25 ms tick, 100 ms horizon) schedules only the N click sources. | One deterministic precision call; standard "A Tale of Two Clocks" shape for the rest. |
| D6 | **Hand-rolled scheduler, no Tone.js.** | ~60 lines, zero new dependency, math already specified (research §3.2/§8). Tone.js would drag in a second audio graph. |
| D7 | **Clicks = pre-rendered AudioBuffers**: accent 1568 Hz, regular 1047 Hz, 60 ms, 5 ms linear attack + exponential decay to 1e-5, rendered at `ctx.sampleRate`. | Research §8; distinct pitch + accent dot visually distinct (a11y: size/shape, not color alone). |
| D8 | **App states**: `noFile / ready / countingIn / playing` + `decoding {active, fileName}` flag + non-blocking `errorMessage` (Error is an overlay — "app stays in the last valid state", spec §9). **Ended is not a resting state**: song `onended` returns to `ready` with position reset to the offset. | Matches spec §9 exactly. |
| D9 | **Beat phase is a pure function of the audio clock**: `beatPhaseFromGrid(now, firstBeatTime, interval) → { beatIndex, inBeat }`. The RAF dot loop calls it every frame; on `visibilitychange` → visible it re-renders once. | No accumulated phase → hidden-tab RAF pausing can never cause drift/stutter (world-review 1.1/5.4/6.1 fall out for free). |
| D10 | **Context-state watch**: while `countingIn`/`playing`/`preview`, a 250 ms interval checks `ctx.state`; `suspended`/`interrupted` (not from our own stop) → engine self-stops + `onInterrupted()` → Ready + announcement. `ctx.resume()` rejection after Play → ~750 ms timeout → friendly error (world-review 1.2/1.4). | OS audio interruptions and blocked autoplay become visible, recoverable states. |
| D11 | **Test fixture**: extract the base64 3 s 440 Hz MP3 already embedded in `_agent_docs/research/howler-research-test.html` into `test/fixtures/sine3s.mp3` (~40 KB). One fixture for all E2E; no new tooling. | Reuses verified artifact; keeps repo light. |

## Behavior Specifications

Legend: **P0** core behavior · **P1** structural correctness · **P2** polish. Scenarios are the contract for `build-tdd` — each maps to failing tests first.

### 3.1 User Behavior (end-to-end)

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| U-01 | P0 | App in No-file state | User drags a valid `song.mp3` (3 s) onto the drop zone (or uses Browse) | Drop zone shows "Decoding song.mp3…", Play disabled; after decode: state Ready, filename + duration "0:03.0" shown, Play/BPM/offset/count-in enabled, live region announces "song.mp3 loaded" |
| U-02 | P0 | Ready, `song.mp3` (3.0 s), BPM 120, offset 0:00.0, count-in 4 | User presses Play | Within 150 ms state "Counting in" (button label **Stop**), announced "Count-in started"; clicks at +0.5 s (accent, dot 1 lit), +1.0 s, +1.5 s, +2.0 s; at +2.5 s song starts at 0:00.0 with **no click** (dot 1 pulses), state "Playing", announced "Song started"; progress reads the offset **0:00.0** at the state flip |
| U-03 | P0 | Playing, offset 0:00.0, 3 s song | Song reaches its end | State returns to Ready automatically, progress/position reset to the offset "0:00.0", button label "Play", announced "Song ended" |
| U-04 | P0 | Counting in (click 2 of 4 just sounded) | User presses Stop | All scheduled clicks cancelled — **no click sounds after the stop**; state Ready within 50 ms; offset/BPM preserved; announced "Stopped"; focus returns to the Play/Stop button |
| U-05 | P0 | Playing | User presses Restart | Song stops immediately (< 50 ms, no fade); new count-in begins with first click exactly one beat after the press (120 BPM → +0.5 s); song starts at +2.5 s at the **original offset**; announced "Count-in started" |
| U-06 | P0 | Ready, BPM 120, offset 1:30.0, count-in 4 | User presses Play | The song's first audible sample is the audio at 1:30.0 in the file, beginning on the beat boundary after the 4th click (manual: listen + progress reads "1:30.0" at the state flip) |
| U-07 | P1 | Ready, BPM 120, count-in 6 | User presses Play | Clicks at +0.5 (accent), +1.0, +1.5, +2.0, +2.5 (accent — beat 1 of bar 2), +3.0; the 4-dot row cycles (dot 1 lit again at +2.5); song starts at +3.5 s |
| U-08 | P1 | Ready, offset 0:01.0 in a 3 s song | User presses Preview | Song plays from 0:01.0 with **no clicks, no count-in** until the song ends at 0:03.0 (3 s preview clamped to the 2 s remaining, D2); app state stays Ready with button label "Stop"; announced "Preview started"; at end, announced "Preview stopped" |
| U-09 | P2 | Preview playing | User presses Stop | Audio stops within 50 ms; dots + progress reset to the offset marker position; offset preserved; announced "Preview stopped" |
| U-10 | P1 | Ready, 3.0 s song | User drags the scrubber to 50 % | Offset field shows "0:01.5" and the progress marker moves to 50 %. When user types "1:05.2" and commits (Enter/blur), value clamps to "0:03.0" (song duration) with hint "Offset limited to song length" |
| U-11 | P1 | Ready | User types "999" in BPM | Clamps to 250 with hint "BPM limited to 30–250"; "10" clamps to 30; non-numeric/empty restores the previous valid value; stepper buttons change by ±1 |
| U-12 | P1 | Counting in (or Playing) | User tries to change BPM / offset / count-in | All three controls disabled **and unfocusable** (Tab skips them), group shows a subtle "locked until next Play" hint; after Stop, new values are used on the next Play |
| U-13 | P1 | Playing | User drops another file on the zone | Drop rejected with "Drop a new song after stopping"; the playing song is unaffected. After Stop, the same drop is accepted: state Ready with new file; old buffer reference dropped and old object URL revoked |
| U-14 | P0 | No-file state | User drops `track.ogg` | In Chromium (supported): proceeds to decode. In Safari (unsupported; manual): Error "This browser can't play .ogg files", stays No-file (Play disabled), announced |
| U-15 | P0 | No-file state | User drops a corrupt/garbage `broken.mp3` | Error "Couldn't decode broken.mp3 — the file may be corrupted"; state remains No-file; Play disabled; announced; **no cryptic DOMException text shown** |
| U-16 | P1 | A file failed to decode (error showing) | User drops a valid `song.mp3` | Prior error cleared; new file loads normally to Ready |
| U-17 | P1 | Playing | User switches tabs ≥ 5 s and returns | Beat dots instantly on the correct beat (recomputed from the audio clock — no stutter, no drift); progress continuous |
| U-18 | P1 | Playing | OS interrupts audio (context → `interrupted`/`suspended`; E2E via `ctx.suspend()` in `page.evaluate`) | App stops the sequence, returns to Ready, announces "Audio was interrupted — press Play to try again" |
| U-19 | P1 | Ready, context blocked (Safari-like) | User presses Play and `ctx.resume()` never reaches "running" | After ~750 ms: error "Audio is blocked by the browser — tap again to enable sound", app returns to Ready (button is not dead) |
| U-20 | P1 | Ready | User drops a 40-minute file | Decode completes, guard fires: error "Song too long — maximum length is 30 minutes"; state No-file; buffer discarded, URL revoked |
| U-21 | P2 | Ready, 34-character filename | Rendered | Name truncated with ellipsis; full name available via `title` tooltip |
| U-22 | P2 | `prefers-reduced-motion: reduce` | Playing | Beat dots use a static highlight (no pulse animation) |
| U-23 | P1 | Playing | User Tabs through the page | Scrubber is not focusable; Play/Stop, Restart, Preview, BPM, count-in reachable in sensible order; all operable by keyboard |

### 3.2 Component Behavior (module contracts)

**FileLoader — `createFileLoader({ codecs, maxDurationSec = 1800 })`** (codec provider injected: `codecs.check(ext) → bool`)

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| F-01 | P0 | `codecs.check` spy | `loadFile(null)` | Resolves `{ ok: false, code: 'noFile' }` — never throws on null (null-input guard convention) |
| F-02 | P0 | `codecs.check('ogg') === false`, spy File | `loadFile(file)` with ext `'ogg'` | Resolves `{ ok: false, code: 'codec' }` **without calling** `file.arrayBuffer()` or `decodeAudioData` (spies) |
| F-03 | P0 | Valid 3 s MP3 File, real AudioContext | `loadFile(file)` | Resolves `{ ok: true, buffer (3.0 s), duration: 3.0, fileName, objectUrl }`; exactly one `URL.createObjectURL` call |
| F-04 | P0 | File whose decode rejects (`EncodingError` via mock) | `loadFile(brokenFile)` | Resolves `{ ok: false, code: 'decode' }`; no throw escapes; the object URL created during the attempt **is revoked** |
| F-05 | P0 | Two files loaded in sequence | `loadFile(a)` then `loadFile(b)` | `a`'s object URL revoked (spy), `a`'s buffer no longer referenced; only `b`'s URL live. All exit paths (success, codec, decode, tooLong) leave no live orphan URL |
| F-06 | P1 | Decoded `buffer.duration > maxDurationSec` | `loadFile(longFile)` | `{ ok: false, code: 'tooLong' }`; URL revoked; buffer not returned |
| F-07 | P1 | File named "track" (no extension) | `loadFile(file)` | `{ ok: false, code: 'codec' }` (unknown extension = not supported) |
| F-08 | P1 | `onStateChange` callback injected | `loadFile(...)` | Fires `decoding` (with fileName) before the await and `idle` after — on success **and** failure (try/finally shape) |
| F-09 | P2 | Various names | `extractExt('Song (final).mp3')` / `('archive.tar.gz')` / `('noext')` | `'mp3'` / `'gz'` / `''` |

**PlaybackEngine — `createPlaybackEngine({ context, masterGain, clickBuffers, onStateChange, onInterrupted, clock = context, schedulerMs = 25, lookaheadSec = 0.1, raf, cancelRaf, setInterval, clearInterval })`**

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

**howlerSetup / codecSupport / clickBuffers**

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| H-01 | P0 | Stubbed `window.Howler` (lazy-ctx behavior) | `initHowler()` | Returns `{ ctx, masterGain }` with non-null `ctx`, numeric `ctx.currentTime`, and **`Howler.autoSuspend === false`** after the call (Pitfall-1 guard); `Howler.autoUnlock` left `true` |
| H-02 | P1 | `Howler.codecs` stub | `isSupportedCodec('mp3')` / `isSupportedCodec('')` | `Howler.codecs('mp3')` result / `false` |
| H-03 | P1 | Real or fake ctx | `renderClickBuffers(ctx)` | `{ accent, regular }`, both `AudioBuffer`s, `duration === 0.06 ± 0.001`, sample rate = `ctx.sampleRate`, buffers distinct (accent 1568 Hz vs regular 1047 Hz — assert configured frequencies differ and buffers are non-identical) |

**createBeatDots (UI layer, callback injection per skill convention)**

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| B-01 | P1 | Mock `vm` with `beatPhase: { beatIndex: 2, inBeat: 0.5 }` (RAF mocked with the callback-collector pattern) | One RAF flush | Dot index 2 has class `beat-dot--active`; next frame with `beatIndex: 0` → dot 0 active, dot 2 not |
| B-02 | P1 | Dots running | `visibilitychange` → hidden, then visible | Hidden: RAF loop paused (no further `onFrame`). Visible: one immediate re-render from `engine.getBeatGrid()` + `clock.currentTime` — dots snap to the correct beat (U-17) |
| B-03 | P2 | `matchMedia('(prefers-reduced-motion: reduce)').matches === true` | Beat active | Active dot gets class `beat-dot--static` (no `--pulse`); media change updates live |
| B-04 | P1 | `songPosition 1.5, duration 3.0, offset 1.0` | Render | Progress fill width `50%`; offset marker left `33.333%`; progress region `aria-label` = "Song position 0:01.5 of 0:03.0, entry at 0:01.0" |
| B-05 | P1 | All visual timers running | `stopAll()` (called from `beforeUnmount`) | Cancels RAF + watch interval (spied) — no leaks after unmount |

**Vue app (`createMetronomadMethods`)** — handler contracts tested via mock-VM construction (spread factory methods first, then override spies):

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| V-01 | P0 | `ready` state | `onPlayToggle()` | `engine.startSequence` called with `{ buffer, bpm, countInBeats, offset }` matching current controls. In `countingIn`/`playing`/`preview` → `engine.stop()` (single Play↔Stop toggle, spec §14.5) |
| V-02 | P0 | `countingIn`/`playing` | `onRestart()` | `engine.restart(...)` called; in `ready`/`noFile`/`preview` → no-op. After Stop/Restart, the Play/Stop button is refocused (`$nextTick` + state guard) |
| V-03 | P1 | `ready` | `onBpmInput('251')` / `('')` | `bpm = 250` + `bpmClamped = true` (hint shown); empty → restores last valid bpm. `onCountInInput('0')` → 1; `('99')` → 16 |
| V-04 | P1 | `ready`, duration 3.0 | `commitOffsetEntry('1:05.2')` / `('abc')` | Offset = 3.0 + hint; `'abc'` → offset unchanged + hint "Enter the time as mm:ss.t" |
| V-05 | P0 | File drop | `onFileDropped(file)` | Wraps `fileLoader.loadFile` in try/finally: `decoding` false on **all** paths; on `ok` → `ready` + live region "<name> loaded"; on failure → `errorMessage` set, `appState` unchanged (U-15/U-16) |
| V-06 | P1 | Any state | `isParamLocked` computed | True in `countingIn`/`playing`/**`preview`** (any running audio); scrubber additionally `tabindex="-1"` when locked (U-12/U-23). Restart's `:disabled` uses `isSequenceRunning` = `countingIn \|\| playing` only — Restart stays disabled during preview (spec §6: Restart is for the count-in/song sequence) |
| V-07 | P1 | State transitions | Live-region text (polite) | "" → "Count-in started" → "Song started" → "Stopped" / "Song ended" / "Preview started" / "Preview stopped" / "Audio was interrupted — press Play to try again". Errors use `role="alert"` |

### 3.3 Pure Function Behavior (input/output pairs)

**`Utils/beatGrid.js`**

| ID | Input | Output |
|----|-------|--------|
| T-01 | `beatInterval(120)` | `0.5` |
| T-02 | `beatInterval(60)` / `(30)` / `(250)` | `1.0` / `2.0` / `0.24` |
| T-03 | `beatInterval(0)`, `(NaN)`, `(Infinity)` | `NaN` (guarded via `Number.isFinite` + `> 0`; assert the guard) |
| T-04 | `buildSchedule({ tP: 100.0, bpm: 120, countInBeats: 4, offset: 90.0 })` | `{ clicks: [{ time: 100.5, isAccent: true }, { time: 101.0, isAccent: false }, { time: 101.5, isAccent: false }, { time: 102.0, isAccent: false }], songStart: { time: 102.5, offset: 90.0 } }` |
| T-05 | `buildSchedule({ tP: 0, bpm: 30, countInBeats: 16 })` | 16 clicks at 2.0, 4.0, …, 32.0; accents on clicks 1/5/9/13; `songStart.time = 34.0` |
| T-06 | `buildSchedule({ tP: 5, bpm: 250, countInBeats: 1 })` | `clicks = [{ time: 5.24, isAccent: true }]`, `songStart.time = 5.48` (D1: no lead floor) |
| T-07 | `buildSchedule({ tP: 1, bpm: 120, countInBeats: 0 })` | throws `RangeError` (count-in ≥ 1 by contract; UI clamps, engine guards per P-13) |
| T-08 | `beatPhaseFromGrid(102.75, 100.5, 0.5)` | `{ beatIndex: 2, inBeat: 0.5 }` |
| T-09 | `beatPhaseFromGrid(100.49, 100.5, 0.5)` (before first beat) | `{ beatIndex: -1, inBeat: 0 }` — no dot lit during the lead beat |
| T-10 | `beatPhaseFromGrid(104.999, 100.5, 0.5)` | `{ beatIndex: 3, inBeat: 0.998 }` (floor, not round — no wrap to 0 until the true boundary) |
| T-11 | `beatPhaseFromGrid(NaN, 100.5, 0.5)` | `{ beatIndex: -1, inBeat: 0 }` (Number.isFinite guard) |

**`Utils/timeFormat.js`**

| ID | Input | Output |
|----|-------|--------|
| T-12 | `formatTime(75.3)` | `"1:15.3"` |
| T-13 | `formatTime(0)` | `"0:00.0"` |
| T-14 | `formatTime(65.25)` | `"1:05.3"` (half-up to tenth) |
| T-15 | `formatTime(3599.94)` | `"59:59.9"` |
| T-16 | `formatTime(600.0)` | `"10:00.0"` (minutes ≥ 10) |
| T-17 | `formatTime(-1)`, `formatTime(NaN)` | `"0:00.0"` (clamped/guarded) |
| T-18 | `parseOffsetInput("1:05.2")` | `65.2` |
| T-19 | `parseOffsetInput("90")` | `90.0` (bare seconds accepted) |
| T-20 | `parseOffsetInput("1:5")` | `65.0` (seconds without tenths) |
| T-21 | `parseOffsetInput("0:00.0")` | `0.0` |
| T-22 | `parseOffsetInput("1:75")` | `null` (seconds ≥ 60 invalid) |
| T-23 | `parseOffsetInput("-5")` | `null` |
| T-24 | `parseOffsetInput("")`, `("abc")`, `("1:2:3")` | `null` |
| T-25 | `parseOffsetInput(90)` (number passthrough) | `90.0` (coerces) |

**`Utils/paramClamps.js`**

| ID | Input | Output |
|----|-------|--------|
| T-26 | `clampBpm(119.6)` | `120` (whole numbers, spec §4) |
| T-27 | `clampBpm(251)` / `(29)` | `250` / `30` |
| T-28 | `clampBpm(NaN)` / `(undefined)` | `120` (default) |
| T-29 | `clampCountIn(0)` / `(16.4)` / `(99)` | `1` / `16` / `16` |
| T-30 | `clampCountIn(NaN)` | `4` (default) |
| T-31 | `clampOffset(90, 3.0)` | `3.0` |
| T-32 | `clampOffset(-5, 3.0)` | `0` |
| T-33 | `clampOffset(1.2345, 3.0)` | `1.2` (quantized to tenths — matches display precision) |
| T-34 | `clampOffset(1, NaN)` | `0` (invalid duration guard) |

### 3.4 E2E Test Scenarios (Playwright, chromium)

**Fixture:** `test/fixtures/sine3s.mp3` — extracted from the research harness base64 (D11). Single fixture for all E2E.
**Config:** `Metronomad/playwright.config.cjs` mirrors CollageMaker's — chromium only, `baseURL: http://localhost:8000`, `workers: 1`, `timeout: 30000`, **no `webServer` block** (server started manually per repo rule), plus `use.launchOptions.args: ['--autoplay-policy=no-user-gesture-required']` for deterministic `AudioContext` state in headless.
**Waits (repo convention — no `waitForTimeout` for assertions):** the app exposes `document.body.dataset.state` = appState and `data-beat` on the beat-dot row (intentional testability hooks, KB-6). Assert with `expect`/`expect.poll`; capture `t0 = performance.now()` at the Play click and assert transition times within tolerance.

**`playback.spec.cjs`** — 3 s fixture, 120 BPM (beat = 0.5 s), **count-in 2** → song starts ≈ +1.0 s, song ends ≈ +3.0 s after start (full lifecycle in 4 s of wall time).

| ID | Test | Steps | Expected |
|----|------|-------|----------|
| E2E-1.1 | Load → ready | `setInputFiles('#fileInput', fixture)` | Filename "sine3s.mp3" + duration "0:03.0" visible; `data-state=ready`; Play enabled |
| E2E-1.2 | Full sequence timing | Set count-in 2 → click Play (t0) | `data-state=countingIn` within 300 ms of t0; dot row shows beat 1 then beat 2 (data-beat) before the flip; `data-state=playing` at t0+1.0 s ± 0.3 s; live region "Song started"; progress advances past 0:01.0; `data-state=ready` ≈ 3.0 s after the playing flip ± 0.5 s; progress reset to offset; "Song ended" announced |
| E2E-1.3 | Stop during count-in | Play → `countingIn` → Stop | `ready` within 500 ms; progress 0:00.0; BPM/offset preserved; controls enabled |
| E2E-1.4 | Stop during playback | Play → `playing` → Stop | `ready`; progress reset to offset |
| E2E-1.5 | Restart | Play → `playing` → Restart | `countingIn` → `playing` again; progress restarts from offset |
| E2E-1.6 | Parameter lock | In `countingIn` and `playing` | BPM input, scrubber, offset text, count-in all `disabled`; re-enabled after Stop |
| E2E-1.7 | Preview clamp | Offset 0:01.0 → Preview | Plays from 1.0 s; auto-stops ≤ 2 s (D2 clamp to song end); back to `ready`; offset still 0:01.0 |
| E2E-1.8 | Beat dots in play | Observe 4 dots during a sequence | Dot 1 has distinct class (`beat-dot--downbeat`); active-dot index advances ≥ 1 over 2 observed beats |

**`errors.spec.cjs`**

| ID | Test | Steps | Expected |
|----|------|-------|----------|
| E2E-2.1 | Decode failure | Upload `bad.mp3` (text bytes named .mp3) | `role=alert` message (no cryptic DOMException text); `data-state` stays `noFile`; then upload the real fixture → `ready` (non-blocking error, D8) |
| E2E-2.2 | Drop lock | Load fixture → Play → `playing` → dispatch file drop | State/filename unchanged; "Drop a new song after stopping" indication |
| E2E-2.3 | Clamps | Offset "9:99.9" → commit; offset "-1" → commit; BPM "999" / "10" | 0:03.0; 0:00.0; 250 / 30, each with clamp hint |
| E2E-2.4 | Non-audio drop | Upload a `.txt` file | Stays `noFile`; no crash; console-error free |

*Note:* a true **codec-reject** E2E is not possible on chromium (it supports every common codec — verified in research §6); that path is covered by unit F-02 (spy) and manually on Safari (U-14).

## Priority Ordering

| Priority | Scenarios | Rationale |
|----------|-----------|-----------|
| **P0** | U-01…U-06, U-14, U-15 · F-01…F-05 · P-01…P-06 · H-01 · V-01, V-02, V-05 · T-04…T-07 (schedule math) · E2E-1.1…1.5, E2E-2.1, E2E-2.3 | Core value: file in, exact count-in out, atomic stop/restart, no leaks, friendly errors |
| **P1** | U-07, U-10…U-13, U-16…U-20, U-23 · F-06…F-08 · P-07…P-12, P-14 · H-02, H-03 · B-01, B-02, B-04, B-05 · V-03, V-04, V-06, V-07 · T-01…T-03, T-08…T-34 · E2E-1.6…1.8, E2E-2.2, E2E-2.4 | Structural correctness, UX safety, accessibility, resource hygiene |
| **P2** | U-09, U-21, U-22 · F-09 · P-13 · B-03 | Polish and edge cases |

---

## File Layout & Module Interfaces

All modules: **named exports only**, factory functions (no classes), relative imports with `.js` extension, re-exported in `MyESModules/index.js` (barrel — verify each name resolves; a re-export of a nonexistent name silently yields `undefined`).

```
Metronomad/
├── index.html                      # Single entry: Vue template + CDN scripts (vue.global.js, howler.min.js)
├── Style.css                       # Project styles
├── AGENTS.md                       # Project conventions (Phase 8)
├── playwright.config.cjs           # chromium only, :8000, autoplay flag, no webServer
├── scripts/
│   └── run-tests.cjs               # Mocha-in-browser runner (adapt CollageMaker/scripts/run-tests.js; BASE_DIR → Metronomad)
├── MyESModules/
│   ├── index.js                    # Barrel
│   ├── App/
│   │   ├── createMetronomadApp.js  # Assembles data/methods/lifecycle → createApp(...).mount('#app')
│   │   ├── createMetronomadData.js
│   │   ├── createMetronomadMethods.js   # Vue handlers (.call(this) binding convention)
│   │   ├── createMetronomadLifecycle.js # mounted/beforeUnmount + cleanup ordering
│   │   └── createBeatDots.js           # RAF beat/progress visualizer (callback injection)
│   ├── Audio/
│   │   ├── howlerSetup.js          # initHowler()
│   │   ├── codecSupport.js         # isSupportedCodec(ext)
│   │   └── clickBuffers.js         # renderClickBuffer/renderClickBuffers
│   ├── File/
│   │   └── fileLoader.js           # createFileLoader
│   ├── Playback/
│   │   └── playbackEngine.js       # createPlaybackEngine — scheduler + sources + state machine
│   └── Utils/
│       ├── beatGrid.js             # beatInterval / buildSchedule / beatPhaseFromGrid
│       ├── timeFormat.js           # formatTime / parseOffsetInput
│       └── paramClamps.js          # clampBpm / clampCountIn / clampOffset
├── MyComponents/                   # Mocha+Chai browser unit tests
│   ├── TimingMathTest.html         # T-01…T-34
│   ├── FileLoaderTest.html         # F-01…F-09, H-01, H-02
│   ├── PlaybackEngineTest.html     # P-01…P-14, H-03 (fake context/clock/RAF helpers in-page)
│   ├── BeatDotsTest.html           # B-01…B-05
│   └── UiHandlersTest.html         # V-01…V-07 (mock-VM pattern)
└── test/
    ├── fixtures/
    │   ├── sine3s.mp3              # D11 — extracted from research harness
    │   └── bad.mp3                 # text bytes for E2E-2.1 (tiny, generated in Phase 7)
    └── e2e/
        ├── playback.spec.cjs       # E2E-1.x
        └── errors.spec.cjs         # E2E-2.x
```

**Key interfaces** (testability core: every time read via `clock.currentTime`; every source created via one `_createSource(buffer)` closure that tests replace with a recording stub; timers injectable):

```js
// Audio/howlerSetup.js
export function initHowler() // → { ctx, masterGain }. Touches Howler.volume(1) to force lazy ctx (Pitfall 2); sets Howler.autoSuspend = false (Pitfall 1); autoUnlock left true

// Audio/codecSupport.js
export function isSupportedCodec(ext) // '' → false; else Howler.codecs(ext)

// Audio/clickBuffers.js
export const CLICK = { ACCENT_FREQ: 1568, REGULAR_FREQ: 1047, DURATION_SEC: 0.06, ATTACK_SEC: 0.005 }
export function renderClickBuffer(ctx, freq) // → AudioBuffer (linear attack + exponential decay to 1e-5)
export function renderClickBuffers(ctx) // → { accent, regular }

// File/fileLoader.js
export function createFileLoader({ codecs, maxDurationSec = 1800 }) // → {
//   loadFile(file) → Promise<{ ok, buffer?, duration?, fileName?, objectUrl?, code?, message? }>,
//   release() → void,   // revoke current URL, drop buffer ref
//   extractExt(name) → string
// }

// Playback/playbackEngine.js
export const ENGINE_STATES = { STOPPED: 'stopped', COUNTING_IN: 'countingIn', PLAYING: 'playing', PREVIEW: 'preview' }
export const SCHEDULER = { TICK_MS: 25, LOOKAHEAD_SEC: 0.1, WATCH_MS: 250, RESUME_TIMEOUT_MS: 750 }
export const PREVIEW_SECONDS = 3
export function createPlaybackEngine({
  context, masterGain, clickBuffers,          // real or fake (tests)
  onStateChange, onInterrupted, onFrame,      // callback injection
  clock, schedulerMs, lookaheadSec,           // testability (defaults: context / SCHEDULER.*)
  raf, cancelRaf, setInterval, clearInterval  // timer injection (defaults: window.*)
}) // → {
//   startSequence({ buffer, bpm, countInBeats, offset }) → { ok, schedule? },
//   stop() → void,            // idempotent; generation bump (D4)
//   restart(params) → { ok }, // stop + startSequence, synchronous
//   preview({ buffer, offset }) → { ok },
//   state → string,
//   getBeatGrid() → { firstBeatTime, interval, state } | null,
//   songPosition(now?) → number | null,   // offset + (now − songStartTime), clamped [offset, duration]
//   startVisualClock() / stopVisualClock(),
//   dispose()                  // clears scheduler + watch + RAF
// }

// App/createBeatDots.js
export function createBeatDots(base, callbacks) // base = { getEngine, getClock, getDom(id) }
// → { startVisualClock(vm), stopVisualClock(vm), onVisibilityChange(vm), stopAll(vm) }

// App/createMetronomadApp.js
export function createMetronomadApp({ createApp, dataConfig, methodsConfig, lifecycleConfig }) // → app
```

**Vue wiring (`createMetronomadLifecycle`):** `mounted()` → `initHowler()` in try (failure → Error state "Audio is not supported in this browser") → `renderClickBuffers` → `createPlaybackEngine` (callbacks mutate reactive state + live region) → `createFileLoader({ codecs: { check: isSupportedCodec } })` → `createBeatDots` → drop handlers (DOM-ID injection with defaults `{ dropZone: 'dropZone', fileInput: 'fileInput' }`). Engine/clock held as non-reactive `_engine`/`_clock`. `beforeUnmount()` cleanup order (memory-management.md): `engine.dispose()` → `fileLoader.release()` → remove drop/visibility listeners → clear error/toast timers.

**Template essentials (`index.html`):** drop zone (`dragover`/`drop` + Browse `<button>` opening hidden `<input type="file" accept="audio/*" id="fileInput">`); file row (truncated name + `title`, duration, KB-2); controls group with `:title` lock hint (U-12); `<input type="number" id="bpmInput" min="30" max="250" step="1">` + ± stepper buttons; offset `<input type="range" id="offsetScrubber" :max="duration" step="0.1" :disabled="isParamLocked" :tabindex="isParamLocked ? -1 : 0" aria-label="Start offset">` + `<input type="text" id="offsetInput">` (Enter/blur commit); count-in number input (min 1 max 16); `<button id="playStopBtn">` (label Play/Stop), `<button id="restartBtn" :disabled="!isSequenceRunning">`, `<button id="previewBtn" :disabled="appState !== 'ready'">`; 4 beat dots (dot 1 larger + `beat-dot--downbeat`, row `aria-hidden`, `data-beat` hook); progress bar with offset marker + `aria-label` (B-04); `<div role="status" aria-live="polite" class="sr-only">{{ announcement }}</div>`; `<div role="alert" v-if="errorMessage">`.

---

## Phase 1: Scaffold (P1)

**TDD workflow:** start with 2–3 P0 scenarios (failing test → minimal code → run), then continue in small batches — don't write the full suite before the first green run.

### Overview
Static UI shell that renders all states, with the repo's standard entry pattern. No audio yet.

### Changes Required:
- `index.html` — CDN scripts (vue.global.js, howler.min.js 2.2.3, shared `../src/css/variables.css` + `../src/css/Style.css` + `./Style.css`, `../src/js/themeSwitcher.js`), `#app` template with all regions (drop zone, file row, controls, dots, progress, live regions) driven by `appState`.
- `Style.css` — layout, drop zone hero, beat dot base styles, reduced-motion variant hook.
- `MyESModules/App/createMetronomad{App,Data,Methods,Lifecycle}.js` — stubs (data only: `appState: 'noFile'`, defaults bpm 120 / countIn 4 / offset 0); `MyESModules/index.js` barrel.
- `playwright.config.cjs` — per §3.4 config note.
- `test/e2e/smoke.spec.cjs` — page-load smoke.

### Success Criteria:
**Automated:**
- [ ] `npx playwright test` smoke passes: page loads at `http://localhost:8000/Metronomad/index.html` with zero console errors; `data-state=nofile`; drop zone visible; all controls present and disabled.
**Manual:**
- [ ] User confirms layout reads well: drop zone hero in no-file state; controls grouped and labeled.

## Phase 2: Pure Functions (P0)

**TDD workflow:** start with 2–3 P0 scenarios (failing test → minimal code → run), then continue in small batches — don't write the full suite before the first green run.

### Overview
All timing/formatting/clamping math, fully unit-tested. No browser APIs touched.

### Changes Required:
- `MyESModules/Utils/{beatGrid,timeFormat,paramClamps}.js` — implement T-01…T-34; every function leads with `Number.isFinite` guards (skill convention).
- Barrel updates; `MyComponents/TimingMathTest.html` (Mocha+Chai CDN page, `mocha.run()` after all describes).
- `scripts/run-tests.cjs` — adapted from `CollageMaker/scripts/run-tests.js` (`BASE_DIR` → Metronomad, `SERVER_ROOT` unchanged; same check-server-then-run behavior).

### Success Criteria:
**Automated:**
- [ ] `node scripts/run-tests.cjs` — all 34 T-scenarios pass.
**Manual:** none (pure math).

## Phase 3: File Loading (P0)

**TDD workflow:** start with 2–3 P0 scenarios (failing test → minimal code → run), then continue in small batches — don't write the full suite before the first green run.

### Overview
Drop/browse → decode → Ready, with all error paths and the memory lifecycle.

### Changes Required:
- `MyESModules/Audio/{howlerSetup,codecSupport}.js` (H-01, H-02); `MyESModules/File/fileLoader.js` (F-01…F-09).
- Vue wiring: drop/browse handlers, "Decoding [name]…" state, Error overlay (U-14…U-16, U-20, V-05), filename truncation (U-21).
- `MyComponents/FileLoaderTest.html` — real `File` objects from base64 for the happy path; spy File for the codec-skip path; mocked `decodeAudioData` rejection only for F-04 (mock only the untriggerable error path, per skill guidance); `window.Howler` stubbed for H-01.

### Success Criteria:
**Automated:**
- [ ] F-01…F-09, H-01, H-02 pass via `node scripts/run-tests.cjs`.
- [ ] No unrevokeable object URL on any exit path (F-05 spy assertions).
**Manual:**
- [ ] User drops a real mp3 → Ready + duration shown; a garbage file → friendly decode error, app usable; a >30-min file → too-long error; (Safari) an .ogg → friendly codec error.

## Phase 4: PlaybackEngine (P0)

**TDD workflow:** start with 2–3 P0 scenarios (failing test → minimal code → run), then continue in small batches — don't write the full suite before the first green run.

### Overview
The core: lookahead scheduler, generation counter, state machine, interrupt watch, preview — all deterministic under injected fakes.

### Changes Required:
- `MyESModules/Playback/playbackEngine.js` (P-01…P-14, D4/D5/D6/D10); `MyESModules/Audio/clickBuffers.js` (H-03, D7).
- `MyComponents/PlaybackEngineTest.html` — `fakeAudioContext` (`createBufferSource() → fakeSource`, `currentTime`, `state`, `resume()`), `fakeClock`, `fakeRAF` helpers in-page; fake sources record `{ when, offset, duration, stopped, ended() }` and connect calls (P-14).

### Success Criteria:
**Automated:**
- [ ] All P-01…P-14 + H-03 pass with **zero real AudioContext instantiated**.
- [ ] Mash test (P-03) and stale-onended (P-04) pass — these are the atomicity gate.
**Manual:** none yet (engine has no UI).

## Phase 5: UI Integration — Play/Stop/Restart/Preview (P0)

**TDD workflow:** start with 2–3 P0 scenarios (failing test → minimal code → run), then continue in small batches — don't write the full suite before the first green run.

### Overview
Wire engine ↔ Vue: the full core workflow with real audio. **P0 acceptance gate.**

### Changes Required:
- `createMetronomadMethods.js` real handlers (V-01…V-07); `createMetronomadData.js` (decoding flag, errorMessage, announcement); `createMetronomadLifecycle.js` (mounted/beforeUnmount per wiring note); template finalization (lock hints, focus return, drop rejection U-13).
- `MyComponents/UiHandlersTest.html` — mock-VM pattern (spread factory methods first, override spies).

### Success Criteria:
**Automated:**
- [ ] V-01…V-07 pass; full unit suite green.
**Manual (first real-audio moment):**
- [ ] U-01…U-09 with a real multi-minute song: count-in lands in tempo; song starts exactly at the offset on the downbeat (listen + watch dots + progress reads the offset at the flip); Stop kills all sound immediately (no phantom clicks); Restart re-counts; Preview works and preserves offset.

## Phase 6: Beat Dots, Progress, Clock Hygiene (P1)

**TDD workflow:** start with 2–3 P0 scenarios (failing test → minimal code → run), then continue in small batches — don't write the full suite before the first green run.

### Overview
Visual beat reference + progress + the visibility/reduced-motion behaviors.

### Changes Required:
- `MyESModules/App/createBeatDots.js` (B-01…B-05, D9); `Style.css` (pulse + `prefers-reduced-motion` static variant, U-22); template (dots, progress bar, offset marker, aria-labels B-04).
- `MyComponents/BeatDotsTest.html` — RAF mock + `matchMedia` stub.

### Success Criteria:
**Automated:**
- [ ] B-01…B-05 pass; full suite green.
**Manual:**
- [ ] U-17: tab switch mid-play → dots snap to correct beat, no drift; U-22 reduced motion; dots visually lockstep with clicks at 120 and 250 BPM.

## Phase 7: E2E Suite (P0/P1)

**TDD workflow:** start with 2–3 P0 scenarios (failing test → minimal code → run), then continue in small batches — don't write the full suite before the first green run.

### Overview
End-to-end verification with the synthesized fixture; timing asserted with tolerance via the data-state/data-beat hooks.

### Changes Required:
- `test/fixtures/sine3s.mp3` (decode the base64 from `_agent_docs/research/howler-research-test.html` — one-off, no tooling); `test/fixtures/bad.mp3` (text bytes, tiny).
- `test/e2e/playback.spec.cjs` (E2E-1.1…1.8), `test/e2e/errors.spec.cjs` (E2E-2.1…2.4) per §3.4.
- Add the `data-state` (body) and `data-beat` (dot row) hooks to the template if not already present (KB-6).

### Success Criteria:
**Automated:**
- [ ] `npx playwright test` — all 12 E2E scenarios pass, 2 consecutive runs green (timing tolerances stable).
**Manual:** none (E2E covers the automatable slice).

## Phase 8: Docs, Site Link, Final Acceptance (P1)

**TDD workflow:** start with 2–3 P0 scenarios (failing test → minimal code → run), then continue in small batches — don't write the full suite before the first green run.

### Overview
Make the project discoverable and self-documenting; run the final acceptance pass.

### Changes Required:
- **Root `index.html`** — add a `project-card` (verified pattern: `card-icon` with material icon e.g. `music_note`, `card-title` "Metronomad", one-paragraph `card-description` — count-in metronome + exact downbeat song start, all in-browser — and `<a href="Metronomad/index.html" class="launch-button">Launch</a>`), placed with the other project cards.
- **`Metronomad/AGENTS.md`** — outline: 1-line purpose; Architecture (static, no build step; Howler for context/codecs/unlock, raw Web Audio lookahead scheduler — no Tone.js); directory tree; Running (`bash start-server.sh` → `http://localhost:8000/Metronomad/index.html`); Testing (`node scripts/run-tests.cjs`; `npx playwright test`); Conventions (named exports, factories, no `waitForTimeout` — assert state + tolerance; audio never asserted by ear in E2E); `_agent_docs/` pointers; `Co-Authored-By: LittleLight <noreply@traveler.dstny>` commit convention.
- Final: run world-review on the completed P1 test files per the skill's Feature Development Workflow (last quality gate).

### Success Criteria:
**Automated:**
- [ ] Full unit + E2E suite green from a clean server start.
**Manual (acceptance checklist):**
1. Load a real multi-minute mp3 via drag *and* Browse
2. Scrub + direct offset entry agree
3. Preview confirms entry and preserves offset
4. Clicks crisp; accent clearly higher-pitched
5. Song lands on the downbeat with the dots (listen + watch)
6. Stop/Restart mid-count-in and mid-song — no phantom audio
7. Parameters locked while running; hint visible
8. Ended → Ready, position reset to offset
9. Garbage file → friendly message, app usable
10. Full keyboard pass + live-region announcements
11. Reduced-motion safe
12. Zero console errors
13. 30-minute guard message on an oversized file

---

## Testing Strategy

- **Unit (Mocha/Chai, in-browser via `MyComponents/*Test.html` + `scripts/run-tests.cjs`):** all pure functions (T-01…T-34) and the engine under injected clock/RAF/timers (state machine, generation counter D4, 30-min guard D3, preview clamp D2, lookahead order P-08, stop/start atomicity P-03/P-04, graph wiring P-14). Table-driven clamp/parse cases; 1–3 assertions per scenario. The engine tests instantiate **no real AudioContext** — deterministic and fast.
- **E2E (Playwright, chromium only):** the 12 scenarios in §3.4 — thin; assert state, UI, and wall-clock timing with tolerance; **never listen to audio**.
- **Manual:** real-audio qualities only — accent audibility, downbeat exactness, click crispness, drag-drop feel, reduced motion, keyboard/screen-reader pass (Phase 8 checklist).
- **Fixtures:** one 3 s sine MP3 for everything; the >30-min and decode-failure long-file cases exist only as unit fakes (no large repo artifacts).

## Performance Considerations

- **Decode:** `decodeAudioData` of a few-minute MP3 ≈ 100–500 ms on modern hardware; the `decoding` flag covers it; Play disabled meanwhile.
- **Memory:** float32 PCM at 44.1 kHz stereo ≈ 21.1 MB/min (3 min ≈ 64 MB; 10 min ≈ 211 MB; 30-min guard caps ≈ 635 MB, D3). Exactly one decoded buffer live at a time; references nulled + sources stopped on replacement (F-05, KB-7). Practical guidance for mobile users: songs ≤ ~10 min are comfortable.
- **Per-frame:** one RAF loop (only while audio runs) updates ≤ 5 dot classes + progress text (re-render text only when the tenth-second changes); scheduler `setInterval` 25 ms runs only during a sequence; 250 ms context watch (D10) cleared when idle; all timers/RAF cancelled on Stop/Ended/unmount (B-05).

## Known Behaviors (intentional design decisions)

1. **KB-1 — No lead-time floor (D1).** At 250 BPM the first click comes 0.24 s after the press. This is the spec's timing law, not a bug. Users who want more preparation use a longer count-in.
2. **KB-2 — Long filenames truncate** with ellipsis; full name in `title` (U-21).
3. **KB-3 — Errors are non-blocking overlays (D8).** The app stays in its last valid state after a failed load; a successful later load clears the error (U-16).
4. **KB-4 — Ended is not a resting state (D8).** Song end returns to Ready with position reset to the offset (spec §9).
5. **KB-5 — Preview locks parameters but not Restart (V-06).** Any running audio locks BPM/offset/count-in; Restart is only enabled during a count-in/song sequence (spec §6); the Play↔Stop toggle shows **Stop** during preview and stops the preview (U-09).
6. **KB-6 — Testability hooks.** `document.body[data-state]` and the dot row's `data-beat` are intentional minimal hooks for E2E assertions; they carry no styling and no ARIA.
7. **KB-7 — 30-minute duration guard (D3)** fires *after* decode (duration is only known post-decode). The friendly error is "Song too long — maximum length is 30 minutes". Pre-decode file-size heuristics are explicitly out of scope.
8. **KB-8 — Click pitch** 1568 Hz (accent) / 1047 Hz (regular) is fixed in v1 (no custom click sounds — spec §12).
9. **KB-9 — No Tone.js (D6).** The lookahead scheduler is ~60 lines of hand-rolled code on the repo's dependency-free pattern; Tone.js remains a post-v1 option if transport needs grow (looping, re-count-in).

## References

- Spec: `_agent_docs/specifications/metronomad-v1-specification.md`
- Research: `_agent_docs/research/howlerjs-research.md` (incl. pitfalls §5 and format matrix §6)
- Research harness: `_agent_docs/research/howler-research-test.html` (fixture source, D11)
- Skill: `.pi/skills/building-web-apps/SKILL.md` (project skill, symlinked) — key references used:
  - `references/midiestro-pattern.md` — entry point + directory structure pattern
  - `references/vue-options-api.md` — Options API factory decomposition, input patterns
  - `references/es-modules.md` — named exports + barrel conventions
  - `references/testing-unit.md` — Mocha/Chai in-browser pages, mock-VM construction, RAF mocking
  - `references/testing-e2e.md` — Playwright wait conventions, event testing
  - `references/testing-strategy.md` — assertion density, `waitForTimeout` fragility, deferred-test rules
  - `references/memory-management.md` — object URL revocation, lifecycle cleanup ordering
  - `references/accessibility.md` — ARIA live regions, reduced motion, focus management
- Reference implementation: `CollageMaker/` (index.html, MyESModules/, MyComponents/, test/e2e/, playwright.config.cjs, scripts/run-tests.js)
- Site integration: `~/workspace/austin183.github.io/index.html` (project-card pattern)

