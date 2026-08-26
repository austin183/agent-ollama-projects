# Metronomad v1 Implementation Plan

**Date:** 2026-08-17
**Spec:** `_agent_docs/specifications/metronomad-v1-specification.md`
**Research:** `_agent_docs/research/howlerjs-research.md` (Howler.js v2.2.3, verified empirically)
**Method:** BDD plan produced via `plan-bdd` workflow (world-review + planner delegation)

**How to use this plan:**
- This file is the entry point: overview, end state, scope, and the **phase map** below (single source of truth for progress).
- **`context.md`** — shared, whole-plan detail: design decisions (D1–D11), file layout & module interfaces, testing strategy, performance, known behaviors (KB-1–KB-9), references. Read the sections a phase's "Context to load" list names.
- **`behavior-specs.md`** — the full BDD scenario tables (U/F/P/H/B/V/T/E2E IDs). The contract for TDD: each scenario maps to a failing test first.
- **`phase-N-*.md`** — one self-contained file per phase: what to build, the inlined scenarios it owns, and success criteria.

**Working a phase:** read the phase file first, then exactly the "Context to load" sections it lists — nothing more. Mark the phase complete in the phase map below when its success criteria are met.

## Overview

Metronomad is a single-page static tool for musicians: drop a local audio file → set BPM (30–250, default 120), an offset (mm:ss.t, scrubber + direct entry), and count-in length (1–16, default 4) → **Play** runs a metronome count-in on the Web Audio clock, then starts the song **sample-accurately at the offset on the downbeat** via `AudioBufferSourceNode.start(when, offset)`.

Architecture is **Option B** from the research doc: Howler.js (CDN) provides only AudioContext setup, `Howler.masterGain`, `Howler.codecs()`, and mobile auto-unlock (`Howler.autoSuspend = false` — Pitfall 1). The precision-critical path is raw Web Audio: we decode the dropped `File` ourselves and schedule count-in clicks AND the song start on the same context into `Howler.masterGain`. No build step, Vue 3 Options API via CDN, ES modules with named exports — the repo's standard pattern.

## Current State Analysis

- `Metronomad/` is empty except `_agent_docs/` and `.pi/skills/building-web-apps` (symlink to the canonical CollageMaker skill).
- Howler research is complete and empirically verified: `start(when, offset)` is sample-accurate (0.41 ms measured drift); Howler's own `play()` cannot schedule a future start; blob URLs need `format`; `autoSuspend` kills custom playback; mp3 decodes in all three major browsers.
- CollageMaker is the reference implementation: Vue 3 CDN factory decomposition, `MyESModules/` + `MyComponents/` (Mocha+Chai in-browser unit tests) + `test/e2e/` (Playwright, chromium only, `baseURL :8000`, workers 1) + `scripts/run-tests.js` (Node+Playwright driver that opens Mocha test pages over HTTP).
- Root `node_modules` already has `@playwright/test` + chromium. Root `index.html` hosts project cards (`project-card` + `card-icon`/`card-title`/`card-description`/`launch-button`).
- Server: user runs `start-server.sh` → `http://localhost:8000/Metronomad/index.html` (repo rule: agents never start it).

## Desired End State

A musician can, at `http://localhost:8000/Metronomad/index.html`: load any Howler-decodable local audio file, set BPM/offset/count-in, and press Play to get a rhythmically exact count-in into the song at the offset — with Stop/Restart, offset preview, beat dots, progress with offset marker, keyboard + screen-reader access, and friendly errors. Verified by 34 pure-function unit scenarios, ~30 component/unit scenarios, 12 E2E scenarios, and a manual acceptance checklist.

### Key Discoveries:
- `AudioBufferSourceNode.start(when, offset)` on the shared context is sample-accurate; Howler's `play()` is not scheduleable (research §3).
- `Howler.autoSuspend` must be `false` — its 30 s timer only sees Howler's own sounds (research Pitfall 1).
- `Howler.ctx` is null until lazy setup — touch `Howler.volume()` first (research Pitfall 2).
- Decoded `AudioBuffer` is float32: 44.1 kHz stereo ≈ **21.1 MB/min** (research's 10.6 MB/min figure was 16-bit PCM) — drives the 30-minute guard (D3).
- Chromium supports every common codec, so the codec-reject path is unit-tested (F-02) + manually verified on Safari; it cannot be triggered with a real file in chromium E2E.
- Beat phase computed as a **pure function of the audio clock** makes hidden-tab RAF pausing (Safari) harmless — no accumulated phase to drift (D9).

## What We're NOT Doing

- No BPM/key detection or any audio analysis (spec §12).
- No persistence between visits, no queue/multi-song, no looping, no metronome-only mode.
- No time signatures other than 4/4 (accent fixed to every 4th beat).
- No volume sliders, custom click sounds, or click/song muting.
- No minimum lead-time floor at high BPM (D1 — spec's timing law wins).
- No pre-decode file-size confirmation dialog (post-decode duration guard instead, D3).
- No Firefox/Safari E2E projects (chromium only, matching CollageMaker); cross-browser checks are manual + a flagged follow-up.
- No live tempo/offset changes mid-sequence (parameters locked, spec §6).
- No mobile-first layout polish (basic responsiveness only, spec §12).

## Phase Map

| Phase | File | Priority | Status |
|-------|------|----------|--------|
| 1. Scaffold | [phase-1-scaffold.md](phase-1-scaffold.md) | P1 | ✅ done |
| 2. Pure Functions | [phase-2-pure-functions.md](phase-2-pure-functions.md) | P0 | ✅ done |
| 3. File Loading | [phase-3-file-loading.md](phase-3-file-loading.md) | P0 | ✅ done |
| 4. PlaybackEngine | [phase-4-playback-engine.md](phase-4-playback-engine.md) | P0 | ✅ done |
| 5. UI Integration (Play/Stop/Restart/Preview) | [phase-5-ui-integration.md](phase-5-ui-integration.md) | P0 | ✅ done |
| 6. Beat Dots, Progress, Clock Hygiene | [phase-6-beat-dots-progress.md](phase-6-beat-dots-progress.md) | P1 | ✅ done |
| 7. E2E Suite | [phase-7-e2e-suite.md](phase-7-e2e-suite.md) | P0/P1 | ✅ done |
| 8. Docs, Site Link, Final Acceptance | [phase-8-docs-acceptance.md](phase-8-docs-acceptance.md) | P1 | ✅ done (user-confirmed 13-item checklist; 127 unit + 21 E2E green; world-review clean; commit pending build-quick-work) |

---

*Original single-file plan archived at `../archive/2026-08-17-metronomad-v1-implementation-plan.md`.*
