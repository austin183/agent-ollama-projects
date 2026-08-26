# CR 2026-08-23-001 — UI Enhancements (Waveform Progress + BPM Detection) — Implementation Plan

**Date:** 2026-08-23
**Source of truth:** `_agent_docs/specifications/change-requests/2026-08-23-001-ui-enhancements.md` — expanded + world-reviewed; its §6 W-1…W-17 dispositions are **settled constraints** (not re-litigated by this plan).
**Base plans:** `_agent_docs/plans/2026-08-17-metronomad-v1/` (8/8 done) and `_agent_docs/plans/2026-08-22-address-v1-review/` (3/3 done). Unreferenced v1/review scenarios stay canonical there; this plan's `behavior-specs.md` is canonical for WF-\*/TD-\*/E2E-3.x/E2E-4.x rows only.
**Method:** BDD planning over an already-explored codebase (design memo D-A…D-M pinned in `context.md`). Key `file:line` anchors were **spot-verified against source on 2026-08-23** — four memo anchors were stale and corrected (see "Key Discoveries").

**How to use this plan:**
- This file is the entry point: overview, end state, scope, the **phase map** (single source of truth for progress), and the sequencing constraint.
- **`context.md`** — stable whole-plan detail: pinned decisions D-A…D-M (corrected), module interfaces, the `clicks20.wav` fixture contract, scenario ID scheme, KB-14…KB-17, the 13-item risk register, CR §4 limitations, cross-cutting constraints.
- **`behavior-specs.md`** — the authoritative, complete set **for this plan's scenarios only** (WF-P\*, WF-V\*, WF-I\*, TD-\*, TD-U\*, E2E-3.x, E2E-4.x). Phase files inline the scenarios they own.
- **`phase-N-*.md`** — self-contained: depends-on (by ID only), "Context to load", inlined owned scenarios, changes required with concrete code, success criteria (automated vs manual).

**Working a phase:** read the phase file first, then exactly its "Context to load" — nothing more. Phases 1–6 are test-first (RED → GREEN per the writing-plans TDD convention; the broken-page RED shape for new barrel names is pinned per phase — risk R-11). At phase close, run the handoff audit from the writing-plans skill (`references/phase-handoff.md`) before marking the phase done here.

## Overview

Two user-facing enhancements, both built purely on the `AudioBuffer` the app already owns (zero new dependencies; Howler and `playbackEngine.js` untouched):

1. **Waveform progress display** — replace the 8 px progress bar with a canvas waveform (full-song min/max peaks, 4096-bucket high-res pool) carrying the offset marker, a live playhead, and **direct-manipulation offset scrubbing** (pointer + full keyboard parity) that **replaces `#offsetScrubber`** (O-1 disposition). The ARIA roles split: canvas = `slider` (offset), `.progress-readout` = `progressbar` (song position; W-10).
2. **BPM detection** — pure-DSP tempo estimation (mono mixdown → silence trim → onset envelope → autocorrelation over 30–250 BPM with a 70–180 musical prior + confidence threshold) that **prefills the BPM field as a correctable suggestion** after Ready, gated by the `bpmTouchedThisFile` flag and draft/focus checks (W-16). Wrong-but-confident is worse than silent: low confidence → `null` → no prefill.

Both run as **async post-Ready tasks** from a single shared hook point in `onFileDropped`'s success branch, each carrying a D4-style generation/buffer-identity guard (W-14/W-15).

## Current State Analysis

- Baseline (post review-plan close, 2026-08-22): `node scripts/run-tests.cjs` → 158/158; `npx playwright test` → 23/23 (chromium; server on :8000, user-started — agents never start it).
- The progress UI is an 8 px bar: `.progress` container carries `role="progressbar"` + `aria-valuenow=songPosition` (`index.html:127-138`), `.progress-fill` binds the existing `progressPercent` computed (`createMetronomadApp.js:51-55`), the offset marker binds `offsetMarkerPercent` (`:57-61`).
- Offset scrubbing is a coarse 0.1 s-step native range (`#offsetScrubber`, `index.html:75-79`) plus the exact `m:ss.t` text field (`#offsetInput`). The commit law is `onOffsetScrub` (`createMetronomadMethods.js:170-178`) → `clampOffset` quantize-then-reclamp (`paramClamps.js:59-65`, T-35).
- The single file-load hook point exists: `onFileDropped`'s `result.ok` branch writes `fileName/duration/_buffer`, clamps offset, flips READY (`createMetronomadMethods.js:66-97`, ok-branch `:78-88`).
- The app-level `createBeatDots` RAF loop is the sole visual-clock owner (D9) and already throttles `vm.songPosition` to tenth-second changes (`createBeatDots.js:142-149`) — the playhead rides this for free.
- `BPM_MIN/BPM_MAX` (30/250) already live in `paramClamps.js:8-10` — the autocorrelation candidate span **imports** them, never re-declares.
- The click recipe (`clickBuffers.js:14-19` constants, `:33-55` envelope) is reused for the synthetic tempo-test trains and the new `clicks20.wav` fixture.

### Key Discoveries (planning pass, 2026-08-23 — memo corrections)

- **`sine3s.mp3` peak-bucket math was inverted in the CR/memo.** 3 s @ 44 100 Hz = 132 300 samples; at 4096 buckets that is **4096 buckets of ≈32 samples each**, not "≈32 effective buckets". The `bucketCount > sampleCount → effective = sampleCount` rule only bites for tiny buffers (pinned as WF-P1.4 with a 50-sample buffer).
- **The design memo's E2E-4.2 tempo expectation contradicted the CR.** Memo: "edit BPM → re-drop → **no** prefill". CR §2.5 (settled): the touched flag **resets on every successful load**, so a re-drop re-suggests. The plan follows the CR (E2E-4.2 asserts prefill *returns*).
- Stale memo anchors corrected: N-14 post-await guard is at `createMetronomadMethods.js:242` (memo said 226–228); `_restoreLastValid` is at `:117-133` (memo said 107–121); lifecycle `mounted()` is `:32-83` and `beforeUnmount()` is `:86-104` (memo said 26–60 / 62–83); the `songPosition` throttle is at `createBeatDots.js:142-149` (memo said 167–176); `renderClickBuffer` is at `clickBuffers.js:33-55` (memo said 40–63).
- All other memo anchors verified exact: `index.html` progress block `:124-138` / scrubber `:75-79` / BPM group `:59-71`; `Style.css` `.progress` block `:293-325`, only media query is `prefers-reduced-motion` at `:285`, `#app { max-width: 640px }` at `:7`; every `#offsetScrubber` E2E reference (`smoke.spec.cjs:30`, `keyboard.spec.cjs:51,71,110`, `playback.spec.cjs:194,255`, `UiHandlersTest.html:647-658`); `paramClamps.js:8-10,22-26,59-65`; `playbackEngine.js:90,154,250-252`; `scripts/run-tests.cjs:220-226` auto-discovery; `codecSupport.js:9-16` (PCM WAV is gate-safe in Chromium).

## Desired End State

- **After Phase 1+2 (pure modules):** `MyESModules/Analysis/` exists with `channelData.js` (shared channel walk + mono mixdown), `waveformPeaks.js` (`extractPeaks`/`poolPeaks`), `tempoDetection.js` (`detectTempo` → `{ bpm, confidence } | null`); all barrel-exported; pure, `Number.isFinite`-guarded, `sampleRate`-explicit (W-8); full unit batteries green.
- **After Phase 3 (view factory):** `createWaveformView(vm, base, callbacks)` — DI-pure per the `createBeatDots` convention — renders pooled min/max columns once per (peaks, size) pair, RAF-coalesced resize (W-5), DPR-scaled, `dispose()` releases GPU + listeners (memory-management.md).
- **After Phase 4 (waveform visible):** the progress block is the waveform: placeholder track until peaks land, canvas paints, playhead + offset marker + pre-offset dim overlays, `.progress-readout` carries the `progressbar` role (W-10), the post-load hook runs both async tasks under the generation guard, decode → Ready is never delayed by peak work. `#offsetScrubber` still coexists (additive phase).
- **After Phase 5 (scrub replaces scrubber):** pointer scrub (capture try/catch, `pointercancel` first-class, `touch-action: pan-y`, blur safety net) + full keyboard parity (←/→ 0.1 s, Shift 1 s, PageUp/Down 10 %, Home/End) all funnel through `onOffsetScrub`; canvas is the ARIA `slider`; **`#offsetScrubber` is removed** and every E2E reference is re-pointed.
- **After Phase 6 (tempo suggestion):** `clicks20.wav` fixture (reproducible generator script); detection prefills BPM + hint "Detected ~120 BPM" + V-07 announcement, gated by the touched-flag/focus/draft contract; negative fixtures stay silent.
- **After Phase 7 (docs + acceptance):** AGENTS.md + v1 `context.md` KB-14…KB-17 match the code; manual acceptance (VoiceOver/NVDA slider+progressbar pass, reduced-motion playhead stays, click pitch/downbeat exactness regression, low-end mobile) signed off; phase map closed.

### Key Discoveries:
- The precision path is frozen: `playbackEngine.js`, beat grid, count-in contract, D4 generation counter, D5, D9 — none are inputs to either feature.
- `progressPercent` becomes load-bearing for the playhead but its contract is **not mutated** (risk R-4): Phase 4 adds `playheadPercent` on top.
- The canvas can never be `:disabled` (risk R-1) — the locked-state E2E contract changes to `aria-disabled` + `pointer-events: none` + `tabindex="-1"`, which ripples into the smoke CONTROLS helper and `playback.spec.cjs:194,255`.
- Phase 4's canvas is a non-focusable `role="img"` (tabindex −1) so the untouched `keyboard.spec.cjs` exact-Tab-order test stays green; Phase 5 flips it to the focusable `slider` and updates the order in the same commit (risk R-2).

## What We're NOT Doing (CR §4 + world-review rejections)

- **No container-metadata BPM parsing** (ID3/Vorbis) — deferred with rationale (CR §2.2).
- **No live re-detection on offset change** (O-5b), no "Detect BPM" re-run button, no STFT/spectral-flux upgrade (v2 path if energy-only disappoints).
- **No waveform zoom/pan, per-channel display, or loop-point selection.** No **snapping the offset to detected beats** (separate CR).
- **No non-integer BPM, no time signatures.**
- **No coexistence of the native range with the canvas** (world-review W-9 suggestion rejected — redundant control; parity is restored deliberately).
- **No `requestIdleCallback`/chunked processing as a v1 default** (W-6 rejected as default; chunking is the documented fallback if low-end measurement shows a hitch).
- **No second RAF loop, no new visual clock** (D9) — the playhead derives from the existing 10 Hz `songPosition` throttle.
- **No changes** to `playbackEngine.js`, `howlerSetup.js`, the scheduler shape, or the 24-string user-facing inventory beyond the two new strings this plan owns ("Detected ~N BPM", "Detected tempo N BPM").
- **No new testability hooks** beyond `#waveformCanvas[data-loaded]` and `#waveformPlayhead[data-position-tenths]` (KB-6 minimal; no styling, no ARIA on hooks).

## Phase Map

| Phase | File | Priority | Status |
|-------|------|----------|--------|
| 1. Peaks + channel data (pure) | [phase-1-peaks-pure.md](phase-1-peaks-pure.md) | P0 | done 2026-08-24 (167/167 unit, 23/23 E2E; WF-P1.7 spike index corrected in place — out-of-range typo) |
| 2. Tempo detection (pure) | [phase-2-tempo-pure.md](phase-2-tempo-pure.md) | P1 | done 2026-08-24 (183/183 unit, 23/23 E2E; 14 ms measured worst case; TD-1.3 row + D-D lag formula corrected in place — see context.md D-D as-built deltas) |
| 3. Waveform view factory | [phase-3-waveform-view.md](phase-3-waveform-view.md) | P0 | done 2026-08-24 (198/198 unit, 23/23 E2E; as-built deltas: `resize(widthCss)` one-arg default height via `getHeightCss`, `getWindow` base param, init does the container-measured DPR sizing — see context.md D-F) |
| 4. Waveform wiring + playhead | [phase-4-waveform-wiring.md](phase-4-waveform-wiring.md) | P0 | done 2026-08-24 (207/207 unit, 27/27 E2E; as-built notes: `setPeaks` is called from `_runPeakExtraction`'s guarded write — the phase-3 handoff question resolved that way; E2E-3.1 uses in-page MutationObservers instead of the 5 ms poll for the two one-shot transition orderings — see sessions/2026-08-24-004; the B-04 (rev) template pin updated in place for the settled W-10 role move) |
| 5. Scrub + keyboard replaces `#offsetScrubber` | [phase-5-scrub-replaces-scrubber.md](phase-5-scrub-replaces-scrubber.md) | P0 | done 2026-08-25 (217/217 unit, 33/33 E2E; as-built deltas: the canvas lands LAST in the app's tab order — DOM order puts the progress block below the playback buttons, so the plan's "scrubber's slot" prose is superseded, canonical sequence re-pinned in keyboard.spec.cjs; `formatTime` exposed as a template method via the inline script for the aria-valuetext binding; zero-duration backstops in scrubStart/keydown per the WF-I2.10 pin (D-G's verbatim showed only the lock guard); E2E-3.10 asserts `#app input[type="range"]` count 0 so the O-1 grep pass is literally zero-hit — see sessions/2026-08-25-005) |
| 6. Tempo suggestion integration | [phase-6-tempo-integration.md](phase-6-tempo-integration.md) | P1 | done 2026-08-25 (228/228 unit, 37/37 E2E; fixture `clicks20.wav` 1 764 044 bytes + reproducible `scripts/make-clicks20-wav.cjs`; as-built deltas: E2E-4.4 re-pinned in place — a live mid-draft never survives a load trigger (drop focus semantics + decoding-disable blur-commit, RD-1), so the row pins the reachable literal-step behavior and the W-16 no-clobber guarantee stays P0-unit (TD-U1.4/5); the ok-branch clears `tempoSuggestion` (per-file silence — the manual criterion “drop a sine → no hint” implies it; the plan never stated it); the prefill clears `bpmClamped` — the D-H “touched flag prevents hint coexistence” rationale was wrong and is corrected in context.md; TD-U1.1/1.8/1.9 pin the two-task yield queue, so WF-I1.2/1.4 flush counts updated — see sessions/2026-08-25-006) |
| 7. Docs + acceptance | [phase-7-docs-acceptance.md](phase-7-docs-acceptance.md) | P2 | done 2026-08-25 (228/228 unit, 37/37 E2E re-verified; integrity check OK — 63 distinct IDs; AGENTS.md + v1 KB-14…KB-17 aligned to as-built; one plan-internal conflict resolved — the Directory prose instruction to name the replaced scrubber yields to the phase's own zero-hit `rg "offsetScrubber"` gate, so the docs phrase the replacement token-free ("zero `input[type=\"range\"]` in the app"); final whole-change-set world-review: zero action items, UX-6 double-announcement stays on the manual SR checklist; manual acceptance checklist pending user sign-off) |

**Sequencing constraint (D-M):** Phase 4 defines `_schedulePostLoadTasks` in its **two-task shape from day one** (peaks task live; tempo task body a guarded no-op until Phase 6). Phase 6 then *fills in* the tempo task — it never refactors Phase 4's hook. This makes the CR §3 "one shared hook point" structurally true, not aspirational.

**Integrity check (run before marking the plan ready / at plan close):**

```bash
bash ~/workspace/agent-ollama-projects/Experiments/pi-development-kit/.pi/skills/writing-plans/script/plan-integrity-check.sh _agent_docs/plans/2026-08-23-cr-001-ui-enhancements \
  --ids 'WF-[PIV]1\.[0-9]+|TD-U1\.[0-9]+|TD-1\.[0-9]+|E2E-[34]\.[0-9]+'
```

(the script's default `R-*/RD-*` regex doesn't cover this plan's ID families; legacy v1 IDs like T-35/U-10/V-07 are referenced for orientation but stay canonical in the v1/review plans and are deliberately out of the regex).
