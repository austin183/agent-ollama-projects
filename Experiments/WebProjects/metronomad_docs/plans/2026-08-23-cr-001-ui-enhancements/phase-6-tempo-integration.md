# Phase 6: Tempo Suggestion Integration (P1)

**Depends on:** Phase 2 — `detectTempo` / `TEMPO` (D-D) as built (returns `{ bpm: integer, confidence } | null`, `null` = "unsure"); Phase 4 — the post-load hook with its **two-task shape** (`_schedulePostLoadTasks` calling a guarded no-op `_runTempoSuggestion`), the `_analysisValid` guard, the `_bpmTouchedThisFile` reset in the ok-branch, and the `tempoSuggestion` data field.

**Context to load:**
- `index.md` → Overview, What We're NOT Doing (no re-detect button, no metadata)
- `context.md` → **D-I in full** (prefill gate, flag lifecycle, the memo-correction on re-drop), D-K (fixture contract), D-E (hook shape — do not refactor it), Known Behaviors KB-15, Risk Register R-6, R-9, R-10, R-12, Cross-Cutting Constraints (strings: the two owned strings)
- `behavior-specs.md` → §6 (this phase's canonical rows)
- CR: §2.5 (UX contract + flag table), §2.6 (acceptance criteria)
- As-built: `MyESModules/App/createMetronomadMethods.js` (`commitBpmEntry` `:137`, `onBpmStep` `:146`, `_restoreLastValid` `:117-133` — R-12: the flag goes in the BPM *callers*, not the shared helper; the Phase-4 `_runTempoSuggestion` no-op), `index.html` (BPM group `:59-71` — hint slot below the `bpmClamped` hint at `:70`; `#bpmInput` `:64`), `MyESModules/Audio/clickBuffers.js` (`:14-19`, `:33-55` — the fixture envelope), `test/e2e/helpers.cjs` (fixture drop pattern `:13-26`), `MyComponents/UiHandlersTest.html` (mock-VM pattern `:34-60`)
- Skill: `building-web-apps` → `references/testing-e2e.md`

**TDD workflow (RED → GREEN):** RED per-test:
1. Author the fixture first (it is ground truth for E2E): `scripts/make-clicks20-wav.cjs` → run once → commit `test/fixtures/clicks20.wav` (D-K: 1 764 044 bytes; sanity-check with the Phase-2 TD-1.15-style in-page assertion or a one-off Node check that the onsets sit at 0.5 s spacing).
2. `UiHandlersTest.html`: TD-U1.1…TD-U1.10 RED (`applyTempoSuggestion`/`onBpmTextInput` missing → TypeError).
3. GREEN the gate + flag sites + the `_runTempoSuggestion` body (replace the Phase-4 no-op — **the hook itself is untouched**, D-M).
4. `tempo.spec.cjs`: E2E-4.1…E2E-4.4 RED (no hint element yet) → GREEN with the hint `<p>`.

## Overview

Make detection user-visible: fill in the tempo half of the post-load hook, gate the prefill behind the W-16 contract (confidence already inside `detectTempo`, touched flag, unfocused, draft==model), surface the short hint + V-07 announcement, and pin the whole lifecycle with unit rows plus the `clicks20.wav` E2E round-trip. A suggestion is never a touch; silence (null) is never a hint.

## Changes Required

### 1. `test/fixtures/clicks20.wav` + `scripts/make-clicks20-wav.cjs` (new — D-K)
**Changes:** dependency-free Node generator: RIFF/WAVE header (20 s · 44 100 Hz · mono · 16-bit PCM) + 40 clicks at t = 0.0, 0.5, …, 19.5 s, each a 60 ms burst (5 ms linear attack, exp decay to 1e-5), 1047 Hz regular with **1568 Hz accent every 4th** (the TD-1.15 shape). Commit script + WAV; the script is the fixture's living provenance.

### 2. `MyESModules/App/createMetronomadMethods.js`
**Changes:** D-I verbatim:
- `_runTempoSuggestion(buffer, generation)` — replace the Phase-4 no-op: `setTimeout(0)` yield → `_analysisValid` guard → `channelArrays(buffer)` → `detectTempo(channels, sampleRate)` → re-check guard (W-14) → `this.applyTempoSuggestion(result)`.
- `applyTempoSuggestion(result)` — the four-clause gate read **at write time** (R-10): (1) `result && result.bpm`; (2) `!this._bpmTouchedThisFile`; (3) `document.activeElement !== document.getElementById('bpmInput')`; (4) `this.bpmText === String(this.bpm)`. Pass → `bpm = clampBpm(result.bpm)`, `bpmText = String(bpm)`, `tempoSuggestion = bpm`, `announcement = 'Detected tempo ' + bpm + ' BPM'` (V-07 inventory +1). The write does **not** set the flag. null → nothing.
- Flag set-true sites (R-12 — BPM callers only, never `_restoreLastValid`): top of `commitBpmEntry()` (`:137`), top of `onBpmStep()` (`:146`), and new `onBpmTextInput()` — a no-op-except-flag setter (R-6: order-independent with v-model; programmatic writes don't fire `input`, so the prefill can't self-poison).
- Import `detectTempo` + `channelArrays` from the barrel.

### 3. `index.html`
**Changes:** below the `bpmClamped` hint (`:70`): `<p v-if="tempoSuggestion" class="clamp-hint" role="status">Detected ~{{ tempoSuggestion }} BPM</p>` (string pinned, W-3); `#bpmInput` (`:64`) gains `@input="onBpmTextInput"` alongside `v-model` (legal; R-6).

### 4. `MyComponents/UiHandlersTest.html`
**Changes:** TD-U1.1…TD-U1.10 mock-VM rows (fake `document` with a controllable `activeElement` — the existing DOM-stub pattern). The V-07 announcement-inventory row gains "Detected tempo N BPM".

### 5. `test/e2e/tempo.spec.cjs` (new)
**Changes:** E2E-4.1…E2E-4.4 per the inlined table; drop via `setInputFiles('#fileInput', …)` (helpers.cjs pattern). **Never assert the fixture's duration string** (R-9). Hint assertion: the `role="status"` paragraph with exact text `Detected ~120 BPM`; assert it and `bpmClamped`'s hint are never simultaneously present.

## Scenarios owned by this phase (canonical copy in `behavior-specs.md` §6)

| ID | Pri | Given | When | Then |
|----|-----|-------|------|------|
| TD-U1.1 | P0 | Unit (mock-VM, fake `document`): all gate clauses hold — `bpm 120`, `bpmText "120"`, flag false, `activeElement ≠ #bpmInput`; stale `bpmClamped === true` (a prior clamped commit a re-drop outlived) | `applyTempoSuggestion({ bpm: 120, confidence: 0.85 })` | `bpm === 120`, `bpmText "120"`, `tempoSuggestion === 120`, `announcement === "Detected tempo 120 BPM"` (V-07 inventory +1); `bpmClamped` **cleared** (D-H hint mutual exclusion — added as-built 2026-08-25); flag **stays false** (a suggestion is not a touch) |
| TD-U1.2 | P0 | Gate would pass, but `onBpmStep(1)` ran first (flag true) | `applyTempoSuggestion({ bpm: 120, confidence: 0.85 })` | **no write**: bpm unchanged, no `tempoSuggestion`, no announcement, no hint |
| TD-U1.3 | P0 | Flag set by `commitBpmEntry` — both the clean path (type "140", Enter) and the garbage-restore path (`bpmText "abc"`, Enter → `_restoreLastValid`) | `applyTempoSuggestion(…)` after each | no prefill in either case (CR §2.5 row 3: typing garbage *is* a user touch); the restore path still restores the last valid value |
| TD-U1.4 | P0 | Mid-draft: `bpm 120`, `bpmText "90"` (divergent, gate clause 4), flag state irrelevant | `applyTempoSuggestion({ bpm: 120, confidence: 0.9 })` | **no prefill** — the field keeps `"90"` (W-16: never clobber an in-progress entry; the suggestion is silently dropped for this file) |
| TD-U1.5 | P0 | `#bpmInput` focused (`activeElement === #bpmInput`), all other clauses pass | `applyTempoSuggestion(…)` | no prefill (clause 3) — the user is typing; a fresh suggestion is available any time by re-dropping |
| TD-U1.6 | P0 | Any gate state | `applyTempoSuggestion(null)` | no prefill, no hint, no announcement (silence is the correct UX for "unknown", W-13) |
| TD-U1.7 | P1 | A successful prefill just landed (flag false by construction) | a second suggestion for the same live file (re-drop path: flag reset on load) | it prefills again — the prefill write never self-poisons the flag |
| TD-U1.8 | P1 | Unit: tempo task for buffer A pending at its yield; second load resolves (buffer B) | flush A's continuation, then B's | A's result writes nothing (same `_analysisValid` guard as peaks, W-14); B's result applies if its gate passes |
| TD-U1.9 | P1 | Unit: tempo task pending at its yield; `beforeUnmount` ran | flush the continuation | no write to the unmounted VM (W-15) |
| TD-U1.10 | P1 | Unit: `#bpmInput` with v-model + the new `@input` flag handler | simulated `input` events set `bpmText` ("1", "12", …) | each event sets the flag **and** leaves the draft write to v-model (`bpmText` holds the typed text, model `bpm` untouched until commit); order-independent (R-6); Enter still commits via `commitBpmEntry` (clamps as U-11 rev) |

**E2E (this phase's rows — `test/e2e/tempo.spec.cjs`; fixture per context D-K; never assert the fixture's duration string — R-9):**

| ID | Test | Steps | Expected |
|----|------|-------|----------|
| E2E-4.1 | Prefill happy path | fresh load; drop `clicks20.wav` (120 BPM ground truth) | `#bpmInput` value `"120"`; hint `Detected ~120 BPM` visible (`role="status"`); live region announces `Detected tempo 120 BPM`; the hint and the `bpmClamped` hint are never both shown |
| E2E-4.2 | Flag reset on load — re-drop re-suggests (CR §2.5 row 1) | E2E-4.1 state; edit `#bpmInput` to `"140"` + Enter (flag set); drop `clicks20.wav` **again** | the successful load resets the flag → prefill happens **again**: field returns to `"120"`, hint + announcement fire (the memo's "no prefill on re-drop" was wrong — the CR is authoritative) |
| E2E-4.3 | Negative fixture stays silent | drop `sine3s.mp3` (3 s → too few onsets → `null`) | `#bpmInput` value **unchanged** from before the drop; no "Detected" hint; no tempo announcement (silence is correct) |
| E2E-4.4 | Focused mid-draft + drop: the blur law commits first; the suggestion then lands visibly (W-16 re-pin — see note) | focus `#bpmInput`; type `"9"` (draft `"9"` ≠ model); drop `clicks20.wav` | decoding disables the field (`:disabled="!isReady"`) → the app's own blur law (RD-1) commits `"9"` (clamped 30); the re-drop's flag reset (CR §2.5 row 1) lets the prefill land **visibly**: field `"120"` + hint + announcement, stale clamp hint cleared. **Re-pinned 2026-08-25 (platform invariants — the original "draft survives" expectation is unreachable via any load trigger):** a drop event (trusted or synthetic) moves focus (native drop focus semantics), and even a focus-preserving load blurs the field via the decoding disable — a live mid-draft never reaches detection time. The no-clobber guarantee for a genuinely live mid-draft lives at the P0 unit level (TD-U1.4/TD-U1.5, gate read at write time, R-10) |

## Success Criteria

**Automated:**
- [ ] `test/fixtures/clicks20.wav` committed (1 764 044 bytes) + `scripts/make-clicks20-wav.cjs` regenerates a byte-identical file.
- [ ] TD-U1.1…TD-U1.10 pass; the V-07 inventory row passes with the new announcement.
- [ ] E2E-4.1…E2E-4.4 pass.
- [ ] `node scripts/run-tests.cjs` fully green; `npx playwright test` fully green (33 + 4 new = 37).
- [ ] Grep pass (no hook refactor, D-M): `rg "_schedulePostLoadTasks" MyESModules/App/createMetronomadMethods.js` → one definition, still calling both `_runPeakExtraction` and `_runTempoSuggestion`; `rg "44100|48000|1047|1568" MyESModules/App/` → zero (envelope math lives only in `clickBuffers.js` / the generator script).

**Manual (user, server on :8000):**
- [ ] Drop a real song with a steady beat: the BPM field prefills to a plausible value with the short hint; the value is a sane guess (within a half/double of the song's feel) or absent — never a confidently-wrong number.
- [ ] Type a BPM before the suggestion lands (or focus the field) → the suggestion is silently dropped; re-drop the file → it suggests again.
- [ ] Drop the 3 s sine (or any intro-heavy/odd file) → no hint, no announcement, field untouched (silence is the correct "unknown").

**Phase close:** run the handoff audit against Phase 7's "Context to load" and its checklist (do the as-built strings match the two owned strings verbatim? do the KB-14…KB-17 statements match what the code actually does — spot-check the reduced-motion playhead and the raw-float `aria-valuemax`?) before marking done in `index.md`.
