# Metronomad v1 — Shared Context

Whole-plan detail shared across all phases. Phase files name the sections here they need under "Context to load."

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
| D9 | **Beat phase is a pure function of the audio clock**: `beatPhaseFromGrid(now, firstBeatTime, interval) → { beatIndex, inBeat }`. The app-level `createBeatDots` RAF dot loop — the **sole** visual-clock owner; the engine has no visual clock (its P-12 surface was removed by review-fix I-5/RD-6, 2026-08-22) — calls it every frame; on `visibilitychange` → visible it re-renders once. | No accumulated phase → hidden-tab RAF pausing can never cause drift/stutter (world-review 1.1/5.4/6.1 fall out for free). |
| D10 | **Context-state watch**: while `countingIn`/`playing`/`preview`, a 250 ms interval checks `ctx.state`; `suspended`/`interrupted` (not from our own stop) → engine self-stops + `onInterrupted()` → Ready + announcement. `ctx.resume()` rejection after Play → ~750 ms timeout → friendly error (world-review 1.2/1.4). | OS audio interruptions and blocked autoplay become visible, recoverable states. |
| D11 | **Test fixture**: extract the base64 3 s 440 Hz MP3 already embedded in `_agent_docs/research/howler-research-test.html` into `test/fixtures/sine3s.mp3` (~40 KB). One fixture for all E2E; no new tooling. | Reuses verified artifact; keeps repo light. |

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

**Vue wiring (`createMetronomadLifecycle`):** `mounted()` → `initHowler()` in try (failure → Error state "Audio is not supported in this browser") → `renderClickBuffers` → `createPlaybackEngine` (callbacks mutate reactive state + live region) → `createFileLoader({ codecs: { check: isSupportedCodec } })` → `createBeatDots` → drop handlers (DOM-ID injection with defaults `{ dropZone: 'dropZone', fileInput: 'fileInput' }`). Engine/clock held as non-reactive `_engine`/`_clock`. `beforeUnmount()` cleanup order (memory-management.md, as built — updated 2026-08-22): remove drop/visibility listeners → `beatDots.stopAll()` (visualizer resources only — it never touches the engine) → `engine.dispose()` → `fileLoader.release()`.

**Template essentials (`index.html`):** drop zone (`dragover`/`drop` + Browse `<button>` opening hidden `<input type="file" accept="audio/*" id="fileInput">`); file row (truncated name + `title`, duration, KB-2); controls group with `:title` lock hint (U-12); `<input type="number" id="bpmInput" min="30" max="250" step="1">` + ± stepper buttons; offset `<input type="range" id="offsetScrubber" :max="duration" step="0.1" :disabled="isParamLocked" :tabindex="isParamLocked ? -1 : 0" aria-label="Start offset">` + `<input type="text" id="offsetInput">` (Enter/blur commit); count-in number input (min 1 max 16); `<button id="playStopBtn">` (label Play/Stop), `<button id="restartBtn" :disabled="!isSequenceRunning">`, `<button id="previewBtn" :disabled="appState !== 'ready'">`; 4 beat dots (dot 1 larger + `beat-dot--downbeat`, row `aria-hidden`, `data-beat` hook); progress bar with offset marker + `aria-label` (B-04); `<div role="status" aria-live="polite" class="sr-only">{{ announcement }}</div>`; `<div role="alert" v-if="errorMessage">`.

## Testing Strategy

- **Unit (Mocha/Chai, in-browser via `MyComponents/*Test.html` + `scripts/run-tests.cjs`):** all pure functions (T-01…T-34) and the engine under injected clock/RAF/timers (state machine, generation counter D4, 30-min guard D3, preview clamp D2, lookahead order P-08, stop/start atomicity P-03/P-04, graph wiring P-14). Table-driven clamp/parse cases; 1–3 assertions per scenario. The engine tests instantiate **no real AudioContext** — deterministic and fast.
- **E2E (Playwright, chromium only):** the 12 scenarios in behavior-specs.md §3.4 — thin; assert state, UI, and wall-clock timing with tolerance; **never listen to audio**.
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
6. **KB-6 — Testability hooks.** `document.body[data-state]` and the dot row's `data-beat` are intentional minimal hooks for E2E assertions; they carry no styling and no ARIA. **Semantics (pinned in Phase 6):** `data-state` = appState (`noFile`/`ready`/`countingIn`/`playing`); `data-beat` = the **zero-based lit dot index** ("0"–"3"), updated per visual frame by `createBeatDots` — "-1" during lead-in and when idle. Spec text saying "beat 1" means data-beat "0" (first click → first dot).
7. **KB-7 — 30-minute duration guard (D3)** fires *after* decode (duration is only known post-decode). The friendly error is "Song too long — maximum length is 30 minutes". Pre-decode file-size heuristics are explicitly out of scope.
8. **KB-8 — Click pitch** 1568 Hz (accent) / 1047 Hz (regular) is fixed in v1 (no custom click sounds — spec §12).
9. **KB-9 — No Tone.js (D6).** The lookahead scheduler is ~60 lines of hand-rolled code on the repo's dependency-free pattern; Tone.js remains a post-v1 option if transport needs grow (looping, re-count-in).
10. **KB-10 — Offline use is best-effort via the browser HTTP cache (deferred, no code).** All external deps are version-pinned CDN URLs with long cache lifetimes (unpkg `max-age=1y`, cdnjs `~355d + immutable`, gstatic font files `~1y`); browsers serve stale cache while offline regardless of expiry, so a previously-visited user typically gets a working offline app. Not guaranteed — cache eviction (Safari most aggressive), private mode, cleared data, or a first visit with no network all break it. Decision (2026-08-22 review): defer — no service worker, no vendoring for v1. If a guarantee is ever needed (mobile as a real target), the path is vendor vue/howler locally + inline SVG icons + a small hand-written SW; see `_agent_docs/reviews/2026-08-22-metronomad-v1-code-review.md` N-28.
11. **KB-11 — Background-tab interval throttling compresses the count-in (latent defect, acceptable v1 edge).** In a backgrounded tab, Chrome throttles `setInterval` (≥1 s; intensive mode 1/min), so the lookahead scheduler (25 ms tick, 100 ms horizon) late-schedules count-in clicks in a burst; `start(when)` with a past `when` fires immediately. The song start stays sample-exact (D5's immediate `start(when, offset)` is not throttled), the D9 dots self-heal (phase is a pure function of the audio clock), and the D10 watch can't catch it (the context is still `running`). Decision (2026-08-22 review N-2): accept for v1. The optional fix — **skip** clicks >50 ms past their time instead of late-scheduling — is a behavior change (a missed click is audibly different from a late one) and is **deferred** with this KB.
12. **KB-12 — Rapid live-region succession may be coalesced by assistive tech (accepted AT behavior).** At high BPM with count-in 1, "Count-in started" → "Song started" land <1 s apart and some screen readers may coalesce or drop the second announcement. The click *sounds* are the primary signal; the polite live region is secondary. Decision (2026-08-22 review N-32): accepted — no debouncing of announcements (code unchanged).
13. **KB-13 — Backgrounding the tab keeps audio playing (intended behavior).** Standard Web Audio: hiding the tab or mobile screen does not stop the song or count-in — arguably what a metronome should do. Only the visualizer pauses (U-17/B-02) and self-heals via the D9 pure-function phase on return. Decision (2026-08-22 review N-33): intended — do not “fix” (e.g. pause on `visibilitychange`). Kept separate from KB-11: KB-11 is the latent defect note (throttled scheduler compresses the count-in); KB-13 pins the intended audio-continues behavior.

_KB-14…KB-17 added 2026-08-23 by CR 2026-08-23-001 (waveform progress + BPM detection; plan `_agent_docs/plans/2026-08-23-cr-001-ui-enhancements/`)._

14. **KB-14 — The playhead stays under `prefers-reduced-motion` (W-7).** It is a functional position indicator (the visual twin of the readout text), not decorative motion: no CSS animation, moves only in the existing 10 Hz tenths steps. The beat dots’ pulse → static swap is unaffected. Do not “fix” it away. Decision (2026-08-23, CR 2026-08-23-001 §1.4 / W-7).
15. **KB-15 — Tempo suggestion is a heuristic, not ground truth (CR §4).** Tempo drift (accelerando/decelerando, live recordings) → smeared “average” over the 60 s window — the estimate is the window average, never the current tempo; a sparse-but-rhythmic intro at a different feel within the first 60 s can bias the estimate; half-time pairs *inside* the 70–180 prior band (75/150) are ambiguous by construction; short files → `null` (correct UX, not a bug). All three: the user’s manual entry is authoritative — limitations, not defects. Decision (2026-08-23, CR 2026-08-23-001 §4).
16. **KB-16 — Waveform paint gate + placeholder during re-decode (W-17, risk R-13).** The waveform paints only when `!decoding.active && waveformReady`. While a *second* file decodes, the previous file’s waveform (or placeholder) stays visible until the READY flip — intentional; do not “fix” it into a blank flash. Decision (2026-08-23, CR 2026-08-23-001 §1.2 / W-17).
17. **KB-17 — `aria-valuemax` (and the old range’s `:max`) carry raw non-round floats** (e.g. `3.0000000001`) (risk R-3). `formatTime`/`clampOffset` absorb them; the raw attribute is acceptable (native ranges did the same at the v1 `#offsetScrubber`). Do not “fix” it into a divergence. Decision (2026-08-23, CR 2026-08-23-001 §1.5 / risk R-3).

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
