# CR 2026-08-23-001 — UI Enhancements: Waveform Progress Display + BPM Detection

**Status:** Expanded + world-reviewed (qwen-agentworld-35b-a3b, §6) — ready for planning
**Date:** 2026-08-23 (original request); expanded + world-review incorporated 2026-08-23 (build-docs)

---

## Original Requests (verbatim)

### Show Wave Form for Progress
In order to give the user more feedback on where to put the offset position, it would be good to show the waveform for the audoi file visually in place of the current progress bar.

### Detect Beats Per Minute
Is there a way to analyze the audio or examine its metadata to set a BPM value based on the song added?

---

## 0. Capability Assessment: Does Howler.js Provide These Features?

**Short answer: no — Howler.js provides neither a waveform/peak API nor any metadata/BPM analysis. But Metronomad does not need it to, because the app already owns the decoded `AudioBuffer` itself.**

Evidence:

1. **Howler 2.2.3 has no analysis surface.** The public API (Howler / Howl / Sound) exposes playback, seek, volume, and codec checks only. There is no peak/waveform method, no tag reader, no DSP. And the decoded buffer is **not retrievable from a Howl** — it lives in Howler's module-private `cache[src]` and is nulled from the sound node after `stop()` (research §5, pitfall 5).
2. **Metronomad already decodes its own buffer.** Per the v1 architecture (research §4, Option B — "Howler context + custom scheduled playback"), `MyESModules/File/fileLoader.js` decodes the dropped file directly (`file.arrayBuffer()` → `context.decodeAudioData(bytes)`) and the decoded `AudioBuffer` is held on the VM as the non-reactive `_buffer` handle (`createMetronomadMethods.js`). Both features are therefore built on standard Web Audio `AudioBuffer` accessors — `getChannelData(c)`, `numberOfChannels`, `sampleRate`, `duration` — with **zero new dependencies and zero Howler involvement**.
3. **Howler's role is unchanged** and stays exactly what `MyESModules/Audio/howlerSetup.js` documents: AudioContext setup (webkit fallback), `masterGain`, `Howler.codecs()` gate, `autoUnlock` first-touch unlock, `autoSuspend = false`. Nothing in this CR touches that contract or the sample-accurate playback path (`playbackEngine.js` is untouched).
4. **File *metadata* (ID3/Vorbis tags) is a separate concern** Howler never touches — it would mean parsing the raw container bytes. Assessed and deferred (see §2.2): low hit-rate, format-specific, poor value for a hand-rolled parser. Audio analysis of the decoded samples is the recommended path.

**Consequence for planning:** both features are (a) pure functions of the already-decoded buffer, (b) new pure modules under `MyESModules/` + thin view wiring, (c) progressive — computed asynchronously *after* the app reaches Ready, never blocking decode → Ready.

**World-review note (§6):** the reviewer confirmed the Howler boundary is sound and flagged no capability gap. One cross-cutting correction was incorporated: **`AudioBuffer.sampleRate` is not a constant** — Chromium/Firefox resample decoded buffers to the AudioContext (device) rate (commonly 48 000 Hz) while some WebKit builds return the file's native rate. Every frame/hop/period computation in both new pure modules must therefore take `sampleRate` as an explicit input; the "44.1 kHz" figures in this CR are illustrative only.

---

## 1. Waveform for Progress

### 1.1 Goal

Replace the 8 px progress bar (`index.html` `.progress-track` block; `Style.css` ≈ lines 293–325: `.progress`, `.progress-track`, `.progress-fill`, `.progress-offset-marker`, `.progress-readout`) with a waveform view of the loaded song that:

- renders the **full-song waveform** (amplitude over time) so the user can *see* where the offset sits — intro length, silent gaps, dense sections;
- keeps the **live progress** visible during playback (a playhead);
- keeps the **offset marker** (existing `.progress-offset-marker` visual — 2 px accent line at `offsetMarkerPercent`);
- makes setting the offset a **direct-manipulation gesture**: click or drag on the waveform to scrub the offset (supersedes the coarse 0.1 s-step `#offsetScrubber` range input for visual users; the `#offsetInput` text field stays for exact `m:ss.t` entry).

### 1.2 Data Source and Peak Extraction

New **pure** module — `MyESModules/Utils/waveformPeaks.js` (directory placement is a plan decision; see §3):

```
extractPeaks(buffer, highResBuckets) → { mins: Float32Array, maxs: Float32Array, bucketCount }
```

- Single pass over each channel's `getChannelData(c)`; per-bucket `min`/`max`; stereo merged as min-of-mins / max-of-maxs (a mono-side-only feature never reads as quieter).
- Leading `Number.isFinite` guards per the skill's es-modules numeric-guard rule (zero-length buffer, `bucketCount` > sample count → effective bucket count = sample count; the 3 s `sine3s.mp3` fixture is only ~132 k samples ≈ 32 effective buckets at 4096).
- Compute **once per file load** at a fixed high resolution (~4096 buckets); any smaller target (canvas pixel columns) is derived by min/max pooling (O(4096), trivial) so canvas resizes never re-walk the full sample array.
- **Cost:** 5 min @ 44.1 kHz stereo ≈ 26.5 M samples → tens of ms; the 30-min worst case (79 M samples) is cut to ≈ 20 M effective samples by **stride sampling** (every 4th sample — visually identical peaks). Both are small, but the contract is pinned: peaks run **after** the Ready flip, and E2E asserts (in-page timing) that decode → Ready is never delayed by peak work (W-6). If low-end mobile measurement ever shows a visible hitch, the documented fallback is chunked processing (yield between channel/slice chunks) — a plan-time decision, not a v1 default.
- **Staleness:** peak work is async after Ready, so a newer file can land mid-flight. The result is applied only if the buffer it was computed from is still the live buffer (buffer-identity / generation guard — same discipline as the engine's D4 generation counter; see §6 W-14).

### 1.3 Rendering (new factory — `createWaveformView.js`)

Follow the skill's canvas-2d lifecycle exactly: `init()` → `resize()` → `scheduleRender()` → `dispose()`; **DPR scaling** for Retina; `canvas.width = 0; canvas.height = 0` in `dispose()` for GPU release (memory-management.md).

- Canvas sized to container width × ~64–96 px CSS, DPR-scaled backing store. **Responsive clamp (W-4):** height steps down on narrow viewports (e.g. 48 px below 375 px CSS) so the waveform + readout + controls stay within reach on small screens; pin the breakpoint/heights in the plan.
- **Draw once per (peaks, size) pair:** one vertical line per CSS column from `y(min)` to `y(max)`, mirrored about the horizontal center (open question O-3), batched via `Path2D` or fillRect (≤ ~1200 columns — trivial).
- **Resize storms (W-5):** `scheduleRender()` is RAF-coalesced with a single-pending-render guard (the skill's canvas-2d pattern) — a rotation or window-resize burst must leave at most one pending render, with the final size winning. Pin in unit tests with a fake RAF collector.
- **Overlay elements as absolutely-positioned divs** (no per-frame canvas redraw):
  - **offset marker** — reuse the existing `.progress-offset-marker` visual, positioned at `offsetMarkerPercent`;
  - **playhead** — 1–2 px line at the existing `progressPercent` computed (re-purposed: `:style="{ left: progressPercent + '%' }"` — no new state, no new computed, no imperative per-frame code; see §1.4);
  - optional pre-offset dim (translucent overlay from 0 → `offsetMarkerPercent`, open question O-4).
- The `.progress-readout` text line (position / duration, tabular nums) is retained beneath the waveform.

### 1.4 Playhead Clock and Cadence (D9 constraint + reduced-motion disposition)

The app-level RAF loop in `createBeatDots.js` is the **sole owner of the visual clock** (AGENTS.md — the engine never drives visuals; beat phase is a pure function of the audio clock). **Do not add a second RAF loop for the playhead.**

- `createBeatDots._render` already rewrites `vm.songPosition` only when the tenth-second changes (10 updates/s, the readout throttle). The playhead binds to that same value via the existing `progressPercent` computed (§1.3) — so it moves in **0.1 s steps at 10 Hz**, compositor-cheap, with zero new clock or imperative code.
- In **Ready** state (nothing playing), the existing `offset` watcher in `createMetronomadApp.js` already sets `songPosition = offset` — the playhead parks at the offset with no new state.
- **Hidden-tab pause/snap (U-17)** behavior comes from the existing loop; the playhead snaps with it because it derives from `songPosition`.
- **prefers-reduced-motion (W-7):** the playhead is a *functional position indicator* (the visual twin of the position readout text), not decorative motion — like a video scrubber's playhead, it stays. It adds **no CSS animation** and moves only in the existing 10 Hz tenths steps, so nothing extra needs suppressing under reduced motion; the beat dots' pulse → static swap is unaffected. State this disposition explicitly in the plan so it isn't "fixed" away later.

### 1.5 Interaction and Accessibility (offset scrubbing)

**Pointer path** (per skill interaction.md, with the world-review corrections W-1/W-2):

- `pointerdown` on the canvas → `setPointerCapture(pointerId)` **wrapped in try/catch** (Safari can throw `InvalidPointerId` on stale captures); `pointermove` → draft position with live playhead + readout, quantized through `clampOffset` (the same quantize-then-reclamp tenths law as `onOffsetScrub` — **never a second quantization rule**); `pointerup` → commit `this.offset` + sync `offsetText` + hint logic identical to the scrubber path.
- **`pointercancel` is a first-class end event** (iOS fires it when the OS takes the gesture — scroll, rotation, incoming call): it releases capture and discards the draft without committing, exactly like the global-`pointerup` off-screen path. Both cleanup paths (global `pointerup` + `window.blur` safety net) are pinned in tests.
- **`touch-action: pan-y`** on the canvas (not `none`): horizontal scrub gestures go to JS, vertical swipes still scroll the page — the right trade for a horizontal scrubber (skill interaction.md documents the pan-y/none trade-off; note it in a CSS comment).
- **Param lock:** while audio runs (`isParamLocked`), the canvas is non-interactive (`pointer-events: none` + `aria-disabled`) — same rule as every other control (U-12).
- **Focus after drag:** returns to the canvas (the drag target), so keyboard continuation with arrows is one action away; `#offsetInput` is reached by tab order or click, never by surprise focus jumps.

**ARIA model — one element, one role each (W-9/W-10):**

| Element | Role | Value | Notes |
|---|---|---|---|
| waveform canvas | `role="slider"` | `aria-valuenow=offset`, `aria-valuemin=0`, `aria-valuemax=duration`, `aria-label="Start offset"` | The interactive offset control. `aria-valuetext` = `"Offset m:ss.t"` (offset only — no dual meaning). |
| `.progress-readout` div | `role="progressbar"` | `aria-valuenow=songPosition`, `aria-valuemin=0`, `aria-valuemax=duration` | The read-only progress meaning the current `.progress` div carries today (same values, same Ready-state `songPosition=offset` semantics) — the role moves from the bar container to the readout element, which is the visible value. Not a live region: 10 Hz value changes are *queried*, not announced, so there is no SR churn. |
| `#offsetInput` text | (unchanged) | exact `m:ss.t` entry | Unchanged contract (V-04). |

- **Keyboard parity with the native range it replaces (W-9):** `←/→` = 0.1 s (the old scrubber step), `Shift+←/→` = 1 s, `PageUp/PageDown` = 10 % of duration (the native range's coarse step), `Home/End` = 0 / duration. All commits flow through the same `clampOffset` law and update `aria-valuetext`.
- **O-1 disposition (kept: replace `#offsetScrubber`).** The native range's 8 px track conveys nothing about where the offset sits relative to content — that is the entire point of the CR. Replacing it is acceptable because parity is restored deliberately: the keyboard table above, `aria-*` wiring, and a manual screen-reader pass (VoiceOver/NVDA) in the acceptance checklist. Coexistence (canvas + hidden or visible range) was rejected as redundant control.

### 1.6 State and Memory

- Peaks live on the VM as a **non-reactive handle** (`this._peaks = { mins, maxs, bucketCount, sourceBuffer }`) plus a reactive `waveformReady` flag (drives visibility + the E2E hook).
- **Staleness guards (W-14/W-15):** both async post-load tasks (peaks, tempo) capture the source buffer (or a load generation) before their first await-yield and drop their result if the live buffer no longer matches — the D4 generation-guard discipline from `playbackEngine.js`, applied to UI-side async work. Unmount mid-flight is the same guard with a null check (the N-14 post-await unmount-guard precedent): stale callbacks write nothing to an unmounted VM.
- Replaced on every new load (the single-buffer invariant F-05 makes the old peaks dead the moment the buffer is replaced); cleared on the same exit paths as `fileLoader.release()` (`beforeUnmount`), and the canvas disposed per memory-management.md.
- **Paint gate (W-17):** the waveform paints only when `!decoding.active && waveformReady` — no frame from a superseded or half-loaded state.
- Size: 2 × 4096 × 4 B = 32 KB of peaks — negligible against the ~10.6 MB/min decoded buffer.

### 1.7 Test and E2E Hooks (KB-6 convention: minimal, no styling, no ARIA)

- `#waveformCanvas[data-loaded]` — set when peaks are first painted;
- `#waveformPlayhead[data-position-tenths]` — quantized position for in-page timing assertions.

**Unit (new `MyComponents/WaveformPeaksTest.html`):**
- `extractPeaks` on synthetic `Float32Array` channel data: silence → all-zero peaks; full-scale sine → expected per-bucket envelope; stereo channel disagreement → min-of-mins/max-of-maxs; 1-sample buffer; `bucketCount` > sample count; NaN/Infinity input guards.

**Unit (view factory, Proxy-mocked canvas 2D ctx per skill testing-unit.md + fake RAF collector):**
- draws exactly once per (peaks, size) pair; a resize burst coalesces to a single pending render with the final size; `dispose()` zeroes the canvas dimensions; playhead position derives from `songPosition` (no internal RAF — the fake RAF collector stays empty except the coalesced render).

**E2E (Playwright, chromium):**
- drop `sine3s.mp3` (existing fixture) → `data-loaded` appears; **decode → Ready is not delayed by peak work** (in-page 5 ms transition logger — existing timing convention);
- pointer-drag on the canvas sets the offset (quantized to tenths; `#offsetInput` mirrors); **`pointercancel`** (dispatched in-page) discards the draft without committing;
- keyboard: arrows / Shift / PageUp-Down / Home-End adjust the offset per §1.5; `aria-valuenow`/`aria-valuetext` reflect it; focus returns to the canvas after a drag;
- **ARIA roles:** canvas exposes `slider`, readout exposes `progressbar` (assert roles + value attributes in-page);
- playhead tracks `songPosition` during playback (in-page timing assertion);
- narrow viewport (emulated 360 px): waveform height clamps per §1.3 and the readout stays visible.

### 1.8 Draft Acceptance Criteria (plan to refine into scenarios)

1. After a successful load, the waveform paints within one frame of peak computation; until then the existing thin progress track renders as placeholder (O-2).
2. The waveform shape is faithful: a silent span in a test fixture renders as a gap.
3. Click at `x` sets `offset ≈ x/width × duration` (tenths-quantized); drag scrubs continuously; text field + readout mirror throughout; param lock disables it; `pointercancel`/off-screen release leave no stuck state.
4. During playback the playhead tracks `songPosition` in 0.1 s steps; reduced-motion users get the same functional indicator with no added animation.
5. Keyboard contract per §1.5 works; SR pass (VoiceOver + NVDA manual checklist): slider and progressbar roles are distinct and correct; no announcement churn at 10 Hz.
6. Replacing the file mid-computation drops the stale peaks (no paint from the old buffer); unmount mid-computation writes nothing; canvas is disposed (no GPU leak).
7. Zero new dependencies; Howler and the playback engine untouched.

### 1.9 Open Questions

- **O-1 — Replace or coexist with `#offsetScrubber`?** Disposition recorded in §1.5: **replace**, with the keyboard/ARIA parity table as the cost of replacement.
- **O-2 — What renders before peaks are ready?** Recommendation: keep the existing thin progress track as placeholder (zero new failure modes, no layout shift if the waveform region reserves its height).
- **O-3 — Mirrored min/max bars (symmetric about center) vs top-anchored?** Recommendation: mirrored — the standard audio-editor look.
- **O-4 — Dim the pre-offset region?** Nice-to-have; cheap (one absolutely-positioned div) — keep in v1 if it does not complicate the layering.

---

## 2. BPM Detection (Tempo Suggestion)

### 2.1 Goal

On song load, **estimate the tempo from the audio** and prefill the BPM field as an explicit, correctable suggestion. Detection is never ground truth: the BPM field stays fully user-owned (integer, 30–250, `clampBpm`), playback is never blocked on detection, and a failed/uncertain detection is silent. **Product principle (W-13): a wrong-but-confident suggestion is worse than no suggestion** — a wrong BPM silently ruins the count-in. When in doubt, the correct output is `null`.

### 2.2 Why Not Metadata (answered: low value, deferred)

- **mp3/ID3v2 has no standard BPM frame.** Non-standard `TBPM` or a `TXXX` frame with description "BPM" exist from some encoders — rare.
- **m4a/AAC (ilst) has no BPM atom.**
- **Vorbis comments** (ogg/flac, and some wav) *can* carry `BPM=` — occasional at best.
- A hand-rolled ID3v2 header scan is ~100 lines for a low hit-rate, format-specific win, and it adds a byte-parsing concern the app has deliberately avoided. **Decision: skip container metadata in v1.** (If ever revisited, the raw bytes are already in hand at `file.arrayBuffer()` in `fileLoader.js` — a tag parser would add no I/O.)

### 2.3 Detection Pipeline (pure DSP — no FFT, no new dependencies)

New **pure** module — `MyESModules/Utils/tempoDetection.js` (name/directory a plan decision; see §3). Signature: `detectTempo(channels: Float32Array[], sampleRate: number) → { bpm, confidence } | null` — **`sampleRate` is an explicit input, never a constant** (W-8: decoded buffers are 44.1 kHz, 48 kHz, or 96 kHz depending on browser/device). Every frame/hop/period figure below is expressed per `sampleRate`; the 44.1 kHz numbers are illustrative only.

1. **Mono mixdown** — average of `getChannelData(c)` across channels (share the channel-walk utility with peak extraction — one sampling helper, AGENTS.md "DO NOT Duplicate").
2. **Leading-silence trim (W-12)** — skip frames until energy first exceeds a noise floor (relative to the window's peak energy), then analyze from there. This is the cheap, principled answer to songs that open with silence/fade-in; it is *not* a full sliding-window search (that is v2, O-5b).
3. **Onset envelope** — frame energy with hop ≈ 512 samples (≈ 11.6 ms at 48 kHz; frame rate ≈ `sampleRate/512` frames/s), window ≈ 2048; onset strength `o[i] = max(0, e[i] − e[i−1])` (half-wave-rectified positive difference; an optional median pre-filter of `o[]` for robustness is a one-line refinement).
4. **Tempo estimation** — autocorrelation of `o[]` over candidate periods `p` spanning **30–250 BPM** (`p ∈ [H · 60/250, H · 60/30]` in frames — *exactly the app's existing BPM clamp range*); pick the best `p`, then resolve the half/double ambiguity by scoring `C(p)`, `C(p/2)`, `C(2p)` (where in range) with a musical prior favoring **70–180 BPM**, where nearly all human music sits.
5. **Confidence (W-11/W-13)** — an explicit metric, pinned in the plan (candidate: best autocorrelation peak vs. the runner-up non-aliased peak, i.e. excluding lags within ~10 % of `p/2` and `2p`); **conservative threshold — below it, return `null`**. The threshold is tuned so the synthetic half-time and sparse-onset cases in §2.7 resolve to the prior-correct tempo *or* `null`, never a confidently-wrong one.

**Cost:** the analysis window (below) bounds the work regardless of song length — 60 s → ≈ 2.9 M samples for the envelope pass + ≈ 5 500 frames × ≈ 150 lags of autocorrelation ≈ **well under 50 ms** on the main thread (48 kHz figures; 44.1 kHz is proportionally less).

**Half-time honesty (W-12):** a 120-BPM song whose only onsets fall every 2 beats (half-time feel) has a stronger 60-BPM correlation peak; the 70–180 prior rescues the common cases (60/45 are out of the prior band → 120/90 wins). The genuinely ambiguous case — a 75-vs-150 half-time pair, *both* inside the prior band — may resolve either way or to `null`; that is an accepted v1 limitation, pinned by test, not papered over.

**Documented upgrade path:** STFT-based spectral flux is strictly better for kick-light material but adds FFT code; if energy-only accuracy disappoints during manual acceptance, that is the v2 path. No FFT in v1.

### 2.4 Analysis Window (open question O-5)

- **(a) First 60 s of content** (recommended for v1): after the §2.3 leading-silence trim, analyze 60 s. Bounded cost, simple, no UI feedback loops.
- (b) Window centered on the *current offset*, re-run (debounced) when the offset moves materially — smarter for songs with long sparse-but-not-silent intros, but couples detection to the offset UI and invites recompute churn; **v2 candidate**.
- **Known limitation (W-12):** a sparse-but-rhythmic *intro at a different feel* within the first 60 s can bias or defeat the estimate; the user's manual BPM entry is always authoritative. Documented in the plan's limitations.
- **Known limitation (W-12):** tempo drift (live recordings, accelerando) yields a smeared, "average" estimate; v1 assumes a stable tempo within the window. Documented.
- Short files: the window clamps to `duration`; a 3 s file has too few onsets for reliable tempo — expect and document `null` (that is correct UX, not a bug).

### 2.5 UX Contract (suggestion, not command)

- Detection runs **async after Ready** (same progressive pattern as the waveform peaks — §3 shared hook point) and is **generation-guarded** (§1.6 W-14): a result computed from a superseded file is dropped before it touches any state.
- **Prefill rule:** write `bpm`/`bpmText` to the detected value + hint + announcement **only when all of**:
  1. the result is non-null and above the §2.3 confidence threshold;
  2. `bpmTouchedThisFile` is false (see flag table below);
  3. the BPM field is **not focused and not mid-draft** — `bpmText` equals `String(bpm)` (W-16: never clobber an in-progress entry; if the user is typing, the suggestion is silently dropped for this file — the user is clearly entering their own value; a fresh suggestion is available any time by re-dropping the file).
- **Hint:** existing clamp-hint slot (`role="status"`), string kept short for narrow viewports (W-3): **"Detected ~122 BPM"** (the plan pins the exact string in the spec; the existing hints wrap naturally as `<p>`, no ellipsis machinery needed).
- **Announcement:** added to the V-07 live-region inventory (polite), e.g. "Detected tempo 122 BPM".
- **Never overwrite a user edit** — the flag makes this structural, not an if-check at write time.
- Null / low-confidence → **no prefill, no hint** (silence is the correct UX for "unknown").
- **No "Detect BPM" button in v1** — an explicit re-run (tied to O-5b) is a v2 candidate.

**`bpmTouchedThisFile` flag lifecycle (W-16):**

| Event | Flag |
|---|---|
| Successful file load (before detection starts) | **reset to false** |
| `onBpmStep` (either stepper) | set true |
| `commitBpmEntry` — including the `_restoreLastValid('bpm')` branch (typing garbage *is* a user touch) | set true |
| `bpmText` `v-model` input event (any keystroke in the field) | set true |
| Auto-prefill write itself | **not** set true (a suggestion is not a touch — the user may still correct it, and a re-drop re-suggests) |

### 2.6 Draft Acceptance Criteria (plan to refine into scenarios)

1. A synthetic click train at 120 BPM (1568/1047 Hz bursts — the existing `clickBuffers.js` recipe) is detected as 120 ± 1 — **at both 44.1 kHz and 48 kHz** synthetic rates (W-8: pins the sampleRate parameter, not an accident of 44.1).
2. Half/double resolution: a 120-BPM train is not reported as 60 or 240; a 75-BPM train is not reported as 150 (the 70–180 prior is what carries these — pin both directions); a **half-time 120-BPM train** (onsets every 2 beats only) resolves to 120 *or* `null` — never 60 (W-12).
3. Near-silence, steady-tone (onset-free), and short-file (window > duration) inputs → `null`; no prefill, no hint.
4. Ready is reachable without waiting for detection (in-page timing, existing convention); detection lands within the cost budget of §2.3.
5. **Staleness:** a detection result for a superseded file never writes (drop-while-in-flight test, W-14); unmount mid-detection writes nothing (W-15).
6. **Mid-draft prefill is impossible:** with the field focused and a divergent draft, a resolving detection changes nothing (W-16).
7. Zero new dependencies; no AudioContext nodes (detection is pure math on decoded samples); Howler and the playback engine untouched.

### 2.7 Tests

- **Unit (new `MyComponents/TempoDetectionTest.html`):** synthetic trains at 60/90/120/180/240 BPM (synthesized via the existing click-buffer recipe or plain impulse arrays); each also at 48 kHz; silence; steady tone; half-time variants (120→never 60; 75/150 pair documented); leading-silence trim (silence prefix then train → still detected); NaN/Infinity guards; short-file clamp (window > duration).
- **E2E:** needs a **new fixture with a known tempo** (≈ 20 s click-train WAV at 120 BPM — generated once at authoring time; `sine3s.mp3` has no usable rhythm). Drop it → BPM field prefills + hint + announcement; edit the BPM; drop a second file → prefill happens again (flag reset); negative fixture (the 3 s sine) → field untouched, no hint, no announcement.

---

## 3. Shared Architecture Notes (both features)

- **One shared hook point, not two ad-hoc call sites.** Both features consume `_buffer` and follow the same "async after Ready" progressive pattern. The plan should define a single post-load callback in the file-load success path (`onFileDropped`'s `result.ok` branch, or a dedicated `onBufferLoaded(buffer, duration)`) that kicks off (a) peak extraction + (b) tempo detection as independent async tasks, each carrying its own generation guard.
- **Module placement:** both are pure signal-processing functions — candidates for `MyESModules/Utils/` alongside `beatGrid`/`paramClamps`, or a new `MyESModules/Analysis/` directory if the plan prefers a distinct concern boundary. Either way: named exports, barrel re-exports in `MyESModules/index.js` (and verify the barrel explicitly — the re-export-of-missing-name-is-silent gotcha, `_agent_docs/learnings/2026-08-22-esmodule-link-failure-is-silent.md`).
- **The precision path is untouched.** `playbackEngine.js`, the beat grid, and the count-in contract are not inputs to either feature. Detection and peaks read the same `_buffer` the engine already plays.
- **Shared sampling utility:** mono mixdown / channel walk used by both peaks and tempo should be one helper, not two copies (AGENTS.md "DO NOT Duplicate").

## 4. Out of Scope (v1) + Documented Limitations

- Container metadata parsing (§2.2 — deferred with rationale).
- Live re-detection on offset change (O-5b) and an explicit re-detect button.
- Waveform zoom/pan, per-channel display, loop-point selection.
- Non-integer BPM; time signatures; **snapping the offset to detected beats** — genuinely useful (detected tempo + offset could snap the marker to a beat grid) but a separate CR.
- **Limitations to document in the plan:** tempo drift → "average" estimate (W-12); sparse-but-rhythmic intros within the first 60 s can bias the estimate (W-12); half-time pairs inside the 70–180 prior band are ambiguous by construction (W-12). All three are "the user's manual entry is authoritative" cases, not defects.

## 5. References

- `_agent_docs/research/howlerjs-research.md` — §4 Option B (app owns the buffer), §5 pitfall 5 (Howl does not expose its buffer), §2 (decode path)
- `MyESModules/File/fileLoader.js` — own decode, single-buffer invariant F-05, 30-min guard
- `MyESModules/App/createBeatDots.js` — sole visual-clock owner (D9), `songPosition` tenth-second throttle, reduced-motion/hidden-tab behavior
- `MyESModules/App/createMetronomadApp.js` — `progressPercent`/`offsetMarkerPercent` computed (playhead re-uses `progressPercent`), Ready-state `offset` watcher
- `index.html` — `.progress` block, `#offsetScrubber`, BPM control group; `Style.css` ≈ lines 293–325
- `MyESModules/Utils/paramClamps.js` — `clampOffset` quantize-then-reclamp law (the waveform scrub must follow it, not invent a second one), `clampBpm`
- `MyESModules/Audio/clickBuffers.js` — 1568/1047 Hz click recipe (reused to synthesize tempo-test audio)
- `.pi/skills/building-web-apps/SKILL.md` — canvas-2d.md, interaction.md, memory-management.md, es-modules.md, audio-scheduling.md (generation guards), testing-unit.md / testing-e2e.md
- `AGENTS.md` — KB-6 hook convention, DI factory convention, "DO NOT Duplicate"

## 6. World-Review Addendum (qwen-agentworld-35b-a3b)

World-review subagent pass over the expanded CR (2026-08-23). Findings are incorporated **in place** where they changed the design (each section cites its W-number); the table records the full disposition.

| ID | Finding (summary) | Disposition |
|----|-------------------|-------------|
| W-1 | iOS Safari: `setPointerCapture` can throw on stale captures; finger-slip leaves drag stuck | **Incorporated** — try/catch around capture; `pointercancel` as first-class end event; global pointerup + blur safety net (was already required, now explicit) — §1.5 |
| W-2 | `touch-action: none` kills page scroll on mobile | **Incorporated (improved)** — `touch-action: pan-y` instead: horizontal scrub to JS, vertical scroll preserved — §1.5 |
| W-3 | BPM hint string too long for narrow viewports | **Incorporated** — short string "Detected ~122 BPM", pinned in spec; existing `<p>` wraps naturally — §2.5 |
| W-4 | Waveform height vs. small-screen real estate | **Incorporated** — responsive height clamp (48 px < 375 px), E2E viewport pin — §1.3/§1.7 |
| W-5 | DPR-3 canvas + rotation resize storms | **Incorporated** — RAF-coalesced single-pending-render guard pinned in unit tests — §1.3/§1.7 |
| W-6 | Peak-extraction jank risk on low-end mobile (30-min files) | **Partially incorporated** — stride sampling + post-Ready timing + E2E "Ready not delayed" assertion in v1; chunked processing documented as fallback, plan-time decision — §1.2 |
| W-7 | Is the moving playhead "motion" under prefers-reduced-motion? | **Incorporated (design decision)** — playhead is a functional position indicator (stays, like a video scrubber's), adds no CSS animation, moves only in the existing 10 Hz tenths steps — §1.4 |
| W-8 | 48 kHz files: hardcoded 44.1 kHz frame math would skew detection ~9 % | **Incorporated (correct)** — `sampleRate` is an explicit input to both pure modules; 48 kHz synthetic test cases pinned — §0 note, §2.3, §2.6 |
| W-9 | Replacing the native range loses native slider semantics (SR announcements, PageUp/Down) | **Partially incorporated** — parity restored deliberately: full keyboard table incl. PageUp/Down = 10 % of duration, aria wiring, manual SR acceptance pass; coexistence rejected as redundant — §1.5 |
| W-10 | Dual role conflict: one element as both slider (offset) and progressbar (song position) | **Incorporated (correct)** — ARIA split: canvas = slider (offset only), `.progress-readout` = progressbar (song position; same values/semantics the current bar carries, role moved to the visible-value element) — §1.5 |
| W-11 | Half-time feel → strong 60-BPM peak; wrong-but-confident suggestion ruins the count-in | **Incorporated** — confidence metric + conservative threshold (below → null); half-time synthetic tests pinned (120→never 60; 75/150 pair documented as ambiguous) — §2.3/§2.6/§2.7 |
| W-12 | Long sparse intros / tempo drift → first-60-s window analyzes the wrong part | **Incorporated** — leading-silence trim (cheap, principled); sparse-intro and drift documented as v1 limitations; offset-centered window stays O-5b/v2 — §2.3/§2.4/§4 |
| W-13 | Undefined confidence threshold; cost of a wrong suggestion | **Incorporated** — explicit metric (plan-pinned) + conservative threshold + "no suggestion > wrong suggestion" product principle — §2.1/§2.3/§2.5 |
| W-14 | File replaced while detection/peaks in flight → stale result writes to new file's state | **Incorporated (correct)** — generation/buffer-identity guard on both async tasks (D4 discipline, N-14 precedent); drop-while-in-flight tests — §1.2/§1.6/§2.5/§2.6 |
| W-15 | Unmount mid-extraction/mid-detection → writes to unmounted VM | **Incorporated** — same guard with null check; beforeUnmount teardown; tests — §1.6/§2.6 |
| W-16 | `bpmTouchedThisFile` lifecycle vs. `_restoreLastValid`; draft/model divergence on prefill | **Incorporated** — explicit flag lifecycle table; prefill requires unfocused + draft==model — §2.5 |
| W-17 | Decode-state race: waveform paint vs. `decoding.active` / offset watcher | **Mostly no-op, pinned** — the watcher semantics are pre-existing and unchanged; explicit paint gate `!decoding.active && waveformReady` added — §1.6 |

**Rejected/adjusted reviewer suggestions:** (a) keeping the native range input alongside the canvas (W-9) — rejected, redundant control; parity table + manual SR pass is the cost of replacement. (b) `requestIdleCallback`/chunking as a v1 default (W-6) — rejected as default; the two post-Ready tasks are small (tens of ms), and chunking is retained as a documented fallback if low-end measurement shows a hitch. (c) SR "10 Hz valuetext churn" concern — mitigated by construction: the progressbar role is not a live region, so 10 Hz value changes are query-only, never announced; the split in W-10 removes the dual-value confusion regardless.
