# Review-Fix Plan — Behavior Specifications

Legend: **P0** shippable gate · **P1** structural correctness · **P2** polish. Scenarios are the contract for `build-tdd` — each maps to a failing test first. This file is the authoritative, complete set **for this plan's scenarios only**: new rows (`R-*`) and the amended versions of v1 rows (U-11, U-13, U-09, P-12, P-13, B-05, B-06, T-35). All other v1 scenarios stay canonical in `_agent_docs/plans/2026-08-17-metronomad-v1/behavior-specs.md` and are unchanged by this plan. Phase files inline the scenarios they own; this file is the canonical copy for the rows below.

## 1. Parameter Entry (C-1 — RD-1)

**Amended U-11 (supersedes the v1 U-11 row; the v1 file's row is updated in Phase 1 to point here):**

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| U-11 (rev) | P0 | Ready | User types "999" in BPM and commits (Enter/blur) | Clamps to 250, field shows "250", hint "BPM limited to 30–250"; "10" → 30; non-numeric/empty on commit restores the previous valid value into field and model; stepper buttons change the model by ±1 **and** sync the field |

**New per-keystroke rows (the regression class that let C-1 slip):**

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| R-C1.1 | P0 | Ready, BPM 120, field "120" (unit, mock-VM) | `bpmText` set to `'9'` then `'90'` then `'190'` (simulated keystrokes; no commit) | `this.bpm` **unchanged (120)** after every keystroke; no hint shown; only on `commitBpmEntry()` does the model move (190, no clamp) |
| R-C1.2 | P0 | Ready, count-in 4, field "4" | Type "16" over it keystroke-by-keystroke, then commit | Model stays 4 until commit → 16; typing "1" over "4" (field "1") and blurring commits 1 (valid) — no accidental restore of 4 (the v1 failure shape) |
| R-C1.3 | P0 | Ready, field cleared to `''` mid-entry | Blur (commit) with empty field | Model + field restore last valid (120 / 4); no hint |
| R-C1.4 | P1 | Ready, BPM 250 via stepper (+ pressed from 249) | Observe field | Field shows "250" (stepper synced the draft — no divergence in either direction) |
| R-C1.5 | P1 | Ready, count-in committed "99" | Commit | Clamps to 16, field "16", hint "Count-in limited to 1–16" shown (N-20) |

**E2E (the review's live-repro path, per-keystroke — `pressSequentially`, never `fill()`):**

| ID | Test | Steps | Expected |
|----|------|-------|----------|
| E2E-R-C1.1 | BPM typeable per-keystroke | Load fixture; triple-click `#bpmInput` (select-all); `pressSequentially('90')`; press Enter | Field shows "90"; Play → sequence runs at 90 BPM (click spacing ≈ 0.667 s via in-page logger); no `2500`-style divergence at any point (assert field text after each keystroke batch) |

*Hook note:* no new data hooks — the field's own text is the assertion surface (it is what the user sees; KB-6 stays minimal).

## 2. File Loading (I-1, I-2 — RD-2/RD-3)

**Amended U-13 (supersedes v1 U-13; v1 file row updated in Phase 1):**

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| U-13 (rev) | P0 | Playing | User drops another file **or** uses Browse (pick a file) | Rejected with "Drop a new song after stopping" (drop) / Browse button is **disabled** during playback (no picker opens); the playing song is unaffected — engine keeps its buffer, UI position/fill/`aria-valuemax` never reference the new file. After Stop, the same drop is accepted: Ready with new file; old buffer reference dropped and old object URL revoked |

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| R-I1.1 | P0 | `playing` (unit, mock-VM) | `onBrowseClick()` path is moot (button disabled); call `onFileDropped(file)` directly with a valid file | `loader.loadFile` **never called**; `errorMessage` = "Drop a new song after stopping"; `appState` unchanged |
| R-I1.2 | P1 | E2E: `playing` | Observe `#browseBtn` | `disabled` attribute present (and `#dropZone` drop still shows the rejection message — existing E2E-2.2 behavior preserved) |
| R-I2.1 | P0 | `decoding.active === true` (unit, mock-VM with a loadFile spy that never settles) | Second `onFileDropped(otherFile)` | Second `loadFile` **never called**; first load's continuation still wins (on resolve: `appState` ready with the *first* file; `decoding` false exactly once) |
| R-I2.2 | P1 | First `loadFile` pending (spy, controllable) | Fire a second drop (rejected) while pending, then resolve the first | `decoding.active` is `true` until the first resolves, then `false` — **Play is never enabled mid-decode** (the flag-lie the review names) |
| R-I2.3 | P0 | Unit: two `loadFile` calls truly concurrent at the **loader** level is now impossible from the app — pin the choke point instead | `onFileDropped(a)` (pending) → `onFileDropped(b)` → settle `a` | Exactly one buffer in `this._buffer` (a's); b's decode never started; the "exactly one decoded buffer live" invariant holds (F-05 contract unchanged) |

## 3. Engine Boundary (I-3 — RD-4)

**Amended P-13 (extends v1 P-13; v1 file row updated in Phase 1):**

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| P-13 (rev) | P0 | Invalid params | `startSequence({ bpm: 0 })` / `({ countInBeats: 17 })` / `({ offset: -1 })` / `({ offset: 3.0 })` with a 3.0 s buffer / `({ offset: 3.0001 })` | All return `{ ok: false }`; no sources created; state unchanged. `preview({ buffer, offset: 3.0 })` on the 3.0 s buffer → `{ ok: false }` (existing D2 guard, now asserted explicitly) |

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| T-35 | P0 | `clampOffset(2.96, 2.96)` (duration that quantizes up) | Call | `2.9` (quantize-then-reclamp — never `> duration`); `clampOffset(2.94, 2.96)` → `2.9`; `clampOffset(3.0, 2.96)` → `2.9`. T-31/T-33/T-34 outputs unchanged |

## 4. Preview Stop (I-4 — RD-5)

**Amended U-09 (supersedes v1 U-09; v1 file row updated in Phase 1):**

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| U-09 (rev) | P1 | Preview playing | User presses Stop | Audio stops within 50 ms; dots + progress reset to the offset marker; offset preserved; announced **"Preview stopped"** (both stop paths now announce identically) |

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| R-I4.1 | P1 | Unit (mock-VM): `isPreviewing === true` | `onEngineStateChange('stopped')` | `announcement` = "Preview stopped"; `isPreviewing` false; `appState` ready |
| R-I4.2 | P1 | Unit (engine, fake context/clock): `preview()` running | `stop()` | Sources stopped, timers cleared, events exactly `['preview', 'stopped']` — **never** `previewEnded`; then firing the stale preview source's `onended` is ignored (state stays stopped, no further events) |
| R-I4.3 | P1 | Unit (mock-VM): normal sequence, `isPreviewing === false` | `onEngineStateChange('stopped')` | `announcement` = "Stopped" (regression: the non-preview path untouched) |

## 5. Test Runner (I-9)

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| R-I9.1 | P0 | A test page that loads Mocha but registers **zero** tests (scratch page for the verification step) | `node scripts/run-tests.cjs` | **Non-zero exit** with a per-file error naming the file ("0 tests") — never a green `passes: 0, failures: 0` line |
| R-I9.2 | P0 | Mocha CDN unavailable (simulate: page with `#mocha` present but `mocha._runner` undefined and no `.passes`/`.failures` elements) | `node scripts/run-tests.cjs` | Non-zero exit; error names the file and the missing runner |
| R-I9.3 | P1 | `run-tests.cjs` invoked from an arbitrary cwd | Run | Works (paths derived from `path.resolve(__dirname, '..')`, not hardcoded `BASE_DIR`/`SERVER_ROOT`); the runner's own `python3 -m http.server` spawn is removed in favor of the user-started server on :8000 (AGENTS.md rule) |

## 6. Visual-Clock Ownership & DI (I-5…I-8, N-17 — RD-6)

**Retired P-12:** the v1 P-12 row (engine `stopVisualClock`/`onFrame`) is **deleted**, not amended — the capability it pinned no longer exists. Its observable content (phase law per frame, RAF cancel on stop) is already pinned by B-01/B-02 against the app's real loop. The v1 file's P-12 row is struck through with a pointer in Phase 2.

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| R-I5.1 | P1 | Unit (engine) | `createPlaybackEngine(...)` with no visual-clock params | No `onFrame` parameter exists; returned object has **no** `startVisualClock`/`stopVisualClock` keys; `getBeatGrid`/`songPosition` intact; `_teardown`/`dispose` make no RAF calls (fake-RAF collector stays empty) |
| R-I6.1 | P1 | Unit (beatDots): all visual timers running, engine spy with `dispose` recorder | `stopAll()` | RAF cancelled, `matchMedia` listener removed, dot classes cleared, `_stopped` set — and **`engine.dispose` never called** |
| R-I6.2 | P1 | Unit (lifecycle, mock-VM with real `createMetronomadLifecycle`, engine/loader/beatDots spies) | `beforeUnmount()` | Order (spied): listener removal → `stopAll` → `engine.dispose()` → `fileLoader.release()`; each exactly once; the `else if` fallback path covered by a variant with `_beatDots` absent → `dispose` still called |
| R-I7.1 | P1 | Unit (beatDots): injected `raf`/`cancelRaf`/`matchMedia`/`isPageHidden` fakes; **no** global patching in the suite | Full B-01…B-05 behavior re-run via injection | All existing B-suite assertions pass with zero `window.*`/`document.*` monkey-patching in `BeatDotsTest.html` (the save/restore boilerplate is deleted) |
| R-I8.1 | P1 | `Utils/beatGrid.js` | Import | `BEATS_PER_BAR === 4` exported; accent rule `k % BEATS_PER_BAR === 1` (T-04/T-09/T-31-v1 accent expectations unchanged); `createBeatDots` derives `DOT_COUNT` from it; template `v-for` + `beat-dot--downbeat` bind to the `beatsPerBar` data property (E2E-1.8 still green: 4 dots, dot 1 downbeat) |
| B-05 (rev) | P1 | All visual timers running | `stopAll()` (called from `beforeUnmount`) | Cancels RAF + matchMedia listener, clears dot state — no leaks after unmount; **no engine access of any kind** (supersedes v1 B-05; v1 row updated in Phase 2) |
| B-06 (new) | P1 | See R-I6.2 | Lifecycle unmount ordering | Engine `dispose` called by the lifecycle, not the visualizer (lifecycle-level pin) |

## Priority Ordering

| Priority | Scenarios | Rationale |
|----------|-----------|-----------|
| **P0** | U-11 (rev), R-C1.1…R-C1.3, E2E-R-C1.1 · U-13 (rev), R-I1.1, R-I2.1, R-I2.3 · P-13 (rev), T-35 · R-I9.1, R-I9.2 | The shippable gate: typing works, one buffer live, no count-in-into-silence, no false-green CI |
| **P1** | R-C1.4, R-C1.5 · R-I1.2, R-I2.2 · U-09 (rev), R-I4.1…R-I4.3 · R-I9.3 · R-I5.1, R-I6.1, R-I6.2, R-I7.1, R-I8.1, B-05 (rev), B-06 | Structural correctness, DI symmetry, ownership, docs integrity |
| **P2** | Phase 3 rows below | Scoped 2026-08-22 — one row per "Do" nit with testable behavior |

## 7. Phase 3 — Nit Backlog (scoped 2026-08-22)

Scoping decisions recorded here and in the per-item `phase-3-N-*.md` files: N-11, N-29…N-31 deferred (OD-2 defaults); N-6 and N-15 carry no new rows (N-6's behavior is already pinned by P-04/P-06/P-07 — refactor-only; N-15 is a template-only attribute deletion pinned by the existing keyboard E2E); N-2/N-32/N-33/N-24 are docs items verified by reading (KB entries present in the v1 `context.md`).

**Batch A — engine / fileLoader:**

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| R-N1.1 | P2 | countingIn, all clicks scheduled, clock < songStart | Advance clock past songStart + one scheduler tick | State `playing`; the scheduler interval is **cleared** (only the watch interval remains); further scheduler ticks create no sources and emit nothing |
| R-N3.1 | P2 | Valid file (real MP3, real context) | `loadFile` | Resolves `{ ok, buffer, duration, fileName }` with **no `objectUrl` property**; `URL.createObjectURL` is called **zero** times on every path (success, decode failure, tooLong, release) — contract collapsed to "exactly one decoded buffer live" |
| R-N3.2 | P2 | `extractExt` removed from the public API | `loader.extractExt` | `undefined`; extension behavior stays pinned via the codec message — `'archive.tar.gz'` → ".gz files", extensionless → unrecognized-type message (F-07) |
| R-N4.1 | P2 | `startSequence` ok | Read `result.schedule`; attempt to mutate it | The returned schedule is a **frozen snapshot** (`Object.isFrozen` true; writes throw `TypeError` in strict mode) — the engine's internal sequence (with its `scheduled` flags) is not exposed live; the engine still schedules every click after the view was snapshotted |
| R-N5.1 | P2 | `maxDurationSec: 3600` (injectable) | `tooLong` result | `message` = "Song too long — maximum length is 60 minutes" (value interpolated); the default (1800 s) still yields "30 minutes" (U-20/KB-7 string unchanged) |
| R-N7.1 | P2 | Imports from `playbackEngine.js` | `ENGINE_EVENTS` | `deep.equal({ ENDED: 'ended', PREVIEW_ENDED: 'previewEnded' })`; the engine emits through it and `createMetronomadMethods` switches on the constants (V-07 event-string behavior unchanged) |

**Batch B — app / template:**

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| R-N8.1 | P2 | playing, `errorMessage` = "Drop a new song after stopping" | `onPlayToggle` (stop path) | `engine.stop()` called; `errorMessage` cleared — the condition that produced it (the lock) is gone |
| R-N8.2 | P2 | ready, `errorMessage` = "Audio is blocked by the browser — tap again to enable sound" | `onPlayToggle` with a running context → `startSequence` ok | `errorMessage` cleared — the tap that works removes its own error (no new strings) |
| R-N8.3 | P2 | stale `errorMessage` from a failed start/restart/preview | A subsequent **successful** `onRestart` / `onPreview` / start | `errorMessage` cleared on each ok path |
| R-N9.1 | P2 | beatDots loop running, grid interval constant across frames | Flush N frames | `style.setProperty('--beat-interval', …)` called **once per distinct interval value**, not per frame; a tempo change (new interval) triggers the next set; the cache resets on stop so a new sequence re-applies |
| B-04 (rev) | P2 | `songPosition 1.5, duration 3.0, offset 1.0` | Render | Fill `50%`; marker `33.333%`; progressbar `aria-label` is the **static** "Song progress" (no per-position churn); `aria-valuetext` = "0:01.5" (supersedes the v1 B-04 aria-label clause; the v1 row is updated at scope time) |
| R-N12.1 | P2 | countingIn or playing, restart ok | `onRestart` | `announcement` = "Count-in restarted" (V-07 string inventory +1 — restart always restarts the count-in, so the string is true in both states) |
| R-N13.1 | P2 | `isDragOver` true | `onDragLeave` with `relatedTarget` inside the drop zone | `isDragOver` stays true (child crossing is not a leave); `relatedTarget` outside (or absent) → false. (The review's `pointer-events: none` option is rejected for this markup — it would disable the Browse button, which is a child.) |
| R-N14.1 | P2 | suspended context, resume promise pending | `_engine` nulled (unmount) before resume settles; `onPlayToggle` completes | No `startSequence` call, no `errorMessage`, no throw — post-`await` guard |

**Batch C — docs (verified by reading, no tests):** N-2 → KB-11 (background-tab interval throttling compresses a count-in; song start stays exact; the >50 ms click skip is deferred as a behavior change) · N-32 → KB-12 (high-BPM / count-in-1 live-region coalescing is accepted AT behavior) · N-33 → KB-13 (backgrounded tab keeps audio playing — intended, do not "fix") · N-24 → U-18 row in the v1 `behavior-specs.md` gains the scoping note (unit-adequate via P-11 + V-07; the `ctx.suspend()` E2E variant dropped — headless suspend quirks).

**Batch D — test quality:**

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| R-N25.1 | P2 | UiHandlers real-timer resume test | Run | The elapsed bound is asserted against `SCHEDULER.RESUME_TIMEOUT_MS` (imported constant), not a hardcoded 700 |
| R-N26.1 | P2 | E2E-1.3 (stop during count-in) | Run | The stop-time bound is the **grid-law flip** (t0 + 1500 ms) — `actionT < flipAt` — not the self-imposed 450 ms (the review's "playing.t" cannot exist in this test: a successful count-in stop never reaches `playing`; the grid-law time is its proxy) |
| R-N27.1 | P2 | locked, `playStopBtn.disabled === true` | `onPlayToggle` (stop path) | The button is **not** focused (the "never focus a disabled button" branch) |
