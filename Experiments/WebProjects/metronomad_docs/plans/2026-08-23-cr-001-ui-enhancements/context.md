# CR 001 UI Enhancements — Context (stable whole-plan detail)

Pinned decisions D-A…D-M (design memo, 2026-08-23, **anchors corrected during plan spot-verification — see index.md "Key Discoveries" where noted**), module interfaces, fixture contract, scenario ID scheme, known behaviors, risk register, and cross-cutting constraints. The CR's W-1…W-17 dispositions are settled inputs, cited but not re-derived.

## Pinned Decisions

### D-A — Module placement: new `MyESModules/Analysis/` directory

Not `Utils/` (small single-purpose helpers). The two DSP modules are a distinct *concern* (signal analysis, ~150–300 lines each with own constants and test files):

```
MyESModules/Analysis/
├── channelData.js      # shared channel walk + mono mixdown (one helper — AGENTS.md "DO NOT Duplicate")
├── waveformPeaks.js    # extractPeaks + poolPeaks (pure)
└── tempoDetection.js   # detectTempo (pure)
```

The barrel (`MyESModules/index.js`, header warning at `:1-9`) gains one `Analysis` block. Per the silent-barrel-re-export learning (`_agent_docs/learnings/2026-08-22-esmodule-link-failure-is-silent.md`): every new test page imports its names **through the barrel**, so a missing re-export surfaces as a broken page (risk R-11), never a silent `undefined`.

### D-B — `channelData.js` interface (shared helper)

```js
// Number.isFinite-guarded; sampleRate explicit everywhere (W-8).
export function channelArrays(buffer)
// → { channels: Float32Array[], sampleRate, duration }
//   walks getChannelData(c) once; guards numberOfChannels/length;
//   degenerate buffer (non-finite/zero channels) → { channels: [], … }.

export function mixDown(channels)      // channels: Float32Array[]
// → Float32Array — element-wise mean; THE one mean implementation
//   (single channel returned as-is, no copy; empty → zero-length).

export function monoMixdown(buffer)
// → mixDown(channelArrays(buffer).channels) — the buffer-facing facade.
```

`tempoDetection` consumes `mixDown` (it takes `Float32Array[]` directly, not a buffer); `waveformPeaks` consumes `channelArrays` (per-channel min/max, not a mixdown — CR §1.2 min-of-mins/max-of-maxs). One mean helper, two call sites — AGENTS.md "DO NOT Duplicate".

### D-C — `waveformPeaks.js` interface

```js
export const PEAK_BUCKETS_DEFAULT = 4096;            // CR §1.2 fixed high resolution
export const PEAK_STRIDE_MAX_SAMPLES = 20_000_000;   // per channel; above → stride 4 (W-6)

export function extractPeaks(buffer, bucketCount = PEAK_BUCKETS_DEFAULT)
// → { mins: Float32Array, maxs: Float32Array, bucketCount, sampleRate }
//   - effective bucketCount = min(bucketCount, sampleCount)  [WF-P1.4]
//     (sine3s @ 44.1 kHz: 132 300 samples → 4096 buckets × ≈32 samples — CORRECTED from CR/memo)
//   - stride = sampleCount > PEAK_STRIDE_MAX_SAMPLES ? 4 : 1, applied
//     deterministically before bucketing (30-min worst case → ≈20 M effective samples)
//   - per-bucket min/max; stereo = min-of-mins / max-of-maxs
//   - NaN/Infinity channel samples treated as 0 (documented); non-finite
//     bucketCount → default; degenerate buffer → zero-length arrays

export function poolPeaks(peaks, targetBuckets)
// → { mins, maxs, bucketCount } — min/max pooling of the high-res source,
//   O(4096); targetBuckets ≥ source bucketCount → copy. The view pools to
//   CSS columns so resizes never re-walk the sample array (CR §1.2).
```

No `sourceBuffer` in the return — the **caller** (the VM) captures `this._buffer` identity for the staleness guard, keeping the function pure over its argument (D-E).

### D-D — `tempoDetection.js` interface + confidence metric (CR §2.3 step 5 pin)

```js
import { BPM_MIN, BPM_MAX } from '../Utils/paramClamps.js';   // 30/250 — NEVER re-declared

export const TEMPO = {
    HOP: 512,             // samples (≈11.6 ms @ 48 kHz)
    FRAME: 2048,          // samples
    WINDOW_SEC: 60,       // O-5(a): first 60 s of content
    PRIOR_MIN: 70,        // musical-prior band (70–180)
    PRIOR_MAX: 180,
    PRIOR_OUT_BAND_SCALE: 0.75,   // score multiplier for out-of-band candidates
    NOISE_FLOOR_SCALE: 0.01,      // trim floor = window peak energy × this (W-12)
    MIN_ONSET_FRAMES: 12,         // fewer onsets above floor in window → null (tuned 8→12 as-built — see deltas below)
    CONFIDENCE_THRESHOLD: 0.6,    // below → null (W-13: no suggestion > wrong suggestion)
    ALIAS_MIN_CORRELATION: 0.5,   // "non-weak" threshold for the out-of-band alias rule (added as-built — the mechanism prose is undefined without it)
    ALIAS_BAND: 0.1               // confidence runner-exclusion band (the "within 10 %" as a named constant; added as-built)
};

export function detectTempo(channels, sampleRate, maxWindowSec = TEMPO.WINDOW_SEC)
// channels: Float32Array[] (from channelArrays); sampleRate explicit (W-8)
// → { bpm: integer, confidence: number } | null
```

Pipeline (all math per-`sampleRate`; 44.1 kHz figures in the CR are illustrative only): mono mixdown → **leading-silence trim** (skip until frame energy first exceeds `peakEnergy × 0.01`, W-12) → frame energy (hop 512, window 2048, window clamped to `min(maxWindowSec · sampleRate, length)`) → onset strength `o[i] = max(0, e[i] − e[i−1])` → autocorrelation over candidate periods `p ∈ [60·sampleRate/(BPM_MAX·HOP), 60·sampleRate/(BPM_MIN·HOP)]` frames (≈21…172 @ 44.1 kHz; ≈23…187 @ 48 kHz — the app's **existing BPM clamp range**, per-`sampleRate` per W-8; the memo's `H·60/BPM` form was dimensionally missing `sampleRate` — corrected 2026-08-24) → candidate score `C(p) × (bpmInPriorBand ? 1 : 0.75)` with half/double rescoring (`C(p/2)`, `C(2p)` where in range) → **confidence = bestScore / bestNonAliasedRunnerScore**, runners excluding lags within 10 % of `best/2` and `best·2` (aliases of the same perceived pulse) → `null` when confidence < 0.6, onsets < `MIN_ONSET_FRAMES`, or the envelope is flat.

**Tuning contract (W-13):** the three numeric thresholds (0.75, 0.6, 8) are initial candidates **pinned by the TD-1.\* battery** — they may be adjusted during RED/GREEN *only* while keeping every pinned outcome (120 ±1 at both rates; half-time 120 → 120 or null, **never 60**; 75/150 → either or null; silence/tone/short → null). Mechanism note for TD-1.7: a genuine half-time train (onsets only every 2 beats) has its true period out-of-band with a *weak* in-band alias — the conservative reading of the metric is **null**, never the out-of-band tempo reported confidently. Test-anchored, not vibe-anchored.

**As-built deltas (Phase 2, 2026-08-24 — every pinned TD-1.\* outcome held):** (1) `MIN_ONSET_FRAMES` tuned 8 → 12 under this contract — with FRAME 2048 over HOP 512 (75 % overlap) each click's frame energy rises over TWO frames, both clearing the 1 % floor, so one click ≈ 2 onsets-above-floor (6 clicks → 11; the pinned 8 would have let the TD-1.11 short file through; the smallest pinned positive train yields ≈39). (2) `TEMPO` gained `ALIAS_MIN_CORRELATION: 0.5` — the TD-1.7 mechanism's "non-weak" threshold, undefined in the verbatim object — and `ALIAS_BAND: 0.1` (the confidence prose's "within 10 %" made a named constant). (3) `refinePeriod` (parabolic vertex fit around the best integer lag) — required because the battery cannot be met with integer lags alone (a 180 BPM period is 28.71 frames @ 44.1 kHz; lag 29 → 178 BPM, off the pinned ±1 by 2).

**TD-1.3 row correction (2026-08-24):** TD-1.3 and TD-1.7 pinned **byte-identical inputs** (20 clicks, 1 s spacing, 44.1 kHz) with contradictory outcomes (60 ± 1 vs 120-or-null-never-60) — a pure function cannot satisfy both. The TD-1.3 "still wins" expectation was a plan error: its own rationale ("in-band aliases have ≈0 correlation") is precisely the TD-1.7 P0 mechanism's null condition. Corrected in place to `null` in `behavior-specs.md` and `phase-2-tempo-pure.md`; the P0 pin governs.

Cost: bounded by the window — 60 s → ≈2.9 M samples (envelope pass) + ≈5 600 frames × ≈165 candidate lags of autocorrelation — **well under 50 ms** on the main thread (48 kHz figures; **measured 14 ms** warmed-up, Node/V8, 2026-08-24 — the citable constant for Phase 7 docs).

### D-E — Async post-load hook + generation/buffer-identity guard (single hook point, CR §3)

**Hook location:** the `result.ok` branch of `onFileDropped`, after the READY flip (`createMetronomadMethods.js:78-88`; method `:66-97`). Exact additions, in order:

```js
this._buffer = result.buffer;
this._loadGeneration = (this._loadGeneration || 0) + 1;   // D4 discipline, UI-side
this._bpmTouchedThisFile = false;                          // CR §2.5 lifecycle row 1
this.waveformReady = false;                                 // placeholder reappears (O-2/W-17)
// …existing offset clamp / READY flip / error clear / announcement…
this._schedulePostLoadTasks(result.buffer, this._loadGeneration);
```

New VM methods in `createMetronomadMethods.js` (mock-VM testable):

```js
// TWO-TASK SHAPE FROM DAY ONE (Phase 4 defines both; tempo body is a
// guarded no-op until Phase 6 fills it in — the D-M sequencing constraint):
_schedulePostLoadTasks(buffer, generation) {
    this._runPeakExtraction(buffer, generation);
    this._runTempoSuggestion(buffer, generation);
},
async _runPeakExtraction(buffer, generation) {
    await new Promise((r) => setTimeout(r, 0));   // pinned yield: Ready paint is already done (W-6)
    if (!this._analysisValid(buffer, generation)) return;
    const peaks = extractPeaks(buffer);           // non-reactive handle
    if (!this._analysisValid(buffer, generation)) return;   // re-check before paint (N-14 shape)
    this._peaks = { ...peaks };                   // caller keeps buffer identity for the guard
    this.waveformReady = true;
},
// Phase 6 fills the body (D-I); Phase 4 ships:
//   async _runTempoSuggestion(buffer, generation) { /* Phase 6 */ }
_analysisValid(buffer, generation) {
    // W-14 (superseded file) + W-15 (unmount): one guard, three clauses
    return !this._disposed && generation === this._loadGeneration && buffer === this._buffer;
}
```

- **`setTimeout(0)` is the pinned yield** — not `requestIdleCallback` (rejected, CR §6), not a second RAF (D9). Chunked processing stays the documented W-6 fallback, not v1.
- `beforeUnmount` adds `this._disposed = true; this._peaks = null; this._buffer = null;` — `_disposed` is the unmount half of the same guard, mirroring the N-14 precedent `if (!this._engine) return;` at `createMetronomadMethods.js:242` (corrected anchor).
- **Failure paths** (codec/decode/tooLong) do **not** bump the generation — the old buffer stays live (F-05), so an in-flight result for it remains valid; pinned by WF-I1.5.
- The two tasks race the same generation harmlessly (independent state); the tempo gate must read `document.activeElement`/`bpmText` **at write time**, never captured at kickoff (risk R-10).

### D-F — `createWaveformView` factory (new `MyESModules/App/createWaveformView.js`)

Mirrors `createBeatDots(vm, base, callbacks)` (`createBeatDots.js:41-56`): DI-pure, vm captured once, browser globals injected with defaults, `dispose()` idempotent and owning only its own resources.

```js
export function createWaveformView(vm, base = {}, callbacks = {})
// base: {
//   canvasId = 'waveformCanvas',
//   raf, cancelRaf,                    // window defaults (I-7 convention)
//   devicePixelRatio = () => window.devicePixelRatio,
//   getDom = (id) => document.getElementById(id),
//   getHeightCss = () => 64,           // injected height provider (testable W-4 clamp)
// }
// callbacks (all OPTIONAL — Phase 4 wires none; Phase 5 wires the three):
//   onScrubStart(tenths), onScrubMove(tenths), onScrubEnd(commit /*bool*/)
// returns {
//   init(canvas),         // DPR sizing + (only if callbacks.onScrubStart is
//                         // provided) pointerdown/move/up/cancel listeners +
//                         // window pointerup + window.blur safety net
//   setPeaks(peaks),      // stores high-res peaks; scheduleRender()
//   setDraft(tenths|null),// transient draft marker painted in-canvas by the
//                         // next render (no VM round-trip; the DOM overlay
//                         // marker tracks the COMMITTED offset only)
//   resize(widthCss, heightCss),  // DPR backing store + scheduleRender()
//   scheduleRender(),     // RAF-coalesced, single-pending guard (W-5)
//   dispose()             // idempotent: cancel pending RAF, remove ALL
//                         // listeners (canvas + window pointerup + blur +
//                         // window resize), canvas.width = 0; canvas.height = 0
// }
```

Render: `poolPeaks(peaks, cssWidth)` → **one vertical line per CSS column** from `y(min)` to `y(max)`, mirrored about the horizontal center (O-3), batched in a single path pass. `#app { max-width: 640px }` (`Style.css:7`) bounds draw count to ≤640 lines — width-bounded, **not** DPR-bounded (risk R-8). No internal RAF loop beyond the coalesced render (the playhead is a DOM overlay, D-H). `pointerdown` → x → tenths via `vm.duration`, `setPointerCapture` wrapped in try/catch (W-1); committed end → `canvas.focus()`, cancel → no focus (CR §1.5).

**Wiring:** built in `mounted()` after the beat dots (`createMetronomadLifecycle.js:78-84` area) as `this._waveformView = createWaveformView(this, {}, { /* Phase 5: onScrubStart: … */ })`; `init(canvas)` at mount (canvas is static DOM). `beforeUnmount` (`createMetronomadLifecycle.js:86-104`) inserts `waveformView.dispose()` **between `beatDots.stopAll()` and `engine.dispose()`** (listener removal before renderer disposal; the lifecycle owns all teardown — the visualizer never touches the engine, RD-6 discipline).

**As-built deltas (Phase 3, 2026-08-24 — every pinned WF-V1.\* outcome held):** (1) `resize(widthCss, heightCss = _getHeightCss())` — the W-5 storm scenarios call `resize(400)` one-arg; the height defaults to the injected provider (the W-4 clamp stays CSS-driven). (2) `base` gained `getWindow = () => window` — the window listener map (`pointerup`/`blur`/`resize`) must be injectable for WF-V1.4's listener-removal pins without global patching (R-I7.1 discipline); purely additive, I-7 shape. (3) **init performs the container-measured DPR sizing** (`resize(canvas.parentElement.clientWidth, getHeightCss())` at the end of `init`) — the pinned init contract says "DPR sizing + listeners", and Phase 4's wiring calls only `init` at mount (no window-resize event fires at mount, so without this the backing store would stay 0×0 and the waveform would never paint). Handoff-audit catch, not a scenario deviation.

### D-G — Scrub + keyboard handlers (VM methods, `createMetronomadMethods.js`; Phase 5)

```js
onWaveformScrubStart(tenths) {          // pointerdown
    if (this.isParamLocked) return;     // U-12 JS backstop (CSS: pointer-events none)
    this.offsetDraft = clampOffset(tenths, this.duration);
    this._waveformView.setDraft(this.offsetDraft);
},
onWaveformScrubMove(tenths) {
    if (this.offsetDraft === null) return;
    this.offsetDraft = clampOffset(tenths, this.duration);   // SAME quantize-then-reclamp law — never a second rule
    this._waveformView.setDraft(this.offsetDraft);
},
onWaveformScrubEnd(commit) {
    this._waveformView.setDraft(null);
    if (commit && this.offsetDraft !== null) {
        this.onOffsetScrub(this.offsetDraft);   // reuse the existing commit law (:170-178)
    }
    this.offsetDraft = null;          // pointercancel / off-screen / blur → discard
},
onWaveformKeydown(e) {
    // ←/→ = ±0.1 s (the old scrubber step); Shift+←/→ = ±1 s (W-9);
    // PageUp/PageDown = ±10 % of duration; Home/End = 0 / duration.
    // Every commit funnels through this.onOffsetScrub(next) — one quantization law.
    // preventDefault only AFTER a commit was handled.
}
```

- `offsetDraft` is a **new reactive data field** (`createMetronomadData.js`, init `null`); the view calls `setDraft` so the in-canvas marker and the `displayPosition` computed (D-H) track the draft.
- `pointercancel`, global `window` `pointerup` (capture released off-canvas), `window` `blur` → `onScrubEnd(false)` (W-1; both cleanup paths pinned in tests).
- **Param lock:** `pointer-events: none` + `aria-disabled` on the canvas; the `isParamLocked` early-return is the JS backstop (same rule as every control, U-12).
- **`onOffsetScrub` is retained and becomes *the* shared scrub law** — its stale JSDoc premise ("the scrubber's own range already keeps values in [0, max]", `:168-169`) is re-pointed to the canvas in Phase 5 (risk R-5). The U-10 unit tests (`UiHandlersTest.html:647-658`) keep passing unchanged.

### D-H — `index.html` / `Style.css` element-level contract

**Phase 4 (additive — `#offsetScrubber` still present):** replace the `.progress` block (`index.html:124-138`, stale N-10 comment updated to cite the W-10 role move):

```html
<!-- Waveform progress (replaces the 8px bar; CR 2026-08-23-001).
     W-10: the progressbar role MOVES to the readout (the visible value). -->
<div class="progress">
    <div class="waveform" :class="{ 'waveform--locked': isParamLocked }">
        <!-- O-2 placeholder: the old thin track until peaks are painted
             (paint gate W-17: !decoding.active && waveformReady) -->
        <div v-if="fileName && !waveformReady" class="progress-track">
            <div class="progress-offset-marker" :style="{ left: offsetMarkerPercent + '%' }"></div>
        </div>
        <canvas id="waveformCanvas"
                v-show="fileName && waveformReady"
                role="img" tabindex="-1"          <!-- Phase 4: display-only (keyboard.spec stays green) -->
                :aria-label="'Waveform of ' + fileName"
                :data-loaded="waveformReady ? 'true' : null"></canvas>
        <div v-if="fileName" class="waveform-dim" :style="{ width: markerPercent + '%' }"></div>
        <div v-if="fileName" class="waveform-offset-marker"
             :style="{ left: markerPercent + '%' }"></div>
        <div id="waveformPlayhead" v-if="fileName" class="waveform-playhead"
             :data-position-tenths="Math.round(displayPosition * 10)"
             :style="{ left: playheadPercent + '%' }"></div>
    </div>
    <div v-if="fileName" class="progress-readout" role="progressbar"
         aria-label="Song progress"
         aria-valuemin="0" :aria-valuemax="duration"
         :aria-valuenow="displayPosition" :aria-valuetext="formattedDisplayPosition">
        {{ formattedDisplayPosition }} / {{ formattedDuration }}
    </div>
</div>
```

**Phase 5 (canvas becomes the slider; scrubber removed):** canvas attrs become `role="slider"`, `:tabindex="isReady ? 0 : -1"`, `aria-label="Start offset"`, `:aria-valuemin="0"`, `:aria-valuemax="duration"`, `:aria-valuenow="offset"`, `:aria-valuetext="'Offset ' + formatTime(offset)"`, `:aria-disabled="isParamLocked || null"`, `@keydown="onWaveformKeydown"`; `#offsetScrubber` + its N-15 comment (`index.html:75-79`) are **deleted** (O-1).

**New computeds in `createMetronomadApp.js`** (alongside `progressPercent` `:51-55` / `offsetMarkerPercent` `:57-61`, which are **untouched** — risk R-4):

```js
displayPosition()          { return this.offsetDraft !== null ? this.offsetDraft : this.songPosition; }
formattedDisplayPosition() { return formatTime(this.displayPosition); }
playheadPercent()          { /* progressPercent math on displayPosition; guarded → 0 */ }
markerPercent()            { /* draft percent while dragging, else offsetMarkerPercent */ }
```

Playhead in Ready parks at the offset via the existing `offset` watcher (`createMetronomadApp.js:78-80`); during playback it rides `songPosition` at the existing 10 Hz tenth-second cadence (`createBeatDots.js:142-149`) — **zero new clocks, zero new state beyond `offsetDraft`** (CR §1.4). **Reduced-motion disposition (W-7, KB-14): the playhead STAYS** — functional position indicator, no CSS animation, 10 Hz tenths steps only.

**Data fields (`createMetronomadData.js`, all Phase 4):** `offsetDraft: null`, `waveformReady: false`, `tempoSuggestion: null` (hint `<p>` lands in Phase 6 — D-I).

**Phase 6 (D-I):** below the existing `bpmClamped` hint (`index.html:70`):

```html
<p v-if="tempoSuggestion" class="clamp-hint" role="status">Detected ~{{ tempoSuggestion }} BPM</p>
```

Hints are structurally mutually exclusive. **Rationale corrected 2026-08-25 (Phase 6 as-built):** the touched flag alone does NOT prevent coexistence — a clamped commit followed by a re-drop resets the flag and the prefill would land beside the stale clamp hint. The mutual exclusion is enforced by the prefill write itself clearing `bpmClamped` (the prefilled value is in-range by `clampBpm`, so the clamp hint cannot describe it) — pinned by TD-U1.1. String pinned (W-3, short for narrow viewports): **`Detected ~122 BPM`** (N = the prefilled integer).

**`Style.css`** (progress block region `:293-325`; the file's only media query today is `prefers-reduced-motion` at `:285` — Phase 4 introduces the first width breakpoint):

- `.progress` (margin) kept; `.progress-track` + `.progress-offset-marker` kept **for the placeholder**; **`.progress-fill` deleted** (dead — Phase 4 removes its only consumer; `progressPercent` computed survives per R-4).
- `.waveform { position: relative; height: 64px; touch-action: pan-y; }` — CSS comment: "pan-y, not none: horizontal scrub → JS, vertical swipe still scrolls (W-2, skill interaction.md)".
- `@media (max-width: 375px) { .waveform { height: 48px; } }` — W-4, E2E-viewport-pinned (E2E-3.4).
- `#waveformCanvas { position: absolute; inset: 0; width: 100%; height: 100%; display: block; cursor: crosshair; }`; `.waveform--locked #waveformCanvas { pointer-events: none; }`
- `.waveform-offset-marker` (2 px accent, full height — re-purposed `.progress-offset-marker` visual), `.waveform-playhead` (2 px `--color-primary`, full height), `.waveform-dim` (`rgba(0,0,0,.25)`, O-4 kept — one cheap overlay) — all `pointer-events: none`.
- KB-6 hooks (`data-loaded`, `data-position-tenths`) carry **no styling and no ARIA** — do not style them.

### D-I — Tempo prefill (methods; Phase 6)

```js
async _runTempoSuggestion(buffer, generation) {   // replaces the Phase-4 no-op
    await new Promise((r) => setTimeout(r, 0));
    if (!this._analysisValid(buffer, generation)) return;
    const { channels, sampleRate } = channelArrays(buffer);
    const result = detectTempo(channels, sampleRate);
    if (!this._analysisValid(buffer, generation)) return;   // post-compute re-check (W-14)
    this.applyTempoSuggestion(result);
},
applyTempoSuggestion(result) {
    // Prefill gate — ALL must hold (W-16), read AT WRITE TIME (risk R-10):
    //  1. result && result.bpm            (confidence already gated inside detectTempo)
    //  2. !this._bpmTouchedThisFile       (non-reactive flag)
    //  3. document.activeElement !== #bpmInput
    //  4. this.bpmText === String(this.bpm)   (not mid-draft)
    // → this.bpm = clampBpm(result.bpm); this.bpmText = String(this.bpm);
    //   this.tempoSuggestion = this.bpm;
    //   this.announcement = `Detected tempo ${this.bpm} BPM`;   // V-07 inventory +1
    // The write does NOT set _bpmTouchedThisFile (a suggestion is not a touch).
    // null → no prefill, no hint, no announcement (silence is correct, W-13).
}
```

`_bpmTouchedThisFile` is a **non-reactive** flag. Set-true sites: top of `commitBpmEntry()` (`createMetronomadMethods.js:137` — covers the `_restoreLastValid` garbage branch, CR §2.5 row 3; **not** inside `_restoreLastValid` itself, which is shared with count-in — risk R-12), top of `onBpmStep()` (`:146`), and a new `@input="onBpmTextInput"` on `#bpmInput` (`index.html:64`) that sets **only** the flag (programmatic v-model writes don't fire DOM `input` events, so the prefill write can't self-poison; both `@input` listeners are legal and order-independent — risk R-6). Reset to `false` at the top of the `onFileDropped` ok-branch (D-E) — **a re-drop re-suggests even after the user edited BPM on the previous file** (CR §2.5 row 1; the design memo's "no prefill on re-drop" was wrong — E2E-4.2 pins the CR behavior).

### D-J — Test surface inventory

**New unit files** (auto-discovered by `scripts/run-tests.cjs:220-226` — no registration):

- `MyComponents/WaveformPeaksTest.html` — WF-P1.\* (Phase 1).
- `MyComponents/TempoDetectionTest.html` — TD-1.\* (Phase 2). Trains synthesized **in-page as plain Float32Arrays** using the `clickBuffers.js` recipe constants (1568/1047 Hz, 60 ms, 5 ms attack, exp decay to 1e-5) — **zero real AudioContext** (engine-test convention). Both 44 100 and 48 000 Hz (W-8).
- `MyComponents/WaveformViewTest.html` — WF-V1.\* (Phase 3). Proxy-mocked real 2D ctx + fake RAF collector (skill `testing-unit.md` patterns); no global patching.

**Updated unit:** `MyComponents/UiHandlersTest.html` (mock-VM pattern, `:34-60`): WF-I1.\* staleness/guard rows (Phase 4), WF-I2.\* scrub/keyboard rows (Phase 5), TD-U1.\* prefill-gate/flag rows (Phase 6); V-07 announcement inventory gains "Detected tempo N BPM".

**Updated E2E (every `#offsetScrubber` reference — complete list verified 2026-08-23):**

| File | Lines | Change |
|---|---|---|
| `test/e2e/smoke.spec.cjs` | `:30` (CONTROLS) | Phase 4: canvas moves to a **presence-only** list (a canvas can't be `:disabled` — R-1); Phase 5: `#offsetScrubber` dropped from CONTROLS |
| `test/e2e/keyboard.spec.cjs` | `:51` (exact Tab order), `:71` (locked-skip list), `:110-112` (arrow test) | Phase 5: new canonical order — `waveformCanvas` replaces `offsetScrubber` between `bpmPlusBtn` and `offsetInput`; arrow test focuses `#waveformCanvas`, 5× ArrowRight → readout `0:00.5 / 0:03.0` (same expectation, new target) |
| `test/e2e/playback.spec.cjs` | `:194` (re-enabled list), `:255` (lockedInputs) | Phase 5: scrubber out; canvas lock asserted as `#waveformCanvas[aria-disabled="true"]` present in countingIn/playing, absent in ready (E2E-1.6 behavior preserved) |
| `test/e2e/waveform.spec.cjs` | **new** | E2E-3.1…E2E-3.4 (Phase 4), E2E-3.5…E2E-3.10 (Phase 5) |
| `test/e2e/tempo.spec.cjs` | **new** | E2E-4.1…E2E-4.4 (Phase 6) |

### D-K — New E2E fixture: `test/fixtures/clicks20.wav`

- **What:** 20 s, 44 100 Hz, mono, 16-bit PCM WAV; a 120 BPM click train — 40 clicks at t = 0.0, 0.5, …, 19.5 s, each a 1047 Hz (C6) 60 ms burst with the `clickBuffers.js` envelope, **1568 Hz (accent) every 4th click** (exercises the accent/regular mix; TD-1.15 mirrors it).
- **Size:** 20 × 44 100 × 2 = 1 764 000 data bytes + 44-byte RIFF/WAVE header = **1 764 044 bytes**.
- **Why WAV:** PCM WAV decodes everywhere (`Howler.codecs('wav')` true in Chromium — `codecSupport.js:9-16`), zero encoder dependency, byte-exact known tempo, no lossy artifacts, no container tags (consistent with CR §2.2's metadata deferral).
- **Why 20 s:** 40 onsets comfortably clear `MIN_ONSET_FRAMES` (8); decode + detection stay fast; the 60 s analysis window clamps to duration (CR §2.4 short-file rule at the boundary).
- **Provenance:** commit a tiny dependency-free generator `scripts/make-clicks20-wav.cjs` (plain Node: RIFF/WAVE header + PCM samples, same envelope math as `clickBuffers.js:33-55`) and run it once; commit both. Reproducible fixture — an improvement over the out-of-band `sine3s.mp3` provenance; the script doubles as living documentation of the tempo ground truth. The 48 kHz unit cases need **no** fixture (in-page synthesis).
- **E2E note (R-9):** don't assert the fixture's duration string anywhere in `tempo.spec.cjs` — assert the BPM field, hint, and announcement only.

### D-L — Scenario ID scheme

Single-letter prefixes are exhausted (B, C, F, H, I, N, P, T, U, V; review R/C). Bare `W-` is **taken by the CR's world-review findings** — two-letter prefixes:

| Prefix | Domain | Home suite |
|---|---|---|
| `WF-P1.*` | waveform **p**eaks pure module | `WaveformPeaksTest.html` |
| `WF-V1.*` | waveform **v**iew factory | `WaveformViewTest.html` |
| `WF-I1.*` | waveform wiring/async guard (Phase 4) | `UiHandlersTest.html` + `waveform.spec.cjs` |
| `WF-I2.*` | waveform **i**nteraction: scrub/keyboard/ARIA (Phase 5) | `UiHandlersTest.html` + `waveform.spec.cjs` |
| `TD-1.*` | **t**empo **d**etection pure module | `TempoDetectionTest.html` |
| `TD-U1.*` | tempo suggestion **U**X integration (prefill gate, flag) | `UiHandlersTest.html` + `tempo.spec.cjs` |
| `E2E-3.*` | waveform E2E rows | `waveform.spec.cjs` |
| `E2E-4.*` | tempo E2E rows | `tempo.spec.cjs` |

### D-M — Phase clustering

See the phase map in `index.md`. File ownership is partitioned per phase (each file's contract lives in exactly one phase); the sequencing constraint — **Phase 4 defines `_schedulePostLoadTasks` in two-task shape from day one** — is the one cross-phase pin.

## Known Behaviors (KB-14…KB-17 — written into v1 `context.md` in Phase 7)

- **KB-14 — The playhead stays under `prefers-reduced-motion` (W-7).** It is a functional position indicator (the visual twin of the readout text), not decorative motion: no CSS animation, moves only in the existing 10 Hz tenths steps. The beat dots' pulse → static swap is unaffected. Do not "fix" it away.
- **KB-15 — Tempo suggestion is a heuristic, not ground truth (CR §4).** Tempo drift (accelerando/decelerando, live recordings) → smeared "average" over the 60 s window — the estimate is the window average, never the current tempo; a sparse-but-rhythmic intro at a different feel within the first 60 s can bias the estimate; half-time pairs *inside* the 70–180 prior band (75/150) are ambiguous by construction; short files → `null` (correct UX, not a bug). All three: the user's manual entry is authoritative — limitations, not defects.
- **KB-16 — Waveform paint gate + placeholder during re-decode (W-17, risk R-13).** The waveform paints only when `!decoding.active && waveformReady`. While a *second* file decodes, the previous file's waveform (or placeholder) stays visible until the READY flip — intentional; do not "fix" it into a blank flash.
- **KB-17 — `aria-valuemax` (and the old range's `:max`) carry raw non-round floats** (e.g. `3.0000000001`) (risk R-3). `formatTime`/`clampOffset` absorb them; the raw attribute is acceptable (native ranges did the same at `index.html:77`). Do not "fix" it into a divergence.

## Risk Register (planning memo §3, R-1…R-13; owning phase in parens)

| # | Risk / gotcha | Disposition (phase) |
|---|---|---|
| R-1 | Canvas is not `:disabled`-able — lock contract becomes `aria-disabled` + `pointer-events: none` + `tabindex="-1"`; smoke CONTROLS helper needs a presence-only list | Phase 4 (helper split), Phase 5 (aria asserts) |
| R-2 | Tab order changes structurally — `keyboard.spec.cjs:51` pins an exact 8-element sequence; Phase 4's canvas is `tabindex="-1"` (stays green); Phase 5 swaps the slot in the same commit as the scrubber removal | Phases 4/5 |
| R-3 | `aria-valuemax` non-round float — accepted (KB-17) | Phase 5 (noted in spec) |
| R-4 | `progressPercent` becomes load-bearing — keep its contract untouched; add `playheadPercent` on top (UiHandlers computed tests stay green) | Phase 4 |
| R-5 | `onOffsetScrub` JSDoc premise ("the scrubber's own range…") goes stale when the range is removed — re-point it; the method becomes *the* scrub law | Phase 5 |
| R-6 | `v-model` + second `@input` on `#bpmInput` — both fire; the flag handler is a no-op-except-flag setter; test v-model still owns the draft write | Phase 6 |
| R-7 | `data-position-tenths` is a string at 10 Hz via reactivity — E2E compares stringified tenths; the hook exists only with a file loaded (`v-if`) | Phase 4 |
| R-8 | `#app` max-width 640 px bounds draw count to ≤640 CSS columns (not the CR's ≤1200); pin "one line per CSS column" so cost is width-bounded, not DPR-bounded | Phase 3 |
| R-9 | WAV fixture duration can carry a fractional last sample — never assert the duration string in `tempo.spec.cjs` | Phase 6 |
| R-10 | The two `setTimeout(0)` tasks share a generation — harmless, but the tempo gate reads `activeElement`/`bpmText` at **write** time, never captured at kickoff | Phase 6 |
| R-11 | **Broken-page RED shape for new barrel names** (learning `2026-08-22-esmodule-link-failure-is-silent.md`): a missing export fails ES-module *linking* — the test page dies before `mocha.run()`, so the runner reports a page error, not per-test failures. Phases 1–3 state this explicitly so build-tdd doesn't chase a phantom | Phases 1–3 |
| R-12 | `_restoreLastValid('bpm')` is shared with count-in (`:117-133`) — the touched flag is set in `commitBpmEntry`/`onBpmStep`, never inside `_restoreLastValid` (count-in commits must not poison BPM suggestion) | Phase 6 |
| R-13 | Placeholder during a second file's decode shows the *old* waveform — pin as intended (KB-16) with scenario WF-I1.4 so it isn't "fixed" | Phase 4 |

## CR §4 Limitations (documented, not fixed)

Tempo drift → "average" estimate; sparse-but-rhythmic intros within the first 60 s can bias the estimate; half-time pairs inside the 70–180 prior band are ambiguous by construction. All three are "the user's manual entry is authoritative" cases (KB-15). Out of scope for v1: container metadata, offset-centered re-detection, re-detect button, zoom/pan, per-channel display, loop points, non-integer BPM, time signatures, offset-to-beat snapping.

## Cross-Cutting Constraints

- **Frozen architecture:** `playbackEngine.js` (D4 generation counter, D5 single `start(when, offset)`, 25 ms/100 ms scheduler), `howlerSetup.js` (ctx setup, `masterGain`, codec gate, `autoUnlock` default-true, `autoSuspend = false`), D9 visual-clock ownership, the fileLoader buffer/URL lifecycle (F-05 single-buffer invariant). Neither feature touches them.
- **Strings:** the new user-facing strings are owned here — "Detected ~N BPM" (hint), "Detected tempo N BPM" (V-07 polite announcement, inventory +1), and the canvas aria-label ("Waveform of {fileName}" in Phase 4's display-only state, replaced by "Start offset" when it becomes the slider in Phase 5). All other strings stay verbatim.
- **DI convention:** dependencies injected as factory parameters — never imported where a parameter would do. `createWaveformView` callbacks are optional and looked up inside handlers (skill: look up in callbacks, not at factory time).
- **Commits:** per phase, `Co-Authored-By: LittleLight <noreply@traveler.dstny>`; commits are `build-quick-work`'s responsibility, not the plan's.
- **Baseline gate per phase:** `node scripts/run-tests.cjs` fully green (count grows from 158) and `npx playwright test` fully green (23 + new); server on :8000, user-started.

## Plan World-Review Addendum (2026-08-23, world-review over the authored plan)

Dispositions of the plan-level review pass. **UX-1 was a factual error and was fixed in place** (WF-I2.8, E2E-3.8, Phase 5 prose); the rest are accept-and-document:

- **UX-1 (fixed):** the CR §1.5 attribution "PageUp/Down = the native range's coarse step" is wrong — a native range with `step="0.1"` moves PageUp/Down by step×10 (1.0 s), not 10 % of duration. Our ±10 % of duration is a deliberate enhancement over native parity, and the scenario wording now says so. Do not "correct" it back to native behavior.
- **UX-2:** iOS Safari OS gestures (two-finger scroll/rotate) can fire `pointercancel` or drop capture mid-drag — both flow through the W-1 cleanup paths as `onScrubEnd(false)` (discard). WF-V1.9 case (d) pins the in-page `pointercancel` path.
- **UX-3:** `role="slider"` on a canvas has known NVDA/VoiceOver configuration quirks. The markup follows WAI-ARIA custom-slider guidance; the Phase 7 dual-SR pass is the acceptance gate — if a major SR mis-reads it, the fallback is the retained `#offsetInput` text field (exact entry never regresses).
- **UX-4:** tempo-drift expectation gap — the estimate is the window *average*, never the current tempo (KB-15 now says so explicitly).
- **UX-5:** scrub coordinates are computed in CSS space (`x / cssWidth · duration`), independent of DPR and backing-store size — a multi-monitor DPI change mid-drag does not affect scrub accuracy. No code consequence; documented so it isn't "optimized" into device-pixel math.
- **PERF-1:** detection runs on the main thread inside the post-Ready `setTimeout(0)` yield (Phase 6); the <50 ms @ 48 kHz budget plus the E2E-3.1 "Ready not delayed" convention cover it; chunked processing remains the documented W-6 fallback if low-end measurement shows a hitch.
- **PERF-2:** the playhead is a CSS-positioned DOM overlay, independent of canvas repaint — a resize storm (WF-V1.2 coalescing) can never desync playhead from waveform. Documented, no action.

## Code World-Review Addendum (2026-08-25, world-review over the Phase 6 as-built change set)

- **UX-6 (Discussion — pinned conflict, no code change):** the tempo prefill is the first event announced twice — the hint `<p role="status">Detected ~N BPM</p>` (inserted → announced, markup pinned by CR §2.5 + E2E-4.1) and the live-region `Detected tempo N BPM` (V-07 inventory, CR-pinned). The existing clamp hints never set `announcement`, so the double-read is new to Phase 6. Both halves are settled constraints — removing `role="status"` from the hint would contradict the CR's "existing clamp-hint slot (`role=\"status\"`)" and the E2E-4.1 assertion. Routed to the Phase 7 VoiceOver acceptance item: if the double-announcement is confusing in practice, the fix is a CR-level spec change (one of the two pinned surfaces yields), not an in-plan edit.
- **DOC-1 (fixed in place):** the `onBpmTextInput` JSDoc said "the two @input listeners" — `v-model` is a directive, not a listener; wording corrected to say the directive owns the draft write and the `@input` handler only sets the flag (TD-U1.10 pins both orders).
- **PERF (no action):** measured — `clicks20.wav` (1.76 MB PCM) decode + detection sits far inside the E2E-4.1 500 ms signal window and the PERF-1 <50 ms detection budget. No consequence.

## References

- `_agent_docs/specifications/change-requests/2026-08-23-001-ui-enhancements.md` — the CR (source of truth; §6 W-table settled)
- `_agent_docs/plans/2026-08-17-metronomad-v1/` — `context.md` (D1–D11, KB-1…KB-13), `behavior-specs.md` (v1 scenario set: T-35, U-10, U-12, V-07, B-04, F-05)
- `_agent_docs/plans/2026-08-22-address-v1-review/` — RD-1…RD-6 (commit-on-Enter/blur, teardown/DI), R-* rows
- `MyESModules/App/createMetronomadMethods.js` — hook point `:66-97` (ok-branch `:78-88`), `commitBpmEntry` `:137`, `onBpmStep` `:146`, `onOffsetScrub` `:170-178`, N-14 guard `:242`
- `MyESModules/App/createMetronomadLifecycle.js` — `mounted()` `:32-83` (beat dots `:78-84`), `beforeUnmount()` `:86-104`
- `MyESModules/App/createMetronomadApp.js` — computeds `:51-61`, Ready `offset` watcher `:78-80`
- `MyESModules/App/createBeatDots.js` — DI shape `:41-56`, songPosition throttle `:142-149`
- `MyESModules/Utils/paramClamps.js` — `BPM_MIN/MAX` `:8-10`, `clampBpm` `:22-26`, `clampOffset` `:59-65`
- `MyESModules/Audio/clickBuffers.js` — recipe constants `:14-19`, envelope `:33-55`
- `index.html` — BPM group `:59-71`, scrubber `:75-79`, progress block `:124-138`; `Style.css` — progress block `:293-325`, `@media` `:285`, `#app` `:7`
- `test/e2e/` — `smoke.spec.cjs:30`, `keyboard.spec.cjs:51,71,110-112`, `playback.spec.cjs:43-67 (startRecordedSequence),194,255`; `MyComponents/UiHandlersTest.html:34-60 (mock-VM),647-658 (U-10)`
- `.pi/skills/building-web-apps/references/` — `canvas-2d.md` (lifecycle/DPR/GPU release), `interaction.md` (pointer capture try/catch, `touch-action: pan-y`, global pointerup + blur safety net), `testing-unit.md` (Proxy ctx, fake RAF collector, mock-VM), `memory-management.md` (teardown ordering), `audio-scheduling.md` (generation guards)
- `_agent_docs/learnings/2026-08-22-esmodule-link-failure-is-silent.md` — R-11
