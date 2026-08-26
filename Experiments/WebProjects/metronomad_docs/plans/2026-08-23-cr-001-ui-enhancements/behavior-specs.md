# CR 001 UI Enhancements — Behavior Specifications

Legend: **P0** core behavior · **P1** structural correctness · **P2** polish/edge. Scenarios are the contract for `build-tdd` — each maps to a failing test first (RED → GREEN). This file is the authoritative, complete set **for this plan's scenarios only**: WF-P1.\*, WF-V1.\*, WF-I1.\*, WF-I2.\*, TD-1.\*, TD-U1.\*, E2E-3.\*, E2E-4.\*. All v1/review scenarios (T-35, U-10, U-12, V-07, B-04, F-05, R-*, …) stay canonical in their original plans and are unchanged — where a row here *extends* one (e.g. V-07's announcement inventory), the extension is stated in the row. Phase files inline the scenarios they own; this file is the canonical copy.

Worked-example constants (recompute-checked 2026-08-23): sine3s.mp3 ≈ 3 s / "0:03.0"; 5 × ArrowRight (0.1 s step) = 0.5 s → "0:00.5"; PageUp on 3 s = 0.3 s; 50 % of 3 s = 1.5 s → "0:01.5"; 3 s @ 44 100 Hz = 132 300 samples → 4096 peak buckets (≈32 samples each); clicks20.wav = 20 s / 44 100 Hz / 16-bit mono PCM = 1 764 044 bytes, 40 clicks at 0.5 s spacing (120 BPM).

## 1. Waveform Peaks — pure module (Phase 1; `MyComponents/WaveformPeaksTest.html`)

Test buffers are plain objects `{ numberOfChannels, length, sampleRate, getChannelData(c) }` — no real AudioContext.

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| WF-P1.1 | P0 | Mono fake buffer, 1024 samples of 0, sampleRate 44 100 | `extractPeaks(buffer, 32)` | 32 buckets; every `mins[i] === 0` and `maxs[i] === 0` |
| WF-P1.2 | P0 | Mono, 2048 samples, 16 buckets; sine with exactly 1 cycle per bucket (freq 44 100/128 ≈ 344.53 Hz, amplitude 1) | `extractPeaks(buffer, 16)` | every bucket `maxs[i] > 0.99` and `mins[i] < -0.99` (per-bucket envelope faithful) |
| WF-P1.3 | P0 | Stereo, 2 buckets: ch0 = [+0.2, −0.2 …], ch1 = [+0.9, −0.8 …] per bucket | `extractPeaks(buffer, 2)` | bucket 0: `min === -0.8` (min-of-mins), `max === 0.9` (max-of-maxs) — a mono-side-only feature never reads quieter |
| WF-P1.4 | P1 | Mono, **50 samples**, bucketCount 4096 (the tiny-buffer edge); and the sine3s shape: 132 300 samples, bucketCount 4096 | `extractPeaks(buffer)` (default) | 50-sample buffer → `bucketCount === 50` (effective = min(bucketCount, sampleCount), one sample per bucket); 132 300-sample buffer → `bucketCount === 4096` (≈32 samples per bucket — NOT "32 buckets", the CR/memo arithmetic error corrected in index.md) |
| WF-P1.5 | P1 | Mono, 1 sample (value 0.7) | `extractPeaks(buffer, 4096)` | `bucketCount === 1`; `mins[0] === maxs[0] === 0.7` |
| WF-P1.6 | P1 | Channel data containing NaN and ±Infinity; non-finite `bucketCount` (NaN); degenerate buffer (`numberOfChannels: 0`) | `extractPeaks(…)` / `channelArrays(…)` | NaN/Inf samples treated as 0 (peaks finite); non-finite bucketCount → default 4096; degenerate buffer → `channelArrays` returns `channels: []` and `extractPeaks` returns zero-length arrays — never throws |
| WF-P1.7 | P2 | Mono, 20 000 001 samples (crosses `PEAK_STRIDE_MAX_SAMPLES` = 20 000 000) with a +1.0 spike at sample 4 000 000 (in range; a stride-4 multiple); same input twice | `extractPeaks(buffer)` | stride 4 applied deterministically: two calls produce byte-identical arrays; the spike's bucket `max === 1.0` (a spike on a non-strided sample is the accepted visual trade — CR §1.2); a 19 999 999-sample buffer uses stride 1 |
| WF-P1.8 | P0 | Source peaks, 8 buckets: `mins = [0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7]`, `maxs = mins + 1.0` | `poolPeaks(source, 2)` | `mins = [0, 0.4]`, `maxs = [1.3, 1.7]` (min-of-mins / max-of-maxs per pool); `poolPeaks(source, 8)` and `poolPeaks(source, 16)` → copy (target ≥ source is a no-op pool); `poolPeaks(source, 1)` → global min/max `[0, 1.7]` |
| WF-P1.9 | P1 | Mono buffer; stereo buffer (2 channels); raw `Float32Array[]` | `channelArrays(…)` / `monoMixdown(…)` / `mixDown(…)` | mono: `channels[0]` is the *same reference* as `getChannelData(0)` (no copy); stereo: 2 arrays, correct lengths; `mixDown` = element-wise mean (single channel returned as-is, no copy; `[a, b]` of length 4 with a=[1,0,1,0], b=[0,1,0,1] → [0.5, 0.5, 0.5, 0.5]); `monoMixdown` = the buffer facade over it |

## 2. Tempo Detection — pure module (Phase 2; `MyComponents/TempoDetectionTest.html`)

Trains are synthesized in-page as plain `Float32Array`s with the `clickBuffers.js` recipe (1047 Hz regular / 1568 Hz accent, 60 ms, 5 ms linear attack, exp decay to 1e-5) — **zero real AudioContext** (engine-test convention). "±1" means the returned integer is within 1 of the stated BPM.

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| TD-1.1 | P0 | 120 BPM train: 40 clicks at t = 0.0, 0.5, …, 19.5 s; 44 100 Hz mono | `detectTempo([ch], 44100)` | `{ bpm: 120 ± 1, confidence ≥ 0.6 }` |
| TD-1.2 | P0 | Identical train re-synthesized at **48 000 Hz** (W-8: the sampleRate parameter, not an accident of 44.1) | `detectTempo([ch], 48000)` | `{ bpm: 120 ± 1 }` |
| TD-1.3 | P1 | 60 BPM train: 20 clicks at t = 0.0, 1.0, …, 19.0 s; 44 100 Hz | `detectTempo([ch], 44100)` | `null` — out-of-band winner (×0.75) whose in-band alias (120 BPM, half the spacing) has ≈0 correlation → "unsure" → null per the TD-1.7 P0 mechanism. **Corrected 2026-08-24**: the original "still wins" expectation pinned byte-identical input to TD-1.7 with a contradictory outcome (a pure function cannot return both); the P0 pin governs (context.md D-D deltas) |
| TD-1.4 | P1 | 90 BPM train: 20 clicks at 0.667 s spacing; 44 100 Hz | `detectTempo([ch], 44100)` | `bpm: 90 ± 1` |
| TD-1.5 | P1 | 180 BPM train: 40 clicks at 0.333 s spacing; 44 100 Hz | `detectTempo([ch], 44100)` | `bpm: 180 ± 1` — the 90-BPM half-period alias correlates at half energy and loses |
| TD-1.6 | P2 | 240 BPM train: 40 clicks at 0.25 s spacing; 44 100 Hz | `detectTempo([ch], 44100)` | `bpm ∈ {120, 240}` — the 120 alias (p/2, in-band) is a same-perceived-pulse family; never a different family (60/80/…); documented alias ambiguity (KB-15 family) |
| TD-1.7 | P0 | **Half-time 120**: 20 clicks at t = 0, 1.0, 2.0, …, 19.0 s (onsets only every 2 beats of a 120-BPM grid); 44 100 Hz | `detectTempo([ch], 44100)` | result is `120` **or `null` — never 60** (W-12/W-13: out-of-band winner with a weak in-band alias reads as "unsure"; the conservative output is silence). The tuning constants (context D-D) may move during RED/GREEN only while this outcome holds |
| TD-1.8 | P1 | 75 BPM train (25 clicks, 0.8 s spacing) AND 150 BPM train (50 clicks, 0.4 s spacing); 44 100 Hz | `detectTempo(…)` on each | each result ∈ {75, 150, null} — both in-band: ambiguous by construction (KB-15), pinned so a regression that *confidently picks the wrong one against the input* is caught at the family boundary, never 30/300/etc. |
| TD-1.9 | P0 | 10 s of digital silence (all 0), 44 100 Hz | `detectTempo([ch], 44100)` | `null` (no onsets above the noise floor) |
| TD-1.10 | P1 | 10 s steady tone: 440 Hz sine at constant amplitude 0.5 (onset-free); 44 100 Hz | `detectTempo([ch], 44100)` | `null` (flat onset envelope) |
| TD-1.11 | P1 | Short file: 3.0 s of a 120 BPM train = 6 clicks (t = 0 … 2.5 s) < `MIN_ONSET_FRAMES` (8); 44 100 Hz | `detectTempo([ch], 44100)` | `null` (too few onsets — the documented short-file behavior, CR §2.4; correct UX, not a bug) |
| TD-1.12 | P1 | 5 s silence + 15 s of a 120 BPM train (30 clicks), 20 s total; 44 100 Hz | `detectTempo([ch], 44100)` | `bpm: 120 ± 1` (leading-silence trim finds the content, W-12) |
| TD-1.13 | P2 | Channel array containing NaN; `sampleRate` = NaN / 0 | `detectTempo(…)` | `null` (guards) — never throws, never a finite BPM from invalid input |
| TD-1.14 | P2 | 20 s of a 120 BPM train (40 clicks); window arg `maxWindowSec = 10` | `detectTempo([ch], 44100, 10)` | `bpm: 120 ± 1` — the window clamps to the first 10 s (20 clicks, still ≥ 8 onsets) and the result matches the full-window answer |
| TD-1.15 | P1 | 120 BPM train with **1568 Hz accent every 4th click** (the `clicks20.wav` fixture shape); 44 100 Hz | `detectTempo([ch], 44100)` | `bpm: 120 ± 1` (accent/regular mix must not bias the estimate) |

## 3. Waveform View factory (Phase 3; `MyComponents/WaveformViewTest.html`)

Proxy-mocked real 2D ctx (records draw calls) + fake RAF collector with `flushRAF()` (skill `testing-unit.md` patterns); no global patching. View built via `createWaveformView(vm, base, callbacks)` with a mock-VM (`{ duration, offsetDraft }`) and a fake DOM node.

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| WF-V1.1 | P0 | View inited; 4096-bucket peaks set; size 300×64 CSS | `setPeaks(peaks)` → `flushRAF()` | exactly **one** render: `poolPeaks` to 300 columns, one vertical line per CSS column (300 lines), mirrored about the center (O-3); a second `setPeaks` of the *same* peaks object at the same size → no further render |
| WF-V1.2 | P0 | View inited, peaks set | `resize(600)` → `resize(500)` → `resize(400)` without flushing (a W-5 rotation storm) | at most **one** pending RAF; `flushRAF()` → one render at the **final** size (400 columns) — earlier sizes never paint |
| WF-V1.3 | P0 | `devicePixelRatio` injected as 2 | `resize(300, 64)` | backing store `canvas.width === 600`, `canvas.height === 128`; drawing coordinates stay in CSS-column space (ctx scaled by 2) |
| WF-V1.4 | P0 | View inited with scrub callbacks; a pending render queued | `dispose()` twice | first call: pending RAF cancelled, canvas + window (`pointerup`, `blur`) + `resize` listeners all removed, `canvas.width === 0 && canvas.height === 0` (GPU release); second call: no throw, no double-removal |
| WF-V1.5 | P1 | View inited, peaks set, steady state | observe the RAF collector after flush | collector is **empty** — no internal clock; the only RAF ever queued is the coalesced render (the playhead is DOM, not canvas) |
| WF-V1.6 | P1 | Peaks with a known per-column profile (e.g. column k: min −0.5, max +0.5) at height 64 | render | one draw op per CSS column from `y(max)` to `y(min)`, center line at y = 32 (mirrored bars, O-3); a silent column (min = max = 0) draws a zero-height line at center — a gap reads as silence |
| WF-V1.7 | P1 | Rendered state | `setDraft(1.5)` → `flushRAF()`; then `setDraft(null)` → `flushRAF()` | draft marker line painted at the draft position on the first flush; gone after the second; the DOM overlay marker is untouched by the view (it tracks the committed offset only) |
| WF-V1.8 | P2 | `setPointerCapture` stubbed to **throw** (Safari stale pointerId, W-1) | `pointerdown` then `pointermove` | the throw is caught; the drag continues — `onScrubMove` still fires; no stuck state |
| WF-V1.9 | P1 | Active drag (pointer captured) | (a) `pointerup` on canvas; (b) pointer released **off-canvas** → global `window` `pointerup`; (c) `window` `blur` mid-drag; (d) `pointercancel` (in-page dispatch, iOS OS-gesture shape — two-finger scroll/rotate) | (a) `onScrubEnd(true)` exactly once; (b) `onScrubEnd(true)` via the global path (capture released) exactly once; (c) `onScrubEnd(false)` — discard; (d) `onScrubEnd(false)` — discard; each path releases capture and a subsequent `pointermove` fires nothing (W-1 cleanup paths) |
| WF-V1.10 | P2 | No drag active | `pointermove` dispatched on the canvas | no `onScrub*` callback fires (move before down is ignored); x→tenths conversion uses `vm.duration`: x = 50 % of width → tenths = 0.5 × duration (1.5 for a 3 s file) |

## 4. Waveform wiring + playhead (Phase 4; `UiHandlersTest.html` mock-VM + `waveform.spec.cjs`)

Mock-VM rows drive the real `onFileDropped` success path with a `loadFile` spy and fake `setTimeout`; the guard is the one `_analysisValid` (D-E).

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| WF-I1.1 | P0 | Unit (mock-VM): loader spy resolves `{ ok: true, buffer: A, duration: 3, fileName: 'a' }` | `onFileDropped(file)` → READY → flush the 0 ms yields | `_loadGeneration` bumped; `_bpmTouchedThisFile === false`; after the yield: `_peaks` set (computed from A), `waveformReady === true`; the READY flip itself precedes the peaks work (W-6) |
| WF-I1.2 | P0 | Unit: peaks task for buffer A pending at its yield; a second load resolves with buffer B (generation bumped) | flush A's continuation, then B's | A's continuation **writes nothing** (guard: `generation !== _loadGeneration \|\| buffer !== _buffer`): `waveformReady` still false, `_peaks` unset; B's continuation then sets `_peaks` (from B) + `waveformReady === true` (W-14) |
| WF-I1.3 | P1 | Unit: peaks task pending at its yield; `beforeUnmount` ran (`_disposed === true`) | flush the continuation | **no write** — nothing touches the unmounted VM (W-15, N-14 shape) |
| WF-I1.4 | P1 | Unit: file A loaded, `waveformReady === true`; a second file is dropped (decoding) | observe during decode; then the second load resolves ok | during decode: `waveformReady` stays true (old waveform visible — KB-16, intentional, do not blank-flash); in the ok-branch: `waveformReady` resets to **false** (placeholder reappears) before the new peaks land (O-2/W-17) |
| WF-I1.5 | P2 | Unit: a load **fails** (codec/decode/tooLong) while a peaks task for the still-live buffer A is pending at its yield | flush A's continuation | the failure path did **not** bump the generation (F-05: old buffer stays live) → A's task completes and applies normally; `errorMessage` set, `appState` unchanged |

**E2E (Phase 4 rows — `test/e2e/waveform.spec.cjs`; in-page 5 ms transition logger per `playback.spec.cjs:43-67` convention):**

| ID | Test | Steps | Expected |
|----|------|-------|----------|
| E2E-3.1 | Waveform paints; Ready is never delayed | drop `sine3s.mp3`; record state transitions in-page | `#waveformCanvas[data-loaded="true"]` appears; the in-page timeline shows the `ready` transition **strictly before** the first frame with `data-loaded="true"` (peaks work runs after the READY paint, W-6); canvas visible (`offsetWidth > 0`) |
| E2E-3.2 | Playhead tracks during playback | E2E-3.1 state; set count-in 1, press Play; in-page: sample `#waveformPlayhead[data-position-tenths]` at two points ≥1 s apart during playing | both samples advance monotonically from the offset's tenths and each is within ±1 tenth of the position parsed from `.progress-readout` at the same timestamp (the readout is the tenth-second ground truth; 10 Hz cadence — no per-frame updates) |
| E2E-3.3 | Playhead parks at the offset in Ready | E2E-3.1 state; commit offset `0:01.2` via `#offsetInput` + Enter | `#waveformPlayhead[data-position-tenths] === "12"`; readout text `0:01.2 / 0:03.0` (existing Ready watcher — no new state) |
| E2E-3.4 | Responsive height clamp (W-4) | emulate viewport 360×740, load; then 1280×800, load | `.waveform` computed height **48 px** at 360 and **64 px** at 1280; `.progress-readout` visible (non-zero height) in both |

## 5. Scrub + keyboard — `#offsetScrubber` replaced (Phase 5; `UiHandlersTest.html` + `waveform.spec.cjs`)

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| WF-I2.1 | P0 | Unit (mock-VM), Ready, duration 3.0, offset 0 | `onWaveformScrubStart(1.5)` | `offsetDraft === 1.5` (quantized via `clampOffset`); `view.setDraft(1.5)` called; committed `offset` still 0 (draft, not commit) |
| WF-I2.2 | P0 | Draft active (1.5), duration 3.0 | `onWaveformScrubMove(2.73)`; then `onWaveformScrubMove(999)` | draft `2.7` (quantize-then-reclamp — the same law as `onOffsetScrub`, never a second rule); draft `3.0` (clamped to duration, T-35) |
| WF-I2.3 | P0 | Draft `2.7` | `onWaveformScrubEnd(true)` | `onOffsetScrub(2.7)` law applied: `offset === 2.7`, `offsetText === "0:02.7"`, hint cleared; `offsetDraft === null`; `view.setDraft(null)` called |
| WF-I2.4 | P0 | Draft `2.7`, committed offset 1.0 | `onWaveformScrubEnd(false)` (pointercancel path) | `offset` stays 1.0, `offsetText` unchanged; `offsetDraft === null` — the draft is discarded, nothing committed (W-1) |
| WF-I2.5 | P0 | `isParamLocked === true` | `onWaveformScrubStart(1.5)` | no-op: `offsetDraft === null`, no view call (U-12 JS backstop; CSS `pointer-events: none` is the first line) |
| WF-I2.6 | P0 | Unit, Ready, offset 0, duration 3.0 | 5× `onWaveformKeydown(ArrowRight)` | offset `0.5`, `offsetText "0:00.5"` after the fifth (0.1 s per press — the old scrubber step, W-9); one `ArrowLeft` → `0.4`; at 0, `ArrowLeft` → stays `0` |
| WF-I2.7 | P1 | Offset 0.4, duration 2.96 (the T-35 quantize-up case) | `onWaveformKeydown(Shift+ArrowRight)` | offset `1.4`; from 2.5 → `Shift+ArrowRight` → `2.9` (never 3.0 > duration — `clampOffset` end-clamp) |
| WF-I2.8 | P1 | Duration 30.0, offset 5.0 | PageDown → PageUp → Home → End | `2.0` → `5.0` → `0` → `30.0` (PageUp/Down = 10 % of duration = 3.0 s — deliberately coarser than the native range's step×10, W-9; Home/End = 0 / duration) |
| WF-I2.9 | P1 | Any handled key; and an unhandled key (`KeyA`) | keydown events | `preventDefault()` called exactly for the handled set (arrows, PageUp/Down, Home/End) and never for `KeyA`; `KeyA` changes nothing |
| WF-I2.10 | P1 | Unit, noFile state (`fileName ''`, duration 0) | `onWaveformKeydown(ArrowRight)` / `onWaveformScrubStart(1)` | no-op — no offset write against a zero duration (the canvas is `tabindex="-1"` and unfocusable in this state; the JS guard is the backstop) |

**E2E (Phase 5 rows — `waveform.spec.cjs` + re-pointed `keyboard.spec.cjs` / `playback.spec.cjs` rows):**

| ID | Test | Steps | Expected |
|----|------|-------|----------|
| E2E-3.5 | Click scrubs the offset | E2E-3.1 state; mouse-click at 50 % of the canvas width | `#offsetInput` value `"0:01.5"` (≈ x/width × duration, tenths); canvas `aria-valuenow="1.5"`, `aria-valuetext="Offset 0:01.5"`; readout `0:01.5 / 0:03.0`; **focus returns to `#waveformCanvas`** after the click (CR §1.5) |
| E2E-3.6 | Drag scrubs continuously | mouse.down at 20 %, mouse.move to 60 % (≥3 steps), mouse.up | during the drag the readout tracks the draft (in-page samples advance); on release: offset `≈ 1.8` (±1 tenth), `#offsetInput` mirrors `"0:01.8"`; no stuck draft (a later click commits normally) |
| E2E-3.7 | `pointercancel` discards (W-1) | dispatch `pointerdown` then `pointercancel` in-page (iOS OS-gesture shape) | offset unchanged; no draft stuck — a subsequent real click at 50 % still commits `1.5`; `window.blur` mid-drag behaves identically (both cleanup paths) |
| E2E-3.8 | Keyboard parity on the canvas (replaces the old scrubber arrow test) | focus `#waveformCanvas` (Ready, offset 0, sine3s) | 5× ArrowRight → readout `0:00.5 / 0:03.0`; Shift+ArrowRight → `0:01.5 / 0:03.0`; PageUp (3 s file → +0.3) → `0:01.8 / 0:03.0`; End → `0:03.0 / 0:03.0`; Home → `0:00.0 / 0:03.0`; `aria-valuenow`/`aria-valuetext` follow after each |
| E2E-3.9 | ARIA roles + tabindex (W-9/W-10) | assert in-page across states | **ready**: canvas `role="slider"`, `tabindex="0"`, `aria-valuemin="0"`, `aria-valuemax` = duration (raw float allowed — KB-17), `aria-valuenow` = offset, `aria-valuetext="Offset 0:00.0"`; readout `role="progressbar"`, `aria-valuenow` = songPosition, `aria-valuetext` formatted — the two roles are **distinct elements**; **noFile**: canvas `tabindex="-1"` (out of tab order); the progressbar readout is absent (no file) |
| E2E-3.10 | Param lock on the canvas (E2E-1.6 behavior preserved) | counting-in 8, Play → countingIn/playing → Stop | in countingIn **and** playing: `#waveformCanvas[aria-disabled="true"]` present and computed `pointer-events: none`; after Stop → ready: attribute absent; `#offsetScrubber` no longer exists in the DOM (grep: zero references in `index.html` and `test/e2e/`) |

## 6. Tempo suggestion — UX integration (Phase 6; `UiHandlersTest.html` + `tempo.spec.cjs`)

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| TD-U1.1 | P0 | Unit (mock-VM, fake `document`): all gate clauses hold — `bpm 120`, `bpmText "120"`, flag false, `activeElement ≠ #bpmInput`; stale `bpmClamped === true` (a prior clamped commit a re-drop outlived) | `applyTempoSuggestion({ bpm: 120, confidence: 0.85 })` | `bpm === 120`, `bpmText "120"`, `tempoSuggestion === 120`, `announcement === "Detected tempo 120 BPM"` (V-07 inventory +1); `bpmClamped` **cleared** (D-H hint mutual exclusion — the prefill is in-range, so the clamp hint cannot describe it; added as-built 2026-08-25 — the flag alone does not prevent coexistence, the prefill write does); flag **stays false** (a suggestion is not a touch) |
| TD-U1.2 | P0 | Gate would pass, but `onBpmStep(1)` ran first (flag true) | `applyTempoSuggestion({ bpm: 120, confidence: 0.85 })` | **no write**: bpm unchanged, no `tempoSuggestion`, no announcement, no hint |
| TD-U1.3 | P0 | Flag set by `commitBpmEntry` — both the clean path (type "140", Enter) and the garbage-restore path (`bpmText "abc"`, Enter → `_restoreLastValid`) | `applyTempoSuggestion(…)` after each | no prefill in either case (CR §2.5 row 3: typing garbage *is* a user touch); the restore path still restores the last valid value |
| TD-U1.4 | P0 | Mid-draft: `bpm 120`, `bpmText "90"` (divergent, gate clause 4), flag state irrelevant | `applyTempoSuggestion({ bpm: 120, confidence: 0.9 })` | **no prefill** — the field keeps `"90"` (W-16: never clobber an in-progress entry; the suggestion is silently dropped for this file) |
| TD-U1.5 | P0 | `#bpmInput` focused (`activeElement === #bpmInput`), all other clauses pass | `applyTempoSuggestion(…)` | no prefill (clause 3) — the user is typing; a fresh suggestion is available any time by re-dropping |
| TD-U1.6 | P0 | Any gate state | `applyTempoSuggestion(null)` | no prefill, no hint, no announcement (silence is the correct UX for "unknown", W-13) |
| TD-U1.7 | P1 | A successful prefill just landed (flag false by construction) | a second suggestion for the same live file (re-drop path: flag reset on load) | it prefills again — the prefill write never self-poisons the flag |
| TD-U1.8 | P1 | Unit: tempo task for buffer A pending at its yield; second load resolves (buffer B) | flush A's continuation, then B's | A's result writes nothing (same `_analysisValid` guard as peaks, W-14); B's result applies if its gate passes |
| TD-U1.9 | P1 | Unit: tempo task pending at its yield; `beforeUnmount` ran | flush the continuation | no write to the unmounted VM (W-15) |
| TD-U1.10 | P1 | Unit: `#bpmInput` with v-model + the new `@input` flag handler | simulated `input` events set `bpmText` ("1", "12", …) | each event sets the flag **and** leaves the draft write to v-model (`bpmText` holds the typed text, model `bpm` untouched until commit); order-independent (R-6); Enter still commits via `commitBpmEntry` (clamps as U-11 rev) |

**E2E (Phase 6 rows — `test/e2e/tempo.spec.cjs`; fixture `test/fixtures/clicks20.wav` per context D-K; never assert the fixture's duration string — R-9):**

| ID | Test | Steps | Expected |
|----|------|-------|----------|
| E2E-4.1 | Prefill happy path | fresh load; drop `clicks20.wav` (120 BPM ground truth) | `#bpmInput` value `"120"`; hint `Detected ~120 BPM` visible (`role="status"`); live region announces `Detected tempo 120 BPM`; the hint and the `bpmClamped` hint are never both shown |
| E2E-4.2 | Flag reset on load — re-drop re-suggests (CR §2.5 row 1) | E2E-4.1 state; edit `#bpmInput` to `"140"` + Enter (flag set); drop `clicks20.wav` **again** | the successful load resets the flag → prefill happens **again**: field returns to `"120"`, hint + announcement fire (the memo's "no prefill on re-drop" was wrong — the CR is authoritative) |
| E2E-4.3 | Negative fixture stays silent | drop `sine3s.mp3` (3 s → too few onsets → `null`) | `#bpmInput` value **unchanged** from before the drop; no "Detected" hint; no tempo announcement (silence is correct) |
| E2E-4.4 | Focused mid-draft + drop: the blur law commits first; the suggestion then lands visibly (W-16 re-pin — see note) | focus `#bpmInput`; type `"9"` (draft `"9"` ≠ model); drop `clicks20.wav` | decoding disables the field (`:disabled="!isReady"`) → the app's own blur law (RD-1) commits `"9"` (clamped 30); the re-drop's flag reset (CR §2.5 row 1) lets the prefill land **visibly**: field `"120"` + hint + announcement, stale clamp hint cleared. **Re-pinned 2026-08-25 (platform invariants — the original "draft survives" expectation is unreachable via any load trigger):** a drop event (trusted or synthetic) moves focus (native drop focus semantics), and even a focus-preserving load blurs the field via the decoding disable — a live mid-draft never reaches detection time. The no-clobber guarantee for a genuinely live mid-draft lives at the P0 unit level (TD-U1.4/TD-U1.5, gate read at write time, R-10) |

## Priority Ordering

| Priority | Scenarios | Rationale |
|----------|-----------|-----------|
| **P0** | WF-P1.1…WF-P1.3, WF-P1.8 · TD-1.1, TD-1.2, TD-1.7, TD-1.9 · WF-V1.1…WF-V1.4 · WF-I1.1, WF-I1.2 · E2E-3.1, E2E-3.2 · WF-I2.1…WF-I2.6 · E2E-3.5, E2E-3.6, E2E-3.8 · TD-U1.1…TD-U1.6 · E2E-4.1, E2E-4.3 | The feature doesn't work without these: faithful peaks, 120 ±1 at both rates (and never a confidently-wrong 60), single-render view, the staleness guard, the paint-not-delaying-Ready contract, the scrub law, the prefill gate, and the happy/negative E2E paths |
| **P1** | WF-P1.4…WF-P1.6, WF-P1.9 · TD-1.3…TD-1.5, TD-1.10…TD-1.12, TD-1.15 · WF-V1.5…WF-V1.7, WF-V1.9 · WF-I1.3, WF-I1.4 · E2E-3.3, E2E-3.4 · WF-I2.7…WF-I2.9 · E2E-3.7, E2E-3.9, E2E-3.10 · TD-U1.7…TD-U1.10 · E2E-4.2 | Structural correctness: guards, resize coalescing, keyboard parity, ARIA role split, flag lifecycle, fixture round-trip |
| **P2** | WF-P1.7 · TD-1.6, TD-1.8, TD-1.13, TD-1.14 · WF-V1.8, WF-V1.10 · WF-I1.5 · WF-I2.10 · E2E-4.4 | Edge cases and polish: stride determinism, alias-family outcomes, NaN guards, Safari capture throw, no-file backstop |
