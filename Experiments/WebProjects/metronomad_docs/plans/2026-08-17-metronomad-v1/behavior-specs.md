# Metronomad v1 — Behavior Specifications

Legend: **P0** core behavior · **P1** structural correctness · **P2** polish. Scenarios are the contract for `build-tdd` — each maps to failing tests first. Phase files inline the scenarios they own; this file is the authoritative, complete set.

## 3.1 User Behavior (end-to-end)

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
| U-11 | P0 | Ready | User types "999" in BPM and commits (Enter/blur) | Clamps to 250, field shows "250", hint "BPM limited to 30–250"; "10" → 30; non-numeric/empty **on commit** restores the previous valid value into field and model; stepper buttons change the model by ±1 **and sync the field**. **Amended by the review-fix plan (C-1/RD-1): commit-on-Enter/blur with a v-model draft, per-keystroke clamp deleted** — canonical rows (U-11 rev, R-C1.1…R-C1.5, E2E-R-C1.1) live in `_agent_docs/plans/2026-08-22-address-v1-review/behavior-specs.md` §1 |
| U-12 | P1 | Counting in (or Playing) | User tries to change BPM / offset / count-in | All three controls disabled **and unfocusable** (Tab skips them), group shows a subtle "locked until next Play" hint; after Stop, new values are used on the next Play |
| U-13 | P1 | Playing | User drops another file on the zone | Drop rejected with "Drop a new song after stopping"; the playing song is unaffected. After Stop, the same drop is accepted: state Ready with new file; old buffer reference dropped and old object URL revoked |
| U-14 | P0 | No-file state | User drops `track.ogg` | In Chromium (supported): proceeds to decode. In Safari (unsupported; manual): Error "This browser can't play .ogg files", stays No-file (Play disabled), announced |
| U-15 | P0 | No-file state | User drops a corrupt/garbage `broken.mp3` | Error "Couldn't decode broken.mp3 — the file may be corrupted"; state remains No-file; Play disabled; announced; **no cryptic DOMException text shown** |
| U-16 | P1 | A file failed to decode (error showing) | User drops a valid `song.mp3` | Prior error cleared; new file loads normally to Ready |
| U-17 | P1 | Playing | User switches tabs ≥ 5 s and returns | Beat dots instantly on the correct beat (recomputed from the audio clock — no stutter, no drift); progress continuous |
| U-18 | P1 | Playing | OS interrupts audio (context → `interrupted`/`suspended`) | App stops the sequence, returns to Ready, announces "Audio was interrupted — press Play to try again". **Scoping note (2026-08-22 review N-24): unit-adequate** — the self-stop + announcement contract is pinned by P-11 (engine watch) + V-07 (app mapping); the `ctx.suspend()` E2E variant is **dropped** — headless Chromium autoplay-policy contexts do not reliably enter `suspended` on demand |
| U-19 | P1 | Ready, context blocked (Safari-like) | User presses Play and `ctx.resume()` never reaches "running" | After ~750 ms: error "Audio is blocked by the browser — tap again to enable sound", app returns to Ready (button is not dead) |
| U-20 | P1 | Ready | User drops a 40-minute file | Decode completes, guard fires: error "Song too long — maximum length is 30 minutes"; state No-file; buffer discarded, URL revoked |
| U-21 | P2 | Ready, 34-character filename | Rendered | Name truncated with ellipsis; full name available via `title` tooltip |
| U-22 | P2 | `prefers-reduced-motion: reduce` | Playing | Beat dots use a static highlight (no pulse animation) |
| U-23 | P1 | Playing | User Tabs through the page | Scrubber is not focusable; Play/Stop, Restart, Preview, BPM, count-in reachable in sensible order; all operable by keyboard |

## 3.2 Component Behavior (module contracts)

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
| ~~P-12~~ | ~~P1~~ | ~~Visual clock running~~ | ~~`stopVisualClock()`~~ | **RETIRED (2026-08-22, review-fix I-5/RD-6):** the engine's visual clock was removed — the capability no longer exists. Its observable content (phase law per frame, RAF cancel on stop) is pinned by B-01/B-02 against the app's real loop. See `_agent_docs/plans/2026-08-22-address-v1-review/behavior-specs.md` §6 (retirement note) |
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
| B-05 (rev) | P1 | All visual timers running | `stopAll()` (called from `beforeUnmount`) | Cancels RAF + matchMedia listener, clears dot state — no leaks after unmount; **no engine access of any kind** (supersedes the original B-05, amended in Phase 2 — canonical text in `_agent_docs/plans/2026-08-22-address-v1-review/behavior-specs.md` §6; engine dispose is owned by the lifecycle, see B-06 there) |

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

## 3.3 Pure Function Behavior (input/output pairs)

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
| T-08 | `beatPhaseFromGrid(101.75, 100.5, 0.5)` | `{ beatIndex: 2, inBeat: 0.5 }` (the v1 table's `102.75` was internally inconsistent with its own output — the tests corrected it; the table is the truth again) |
| T-09 | `beatPhaseFromGrid(100.49, 100.5, 0.5)` (before first beat) | `{ beatIndex: -1, inBeat: 0 }` — no dot lit during the lead beat |
| T-10 | `beatPhaseFromGrid(102.499, 100.5, 0.5)` | `{ beatIndex: 3, inBeat: 0.998 }` (floor, not round — no wrap to 0 until the true boundary; same correction as T-08) |
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

## 3.4 E2E Test Scenarios (Playwright, chromium)

**Fixture:** `test/fixtures/sine3s.mp3` — extracted from the research harness base64 (D11). Single fixture for all E2E.
**Config:** `Metronomad/playwright.config.cjs` mirrors CollageMaker's — chromium only, `baseURL: http://localhost:8000`, `workers: 1`, `timeout: 30000`, **no `webServer` block** (server started manually per repo rule), plus `use.launchOptions.args: ['--autoplay-policy=no-user-gesture-required']` for deterministic `AudioContext` state in headless.
**Waits (repo convention — no `waitForTimeout` for assertions):** the app exposes `document.body.dataset.state` = appState and `data-beat` on the beat-dot row (intentional testability hooks, KB-6). Assert with `expect`/`expect.poll`; capture `t0 = performance.now()` at the Play click and assert transition times within tolerance.

**`playback.spec.cjs`** — 3 s fixture, 120 BPM (beat = 0.5 s), **count-in 2** → clicks at +0.5 s / +1.0 s, song starts at t0+1.5 s (grid law: t_p+(N+1)·beat — T-04/P-01), song ends ≈ +3.0 s after the start (full lifecycle in ~4.5 s of wall time).

| ID | Test | Steps | Expected |
|----|------|-------|----------|
| E2E-1.1 | Load → ready | `setInputFiles('#fileInput', fixture)` | Filename "sine3s.mp3" + duration "0:03.0" visible; `data-state=ready`; Play enabled |
| E2E-1.2 | Full sequence timing | Set count-in 2 → click Play (t0) | `data-state=countingIn` within 300 ms of t0; data-beat shows "0" then "1" before the flip (zero-based lit dot — KB-6; "-1" during lead-in); `data-state=playing` at t0+1.5 s ± 0.3 s; live region "Song started"; progress advances past 0:01.0; `data-state=ready` ≈ 3.0 s after the playing flip ± 0.5 s; progress reset to offset; "Song ended" announced |
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
| E2E-2.3 | Clamps | Offset "9:59.9" → commit; offset "-1" → commit; BPM "999" / "10" | 0:03.0; 0:00.0; 250 / 30, each with clamp hint (the v1 table's "9:99.9" was invalid — T-22: seconds ≥ 60 is rejected; the test always used 9:59.9) |
| E2E-2.4 | Non-audio drop | Upload a `.txt` file | Stays `noFile`; no crash; console-error free |

*Note:* a true **codec-reject** E2E is not possible on chromium (it supports every common codec — verified in research §6); that path is covered by unit F-02 (spy) and manually on Safari (U-14).

## Priority Ordering

| Priority | Scenarios | Rationale |
|----------|-----------|-----------|
| **P0** | U-01…U-06, U-14, U-15 · F-01…F-05 · P-01…P-06 · H-01 · V-01, V-02, V-05 · T-04…T-07 (schedule math) · E2E-1.1…1.5, E2E-2.1, E2E-2.3 | Core value: file in, exact count-in out, atomic stop/restart, no leaks, friendly errors |
| **P1** | U-07, U-10…U-13, U-16…U-20, U-23 · F-06…F-08 · P-07…P-11, P-14 (P-12 retired) · H-02, H-03 · B-01, B-02, B-04, B-05 (rev) · V-03, V-04, V-06, V-07 · T-01…T-03, T-08…T-34 · E2E-1.6…1.8, E2E-2.2, E2E-2.4 | Structural correctness, UX safety, accessibility, resource hygiene |
| **P2** | U-09, U-21, U-22 · F-09 · P-13 · B-03 | Polish and edge cases |
