# Metronomad — Howler.js Library Research

**Date:** 2026-08-17
**Sources:** howler.js v2.2.3 README + `#documentation` (github.com/goldfire/howler.js), source analysis of `src/howler.core.js` (master branch), live verification in headless Chromium (playwright)
**Target:** Decide how Metronomad plays a locally-dropped mp3 with a **sample-accurate start at a given offset**, rhythmically aligned to a metronome count-in (spec §5: song starts on the beat boundary after the last click)

**Companion harness:** [`howler-research-test.html`](./howler-research-test.html) — self-contained verification page (embeds a 3s MP3, loads howler 2.2.3 from cdnjs). Run in a browser console: `await runHowlerTest()`

---

## 1. Howler.js at a Glance

- **Version:** 2.2.3 (current, via cdnjs/jsDelivr/npm). MIT, ~7KB gzipped, zero dependencies.
- **Model:** Defaults to the **Web Audio API**, falls back to HTML5 `<audio>` per-file (e.g., XHR failure flips a Howl to HTML5 mode automatically).
- **Object layers:**
  - **`Howler`** (global): `ctx` (the AudioContext — *public, documented*), `masterGain` (documented), `volume()`, `mute()`, `stop()`, `codecs(ext)`, `unload()`, `autoSuspend`, `autoUnlock`, `state`.
  - **`Howl`** (a group; **one audio file per Howl**): `src`, `format`, `html5`, `preload`, `loop`, `sprite`, `rate`, `pool`, `xhr`, `volume`, `fade`, `play()`, `pause()`, `stop()`, `seek()`, `duration()`, `playing()`, `state()`, `unload()`, events: `load`, `loaderror`, `play`, `playerror`, `end`, `pause`, `stop`, `seek`, `fade`, `mute`, `volume`, `rate`, `unlock`, `resume`.
  - **`Sound`** (per-playback node, internal): in Web Audio mode a `GainNode` connected to `Howler.masterGain`; a fresh `AudioBufferSourceNode` is created for each `play()` call.

### Key APIs for Metronomad

| API | Notes (verified against source) |
|-----|--------------------------------|
| `new Howl({src, format, html5, onload, ...})` | `src` = URLs or base64 data URIs. Codec is inferred from the **URL extension** or data-URI MIME; **blob: URLs have no extension → `format: ['mp3']` is mandatory** (see §3). |
| `howl.play()` | Web Audio: `bufferSource.start(0, seek, duration)` — starts at the **next render quantum** after the JS call. **No "start at time T" parameter exists.** |
| `howl.seek([s], [id])` | Paused (Web Audio): stores `_seek`, applied on next `play()`. **Playing (Web Audio): pause → seek → play cycle** (adds jitter; avoid on precision paths). HTML5: sets `node.currentTime`. |
| `howl.stop()` | Stops and **resets seek to 0** (verified). |
| `howl.duration()` | Exact (`buffer.duration` in Web Audio mode); 0 until `load`. |
| `howl.unload()` | Stops, destroys, **removes the decoded buffer from Howler's cache** — use when replacing files. |
| `Howler.codecs(ext)` | Cached `Audio.canPlayType` result; extensions: `mp3, mpeg, opus, ogg, oga, wav, aac, caf, m4a, m4b, mp4, weba, webm, dolby, flac`. The right runtime gate for "what can this browser play". |
| `Howler.ctx` | The shared AudioContext. **This is what makes Howler useful for us**: we can schedule our own nodes on the same clock/graph. |
| `Howler.masterGain` | Documented public GainNode into `ctx.destination` — global volume/mute applies to anything connected to it. |
| `Howler.autoSuspend` | True by default: suspends the context 30s after "no Howler sound playing". **Breaks custom playback — see Pitfall 1.** |
| `Howler.autoUnlock` | True by default: silently unlocks mobile/Chrome/Safari audio on first touch/click/key by playing a scratch buffer and calling `ctx.resume()` inside the gesture. |

---

## 2. Loading a Locally-Dropped File (no upload)

Verified end-to-end in Chromium with a real (synthesized) MP3:

1. **XHR on `blob:` URLs works** — `XMLHttpRequest` + `responseType: 'arraybuffer'` against `URL.createObjectURL(file)` returned the exact byte count (24,468 B). This is Howler's Web Audio load path, so blob URLs are a viable `src`.
2. **Gotcha:** `new Howl({src: [blobUrl]})` fails with `loaderror: No codec support for selected audio sources` — Howler derives the codec from the URL extension, and `blob:…/uuid` has none. **Fix: pass `format: [ext]`** (ext taken from the dropped file's filename), e.g. `new Howl({src: [blobUrl], format: ['mp3']})`. Verified loading successfully (3 ms for a 24 KB file, exact duration 3 s).
3. **Alternative:** base64 data URI (`data:audio/mpeg;base64,…`) — codec inferred from the MIME type, no `format` needed. Verified working. Howler decodes base64 without XHR (some browsers don't XHR data URIs).
4. **Web Audio mode decodes the whole file** into an `AudioBuffer` cached globally keyed by the src string (`cache[src]`). Memory ≈ **10.6 MB/min** of 44.1 kHz stereo PCM — a 5-minute song ≈ 53 MB. Fine for desktop and modern mobile; no need for HTML5 streaming mode in v1.
5. **Replacing a file:** call `howl.unload()` before creating the next Howl to drop the cached buffer.

**Recommendation for v1:** `format` derived from the dropped file's extension + `Howler.codecs(ext)` check *before* constructing the Howl (clear "this browser can't play .ogg" error in the Error state, spec §9).

---

## 3. Timing Analysis (the core question)

### 3.1 How Howler plays (source-verified)

Web Audio `play()` does:

```js
sound._playStart = Howler.ctx.currentTime;
node.gain.setValueAtTime(vol, Howler.ctx.currentTime);
node.bufferSource.start(0, seek, duration);   // when=0 → "now"
```

- `start(0, …)` begins on the **next 128-sample render quantum** (~2.9 ms at 44.1 kHz) after the call.
- There is **no API to start at a future audio-clock time**. Scheduling `howl.play()` from a `setTimeout` fires **late** (timer granularity ≥4 ms, typically 10–30 ms under main-thread load) — the song would start 10–30 ms *after* the beat boundary the click grid points at. Musicians perceive onset offsets of ~10–25 ms; for a tool whose entire purpose is landing on the beat, this is not acceptable.
- `end` detection is a JS `setTimeout` (fine for state transitions; we use `onended` instead — see §6).

### 3.2 What Metronomad must schedule

Let `t_p` = `ctx.currentTime` at the Play click, `b` = 60/BPM, `N` = count-in beats:

| Event | Audio-clock time |
|-------|-----------------|
| Click 1 (accent, "1") | `t_p + 1·b` (one-beat lead, spec §14 decision 2) |
| Click k (k = 1…N) | `t_p + k·b` — accent (4/4) when `(k−1) mod 4 === 0` |
| **Song start** (click-free, spec §14 decision 3) | `t_p + (N+1)·b`, at the user's offset |

Example (120 BPM, N=4): clicks at +0.5/+1.0/+1.5/+2.0 s, song at +2.5 s — matching spec §5.

### 3.3 The sample-accurate primitive (measured)

`AudioBufferSourceNode.start(when, offset)` on the shared context is **sample-accurate**. Measured in the harness: a source started at `when = ctx.currentTime + 1.0` with `offset = 0.5` into a 3.0 s buffer fired `onended` at **0.41 ms** from the exact expected audio-clock time (`when + duration − offset`). That residual is JS callback latency, not scheduling error.

Latency context (headless machine): `ctx.baseLatency ≈ 5.8 ms`, `ctx.outputLatency = 0` (no real device). On real hardware baseLatency+outputLatency is typically 5–30 ms — irrelevant to alignment because **clicks and the song traverse the same output path**; only absolute alignment to the button press shifts, which the product doesn't care about.

### 3.4 The gap

Howler's playback API cannot express "start this buffer at audio-clock time T, at sample offset S". The precision-critical start **must** be a raw Web Audio `start(when, offset)` call on the same `AudioContext` the clicks use.

---

## 4. Architecture Options

| | A. Pure Howler | **B. Howler context + custom scheduled playback (recommended)** | C. Raw Web Audio only | D. Howler `html5: true` |
|---|---|---|---|---|
| Song start precision | 10–30 ms late (timer) | **Sample-accurate** | Sample-accurate | Tens of ms, event-based |
| Clicks | Howler `play()` per click (also timer-bound) | Raw `start(when)` on `Howler.ctx` | Raw `start(when)` | N/A (no future-time API) |
| Local file load | Howler (blob URL + `format`) | Howler or own `file.arrayBuffer()` → `ctx.decodeAudioData` | Own decode | `<audio src=blobUrl>` |
| Context mgmt (webkit fallback, iOS unlock, autoSuspend) | Howler | Howler (`autoSuspend=false`, see Pitfall 1) | DIY (small, but you own edge cases) | Howler |
| v1 fit (Play/Stop/Restart, no mid-song pause) | Fails core requirement | **Excellent — a small PlaybackEngine owns one song source + click sources** | Excellent | Fails core requirement |
| Private-API dependence | None | **None** (`Howler.ctx` + `Howler.masterGain` are public) | None | None |
| Failure mode | Song drags behind the click grid — defeats the product | — | — | Song start wobbles |

**Recommendation: Option B.** Use Howler for what it's genuinely good at here — battle-tested AudioContext setup (including the `webkitAudioContext` fallback), the `masterGain` volume graph, mobile unlock, and `codecs()` — and do the two precision-critical things (the count-in clicks and the song start) with raw `start(when, offset)` nodes connected into `Howler.masterGain`. No private API is needed: the decoded buffer is simply decoded by us (`file.arrayBuffer()` → `Howler.ctx.decodeAudioData()`), which also sidesteps Howler's internal cache entirely.

Option C is a legitimate simplification (the Howler delta is ~1 file + `new (window.AudioContext||window.webkitAudioContext)()` + an iOS-unlock note); decide at plan time. Both keep the identical PlaybackEngine shape, so the decision is cheap to defer.

**Repo precedent:** MidiSongBuilder already loads **Tone.js** from CDN for synthesis; `Tone.Transport` ships a production-grade lookahead scheduler. If we hand-roll the scheduler (the classic "A Tale of Two Clocks" pattern, ~60 lines: 25 ms timer scheduling 100 ms ahead of `ctx.currentTime`), we add no dependency; if we'd rather reuse, Tone.js is on the table. Plan-phase decision.

---

## 5. Pitfalls Found (all source- or test-verified)

1. **`autoSuspend` will kill custom playback.** Howler's 30 s idle-suspend timer only recognizes *Howler's own* sounds (`_autoSuspend` returns early only when a Howl sound is `!_paused`; the timer is armed at init and re-armed when Howler sounds end). Playback via our own buffer sources is invisible to it → the context suspends 30 s after page load, freezing a song started within that window. **Set `Howler.autoSuspend = false`** (documented public property) when using custom scheduled playback.
2. **`Howler.ctx` is null until lazy setup.** `init()` leaves `ctx = null`; `setupAudioContext()` runs on the first `Howl`/`volume()`/`mute()`/`stop()`. `Howler.usingWebAudio === true` is only an initial flag. Touch `Howler.volume()` (or construct a Howl) before reading `Howler.ctx`.
3. **Blob URLs need `format`.** See §2.2. Data URIs don't (MIME sniffing).
4. **`seek()` while playing = pause→seek→play.** Don't use it on precision paths; in v1 we never seek mid-playback (controls are locked during playback, spec §6).
5. **The decoded buffer isn't retrievable from a Howl.** It lives in a module-private `cache[src]`; after `stop()`, the sound's `bufferSource` is nulled (`_cleanBuffer`). Decode our own buffer if we want ownership.
6. **End events:** Howler's `end` is timer-based; raw sources give a sample-accurate `onended` (measured 0.41 ms in §3.3). Use `onended` for the song's Ended state.
7. **Autoplay policy:** on real devices the context starts `suspended`; `ctx.resume()` must happen inside (or triggered by) a user gesture. Our Play button is the gesture; Howler's `autoUnlock` additionally handles the first-touch unlock on iOS/Android (plays a scratch buffer + resumes in the gesture stack — that's its Android Chrome ≥55 fix).
8. **HTML5 fallback is per-Howl and silent-ish:** an XHR error flips the Howl to HTML5 mode and reloads. With our own decode path this doesn't apply, but if a Howl is ever used, an `onloaderror` listener is mandatory.

---

## 6. Supported Formats (spec decision: "whatever Howler.js can decode")

`Howler.codecs(ext)` is the runtime gate. Measured vs. documented:

| Codec | Chromium (measured) | Firefox (documented) | Safari (documented) |
|-------|--------------------|----------------------|---------------------|
| mp3 | ✅ | ✅ | ✅ |
| wav | ✅ | ✅ | ✅ |
| aac / m4a | ✅ | ✅ | ✅ |
| ogg / oga / opus / webm / weba | ✅ | ✅ | ❌ |
| flac | ✅ | ❌ (verify in E2E) | ✅ (Safari 14+) |
| caf | (n/a) | ❌ | ✅ |

- **mp3 — the primary target — works in all three major browsers.**
- App behavior: on file drop, check `Howler.codecs(ext)`; on failure, show the Error state ("This browser can't play .ogg files") instead of a cryptic decode failure.
- Firefox/Safari cells are from compatibility documentation, not measured here (no Firefox/WebKit builds installed for playwright on this machine; installs skipped to avoid ~170 MB downloads). **Add a cross-browser codec check to the implementation-phase E2E plan.**

---

## 7. Verification Evidence

Harness: `howler-research-test.html` (this folder). Results (headless Chromium, howler 2.2.3, synthesized 3 s 440 Hz MP3):

| Check | Result |
|-------|--------|
| `Howler.codecs` (Chromium) | mp3/wav/ogg/oga/opus/m4a/aac/webm/weba/flac all `true` |
| XHR `arraybuffer` on `blob:` URL | ✅ status 200, exact 24,468 bytes |
| `new Howl({src:[blobUrl]})` (no format) | ❌ `No codec support for selected audio sources` |
| `new Howl({src:[blobUrl], format:['mp3']})` | ✅ loaded in 3 ms, `duration()` = 3, `state()` = `loaded` |
| `new Howl({src:[dataUri]})` | ✅ loaded, duration 3 |
| `seek(1.5)` while paused → `seek()` | 1.5 (stored, applied on play) |
| `play()` after 400 ms | `playing()` = true, `seek()` ≈ 1.88 (position derived from JS timing) |
| `stop()` | `playing()` = false, `seek()` = 0 (reset) |
| `decodeAudioData` on MP3 bytes | 3 s / 44100 Hz / 1 ch |
| `start(when, 0.5)` vs. expected end on audio clock | **Δ = 0.41 ms** (sample-accurate) |
| Sound node / cleanup | `GainNode` → `masterGain`; `bufferSource` nulled after stop |
| `baseLatency` / `outputLatency` (headless) | 5.8 ms / 0 |

Re-run recipe: the harness is a single HTML file. Open it in a browser (or, for playwright-cli which blocks `file:` URLs, load it as a `data:` URL — `python3 -c "import urllib.parse; print('data:text/html,'+urllib.parse.quote(open('howler-research-test.html').read(), safe=''), end='')"`) and call `await runHowlerTest()` in the console / via `playwright-cli eval`.

---

## 8. Implications for the v1 Plan

- **PlaybackEngine module** (raw Web Audio on `Howler.ctx`, into `Howler.masterGain`):
  - Owns: the decoded `AudioBuffer` (decoded from the dropped `File` via `file.arrayBuffer()`), two pre-rendered click buffers (accent + regular — e.g. short 1568 Hz vs 1047 Hz sine bursts with fast decay), the lookahead scheduler (setInterval ~25 ms, schedule ~100 ms ahead), and the active sequence state.
  - `startSequence({bpm, countInBeats, offset})` computes `t_p` and schedules per §3.2; `stop()` stops sources + clears the scheduler; song end via `onended` → Ended state (spec §9).
  - Exposes the beat grid (downbeat time + interval) so the **beat dots** (spec §7) render from `ctx.currentTime` in a `requestAnimationFrame` loop — no second clock, no drift.
  - Song position display (spec §8): `offset + (ctx.currentTime − songStartCtxTime)`, clamped to `[0, duration]`.
- **Howler stays for:** context setup/fallback, `masterGain`, `autoUnlock`, `codecs()`. Set `Howler.autoSuspend = false` at init (Pitfall 1).
- **Open for the plan phase:** hand-rolled scheduler vs. Tone.js `Transport` (repo precedent); exact click-sound synthesis; E2E matrix across Chrome/Firefox/Safari (codec checks + mobile autoplay behavior).
