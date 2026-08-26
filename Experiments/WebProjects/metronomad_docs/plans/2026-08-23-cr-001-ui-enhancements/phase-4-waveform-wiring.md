# Phase 4: Waveform Wiring + Playhead (P0)

**Depends on:** Phase 1 — `extractPeaks` (D-C); Phase 3 — `createWaveformView` (D-F) as built (optional-callback contract: this phase passes **no** callbacks, so the canvas ships display-only and the untouched `keyboard.spec.cjs` exact-Tab-order test stays green — R-2).

**Context to load:**
- `index.md` → Overview, Key Discoveries, **Sequencing constraint (D-M: `_schedulePostLoadTasks` two-task shape from day one)**
- `context.md` → **D-E in full** (hook + guard), D-F (wiring paragraph), **D-H in full** (Phase-4 HTML/CSS state), Risk Register R-1, R-2, R-4, R-7, R-8, R-10, R-13, Known Behaviors KB-14/KB-16, Cross-Cutting Constraints (frozen architecture)
- `behavior-specs.md` → §4 (this phase's canonical rows)
- As-built: `MyESModules/App/createMetronomadMethods.js` (`onFileDropped` `:66-97`, ok-branch `:78-88`), `MyESModules/App/createMetronomadLifecycle.js` (`mounted()` `:32-83`, `beforeUnmount()` `:86-104`), `MyESModules/App/createMetronomadApp.js` (computeds `:51-61`, offset watcher `:78-80`), `MyESModules/App/createMetronomadData.js`, `index.html` (progress block `:124-138`), `Style.css` (progress block `:293-325`, media query `:285`, `#app` `:7`), `test/e2e/smoke.spec.cjs` (CONTROLS `:22-33`), `test/e2e/playback.spec.cjs` (`startRecordedSequence` `:43-67`)
- Skill: `building-web-apps` → `references/memory-management.md` (teardown ordering), `references/testing-e2e.md` (in-page timing logger convention)

**TDD workflow (RED → GREEN):** modules exist (no R-11 broken-page shape here) — RED is per-test:
1. `UiHandlersTest.html`: WF-I1.1…WF-I1.5 first (the new methods/guard don't exist → TypeError RED).
2. GREEN the hook + guard + lifecycle.
3. `waveform.spec.cjs`: E2E-3.1…E2E-3.4 RED (no canvas in the DOM) → GREEN with the template/CSS/data/computed changes.
4. Update `smoke.spec.cjs` CONTROLS in the same commit as the template change (R-1).

## Overview

Make the waveform visible and live: replace the 8 px progress block with the waveform container (placeholder track → canvas once peaks land), add the playhead/marker/dim overlays, move the `progressbar` role to the readout (W-10), and wire the single post-load hook that runs **both** async analysis tasks under the D4-style generation guard (the tempo task is a guarded no-op until Phase 6 — the D-M constraint). `#offsetScrubber` still coexists this phase (additive).

## Changes Required

### 1. `MyESModules/App/createMetronomadMethods.js`
**Changes:** D-E verbatim. In `onFileDropped`'s `result.ok` branch (`:78-88`), after `this._buffer = result.buffer;`:

```js
this._loadGeneration = (this._loadGeneration || 0) + 1;
this._bpmTouchedThisFile = false;      // Phase 6's flag; reset lives here (CR §2.5 row 1)
this.waveformReady = false;             // placeholder reappears (O-2/W-17)
// …existing offset clamp / READY flip / error clear / announcement…
this._schedulePostLoadTasks(result.buffer, this._loadGeneration);
```

New methods (D-E): `_schedulePostLoadTasks(buffer, generation)` — **two-task shape from day one**; `async _runPeakExtraction(buffer, generation)` — `setTimeout(0)` yield → `_analysisValid` guard → `extractPeaks(buffer)` → re-check guard → `this._peaks = { ...peaks }` + `waveformReady = true`; `async _runTempoSuggestion(buffer, generation)` — **body: `/* Phase 6 (D-I) */` (guarded no-op)**; `_analysisValid(buffer, generation)` — `!this._disposed && generation === this._loadGeneration && buffer === this._buffer` (W-14 + W-15 in one guard).

### 2. `MyESModules/App/createMetronomadLifecycle.js`
**Changes:**
- `mounted()` (`:78-84` area, after the beat dots): `this._waveformView = createWaveformView(this, {}, {});` + `this._waveformView.init(document.getElementById('waveformCanvas'));` (import from the barrel).
- `beforeUnmount()` (`:86-104`), inserted **between `stopAll()` and `engine.dispose()`**:
```js
this._disposed = true;      // D-E guard half (unmount) — set FIRST so in-flight tasks die
this._peaks = null;
this._buffer = null;
if (this._waveformView) { this._waveformView.dispose(); this._waveformView = null; }
```
(memory-management.md: listener removal before renderer disposal; the visualizer touches only its own resources — RD-6 discipline.)

### 3. `MyESModules/App/createMetronomadData.js`
**Changes:** add `offsetDraft: null`, `waveformReady: false`, `tempoSuggestion: null` (the last is a placeholder — its hint `<p>` lands in Phase 6; D-H).

### 4. `MyESModules/App/createMetronomadApp.js`
**Changes:** add the four D-H computeds alongside the existing ones — `displayPosition`, `formattedDisplayPosition`, `playheadPercent`, `markerPercent`. **`progressPercent` (`:51-55`) and `offsetMarkerPercent` (`:57-61`) are untouched** (R-4: the playhead re-purposes the *math* via `playheadPercent`, never the computed's contract; existing computed tests stay green).

### 5. `index.html` — replace the `.progress` block (`:124-138`)
**Changes:** the D-H **Phase-4** template verbatim (placeholder track + `role="img" tabindex="-1"` canvas + dim/offset-marker/playhead overlays + readout carrying the `progressbar` role). Update the stale N-10 comment (`:124-126`) to cite the W-10 role move. **Do not touch `#offsetScrubber` (`:75-79`) or the BPM group yet.**

### 6. `Style.css` (progress block region `:293-325`)
**Changes:** D-H Phase-4 CSS verbatim — keep `.progress`/`.progress-track`/`.progress-offset-marker` (placeholder); **delete `.progress-fill`** (its only consumer, `index.html:131`, is removed in step 5; the `progressPercent` computed survives per R-4); add `.waveform` (64 px, `touch-action: pan-y` + the W-2 comment), `@media (max-width: 375px) { .waveform { height: 48px; } }` (the file's first width breakpoint, W-4), `#waveformCanvas` (absolute inset 0, crosshair), `.waveform--locked #waveformCanvas { pointer-events: none; }`, `.waveform-offset-marker` / `.waveform-playhead` / `.waveform-dim` (all `pointer-events: none`). KB-6 hooks get no styling.

### 7. `test/e2e/smoke.spec.cjs` (R-1)
**Changes:** split CONTROLS: `#waveformCanvas` moves to a new **presence-only** list (a canvas has no `disabled` attribute — the presence check passes in no-file via `v-show`; do NOT assert `toBeDisabled()` on it). `#offsetScrubber` stays in CONTROLS (still present this phase).

### 8. `test/e2e/waveform.spec.cjs` (new — Phase 4 rows)
**Changes:** E2E-3.1…E2E-3.4 per the inlined table; reuse `loadFixture`-style helpers from `helpers.cjs` and the in-page 5 ms transition logger convention (`playback.spec.cjs:43-67`). `data-position-tenths` assertions compare **stringified** tenths (R-7).

## Scenarios owned by this phase (canonical copy in `behavior-specs.md` §4)

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| WF-I1.1 | P0 | Unit (mock-VM): loader spy resolves `{ ok: true, buffer: A, duration: 3, fileName: 'a' }` | `onFileDropped(file)` → READY → flush the 0 ms yields | `_loadGeneration` bumped; `_bpmTouchedThisFile === false`; after the yield: `_peaks` set (computed from A), `waveformReady === true`; the READY flip itself precedes the peaks work (W-6) |
| WF-I1.2 | P0 | Unit: peaks task for buffer A pending at its yield; a second load resolves with buffer B (generation bumped) | flush A's continuation, then B's | A's continuation **writes nothing** (guard: `generation !== _loadGeneration \|\| buffer !== _buffer`): `waveformReady` still false, `_peaks` unset; B's continuation then sets `_peaks` (from B) + `waveformReady === true` (W-14) |
| WF-I1.3 | P1 | Unit: peaks task pending at its yield; `beforeUnmount` ran (`_disposed === true`) | flush the continuation | **no write** — nothing touches the unmounted VM (W-15, N-14 shape) |
| WF-I1.4 | P1 | Unit: file A loaded, `waveformReady === true`; a second file is dropped (decoding) | observe during decode; then the second load resolves ok | during decode: `waveformReady` stays true (old waveform visible — KB-16, intentional, do not blank-flash); in the ok-branch: `waveformReady` resets to **false** (placeholder reappears) before the new peaks land (O-2/W-17) |
| WF-I1.5 | P2 | Unit: a load **fails** (codec/decode/tooLong) while a peaks task for the still-live buffer A is pending at its yield | flush A's continuation | the failure path did **not** bump the generation (F-05: old buffer stays live) → A's task completes and applies normally; `errorMessage` set, `appState` unchanged |

**E2E (this phase's rows — `test/e2e/waveform.spec.cjs`; in-page 5 ms transition logger per `playback.spec.cjs:43-67` convention):**

| ID | Test | Steps | Expected |
|----|------|-------|----------|
| E2E-3.1 | Waveform paints; Ready is never delayed | drop `sine3s.mp3`; record state transitions in-page | `#waveformCanvas[data-loaded="true"]` appears; the in-page timeline shows the `ready` transition **strictly before** the first frame with `data-loaded="true"` (peaks work runs after the READY paint, W-6); canvas visible (`offsetWidth > 0`) |
| E2E-3.2 | Playhead tracks during playback | E2E-3.1 state; set count-in 1, press Play; in-page: sample `#waveformPlayhead[data-position-tenths]` at two points ≥1 s apart during playing | both samples advance monotonically from the offset's tenths and each is within ±1 tenth of the position parsed from `.progress-readout` at the same timestamp (the readout is the tenth-second ground truth; 10 Hz cadence — no per-frame updates) |
| E2E-3.3 | Playhead parks at the offset in Ready | E2E-3.1 state; commit offset `0:01.2` via `#offsetInput` + Enter | `#waveformPlayhead[data-position-tenths] === "12"`; readout text `0:01.2 / 0:03.0` (existing Ready watcher — no new state) |
| E2E-3.4 | Responsive height clamp (W-4) | emulate viewport 360×740, load; then 1280×800, load | `.waveform` computed height **48 px** at 360 and **64 px** at 1280; `.progress-readout` visible (non-zero height) in both |

## Success Criteria

**Automated:**
- [ ] WF-I1.1…WF-I1.5 pass (mock-VM, UiHandlersTest).
- [ ] E2E-3.1…E2E-3.4 pass (`waveform.spec.cjs`).
- [ ] `node scripts/run-tests.cjs` fully green; `npx playwright test` green with the new 4 rows (27 total) — **`keyboard.spec.cjs` and `playback.spec.cjs` untouched and green** (the canvas is `tabindex="-1"` display-only; R-2).
- [ ] Grep pass: `rg "progress-fill" index.html Style.css` → zero (consumer + rule deleted); `rg "progressPercent" MyESModules/ index.html` → zero template consumers (its only one, `.progress-fill`, is gone — the computed itself is retained per R-4 for its existing computed-level tests, and `playheadPercent` re-derives the math on `displayPosition`); `rg "requestAnimationFrame" MyESModules/App/createMetronomadMethods.js` → zero (no second visual clock — D9).

**Manual (user, server on :8000):**
- [ ] Drop a song: the thin placeholder track shows during decode/peak work, then the waveform paints (silent spans read as gaps — CR §1.8.2); the offset marker sits at the offset; the pre-offset dim renders.
- [ ] During playback the playhead moves in 0.1 s steps with the readout; in Ready it parks at the offset.
- [ ] Resize/rotate the window: at most one visible re-render, final size wins (W-5); at a narrow phone width the waveform is 48 px tall and everything stays in reach.
- [ ] `#offsetScrubber` still works (coexistence is additive this phase).

**Phase close:** run the handoff audit against Phase 5's "Context to load" and inlined WF-I2.\*/E2E-3.5…3.10 rows (as-built canvas attrs vs the Phase-5 slider diff; does `createWaveformView` as built accept the three Phase-5 callbacks and expose `setDraft`?) before marking done in `index.md`.
