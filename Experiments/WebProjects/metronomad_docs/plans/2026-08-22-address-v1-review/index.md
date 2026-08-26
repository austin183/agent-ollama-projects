# Metronomad v1 Review Findings — Implementation Plan

**Date:** 2026-08-22
**Source:** `_agent_docs/reviews/2026-08-22-metronomad-v1-code-review.md` (1 CRITICAL, 9 IMPORTANT, 33 nits)
**Base plan:** `_agent_docs/plans/2026-08-17-metronomad-v1/` (all 8 phases done — its `behavior-specs.md` remains the canonical full scenario set for the v1 behaviors this plan does not modify)
**Method:** Light BDD planning — the review carries locations, fixes, and test expectations; this plan scopes, sequences, and pins regression scenarios. No re-research.

**How to use this plan:**
- This file is the entry point: overview, end state, scope, the **phase map** (single source of truth for progress), and the open decisions.
- **`context.md`** — design decisions RD-1…RD-6 (fix contracts), interface shapes, testing strategy, cross-cutting constraints.
- **`behavior-specs.md`** — the authoritative scenario rows *for this plan only*: new IDs (R-*) and the amended v1 rows (U-11, U-13, U-09, P-12, P-13, B-05). Unreferenced v1 scenarios stay canonical in the v1 plan.
- **`phase-N-*.md`** — self-contained: what to change, inlined scenarios owned, success criteria.

**Working a phase:** read the phase file first, then exactly its "Context to load" — nothing more. At phase close, run the handoff audit from the writing-plans skill (`references/phase-handoff.md`) before marking the phase done here.

## Overview

The v1 code review found one CRITICAL user-facing defect (BPM/count-in typing destroyed by clamp-on-keystroke), nine IMPORTANT issues (file-load lock/race gaps, an engine boundary guard, a U-09 contract deviation, a dead parallel visual clock, inverted teardown ownership, an DI asymmetry, an unshared constant, and a test runner that can report green with zero tests), and 33 nits. The core precision architecture (D4 generation counter, D5 single sample-accurate start, D9 pure-function beat phase) is untouched.

This plan closes the shippable gate (Phase 1), then the design-hygiene batch (Phase 2), and holds the curated nit backlog (Phase 3, scoped on pickup).

## Current State Analysis

- Baseline (review-verified 2026-08-22, spot-checked during planning): `node scripts/run-tests.cjs` → 127/127; `npx playwright test` → 21/21 (chromium, server on :8000 — user-started, agents never start it).
- The defects cluster in two places the review names precisely: **the file-loading path** (lock check lives in `onDrop` not `onFileDropped`; no single-flight guard) and **input handling unit-tested single-shot but never per-keystroke** (C-1's live repro: typing `120` leaves `2500` in the field with 250 in the model).
- All 10 findings to be fixed in Phases 1–2 were re-verified against source during this planning pass (2026-08-22): `index.html:63-66` (`:value`+`@input` on BPM/count-in), `onDrop` vs `onFileDropped` lock asymmetry, `clampOffset` quantize-after-clamp (`paramClamps.js`), engine `startVisualClock`/`stopVisualClock`/`_rafTick` with zero app callers, `createBeatDots.stopAll` → `engine.dispose()`, hardcoded browser globals in `createBeatDots`, and `scripts/run-tests.cjs`'s silent-0-tests fallback.
- **Ownership clusters** drive sequencing: (a) the input handlers (C-1 + N-16 + N-20), (b) `onFileDropped` (I-1 + I-2 + N-23's re-clamp test), (c) the engine/beatDots teardown surface (I-5 + I-6 + I-7 + N-17 — one coherent refactor, never split across phases).

## Desired End State

- **After Phase 1 (v1 shippable gate):** BPM/count-in are typeable per-keystroke (commit-on-Enter/blur, matching the offset field); file loads are single-flight and lock-checked at one choke point; the engine rejects `offset >= buffer.duration`; user Stop during preview announces "Preview stopped"; the runner fails on 0 tests. Full unit + E2E suites green with new regression tests pinning every fix.
- **After Phase 2 (design hygiene):** the app's `createBeatDots` is the sole owner of the visual clock; `beforeUnmount` owns all teardown ordering; `createBeatDots` is fully DI; `BEATS_PER_BAR` is the single source for "4"; AGENTS.md and the v1 behavior-specs match the code.
- **After Phase 3 (backlog, scoped on pickup):** selected nits closed or explicitly deferred with KB entries; every KB-10/KB-11-class decision recorded in the v1 plan's `context.md`.

### Key Discoveries (planning pass):
- The review is accurate line-for-line; no findings were stale at planning time.
- KB-10 (offline deferral, N-28) **already exists** in the v1 plan's `context.md` — N-28 requires no further work; N-2's KB entry lands there as **KB-11** in Phase 3.
- N-16 (extract `_restoreLastValid`) and N-20 (count-in clamp hint) touch the exact lines C-1 rewrites → folded into Phase 1, not the backlog.
- N-22 (U-21 filename ellipsis E2E) and N-23's 1-line VM test are cheap add-ons to Phase 1's existing test files.

## What We're NOT Doing

- **No offline guarantee / service worker / vendoring** (N-28 — deferred; KB-10 already recorded).
- **No mobile touch cluster** (N-29…N-31) unless the Phase 3 scoping session elects it.
- **No time signatures, looping, or scheduler redesign** — the core timing architecture survived the review and is frozen.
- **No concurrent-decode support** — I-2 is fixed by rejection, not an in-flight counter.
- **No new testability hooks** beyond the E2E keystroke scenario's existing ones (KB-6 hooks stay minimal; the BPM commit state is asserted via the field + behavior, see `behavior-specs.md` E2E-R-C1.1 note).
- **No spec changes beyond** the C-1 commit-pattern note and N-21's stale-value corrections (U-11 wording updates in v1 behavior-specs land with Phase 1).

## Open Decisions (user sign-off before execution)

**All confirmed by user, 2026-08-22 — execution may start from Phase 1.**

| # | Decision | Confirmed |
|---|----------|-----------|
| OD-1 | C-1 fix pattern: commit-on-Enter/blur with local draft text (offset-field pattern); steppers remain the live path and sync the draft | **Yes** |
| OD-2 | Phase 3 scope selection | Review-order default: code nits with test impact + docs/KB items (N-24 scheduled at scoping, 2026-08-22); **defer** N-11 (behavior change), N-29…N-31 (mobile cluster) |
| OD-3 | N-11 — start the visual loop during Preview too | **No** (spec §8 says "during playback"; leave as-is) |

## Phase Map

| Phase | File | Priority | Status |
|-------|------|----------|--------|
| 1. Shippable Gate — C-1 + I-1…I-4 + I-9 (+ N-16, N-20, N-22, N-23) | [phase-1-shippable-gate.md](phase-1-shippable-gate.md) | P0 | ✅ done (2026-08-22; unit 142/142, E2E 23/23) |
| 2. Design Hygiene — I-5…I-8 + N-17, N-18, N-21 | [phase-2-design-hygiene.md](phase-2-design-hygiene.md) | P1 | ✅ done (2026-08-22; unit 145/145, E2E 23/23) |
| 3. Nit Backlog — curated (scoped on pickup) | [phase-3-nit-backlog.md](phase-3-nit-backlog.md) | P2 | ✅ done (2026-08-22; 21/21 items; unit 158/158, E2E 23/23) |

### Phase 3 items (scoped 2026-08-22)

Scenario rows for all scheduled items are in [behavior-specs.md §7](behavior-specs.md#7-phase-3--nit-backlog-scoped-2026-08-22). Deferred (OD-2 defaults): N-11 (behavior change), N-29…N-31 (mobile cluster), N-28 upgrade path.

| Item | File | Status |
|------|------|--------|
| N-1 scheduler clear at PLAYING | [phase-3-N1-scheduler-clear.md](phase-3-N1-scheduler-clear.md) | ✅ |
| N-2 KB-11 background throttling (docs) | [phase-3-N2-kb-background-throttle.md](phase-3-N2-kb-background-throttle.md) | ✅ |
| N-3 fileLoader dead URL lifecycle | [phase-3-N3-fileloader-url-dead-code.md](phase-3-N3-fileloader-url-dead-code.md) | ✅ |
| N-4 frozen schedule view | [phase-3-N4-seq-frozen-view.md](phase-3-N4-seq-frozen-view.md) | ✅ |
| N-5 tooLong message interpolation | [phase-3-N5-toolong-message.md](phase-3-N5-toolong-message.md) | ✅ |
| N-6 `_finish(event)` extract | [phase-3-N6-finish-extract.md](phase-3-N6-finish-extract.md) | ✅ |
| N-7 ENGINE_EVENTS export | [phase-3-N7-engine-events.md](phase-3-N7-engine-events.md) | ✅ |
| N-8 errorMessage clearing | [phase-3-N8-error-clearing.md](phase-3-N8-error-clearing.md) | ✅ |
| N-9 `--beat-interval` cache | [phase-3-N9-beat-interval-cache.md](phase-3-N9-beat-interval-cache.md) | ✅ |
| N-10 progressbar static label + valuetext | [phase-3-N10-progressbar-aria.md](phase-3-N10-progressbar-aria.md) | ✅ |
| N-12 "Count-in restarted" announcement | [phase-3-N12-restart-announcement.md](phase-3-N12-restart-announcement.md) | ✅ |
| N-13 dragover flicker | [phase-3-N13-dragover-flicker.md](phase-3-N13-dragover-flicker.md) | ✅ |
| N-14 resume post-await guard | [phase-3-N14-resume-unmount-guard.md](phase-3-N14-resume-unmount-guard.md) | ✅ |
| N-15 scrubber `:tabindex` drop | [phase-3-N15-scrubber-tabindex.md](phase-3-N15-scrubber-tabindex.md) | ✅ |
| N-19 offset format story | [phase-3-N19-offset-format.md](phase-3-N19-offset-format.md) | ✅ |
| N-24 U-18 scoping note (docs) | [phase-3-N24-u18-scoping-note.md](phase-3-N24-u18-scoping-note.md) | ✅ |
| N-25 resume-timeout constant | [phase-3-N25-resume-constant.md](phase-3-N25-resume-constant.md) | ✅ |
| N-26 E2E-1.3 grid-law bound | [phase-3-N26-e2e13-bound.md](phase-3-N26-e2e13-bound.md) | ✅ |
| N-27 refocus disabled-branch test | [phase-3-N27-refocus-disabled.md](phase-3-N27-refocus-disabled.md) | ✅ |
| N-32 KB-12 AT coalescing (docs) | [phase-3-N32-kb-at-coalescing.md](phase-3-N32-kb-at-coalescing.md) | ✅ |
| N-33 KB-13 background audio (docs) | [phase-3-N33-kb-background-audio.md](phase-3-N33-kb-background-audio.md) | ✅ |
