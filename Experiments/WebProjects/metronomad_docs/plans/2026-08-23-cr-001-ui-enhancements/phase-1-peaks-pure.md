# Phase 1: Peaks + Channel Data — Pure Modules (P0)

**Depends on:** — (first phase). Provides the D-B/D-C contracts (`channelArrays`, `monoMixdown`, `extractPeaks`, `poolPeaks`, `PEAK_BUCKETS_DEFAULT`, `PEAK_STRIDE_MAX_SAMPLES`) that Phases 2, 3, and 4 consume by ID.

**Context to load:**
- `index.md` → Overview, What We're NOT Doing, Key Discoveries (the sine3s bucket-count correction)
- `context.md` → **D-A, D-B, D-C in full**, Risk Register R-11, Cross-Cutting Constraints (DI convention)
- `behavior-specs.md` → §1 (this phase's canonical rows)
- As-built: `MyESModules/index.js` (barrel + silent-re-export warning header `:1-9`), `MyESModules/Utils/paramClamps.js` (the `Number.isFinite`-guard style to mirror)
- Learning: `_agent_docs/learnings/2026-08-22-esmodule-link-failure-is-silent.md` (R-11)
- Skill: `building-web-apps` → `references/testing-unit.md` (plain-Mocha suite shape used by `MyComponents/*Test.html`)

**TDD workflow (RED → GREEN):** RED first — create `MyComponents/WaveformPeaksTest.html` importing `{ channelArrays, mixDown, monoMixdown, extractPeaks, poolPeaks }` **through the barrel** (`../MyESModules/index.js`). **RED shape (R-11):** the missing barrel exports fail ES-module *linking* — the page dies before `mocha.run()`, so `node scripts/run-tests.cjs` reports a page-load error for this file, not per-test failures. That page error *is* the expected RED signal; do not chase it as a phantom. GREEN: implement the modules, add the barrel block, all WF-P1.\* pass.

## Overview

Create the new `MyESModules/Analysis/` directory (D-A) with the shared channel-walk/mixdown helper and the peak-extraction pure functions. Everything is a pure function of a buffer-shaped object with `Number.isFinite` guards; `sampleRate` travels in the result but is never a constant (W-8). No app wiring, no DOM, no AudioContext.

## Changes Required

### 1. `MyESModules/Analysis/channelData.js` (new)
**Changes:** D-B interface verbatim.

```js
// Number.isFinite guards on every input (paramClamps.js style).
export function channelArrays(buffer)   // → { channels: Float32Array[], sampleRate, duration }
export function mixDown(channels)       // → Float32Array — THE one mean implementation (D-B)
export function monoMixdown(buffer)     // → mixDown(channelArrays(buffer).channels) facade
```

- `channelArrays`: guard `Number.isFinite(buffer?.numberOfChannels) && > 0` and `Number.isFinite(buffer?.length) && > 0` → degenerate → `{ channels: [], sampleRate: 0, duration: 0 }` (WF-P1.6). Walk `getChannelData(c)` once.
- `mixDown`: element-wise mean; single channel returned as-is (no copy); `monoMixdown` is the thin buffer facade (WF-P1.9). Phase 2's `detectTempo` imports `mixDown` directly — there must be exactly one mean implementation (AGENTS.md "DO NOT Duplicate").

### 2. `MyESModules/Analysis/waveformPeaks.js` (new)
**Changes:** D-C interface verbatim — `PEAK_BUCKETS_DEFAULT = 4096`, `PEAK_STRIDE_MAX_SAMPLES = 20_000_000`, `extractPeaks(buffer, bucketCount = PEAK_BUCKETS_DEFAULT)`, `poolPeaks(peaks, targetBuckets)`.

- Effective bucketCount = `min(bucketCount, sampleCount)` — 50 samples → 50 buckets; 132 300 (sine3s @ 44.1 kHz) → 4096 buckets of ≈32 samples (the corrected arithmetic; WF-P1.4/WF-P1.5).
- Stride: `sampleCount > PEAK_STRIDE_MAX_SAMPLES ? 4 : 1`, applied deterministically before bucketing (WF-P1.7).
- Per-bucket min/max; stereo merged min-of-mins / max-of-maxs (WF-P1.3). NaN/Inf samples → 0 (documented in JSDoc).
- **No `sourceBuffer` in the return** — the caller keeps buffer identity for the D-E guard.
- `poolPeaks`: min/max pooling, O(4096); `targetBuckets ≥ source.bucketCount` → copy (WF-P1.8).

### 3. `MyESModules/index.js` (barrel)
**Changes:** add the Analysis block after the existing Phase 6 block, names: `channelArrays`, `mixDown`, `monoMixdown`, `extractPeaks`, `poolPeaks`, `PEAK_BUCKETS_DEFAULT`, `PEAK_STRIDE_MAX_SAMPLES`. Verify each re-exported name exists in its source module (header warning) — the test page's barrel import is the verification.

### 4. `MyComponents/WaveformPeaksTest.html` (new)
**Changes:** the §1 table, one `it` per row (plus the sub-cases inside WF-P1.4/WF-P1.6/WF-P1.8). Fake buffers are plain objects: `{ numberOfChannels, length, sampleRate, getChannelData: (c) => arrays[c] }`.

## Scenarios owned by this phase (canonical copy in `behavior-specs.md` §1)

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

## Success Criteria

**Automated:**
- [ ] RED observed first: `node scripts/run-tests.cjs` shows the WaveformPeaks page-load (link) error before the modules exist (R-11 shape), then GREEN.
- [ ] WF-P1.1…WF-P1.9 all pass in `MyComponents/WaveformPeaksTest.html`.
- [ ] `node scripts/run-tests.cjs` fully green (158 + new rows); `npx playwright test` unchanged at 23 (no app surface touched).
- [ ] Grep pass: `rg "import " MyESModules/Analysis/` — no import of app/Playback/`index.js` (pure modules import at most nothing or `channelData.js`); `rg "sampleRate" MyESModules/Analysis/waveformPeaks.js` — read from the buffer, never a literal 44100/48000.

**Manual:**
- [ ] n/a in this phase (pure functions — the waveform becomes visible in Phase 4).

**Phase close:** run the handoff audit against Phase 2's "Context to load" and inlined TD-1.\* table (does `channelData.js` as built satisfy D-B for `monoMixdown`'s consumer?) and against Phase 3's (does `poolPeaks` as built match WF-V1.1's pooling assumption?) before marking done in `index.md`.
