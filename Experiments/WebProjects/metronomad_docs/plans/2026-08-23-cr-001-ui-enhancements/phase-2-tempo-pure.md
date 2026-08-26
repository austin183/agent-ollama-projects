# Phase 2: Tempo Detection — Pure Module (P1)

**Depends on:** Phase 1 — `channelArrays`/`monoMixdown` from `MyESModules/Analysis/channelData.js` (D-B) as built. The test suite synthesizes its own `Float32Array` channels, so the dependency is at the *implementation* level (mixdown reuse) and at the barrel level.

**Context to load:**
- `index.md` → Overview, What We're NOT Doing (no FFT, no metadata — v1 scope)
- `context.md` → **D-D in full** (interface, pipeline, tuning contract), D-A/D-B, Risk Register R-11, Cross-Cutting Constraints
- `behavior-specs.md` → §2 (this phase's canonical rows)
- CR: `_agent_docs/specifications/change-requests/2026-08-23-001-ui-enhancements.md` → §2.3 (pipeline), §2.4 (window + short-file rule), §4 (limitations to document)
- As-built: `MyESModules/Audio/clickBuffers.js` (`CLICK` constants `:14-19`, envelope math `:33-55` — reuse the recipe constants, don't re-declare), `MyESModules/Utils/paramClamps.js` (`BPM_MIN`/`BPM_MAX` `:8-10` — **import, never re-declare**), Phase 1's `channelData.js` as built
- Skill: `building-web-apps` → `references/testing-unit.md`

**TDD workflow (RED → GREEN):** RED first — create `MyComponents/TempoDetectionTest.html` importing `{ detectTempo, TEMPO }` through the barrel. **RED shape (R-11):** broken page (module link failure), not per-test failures — the runner's page error is the expected RED signal. GREEN: implement `tempoDetection.js`, add barrel exports. The three tuning constants (0.75 / 0.6 / 8) may be adjusted during RED/GREEN **only** while every pinned TD-1.\* outcome holds (D-D tuning contract) — a table outcome that can't be met by tuning is a plan bug, not a test bug: surface it in the session summary.

## Overview

Implement the pure-DSP tempo estimator: mono mixdown → leading-silence trim → half-wave-rectified frame-energy onset envelope → autocorrelation over the app's existing 30–250 BPM range with a 70–180 musical prior, half/double rescoring, and an explicit confidence metric whose conservative threshold returns `null` when unsure (W-13: a wrong-but-confident suggestion is worse than no suggestion). All math per-`sampleRate` (W-8); zero AudioContext; zero new dependencies.

## Changes Required

### 1. `MyESModules/Analysis/tempoDetection.js` (new)
**Changes:** D-D interface verbatim — `import { BPM_MIN, BPM_MAX } from '../Utils/paramClamps.js'` and `import { mixDown } from './channelData.js'` (D-B: the shared mean; relative import, same directory — no barrel self-import); `export const TEMPO = { HOP: 512, FRAME: 2048, WINDOW_SEC: 60, PRIOR_MIN: 70, PRIOR_MAX: 180, PRIOR_OUT_BAND_SCALE: 0.75, NOISE_FLOOR_SCALE: 0.01, MIN_ONSET_FRAMES: 8, CONFIDENCE_THRESHOLD: 0.6 }`; `export function detectTempo(channels, sampleRate, maxWindowSec = TEMPO.WINDOW_SEC)`.

Pipeline (each step its own internal function; every input `Number.isFinite`-guarded → `null`, never throws — TD-1.13):
1. **Mixdown** — `mixDown(channels)` from `channelData.js` (D-B: the single shared mean implementation — `monoMixdown` is its buffer-facing facade; do NOT write a second local mean loop here).
2. **Trim** — skip leading frames until frame energy first exceeds `windowPeakEnergy × NOISE_FLOOR_SCALE` (TD-1.12).
3. **Window** — analyze `min(maxWindowSec · sampleRate, length)` samples (TD-1.14; short files clamp to duration — CR §2.4).
4. **Onset envelope** — frame energy, hop `HOP`, window `FRAME`; `o[i] = max(0, e[i] − e[i−1])`.
5. **Autocorrelation** — candidate periods `p ∈ [60·sampleRate/(BPM_MAX·HOP), 60·sampleRate/(BPM_MIN·HOP)]` frames (≈21…172 @ 44.1 kHz; ≈23…187 @ 48 kHz — per-`sampleRate`, W-8; the memo's `HOP·60/BPM` form was dimensionally wrong — corrected 2026-08-24); energy-normalized `C(p)`.
6. **Score + half/double** — `score(p) = C(p) × (bpm(p) in [PRIOR_MIN, PRIOR_MAX] ? 1 : PRIOR_OUT_BAND_SCALE)`; compare against `p/2` and `2p` where in range.
7. **Confidence** — `bestScore / bestNonAliasedRunnerScore`, runners excluding lags within 10 % of `best/2` and `best·2` (aliases of the same perceived pulse); `null` when `confidence < CONFIDENCE_THRESHOLD` or onsets-above-floor `MIN_ONSET_FRAMES` or the envelope is flat.
8. Return `{ bpm: Math.round(60 · sampleRate / bestP), confidence }`.

The TD-1.7 half-time case (onsets only every 2 beats → true period 60 BPM, out-of-band, weak in-band alias) must resolve to `120` **or `null`, never 60** — if the raw metric confidently reports 60, tighten the metric (e.g. out-of-band winners require the in-band alias to be non-weak, else `null`) *within the tuning contract*; do not special-case the test input.

### 2. `MyESModules/index.js` (barrel)
**Changes:** add `detectTempo`, `TEMPO` to the Analysis block.

### 3. `MyComponents/TempoDetectionTest.html` (new)
**Changes:** the §2 table, one `it` per row. Train synthesis helper (standalone in the page): place 60 ms bursts (1047 Hz regular / 1568 Hz accent per `CLICK`, 5 ms linear attack, exp decay to 1e-5) at the row's onsets into a zeroed `Float32Array` of the row's length at the row's rate. **Zero real AudioContext.**

## Scenarios owned by this phase (canonical copy in `behavior-specs.md` §2)

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

## Success Criteria

**Automated:**
- [ ] RED observed first: broken-page (link) RED for `TempoDetectionTest.html` before the module exists (R-11), then GREEN.
- [ ] TD-1.1…TD-1.15 all pass — including both rates (TD-1.2) and the half-time never-60 pin (TD-1.7).
- [ ] `node scripts/run-tests.cjs` fully green; `npx playwright test` unchanged at 23.
- [ ] Grep pass: `rg "44100|48000" MyESModules/Analysis/tempoDetection.js` → zero literal sample rates (all math per-parameter, W-8); `rg "30|250" MyESModules/Analysis/tempoDetection.js` → the range comes from `BPM_MIN`/`BPM_MAX` imports, no re-declared literals in a range context.

**Manual:**
- [ ] n/a in this phase (detection becomes user-visible in Phase 6).

**Phase close:** run the handoff audit against Phase 6's "Context to load" and inlined TD-U1.\* rows (does the as-built `detectTempo` return shape — `{ bpm, confidence } | null` with `bpm` an integer — match `applyTempoSuggestion`'s assumptions, and does TD-1.15's accent-mix result hold for the fixture the E2E will drop?) before marking done in `index.md`.
