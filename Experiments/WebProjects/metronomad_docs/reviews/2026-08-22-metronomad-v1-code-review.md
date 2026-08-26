# Metronomad v1 — Full Code Review

**Date:** 2026-08-22
**Scope:** Complete v1 implementation of the plan at `_agent_docs/plans/2026-08-17-metronomad-v1/` (all 8 phases marked done).
**Method:** Six structured passes over the full source (~1,760 lines app + ~3,600 lines tests):

| Pass | Focus |
|------|-------|
| Architecture & SOLID | Module boundaries, data flow, coupling, DIP consistency, single-source-of-truth |
| Playback/audio core correctness | Scheduler, generation counter (D4), state machine, resource hygiene, Web Audio edge cases |
| Vue app layer + template | State consistency, lifecycle, a11y, template binding behavior |
| Test suite | Coverage matrix vs `behavior-specs.md`, determinism, flake risk, mock fidelity |
| Spec compliance & docs | Requirement-by-requirement vs the v1 spec, wording audit, AGENTS.md accuracy |
| World review (real-world systems/UX) | Mobile, offline, cross-browser, musician-workflow angles |

Plus direct verification by the reviewing agent: full unit suite re-run (127/127 green), full E2E re-run (21/21 green, 50.5 s), and live-browser repros of the top findings (see C-1).

**Baseline at review time:** server on :8000, `node scripts/run-tests.cjs` → 127/127; `npx playwright test` → 21/21. All scenario IDs T/F/P/H/B/V/E2E map to tests; matrix detail in §5.

---

## Verdict

**Request changes** — one CRITICAL user-facing defect (BPM typing is effectively broken; C-1) and nine IMPORTANT issues, several of which are small fixes. The core precision architecture (D4 generation counter, D5 single sample-accurate start, D9 pure-function beat phase, fileLoader URL lifecycle) is sound and withstood interleaving analysis; spec compliance is excellent (the three spec-prescribed live-region strings match verbatim; only two documented, acceptable deviations). The defects cluster in the **file-loading path** (lock/race gaps) and in **input handling that was unit-tested single-shot but never per-keystroke**.

Nothing here blocks the *timing* promise of the product. C-1 and I-1/I-2 are the ones to fix before anyone else uses the tool.

---

## CRITICAL

### C-1 — BPM (and to a lesser degree count-in) direct entry is broken by clamp-on-keystroke

**Location:** `index.html:63-66` (`:value="bpm"` + `@input="onBpmInput"`), `createMetronomadMethods.js:91-102` (`onBpmInput` clamps every keystroke and writes back `this.bpm`).

**What happens:** every partial entry below 30 clamps to 30, and Vue re-sets the DOM value mid-word. Human typing is destroyed:

Live repro (chromium, fixture loaded, triple-click select-all, per-keystroke input via Playwright):

| User intends | Field ends showing | Model (`this.bpm`) |
|---|---|---|
| `90` | `250` | 250 |
| `120` | **`2500`** | 250 |
| `250` | **`2500`** | 250 |

`2500` in the field with 250 in the model is a display/model divergence: Play uses 250 while the user sees 2500. In practice **no BPM value is typeable** — the ± steppers are the only reliable path, which defeats spec §4 "direct typing + ±1 steppers". Count-in (min 1) is mostly typeable but has the same failure shape (clearing restores 4; `16` typed over `4` works only by luck of caret position).

**Why the tests are green:** V-03 unit tests call `onBpmInput('251')` single-shot; E2E-2.3 uses Playwright `fill()`, which is one input event. U-11's own example ("types 999") only works as a single event. The per-keystroke path was never exercised anywhere.

**Note:** the clamp-on-input behavior is what U-11/V-03 pin, so this is a *design* consequence, not a typo — but the pinned behavior is unimplementable for real typing. The fix is a product decision plus a spec-scenario update.

**Fix:** adopt the pattern the offset field already uses and that works: local draft text (`bpmText` via `v-model`), commit + clamp only on Enter/blur via a `commitBpmEntry`, hint shown from the commit result. `onBpmInput` survives as the commit function's parse/clamp core. Same for count-in. Update U-11/V-03 to pin per-keystroke expectations (add a unit test that feeds `'9'` then `'0'` and expects the model untouched until commit — the exact regression that slipped through). Optionally also add one E2E that types a value keystroke-by-keystroke (`pressSequentially`) instead of `fill()`.

---

## IMPORTANT

### I-1 — Browse bypasses the drop-zone lock → UI/engine state contradiction mid-playback

**Location:** `createMetronomadMethods.js:44-53` (`onBrowseClick`/`onFileInputChange` — no lock check), `index.html:41` (`#browseBtn` has no `:disabled`), vs `onDrop` which does check `isParamLocked` (line 29).

Repro: Play → click **Browse…** → pick a file. Decode succeeds while the old song still plays; the success path then sets `appState = READY`, swaps `_buffer`, re-clamps `offset` to the *new* duration, and clears any error — while the engine keeps playing the *old* buffer. Result: Play button reads "Play" with audible music, progress fill/`aria-valuemax` (new duration) disagree with the engine's position (old buffer), and the controls unlock mid-song.

**Fix:** move the lock check into `onFileDropped` (covers drop *and* browse): `if (this.isParamLocked) { this.errorMessage = 'Drop a new song after stopping'; return; }`, and add `:disabled="isParamLocked"` (or at least visual dimming) on `#browseBtn` for feedback. E2E-2.2 currently only tests the drop path — extend it or add a browse variant.

### I-2 — Concurrent file loads race: loader and app can track different buffers; decoding flag lies

**Location:** `createMetronomadMethods.js:56-83` (no rejection while `decoding.active`), `fileLoader.js:52-91` (`releaseCurrent()` at resolve time; `finally` emits `'idle'` unconditionally).

The drop zone shows "Decoding …" (implying single-flight) but a second drop while decoding starts a concurrent `loadFile`. Consequences:

1. Whichever load *resolves second* wins the loader's `currentBuffer`/`currentUrl`, but the app's `_buffer`/`fileName` are whichever `onFileDropped` continuation runs last — they can diverge (UI shows song A, loader owns/revokes song B's URL). Breaks the "exactly one decoded buffer live" invariant.
2. The *earlier*-resolving load's `finally` emits `'idle'` while the later load is still decoding → `decoding` flag false → **Play enables mid-decode** with a stale buffer (a transient flag lie, self-healing when the second load settles).
3. Entirely untested (no concurrent-`loadFile` scenario in F-01…F-09).

**Fix (cheap and complete):** reject while a decode is in flight, at the top of `onFileDropped`: `if (this.decoding.active) return;` — safe because `loadFile` emits `'decoding'` synchronously before its first await (`fileLoader.js:52`), so the flag is visible to any subsequent drop event. Add a unit test pinning the rejection and one pinning the `decoding` flag staying true across a second (rejected) drop. (If concurrent loads are ever wanted, the loader needs an in-flight counter for the `'idle'` emit.)

### I-3 — `startSequence` accepts `offset ≥ buffer.duration`; UI can reach it → count-in into silence

**Location:** `playbackEngine.js:215-221` (validates `offset >= 0` only), `paramClamps.js:51-53` (`clampOffset` clamps *then* quantizes: `duration 2.96` → `3.0 > duration`), `index.html:74` (scrubber `:max="duration"` lets the slider sit at the end).

`source.start(when, offset)` with a past-the-end offset is spec-legal and yields a zero-sample source: user gets a full count-in, then **silence** at the downbeat, then `onended` → "Song ended" → back to ready. No crash, no frozen state (the `COUNTING_IN` branch in the song `onended` guarantees termination), but a confusing user-reachable dead end — and inconsistent with `preview()`, which *does* reject the same condition (`playbackEngine.js:277-279`, D2). Reachable with the E2E fixture itself: offset entry "0:03.0" on the 3 s sine.

**Fix (both, they're one line each):** (a) add `offset >= buffer.duration` to the `startSequence` invalid-check → `{ ok: false }` (matching preview's D2 guard); (b) make `clampOffset` quantize-then-reclamp: `Math.min(duration, Math.round(clamped * 10) / 10)`. Add P-13 cases: `startSequence({offset > duration})` and `preview({offset === duration})` → no sources created, state unchanged.

### I-4 — U-09 contract deviation: user Stop during preview announces "Stopped", not "Preview stopped"; zero tests on stop-during-preview

**Location:** `createMetronomadMethods.js:302-304` (`case STOPPED` unconditionally → `_returnToReady('Stopped')`); `behavior-specs.md` U-09 pins announced **"Preview stopped"**.

Only the *auto*-end path (`previewEnded`) gets "Preview stopped". User Stop during preview announces "Stopped". Uncaught because V-01 only asserts the toggle *calls* `stop()`, and no engine test ever calls `stop()` on a live preview (P-06 covers the `onended` auto-end path only).

**Fix:** branch on `this.isPreviewing` in the `STOPPED` case (it is still true when the engine's `stopped` event arrives) → "Preview stopped". Add (a) a V-07 case `'stopped' while isPreviewing` and (b) an engine test: `preview()` → `stop()` → sources stopped, timers cleared, events exactly `['preview','stopped']` (never `previewEnded`), then fire the stale preview `onended` → ignored.

### I-5 — The engine's visual clock is a second, parallel D9 implementation with no production client

**Location:** `playbackEngine.js` — `_rafTick` (197-213), `startVisualClock`/`stopVisualClock` (333-343), `onFrame` dep (59/72/210), `stopVisualClock()` embedded in `_teardown` (145) and `dispose` (346).

The app drives the dots via `createBeatDots` (pinned in AGENTS.md), so `engine.startVisualClock`/`onFrame` have zero production callers (grep-verified). It's a second reason for the engine to change, a second implementation of the same D9 phase law (two loops to keep in lockstep if the phase law ever changes), and it forces `_teardown` to reference a loop production never starts.

**Fix:** remove `startVisualClock`/`stopVisualClock`/`onFrame` from the engine (keep `getBeatGrid`/`songPosition`, which `createBeatDots` genuinely consumes), drop the `stopVisualClock()` calls from `_teardown`/`dispose`, and fold the P-12 coverage into `BeatDotsTest` (B-01…B-05 already cover the real loop). Update AGENTS.md's "tested public capability the app does not use" paragraph accordingly. (Alternative — make `createBeatDots` a consumer of the engine's loop — is worse: the app loop needs visibility snap, DOM class management, and reduced-motion handling the engine's loop deliberately lacks.)

### I-6 — A presentation module disposes the audio engine it doesn't own (inverted teardown direction)

**Location:** `createBeatDots.js:196-210` (`stopAll` ends with `engine.dispose()`); `createMetronomadLifecycle.js:85-92` (the `else if (this._engine) dispose()` fallback is dead in production — whenever `_engine` exists, `_beatDots` does too, since `mounted()` has no early return between the two).

The visualizer is a leaf presentation concern; disposing `playbackEngine` from inside it means the only module that knows the audio stack's shape (the lifecycle, which created all three) no longer owns its teardown.

**Fix:** `stopAll` tears down only its own resources (RAF, matchMedia listener, dot classes, `_vm`). `beforeUnmount` does the full ordering explicitly: `beatDots.stopAll(vm)` → `engine.dispose()` → `fileLoader.release()` (listener removal stays first — see N-1). Update B-05 to assert the visualizer no longer touches the engine; add a lifecycle-level test asserting `dispose` is called.

### I-7 — Injection story is asymmetric: engine is fully DI, `createBeatDots` hardcodes four browser globals

**Location:** `createBeatDots.js` — `window.matchMedia` (92), `window.requestAnimationFrame` (139/154/189), `window.cancelAnimationFrame` (72), `document.hidden` (179); only `getDom` is injected.

AGENTS.md convention: "dependencies are injected as factory parameters … never imported where a parameter would do." The engine follows it exactly; `createBeatDots` breaks it. The cost is visible in `BeatDotsTest.html:39-57, 313-342`: save/restore monkey-patching of `window.requestAnimationFrame`/`window.matchMedia` plus a `document.hidden` override — global-state boilerplate with a leak risk if an assertion throws before `afterEach`, exactly what the engine's fake-injection pattern avoids.

**Fix:** extend `base`: `{ getEngine, getClock, getDom, raf, cancelRaf, matchMedia, isPageHidden }` with `window.*`/`document.*` defaults, mirroring the engine's parameter shape. `BeatDotsTest` then drops all global patching.

### I-8 — "4 beats per bar" is load-bearing in four unconnected places

**Location:** `beatGrid.js:39` (`isAccent: k % 4 === 1`), `createBeatDots.js:19` (`DOT_COUNT = 4`) and ~116 (`beatIndex % DOT_COUNT`), `index.html` (`v-for="dot in 4"` + `'beat-dot--downbeat': dot === 1`).

Same concept, three modules, zero shared constant. v1 is 4/4-only by spec so this isn't a bug — but the known v2 candidates (KB-9: "looping, re-count-in", custom time signatures) make a missed site produce dots that silently disagree with accents.

**Fix (cheap now, expensive later):** export `BEATS_PER_BAR = 4` from `Utils/beatGrid.js`; `DOT_COUNT = BEATS_PER_BAR` in `createBeatDots`; expose `beatsPerBar` on Vue data so the template's `v-for` and downbeat class bind to it; accent rule becomes `k % BEATS_PER_BAR === 1`.

### I-9 — Test runner can report GREEN with zero tests executed

**Location:** `scripts/run-tests.cjs:107-158`.

If `mocha._runner` is unavailable (CDN blocked in CI, module-load failure) or the run times out, extraction falls back to DOM parsing; with no `.passes`/`.failures` elements that yields `passes: 0, failures: 0`, which is pushed to results and exits 0. A suite that loads but registers no tests is equally green. In a repo whose whole testing strategy is these in-browser suites, a false-green runner is the highest-leverage process risk.

**Fix:** throw per file when the runner is missing or `s.tests === 0` — "0 tests" must be a failure. (Related nit: `run-tests.cjs:47` spawns its own `python3 -m http.server` and hardcodes absolute `BASE_DIR`/`SERVER_ROOT`, contradicting AGENTS.md's user-started-server rule and the "from anywhere" claim — derive paths from `path.resolve(__dirname, '..')`.)

---

## Nits (grouped; each is a small, independent fix)

### Engine / fileLoader
- **N-1.** `playbackEngine.js:179,194` — the 25 ms scheduler interval is never cleared at the PLAYING flip; a 30-min song runs ~72,000 no-op ticks. Clear it in the flip branch (all clicks are strictly before `songStart.time`, so nothing is left to schedule).
- **N-2.** `playbackEngine.js:179-192` — background-tab `setInterval` throttling (≥1 s, Chrome intensive: 1/min) late-schedules clicks in a burst; `start(when)` with a past `when` fires immediately → compressed count-in audio (song start stays exact; D9 dots self-heal; D10 watch can't catch it — context is still `running`). Acceptable edge; **document as KB-10** and optionally skip (not late-schedule) clicks >50 ms past.
- **N-3.** `fileLoader.js:56-91` — the object URL is created, tracked, and revoked but **never consumed** (decode uses `file.arrayBuffer()`; nothing in `App/` reads `result.objectUrl` — grep-verified). ~15 lines of lifecycle code + F-05 test surface guarding a dead resource. Either consume it or delete it and collapse the contract to "exactly one decoded buffer live" (the property that actually matters). Also `extractExt` is public but only used internally.
- **N-4.** `playbackEngine.js:258-259` — `startSequence` returns the live mutable `_seq` (incl. the `scheduled` flags the scheduler trusts). App ignores it; only tests read it. Return a frozen copy view or a test-only accessor.
- **N-5.** `fileLoader.js:62-66` — `tooLong` message hardcodes "30 minutes" while `maxDurationSec` is injectable; interpolate the value.
- **N-6.** `playbackEngine.js:256-261 / 293-298` — terminal-transition pattern (gen check → state guard → teardown → silent `_state = STOPPED` → emit) duplicated for song and preview, with the deliberate `_setState` bypass documented only in comments. Extract `_finish(event)`.
- **N-7.** `playbackEngine.js` emits `'ended'`/`'previewEnded'` through `onStateChange` — magic strings that aren't in `ENGINE_STATES`, switched on as bare literals in `createMetronomadMethods.js:305,310`. Export `ENGINE_EVENTS` (or a separate `onEvent` callback).

### App layer / template
- **N-8.** `createMetronomadMethods.js` — `errorMessage` never auto-clears (only a successful load clears it). "Audio is blocked — tap again" stays on screen after the tap works; the drop-lock message outlives the Stop that unblocks it. Clear each message where its condition resolves, or add a dismiss "×".
- **N-9.** `createBeatDots.js:118-121` — `--beat-interval` is re-`setProperty`'d every frame with a constant value, dirtying style at ~60 fps. Cache the last value (same trick already used for the position readout).
- **N-10.** `createMetronomadApp.js:57-60` + `index.html:121-122` — the progressbar's live position appears in *both* `aria-label` (churning every ~100 ms) and `aria-valuenow` (unquantized float, e.g. `1.2345678`). Static label + `aria-valuetext="formatTime(songPosition)"` is the pattern the role intends.
- **N-11.** Progress readout frozen during Preview (`_startBeatDots` only on `COUNTING_IN`) — spec-defensible (§8 says "during playback") but a preview that visibly doesn't advance can read as broken. Optionally start the visual loop on `PREVIEW` too (dots stay dark; readout advances).
- **N-12.** Restart *during count-in* announces nothing (`_setState` no-ops on unchanged state) → silent to AT. Set `announcement = 'Count-in restarted'` in `onRestart`'s ok path.
- **N-13.** `index.html:36-43` — `drop-zone--dragover` flickers as the cursor crosses children (dragenter/leave pairs). `pointer-events: none` on `.drop-zone > *` or an enter/leave counter.
- **N-14.** `createMetronomadMethods.js:186-207` — unmount inside the resume await (up to 750 ms) leaves `this._engine` null after the `await` → unhandled TypeError. Guard: `if (!this._engine) return;` post-await.
- **N-15.** `index.html:75-77` — `:tabindex="isReady ? 0 : -1"` on the scrubber duplicates `:disabled="!isReady"` (disabled already removes it from tab order).
- **N-16.** `createMetronomadMethods.js` — the empty-input → restore-last-valid branch is copy-shaped in `onBpmInput` and `onCountInInput`; extract `_restoreLastValid`. (The pinned context.md wiring also promised "DOM-ID injection with defaults `{dropZone, fileInput}`" — the implementation hardcodes `document.getElementById('fileInput')`; implement the injection or update the pinned contract.)
- **N-17.** `createBeatDots` methods all re-accept the same `vm` (`startVisualClock(vm)` etc.) even though the factory is built in `mounted()` where the instance exists. `createBeatDots(vm, base, callbacks)` — one capture, four simpler signatures.

### Docs
- **N-18.** `AGENTS.md` (Memory bullet) pins the wrong `beforeUnmount` order: code removes the `visibilitychange` listener **first** (`createMetronomadLifecycle.js:84`), then `stopAll`, then `release` — arguably preferable (no events mid-teardown). Update AGENTS.md + the file's own JSDoc to match the code, don't move the line. (Same doc: the `autoSuspend` parenthetical is glued to "mobile auto-unlock" — those are two different Howler features; `autoUnlock` is deliberately left default-true per `howlerSetup.js:27-30`.) Also context.md's "clear error/toast timers" cleanup step doesn't exist in code (historical drift).
- **N-19.** Offset is rendered `m:ss.t` (unpadded minutes, `timeFormat.js:22-28`) while the placeholder and error hint literally say "mm:ss.t" (`index.html:80`, `commitOffsetEntry` hint). Pick one and align.
- **N-20.** Count-in clamps silently (99 → 16, no hint) while BPM gets one — spec only mandates the BPM indication, so consistency-only. Optionally add "Count-in limited to 1–16".
- **N-21.** `behavior-specs.md` is stale in two places the tests already corrected with visible notes: T-08/T-10 `now` inputs (tests use 101.75/102.499) and E2E-2.3's "9:99.9" (invalid per T-22; test uses 9:59.9). Update the contract file so it stays the single source of truth.

### Tests (coverage gaps & quality)
- **N-22.** **U-21 is the only fully missing user scenario** (P2): long-filename ellipsis + `title`. Cheapest fix: in E2E-1.1 (or a smoke case) copy the fixture to a 40-char name, assert `.file-name[title="<full name>"]`.
- **N-23.** U-13's "accepted after Stop → new file ready, old buffer/URL dropped" half is not E2E'd (only the rejection is); the `onFileDropped` offset re-clamp to a shorter new file (`createMetronomadMethods.js:77-79`) is untested (1-line VM test).
- **N-24.** U-18 has no E2E variant (contract suggested `ctx.suspend()` in `page.evaluate`); P-11 + V-07 are unit-adequate. Low priority (headless suspend quirks) — document the scoping if dropped.
- **N-25.** `UiHandlersTest.html:681` — the one real-timer test (750 ms `setTimeout` + `greaterThan(700)`); import `SCHEDULER` and assert against the constant. Flake-safe today but drifts silently if `RESUME_TIMEOUT_MS` changes.
- **N-26.** `playback.spec.cjs` E2E-1.3 asserts `actionT < 450` (self-imposed bound over a 250 ms in-page timeout). Under saturated CI the timeout can slip past 450 ms while the stop is still a valid count-in stop (window ends at t0+1500). Assert `actionT < playing.t` instead.
- **N-27.** `_refocusPlayStopButton`'s "never focus a disabled button" branch is untested (mock button always `disabled: false`).

### World-review additions (mobile / offline / a11y)
- **N-28.** **Offline is total, not partial**: no service worker — the app needs unpkg (Vue), cdnjs (Howler), *and* Google Fonts (Material Icons) on every load. A musician in a green room with no network gets nothing; with an ad-blocker that kills only fonts, the icon-only theme/home buttons go blank (text-labeled buttons survive). Given the CDN coupling already exists, inline SVG icons (zero third-party font) is the cheap improvement; offline support itself is a scope decision — document as non-goal or KB. **Decision (2026-08-22): deferred** — passive HTTP cache is best-effort sufficient for v1 (pinned URLs carry 1-yr cache lifetimes; browsers serve stale-while-offline regardless of expiry). Recorded as KB-10 in `_agent_docs/plans/2026-08-17-metronomad-v1/context.md`; the vendor-libs + hand-written-SW path remains the documented upgrade if a guarantee is ever needed.
- **N-29.** Range scrubber touch target is the native ~14 px thumb (WCAG 2.5.8 wants 44 px). Custom `::-webkit-slider-thumb`/`::-moz-range-thumb` at ≥28 px + taller hit area.
- **N-30.** iOS Safari double-tap zoom: pin `font-size: 16px` on the number/text inputs (and `-webkit-text-size-adjust: 100%`).
- **N-31.** Native spin buttons on `type="number"` duplicate the custom ± steppers for BPM; hide them (`-webkit-appearance: none` / `-moz-appearance: textfield`) — keep them on count-in or hide both.
- **N-32.** Rapid live-region succession at high BPM with count-in 1 ("Count-in started" → "Song started" <1 s apart) may be coalesced/dropped by some AT. Acceptable (clicks are the primary signal); document as known AT behavior.
- **N-33.** Backgrounding the tab/mobile screen keeps audio playing (standard Web Audio; arguably what a metronome should do). Document as KB so it isn't "fixed" later by accident.

---

## 5. Test coverage vs `behavior-specs.md`

**95 of 98 user/component scenarios fully covered** (T-01…T-34, F-01…F-09, P-01…P-14, H-01…H-03, B-01…B-05, V-01…V-07, E2E-1.1…2.4 all 1:1 mapped; U-series covered via the unit/E2E combinations the matrix in the test pass records). Gaps:

| Scenario | Gap |
|---|---|
| U-09 (P2) | **PARTIAL + deviation** — see I-4: stop-during-preview announcement wrong, zero tests on the path |
| U-13 (P1) | **PARTIAL** — rejection tested (E2E-2.2); post-Stop acceptance + old-buffer/URL drop not E2E'd (N-23) |
| U-18 (P1) | **PARTIAL** — unit only; E2E `ctx.suspend()` variant absent (N-24) |
| U-21 (P2) | **MISSING** — no test for filename truncation/`title` (N-22) |
| (negative) | No tests for: engine `stop()` during preview; `startSequence({offset > duration})`; `preview({offset === duration})`; stale *preview* `onended`; concurrent `loadFile`; double-`onFileDropped` (all addressed by the fixes in I-1…I-4, N-3, N-23) |

**Suite strengths** (from the test pass): total ID traceability (auditable in minutes); genuinely deterministic engine tests (fake clock/RAF/timers + a `calls` ordering log assert concurrency properties near-untestable on a real context — P-03's 20× mash with a dead-generation `onended` storm, P-08's sweep across every tick boundary); the mock-VM pattern attaches the *real* app computeds as live getters (no stale-mock false confidence); the in-page 5 ms transition-logger timing methodology is done properly and its rationale is commented; H-03 measures rendered click pitch via zero-crossings instead of asserting internals.

## 6. Spec compliance

Requirement-by-requirement: **every user-visible spec requirement is compliant**, with exactly two documented, acceptable deviations (drop-reject-while-playing vs §3's "replaces" wording — safer; sine-burst clicks vs "woodblock" timbre — D7/KB-8, manual-checklist-gated). The three spec-prescribed live-region strings match **verbatim**; the full user-facing string inventory (24 strings) was audited — none contradict the spec. Phase-8 success criteria verified (root project card present, AGENTS.md complete, 13-item manual checklist user-confirmed). 12 in-code decision references spot-checked — all accurate. Non-goals enforced (no persistence, no volume, no looping, no time signatures).

## 7. What's well-designed

1. **Generation counter (D4) as lock-free atomicity** — Play/Stop/Restart mashing and phantom clicks handled with a captured integer; every interleaving tried in review (play→stop→play, preview→play, interrupt→pending-onended, rapid preview-end→Play) closes cleanly.
2. **Single choke points** (`createSource`, `_clock`, injected timers) make the entire engine testable with zero real `AudioContext` — the P-suite asserts scheduling *order* and *horizon bounds*, not just outcomes.
3. **D9 pure-function beat phase** turns hidden-tab RAF pausing (Safari) from a drift bug class into a non-issue; the visibility handler is a one-line snap + resume, E2E-verified.
4. **fileLoader URL lifecycle** — the `finally` + `currentUrl !== objectUrl` check leaves no orphan URL on *any* of the five exit paths (the class of code that usually rots; airtight here). Foreground scheduler math verified airtight: every click is scheduled 50–100 ms early, never late.
5. **Clean engine→app boundary** — engine emits events and answers read-only queries; all presentation state lives in the app; non-reactive `_` handles keep audio objects out of Vue's reactivity (and Vue's equal-write dedup keeps the per-frame `activeBeatIndex` write free of re-renders).
6. **Accessibility beyond the letter of the spec** — downbeat distinguished by size not color, reduced motion honored twice (JS class + CSS media fallback, live media changes), locked controls *unfocusable* not just disabled, focus returned to Play/Stop after Stop/Restart — each with its own E2E scenario.

## 8. Recommended action plan

**Before v1 is considered shippable (small, ~1 session):**
1. C-1 — BPM/count-in commit-on-Enter/blur pattern + per-keystroke regression test (update U-11/V-03).
2. I-1 — move the lock check into `onFileDropped`; disable/dim Browse while locked.
3. I-2 — reject drops while `decoding.active`.
4. I-3 — `offset >= buffer.duration` guard in `startSequence` + `clampOffset` quantize-then-reclamp + P-13 cases.
5. I-4 — "Preview stopped" branch + the two missing stop-during-preview tests.
6. I-9 — runner must fail on 0 tests / missing runner.

**Before v2 work starts (design hygiene, ~half a session):**
7. I-5 — remove the engine's unused visual-clock surface (or commit to making `createBeatDots` its consumer).
8. I-6 — move `engine.dispose()` out of `beatDots.stopAll` into the lifecycle.
9. I-7 — inject RAF/matchMedia/hidden into `createBeatDots`.
10. I-8 — `BEATS_PER_BAR` constant.
11. N-18 — AGENTS.md/context.md doc corrections (order, autoSuspend/autoUnlock, "clear error/toast timers").
12. N-21 — refresh the stale behavior-specs inputs.

**Nice-to-have backlog:** the remaining nits (N-2…N-17, N-19…N-20, N-22…N-33), roughly in the order listed. The mobile-touch cluster (N-28…N-31) is the highest-value batch if mobile use becomes real.
